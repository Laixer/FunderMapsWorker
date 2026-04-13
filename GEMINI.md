# GEMINI.md

This file provides foundational mandates and guidance for Gemini CLI when working in this repository. These instructions take absolute precedence over general defaults.

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

- **`src/commands/`** — Job handlers, one per job type. Each exports a function taking `(sql, jobId, payload)`. Job types: `process-mapset`, `refresh-models`, `export-product`, `load-dataset`, `generate-pdf`, `cleanup-storage`, `send-mail`.
- **`src/providers/`** — External service wrappers: S3 (DigitalOcean Spaces), GDAL/ogr2ogr, tippecanoe, Mailgun, PDF.co.
- **`src/lib/`** — Internal utilities: structured logger, concurrent queue, subprocess spawning with timeout, file/HTTP helpers.
- **`src/config.ts`** — Zod-validated environment config. All env vars prefixed `FUNDERMAPS_`.
- **`src/db.ts`** — PostgreSQL connection pool (uses `postgres` library with SSL prefer mode).

### Key patterns

- **Subprocess execution**: GDAL and tippecanoe are invoked as child processes via `src/lib/subprocess.ts` which wraps `Bun.spawn` with timeout and stdio capture.
- **Path alias**: `@/*` maps to `./src/*` (configured in tsconfig.json).
- **Payload validation**: Each command validates its payload with Zod schemas before execution.
- **S3 buckets**: `fundermaps-data` (datasets/exports), `fundermaps-tileset` (vector tiles), `fundermaps` (PDFs/artifacts), `fundermaps-development` (default).

## Foundational Mandates

### SQL Risk Model (recreate_model_risk_dynamic_all.sql)

The following rules **MUST** be strictly adhered to when modifying the risk models:

1.  **Reliability Hierarchy**: The reliability tiers must follow the order: **Established (Vastgesteld) > Cluster (Afgeleid) > Supercluster (Afgeleid) > Indicative (Modelmatig)**.
2.  **Tier Inclusion**: All risk calculations (`DrystandRisk`, `BioInfectionRisk`, `DewateringDepthRisk`) and physical measurements (`Drystand`, `DewateringDepth`) must include the `supercluster` tier.
3.  **Reliability Logic**: Reliability fields must reflect the highest available tier of information (e.g., check if `.id IS NOT NULL` for each tier) rather than being strictly dependent on whether a specific `damage_cause` was found. If an inquiry exists, it authorizes the result at that tier's level of reliability.
