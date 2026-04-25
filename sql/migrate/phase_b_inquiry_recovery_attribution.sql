-- Phase B: rename inquiry.attribution and recovery.attribution to attribution_id.
-- Wire format preserved by app-layer aliases (Drizzle name arg, C# positional reads).
-- Coordinated deploy required: WebApi must be on the new build before this runs.
-- Run as: fundermaps (owner)
--
-- Pre-flight verified (2026-04-25):
-- - 6 dependent views/matviews have 0 references to "attribution" — column rename is
--   transparent (PG stores view col refs by attnum).
-- - No DB functions/procedures reference these columns.
-- - Triggers on these tables (last_record_update on update_date) don't touch attribution.
-- - Row counts: inquiry=20428, recovery=9 — rename is metadata-only and instant.

BEGIN;

ALTER TABLE report.inquiry  RENAME COLUMN attribution TO attribution_id;
ALTER TABLE report.recovery RENAME COLUMN attribution TO attribution_id;

ALTER TABLE report.inquiry  RENAME CONSTRAINT inquiry_attribution_fkey  TO inquiry_attribution_id_fkey;
ALTER TABLE report.recovery RENAME CONSTRAINT recovery_attribution_fkey TO recovery_attribution_id_fkey;

ALTER INDEX report.inquiry_attribution_idx  RENAME TO inquiry_attribution_id_idx;
ALTER INDEX report.recovery_attribution_idx RENAME TO recovery_attribution_id_idx;

COMMIT;
