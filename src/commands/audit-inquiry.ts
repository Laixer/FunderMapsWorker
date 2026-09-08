import { log, ACCENT, RESET } from "../lib/log.ts";
import { sql } from "../db.ts";
import { readSubmission } from "./ingest-dossier.ts";
import {
  INQUIRY_COLUMN,
  NOT_COMPARED,
  SAMPLE_COLUMN,
  compare,
  currentValueText,
  type Comparison,
} from "../lib/audit-compare.ts";

/**
 * The nalezing: Fundie re-reads a rapportage that is already in the
 * database, and a person judges only what differs.
 *
 * 22,776 of 29,165 rapportages (2026-09-08) sit in pending_review: typed by
 * one person, never checked by a second. The document is still there. So:
 * read it again with the same pipeline that reads new submissions, compare
 * every proposal with the sample it belongs to, and put only the
 * discrepancies -- and the values the database does not have at all -- in
 * front of a reviewer. A document whose reading agrees with the database
 * closes its own dossier; that share, per inquiry type, is the invoer's
 * quality score.
 *
 * An audit is an ordinary dossier (channel 'audit', `audit_inquiry_id` set)
 * whose artifact points at the existing inquiry-report/ file. Nothing is
 * copied and nothing in report.* changes here; the API's commit for an audit
 * dossier applies the confirmed values as updates.
 *
 *   audit-inquiry --inquiry <id> [--again] [--dry-run]
 *   audit-inquiry --type foundation_research [--limit 200] [--parallel 4]
 */

/** The sender's label the admissibility gate expects, per inquiry type. */
const CATEGORY_FOR_TYPE: Record<string, string> = {
  foundation_research: "foundationresearch",
  archive_research: "archieveresearch",
  quickscan: "quickscan",
  note: "overig",
};

interface InquiryHead {
  id: number;
  document_name: string | null;
  document_file: string | null;
  type: string;
  document_date: Date | null;
  contractor_name: string | null;
  audit_status: string;
}

interface SampleRow {
  id: number;
  address: string;
  building_id: string | null;
  [column: string]: unknown;
}

export interface AuditResult {
  inquiryId: number;
  dossierId: number | null;
  read: boolean;
  compared: number;
  agreed: number;
  differs: number;
  missing: number;
  skipped: number;
  closed: boolean;
  error?: string;
}

const SAMPLE_COLUMNS = [...new Set(Object.values(SAMPLE_COLUMN))];

/** Open (or find) the audit dossier for one rapportage. */
async function ensureDossier(head: InquiryHead, samples: SampleRow[], again: boolean): Promise<{ id: number; fresh: boolean }> {
  const [existing] = await sql<{ id: number; outcome: string | null }[]>`
    SELECT id, outcome FROM dataops.dossier WHERE audit_inquiry_id = ${head.id} ORDER BY id DESC LIMIT 1`;
  if (existing) {
    if (!again) return { id: existing.id, fresh: false };
    // A re-read reopens the dossier: outcome and the inquiry link go, the
    // earlier reading is superseded by readSubmission({again}).
    await sql`UPDATE dataops.dossier SET outcome = NULL, outcome_note = NULL, outcome_at = NULL, inquiry_id = NULL WHERE id = ${existing.id}`;
    return { id: existing.id, fresh: false };
  }

  // The dossier's own building: the pand most samples sit on, so the
  // document-level values compare against the sample they describe.
  const counts = new Map<string, number>();
  for (const s of samples) if (s.building_id) counts.set(s.building_id, (counts.get(s.building_id) ?? 0) + 1);
  const building = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;

  const ext = (head.document_file ?? "").split(".").pop()?.toLowerCase() ?? "pdf";
  const mime = ext === "pdf" ? "application/pdf" : `image/${ext === "jpg" ? "jpeg" : ext}`;
  const [d] = await sql<{ id: number }[]>`
    INSERT INTO dataops.dossier (channel, subject, external_ref, building_id, resolution_status, audit_inquiry_id, payload)
    VALUES ('audit', ${head.document_name ?? `rapportage ${head.id}`}, ${`audit:inquiry:${head.id}`},
            ${building}, ${building ? "resolved" : null}, ${head.id},
            ${sql.json({ inquiry_type: head.type, samples: samples.length, audit_status: head.audit_status })})
    RETURNING id`;
  await sql`
    INSERT INTO dataops.artifact (dossier_id, storage_key, original_filename, mime_type, declared_category, lane)
    VALUES (${d!.id}, ${`inquiry-report/${head.document_file}`},
            ${`${head.document_name ?? `rapportage-${head.id}`}.${ext}`}, ${mime},
            ${CATEGORY_FOR_TYPE[head.type] ?? null}, 'none')`;
  await sql`
    INSERT INTO dataops.dossier_entry (dossier_id, kind, actor_kind, actor, text, body, visible_to_melder)
    VALUES (${d!.id}, 'received', 'pipeline', 'audit',
            ${`Nalezing van rapportage #${head.id} (${head.type}, ${samples.length} adres${samples.length === 1 ? "" : "sen"})`},
            ${sql.json({ inquiry_id: head.id })}, false)`;
  return { id: d!.id, fresh: true };
}

/**
 * Compare the latest reading of the audit dossier with the rapportage.
 * Returns the tallies; writes state + current_value on every field.
 */
async function compareReading(dossierId: number, head: InquiryHead, samples: SampleRow[], dryRun: boolean) {
  const fields = await sql<{ id: number; field: string; value: string | null; address_id: string | null; address_text: string | null; state: string }[]>`
    SELECT f.id, f.field, f.value, f.address_id, f.address_text, f.state::text AS state
      FROM dataops.extraction_field f
      JOIN dataops.extraction e ON e.id = f.extraction_id
      JOIN dataops.artifact a ON a.id = e.artifact_id
     WHERE a.dossier_id = ${dossierId}
       AND e.id = (SELECT max(e2.id) FROM dataops.extraction e2 JOIN dataops.artifact a2 ON a2.id = e2.artifact_id WHERE a2.dossier_id = ${dossierId} AND e2.error IS NULL)
       AND f.state = 'pending'
     ORDER BY f.id`;

  const byAddress = new Map(samples.map((s) => [s.address, s]));
  const [main] = await sql<{ building_id: string | null }[]>`SELECT building_id FROM dataops.dossier WHERE id = ${dossierId}`;
  const mainSample = samples.length === 1
    ? samples[0]!
    : (samples.find((s) => s.building_id === main?.building_id) ?? null);

  // Group candidates per (target, field): the damage lists are one question
  // with several answers, and the database agrees if it agrees with any.
  type Group = { key: string; field: string; ids: number[]; values: string[]; target: SampleRow | null; document: boolean; unresolved: boolean };
  const groups = new Map<string, Group>();
  for (const f of fields) {
    const document = f.field in INQUIRY_COLUMN;
    const unresolved = !!f.address_text && !f.address_id;
    const target = document ? null : f.address_id ? (byAddress.get(f.address_id) ?? null) : mainSample;
    const key = `${document ? "doc" : f.address_id ?? (unresolved ? `?${f.address_text}` : "main")}|${f.field}`;
    if (!groups.has(key)) groups.set(key, { key, field: f.field, ids: [], values: [], target, document, unresolved });
    const g = groups.get(key)!;
    g.ids.push(f.id);
    if (f.value) g.values.push(f.value);
  }

  const tally = { compared: 0, agreed: 0, differs: 0, missing: 0, skipped: 0 };
  const settle = async (ids: number[], state: string, current: string | null) => {
    if (dryRun) return;
    await sql`UPDATE dataops.extraction_field SET state = ${state}::dataops.review_state, current_value = ${current} WHERE id = ANY(${ids})`;
  };

  for (const g of groups.values()) {
    if (NOT_COMPARED.has(g.field)) {
      tally.skipped++;
      await settle(g.ids, "superseded", null);
      continue;
    }
    let dbValue: unknown = null;
    let known = true;
    if (g.document) {
      const col = INQUIRY_COLUMN[g.field]!;
      dbValue = col === "contractor" ? head.contractor_name : col === "type" ? head.type : head.document_date;
    } else if (g.unresolved) {
      // The report names an address we could not match: the database may
      // well have it under another pand. Left open, with nothing alongside;
      // the reviewer decides. Counted as missing.
      known = false;
    } else if (g.target) {
      const col = SAMPLE_COLUMN[g.field];
      if (!col) { tally.skipped++; await settle(g.ids, "superseded", null); continue; }
      dbValue = g.target[col];
    } else {
      known = false;
    }
    const outcome: Comparison = known ? compare(g.field, g.values, dbValue) : "missing";
    const current = known ? currentValueText(g.field, dbValue) : null;
    tally.compared++;
    if (outcome === "agrees") { tally.agreed++; await settle(g.ids, "agreed", current); }
    else if (outcome === "differs") { tally.differs++; await settle(g.ids, "pending", current); }
    else { tally.missing++; await settle(g.ids, "pending", null); }
    log.step(
      `  ${g.field}${g.target && !g.document ? ` @${g.target.address.slice(0, 14)}` : g.unresolved ? " @?" : ""} = ` +
      `${ACCENT.type}${g.values.join(" | ")}${RESET}  db: ${ACCENT.muted}${current ?? "—"}${RESET}  ` +
      (outcome === "agrees" ? `${ACCENT.ok}agrees${RESET}` : outcome === "differs" ? `${ACCENT.fail}differs${RESET}` : `${ACCENT.muted}missing${RESET}`),
    );
  }
  return tally;
}

export async function auditInquiry(inquiryId: number, opts: { again?: boolean; dry_run?: boolean } = {}): Promise<AuditResult> {
  const result: AuditResult = { inquiryId, dossierId: null, read: false, compared: 0, agreed: 0, differs: 0, missing: 0, skipped: 0, closed: false };
  const [head] = await sql<InquiryHead[]>`
    SELECT i.id, i.document_name, i.document_file, i.type::text AS type, i.document_date, i.audit_status::text AS audit_status,
           c.name AS contractor_name
      FROM report.inquiry i
      JOIN application.attribution at ON at.id = i.attribution_id
      LEFT JOIN application.contractor c ON c.id = at.contractor_id
     WHERE i.id = ${inquiryId}`;
  if (!head) throw new Error(`no rapportage ${inquiryId}`);
  if (!head.document_file) { result.error = "no document"; return result; }

  const samples = await sql<SampleRow[]>`
    SELECT id, address, building_id, ${sql(SAMPLE_COLUMNS)}
      FROM report.inquiry_sample WHERE inquiry_id = ${inquiryId} ORDER BY id`;
  log.info(`rapportage #${head.id} ${head.document_name ?? ""}`, { type: head.type, status: head.audit_status, adressen: samples.length });

  if (opts.dry_run) {
    log.warn("dry run: no dossier is opened, nothing is read");
    return result;
  }

  const { id: dossierId, fresh } = await ensureDossier(head, samples, !!opts.again);
  result.dossierId = dossierId;
  if (!fresh && !opts.again) {
    log.warn(`already audited as dossier #${dossierId}; use --again to re-read`);
    return result;
  }

  const reads = await readSubmission({ dossier_id: dossierId, again: !!opts.again });
  result.read = reads.length > 0;
  if (!result.read) { result.error = "read failed"; return result; }

  const t = await compareReading(dossierId, head, samples, false);
  Object.assign(result, t);

  const open = t.differs + t.missing;
  if (open === 0) {
    await sql`
      UPDATE dataops.dossier
         SET outcome = 'accepted', outcome_note = ${`Nalezing: geen afwijkingen (${t.agreed} waarden komen overeen)`},
             outcome_at = now(), inquiry_id = ${head.id}
       WHERE id = ${dossierId}`;
    result.closed = true;
  }
  await sql`
    INSERT INTO dataops.dossier_entry (dossier_id, kind, actor_kind, actor, text, body, visible_to_melder)
    VALUES (${dossierId}, 'status', 'pipeline', 'audit',
            ${open === 0
              ? `Nalezing klaar: ${t.agreed} waarden komen overeen, geen afwijkingen; dossier gesloten`
              : `Nalezing klaar: ${t.differs} afwijking${t.differs === 1 ? "" : "en"}, ${t.missing} niet in de database, ${t.agreed} komen overeen`},
            ${sql.json(t)}, false)`;
  log.step(`${ACCENT.ok}${t.agreed} agree${RESET}, ${ACCENT.fail}${t.differs} differ${RESET}, ${t.missing} missing, ${t.skipped} not compared` + (open === 0 ? " -> closed" : " -> in the queue"));
  return result;
}

/**
 * A batch: rapportages of one type with a document and no audit yet, the
 * never-reviewed ones first. `parallel` reads run at once; the model is the
 * bottleneck, not this process.
 */
export async function auditBatch(opts: { type: string; limit: number; parallel: number; dry_run?: boolean }): Promise<AuditResult[]> {
  const todo = await sql<{ id: number }[]>`
    SELECT i.id
      FROM report.inquiry i
     WHERE i.type = ${opts.type}::report.inquiry_type
       AND i.document_file IS NOT NULL AND i.document_file <> ''
       AND NOT EXISTS (SELECT 1 FROM dataops.dossier d WHERE d.audit_inquiry_id = i.id)
     ORDER BY (i.audit_status = 'pending_review') DESC, i.id DESC
     LIMIT ${opts.limit}`;
  log.info(`batch ${opts.type}`, { todo: todo.length, parallel: opts.parallel });
  const results: AuditResult[] = [];
  let next = 0;
  const worker = async () => {
    while (next < todo.length) {
      const id = todo[next++]!.id;
      try {
        results.push(await auditInquiry(id, { dry_run: opts.dry_run }));
      } catch (e) {
        log.error(`rapportage #${id}: ${String(e).slice(0, 200)}`);
        results.push({ inquiryId: id, dossierId: null, read: false, compared: 0, agreed: 0, differs: 0, missing: 0, skipped: 0, closed: false, error: String(e).slice(0, 200) });
      }
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, opts.parallel) }, worker));
  const ok = results.filter((r) => r.read);
  log.info("batch done", {
    read: ok.length,
    failed: results.length - ok.length,
    closed: ok.filter((r) => r.closed).length,
    "in queue": ok.filter((r) => !r.closed).length,
    agreed: ok.reduce((n, r) => n + r.agreed, 0),
    differs: ok.reduce((n, r) => n + r.differs, 0),
    missing: ok.reduce((n, r) => n + r.missing, 0),
  });
  return results;
}

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const arg = (k: string) => { const i = argv.indexOf(`--${k}`); return i > -1 ? argv[i + 1] : undefined; };
  const inquiry = arg("inquiry");
  const type = arg("type");
  if (!inquiry && !type) {
    console.error(
      "usage:\n" +
      "  audit-inquiry --inquiry <id> [--again] [--dry-run]\n" +
      "  audit-inquiry --type foundation_research [--limit 200] [--parallel 4]\n",
    );
    process.exit(1);
  }
  log.banner("Data Ops — nalezing");
  try {
    if (inquiry) {
      const r = await auditInquiry(Number(inquiry), { again: argv.includes("--again"), dry_run: argv.includes("--dry-run") });
      console.log(JSON.stringify(r));
    } else {
      const rs = await auditBatch({ type: type!, limit: Number(arg("limit") ?? 200), parallel: Number(arg("parallel") ?? 4), dry_run: argv.includes("--dry-run") });
      console.log(JSON.stringify(rs));
    }
  } finally {
    await sql.end({ timeout: 5 });
  }
  process.exit(0);
}
