# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FunderMaps Worker is a polling-based background job processor built with **Bun** and **TypeScript**. It reads jobs from a PostgreSQL queue (`application.worker_jobs`) and executes them concurrently.

## Commands

```bash
bun run dev          # Start with --watch (auto-reload)
bun run start        # Start without watch
bun install          # Install dependencies
```

No test runner or linter is configured. TypeScript strict mode is the primary safety net.

## Architecture

**Main loop** (`src/index.ts`): recover stale jobs → poll pending jobs → process up to `MAX_CONCURRENT` (default 3) in parallel → sleep `POLL_INTERVAL` (default 30s) → repeat.

**Job lifecycle**: pending → processing → completed/failed. Failed jobs reschedule themselves to `pending` with `process_after = NOW() + 30 * 2^(n-1) seconds` (so retry waits are 30s, 60s, 120s, 240s, …). The cap is per-row: `worker_jobs.max_retries` (schema default **3**; `0` means infinite). When the row exhausts its retries the status flips to `failed` and `last_error` records why.

**Stale-job recovery**: at the top of each poll cycle, any `processing` job whose `updated_at` is older than `STALE_THRESHOLD_HOURS = 2` is reset to `pending` with a `Reset: stuck in processing …` note. This is how we recover from OOM kills, crashed pods, or any path where `safeDbUpdate` couldn't write a terminal state.

### Layers

- **`src/commands/`** — Job handlers, one per job type. Each exports a function taking `(sql, jobId, payload)`. Job types (canonical underscore form stored in `application.worker_jobs.job_type` and emitted by `data.refresh_all`): `process_mapset`, `export_product`, `load_dataset`, `generate_pdf`, `cleanup_storage`, `send_mail`, `export_samples`. (Dispatch normalizes `-` → `_`, so the dashed file-name form also resolves.)
- **`src/providers/`** — External service wrappers: S3 (DigitalOcean Spaces), GDAL/ogr2ogr, tippecanoe, Mailgun, PDF.co. PDF.co is being replaced by self-hosted Gotenberg (see `project_pdf_gotenberg.md` in the auto-memory); the swap hasn't shipped yet, so `providers/pdf.ts` still talks to `api.pdf.co`.
- **`src/lib/`** — Internal utilities: structured logger, concurrent queue, subprocess spawning with timeout, file/HTTP helpers.
- **`src/config.ts`** — Zod-validated environment config. All env vars prefixed `FUNDERMAPS_`.
- **`src/db.ts`** — PostgreSQL connection pool (uses `postgres` library with SSL prefer mode).
- **`sql/`** — Hand-written SQL: `load/` (BAG/subsidence/3DBAG ingest), `model/` (risk model refresh), `migrate/` (one-shot schema migrations). Run manually via `psql`; the worker does not auto-apply migrations.

### Key patterns

- **Subprocess execution**: GDAL and tippecanoe are invoked as child processes via `src/lib/subprocess.ts` which wraps `Bun.spawn` with timeout and stdio capture.
- **Path alias**: `@/*` maps to `./src/*` (configured in tsconfig.json).
- **Payload validation**: Each command validates its payload with Zod schemas before execution.
- **S3 buckets**: `fundermaps-data` (datasets/exports), `fundermaps-tileset` (vector tiles), `fundermaps` (PDFs/artifacts), `fundermaps-development` (default).

## System Dependencies (for local dev)

The `process_mapset` and `load_dataset` commands require `ogr2ogr` (GDAL ≥3.0) and `tippecanoe` installed on the system. See `Containerfile` for the full build setup.

## Container Build

Uses a multi-stage `Containerfile`: builds tippecanoe from source, then creates a minimal Bun runtime image with `gdal-bin` and `libsqlite3-0`.

## Operational constraints

- **`MAX_TILESET_WORKERS=1` must be set in any deployment that runs `process_mapset`**. The default in `config.ts` is unset (no parallelism cap on tileset rendering), but `analysis_full` exports OOM an 8 GB box if more than one tileset renders concurrently. New deployments should pin this to 1 until someone addresses the OOM root cause — don't bump it without that.
- `MAX_CONCURRENT` defaults to 3 (process-wide cap across job types). Tileset jobs honour `MAX_TILESET_WORKERS` *inside* this cap, so a healthy mix of mixed jobs can saturate without OOMing the tileset path.
- The worker does **not** auto-apply migrations. SQL under `sql/migrate/` is hand-run via `psql` against the target database. Worker boot will happily run against a schema that's a migration behind; the failure mode is a job that hits a missing column at runtime, not a startup error.
