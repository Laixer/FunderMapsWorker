import * as wmill from "windmill-client";
import { Client } from "pg";
import { to as copyTo } from "pg-copy-streams";
import { S3Client } from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";

// Streams each organization's CSV straight from Postgres (COPY ... TO STDOUT)
// into a multipart S3 upload. The previous implementation buffered the whole
// result set per org three times over (pg rows -> mapped string[] -> joined
// string) and was OOM-killed on 2026-08-01 at mem_peak 3.37 GB on the 4 GB
// worker, on the largest tenant (1.45M rows). Memory here is bounded by
// PART_SIZE * QUEUE_SIZE regardless of tenant size.
//
// create_date is formatted in SQL to byte-match the old output, which was a
// JS Date.toString(): "Wed Jul 01 2026 09:10:26 GMT+0000 (Coordinated Universal Time)".
// Ugly, but it is the existing contract for a billing input — do not "fix" it
// here without agreeing the format change with whoever consumes these files.

const PART_SIZE = 8 * 1024 * 1024;
const QUEUE_SIZE = 2;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function main(
  db: wmill.Resource<"postgresql">,
  s3: wmill.Resource<"s3">,
  date?: string,
) {
  const referenceDate = date ? new Date(date) : new Date();
  const exportDate = new Date(referenceDate);
  exportDate.setMonth(exportDate.getMonth() - 1);

  const year = exportDate.getFullYear();
  const month = exportDate.toLocaleString("en", { month: "short" }).toLowerCase();
  const refDay = referenceDate.toISOString().slice(0, 10);

  console.log(`Reference date: ${refDay}, exporting: ${year}-${month}`);

  const client = new Client({
    host: db.host,
    port: db.port,
    user: db.user,
    password: db.password,
    database: db.dbname,
    ssl: db.sslmode === "require" ? { rejectUnauthorized: false } : false,
  });
  await client.connect();

  try {
    const { rows: orgs } = await client.query<{ organization_id: string }>(
      `SELECT DISTINCT organization_id
        FROM application.product_tracker
        WHERE create_date >= date_trunc('month', $1::date) - interval '1 month'
          AND create_date < date_trunc('month', $1::date)`,
      [refDay],
    );

    console.log(`Found ${orgs.length} organization(s)`);

    const s3Client = new S3Client({
      endpoint: s3.endPoint,
      region: s3.region || "us-east-1",
      credentials: { accessKeyId: s3.accessKey, secretAccessKey: s3.secretKey },
      forcePathStyle: s3.pathStyle ?? true,
    });

    let totalRows = 0;

    for (const { organization_id: org } of orgs) {
      // COPY takes no bind parameters, so these are inlined. org comes straight
      // out of a uuid column and refDay off a Date, but guard anyway.
      if (!UUID_RE.test(org)) throw new Error(`Refusing to inline non-uuid org: ${org}`);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(refDay)) throw new Error(`Bad reference date: ${refDay}`);

      const copySql = `COPY (
          SELECT
            pt.organization_id,
            pt.product,
            pt.building_id,
            to_char(pt.create_date AT TIME ZONE 'UTC', 'Dy Mon DD YYYY HH24:MI:SS')
              || ' GMT+0000 (Coordinated Universal Time)' AS create_date,
            pt.identifier AS request
          FROM application.product_tracker AS pt
          WHERE pt.organization_id = '${org}'::uuid
            AND pt.create_date >= date_trunc('month', DATE '${refDay}') - interval '1 month'
            AND pt.create_date <  date_trunc('month', DATE '${refDay}')
        ) TO STDOUT WITH (FORMAT csv, HEADER true)`;

      const s3Key = `product/${year}/${month}/${org}.csv`;
      const copyStream = client.query(copyTo(copySql));

      const upload = new Upload({
        client: s3Client,
        params: {
          Bucket: "fundermaps-data",
          Key: s3Key,
          Body: copyStream,
          ContentType: "text/csv",
        },
        partSize: PART_SIZE,
        queueSize: QUEUE_SIZE,
      });

      await upload.done();

      const rows = (copyStream as unknown as { rowCount?: number }).rowCount ?? 0;
      totalRows += rows;
      console.log(`${org.slice(0, 8)}… → ${rows} rows → s3://fundermaps-data/${s3Key}`);
    }

    return { year, month, organizations: orgs.length, rows: totalRows };
  } finally {
    await client.end();
  }
}
