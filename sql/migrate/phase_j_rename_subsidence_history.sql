-- Phase J: rename data.subsidence_history → data.building_subsidence_history.
--
-- The renamed table is the time-series sibling of data.building_subsidence
-- (current/P95 values per building). The new name makes the relationship
-- between the two tables explicit.
--
-- Largest table in the database: 132M rows / 10 GB heap / 8.7 GB indexes.
-- ALTER TABLE RENAME is metadata-only — no data movement.
--
-- Pre-flight verified (2026-04-25):
--   - Zero views/matviews/functions/triggers depend on the table
--   - 1 PK index + 2 constraints (PK + FK) — renamed below for naming consistency
--
-- Coordinated with code changes:
--   * C# entity class SubsidenceHistory → BuildingSubsidenceHistory
--     (file rename + class + interface return type + repo + controller)
--   * C# SQL: FROM data.subsidence_history → FROM data.building_subsidence_history
--   * TS API SQL in src/routes/product.ts (subsidence/historic route)
--   * Worker SQL in sql/load/load_subsidence_history.sql (loader script)
--
-- Wire format unchanged (System.Text.Json uses property names, not class
-- name). Frontends and Go backend have zero references.
--
-- Run as: fundermaps (owner)

BEGIN;

ALTER TABLE data.subsidence_history
    RENAME TO building_subsidence_history;

ALTER TABLE data.building_subsidence_history
    RENAME CONSTRAINT subsidence_history_pkey
                   TO building_subsidence_history_pkey;

ALTER TABLE data.building_subsidence_history
    RENAME CONSTRAINT subsidence_history_building_id_fkey
                   TO building_subsidence_history_building_id_fkey;

COMMIT;
