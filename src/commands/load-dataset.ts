import { log, ACCENT, RESET } from "../lib/log.ts";
import { toPostgis } from "../providers/gdal.ts";
import * as s3 from "../providers/s3.ts";
import {
  httpDownloadFile,
  validateFileSize,
  validateFileExtension,
  FILE_ALLOWED_EXTENSIONS,
  FILE_MIN_SIZE,
} from "../lib/util.ts";
import { mkdtemp, rm } from "node:fs/promises";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";

export async function loadDataset(payload: {
  dataset_input: string;
  layer?: string[];
  delete_after?: boolean;
  tmp_dir?: string;
}): Promise<boolean> {
  const { dataset_input, layer = [], delete_after = false } = payload;

  if (!dataset_input) {
    throw new Error("Missing required field 'dataset_input'");
  }

  const workDir =
    payload.tmp_dir ?? await mkdtemp(join(tmpdir(), "fm-load-"));
  const fileName = basename(dataset_input);
  let localPath = join(workDir, fileName);

  try {
    if (
      dataset_input.startsWith("https://") ||
      dataset_input.startsWith("http://")
    ) {
      log.step(`Downloading from URL`);
      await httpDownloadFile(dataset_input, localPath);
    } else if (dataset_input.startsWith("s3://")) {
      log.step(`Downloading from S3`);
      const s3Path = dataset_input.replace("s3://", "");
      await s3.downloadFile(localPath, s3Path);
    } else {
      if (!(await Bun.file(dataset_input).exists())) {
        log.error(`Local file not found: ${dataset_input}`);
        return false;
      }
      localPath = dataset_input;
    }

    log.step(`Validating ${ACCENT.type}${fileName}${RESET}`);
    validateFileSize(localPath, FILE_MIN_SIZE);
    validateFileExtension(localPath, FILE_ALLOWED_EXTENSIONS);

    log.step(`Loading into PostGIS`);
    await toPostgis(localPath, ...layer);

    if (delete_after && dataset_input.startsWith("s3://")) {
      try {
        const s3Path = dataset_input.replace("s3://", "");
        await s3.deleteFile(s3Path);
      } catch (e) {
        log.warn("Failed to delete S3 file after load", { error: String(e) });
      }
    }

    log.info(`${ACCENT.ok}✓${RESET} Dataset loaded`);
    return true;
  } catch (e) {
    log.error("Failed to load dataset", { error: String(e) });
    return false;
  } finally {
    if (!payload.tmp_dir) {
      await rm(workDir, { recursive: true, force: true });
    }
  }
}
