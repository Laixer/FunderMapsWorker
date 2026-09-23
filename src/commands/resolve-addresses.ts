/**
 * Re-resolve the address texts the pipeline could not place.
 *
 * A value read "per address" carries the text the document wrote and, when
 * the resolver could place it, a geocoder id. Until 2026-09-14 the resolver
 * looked at an arbitrary twenty candidates before ranking them by what the
 * dossier knows, so a common street name in the dossier's own city stayed
 * unresolved (451 texts on 253 open dossiers). This command runs today's
 * resolver over exactly those values and links what it can:
 *
 *   - extraction_field.address_id is set on the pending values of that text;
 *   - an address beyond the dossier's own pand gets a pending pipeline row in
 *     dataops.dossier_address, as ingest does now (#333 part D);
 *   - the dossier's timeline gets one line per run.
 *
 * Only open dossiers, only pending values with a text and no id; values a
 * reviewer already judged, re-linked or rejected are never touched. Safe to
 * re-run: what is resolved is skipped next time.
 *
 *   bun run src/commands/resolve-addresses.ts [--dossier <id>] [--limit N] [--apply]
 *
 * --ranges (#186): the texts that name a range or list of numbers ("Olympiaweg
 * 20-92", "Harddraverstraat 46 t/m 52A, 52C en 54C"). Each pending value on
 * such a text is spread over every address the range names -- the row itself
 * moves to one of them, copies go to the rest -- whether it was unresolved or
 * sat on one address. A single link outside the range (dossier 2494: 54B, a
 * number the document never writes) is replaced; a link inside it, perhaps set
 * by hand, is kept and the others are added beside it. A range we cannot
 * expand is left exactly as it is.
 *
 *   bun run src/commands/resolve-addresses.ts --ranges [--dossier <id>] [--apply]
 */

import { log } from "../lib/log.ts";
import { sql } from "../db.ts";
import { loadDossierContext, placeAddressText, resolveAddress } from "./ingest-dossier.ts";
import { parseAddressList } from "../lib/address-resolve.ts";

interface Pending {
  dossier_id: number;
  address_text: string;
  n: number;
}

async function main(opts: { dossier?: number; limit?: number; apply: boolean }) {
  const rows = await sql<Pending[]>`
    SELECT d.id AS dossier_id, f.address_text, count(*)::int AS n
      FROM dataops.extraction_field f
      JOIN dataops.extraction e ON e.id = f.extraction_id
      JOIN dataops.artifact a ON a.id = e.artifact_id
      JOIN dataops.dossier d ON d.id = a.dossier_id
     WHERE d.outcome IS NULL AND d.inquiry_id IS NULL
       AND f.state = 'pending' AND f.address_id IS NULL AND f.address_text IS NOT NULL
       ${opts.dossier ? sql`AND d.id = ${opts.dossier}` : sql``}
     GROUP BY d.id, f.address_text
     ORDER BY d.id, min(f.id)
     ${opts.limit ? sql`LIMIT ${opts.limit}` : sql``}`;
  log.info("unresolved address texts", { texts: rows.length, dossiers: new Set(rows.map((r) => r.dossier_id)).size, apply: opts.apply });

  const counts = { texts: 0, resolved: 0, values: 0, extra_rows: 0, still_unresolved: 0 };
  let lastDossier: number | null = null;
  let ctx = await loadDossierContext(null);
  const resolvedForDossier: string[] = [];

  const flush = async () => {
    if (lastDossier && resolvedForDossier.length && opts.apply) {
      await sql`
        INSERT INTO dataops.dossier_entry (dossier_id, kind, actor_kind, actor, text, body, visible_to_melder)
        VALUES (${lastDossier}, 'finding', 'pipeline', 'resolve-addresses',
                ${`Adressen alsnog herkend: ${resolvedForDossier.slice(0, 6).join(", ")}${resolvedForDossier.length > 6 ? ` … (+${resolvedForDossier.length - 6})` : ""}`},
                ${sql.json({ resolved: resolvedForDossier })}, false)`;
    }
    resolvedForDossier.length = 0;
  };

  for (const r of rows) {
    if (r.dossier_id !== lastDossier) {
      await flush();
      lastDossier = r.dossier_id;
      ctx = await loadDossierContext(r.dossier_id);
    }
    counts.texts++;
    const c = await resolveAddress(r.address_text, ctx);
    if (!c) {
      counts.still_unresolved++;
      continue;
    }
    counts.resolved++;
    counts.values += r.n;
    resolvedForDossier.push(r.address_text);
    log.step(`#${r.dossier_id} ${r.address_text} → ${c.id}${c.city ? ` (${c.city})` : ""} ×${r.n}`);
    if (!opts.apply) continue;
    await sql`
      UPDATE dataops.extraction_field f SET address_id = ${c.id}
        FROM dataops.extraction e JOIN dataops.artifact a ON a.id = e.artifact_id
       WHERE e.id = f.extraction_id AND a.dossier_id = ${r.dossier_id}
         AND f.state = 'pending' AND f.address_id IS NULL AND f.address_text = ${r.address_text}`;
    // Beyond the dossier's own pand: a pending row for the address panel, the
    // way ingest records it now. The own pand is never a row there.
    if (c.buildingId && c.buildingId !== ctx.buildingId) {
      const ins = await sql`
        INSERT INTO dataops.dossier_address (dossier_id, address_id, address_text, source, state)
        VALUES (${r.dossier_id}, ${c.id}, ${r.address_text}, 'pipeline', 'pending')
        ON CONFLICT (dossier_id, address_id) DO NOTHING`;
      counts.extra_rows += ins.count;
    }
  }
  await flush();
  log.info(opts.apply ? "done" : "dry run — nothing written", counts);
}

interface RangeValue {
  id: number;
  dossier_id: number;
  extraction_id: number;
  field: string;
  value: string | null;
  address_text: string;
  address_id: string | null;
}

// Two numbers joined by a range word or a list separator (Postgres ARE: \y is
// a word boundary). A cheap cut in SQL; parseAddressList has the last word.
const RANGE_PREFILTER = String.raw`\d\s*[a-z]?\s*(t\s*/\s*m|tot en met|-|,|&|\+|\yen\y)\s*\d`;

async function expandRanges(opts: { dossier?: number; apply: boolean }) {
  // A cheap pre-filter in SQL (two numbers joined by a range word or a list
  // separator); parseAddressList decides.
  const rows = (await sql<RangeValue[]>`
    SELECT f.id, d.id AS dossier_id, f.extraction_id, f.field, f.value, f.address_text, f.address_id
      FROM dataops.extraction_field f
      JOIN dataops.extraction e ON e.id = f.extraction_id
      JOIN dataops.artifact a ON a.id = e.artifact_id
      JOIN dataops.dossier d ON d.id = a.dossier_id
     WHERE d.outcome IS NULL AND d.inquiry_id IS NULL AND f.state = 'pending'
       AND f.address_text ~* ${RANGE_PREFILTER}
       ${opts.dossier ? sql`AND d.id = ${opts.dossier}` : sql``}
     ORDER BY d.id, f.id`).filter((r) => parseAddressList(r.address_text));

  const counts = { values: rows.length, texts: 0, expanded_texts: 0, unexpandable_texts: 0, moved: 0, copies: 0, moved_off_wrong_address: 0, kept_in_range: 0 };
  const byDossier = new Map<number, RangeValue[]>();
  for (const r of rows) byDossier.set(r.dossier_id, [...(byDossier.get(r.dossier_id) ?? []), r]);

  for (const [dossierId, values] of byDossier) {
    const ctx = await loadDossierContext(dossierId);
    // What the values already point at counts as known: it settles which
    // city a street like Stadionweg is in when the dossier has no pand.
    for (const v of values) if (v.address_id) ctx.knownAddressIds.add(v.address_id);
    const texts = new Map<string, RangeValue[]>();
    for (const v of values) texts.set(v.address_text, [...(texts.get(v.address_text) ?? []), v]);
    const expandedHere: string[] = [];

    for (const [text, vs] of texts) {
      counts.texts++;
      const { targets, hits } = await placeAddressText(text, ctx);
      if (!targets.length) {
        // Not in our BAG under this name, or a street in several cities we
        // cannot choose between: leave the values exactly as they are. We can
        // show a link is wrong only when we know what the range covers.
        counts.unexpandable_texts++;
        log.step(`#${dossierId} ${text} → not expandable, left as is`);
        continue;
      }
      counts.expanded_texts++;
      expandedHere.push(`${text} (${targets.length})`);
      log.step(`#${dossierId} ${text} → ${targets.length} address(es) × ${vs.length} value(s)`);
      const targetIds = new Set(targets.map((t) => t.id));

      for (const v of vs) {
        const own = v.address_id && targetIds.has(v.address_id) ? targets.find((t) => t.id === v.address_id)! : targets[0]!;
        if (v.address_id && targetIds.has(v.address_id)) counts.kept_in_range++;
        else if (v.address_id) counts.moved_off_wrong_address++;
        counts.moved++;
        counts.copies += targets.length - 1;
        if (!opts.apply) continue;
        await sql`UPDATE dataops.extraction_field SET address_id = ${own.id}, address_text = ${own.text}
                   WHERE id = ${v.id} AND state = 'pending'`;
        for (const t of targets) {
          if (t.id === own.id) continue;
          await sql`
            INSERT INTO dataops.extraction_field
              (extraction_id, field, value, confidence, evidence, evidence_page, evidence_offset,
               state, address_text, address_id, current_value)
            SELECT extraction_id, field, value, confidence, evidence, evidence_page, evidence_offset,
                   'pending', ${t.text}, ${t.id}, current_value
              FROM dataops.extraction_field WHERE id = ${v.id}
            ON CONFLICT DO NOTHING`;
        }
      }
      if (opts.apply) {
        for (const h of hits) {
          if (!h.buildingId || h.buildingId === ctx.buildingId) continue;
          await sql`
            INSERT INTO dataops.dossier_address (dossier_id, address_id, address_text, source, state)
            VALUES (${dossierId}, ${h.id}, ${text}, 'pipeline', 'pending')
            ON CONFLICT (dossier_id, address_id) DO NOTHING`;
        }
      }
    }
    if (opts.apply && expandedHere.length) {
      await sql`
        INSERT INTO dataops.dossier_entry (dossier_id, kind, actor_kind, actor, text, body, visible_to_melder)
        VALUES (${dossierId}, 'finding', 'pipeline', 'resolve-addresses',
                ${`Adresreeksen uitgesplitst: ${expandedHere.slice(0, 6).join(", ")}${expandedHere.length > 6 ? ` … (+${expandedHere.length - 6})` : ""}`},
                ${sql.json({ expanded: expandedHere })}, false)`;
    }
  }
  log.info(opts.apply ? "done" : "dry run — nothing written", counts);
}

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const arg = (k: string) => {
    const i = argv.indexOf(`--${k}`);
    return i > -1 ? argv[i + 1] : undefined;
  };
  log.banner("Data Ops — resolve addresses");
  try {
    const dossier = arg("dossier") ? Number(arg("dossier")) : undefined;
    if (argv.includes("--ranges")) await expandRanges({ dossier, apply: argv.includes("--apply") });
    else await main({ dossier, limit: arg("limit") ? Number(arg("limit")) : undefined, apply: argv.includes("--apply") });
    process.exit(0);
  } catch (e) {
    log.error(String(e));
    process.exit(1);
  } finally {
    await sql.end({ timeout: 5 }).catch(() => {});
  }
}
