import * as wmill from "windmill-client";
import { Client } from "pg";
import { from as pgCopyFrom } from "pg-copy-streams";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { Readable } from "stream";

export async function main(
  db: wmill.Resource<"postgresql">,
  s3: wmill.Resource<"s3">,
  inquiry_id: number,
  s3_key: string,
) {
  console.log(`Loading samples for inquiry ${inquiry_id} from s3://fundermaps-data/${s3_key}`);

  const s3Client = new S3Client({
    endpoint: s3.endPoint,
    region: s3.region || "us-east-1",
    credentials: { accessKeyId: s3.accessKey, secretAccessKey: s3.secretKey },
    forcePathStyle: s3.pathStyle ?? true,
  });

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
    // Verify inquiry exists
    const { rows } = await client.query(
      "SELECT id FROM report.inquiry WHERE id = $1",
      [inquiry_id]
    );
    if (rows.length === 0) throw new Error(`Inquiry ${inquiry_id} not found`);

    const s3Res = await s3Client.send(new GetObjectCommand({
      Bucket: "fundermaps-data",
      Key: s3_key,
    }));

    // Stream CSV into temp table
    await client.query(`
      CREATE TEMP TABLE tmp_samples (
        building_id text,
        foundation_type text
      )
    `);

    const copyStream = client.query(pgCopyFrom(
      "COPY tmp_samples FROM STDIN WITH (FORMAT csv)"
    ));
    await new Promise<void>((resolve, reject) => {
      const s3Stream = Readable.from(s3Res.Body as AsyncIterable<Uint8Array>);
      s3Stream.on("error", reject);
      copyStream.on("error", reject);
      copyStream.on("finish", resolve);
      s3Stream.pipe(copyStream);
    });

    // Insert samples, skipping unknown buildings or invalid enum values
    const result = await client.query(`
      INSERT INTO report.inquiry_sample (inquiry_id, building_id, foundation_type)
      SELECT DISTINCT ON (t.building_id)
        $1,
        t.building_id,
        t.foundation_type::report.foundation_type
      FROM tmp_samples t
      INNER JOIN geocoder.building b ON b.external_id = t.building_id
      ON CONFLICT DO NOTHING
    `, [inquiry_id]);

    const count = result.rowCount ?? 0;
    console.log(`Done — ${count} samples inserted for inquiry ${inquiry_id}`);
    return { inquiry_id: inquiry_id, inserted: count };
  } finally {
    await client.end();
  }
}
