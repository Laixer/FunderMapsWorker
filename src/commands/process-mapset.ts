import { sql } from "../db.ts";
import { log, ACCENT, RESET, formatDuration } from "../lib/log.ts";
import { concurrentMap } from "../lib/queue.ts";
import { fromPostgis, ogr2ogr } from "../providers/gdal.ts";
import { tippecanoe } from "../providers/tippecanoe.ts";
import * as s3 from "../providers/s3.ts";
import { env } from "../config.ts";
import {
  datePath,
  collectFilesWithExtension,
} from "../lib/util.ts";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

interface TileBundle {
  tileset: string;
  minZoom: number;
  maxZoom: number;
  uploadDataset: boolean;
  generateTiles: boolean;
}

const TILE_CACHE =
  "max-age=43200,s-maxage=300,stale-while-revalidate=300,stale-if-error=600";
const MAX_RETRIES = 3;
const RETRY_DELAY = 5_000;

async function downloadDataset(
  tileset: TileBundle,
  workDir: string
): Promise<boolean> {
  const outputFile = join(workDir, `${tileset.tileset}.gpkg`);

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      log.step(`Downloading '${ACCENT.type}${tileset.tileset}${RESET}' from PostGIS`);
      await fromPostgis(outputFile, `maplayer.${tileset.tileset}`);
      return true;
    } catch (e) {
      if (attempt < MAX_RETRIES) {
        log.warn(`Download attempt ${attempt} failed for ${tileset.tileset}, retrying...`);
        await Bun.sleep(RETRY_DELAY * attempt);
      } else {
        log.error(`Failed to download ${tileset.tileset} after ${MAX_RETRIES} attempts`, {
          error: String(e),
        });
        return false;
      }
    }
  }
  return false;
}

async function generateTileset(
  tileset: TileBundle,
  workDir: string
): Promise<boolean> {
  try {
    const gpkg = join(workDir, `${tileset.tileset}.gpkg`);
    const geojson = join(workDir, `${tileset.tileset}.geojson`);
    const tileDir = join(workDir, tileset.tileset);

    log.step(`Converting '${ACCENT.type}${tileset.tileset}${RESET}' to GeoJSON`);
    await ogr2ogr(gpkg, geojson);

    // Free GPKG memory before tippecanoe runs
    await rm(gpkg, { force: true });

    log.step(`Generating tiles for '${ACCENT.type}${tileset.tileset}${RESET}'`);
    await tippecanoe(geojson, tileDir, tileset.tileset, tileset.maxZoom, tileset.minZoom);

    // Free GeoJSON after tiles are generated
    await rm(geojson, { force: true });

    return true;
  } catch (e) {
    log.error(`Failed to generate tileset for ${tileset.tileset}`, { error: String(e) });
    return false;
  }
}

async function uploadDataset(
  tileset: TileBundle,
  workDir: string
): Promise<boolean> {
  try {
    log.step(`Uploading '${ACCENT.type}${tileset.tileset}${RESET}' dataset to S3`);
    const gpkg = join(workDir, `${tileset.tileset}.gpkg`);
    const s3Path = `mapset/${datePath()}/${tileset.tileset}.gpkg`;
    await s3.uploadFile(gpkg, s3Path, "fundermaps-data");
    return true;
  } catch (e) {
    log.error(`Failed to upload dataset for ${tileset.tileset}`, { error: String(e) });
    return false;
  }
}

async function uploadTiles(
  tileset: TileBundle,
  tileDir: string
): Promise<boolean> {
  try {
    log.step(`Uploading tiles for '${ACCENT.type}${tileset.tileset}${RESET}' to S3`);

    const jsonFiles = await collectFilesWithExtension(tileDir, ".json");
    if (jsonFiles.length > 0) {
      log.debug(`Removing ${jsonFiles.length} non-tile files`);
      for (const f of jsonFiles) {
        try { await Bun.file(f).delete(); } catch {}
      }
    }

    await s3.uploadDirectory(tileDir, tileset.tileset, "fundermaps-tileset", {
      CacheControl: TILE_CACHE,
      ContentType: "application/x-protobuf",
      ACL: "public-read",
    });
    return true;
  } catch (e) {
    log.error(`Failed to upload tiles for ${tileset.tileset}`, { error: String(e) });
    return false;
  }
}

async function processOne(tileset: TileBundle): Promise<boolean> {
  const start = performance.now();
  const workDir = await mkdtemp(join(tmpdir(), `fm-${tileset.tileset}-`));

  try {
    log.info(`${ACCENT.type}${tileset.tileset}${RESET} processing started`);

    if (!(await downloadDataset(tileset, workDir))) return false;

    if (tileset.uploadDataset) {
      if (!(await uploadDataset(tileset, workDir))) return false;
    }

    if (tileset.generateTiles) {
      if (!(await generateTileset(tileset, workDir))) return false;
      if (!(await uploadTiles(tileset, join(workDir, tileset.tileset)))) return false;
    }

    const elapsed = performance.now() - start;
    log.info(
      `${ACCENT.ok}✓${RESET} ${ACCENT.type}${tileset.tileset}${RESET} done in ${ACCENT.time}${formatDuration(elapsed)}${RESET}`
    );
    return true;
  } catch (e) {
    log.error(`${ACCENT.fail}✗${RESET} ${tileset.tileset} failed`, { error: String(e) });
    return false;
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
}

export async function processMapset(payload: {
  tileset?: string | string[];
  max_workers?: number;
}): Promise<boolean> {
  const requestedTilesets = payload.tileset
    ? Array.isArray(payload.tileset)
      ? payload.tileset
      : [payload.tileset]
    : [];
  const maxWorkers = payload.max_workers ?? env.MAX_TILESET_WORKERS ?? env.MAX_CONCURRENT;

  let bundles: TileBundle[];

  if (requestedTilesets.length > 0) {
    bundles = await sql<TileBundle[]>`
      SELECT tileset, zoom_min_level as "minZoom", zoom_max_level as "maxZoom",
             generate_tileset as "generateTiles", upload_dataset as "uploadDataset"
      FROM maplayer.bundle
      WHERE enabled = TRUE AND tileset IN ${sql(requestedTilesets)}
    `;
  } else {
    bundles = await sql<TileBundle[]>`
      SELECT tileset, zoom_min_level as "minZoom", zoom_max_level as "maxZoom",
             generate_tileset as "generateTiles", upload_dataset as "uploadDataset"
      FROM maplayer.bundle
      WHERE enabled = TRUE
    `;
  }

  if (bundles.length === 0) {
    log.warn("No matching tilesets found");
    return false;
  }

  log.info(
    `Processing ${ACCENT.job}${bundles.length}${RESET} tilesets with ${ACCENT.job}${maxWorkers}${RESET} workers`
  );

  // Sort alphabetically for deterministic ordering
  bundles.sort((a, b) => a.tileset.localeCompare(b.tileset));

  const { ok, failed } = await concurrentMap(bundles, maxWorkers, processOne);

  if (failed === 0) {
    log.info(`${ACCENT.ok}✓${RESET} All ${ACCENT.job}${ok}${RESET} tilesets processed`);
  } else {
    log.warn(
      `${ACCENT.ok}${ok}${RESET} succeeded, ${ACCENT.fail}${failed}${RESET} failed`
    );
  }
  return failed === 0;
}
