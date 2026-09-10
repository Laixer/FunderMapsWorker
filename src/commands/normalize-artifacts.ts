import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { log } from "../lib/log.ts";
import { sql } from "../db.ts";
import * as pdf from "../providers/pdf.ts";
import * as s3 from "../providers/s3.ts";

/**
 * One-time repair for dataops artifacts stored in a format the review screen
 * cannot show (TIFF from the archives, mostly), plus the mislabelled types.
 *
 * Before 2026-09-10 the ingest command wrote `image/jpeg` on every non-PDF
 * row and stored the file as it came, so 23 TIFF drawings sat behind an
 * <img> tag that Chrome and Firefox render as nothing. Ingest now converts
 * at intake; this walks the rows written before that and does the same:
 * download, sniff, convert (PNG for bilevel/grayscale, JPEG for colour),
 * upload under a new dataops/ key, repoint the row. Rows from the public
 * intake form (intake/ keys) carried no type at all; those get one. The
 * original object is
 * left in place -- delete it by hand once the review screen has been seen
 * to work. Rows whose real type already renders inline only get their
 * mime_type corrected.
 *
 *   normalize-artifacts [--apply] [--limit N] [--id <artifact_id>]
 *
 * Dry-run by default: prints what it would do and touches nothing.
 */
const DATAOPS_PREFIX = "dataops/";

interface Row { id: number; storage_key: string; original_filename: string | null; mime_type: string | null; size_bytes: number | null }

export async function normalizeArtifacts(opts: { apply: boolean; limit: number; id?: number }) {
  const rows = await sql<Row[]>`
    SELECT id, storage_key, original_filename, mime_type, size_bytes
      FROM dataops.artifact
     WHERE (storage_key LIKE ${DATAOPS_PREFIX + "%"} OR storage_key LIKE 'intake/%')
       AND (mime_type IS NULL OR mime_type LIKE 'image/%')
       AND (${opts.id ?? null}::int IS NULL OR id = ${opts.id ?? null})
     ORDER BY id
     LIMIT ${opts.limit}`;
  log.step(`${rows.length} image artifact(s) under ${DATAOPS_PREFIX} and intake/`);

  const summary = { checked: 0, relabelled: 0, converted: 0, skipped: 0, failed: 0 };
  for (const r of rows) {
    summary.checked++;
    const workDir = await mkdtemp(join(tmpdir(), "fm-normalize-"));
    try {
      const local = join(workDir, r.original_filename ?? `artifact-${r.id}`);
      await s3.downloadFile(local, r.storage_key);
      const real = await pdf.sniffMime(local);
      if (!real.startsWith("image/")) {
        if (r.mime_type === null && real) {
          log.step(`#${r.id}: null → ${real} (relabel only)`);
          if (opts.apply) await sql`UPDATE dataops.artifact SET mime_type = ${real} WHERE id = ${r.id}`;
          summary.relabelled++;
        } else {
          log.step(`#${r.id} ${r.storage_key}: ${real || "unknown"}, not an image -- skipped`);
          summary.skipped++;
        }
        continue;
      }
      if (pdf.browserRenders(real)) {
        if (real !== r.mime_type) {
          log.step(`#${r.id}: ${r.mime_type ?? "null"} → ${real} (relabel only)`);
          if (opts.apply) await sql`UPDATE dataops.artifact SET mime_type = ${real} WHERE id = ${r.id}`;
          summary.relabelled++;
        }
        continue;
      }
      const out = await pdf.toBrowserImage(local, workDir);
      const size = Bun.file(out.path).size;
      const key = `${DATAOPS_PREFIX}${crypto.randomUUID()}.${out.path.split(".").pop()}`;
      log.step(`#${r.id}: ${real} ${((r.size_bytes ?? 0) / 1e6).toFixed(1)} MB → ${out.mime} ${(size / 1e6).toFixed(1)} MB as ${key}${opts.apply ? "" : " (dry run)"}`);
      if (opts.apply) {
        await s3.uploadFile(out.path, key, undefined, { ContentType: out.mime });
        await sql`
          UPDATE dataops.artifact
             SET storage_key = ${key}, mime_type = ${out.mime}, size_bytes = ${size}
           WHERE id = ${r.id}`;
      }
      summary.converted++;
    } catch (e) {
      summary.failed++;
      log.step(`#${r.id} FAILED: ${(e as Error).message}`);
    } finally {
      await rm(workDir, { recursive: true, force: true });
    }
  }
  return summary;
}

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const arg = (k: string) => { const i = argv.indexOf(`--${k}`); return i > -1 ? argv[i + 1] : undefined; };
  log.banner("Data Ops — normalize artifacts");
  try {
    const r = await normalizeArtifacts({
      apply: argv.includes("--apply"),
      limit: Number(arg("limit") ?? 5000),
      id: arg("id") ? Number(arg("id")) : undefined,
    });
    console.log(JSON.stringify(r));
  } finally {
    await sql.end({ timeout: 5 });
  }
  process.exit(0);
}
