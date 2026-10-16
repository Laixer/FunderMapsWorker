import { $ } from "bun";
import postgres from "postgres";

/**
 * Data Ops — read what arrived.
 *
 * Every hour, at :03: each open dossier that has a document nobody has read yet
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
/**
 * The exact Worker commit this runner imports. Pinned on purpose: the ingest
 * lane runs a commit someone chose, not whatever lands on main next. To ship
 * Worker changes here, set this to a commit on main, in Windmill and in the
 * windmill/ mirror together.
 */
const WORKER_REF = "e761477ceeb21c018e624cea8ce9c2de5007510e";
/** Where intake and pipeline objects live; the s3 resource's own bucket is fundermaps-data. */
const BUCKET = "fundermaps";

/**
 * @param dossier_id  read this one dossier, now. The Studio's "Nieuwe
 *                    rapportage" uploads a document and calls this through
 *                    the API so the reviewer is not waiting for the next
 *                    hourly sweep. Without it: the sweep, oldest first.
 */
export async function main(pg: Postgresql, s3: S3, openrouter: string, limit: number = 20, dossier_id?: number) {
  await ensureTools();
  const commit = await ensureWorker();

  // The Worker reads its configuration from the environment.
  Object.assign(process.env, {
    FUNDERMAPS_DATABASE_HOST: pg.host,
    FUNDERMAPS_DATABASE_PORT: String(pg.port || 25060),
    FUNDERMAPS_DATABASE_NAME: pg.dbname || "fundermaps",
    FUNDERMAPS_DATABASE_USER: pg.user,
    FUNDERMAPS_DATABASE_PASSWORD: pg.password,
    FUNDERMAPS_S3_ENDPOINT: `${s3.useSSL === false ? "http" : "https"}://${(s3.endPoint || "ams3.digitaloceanspaces.com").replace(/^https?:\/\//, "")}`,
    FUNDERMAPS_S3_REGION: s3.region || "ams3",
    FUNDERMAPS_S3_BUCKET: BUCKET,
    FUNDERMAPS_S3_ACCESS_KEY: s3.accessKey,
    FUNDERMAPS_S3_SECRET_KEY: s3.secretKey,
    OPENROUTER_API_KEY: openrouter,
  });

  const sql = postgres({
    host: pg.host, port: pg.port || 25060, database: pg.dbname || "fundermaps",
    username: pg.user, password: pg.password, ssl: "require", max: 1,
  });
  let pending: number[];
  try {
    pending = (await sql<{ id: number }[]>`
      select distinct d.id
        from dataops.dossier d
        join dataops.artifact a on a.dossier_id = d.id
       where d.inquiry_id is null and d.outcome is null
         and d.channel in ('upload', 'email', 'api', 'invoer_app')
         and not exists (select 1 from dataops.extraction e where e.artifact_id = a.id)
         ${dossier_id ? sql`and d.id = ${dossier_id}` : sql``}
       order by d.id
       limit ${dossier_id ? 1 : limit}`).map((r) => Number(r.id));
  } finally {
    await sql.end({ timeout: 5 });
  }
  console.log(`worker at ${commit}; pending dossiers: ${pending.length}`);

  // Import the Worker's own function rather than spawning its CLI: same code
  // the CLI and bench-extract run, but a real return value per dossier and no
  // log scraping. The env above must be set BEFORE this import -- the Worker
  // parses its configuration at load time.
  const worker = (await import(`${WORKER_DIR}/src/commands/ingest-dossier.ts`)) as {
    readSubmission: (p: { dossier_id: number }) => Promise<{ dossierId: number | null; lane: string; pages: number; fields: number; highConfidence: number }[]>;
  };
  const { sql: workerSql } = (await import(`${WORKER_DIR}/src/db.ts`)) as { sql: { end: (o?: { timeout?: number }) => Promise<void> } };

  const details: { dossier: number; ok: boolean; documents: number; fields: number; error?: string }[] = [];
  try {
    for (const id of pending) {
      try {
        const rs = await worker.readSubmission({ dossier_id: id });
        details.push({ dossier: id, ok: true, documents: rs.length, fields: rs.reduce((n, r) => n + r.fields, 0) });
      } catch (e) {
        details.push({ dossier: id, ok: false, documents: 0, fields: 0, error: String(e).slice(0, 300) });
      }
    }
  } finally {
    await workerSql.end({ timeout: 5 }).catch(() => {});
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
  const missing = (await Promise.all(["pdftotext", "pdftoppm", "convert", "file", "vips", "tiffset"].map((b) => Bun.which(b)))).some((p) => !p);
  if (!missing) return;
  console.log("installing pdf/image tools");
  await $`apt-get update -qq`.quiet().nothrow();
  await $`env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils imagemagick file`.quiet();
  // HEIC photos (iPhone uploads on melden.fundermaps.com) need the HEVC decoder
  // plugin, split out of libheif since Ubuntu 24.04 / Debian trixie. Older
  // images have it built in, so a missing package is not an error.
  await $`env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libheif-plugin-libde265`.quiet().nothrow();
  // Archive TIFFs: vips as a second reader, libtiff's tiffinfo/tiffset to
  // repair fax scans that lack their Photometric tag (src/providers/pdf.ts).
  await $`env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libvips-tools libtiff-tools`.quiet().nothrow();
}

/**
 * FunderMapsWorker at exactly WORKER_REF, cached per container; fetched only
 * when the pin moves. Throws before any Worker code is imported if the
 * checkout is anything else. Returns the short commit.
 */
async function ensureWorker(): Promise<string> {
  const headOf = async () =>
    (await Bun.file(`${WORKER_DIR}/.git/HEAD`).exists())
      ? (await $`git -C ${WORKER_DIR} rev-parse HEAD`.quiet().nothrow().text()).trim()
      : "";
  const have = await headOf();
  if (have !== WORKER_REF) {
    if (!have) {
      await $`rm -rf ${WORKER_DIR}`.quiet();
      await $`git init -q ${WORKER_DIR}`.quiet();
      await $`git -C ${WORKER_DIR} remote add origin ${WORKER_REPO}`.quiet();
    }
    await $`git -C ${WORKER_DIR} fetch -q --depth 1 origin ${WORKER_REF}`.quiet();
    await $`git -C ${WORKER_DIR} checkout -q --force --detach FETCH_HEAD`.quiet();
  }
  const head = await headOf();
  if (head !== WORKER_REF) throw new Error(`Worker checkout is ${head || "missing"}, expected ${WORKER_REF}`);
  await $`bun install --frozen-lockfile --silent`.cwd(WORKER_DIR).quiet();
  return head.slice(0, 7);
}
