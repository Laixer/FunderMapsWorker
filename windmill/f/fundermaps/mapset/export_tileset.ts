// Export one maplayer bundle to the GPKG archive — the job the queue worker
// (fundermaps-worker-0, `process_mapset`) does today, run on the Windmill
// worker instead so that droplet can be retired.
//
// Same output as the queue worker: `ogr2ogr -overwrite -f GPKG` of
// `maplayer.<tileset>` → `<prefix>/YYYY/mon/DD/<tileset>.gpkg` in the
// cold-storage bucket `fundermaps-archive`. archive_mapset_monthly reads that
// layout, and that bucket is the only model history: never prune `mapset/`.
//
// It then writes a GeoParquet copy of that same file next to it
// (`<tileset>.parquet`): ~4x smaller, and DuckDB can query it in place, so
// comparing two days no longer means downloading two 3.35 GB files. The GPKG
// stays the archive of record — see archiveParquet.
//
// Needs `ogr2ogr` and `duckdb` on the worker: the image in `windmill-worker/`.
//
// Upload constraints (same as the queue worker's, see its process-mapset.ts):
//   * Multipart uploads to the cold bucket fail (BadDigest on
//     CompleteMultipartUpload). The AWS SDK's Upload and Bun's S3 write both
//     go multipart on big files, so this does ONE presigned PUT.
//   * That PUT must stream from disk: the worker has 4 GB. Bun's fetch reads
//     a Bun.file body into memory first — the first analysis_full test was
//     OOM-killed at 3.1 GB (2026-10-09) — so curl does the PUT.
//   * A single PUT is capped at 5 GB. analysis_full is ~3.35 GB; past 5 GB the
//     fix is splitting the export, not multipart.
//
// `prefix` exists for test runs: they write to their own folder (the
// side-by-side run against the queue worker used `mapset-shadow/`) so they
// never overwrite the real archive.

import { S3Client, SQL } from "bun";
import { mkdtemp, readdir, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

type Postgresql = {
  host: string;
  port: number;
  user: string;
  password: string;
  dbname: string;
  sslmode?: string;
};

type S3 = {
  endPoint: string;
  region?: string;
  accessKey: string;
  secretKey: string;
  pathStyle?: boolean;
};

const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const MAX_ATTEMPTS = 3;
const RETRY_DELAY_MS = 5_000;
const OGR2OGR_TIMEOUT_MS = 2 * 60 * 60 * 1000; // same 2 h cap as the queue worker
const UPLOAD_TIMEOUT_S = 3600;
const SINGLE_PUT_LIMIT = 5 * 1024 ** 3;
const DUCKDB_TIMEOUT_MS = 30 * 60 * 1000; // analysis_full converts in about a minute
// Where the worker image keeps DuckDB's spatial extension (windmill-worker/Containerfile).
const DUCKDB_EXTENSIONS = "/usr/local/share/duckdb/extensions";
// A killed run (OOM, cancel) skips its `finally` and leaves a multi-GB temp dir
// behind; the next run removes ones older than any run can take.
const STALE_WORKDIR_MS = 4 * 60 * 60 * 1000;

export async function main(
  db: Postgresql,
  s3: S3,
  tileset: string,
  bucket = "fundermaps-archive",
  prefix = "mapset",
) {
  // The name ends up in an ogr2ogr argument and an object key.
  if (!/^[a-z][a-z0-9_]*$/.test(tileset)) throw new Error(`invalid tileset name: '${tileset}'`);

  const bundle = await readBundle(db, tileset);
  if (!bundle) throw new Error(`no maplayer.bundle row for '${tileset}'`);
  if (!bundle.enabled || !bundle.upload_dataset) {
    console.log(`${tileset}: enabled=${bundle.enabled} upload_dataset=${bundle.upload_dataset} — nothing to export`);
    return { tileset, skipped: true };
  }

  // UTC date, like the queue worker (its container runs in UTC).
  const now = new Date();
  const day = String(now.getUTCDate()).padStart(2, "0");
  const key = `${prefix}/${now.getUTCFullYear()}/${MONTHS[now.getUTCMonth()]}/${day}/${tileset}.gpkg`;

  await removeStaleWorkDirs(tileset);
  const started = performance.now();
  const workDir = await mkdtemp(join(tmpdir(), `fm-${tileset}-`));
  const gpkg = join(workDir, `${tileset}.gpkg`);
  try {
    await withRetries(`export ${tileset}`, () => exportGpkg(db, tileset, gpkg));
    const bytes = (await stat(gpkg)).size;
    const features = await featureCount(gpkg);
    console.log(`${tileset}: ${features} features, ${(bytes / 1e9).toFixed(2)} GB`);
    if (features === 0) throw new Error(`${tileset}: export has no features — not uploading`);
    if (bytes >= SINGLE_PUT_LIMIT) {
      throw new Error(`${tileset}: ${bytes} bytes exceeds the 5 GB single-PUT limit — split the export`);
    }

    await withRetries(`upload ${key}`, () => upload(s3, bucket, key, gpkg, bytes));
    const seconds = Math.round((performance.now() - started) / 1000);
    console.log(`${tileset}: uploaded to s3://${bucket}/${key} in ${seconds}s total`);

    const parquet = await archiveParquet(s3, bucket, key, gpkg, workDir, tileset, features);
    return { tileset, bucket, key, bytes, features, seconds, ...parquet };
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
}

async function readBundle(db: Postgresql, tileset: string) {
  const sql = new SQL({
    hostname: db.host,
    port: db.port,
    database: db.dbname,
    username: db.user,
    password: db.password,
    tls: db.sslmode === "require" ? { rejectUnauthorized: false } : false,
    max: 1,
  });
  try {
    const [row] = await sql`
      SELECT enabled, upload_dataset FROM maplayer.bundle WHERE tileset = ${tileset}
    `;
    return row as { enabled: boolean; upload_dataset: boolean } | undefined;
  } finally {
    await sql.close();
  }
}

// The queue worker's exact command (fromPostgis → ogr2ogr -overwrite -f GPKG),
// except the password travels in PGPASSWORD instead of the argument list, so
// it never shows up in `ps` or in an error message.
async function exportGpkg(db: Postgresql, tileset: string, gpkg: string) {
  const source = `PG:host=${db.host} port=${db.port} dbname=${db.dbname} user=${db.user} sslmode=${db.sslmode ?? "require"}`;
  console.log(`${tileset}: ogr2ogr maplayer.${tileset} → GPKG`);
  const proc = Bun.spawn(["ogr2ogr", "-overwrite", "-f", "GPKG", gpkg, source, `maplayer.${tileset}`], {
    env: { ...process.env, PGPASSWORD: db.password },
    stdout: "ignore",
    stderr: "pipe",
    timeout: OGR2OGR_TIMEOUT_MS,
  });
  const [code, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
  if (code !== 0) throw new Error(`ogr2ogr exited ${code}: ${stderr.trim().slice(0, 2000)}`);
}

async function featureCount(gpkg: string): Promise<number> {
  const proc = Bun.spawn(["ogrinfo", "-ro", "-so", "-al", gpkg], { stdout: "pipe", stderr: "pipe" });
  const [code, out] = await Promise.all([proc.exited, new Response(proc.stdout).text()]);
  if (code !== 0) throw new Error(`ogrinfo exited ${code}`);
  return [...out.matchAll(/^Feature Count: (\d+)$/gm)].reduce((n, m) => n + Number(m[1]), 0);
}

// The GeoParquet copy, made from the GPKG on disk rather than from a second
// read of the database: no extra load, and both files are the same snapshot.
//
// The GPKG is already uploaded when this runs and stays the archive of record.
// Whatever goes wrong here (no duckdb on the worker, a failed conversion or
// upload) is logged and leaves the export a success; the result then has no
// parquet_* fields and refresh_log shows a null parquet_bytes.
async function archiveParquet(
  s3: S3,
  bucket: string,
  key: string,
  gpkg: string,
  workDir: string,
  tileset: string,
  features: number,
) {
  const started = performance.now();
  const parquetKey = key.replace(/\.gpkg$/, ".parquet");
  const parquet = gpkg.replace(/\.gpkg$/, ".parquet");
  try {
    const rows = await convertToParquet(gpkg, parquet, workDir);
    if (rows !== features) throw new Error(`the Parquet file has ${rows} rows, the GPKG ${features}`);
    const parquetBytes = (await stat(parquet)).size;
    await withRetries(`upload ${parquetKey}`, () => upload(s3, bucket, parquetKey, parquet, parquetBytes));
    const parquetSeconds = Math.round((performance.now() - started) / 1000);
    console.log(
      `${tileset}: GeoParquet copy at s3://${bucket}/${parquetKey}, ${(parquetBytes / 1e9).toFixed(2)} GB in ${parquetSeconds}s`,
    );
    return { parquet_key: parquetKey, parquet_bytes: parquetBytes, parquet_seconds: parquetSeconds };
  } catch (err) {
    console.log(`${tileset}: no GeoParquet copy this run — ${String(err).slice(0, 1000)}`);
    return {};
  }
}

// Returns the row count of the Parquet file it wrote.
async function convertToParquet(gpkg: string, parquet: string, workDir: string): Promise<number> {
  const q = (s: string) => `'${s.replaceAll("'", "''")}'`;
  const sql = [
    // The extension comes from the image; a run never downloads one.
    `SET extension_directory = ${q(DUCKDB_EXTENSIONS)}`,
    "SET autoinstall_known_extensions = false",
    "SET autoload_known_extensions = false",
    // The worker has 4 GB and 2 vCPUs; analysis_full peaks around 0.3 GB.
    "SET memory_limit = '1GB'",
    "SET threads = 2",
    `SET temp_directory = ${q(workDir)}`,
    "SET preserve_insertion_order = false",
    "LOAD spatial",
    // `fid` is the row number ogr2ogr adds to a GPKG, not a column of the
    // maplayer table (none of them has one).
    `COPY (SELECT COLUMNS(lambda c: c <> 'fid') FROM ST_Read(${q(gpkg)})) TO ${q(parquet)} (FORMAT parquet, COMPRESSION zstd)`,
    `SELECT (SELECT count(*) FROM read_parquet(${q(parquet)})),
            (SELECT count(*) FROM parquet_kv_metadata(${q(parquet)}) WHERE decode(key) = 'geo')`,
  ].join(";\n");

  const proc = Bun.spawn(["duckdb", "-bail", "-csv", "-noheader", "-c", sql], {
    stdout: "pipe",
    stderr: "pipe",
    timeout: DUCKDB_TIMEOUT_MS,
  });
  const [code, out, err] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  if (code !== 0) throw new Error(`duckdb exited ${code}: ${(err + out).trim().slice(0, 2000)}`);

  const [rows, geo] = (out.trim().split("\n").at(-1) ?? "").split(",").map(Number);
  if (!Number.isInteger(rows)) throw new Error(`duckdb printed no row count: ${out.trim().slice(0, 500)}`);
  // Without the `geo` key it is plain Parquet with a blob column, not GeoParquet.
  if (geo !== 1) throw new Error("the Parquet file has no `geo` metadata");
  return rows as number;
}

async function upload(s3: S3, bucket: string, key: string, file: string, bytes: number) {
  const client = new S3Client({
    accessKeyId: s3.accessKey,
    secretAccessKey: s3.secretKey,
    endpoint: s3.endPoint,
    region: s3.region || "us-east-1",
    bucket,
    virtualHostedStyle: !(s3.pathStyle ?? true),
  });
  const url = client.presign(key, { method: "PUT", expiresIn: UPLOAD_TIMEOUT_S + 600 });

  // curl -T streams the file with a Content-Length in one PUT. The presigned
  // URL goes in on stdin (`--config -`) so the signature stays out of `ps`.
  const proc = Bun.spawn(
    ["curl", "--fail-with-body", "--silent", "--show-error", "--max-time", String(UPLOAD_TIMEOUT_S),
     "--upload-file", file, "--config", "-"],
    { stdin: new Blob([`url = "${url}"\n`]), stdout: "pipe", stderr: "pipe" },
  );
  const [code, out, err] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  if (code !== 0) throw new Error(`PUT ${key}: curl exited ${code}: ${(err + out).trim().slice(0, 500)}`);

  const remote = await client.stat(key);
  if (remote.size !== bytes) throw new Error(`PUT ${key}: stored ${remote.size} bytes, expected ${bytes}`);
}

async function removeStaleWorkDirs(tileset: string) {
  const dir = tmpdir();
  for (const name of await readdir(dir)) {
    if (!name.startsWith(`fm-${tileset}-`)) continue;
    const path = join(dir, name);
    const age = Date.now() - (await stat(path)).mtimeMs;
    if (age < STALE_WORKDIR_MS) continue;
    console.log(`${tileset}: removing stale ${path} (${Math.round(age / 3_600_000)} h old)`);
    await rm(path, { recursive: true, force: true });
  }
}

async function withRetries(what: string, fn: () => Promise<void>) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt >= MAX_ATTEMPTS) throw err;
      console.log(`${what}: attempt ${attempt} failed (${String(err).slice(0, 300)}), retrying`);
      await Bun.sleep(RETRY_DELAY_MS * attempt);
    }
  }
}
