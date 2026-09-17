/**
 * Schema migrations: the pure part. What is on disk, what the ledger says,
 * and what to do about the difference. No I/O here; src/commands/migrate.ts
 * reads the files and talks to Postgres.
 *
 * Contract (db/migrations/README.md):
 *   - a migration is db/migrations/<YYYYMMDD>_<NNN>_<name>.sql, forward-only;
 *   - the ledger is application.schema_migrations, one row per applied file,
 *     with the file's sha256 at the time it ran;
 *   - db/migrations/BASELINE names the last version that schema.sql already
 *     contains: a fresh database bootstrapped from schema.sql gets those
 *     versions stamped as applied instead of re-run.
 */

export interface MigrationFile {
  /** `20260917_001` — sorts chronologically, unique per file. */
  version: string;
  /** `reviewer_extraction_unique` */
  name: string;
  /** file name as found on disk */
  file: string;
  /** full SQL */
  body: string;
  /** sha256 hex of `body` */
  checksum: string;
  /** `-- migrate: no-transaction` on the first lines: run outside BEGIN/COMMIT (CREATE INDEX CONCURRENTLY). */
  noTransaction: boolean;
}

export interface LedgerRow {
  version: string;
  checksum: string;
  baseline: boolean;
}

export type PlanAction =
  | { kind: "apply"; migration: MigrationFile }
  | { kind: "stamp"; migration: MigrationFile }
  | { kind: "ok"; migration: MigrationFile }
  | { kind: "mismatch"; migration: MigrationFile; ledgerChecksum: string }
  | { kind: "missing-file"; version: string };

const FILE_RE = /^(\d{8}_\d{3})_([a-z0-9_]+)\.sql$/;

export function parseMigrationFileName(file: string): { version: string; name: string } | null {
  const m = FILE_RE.exec(file);
  return m ? { version: m[1]!, name: m[2]! } : null;
}

export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function hasNoTransactionHeader(body: string): boolean {
  return body
    .split("\n")
    .slice(0, 5)
    .some((l) => /^--\s*migrate:\s*no-transaction\s*$/.test(l.trim()));
}

export async function toMigrationFile(file: string, body: string): Promise<MigrationFile> {
  const parsed = parseMigrationFileName(file);
  if (!parsed) throw new Error(`not a migration file name: ${file} (want <YYYYMMDD>_<NNN>_<snake_name>.sql)`);
  return { ...parsed, file, body, checksum: await sha256Hex(body), noTransaction: hasNoTransactionHeader(body) };
}

/** Versions compare as strings; the fixed-width prefix makes that chronological. */
export function compareVersions(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * What to do, in order. Files are applied oldest first. A file at or below
 * the baseline that the ledger does not know is stamped, not run: schema.sql
 * already contains it. A ledger row whose checksum differs from the file is
 * a mismatch and stops everything: an applied migration must never change.
 * A ledger row without a file is reported but does not stop the run (the
 * README says how a folded migration is retired).
 */
export function plan(files: MigrationFile[], ledger: LedgerRow[], baseline: string): PlanAction[] {
  const byVersion = new Map(ledger.map((r) => [r.version, r]));
  const seen = new Set<string>();
  const out: PlanAction[] = [];
  const sorted = [...files].sort((a, b) => compareVersions(a.version, b.version));
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i]!.version === sorted[i - 1]!.version) {
      throw new Error(`two migrations share version ${sorted[i]!.version}: ${sorted[i - 1]!.file} and ${sorted[i]!.file}`);
    }
  }
  for (const m of sorted) {
    seen.add(m.version);
    const row = byVersion.get(m.version);
    if (row) {
      if (row.checksum !== m.checksum && !row.baseline) out.push({ kind: "mismatch", migration: m, ledgerChecksum: row.checksum });
      else out.push({ kind: "ok", migration: m });
    } else if (compareVersions(m.version, baseline) <= 0) {
      out.push({ kind: "stamp", migration: m });
    } else {
      out.push({ kind: "apply", migration: m });
    }
  }
  for (const r of ledger) if (!seen.has(r.version)) out.push({ kind: "missing-file", version: r.version });
  return out;
}

export function describe(a: PlanAction): string {
  switch (a.kind) {
    case "apply": return `apply    ${a.migration.file}${a.migration.noTransaction ? "  (no transaction)" : ""}`;
    case "stamp": return `stamp    ${a.migration.file}  (at or below BASELINE: schema.sql already has it)`;
    case "ok": return `ok       ${a.migration.file}`;
    case "mismatch": return `MISMATCH ${a.migration.file}: ledger sha256 ${a.ledgerChecksum.slice(0, 12)}…, file ${a.migration.checksum.slice(0, 12)}…`;
    case "missing-file": return `no file  ${a.version} is in the ledger but not on disk`;
  }
}
