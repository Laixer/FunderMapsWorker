import { log } from "../lib/log.ts";
import { sql } from "../db.ts";
import * as pdf from "../providers/pdf.ts";
import * as s3 from "../providers/s3.ts";
import { extractFields, EXTRACT_FIELDS } from "../providers/vision.ts";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

/**
 * Score the text-lane extraction against what a human typed.
 *
 * The one place we hold ground truth for every field the prompt asks for --
 * the new levels included -- is a foundation_research inquiry with its PDF in
 * inquiry-report/ and its report.inquiry_sample rows. This runs the live
 * `extractFields` on N of those and counts, per field:
 *
 *   hit           proposed, and matches a sample on the inquiry
 *   wrong         proposed, the humans entered something, and it differs
 *   missed        the humans entered it, the model proposed nothing
 *   unverifiable  proposed, no human ever entered this field -- could be a
 *                 recovered value or a fabrication; a person has to look
 *
 * The selection is deterministic (ordered by md5 of the id) so two runs on
 * two prompts compare the same documents. Nothing is written to the database.
 *
 *   bun run src/commands/bench-extract.ts [--n 50] [--out bench.csv]
 */

type Truth = Record<string, Set<string>>;

const LEGACY_TERM: Record<string, string> = { term05: "term5", term510: "term10", term1020: "term20" };

/** Foundation type families, so wood_rotterdam vs wood counts as a family hit, not a miss. */
function family(t: string): string {
  if (t.startsWith("wood")) return "wood";
  if (t.startsWith("no_pile")) return "no_pile";
  return t;
}

function matches(field: string, proposed: string, truths: Set<string>): "exact" | "family" | "no" {
  if (truths.has(proposed)) return "exact";
  switch (field) {
    case "foundation_type":
      return [...truths].some((t) => family(t) === family(proposed)) ? "family" : "no";
    case "enforcement_term":
      return [...truths].some((t) => (LEGACY_TERM[t] ?? t) === proposed) ? "exact" : "no";
    case "groundwater_level":
    case "wood_level":
    case "pile_head_level":
    case "pile_tip_level":
    case "concrete_charger_length":
    case "pile_distance_length":
    case "mason_level":
    case "foundation_depth":
    case "groundlevel": {
      const p = parseFloat(proposed.replace(",", "."));
      return [...truths].some((t) => Math.abs(parseFloat(t) - p) <= 0.1) ? "exact" : "no";
    }
    case "pile_diameter_top":
    case "pile_diameter_bottom":
    case "wood_penetration_depth": {
      const p = parseFloat(proposed.replace(",", "."));
      return [...truths].some((t) => Math.abs(parseFloat(t) - p) <= 10) ? "exact" : "no";
    }
    case "cpt":
      return [...truths].some((t) => t.toLowerCase().replace(/\s+/g, "") === proposed.toLowerCase().replace(/\s+/g, "")) ? "exact" : "no";
    case "built_year":
      return [...truths].some((t) => Math.abs(parseInt(t) - parseInt(proposed)) <= 1) ? "exact" : "no";
    default:
      return "no";
  }
}

const argv = process.argv.slice(2);
const arg = (k: string) => { const i = argv.indexOf(`--${k}`); return i > -1 ? argv[i + 1] : undefined; };
const N = Number(arg("n") ?? 50);
const OUT = arg("out") ?? `bench-extract-${new Date().toISOString().slice(0, 10)}.csv`;

log.banner("Data Ops — bench extract");

const inquiries = await sql<{ id: number; document_file: string }[]>`
  SELECT i.id, i.document_file
  FROM report.inquiry i
  WHERE i.type = 'foundation_research' AND i.delete_date IS NULL
    AND i.document_file ~ '\\.pdf$' AND i.document_date >= '2015-01-01'
    AND EXISTS (SELECT 1 FROM report.inquiry_sample s WHERE s.inquiry_id = i.id AND s.foundation_type IS NOT NULL)
    AND (SELECT count(*) FROM report.inquiry_sample s WHERE s.inquiry_id = i.id) BETWEEN 1 AND 6
    AND (SELECT count(s.wood_level) + count(s.pile_head_level) + count(s.concrete_charger_length)
         FROM report.inquiry_sample s WHERE s.inquiry_id = i.id) > 0
  ORDER BY md5(i.id::text)
  LIMIT ${N}`;

const work = await mkdtemp(join(tmpdir(), "fm-bench-"));
const rows: string[] = ["inquiry,field,proposed,truth,verdict,confidence,evidence"];
const tally: Record<string, { hit: number; family: number; wrong: number; missed: number; unverifiable: number; truth: number }> = {};
for (const f of EXTRACT_FIELDS) tally[f] = { hit: 0, family: 0, wrong: 0, missed: 0, unverifiable: 0, truth: 0 };
const csvq = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""').replace(/\s+/g, " ").slice(0, 200)}"`;

let done = 0, skipped = 0;
for (const inq of inquiries) {
  const samples = await sql<Record<string, unknown>[]>`
    SELECT foundation_type::text, extract(year FROM built_year)::int::text AS built_year,
           overall_quality::text AS foundation_quality, recovery_advised::text,
           enforcement_term::text, groundwater_level_temp::text AS groundwater_level,
           wood_level::text, pile_head_level::text, pile_tip_level::text, concrete_charger_length::text,
           pile_diameter_top::text, pile_diameter_bottom::text, pile_distance_length::text,
           wood_type::text, wood_penetration_depth::text, wood_encroachment::text,
           mason_level::text, foundation_depth::text, groundlevel::text, cpt::text,
           damage_cause::text, damage_characteristics::text
    FROM report.inquiry_sample WHERE inquiry_id = ${inq.id}`;
  const truth: Truth = {};
  for (const f of EXTRACT_FIELDS) {
    truth[f] = new Set(samples.map((s) => s[f]).filter((v): v is string => v != null && v !== ""));
    if (truth[f].size) tally[f]!.truth++;
  }

  const local = join(work, inq.document_file);
  try {
    await s3.downloadFile(local, `inquiry-report/${inq.document_file}`);
    if ((await pdf.fileKind(local)) !== "pdf") throw new Error("not a pdf");
    const text = await pdf.documentText(local, 1);
    if (text.trim().length < 500) throw new Error("scanned, no text layer");
    const fields = await extractFields(text.slice(0, 250_000));
    const proposed = new Map(fields.map((f) => [f.field, f]));
    for (const f of EXTRACT_FIELDS) {
      const p = proposed.get(f);
      const t = truth[f]!;
      let verdict: string;
      if (!p && !t.size) continue;
      if (!p) verdict = "missed";
      else if (!t.size) verdict = "unverifiable";
      else { const m = matches(f, p.value, t); verdict = m === "no" ? "wrong" : m === "family" ? "family" : "hit"; }
      (tally[f] as Record<string, number>)[verdict]!++;
      rows.push([inq.id, f, csvq(p?.value), csvq([...t].join("|")), verdict, p?.confidence ?? "", csvq(p?.evidence)].join(","));
    }
    done++;
    log.step(`#${inq.id} ${fields.length} proposed`);
  } catch (e) {
    skipped++;
    log.warn(`#${inq.id} skipped: ${String(e).slice(0, 80)}`);
  } finally {
    await rm(local, { force: true }).catch(() => {});
  }
}
await rm(work, { recursive: true, force: true }).catch(() => {});
await writeFile(OUT, rows.join("\n") + "\n");

console.log(`\ndocuments: ${done} scored, ${skipped} skipped\n`);
console.log("field                     truth  hit  fam  wrong  missed  unverif   precision  recall");
for (const f of EXTRACT_FIELDS) {
  const t = tally[f]!;
  const proposedOnTruth = t.hit + t.family + t.wrong;
  const precision = proposedOnTruth ? ((t.hit + t.family) / proposedOnTruth) : NaN;
  const recall = t.truth ? ((t.hit + t.family) / t.truth) : NaN;
  const pct = (x: number) => (Number.isNaN(x) ? "   -" : `${Math.round(x * 100)}%`.padStart(4));
  console.log(`${f.padEnd(25)}${String(t.truth).padStart(6)}${String(t.hit).padStart(5)}${String(t.family).padStart(5)}${String(t.wrong).padStart(7)}${String(t.missed).padStart(8)}${String(t.unverifiable).padStart(9)}   ${pct(precision).padStart(9)}  ${pct(recall)}`);
}
console.log(`\nper-field rows: ${OUT}`);
await sql.end({ timeout: 5 }).catch(() => {});
process.exit(0);
