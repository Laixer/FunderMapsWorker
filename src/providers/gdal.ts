import { spawn } from "../lib/subprocess.ts";
import { pgConnectionString } from "../db.ts";
import { extname } from "node:path";

let cachedVersion: [number, number, number] | null = null;

export async function gdalVersion(): Promise<[number, number, number]> {
  if (cachedVersion) return cachedVersion;

  const result = await spawn(["ogr2ogr", "--version"]);
  const versionStr = result.stdout.split(" ")[1]?.replace(",", "") ?? "0.0.0";
  const [major, minor, patch] = versionStr.split(".").map(Number) as [
    number,
    number,
    number,
  ];
  cachedVersion = [major, minor, patch];
  return cachedVersion;
}

export async function fromPostgis(
  output: string,
  ...args: string[]
): Promise<void> {
  const input = pgConnectionString();
  await ogr2ogr(input, output, ...args);
}

export async function toPostgis(
  input: string,
  ...args: string[]
): Promise<void> {
  const output = pgConnectionString();
  await ogr2ogr(input, output, ...args);
}

export async function ogr2ogr(
  input: string,
  output: string,
  ...args: string[]
): Promise<void> {
  let driver: string;
  if (output.startsWith("PG:")) {
    driver = "PostgreSQL";
  } else if (output.endsWith(".gpkg")) {
    driver = "GPKG";
  } else if (output.endsWith(".geojson")) {
    driver = "GeoJSONSeq";
  } else {
    throw new Error("Unsupported output format");
  }

  const cmdArgs: string[] = ["-overwrite"];

  const version = await gdalVersion();
  if (version[0] < 3) {
    throw new Error("GDAL version 3.0.0 or higher is required");
  }

  if (version[0] === 3 && version[1] === 8) {
    cmdArgs.push("--config", "OGR2OGR_USE_ARROW_API", "NO");
  }

  const ext = extname(input).toLowerCase();
  if (ext === ".csv") {
    const name = input.toLowerCase();
    if (name.includes("semicolon")) {
      cmdArgs.push("-oo", "SEPARATOR=SEMICOLON");
    } else if (name.includes("pipe")) {
      cmdArgs.push("-oo", "SEPARATOR=PIPE");
    }
  }

  let actualInput = input;
  if (ext === ".zip") {
    actualInput = `/vsizip/${input}`;
  }

  const cmd = [
    "ogr2ogr",
    ...cmdArgs,
    "-f",
    driver,
    output,
    actualInput,
    ...args,
  ];

  // PostGIS downloads of large tables (10M+ rows) can take 20+ minutes
  const isPostgis = input.startsWith("PG:") || output.startsWith("PG:");
  const timeout = isPostgis ? 7_200_000 : 3_600_000;

  const result = await spawn(cmd, { timeout });
  if (result.exitCode !== 0) {
    throw new Error(`ogr2ogr failed: ${result.stderr}`);
  }
}
