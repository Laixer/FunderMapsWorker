import * as wmill from "windmill-client";
import { Client } from "pg";
import { to as pgCopyTo } from "pg-copy-streams";
import { S3Client } from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";
import { Readable } from "stream";

const TABLES = [
  { schema: "report", name: "inquiry" },
  { schema: "report", name: "inquiry_sample" },
  { schema: "report", name: "recovery" },
  { schema: "report", name: "recovery_sample" },
];

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

  console.log(`Exporting samples for: ${year}-${month}`);

  const s3Client = new S3Client({
    endpoint: s3.endPoint,
    region: s3.region || "us-east-1",
    credentials: { accessKeyId: s3.accessKey, secretAccessKey: s3.secretKey },
    forcePathStyle: s3.pathStyle ?? true,
  });

  for (const table of TABLES) {
    console.log(`Exporting ${table.schema}.${table.name}`);

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
      const stream = client.query(
        pgCopyTo(`COPY ${table.schema}.${table.name} TO STDOUT WITH CSV HEADER`)
      );

      const s3Key = `samples/${year}/${month}/${table.name}.csv`;
      const upload = new Upload({
        client: s3Client,
        params: {
          Bucket: "fundermaps-data",
          Key: s3Key,
          Body: Readable.from(stream),
          ContentType: "text/csv",
        },
      });

      await upload.done();
      console.log(`  → s3://fundermaps-data/${s3Key}`);
    } finally {
      await client.end();
    }
  }

  return { year, month, tables: TABLES.map((t) => t.name) };
}
