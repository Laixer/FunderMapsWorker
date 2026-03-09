import { sql } from "../db.ts";
import { log, ACCENT, RESET } from "../lib/log.ts";
import * as s3 from "../providers/s3.ts";
import { join } from "node:path";
import { tmpdir } from "node:os";

const ORGANIZATIONS = [
  "5c2c5822-6996-4306-96ba-6635ea7f90e2",
  "8a56e920-7811-47b7-9289-758c8fe346db",
  "c06a1fc6-6452-4b88-85fd-ba50016c578f",
  "58872000-cb69-433a-91ba-165a9d0b4710",
  "0ca4d02d-8206-4453-ba45-84f532c868f3",
  "8a9db31a-1142-4e8e-b1c2-17bfa2b0f2c2",
  "0689db53-3fc7-4a7e-939e-26580c677ea0",
];

export async function exportProduct(payload: {
  date?: string;
}): Promise<boolean> {
  const referenceDate = payload.date
    ? new Date(payload.date)
    : new Date();

  log.info(`Export reference date: ${ACCENT.time}${referenceDate.toISOString().slice(0, 10)}${RESET}`);

  for (const org of ORGANIZATIONS) {
    log.step(`Organization ${ACCENT.muted}${org.slice(0, 8)}…${RESET}`);

    const rows = await sql`
      SELECT
        pt.organization_id,
        pt.product,
        pt.building_id,
        b.external_id,
        pt.create_date,
        pt.identifier AS request
      FROM application.product_tracker AS pt
      JOIN geocoder.building AS b ON b.id = pt.building_id
      WHERE pt.organization_id = ${org}
        AND pt.create_date >= date_trunc('month', ${referenceDate}::date) - interval '1 month'
        AND pt.create_date < date_trunc('month', ${referenceDate}::date)
    `;

    if (rows.length === 0) {
      log.debug("No data to export");
      continue;
    }

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

    const year = referenceDate.getFullYear();
    const month = referenceDate
      .toLocaleString("en", { month: "short" })
      .toLowerCase();
    const s3Path = `product/${year}/${month}/${org}.csv`;

    log.step(`Uploading ${ACCENT.job}${rows.length}${RESET} rows to S3`);
    await s3.uploadFile(csvPath, s3Path, "fundermaps-data");
  }

  return true;
}
