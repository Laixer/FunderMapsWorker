import { log } from "./log.ts";

export async function concurrentMap<T>(
  items: T[],
  maxConcurrent: number,
  fn: (item: T) => Promise<boolean>
): Promise<{ ok: number; failed: number }> {
  let running = 0;
  let ok = 0;
  let failed = 0;
  const queue = [...items];

  return new Promise((resolve) => {
    function next() {
      if (queue.length === 0 && running === 0) {
        resolve({ ok, failed });
        return;
      }

      while (running < maxConcurrent && queue.length > 0) {
        const item = queue.shift()!;
        running++;
        fn(item)
          .then((success) => {
            if (success) ok++;
            else failed++;
          })
          .catch((e) => {
            failed++;
            log.error("Concurrent task failed", { error: String(e) });
          })
          .finally(() => {
            running--;
            next();
          });
      }
    }
    next();
  });
}
