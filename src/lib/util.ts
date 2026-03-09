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
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }
  await Bun.write(destPath, response);
}
