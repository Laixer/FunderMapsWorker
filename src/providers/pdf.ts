import { spawn } from "../lib/subprocess.ts";
import { join, basename } from "node:path";
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

/** Above this many characters a page is a typed document, not an annotated scan. */
export const TEXT_PAGE_CHARS = 300;

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

export async function documentText(
  pdfPath: string,
  from = 1,
  skipPages: number[] = []
): Promise<string> {
  const pages = await pageCount(pdfPath);
  const skip = new Set(skipPages);
  const parts: string[] = [];
  for (let p = from; p <= pages; p++) {
    if (skip.has(p)) continue;          // a preparer's summary is not evidence
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

  // A page carrying a substantial text layer is not a scan with a caption on
  // it; it is a typed document, and its text is the evidence. Painting it out
  // destroys the page before anything reads it.
  //
  // This guard exists because the lane threshold is a hard cutoff on a
  // continuous quantity. Inquiry 130075 -- a 1979 Rotterdam funderingsonderzoek
  // stating "het funderingshout in goede staat was" -- carried 1,927 characters
  // against a 2,000-character threshold, was routed to the vision lane, had both
  // pages whited out, and was reported as blank. Seventy-three characters
  // decided whether a survey report was read or erased.
  //
  // Redaction may therefore only remove a caption from a page that is
  // otherwise empty, never the body of a typed one. Getting the lane wrong now
  // costs a worse reading, not the document.
  if (annotation.replace(/\s/g, "").length > TEXT_PAGE_CHARS) {
    await rename(src, dst);
    return { page, path: dst, redacted: 0, annotation: "" };
  }
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

/**
 * Prepare a loose image for the vision lane.
 *
 * Archive material does not always arrive as a PDF -- Het Utrechts Archief
 * hands out plain JPEGs, and a 6859x4883 scan of a 1920s drawing is a perfectly
 * ordinary thing to be sent. There is no text layer to strip, so redaction does
 * not apply; any caption burned into the pixels is caught by the classifier
 * instead, which is the same safety net that covers scanned-in cover sheets.
 */
export async function prepareImage(
  imagePath: string,
  outDir: string,
  longEdge = 1600
): Promise<RenderedPage> {
  const dst = join(outDir, "p-001.jpg");
  const probe = await spawn(["identify", "-format", "%w %h", imagePath]).catch(() => null);
  if (!probe) throw new Error(`not a readable image: ${imagePath}`);
  await spawn([
    "convert", imagePath, "-resize", `${longEdge}x${longEdge}>`,
    "-quality", "80", dst,
  ]);
  return { page: 1, path: dst, redacted: 0, annotation: "" };
}

/** Sniff the kind from content, never from the extension. */
export async function fileKind(path: string): Promise<"pdf" | "image" | "other"> {
  const r = await spawn(["file", "-b", "--mime-type", path]).catch(() => null);
  const mime = r?.stdout.trim() ?? "";
  if (mime === "application/pdf") return "pdf";
  if (mime.startsWith("image/")) return "image";
  return "other";
}

/**
 * Does this page's text look like the preparer's own summary sheet?
 *
 * Recognised by its template rather than by any ratio. An earlier version
 * guessed from size -- "a short page in front of a long document" -- and missed
 * every cover attached to a scan, because a scan contributes no text of its own
 * so the document never looked long. The model then read `Fundering: Niet
 * onderheid - gemetseld` straight off page 1 and scored a perfect match against
 * the human who wrote it.
 *
 * Two shapes exist in the corpus: the full FunderMaps sheet, and a bare typed
 * header of address / Bouwjaar / Fundering above a scan. Both label the
 * foundation, which is the thing that must never reach a model.
 */
export function looksLikeCoverSheet(text: string): boolean {
  const t = text.replace(/\s+/g, " ");
  const fundering = /\bFundering\s*:/i.test(t);
  const bouwjaar  = /\bBouwjaar\s*:/i.test(t);

  // The full FunderMaps sheet.
  if (/\bRapportage\s*:/i.test(t) && (fundering || bouwjaar)) return true;

  // The bare typed header above a scan: address, Bouwjaar, Fundering. Both
  // labels together, on a page with little else, is the signature.
  //
  // `Fundering:` ALONE is not enough. A construction drawing legitimately
  // carries an annotation block headed `PREFAB FUNDERING:` or similar, and an
  // earlier version of this rule threw those pages away whole -- turning a
  // confident, correct `concrete` into no answer at all.
  if (fundering && bouwjaar && t.length < 1200) return true;

  return false;
}

/** A page with essentially no text layer is a scan; with plenty, a typed document. */
export function looksScanned(textChars: number): boolean {
  return textChars < 200;
}

/** A2 and up: 1684 pt long edge for A2; A3 is 1191. Architects' sheets live here. */
export const LARGE_FORMAT_PT = 1500;

/**
 * Cut a rendered sheet into a grid of tiles. A0 drawing downscaled to one
 * 1600 px image loses the foundation detail entirely -- the doorsneden at the
 * bottom of an omgevingsvergunning sheet are a few hundred pixels wide at
 * that size. Tiles of a 4000 px render keep it legible; the full sheet is
 * still sent first so the model knows where each tile sits.
 */
export async function tileImage(
  imagePath: string,
  outDir: string,
  cols = 3,
  rows = 2
): Promise<string[]> {
  const prefix = join(outDir, `${basename(imagePath).replace(/\.[^.]+$/, "")}-tile`);
  await spawn([
    "convert", imagePath, "-crop", `${cols}x${rows}@`, "+repage", "-quality", "82", `${prefix}-%d.jpg`,
  ]);
  const out: string[] = [];
  for (let i = 0; i < cols * rows; i++) out.push(`${prefix}-${i}.jpg`);
  return out;
}
