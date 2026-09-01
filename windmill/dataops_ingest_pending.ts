import { $ } from "bun";
import postgres from "postgres";

/**
 * Data Ops — read what arrived.
 *
 * Every 15 minutes: each open dossier that has a document nobody has read yet
 * goes through FunderMapsWorker's `ingest-dossier` (classify pages, extract,
 * per-address rows, admissibility). Nothing here decides anything: every value
 * lands 'pending' for a person in Studio → Controle.
 *
 * Batch, not webhook (Yorick 2026-09-01): a sweep is idempotent and
 * self-healing — a dossier missed by one run is picked up by the next, and a
 * crash mid-batch loses nothing because the CLI leaves no extraction behind on
 * failure. This script is a thin runner; the logic lives in the Worker repo.
 */

/** Windmill resource shapes (f/fundermaps/managed_pg, f/fundermaps/s3). */
type Postgresql = { host: string; port?: number; user: string; dbname?: string; password: string; sslmode?: string };
type S3 = { endPoint?: string; region?: string; accessKey: string; secretKey: string; useSSL?: boolean; bucket?: string };

const WORKER_DIR = "/tmp/fundermaps-worker";
const WORKER_REPO = "https://github.com/Laixer/FunderMapsWorker.git";
/** Where intake and pipeline objects live; the s3 resource's own bucket is fundermaps-data. */
const BUCKET = "fundermaps";

export async function main(pg: Postgresql, s3: S3, openrouter: string, limit: number = 20) {
  await ensureTools();
  const commit = await ensureWorker();

  // The Worker reads its configuration from the environment.
  Object.assign(process.env, {
    FUNDERMAPS_DATABASE_HOST: pg.host,
    FUNDERMAPS_DATABASE_PORT: String(pg.port ?? 25060),
    FUNDERMAPS_DATABASE_NAME: pg.dbname ?? "fundermaps",
    FUNDERMAPS_DATABASE_USER: pg.user,
    FUNDERMAPS_DATABASE_PASSWORD: pg.password,
    FUNDERMAPS_S3_ENDPOINT: `${s3.useSSL === false ? "http" : "https"}://${(s3.endPoint ?? "ams3.digitaloceanspaces.com").replace(/^https?:\/\//, "")}`,
    FUNDERMAPS_S3_REGION: s3.region ?? "ams3",
    FUNDERMAPS_S3_BUCKET: BUCKET,
    FUNDERMAPS_S3_ACCESS_KEY: s3.accessKey,
    FUNDERMAPS_S3_SECRET_KEY: s3.secretKey,
    OPENROUTER_API_KEY: openrouter,
  });

  const sql = postgres({
    host: pg.host, port: pg.port ?? 25060, database: pg.dbname ?? "fundermaps",
    username: pg.user, password: pg.password, ssl: "require", max: 1,
  });
  let pending: number[];
  try {
    pending = (await sql<{ id: number }[]>`
      select distinct d.id
        from dataops.dossier d
        join dataops.artifact a on a.dossier_id = d.id
       where d.inquiry_id is null and d.outcome is null
         and d.channel in ('upload', 'email', 'api')
         and not exists (select 1 from dataops.extraction e where e.artifact_id = a.id)
       order by d.id
       limit ${limit}`).map((r) => Number(r.id));
  } finally {
    await sql.end({ timeout: 5 });
  }
  console.log(`worker at ${commit}; pending dossiers: ${pending.length}`);

  const details: { dossier: number; ok: boolean; fields: number; summary: string }[] = [];
  for (const id of pending) {
    const run = await $`bun run src/commands/ingest-dossier.ts --dossier ${id}`.cwd(WORKER_DIR).nothrow().quiet();
    const log = (run.stdout.toString() + run.stderr.toString()).replace(/\x1b\[[0-9;]*m/g, "");
    const lines = log.split("\n").filter((l) => /dossier #|proposed|ERR|WRN|done/.test(l));
    console.log(lines.join("\n"));
    const fields = Number(/done .*fields=(\d+)/.exec(log)?.[1] ?? 0);
    details.push({ dossier: id, ok: run.exitCode === 0 && !/\bERR\b/.test(log), fields, summary: lines.at(-1) ?? "" });
  }

  return {
    worker: commit,
    read: details.filter((d) => d.ok).length,
    failed: details.filter((d) => !d.ok).map((d) => d.dossier),
    fields: details.reduce((n, d) => n + d.fields, 0),
    details,
  };
}

/** The worker image lacks poppler/ImageMagick/`file`; they vanish on a container restart. */
async function ensureTools() {
  const missing = (await Promise.all(["pdftotext", "pdftoppm", "convert", "file"].map((b) => Bun.which(b)))).some((p) => !p);
  if (!missing) return;
  console.log("installing pdf/image tools");
  await $`apt-get update -qq`.quiet().nothrow();
  await $`env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils imagemagick file`.quiet();
}

/** FunderMapsWorker at main, cached per container. Returns the short commit. */
async function ensureWorker(): Promise<string> {
  const cached = await Bun.file(`${WORKER_DIR}/.git/HEAD`).exists();
  if (cached) {
    await $`git -C ${WORKER_DIR} fetch -q --depth 1 origin main`.quiet();
    await $`git -C ${WORKER_DIR} reset -q --hard origin/main`.quiet();
  } else {
    await $`rm -rf ${WORKER_DIR}`.quiet();
    await $`git clone -q --depth 1 ${WORKER_REPO} ${WORKER_DIR}`.quiet();
  }
  await $`bun install --frozen-lockfile --silent`.cwd(WORKER_DIR).quiet();
  return (await $`git -C ${WORKER_DIR} rev-parse --short HEAD`.text()).trim();
}
