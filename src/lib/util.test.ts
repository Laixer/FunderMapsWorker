import { describe, test, expect } from "bun:test";
import {
  FILE_ALLOWED_EXTENSIONS,
  validateFileExtension,
  withRetry,
} from "./util.ts";

describe("validateFileExtension", () => {
  for (const ext of FILE_ALLOWED_EXTENSIONS) {
    test(`accepts ${ext}`, () => {
      expect(() => validateFileExtension(`/tmp/foo${ext}`, FILE_ALLOWED_EXTENSIONS)).not.toThrow();
    });
    test(`accepts ${ext.toUpperCase()} (case-insensitive)`, () => {
      expect(() => validateFileExtension(`/tmp/foo${ext.toUpperCase()}`, FILE_ALLOWED_EXTENSIONS)).not.toThrow();
    });
  }

  test("rejects extension not in allowed list", () => {
    expect(() => validateFileExtension("/tmp/foo.exe", FILE_ALLOWED_EXTENSIONS)).toThrow(
      /extension '\.exe' is not allowed/,
    );
  });

  test("rejects extensionless paths", () => {
    expect(() => validateFileExtension("/tmp/README", FILE_ALLOWED_EXTENSIONS)).toThrow(
      /extension '' is not allowed/,
    );
  });

  test("rejects against an empty allow-list", () => {
    expect(() => validateFileExtension("/tmp/foo.geojson", [])).toThrow();
  });
});

describe("withRetry", () => {
  test("returns the value when fn succeeds on first attempt", async () => {
    let calls = 0;
    const result = await withRetry(async () => {
      calls++;
      return "ok";
    });
    expect(result).toBe("ok");
    expect(calls).toBe(1);
  });

  test("retries up to maxAttempts before throwing", async () => {
    let calls = 0;
    await expect(
      withRetry(
        async () => {
          calls++;
          throw new Error(`boom ${calls}`);
        },
        { maxAttempts: 3, delay: 1 },
      ),
    ).rejects.toThrow(/boom 3/);
    expect(calls).toBe(3);
  });

  test("succeeds on the last allowed attempt", async () => {
    let calls = 0;
    const result = await withRetry(
      async () => {
        calls++;
        if (calls < 3) throw new Error("not yet");
        return 42;
      },
      { maxAttempts: 3, delay: 1 },
    );
    expect(result).toBe(42);
    expect(calls).toBe(3);
  });

  test("propagates the final error (not the first one)", async () => {
    let calls = 0;
    await expect(
      withRetry(
        async () => {
          calls++;
          throw new Error(`attempt-${calls}`);
        },
        { maxAttempts: 2, delay: 1 },
      ),
    ).rejects.toThrow("attempt-2");
  });
});
