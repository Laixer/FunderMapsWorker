import { sql } from "../db.ts";
import { log, ACCENT, RESET } from "../lib/log.ts";
import * as s3 from "../providers/s3.ts";
import { join } from "node:path";
import { tmpdir } from "node:os";

export async function exportProduct(payload: {
  date?: string;
}): Promise<boolean> {
  const referenceDate = payload.date
    ? new Date(payload.date)
    : new Date();

  log.info(`Export reference date: ${ACCENT.time}${referenceDate.toISOString().slice(0, 10)}${RESET}`);

  const orgs = await sql<{ organization_id: string }[]>`
    SELECT DISTINCT organization_id
    FROM application.product_tracker
    WHERE create_date >= date_trunc('month', ${referenceDate}::date) - interval '1 month'
      AND create_date < date_trunc('month', ${referenceDate}::date)
  `;

  log.info(`Exporting ${ACCENT.job}${orgs.length}${RESET} organization(s)`);

  for (const { organization_id: org } of orgs) {
    log.step(`Organization ${ACCENT.muted}${org.slice(0, 8)}…${RESET}`);

    const rows = await sql`
      SELECT
        pt.organization_id,
        pt.product,
        pt.building_id,
        pt.create_date,
        pt.identifier AS request
      FROM application.product_tracker AS pt
      WHERE pt.organization_id = ${org}
        AND pt.create_date >= date_trunc('month', ${referenceDate}::date) - interval '1 month'
        AND pt.create_date < date_trunc('month', ${referenceDate}::date)
    `;

    const csvEscape = (v: unknown): string => {
      const s = String(v ?? "");
      return s.includes(",") || s.includes('"') || s.includes("\n")
        ? `"${s.replace(/"/g, '""')}"`
        : s;
    };
    const columns = Object.keys(rows[0]!);
    const csvLines = [columns.join(",")];
    for (const row of rows) {
      csvLines.push(columns.map((c) => csvEscape(row[c])).join(","));
    }

    const csvPath = join(tmpdir(), `${org}.csv`);
    await Bun.write(csvPath, csvLines.join("\n"));

    // Identify the year and month of the data being exported (one month before the reference date)
    const exportDate = new Date(referenceDate);
    exportDate.setMonth(exportDate.getMonth() - 1);

    const year = exportDate.getFullYear();
    const month = exportDate
      .toLocaleString("en", { month: "short" })
      .toLowerCase();
    const s3Path = `product/${year}/${month}/${org}.csv`;

    log.step(`Uploading ${ACCENT.job}${rows.length}${RESET} rows to S3`);
    await s3.uploadFile(csvPath, s3Path, "fundermaps-data");
  }

  return true;
}
