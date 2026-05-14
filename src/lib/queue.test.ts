import { describe, test, expect } from "bun:test";
import { concurrentMap } from "./queue.ts";

// concurrentMap is the worker's parallelism primitive — it drives the
// MAX_CONCURRENT cap and the (separate) MAX_TILESET_WORKERS cap inside
// tileset rendering. A regression that lets concurrency exceed the cap
// would silently re-introduce the OOM landmine that MAX_TILESET_WORKERS=1
// was added to prevent (see CLAUDE.md "Operational constraints").

describe("concurrentMap", () => {
  test("returns 0/0 for an empty input", async () => {
    const result = await concurrentMap([], 3, async () => true);
    expect(result).toEqual({ ok: 0, failed: 0 });
  });

  test("counts successes and failures from the fn return value", async () => {
    const result = await concurrentMap([1, 2, 3, 4, 5], 2, async (n) => n % 2 === 1);
    expect(result).toEqual({ ok: 3, failed: 2 });
  });

  test("counts thrown errors as failures", async () => {
    const result = await concurrentMap([1, 2, 3], 2, async (n) => {
      if (n === 2) throw new Error("boom");
      return true;
    });
    expect(result).toEqual({ ok: 2, failed: 1 });
  });

  test("never exceeds the maxConcurrent ceiling", async () => {
    let inFlight = 0;
    let peak = 0;
    const items = Array.from({ length: 20 }, (_, i) => i);

    await concurrentMap(items, 4, async () => {
      inFlight++;
      peak = Math.max(peak, inFlight);
      await Bun.sleep(5);
      inFlight--;
      return true;
    });

    expect(peak).toBeLessThanOrEqual(4);
    expect(peak).toBe(4); // 20 items / 4-wide ⇒ must hit the cap
  });

  test("respects maxConcurrent = 1 (serialized)", async () => {
    let inFlight = 0;
    let peak = 0;

    await concurrentMap([1, 2, 3, 4], 1, async () => {
      inFlight++;
      peak = Math.max(peak, inFlight);
      await Bun.sleep(2);
      inFlight--;
      return true;
    });

    expect(peak).toBe(1);
  });

  test("processes every item even when some throw", async () => {
    const seen: number[] = [];
    await concurrentMap([1, 2, 3, 4, 5], 2, async (n) => {
      seen.push(n);
      if (n === 3) throw new Error("boom");
      return true;
    });
    expect(seen.sort()).toEqual([1, 2, 3, 4, 5]);
  });
});
