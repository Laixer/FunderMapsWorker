import { log } from "../lib/log.ts";
import { sql } from "../db.ts";
import * as pdf from "../providers/pdf.ts";
import * as s3 from "../providers/s3.ts";
import { extractFields, EXTRACT_FIELDS, ADDRESS_FIELDS } from "../providers/vision.ts";
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

/**
 * In a Rotterdam wood foundation the masonry sits directly on the langshout, so
 * "onderkant metselwerk" and "bovenkant hout" are one measurement that invoerders
 * entered under either name (2026-08-29 run 2: 17 of 18 mason_level misses were
 * the model's wood_level to the centimetre). Truth for one counts for the other.
 */
const TRUTH_SYNONYMS: Record<string, string[]> = {
  wood_level: ["mason_level"],
};

function matches(field: string, proposed: string, truths: Set<string>): "exact" | "family" | "no" {
  if (truths.has(proposed)) return "exact";
  if (field.startsWith("crack_")) return truths.has("nil") && proposed === "none" ? "exact" : "no";
  if (field === "skewed_parallel" || field === "skewed_perpendicular" || field === "settlement_speed") {
    const p = parseFloat(proposed.replace(",", "."));
    return [...truths].some((t) => Math.abs(parseFloat(t) - p) <= Math.max(1, Math.abs(parseFloat(t)) * 0.1)) ? "exact" : "no";
  }
  if (field === "threshold_front_level" || field === "threshold_back_level") {
    const p = parseFloat(proposed.replace(",", "."));
    return [...truths].some((t) => Math.abs(parseFloat(t) - p) <= 0.1) ? "exact" : "no";
  }
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
for (const f of ADDRESS_FIELDS) tally[`@${f}`] = { hit: 0, family: 0, wrong: 0, missed: 0, unverifiable: 0, truth: 0 };
let addrRowsProposed = 0, addrRowsResolved = 0, addrRowsTruth = 0;

/** "Adamshofstraat 93 A" -> "adamshofstraat|93a". Good enough to pair report rows with samples. */
function addrKey(street: string, number: string): string {
  return `${street.toLowerCase().replace(/[^a-z]/g, "")}|${number.toLowerCase().replace(/[^a-z0-9]/g, "")}`;
}
function parseAddr(text: string): string | null {
  const m = text.trim().match(/^(.+?)\s+(\d+\s*[a-zA-Z]?(?:[-/]\d+)?)\s*,?/);
  return m ? addrKey(m[1]!, m[2]!.replace(/\s+/g, "")) : null;
}
const csvq = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""').replace(/\s+/g, " ").slice(0, 200)}"`;

let done = 0, skipped = 0;
for (const inq of inquiries) {
  const samples = await sql<Record<string, unknown>[]>`
    SELECT ga.street AS _street, ga.building_number AS _number,
           s.crack_facade_front_type::text, s.crack_facade_back_type::text, s.crack_indoor_type::text,
           s.skewed_parallel::text, s.skewed_perpendicular::text,
           s.threshold_front_level::text, s.threshold_back_level::text, s.settlement_speed::text,
           foundation_type::text, extract(year FROM built_year)::int::text AS built_year,
           overall_quality::text AS foundation_quality, recovery_advised::text,
           enforcement_term::text, groundwater_level_temp::text AS groundwater_level,
           wood_level::text, pile_head_level::text, pile_tip_level::text, concrete_charger_length::text,
           pile_diameter_top::text, pile_diameter_bottom::text, pile_distance_length::text,
           wood_type::text, wood_penetration_depth::text, wood_encroachment::text,
           mason_level::text AS mason_level, foundation_depth::text, groundlevel::text,
           damage_cause::text, damage_characteristics::text
    FROM report.inquiry_sample s LEFT JOIN geocoder.address ga ON ga.id = s.address
    WHERE s.inquiry_id = ${inq.id}`;
  const truth: Truth = {};
  for (const f of EXTRACT_FIELDS) {
    const cols = [f, ...(TRUTH_SYNONYMS[f] ?? [])];
    truth[f] = new Set(samples.flatMap((s) => cols.map((c) => s[c])).filter((v): v is string => v != null && v !== ""));
    if (truth[f].size) tally[f]!.truth++;
  }

  const local = join(work, inq.document_file);
  try {
    await s3.downloadFile(local, `inquiry-report/${inq.document_file}`);
    if ((await pdf.fileKind(local)) !== "pdf") throw new Error("not a pdf");
    const text = await pdf.documentText(local, 1);
    if (text.trim().length < 500) throw new Error("scanned, no text layer");
    const fields = await extractFields(text.slice(0, 250_000));
    // A field may carry several candidates (damage_cause, damage_characteristics
    // return a list); it counts as a hit when any candidate matches the truth.
    const proposed = new Map<string, typeof fields>();
    for (const f of fields) proposed.set(f.field, [...(proposed.get(f.field) ?? []), f]);
    for (const f of EXTRACT_FIELDS) {
      const ps = proposed.get(f) ?? [];
      const t = truth[f]!;
      let verdict: string;
      if (!ps.length && !t.size) continue;
      if (!ps.length) verdict = "missed";
      else if (!t.size) verdict = "unverifiable";
      else {
        const ms = ps.map((p) => matches(f, p.value, t));
        verdict = ms.includes("exact") ? "hit" : ms.includes("family") ? "family" : "wrong";
      }
      (tally[f] as Record<string, number>)[verdict]!++;
      const p = ps[0];
      rows.push([inq.id, f, csvq(ps.map((x) => x.value).join("|")), csvq([...t].join("|")), verdict, p?.confidence ?? "", csvq(p?.evidence)].join(","));
    }
    // ---- per-address rows -------------------------------------------------
    const truthByAddr = new Map<string, Record<string, unknown>>();
    for (const smp of samples) if (smp["_street"]) truthByAddr.set(addrKey(String(smp["_street"]), String(smp["_number"])), smp);
    addrRowsTruth += truthByAddr.size;
    const perAddr = fields.filter((f) => f.address);
    const byAddr = new Map<string, typeof perAddr>();
    for (const f of perAddr) byAddr.set(f.address!, [...(byAddr.get(f.address!) ?? []), f]);
    addrRowsProposed += byAddr.size;
    // Exact first; then the same street + house number ignoring the BAG unit
    // letter ("93" vs "93A": the report addresses the pand, the sample a unit).
    const bareKey = (k: string) => k.replace(/\|(\d+).*$/, "|$1");
    const truthByBare = new Map<string, Record<string, unknown>>();
    for (const [k, v] of truthByAddr) if (!truthByBare.has(bareKey(k))) truthByBare.set(bareKey(k), v);
    for (const [addrText, fs] of byAddr) {
      const key = parseAddr(addrText);
      const smp = key ? (truthByAddr.get(key) ?? truthByBare.get(bareKey(key))) : undefined;
      if (smp) addrRowsResolved++;
      for (const af of ADDRESS_FIELDS) {
        const ps = fs.filter((f) => f.field === af);
        const tv = smp?.[af];
        const t = new Set(tv != null && tv !== "" ? [String(tv)] : []);
        if (!ps.length && !t.size) continue;
        let verdict: string;
        if (!ps.length) verdict = "missed";
        else if (!smp || !t.size) verdict = "unverifiable";
        else { const ms = ps.map((p) => matches(af, p.value, t)); verdict = ms.includes("exact") ? "hit" : ms.includes("family") ? "family" : "wrong"; }
        (tally[`@${af}`] as Record<string, number>)[verdict]!++;
        rows.push([inq.id, `@${af} ${addrText}`, csvq(ps.map((x) => x.value).join("|")), csvq([...t].join("|")), verdict, ps[0]?.confidence ?? "", csvq(ps[0]?.evidence)].join(","));
      }
    }
    // truth rows the model never produced an address for
    for (const [key, smp] of truthByAddr) {
      if ([...byAddr.keys()].some((a) => { const k = parseAddr(a); return k === key || (k && bareKey(k) === bareKey(key)); })) continue;
      for (const af of ADDRESS_FIELDS) { const tv = smp[af]; if (tv != null && tv !== "") tally[`@${af}`]!.missed++; }
    }
    for (const af of ADDRESS_FIELDS) { if ([...truthByAddr.values()].some((smp) => smp[af] != null && smp[af] !== "")) tally[`@${af}`]!.truth++; }

    done++;
    log.step(`#${inq.id} ${fields.length - perAddr.length} proposed, ${byAddr.size} address rows`);
  } catch (e) {
    skipped++;
    log.warn(`#${inq.id} skipped: ${String(e).slice(0, 80)}`);
  } finally {
    await rm(local, { force: true }).catch(() => {});
  }
}
await rm(work, { recursive: true, force: true }).catch(() => {});
await writeFile(OUT, rows.join("\n") + "\n");

console.log(`\ndocuments: ${done} scored, ${skipped} skipped`);
console.log(`address rows: ${addrRowsProposed} proposed, ${addrRowsResolved} matched a sample address, ${addrRowsTruth} sample addresses in truth\n`);
console.log("field                     truth  hit  fam  wrong  missed  unverif   precision  recall");
for (const f of [...EXTRACT_FIELDS, ...ADDRESS_FIELDS.map((x) => `@${x}`)]) {
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
