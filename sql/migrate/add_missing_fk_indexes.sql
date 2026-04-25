-- Add missing indexes on the remaining 9 FK columns surfaced by the
-- 2026-04-25 hygiene audit. All tables here are <2 MB so a plain
-- CREATE INDEX is fine (no need for CONCURRENTLY).
--
-- The 1.7 GB geocoder.residence.address_id case was handled separately
-- in add_residence_address_id_idx.sql with CONCURRENTLY.

BEGIN;

CREATE INDEX IF NOT EXISTS recovery_sample_recovery_id_idx
    ON report.recovery_sample USING btree (recovery_id);

CREATE INDEX IF NOT EXISTS application_user_application_id_idx
    ON application.application_user USING btree (application_id);

CREATE INDEX IF NOT EXISTS organization_geolock_neighborhood_neighborhood_id_idx
    ON application.organization_geolock_neighborhood USING btree (neighborhood_id);

CREATE INDEX IF NOT EXISTS organization_user_organization_id_idx
    ON application.organization_user USING btree (organization_id);

CREATE INDEX IF NOT EXISTS organization_mapset_mapset_id_idx
    ON application.organization_mapset USING btree (mapset_id);

CREATE INDEX IF NOT EXISTS organization_geolock_municipality_municipality_id_idx
    ON application.organization_geolock_municipality USING btree (municipality_id);

CREATE INDEX IF NOT EXISTS organization_geolock_district_district_id_idx
    ON application.organization_geolock_district USING btree (district_id);

CREATE INDEX IF NOT EXISTS product_tracker_mismatch_organization_id_idx
    ON application.product_tracker_mismatch USING btree (organization_id);

CREATE INDEX IF NOT EXISTS product_tracker_building_id_idx
    ON application.product_tracker USING btree (building_id);

COMMIT;
