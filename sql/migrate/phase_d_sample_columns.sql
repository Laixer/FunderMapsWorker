-- Phase D: rename sample-table FK columns to _id convention.
-- Wire format preserved by app-layer aliases (Drizzle name arg, C# positional reads).
-- Coordinated deploy required: WebApi must be on the new build before this runs.
-- Run as: fundermaps (owner)
--
-- Pre-flight verified (2026-04-25):
-- - 11 dependent views/matviews; only 2 reference renamed columns directly
--   (data.statistics_postal_code_data_collected, data.statistics_product_data_collected
--   — both reference is2.building). PG transparently rewrites view defs on column
--   rename — refs stored by attnum.
-- - No DB functions reference these columns.
-- - Triggers on samples (last_record_update on update_date) don't touch them.
-- - Row counts: inquiry_sample=454120, recovery_sample=18749. Rename is metadata-only.
-- - Note: recovery_sample.building was renamed to building_id long ago (commit
--   911a97f2) and is already correct; this migration only touches the remaining 4 cols.

BEGIN;

ALTER TABLE report.inquiry_sample  RENAME COLUMN building   TO building_id;
ALTER TABLE report.inquiry_sample  RENAME COLUMN inquiry    TO inquiry_id;
ALTER TABLE report.recovery_sample RENAME COLUMN recovery   TO recovery_id;
ALTER TABLE report.recovery_sample RENAME COLUMN contractor TO contractor_id;

ALTER TABLE report.inquiry_sample  RENAME CONSTRAINT inquiry_sample_building_fkey   TO inquiry_sample_building_id_fkey;
ALTER TABLE report.inquiry_sample  RENAME CONSTRAINT inquiry_sample_inquiry_fkey    TO inquiry_sample_inquiry_id_fkey;
ALTER TABLE report.recovery_sample RENAME CONSTRAINT recovery_sample_recovery_fkey  TO recovery_sample_recovery_id_fkey;
ALTER TABLE report.recovery_sample RENAME CONSTRAINT recovery_sample_contractor_fkey TO recovery_sample_contractor_id_fkey;

ALTER INDEX report.inquiry_sample_building_idx  RENAME TO inquiry_sample_building_id_idx;
ALTER INDEX report.inquiry_sample_inquiry_idx   RENAME TO inquiry_sample_inquiry_id_idx;
ALTER INDEX report.recovery_sample_contractor_idx RENAME TO recovery_sample_contractor_id_idx;

COMMIT;
