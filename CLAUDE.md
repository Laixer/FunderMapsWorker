# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FunderMaps Worker is the data-side repository of FunderMaps, built with **Bun** and **TypeScript**. It holds:

- the **database schema** (`schema.sql`, `db/migrations/`, `sql/`) — this repo owns it; no other repo runs migrations;
- **command-line tools** for data work (`src/commands/`): the BAG / 3DBAG / subsidence loader, the dossier ingest and its helpers, the migration runner;
- the **Windmill workspace mirror** (`windmill/`) and the **Windmill worker image** (`windmill-worker/`, Windmill + GDAL + DuckDB);
- the **tileserver** deploy config (`tileserver/`, Martin).

**There is no background worker any more.** Until 2026-10-12 this repo also ran a polling job processor on a droplet (`fundermaps-worker-0`) that read `application.worker_jobs`. Its last job, the GPKG archive export (`process_mapset`), now runs as the Windmill script `f/fundermaps/mapset/export_tileset`; the droplet, the queue loop, the container image and the queue table are gone (#147). The name "Worker" is history.

## Commands

```bash
bun install               # Install dependencies
bun test                  # Unit tests (src/**/*.test.ts)
bun run typecheck         # tsc --noEmit
bun run migrate           # Apply db/migrations/ (see db/migrations/README.md)
bun run load-dataset <dataset_input> [layer ...] [--delete-after] [--tmp-dir=PATH]
bun run ingest-dossier | normalize-artifacts | load-loket-export | resolve-addresses | check-qs-duplicates
```

The commands are run directly (`bun run <script>`, or `bun run src/commands/<file>.ts` for the ones without a script); there is no long-running process to start.

## Architecture

### Layers

- **`src/commands/`** — One file per command-line tool. `load-dataset` (BAG / 3DBAG / subsidence ingest) and `migrate` are run by hand from the ops VM; the dossier tools also run from Windmill (`f/fundermaps/dataops/ingest_pending` checks this repo out at a pinned commit).
- **`src/providers/`** — External service wrappers: S3 (DigitalOcean Spaces), GDAL/ogr2ogr, PDF tooling, the vision/LLM client.
- **`src/lib/`** — Internal utilities: structured logger, subprocess spawning with timeout, file/HTTP helpers, the migration runner's logic, address and evidence matching.
- **`src/config.ts`** — Zod-validated environment config. Database and S3 variables are prefixed `FUNDERMAPS_`.
- **`src/db.ts`** — PostgreSQL connection pool (uses `postgres` library with SSL prefer mode).
- **`db/migrations/`** — Ledger-tracked schema migrations, applied with `bun run migrate` (ledger `application.schema_migrations`, contract in `db/migrations/README.md`). `sql/migrate/` is the pre-ledger history, not replayed.
- **`sql/`** — Hand-written SQL: `load/` (BAG/subsidence/3DBAG ingest), `model/` (risk model refresh), `migrate/` (legacy one-shot migrations, see above).
- **`windmill/`** — Git mirror of the Windmill workspace (scripts, flows, schedules); the workspace is edited in Windmill and mirrored here for review. See `windmill/README.md`.
- **`windmill-worker/`** — The Windmill worker image: stock Windmill plus `gdal-bin` and the DuckDB CLI, built on the worker droplet. See its README.

### Key patterns

- **Subprocess execution**: GDAL and the PDF tools are invoked as child processes via `src/lib/subprocess.ts`, which wraps `Bun.spawn` with timeout and bounded stdio capture.
- **Path alias**: `@/*` maps to `./src/*` (configured in tsconfig.json).
- **Bun's global types** come from `"types": ["bun"]` in `tsconfig.json` — no source file needs to import from `"bun"` for them.
- **S3 buckets**: `fundermaps-archive` (**cold storage** — the GPKG exports, each with a GeoParquet copy next to it, under `mapset/` and the monthly keepers under `mapset-archive/`; this is the permanent static-model history), `fundermaps-data` (source datasets, exports, funda media), `fundermaps-tileset` (basemap fonts/sprites/styles; the vector tilesets themselves were retired in favour of the Martin tileserver), `fundermaps` (PDFs/artifacts), `fundermaps-development` (default).
  - Cold-bucket gotchas: **multipart upload fails** (`BadDigest` on `CompleteMultipartUpload`), so uploads must be a single PUT — capped at 5 GB, and `analysis_full` is ~3.35 GB. **Spaces cannot server-side copy between buckets at all** (`NotImplemented: … cross-region or cross-cluster CopyObject`), only within one bucket. 30-day minimum retention.

### The archive export (GPKG + GeoParquet)

Runs in Windmill, not here: `f/fundermaps/mapset/process_mapset` (called at the end of `f/fundermaps/data/refresh_data_model`) loops over the enabled rows of `maplayer.bundle` and runs `export_tileset` for each — `ogr2ogr` of `maplayer.<tileset>` to GeoPackage, one streaming PUT (via `curl`; Bun's `fetch` buffers a file body in memory) to `fundermaps-archive/mapset/YYYY/mon/DD/<tileset>.gpkg`, then a GeoParquet copy of that same file (`<tileset>.parquet`, converted on the worker with the DuckDB CLI; ~4x smaller, and DuckDB can query it in place) — then writes one `data.refresh_log` row per export (job `export_tileset`; size, row count and `parquet_bytes` in `detail`). The GPKG is the archive of record: a failed GeoParquet copy is logged, leaves `parquet_bytes` null and does not fail the export. Source in `windmill/f/fundermaps/mapset/`.

## System Dependencies (for local dev)

`load-dataset` requires `ogr2ogr` (GDAL ≥ 3.0) on the system. The dossier tools need the PDF utilities `src/providers/pdf.ts` shells out to.

## Operational constraints

- Nothing applies migrations automatically. `bun run migrate` is a deliberate step (CI runs it on the bootstrapped schema; prod from the ops VM as doadmin with `--allow-prod`). Code can run against a schema that is a migration behind; the failure mode is a query that hits a missing column at runtime.
- Windmill's server and worker versions move together: rebuild the `windmill-worker/` image for the new version when the server is upgraded.
