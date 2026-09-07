import { extname } from "node:path";

export const FILE_ALLOWED_EXTENSIONS = [
  ".geojson",
  ".gpkg",
  ".shp",
  ".zip",
  ".csv",
];
export const FILE_MIN_SIZE = 1024; // 1 KB

export function validateFileSize(filePath: string, minSize: number): void {
  const size = Bun.file(filePath).size;
  if (size < minSize) {
    throw new Error(`File is below the minimum size (${size} < ${minSize})`);
  }
}

export function validateFileExtension(
  filePath: string,
  allowed: string[]
): void {
  const ext = extname(filePath).toLowerCase();
  if (!allowed.includes(ext)) {
    throw new Error(`File extension '${ext}' is not allowed`);
  }
}

export function datePath(
  withMonth = true,
  withDay = true
): string {
  const now = new Date();
  const year = now.getFullYear().toString();
  const month = now
    .toLocaleString("en", { month: "short" })
    .toLowerCase();
  const day = now.getDate().toString().padStart(2, "0");

  let path = year;
  if (withMonth) path += `/${month}`;
  if (withDay) path += `/${day}`;
  return path;
}

export async function collectFilesWithExtension(
  directory: string,
  extension: string
): Promise<string[]> {
  const glob = new Bun.Glob(`**/*${extension}`);
  const results: string[] = [];
  for await (const path of glob.scan({ cwd: directory, absolute: true })) {
    results.push(path);
  }
  return results;
}

export async function httpDownloadFile(
  url: string,
  destPath: string
): Promise<void> {
  await withRetry(async () => {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    await Bun.write(destPath, response);
  });
}

/**
 * Executes an async function with exponential backoff retries.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: { maxAttempts?: number; delay?: number } = {}
): Promise<T> {
  const maxAttempts = options.maxAttempts ?? 3;
  const delay = options.delay ?? 1000;

  let lastError: Error | unknown;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      lastError = e;
      if (attempt < maxAttempts) {
        const backoff = delay * Math.pow(2, attempt - 1);
        await Bun.sleep(backoff);
      }
    }
  }
  throw lastError;
}

const DUTCH_MONTHS: Record<string, number> = {
  januari: 1, jan: 1, februari: 2, feb: 2, maart: 3, mrt: 3, april: 4, apr: 4, mei: 5,
  juni: 6, jun: 6, juli: 7, jul: 7, augustus: 8, aug: 8, september: 9, sep: 9, sept: 9,
  oktober: 10, okt: 10, november: 11, nov: 11, december: 12, dec: 12,
};

/**
 * A report date as YYYY-MM-DD, or null. The prompt asks for ISO and mostly
 * gets it; the rest is what Dutch reports print: "12-03-2021", "12 maart 2021",
 * "maart 2021" (-> the 1st). A year outside 1900..next year is a misread, not a
 * date.
 */
export function normaliseDocumentDate(raw: string): string | null {
  const t = raw.trim().toLowerCase();
  let y: number | undefined, m: number | undefined, d: number | undefined;
  let x: RegExpMatchArray | null;
  if ((x = t.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/))) [y, m, d] = [+x[1]!, +x[2]!, +x[3]!];
  else if ((x = t.match(/^(\d{4})-(\d{1,2})$/))) [y, m, d] = [+x[1]!, +x[2]!, 1];
  else if ((x = t.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})/))) [y, m, d] = [+x[3]!, +x[2]!, +x[1]!];
  else if ((x = t.match(/^(?:(\d{1,2})\s+)?([a-z]+)\.?\s+(\d{4})/)) && DUTCH_MONTHS[x[2]!]) [y, m, d] = [+x[3]!, DUTCH_MONTHS[x[2]!]!, x[1] ? +x[1] : 1];
  else if ((x = t.match(/^(\d{4})$/))) [y, m, d] = [+x[1]!, 1, 1];
  if (!y || !m || !d) return null;
  if (y < 1900 || y > new Date().getFullYear() + 1 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  // 31-02 is a misread too: the calendar decides, not the regex.
  if (new Date(Date.UTC(y, m - 1, d)).getUTCDate() !== d) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}
