import * as wmill from "windmill-client";
import { Client } from "pg";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";

const COLUMNS = [
  "foundation_type",
  "foundation_type_reliability",
  "drystand_risk",
  "drystand_risk_reliability",
  "dewatering_depth_risk",
  "dewatering_depth_risk_reliability",
  "bio_infection_risk",
  "bio_infection_risk_reliability",
] as const;

type Col = typeof COLUMNS[number];

export async function main(
  db: wmill.Resource<"postgresql">,
  s3: wmill.Resource<"s3">,
) {
  // 1. Read reference CSV from S3
  const s3Client = new S3Client({
    endpoint: s3.endPoint,
    region: s3.region || "us-east-1",
    credentials: { accessKeyId: s3.accessKey, secretAccessKey: s3.secretKey },
    forcePathStyle: s3.pathStyle ?? true,
  });

  const response = await s3Client.send(new GetObjectCommand({
    Bucket: "fundermaps-data",
    Key: "validation/risk_model_reference.csv",
  }));
  const csvText = await (response.Body as any).transformToString("utf-8");

  // 2. Parse semicolon-delimited CSV, strip BOM
  const lines = csvText.replace(/^﻿/, "").trim().split("\n");
  type RefRow = { building_id: string } & Partial<Record<Col, string | null>>;
  const reference: RefRow[] = lines.slice(1).map((line: string) => {
    const c = line.trimEnd().split(";");
    return {
      building_id: c[0],
      foundation_type: c[1] || null,
      foundation_type_reliability: c[2] || null,
      drystand_risk: c[3] || null,
      drystand_risk_reliability: c[4] || null,
      dewatering_depth_risk: c[5] || null,
      dewatering_depth_risk_reliability: c[6] || null,
      bio_infection_risk: c[7] || null,
      bio_infection_risk_reliability: c[8] || null,
    };
  });

  console.log(`Reference: ${reference.length} buildings`);

  // 3. Query model for all reference IDs
  const client = new Client({
    host: db.host,
    port: db.port,
    user: db.user,
    password: db.password,
    database: db.dbname,
    ssl: db.sslmode === "require" ? { rejectUnauthorized: false } : false,
  });
  await client.connect();

  const { rows: modelRows } = await client.query(
    `SELECT building_id,
            foundation_type::text,
            foundation_type_reliability::text,
            drystand_risk::text,
            drystand_risk_reliability::text,
            dewatering_depth_risk::text,
            dewatering_depth_risk_reliability::text,
            bio_infection_risk::text,
            bio_infection_risk_reliability::text
     FROM data.model_risk_dynamic_all
     WHERE building_id = ANY($1)`,
    [reference.map((r) => r.building_id)],
  );
  await client.end();

  // 4. Compare
  const modelMap = new Map(modelRows.map((r: any) => [r.building_id, r]));

  type ColStats = { compared: number; match: number; rate: number | null };
  const colStats: Record<Col, ColStats> = {} as any;
  for (const col of COLUMNS) colStats[col] = { compared: 0, match: 0, rate: null };

  let foundInModel = 0;
  const notInModel: string[] = [];
  const mismatches: Array<{
    building_id: string;
    column: string;
    reference: string;
    model: string | null;
  }> = [];

  for (const ref of reference) {
    const model = modelMap.get(ref.building_id) as any;
    if (!model) {
      notInModel.push(ref.building_id);
      continue;
    }
    foundInModel++;

    for (const col of COLUMNS) {
      const refVal = ref[col];
      if (!refVal) continue;
      colStats[col].compared++;
      if ((model[col] ?? "") === refVal) {
        colStats[col].match++;
      } else {
        mismatches.push({
          building_id: ref.building_id,
          column: col,
          reference: refVal,
          model: model[col] ?? null,
        });
      }
    }
  }

  for (const col of COLUMNS) {
    const s = colStats[col];
    s.rate = s.compared > 0 ? Math.round((s.match / s.compared) * 1000) / 10 : null;
  }

  // 5. Log summary
  console.log(`Found in model: ${foundInModel}/${reference.length}`);
  if (notInModel.length > 0) console.log(`Not in model: ${notInModel.length}`);
  console.log("\nAgreement rates:");
  for (const [col, s] of Object.entries(colStats)) {
    const warn = s.rate !== null && s.rate < 90 ? " ⚠" : "";
    console.log(`  ${col}: ${s.match}/${s.compared} = ${s.rate ?? "N/A"}%${warn}`);
  }
  if (mismatches.length > 0) console.log(`\nTotal mismatches: ${mismatches.length}`);

  return {
    total_reference: reference.length,
    found_in_model: foundInModel,
    not_in_model_count: notInModel.length,
    columns: colStats,
    mismatches,
  };
}
