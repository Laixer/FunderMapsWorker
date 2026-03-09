import { sql } from "../db.ts";
import { log, ACCENT, RESET } from "../lib/log.ts";
import * as s3 from "../providers/s3.ts";

interface OrphanedFile {
  id: number;
  key: string;
  original_filename: string;
}

export async function cleanupStorage(): Promise<boolean> {
  const orphaned = await sql<OrphanedFile[]>`
    SELECT id, key, original_filename
    FROM application.file_resources_orphaned
  `;

  if (orphaned.length === 0) {
    log.info("No orphaned files found");
    return true;
  }

  log.info(`Found ${ACCENT.job}${orphaned.length}${RESET} orphaned files`);

  let deleted = 0;
  let failed = 0;

  for (const file of orphaned) {
    const s3Path = `user-data/${file.key}/${file.original_filename}`;
    try {
      log.step(`Deleting ${ACCENT.muted}${s3Path}${RESET}`);
      await s3.deleteFile(s3Path, "fundermaps");

      await sql`
        DELETE FROM application.file_resources WHERE id = ${file.id}
      `;
      deleted++;
    } catch (e) {
      log.error(`Failed to delete ${s3Path}`, { error: String(e) });
      failed++;
    }
  }

  if (failed === 0) {
    log.info(`${ACCENT.ok}✓${RESET} Cleaned up ${ACCENT.job}${deleted}${RESET} files`);
  } else {
    log.warn(`Cleanup: ${ACCENT.ok}${deleted}${RESET} deleted, ${ACCENT.fail}${failed}${RESET} failed`);
  }
  return failed === 0;
}
