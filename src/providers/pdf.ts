import { spawn } from "../lib/subprocess.ts";
import { join } from "node:path";
import { readdir, unlink, rename } from "node:fs/promises";

/**
 * Poppler wrappers for the Data Ops document lanes.
 *
 * The one rule worth stating up front, because everything else follows from it:
 *
 *   A scanned page contributes NO text layer. Anything pdftotext can read on a
 *   scan was added digitally afterwards -- by the person who prepared the file,
 *   on top of the scan. On a born-digital report the opposite holds: the text
 *   layer IS the document.
 *
 * So the same operation means different things per lane, and the lane has to be
 * decided before anything is stripped. See classifyPages / redactPage.
 */

export interface WordBox {
  x0: number; y0: number; x1: number; y1: number;
}

export async function pageCount(pdfPath: string): Promise<number> {
  const r = await spawn(["pdfinfo", pdfPath]);
  const m = r.stdout.match(/^Pages:\s+(\d+)/m);
  if (!m) throw new Error(`pdfinfo could not read ${pdfPath}`);
  return Number(m[1]);
}

export async function producer(pdfPath: string): Promise<string> {
  const r = await spawn(["pdfinfo", pdfPath]);
  return r.stdout.match(/^Producer:\s+(.*)$/m)?.[1]?.trim() ?? "";
}

export async function pageText(
  pdfPath: string,
  page: number,
  layout = true
): Promise<string> {
  const args = ["pdftotext"];
  if (layout) args.push("-layout");
  args.push("-f", String(page), "-l", String(page), pdfPath, "-");
  const r = await spawn(args);
  return r.stdout;
}

export async function documentText(pdfPath: string, from = 1): Promise<string> {
  const pages = await pageCount(pdfPath);
  const parts: string[] = [];
  for (let p = from; p <= pages; p++) {
    const t = await pageText(pdfPath, p);
    if (t.trim().length === 0) continue;
    parts.push(`\n--- pagina ${p} ---\n${t}`);
  }
  return parts.join("");
}

/** Bounding boxes, in PDF points, of every word the text layer holds. */
export async function wordBoxes(pdfPath: string, page: number): Promise<WordBox[]> {
  const r = await spawn([
    "pdftotext", "-bbox", "-f", String(page), "-l", String(page), pdfPath, "-",
  ]);
  return [
    ...r.stdout.matchAll(
      /<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)"/g
    ),
  ].map((m) => ({
    x0: Number(m[1]), y0: Number(m[2]), x1: Number(m[3]), y1: Number(m[4]),
  }));
}

export async function pageSize(
  pdfPath: string,
  page: number
): Promise<{ width: number; height: number }> {
  const r = await spawn(["pdfinfo", "-f", String(page), "-l", String(page), pdfPath]);
  const m =
    r.stdout.match(/Page\s+\d+\s+size:\s+([\d.]+)\s+x\s+([\d.]+)/) ??
    r.stdout.match(/Page size:\s+([\d.]+)\s+x\s+([\d.]+)/);
  return m
    ? { width: Number(m[1]), height: Number(m[2]) }
    : { width: 595, height: 842 };
}

export interface RenderedPage {
  page: number;
  path: string;
  /** words whited out on this page; 0 means the page was already clean */
  redacted: number;
  /** the text that was removed, if any -- kept, never sent to a model */
  annotation: string;
}

/**
 * Render one page to JPEG with every text-layer region painted out.
 *
 * On a pure scan this is a no-op: there are no boxes, nothing is painted, the
 * image is the photograph of the drawing. On a page carrying a preparer's
 * caption the caption disappears and the drawing underneath survives.
 *
 * Do not call this on the text lane. A born-digital report is all text layer,
 * and blanking it would erase the document.
 */
export async function redactPage(
  pdfPath: string,
  page: number,
  outDir: string,
  longEdge = 1600
): Promise<RenderedPage> {
  const prefix = join(outDir, `raw-${page}`);
  await spawn([
    "pdftoppm", "-jpeg", "-jpegopt", "quality=80",
    "-scale-to", String(longEdge),
    "-f", String(page), "-l", String(page), pdfPath, prefix,
  ]);

  const made = (await readdir(outDir)).filter((f) => f.startsWith(`raw-${page}-`));
  if (made.length === 0) throw new Error(`pdftoppm produced nothing for page ${page}`);
  const src = join(outDir, made[0]!);
  const dst = join(outDir, `p-${String(page).padStart(3, "0")}.jpg`);

  const boxes = await wordBoxes(pdfPath, page);
  if (boxes.length === 0) {
    await rename(src, dst);
    return { page, path: dst, redacted: 0, annotation: "" };
  }

  const annotation = (await pageText(pdfPath, page)).trim();
  const { width, height } = await pageSize(pdfPath, page);
  await paintOut(src, dst, boxes, width, height);
  await unlink(src).catch(() => {});
  return { page, path: dst, redacted: boxes.length, annotation };
}

/**
 * Paint white rectangles over the given PDF-point boxes.
 *
 * Bun has no image library, and pulling one in for six rectangles is not worth
 * a dependency, so this goes through ImageMagick if present and falls back to a
 * hard failure rather than silently shipping an unredacted page. Shipping one
 * would hand a model the answer, which is the failure mode this whole pipeline
 * exists to avoid.
 */
async function paintOut(
  src: string, dst: string, boxes: WordBox[], pw: number, ph: number
): Promise<void> {
  const probe = await spawn(["identify", "-format", "%w %h", src]).catch(() => null);
  if (!probe) {
    throw new Error(
      "ImageMagick (`identify`/`convert`) is required to redact a page; refusing to emit an unredacted image"
    );
  }
  const [iw, ih] = probe.stdout.trim().split(/\s+/).map(Number) as [number, number];
  const sx = iw / pw, sy = ih / ph;
  const pad = 4;

  const draws = boxes.flatMap((b) => [
    "-draw",
    `rectangle ${Math.max(0, b.x0 * sx - pad)},${Math.max(0, b.y0 * sy - pad)} ` +
      `${b.x1 * sx + pad},${b.y1 * sy + pad}`,
  ]);

  await spawn(["convert", src, "-fill", "white", "-stroke", "none", ...draws, dst]);
}

/** A page with essentially no text layer is a scan; with plenty, a typed document. */
export function looksScanned(textChars: number): boolean {
  return textChars < 200;
}
