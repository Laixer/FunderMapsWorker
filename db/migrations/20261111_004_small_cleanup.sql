-- Small clean-up after the full database check of 2026-11-11 (Yorick: "Do 9 and timeouts, drop pgcrypto").
-- What the check rests on: the scan counters since 2026-10-28 (14 days, a month turn included), the code on main in
-- every repo, Windmill's live scripts and flows, the tile server config and the recorded statements.
SET LOCAL lock_timeout = '2s';

-- 1. Twelve indexes nothing has read since the counters began. None backs a constraint and none supports a foreign
--    key. All sit on small tables (the largest has 35,000 rows), where a sequential scan costs milliseconds.
DROP INDEX geocoder.neighborhood_name_idx;
DROP INDEX geocoder.district_name_idx;
DROP INDEX geocoder.state_name_idx;
DROP INDEX geocoder.state_country_idx;
DROP INDEX geocoder.state_geom_idx;
DROP INDEX report.inquiry_access_policy_idx;
DROP INDEX report.recovery_access_policy_idx;
DROP INDEX report.recovery_type_idx;
DROP INDEX report.recovery_sample_status_idx;
DROP INDEX report.recovery_sample_pile_type_idx;
DROP INDEX report.recovery_sample_type_idx;
DROP INDEX dataops.extraction_field_state_idx;

-- 2. A duplicate: the unique index dossier_address_once (dossier_id, address_id) starts with the same column and
--    serves the same lookups, the foreign key's included.
DROP INDEX dataops.dossier_address_dossier_idx;

-- 3. 104 MB that every refresh rebuilds for nothing: refresh_building_precomputed() truncates and refills the table
--    twice a day, and the only two scans of this index in 14 days were a one-off check by hand.
DROP INDEX data.building_precomputed_neighborhood_id_idx;

-- 4. maplayer.bundle is the list of archive exports (2 rows). Three columns are left from the tippecanoe tilesets,
--    retired in 2026-10: the export reads tileset, enabled and upload_dataset only.
ALTER TABLE maplayer.bundle
    DROP COLUMN generate_tileset,
    DROP COLUMN zoom_min_level,
    DROP COLUMN zoom_max_level;

-- 5. Comments that were wrong or missing.
COMMENT ON TABLE data.refresh_log IS
    '[ops] One row per completed scheduled job (e.g. refresh_data_model). Read by the Studio (Modellen, Vandaag), the '
    'intake follow-up mail and the Webservice''s delivery stamp. A missing row is the only sign that a refresh failed.';
COMMENT ON COLUMN data.building_subsidence_history.velocity IS
    'Cumulative displacement in mm since the first measurement (InSAR), NOT a velocity; the name is historical. '
    'The velocity itself is data.building_subsidence.velocity, the least-squares slope of this series.';
COMMENT ON FUNCTION data.compute_indicative_dewatering_risk(report.foundation_type, double precision, double precision, boolean) IS
    '[model-2024.1, frozen] The 2024.1 logic, kept only for the view model_risk_dynamic_all behind the frozen matview. '
    'The current model uses compute_indicative_dewatering_risk_2026_3.';
COMMENT ON FUNCTION data.compute_indicative_drystand_risk(report.foundation_type, double precision, double precision, boolean) IS
    '[model-2024.1, frozen] The 2024.1 logic, kept only for the view model_risk_dynamic_all behind the frozen matview. '
    'The current model uses compute_indicative_drystand_risk_2026_3.';

-- 6. pgcrypto: nothing of ours calls it. No function body, default, view, code or recorded statement names one of its
--    functions; gen_random_uuid() is in core since PostgreSQL 13. No CASCADE: a hidden dependency stops this file.
DROP EXTENSION pgcrypto;
