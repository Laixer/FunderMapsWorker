-- FunderMaps DB role grants for a fresh test/stage instance.
--
-- Mirrors the production role privilege model so the TS API and TS Webservice
-- can connect with their normal roles.
--
-- Run AFTER schema.sql has loaded. The owner of all objects is the role that
-- ran schema.sql (typically `fundermaps` when bootstrapped via init_db.sh).
--
-- Roles assumed to already exist (init_db.sh creates them):
--   fundermaps             -- ETL/owner
--   fundermaps_webapp      -- privilege group for the TS API (full CRUD on app/report data)
--   fundermaps_api         -- TS API login role; member of fundermaps_webapp
--                            (see migrate/create_fundermaps_api_role.sql)
--   fundermaps_webservice  -- product webservice (read-only)

-- ---------------------------------------------------------------------------
-- Schema USAGE
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA application, auth, data, geocoder, maplayer, report
    TO fundermaps_webapp, fundermaps_webservice;

-- ---------------------------------------------------------------------------
-- fundermaps_webapp: full CRUD on every schema (TS API needs to write
-- inquiries, recovery samples, sessions, auth_keys, mapsets, etc.).
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA application, auth, data, geocoder, maplayer, report
    TO fundermaps_webapp;

GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA application, data, geocoder, maplayer, report
    TO fundermaps_webapp;

GRANT EXECUTE
    ON ALL FUNCTIONS IN SCHEMA application, data, geocoder, maplayer, report
    TO fundermaps_webapp;

-- ---------------------------------------------------------------------------
-- fundermaps_webservice: read-only product data plus auth_key.last_used UPDATE
-- (so it can record key usage) and product_tracker INSERT (for billing).
-- ---------------------------------------------------------------------------
GRANT SELECT
    ON ALL TABLES IN SCHEMA application, data, geocoder, maplayer, report
    TO fundermaps_webservice;

GRANT INSERT ON application.product_tracker
    TO fundermaps_webservice;

GRANT UPDATE (last_used) ON application.auth_key
    TO fundermaps_webservice;

-- Of schema auth (Better Auth) the webservice reads only the keys and the memberships, and bumps two usage
-- columns of a key. Nothing schema-wide there.
GRANT SELECT ON auth.apikey, auth.organization_user TO fundermaps_webservice;
GRANT UPDATE (last_request, request_count) ON auth.apikey TO fundermaps_webservice;

-- Passkeys (Better Auth passkey plugin): API full CRUD; nothing else reads them.
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.passkey TO fundermaps_webapp;

-- Least privilege for the read-only role (migration 20261009_007): the
-- schema-wide SELECT above covers objects it does not read.
REVOKE SELECT ON application.application_user,
                 application.organization_geolock_district,
                 application.organization_geolock_municipality,
                 application.organization_geolock_neighborhood,
                 data.building_elevation, data.building_geographic_region,
                 data.building_groundwater_level, data.building_height,
                 data.building_ownership, data.building_sample, data.building_subsidence,
                 data.building_subsidence_history, data.model_risk_static_2024_1,
                 data.model_risk_static_2026_3,
                 data.building_sample_2026_3, data.building_sample_2024_1,
                 data.product_tracker_daily, geocoder.building_active,
                 geocoder.municipality, geocoder.residence, geocoder.state, report.incident
    FROM fundermaps_webservice;
REVOKE ALL ON SEQUENCE report.inquiry_id_seq, report.inquiry_sample_id_seq,
                       report.recovery_id_seq, report.recovery_sample_id_seq,
                       application.attribution_id_seq
    FROM fundermaps_webservice;

-- The refresh_data_model flow (fundermaps_windmill) refreshes the rollup and
-- writes one refresh_log row per run.
GRANT SELECT, MAINTAIN ON data.product_tracker_daily TO fundermaps_windmill;
GRANT SELECT, INSERT ON data.refresh_log TO fundermaps_windmill;

-- ---------------------------------------------------------------------------
-- Default privileges so future tables (created later via migrations or by
-- the worker) inherit the same access without manual GRANTs.
-- ---------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA application, data, geocoder, maplayer, report
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO fundermaps_webapp;
ALTER DEFAULT PRIVILEGES IN SCHEMA application, data, geocoder, maplayer, report
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO fundermaps_webapp;
ALTER DEFAULT PRIVILEGES IN SCHEMA application, data, geocoder, maplayer, report
    GRANT EXECUTE ON FUNCTIONS TO fundermaps_webapp;

ALTER DEFAULT PRIVILEGES IN SCHEMA application, data, geocoder, maplayer, report
    GRANT SELECT ON TABLES TO fundermaps_webservice;
