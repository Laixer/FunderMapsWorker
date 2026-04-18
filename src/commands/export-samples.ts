import { log, ACCENT, RESET } from "../lib/log.ts";
import { spawn } from "../lib/subprocess.ts";
import { env } from "../config.ts";
import * as s3 from "../providers/s3.ts";
import { join } from "node:path";
import { tmpdir } from "node:os";

/**
 * Export specific sample tables as SQL + data and upload to S3.
 */
export async function exportSamples(payload: {
  date?: string;
}): Promise<boolean> {
  const referenceDate = payload.date ? new Date(payload.date) : new Date();

  // Reference the previous month for the export (matching export-product logic)
  const exportDate = new Date(referenceDate);
  exportDate.setMonth(exportDate.getMonth() - 1);

  const year = exportDate.getFullYear();
  const month = exportDate
    .toLocaleString("en", { month: "short" })
    .toLowerCase();

  log.info(`Exporting samples for: ${ACCENT.time}${year}-${month}${RESET}`);

  const tables = [
    { schema: "report", name: "inquiry" },
    { schema: "report", name: "inquiry_sample" },
    { schema: "report", name: "recovery" },
    { schema: "report", name: "recovery_sample" },
  ];

  for (const table of tables) {
    const tableName = `${table.schema}.${table.name}`;
    const fileName = `${table.name}.sql`;
    const localPath = join(tmpdir(), fileName);
    const s3Path = `samples/${year}/${month}/${fileName}`;

    log.step(`Dumping ${ACCENT.muted}${tableName}${RESET} to ${localPath}`);

    const { exitCode, stderr } = await spawn([
      "pg_dump",
      "-h", env.FUNDERMAPS_DATABASE_HOST,
      "-p", env.FUNDERMAPS_DATABASE_PORT.toString(),
      "-U", env.FUNDERMAPS_DATABASE_USER,
      "-d", env.FUNDERMAPS_DATABASE_NAME,
      "-t", tableName,
      "--clean",
      "--if-exists",
      "-f", localPath,
    ], {
      env: {
        PGPASSWORD: env.FUNDERMAPS_DATABASE_PASSWORD,
      },
    });

    if (exitCode !== 0) {
      log.error(`Failed to dump ${tableName}`, { error: stderr });
      return false;
    }

    log.step(`Uploading ${ACCENT.muted}${fileName}${RESET} to S3`);
    await s3.uploadFile(localPath, s3Path, "fundermaps-data");
  }

  return true;
}
