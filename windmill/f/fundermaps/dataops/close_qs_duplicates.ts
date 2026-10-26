import { $ } from "bun";

/**
 * Data Ops — close QuickScans that are already in FunderMaps (Worker #219).
 *
 * Every hour, at :20: each open melden dossier with a QuickScan document goes
 * through FunderMapsWorker's `check-qs-duplicates`: the registration number is
 * read from the PDF (text and file name) and compared with the QuickScans
 * already on the dossier's pand. Only a certain duplicate (same registration
 * on the same pand) is closed, through the API, as a reviewer would close it:
 * outcome duplicate with the registration and the existing QuickScan as the
 * note, and the melder's "verwerkt" mail. Everything else (a new QuickScan, no
 * number read, a number found on another pand) stays for a person.
 *
 * Batch and idempotent like ingest_pending: a closed dossier is not open any
 * more, so the next run does not see it again. This script is a thin runner;
 * the logic lives in the Worker repo.
 */

/** Windmill resource shapes (f/fundermaps/managed_pg, f/fundermaps/s3). */
type Postgresql = { host: string; port?: number; user: string; dbname?: string; password: string; sslmode?: string };
type S3 = { endPoint?: string; region?: string; accessKey: string; secretKey: string; useSSL?: boolean; bucket?: string };

/** Its own checkout: ingest_pending pins /tmp/fundermaps-worker to another commit in the same container. */
const WORKER_DIR = "/tmp/fundermaps-worker-qs";
const WORKER_REPO = "https://github.com/Laixer/FunderMapsWorker.git";
/**
 * The exact Worker commit this runner imports (Worker #312: closeDuplicates
 * exported). To ship Worker changes here, set this to a commit on main, in
 * Windmill and in the windmill/ mirror together.
 */
const WORKER_REF = "0d83e9702575c26a0f1d7820498731437288832b";
/** Where intake objects live; the s3 resource's own bucket is fundermaps-data. */
const BUCKET = "fundermaps";
const API_URL = "https://api.fundermaps.com";

/**
 * @param api_key  fmsk key of the Fundie user (variable f/fundermaps/dataops/qs_sweeper_api_key):
 *                 the close goes through the API as that user.
 * @param close    false = report only, close nothing (a dry run).
 * @param dossier_id  check only this dossier.
 */
export async function main(pg: Postgresql, s3: S3, api_key: string = "", close: boolean = true, dossier_id?: number) {
  if (close && !api_key) throw new Error("close needs api_key (variable f/fundermaps/dataops/qs_sweeper_api_key)");
  await ensureTools();
  const commit = await ensureWorker();

  // The Worker reads its configuration from the environment, at import time.
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
    FUNDERMAPS_API_URL: API_URL,
    FUNDERMAPS_API_KEY: api_key,
  });

  type Verdict = {
    dossierId: number; reference: string | null; verdict: "dubbel" | "nieuw" | "onbekend";
    read: { system: string; number: string }[];
    match: { inquiryId: number; documentName: string; documentDate: string } | null;
  };
  const worker = (await import(`${WORKER_DIR}/src/commands/check-qs-duplicates.ts`)) as {
    checkDossiers: (o: { dossier?: number }) => Promise<Verdict[]>;
    closeDuplicates: (v: Verdict[]) => Promise<number>;
  };
  const { sql: workerSql } = (await import(`${WORKER_DIR}/src/db.ts`)) as { sql: { end: (o?: { timeout?: number }) => Promise<void> } };

  try {
    const verdicts = await worker.checkDossiers({ dossier: dossier_id });
    const duplicates = verdicts.filter((v) => v.verdict === "dubbel");
    const closed = close && duplicates.length ? await worker.closeDuplicates(verdicts) : 0;
    console.log(`worker at ${commit}; open QuickScan dossiers: ${verdicts.length}; duplicates: ${duplicates.length}; closed: ${closed}`);
    return {
      worker: commit,
      checked: verdicts.length,
      duplicates: duplicates.length,
      closed,
      close,
      details: verdicts.map((v) => ({
        dossier: v.dossierId, reference: v.reference, verdict: v.verdict,
        read: v.read.map((r) => `${r.system} ${r.number}`),
        match: v.match ? `${v.match.documentName} (${v.match.documentDate})` : null,
      })),
    };
  } finally {
    await workerSql.end({ timeout: 5 }).catch(() => {});
  }
}

/** The worker image may lack the PDF text tools; they vanish on a container restart. */
async function ensureTools() {
  const missing = (await Promise.all(["pdftotext", "pdfinfo", "file"].map((b) => Bun.which(b)))).some((p) => !p);
  if (!missing) return;
  console.log("installing pdf tools");
  await $`apt-get update -qq`.quiet().nothrow();
  await $`env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils file`.quiet();
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
