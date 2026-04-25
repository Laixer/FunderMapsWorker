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

**Job lifecycle**: pending → processing → completed/failed. Failed jobs retry with exponential backoff (capped at 5 attempts).

### Layers

- **`src/commands/`** — Job handlers, one per job type. Each exports a function taking `(sql, jobId, payload)`. Job types: `process-mapset`, `export-product`, `load-dataset`, `generate-pdf`, `cleanup-storage`, `send-mail`, `export-samples`.
- **`src/providers/`** — External service wrappers: S3 (DigitalOcean Spaces), GDAL/ogr2ogr, tippecanoe, Mailgun, PDF.co.
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

The `process-mapset` and `load-dataset` commands require `ogr2ogr` (GDAL ≥3.0) and `tippecanoe` installed on the system. See `Containerfile` for the full build setup.

## Container Build

Uses a multi-stage `Containerfile`: builds tippecanoe from source, then creates a minimal Bun runtime image with `gdal-bin` and `libsqlite3-0`.
