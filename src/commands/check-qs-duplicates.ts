/**
 * Which submitted QuickScans are already in FunderMaps (#219)?
 *
 * For every open melden dossier with a QuickScan document, read the
 * registration number from the PDF (text and file name) and compare it with
 * the QuickScans already on the dossier's pand. Read-only: it reports, it
 * never closes a dossier or sends a mail. Closing a certain duplicate (and so
 * the melder's "verwerkt" mail) is the API's job, after Yorick's review.
 *
 * Verdicts:
 *   dubbel    the pand already has a QuickScan with the same registration
 *   nieuw     a registration was read, and no QuickScan on the pand has it
 *   onbekend  no registration could be read; a human decides, as before
 *
 *   bun run src/commands/check-qs-duplicates.ts [--dossier <id>] [--json]
 */

import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { sql } from "../db.ts";
import { log } from "../lib/log.ts";
import * as s3 from "../providers/s3.ts";
import { fileKind, pageCount, pageText } from "../providers/pdf.ts";
import {
  inquiryRegistrations,
  readRegistrations,
  sharedRegistration,
  type Registration,
} from "../lib/qs-registration.ts";

/** A registration sits on the first pages of an attest or certificate. */
const PAGES_READ = 4;

export interface Verdict {
  dossierId: number;
  reference: string | null;
  buildingId: string | null;
  verdict: "dubbel" | "nieuw" | "onbekend";
  read: Registration[];
  match: { inquiryId: number; documentName: string; documentDate: string; registration: Registration } | null;
  existing: { inquiryId: number; documentName: string; documentDate: string }[];
}

async function readArtifact(storageKey: string, filename: string | null, dir: string): Promise<Registration[]> {
  const path = join(dir, storageKey.replace(/[^\w.-]/g, "_"));
  await s3.downloadFile(path, storageKey);
  let text = "";
  if ((await fileKind(path)) === "pdf") {
    const pages = Math.min(await pageCount(path), PAGES_READ);
    for (let p = 1; p <= pages; p++) text += `\n${await pageText(path, p)}`;
  }
  return readRegistrations(text, filename);
}

export async function checkDossiers(opts: { dossier?: number }): Promise<Verdict[]> {
  const dossiers = await sql<{ id: number; reference: string | null; building_id: string | null }[]>`
    SELECT DISTINCT d.id, d.reference, d.building_id
    FROM dataops.dossier d
    JOIN dataops.artifact a ON a.dossier_id = d.id AND a.declared_category = 'quickscan'
    WHERE d.channel = 'upload' AND d.outcome IS NULL AND d.audit_inquiry_id IS NULL
      ${opts.dossier ? sql`AND d.id = ${opts.dossier}` : sql``}
    ORDER BY d.id`;

  const dir = await mkdtemp(join(tmpdir(), "qs-dup-"));
  const out: Verdict[] = [];
  try {
    for (const d of dossiers) {
      const artifacts = await sql<{ storage_key: string; original_filename: string | null }[]>`
        SELECT storage_key, original_filename FROM dataops.artifact
        WHERE dossier_id = ${d.id} AND declared_category = 'quickscan' AND storage_key IS NOT NULL`;
      const read: Registration[] = [];
      for (const a of artifacts) {
        try {
          read.push(...(await readArtifact(a.storage_key, a.original_filename, dir)));
        } catch (e) {
          log.warn(`dossier ${d.id}: could not read ${a.original_filename ?? a.storage_key}: ${e}`);
        }
      }

      const existing = d.building_id
        ? await sql<{ id: number; document_name: string; document_date: string; note: string | null }[]>`
            SELECT DISTINCT i.id, i.document_name, i.document_date::text, i.note
            FROM report.inquiry i
            JOIN report.inquiry_sample s ON s.inquiry_id = i.id
            WHERE s.building_id = ${d.building_id} AND i.type = 'facade_scan'
              AND i.delete_date IS NULL AND s.delete_date IS NULL
            ORDER BY 3 DESC`
        : [];

      let match: Verdict["match"] = null;
      for (const i of existing) {
        const hit = sharedRegistration(read, inquiryRegistrations(i.document_name, i.note));
        if (hit) { match = { inquiryId: i.id, documentName: i.document_name, documentDate: i.document_date, registration: hit }; break; }
      }

      out.push({
        dossierId: d.id,
        reference: d.reference,
        buildingId: d.building_id,
        verdict: match ? "dubbel" : read.length ? "nieuw" : "onbekend",
        read,
        match,
        existing: existing.map((i) => ({ inquiryId: i.id, documentName: i.document_name, documentDate: i.document_date })),
      });
    }
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
  return out;
}

function print(verdicts: Verdict[]): void {
  if (!verdicts.length) { log.info("no open melden dossiers with a QuickScan"); return; }
  for (const v of verdicts) {
    const read = v.read.map((r) => `${r.system} ${r.number}`).join(", ") || "geen nummer gelezen";
    const why = v.match
      ? `= ${v.match.documentName} (${v.match.documentDate}, ${v.match.registration.system} ${v.match.registration.number})`
      : v.existing.length ? `bestaand: ${v.existing.map((e) => `${e.documentName} ${e.documentDate}`).join(", ")}` : "geen QuickScan op het pand";
    log.info(`${v.reference ?? `dossier ${v.dossierId}`}  ${v.verdict.toUpperCase().padEnd(8)}  gelezen: ${read}  ${why}`);
  }
}

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const arg = (k: string) => {
    const i = argv.indexOf(`--${k}`);
    return i > -1 ? argv[i + 1] : undefined;
  };
  try {
    const verdicts = await checkDossiers({ dossier: arg("dossier") ? Number(arg("dossier")) : undefined });
    if (argv.includes("--json")) process.stdout.write(JSON.stringify(verdicts, null, 2) + "\n");
    else { log.banner("Data Ops — QuickScan duplicates"); print(verdicts); }
    process.exit(0);
  } catch (e) {
    log.error(String(e));
    process.exit(1);
  } finally {
    await sql.end({ timeout: 5 }).catch(() => {});
  }
}
