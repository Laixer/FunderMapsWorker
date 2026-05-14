import { describe, test, expect } from "bun:test";
import { spawn } from "./subprocess.ts";

// `spawn` wraps every GDAL/tippecanoe invocation made by the worker.
// The two guarantees that matter operationally:
//   1. A misbehaving subprocess can be timed out and killed.
//   2. Captured output is bounded (1 MB ring buffer) so a chatty tool
//      doesn't OOM the worker before its own MAX_TILESET_WORKERS cap.
//
// Tests use system binaries available on Linux CI runners and the dev
// VM (per CLAUDE.md the VM is the test env; runner is ubuntu-latest).

describe("spawn — exit codes", () => {
  test("captures exit code 0 from a successful command", async () => {
    const result = await spawn(["true"]);
    expect(result.exitCode).toBe(0);
  });

  test("captures non-zero exit code from a failing command", async () => {
    const result = await spawn(["false"]);
    expect(result.exitCode).not.toBe(0);
  });

  test("propagates an explicit non-zero exit code", async () => {
    const result = await spawn(["sh", "-c", "exit 42"]);
    expect(result.exitCode).toBe(42);
  });
});

describe("spawn — stdout/stderr capture", () => {
  test("captures stdout and trims trailing whitespace", async () => {
    const result = await spawn(["echo", "hello world"]);
    expect(result.stdout).toBe("hello world");
    expect(result.stderr).toBe("");
  });

  test("captures stderr separately from stdout", async () => {
    const result = await spawn([
      "sh",
      "-c",
      "echo to-out; echo to-err >&2",
    ]);
    expect(result.stdout).toBe("to-out");
    expect(result.stderr).toBe("to-err");
  });

  test("captures both streams on failure", async () => {
    const result = await spawn([
      "sh",
      "-c",
      "echo before-fail; echo err-msg >&2; exit 7",
    ]);
    expect(result.exitCode).toBe(7);
    expect(result.stdout).toBe("before-fail");
    expect(result.stderr).toBe("err-msg");
  });
});

describe("spawn — env merging", () => {
  test("merges custom env vars on top of process.env", async () => {
    const result = await spawn(
      ["sh", "-c", "echo \"$MY_TEST_VAR:$PATH_EXISTS\""],
      { env: { MY_TEST_VAR: "injected", PATH_EXISTS: process.env["PATH"] ? "yes" : "no" } },
    );
    expect(result.stdout).toBe("injected:yes");
  });

  test("custom env var overrides inherited one with the same name", async () => {
    const result = await spawn(
      ["sh", "-c", "echo $HOME"],
      { env: { HOME: "/override/path" } },
    );
    expect(result.stdout).toBe("/override/path");
  });
});

describe("spawn — timeout", () => {
  test("kills a process that exceeds the timeout", async () => {
    const start = Date.now();
    const result = await spawn(["sleep", "30"], { timeout: 100 });
    const elapsed = Date.now() - start;

    // Killed by SIGKILL → non-zero exit. Should return well under the
    // 30-second sleep, with a healthy margin for CI jitter.
    expect(result.exitCode).not.toBe(0);
    expect(elapsed).toBeLessThan(5000);
  });

  test("does not kill a process that finishes before the timeout", async () => {
    const result = await spawn(["echo", "fast"], { timeout: 5000 });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("fast");
  });

  test("timer is cleared after successful exit (no late kill of next call)", async () => {
    // If the timer from the first call isn't cleared, it could fire
    // during the second call. Run two short calls back-to-back with
    // a timeout longer than both combined.
    const a = await spawn(["echo", "first"], { timeout: 2000 });
    const b = await spawn(["echo", "second"], { timeout: 2000 });
    expect(a.stdout).toBe("first");
    expect(b.stdout).toBe("second");
    expect(a.exitCode).toBe(0);
    expect(b.exitCode).toBe(0);
  });
});

describe("spawn — output bounding (1 MB ring buffer)", () => {
  test("caps captured stdout at ~1 MB even when the process emits more", async () => {
    // `yes x | head -c 2_500_000` emits 2.5 MB of "x\n" lines. The
    // wrapper should retain only the trailing 1 MB.
    const result = await spawn([
      "sh",
      "-c",
      "yes x | head -c 2500000",
    ]);
    expect(result.exitCode).toBe(0);
    // Allow some slack — the trim happens chunk-by-chunk, so the final
    // size is between 1 MB and 1 MB + one read chunk.
    expect(result.stdout.length).toBeGreaterThanOrEqual(1024 * 1024 - 100);
    expect(result.stdout.length).toBeLessThan(1024 * 1024 + 256 * 1024);
  });
});
