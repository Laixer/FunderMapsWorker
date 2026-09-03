import * as wmill from "windmill-client";
import { Client } from "pg";
import { from as pgCopyFrom } from "pg-copy-streams";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { Readable } from "stream";

export async function main(
  db: wmill.Resource<"postgresql">,
  s3: wmill.Resource<"s3">,
  s3_key: string = "source/owner_full.csv",
) {
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
    console.log(`Fetching s3://fundermaps-data/${s3_key}`);
    const s3Res = await s3Client.send(new GetObjectCommand({
      Bucket: "fundermaps-data",
      Key: s3_key,
    }));

    // Load into temp table via COPY FROM STDIN
    await client.query(`
      CREATE TEMP TABLE tmp_ownership (
        building_id text,
        owner       text
      )
    `);

    console.log("Streaming CSV into temp table...");
    const copyStream = client.query(pgCopyFrom(
      "COPY tmp_ownership FROM STDIN WITH (FORMAT csv)"
    ));
    await new Promise<void>((resolve, reject) => {
      const s3Stream = Readable.from(s3Res.Body as AsyncIterable<Uint8Array>);
      s3Stream.on("error", reject);
      copyStream.on("error", reject);
      copyStream.on("finish", resolve);
      s3Stream.pipe(copyStream);
    });

    console.log("Upserting into data.building_ownership...");
    const result = await client.query(`
      INSERT INTO data.building_ownership (building_id, owner)
      SELECT DISTINCT ON (t.building_id) t.building_id, t.owner
      FROM tmp_ownership t
      INNER JOIN geocoder.building b ON b.external_id = t.building_id
      ON CONFLICT (building_id) DO UPDATE SET owner = EXCLUDED.owner
    `);

    const count = result.rowCount ?? 0;
    console.log(`Done — ${count} rows upserted`);
    return { upserted: count };
  } finally {
    await client.end();
  }
}
