import { describe as d, expect, test } from "bun:test";
import { hasNoTransactionHeader, parseMigrationFileName, plan, sha256Hex, toMigrationFile, type LedgerRow } from "./migrations.ts";

const mk = (file: string, body = `-- ${file}\nselect 1;`) => toMigrationFile(file, body);

d("migration file names", () => {
  test("accepts <YYYYMMDD>_<NNN>_<snake>.sql and nothing else", () => {
    expect(parseMigrationFileName("20260917_001_reviewer_extraction_unique.sql")).toEqual({ version: "20260917_001", name: "reviewer_extraction_unique" });
    expect(parseMigrationFileName("2026_09_17_x.sql")).toBeNull();
    expect(parseMigrationFileName("20260917_001_Has-Dash.sql")).toBeNull();
    expect(parseMigrationFileName("README.md")).toBeNull();
  });

  test("no-transaction header is only honoured in the first lines", () => {
    expect(hasNoTransactionHeader("-- migrate: no-transaction\ncreate index concurrently x on t (c);")).toBe(true);
    expect(hasNoTransactionHeader("-- something\n-- migrate:no-transaction\n")).toBe(true);
    expect(hasNoTransactionHeader("select 1;\n\n\n\n\n\n-- migrate: no-transaction")).toBe(false);
  });

  test("checksum is the sha256 of the body", async () => {
    expect(await sha256Hex("")).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  });
});

d("plan", () => {
  test("fresh database, nothing folded: everything applies, oldest first", async () => {
    const files = [await mk("20260918_001_b.sql"), await mk("20260917_001_a.sql")];
    const p = plan(files, [], "0");
    expect(p.map((a) => a.kind)).toEqual(["apply", "apply"]);
    expect(p.map((a) => (a.kind === "apply" ? a.migration.version : ""))).toEqual(["20260917_001", "20260918_001"]);
  });

  test("fresh database with a baseline: folded versions are stamped, later ones applied", async () => {
    const files = [await mk("20260917_001_a.sql"), await mk("20260918_001_b.sql")];
    const p = plan(files, [], "20260917_001");
    expect(p.map((a) => a.kind)).toEqual(["stamp", "apply"]);
  });

  test("a live ledger never stamps: a file below BASELINE that it does not know is applied (Worker #169)", async () => {
    // Prod on 2026-09-18: _001.._004 applied, BASELINE moved to _004 by the
    // regen, and a PR numbered _002 merges late. It must run, not be recorded.
    const files = [await mk("20260918_001_a.sql"), await mk("20260918_002_late.sql"), await mk("20260918_004_c.sql")];
    const ledger: LedgerRow[] = [
      { version: "20260918_001", checksum: files[0]!.checksum, baseline: false },
      { version: "20260918_004", checksum: files[2]!.checksum, baseline: false },
    ];
    const p = plan(files, ledger, "20260918_004");
    expect(p.map((a) => a.kind)).toEqual(["ok", "apply", "ok"]);
  });

  test("a database bootstrapped from an older schema.sql applies what a newer BASELINE folded", async () => {
    // Bootstrapped when BASELINE was _001 (one stamped row, nothing executed),
    // then main moves BASELINE to _003. This database never got _002 and _003.
    const files = [await mk("20260918_001_a.sql"), await mk("20260918_002_b.sql"), await mk("20260918_003_c.sql")];
    const ledger: LedgerRow[] = [{ version: "20260918_001", checksum: files[0]!.checksum, baseline: true }];
    const p = plan(files, ledger, "20260918_003");
    expect(p.map((a) => a.kind)).toEqual(["ok", "apply", "apply"]);
  });

  test("applied and unchanged is ok; an edited applied file is a mismatch", async () => {
    const a = await mk("20260917_001_a.sql");
    const ledger: LedgerRow[] = [{ version: a.version, checksum: a.checksum, baseline: false }];
    expect(plan([a], ledger, "0")[0]!.kind).toBe("ok");
    const edited = await mk("20260917_001_a.sql", "select 2;");
    expect(plan([edited], ledger, "0")[0]!.kind).toBe("mismatch");
  });

  test("a stamped row never mismatches: its checksum was never executed", async () => {
    const a = await mk("20260917_001_a.sql", "select 2;");
    const ledger: LedgerRow[] = [{ version: a.version, checksum: "not-the-file", baseline: true }];
    expect(plan([a], ledger, "20260917_001")[0]!.kind).toBe("ok");
  });

  test("a ledger row without a file is reported, not fatal", async () => {
    const p = plan([], [{ version: "20260101_001", checksum: "x", baseline: false }], "0");
    expect(p).toEqual([{ kind: "missing-file", version: "20260101_001" }]);
  });

  test("two files with one version is an error", async () => {
    const files = [await mk("20260917_001_a.sql"), await mk("20260917_001_b.sql")];
    expect(() => plan(files, [], "0")).toThrow(/share version/);
  });
});
