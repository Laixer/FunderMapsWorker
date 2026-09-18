import { readdir } from "node:fs/promises";
import { join } from "node:path";
import postgres from "postgres";
import { describe, plan, toMigrationFile, type LedgerRow, type MigrationFile, type PlanAction } from "../lib/migrations.ts";

/**
 * `bun run migrate [--dry-run] [--status] [--allow-prod]`
 *
 * Applies db/migrations/*.sql that the ledger (application.schema_migrations)
 * does not know yet (on an empty ledger: stamps the ones at or below BASELINE,
 * which schema.sql already contains), oldest first, each in its own transaction unless the
 * file says `-- migrate: no-transaction`. Records version, sha256, who and
 * how long. Refuses to continue when an applied file has been edited.
 *
 * Connection: DATABASE_URL, else FUNDERMAPS_DATABASE_{HOST,PORT,NAME,USER,PASSWORD}.
 * Deliberately not src/config.ts: that wants the S3 and model settings too,
 * and this command runs from CI, a laptop and Windmill with nothing but a
 * database. Runs as whoever the URL names; on prod that is doadmin, the
 * owner of every object, so grants inside a migration work as written.
 */

const MIGRATIONS_DIR = join(import.meta.dir, "..", "..", "db", "migrations");
const BASELINE_FILE = join(MIGRATIONS_DIR, "BASELINE");
const LEDGER = "application.schema_migrations";
// One runner at a time per database; the number is arbitrary but fixed.
const LOCK_KEY = 811_001;

function connectionUrl(): string {
  const e = process.env;
  const direct = e["DATABASE_URL"];
  if (direct) return direct;
  const host = e["FUNDERMAPS_DATABASE_HOST"];
  const password = e["FUNDERMAPS_DATABASE_PASSWORD"];
  if (host && password) {
    const user = e["FUNDERMAPS_DATABASE_USER"] ?? "fundermaps";
    const port = e["FUNDERMAPS_DATABASE_PORT"] ?? "25060";
    const db = e["FUNDERMAPS_DATABASE_NAME"] ?? "fundermaps";
    return `postgres://${encodeURIComponent(user)}:${encodeURIComponent(password)}@${host}:${port}/${db}`;
  }
  throw new Error("set DATABASE_URL (or FUNDERMAPS_DATABASE_HOST + FUNDERMAPS_DATABASE_PASSWORD)");
}

function redact(url: string): string {
  return url.replace(/\/\/([^:@/]+)(:[^@/]*)?@/, "//$1:***@");
}

async function loadFiles(): Promise<MigrationFile[]> {
  const names = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith(".sql"));
  return Promise.all(names.map(async (f) => toMigrationFile(f, await Bun.file(join(MIGRATIONS_DIR, f)).text())));
}

async function loadBaseline(): Promise<string> {
  const f = Bun.file(BASELINE_FILE);
  if (!(await f.exists())) return "0";
  const v = (await f.text()).trim();
  return v || "0";
}

export async function migrate(opts: { dryRun: boolean; status: boolean; allowProd: boolean }): Promise<number> {
  const url = connectionUrl();
  const isProd = url.includes("do-user-871803");
  if (isProd && !opts.allowProd && !opts.dryRun && !opts.status) {
    console.error(`target looks like production (${redact(url)}); add --allow-prod to apply there`);
    return 2;
  }
  const [files, baseline] = await Promise.all([loadFiles(), loadBaseline()]);
  const sql = postgres(url, { max: 1, ssl: url.includes("ondigitalocean") ? "require" : "prefer", connection: { application_name: "fundermaps-migrate" } });
  try {
    console.log(`target   ${redact(url)}`);
    console.log(`baseline ${baseline}   files ${files.length}`);
    // Bootstrap the ledger on the first real run only; a later run would get
    // a "relation already exists, skipping" NOTICE printed by the driver.
    const hadLedger = (await sql`select to_regclass(${LEDGER}) is not null as ok`)[0]!["ok"] as boolean;
    if (!opts.dryRun && !opts.status && !hadLedger) {
      await sql.unsafe(`
        create table ${LEDGER} (
          version     text primary key,
          name        text not null,
          checksum    text not null,
          applied_at  timestamptz not null default now(),
          applied_by  text not null default current_user,
          duration_ms integer,
          baseline    boolean not null default false
        )`);
    }
    const ledgerExists = hadLedger || (!opts.dryRun && !opts.status);
    const ledger: LedgerRow[] = ledgerExists
      ? (await sql.unsafe(`select version, checksum, baseline from ${LEDGER}`)) as unknown as LedgerRow[]
      : [];
    const actions = plan(files, ledger, baseline);
    for (const a of actions) console.log(describe(a));
    const mismatches = actions.filter((a) => a.kind === "mismatch");
    if (mismatches.length) {
      console.error(`\n${mismatches.length} applied migration(s) changed on disk. An applied migration is history; write a new one.`);
      return 1;
    }
    const todo = actions.filter((a): a is Extract<PlanAction, { kind: "apply" | "stamp" }> => a.kind === "apply" || a.kind === "stamp");
    if (opts.status || opts.dryRun) {
      console.log(`\n${todo.length} pending (${opts.status ? "status" : "dry run"}, nothing applied)`);
      return 0;
    }
    if (!todo.length) {
      console.log("\nnothing to do");
      return 0;
    }
    const locked = (await sql`select pg_try_advisory_lock(${LOCK_KEY}) as ok`)[0]!["ok"] as boolean;
    if (!locked) {
      console.error("another migrate run holds the lock on this database");
      return 1;
    }
    try {
      // Stamps happen only on an empty ledger (lib/migrations.ts plan()), and
      // all of them or none: a first run that died half-way through would leave
      // a ledger that is no longer empty, and the rerun would try to apply the
      // rest of what schema.sql already contains.
      const stamps = todo.filter((a) => a.kind === "stamp");
      if (stamps.length) {
        await sql.begin(async (tx) => {
          for (const { migration: m } of stamps) {
            await tx.unsafe(`insert into ${LEDGER} (version, name, checksum, duration_ms, baseline) values ($1, $2, $3, 0, true)`, [m.version, m.name, m.checksum]);
          }
        });
        for (const { migration: m } of stamps) console.log(`stamped  ${m.file}`);
      }
      for (const a of todo) {
        if (a.kind === "stamp") continue;
        const m = a.migration;
        const t0 = performance.now();
        if (m.noTransaction) {
          // Statements run one by one outside a transaction (CREATE INDEX
          // CONCURRENTLY refuses to run inside one). A failure half-way leaves
          // the earlier statements in place and no ledger row: rerun after
          // fixing the file, which must therefore be idempotent.
          await sql.unsafe(m.body);
          await sql.unsafe(`insert into ${LEDGER} (version, name, checksum, duration_ms) values ($1, $2, $3, $4)`, [m.version, m.name, m.checksum, Math.round(performance.now() - t0)]);
        } else {
          await sql.begin(async (tx) => {
            await tx.unsafe(m.body);
            await tx.unsafe(`insert into ${LEDGER} (version, name, checksum, duration_ms) values ($1, $2, $3, $4)`, [m.version, m.name, m.checksum, Math.round(performance.now() - t0)]);
          });
        }
        console.log(`applied  ${m.file}  ${Math.round(performance.now() - t0)} ms`);
      }
    } finally {
      await sql`select pg_advisory_unlock(${LOCK_KEY})`;
    }
    const applied = todo.filter((a) => a.kind === "apply").length;
    const stamped = todo.length - applied;
    console.log(`\n${applied} applied, ${stamped} stamped`);
    return 0;
  } finally {
    await sql.end({ timeout: 5 });
  }
}

if (import.meta.main) {
  const args = new Set(Bun.argv.slice(2));
  const known = new Set(["--dry-run", "--status", "--allow-prod"]);
  const unknown = [...args].filter((a) => !known.has(a));
  if (unknown.length) {
    console.error(`unknown argument(s): ${unknown.join(" ")}\nusage: bun run migrate [--dry-run] [--status] [--allow-prod]`);
    process.exit(2);
  }
  process.exit(await migrate({ dryRun: args.has("--dry-run"), status: args.has("--status"), allowProd: args.has("--allow-prod") }));
}
