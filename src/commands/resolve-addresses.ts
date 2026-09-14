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
 */

import { log } from "../lib/log.ts";
import { sql } from "../db.ts";
import { loadDossierContext, resolveAddress } from "./ingest-dossier.ts";

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

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const arg = (k: string) => {
    const i = argv.indexOf(`--${k}`);
    return i > -1 ? argv[i + 1] : undefined;
  };
  log.banner("Data Ops — resolve addresses");
  try {
    await main({ dossier: arg("dossier") ? Number(arg("dossier")) : undefined, limit: arg("limit") ? Number(arg("limit")) : undefined, apply: argv.includes("--apply") });
    process.exit(0);
  } catch (e) {
    log.error(String(e));
    process.exit(1);
  } finally {
    await sql.end({ timeout: 5 }).catch(() => {});
  }
}
