import { describe, test, expect } from "bun:test";
import { mkdtemp } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { spawn } from "../lib/subprocess.ts";
import { browserRenders, sniffMime, toBrowserImage } from "./pdf.ts";

const hasMagick = await spawn(["convert", "-version"]).then(() => true, () => false);

describe("browserRenders", () => {
  test("the inline-viewable set", () => {
    for (const m of ["image/jpeg", "image/png", "image/webp", "image/gif", "image/svg+xml", "image/avif"]) expect(browserRenders(m)).toBe(true);
    for (const m of ["image/tiff", "image/bmp", "image/heic", "application/pdf", ""]) expect(browserRenders(m)).toBe(false);
  });
});

describe.if(hasMagick)("toBrowserImage", () => {
  test("a bilevel TIFF (archive drawing) becomes a PNG; the PNG is then left alone", async () => {
    const dir = await mkdtemp(join(tmpdir(), "fm-pdf-test-"));
    const tiff = join(dir, "drawing.tiff");
    await spawn(["convert", "-size", "40x30", "xc:white", "-monochrome", tiff]);
    expect(await sniffMime(tiff)).toBe("image/tiff");

    const out = await toBrowserImage(tiff, dir);
    expect(out.converted).toBe(true);
    expect(out.mime).toBe("image/png");
    expect(out.path.endsWith("drawing.png")).toBe(true);
    expect(await sniffMime(out.path)).toBe("image/png");

    const again = await toBrowserImage(out.path, dir);
    expect(again.converted).toBe(false);
    expect(again.path).toBe(out.path);
  });

  test("a colour TIFF (photo) becomes a JPEG", async () => {
    const dir = await mkdtemp(join(tmpdir(), "fm-pdf-test-"));
    const tiff = join(dir, "photo.tiff");
    await spawn(["convert", "-size", "40x30", "gradient:red-blue", "-type", "TrueColor", tiff]);
    const out = await toBrowserImage(tiff, dir);
    expect(out.mime).toBe("image/jpeg");
    expect(out.path.endsWith("photo.jpg")).toBe(true);
  });
});
