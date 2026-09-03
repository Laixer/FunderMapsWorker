import * as wmill from "windmill-client";
import { Client } from "pg";

export async function main(
  db: wmill.Resource<"postgresql">,
  tileset: string,
) {
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
    const { rows: [job] } = await client.query(
      `INSERT INTO application.worker_jobs (job_type, payload)
       VALUES ('process_mapset', $1)
       RETURNING id`,
      [JSON.stringify({ tileset })]
    );
    const jobId = Number(job.id);
    console.log(`Enqueued ${tileset} → job #${jobId}`);

    const deadline = Date.now() + 10_800_000; // 3 hours
    while (Date.now() < deadline) {
      await new Promise(r => setTimeout(r, 30_000));
      const { rows: [j] } = await client.query(
        "SELECT status, last_error FROM application.worker_jobs WHERE id = $1",
        [jobId]
      );
      console.log(`${tileset}: ${j.status}`);
      if (j.status === "completed") return { tileset, job_id: jobId, status: "completed" };
      if (j.status === "failed") throw new Error(`${tileset} failed: ${j.last_error ?? "unknown"}`);
    }
    throw new Error(`${tileset} timed out after 3 hours`);
  } finally {
    await client.end();
  }
}