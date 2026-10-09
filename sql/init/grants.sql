-- FunderMaps DB role grants for a fresh test/stage instance.
--
-- Mirrors the production role privilege model so the TS API, TS Webservice,
-- C# Webservice and Grafana can connect with their normal roles.
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
--   grafana                -- dashboards (read-only)

-- ---------------------------------------------------------------------------
-- Schema USAGE
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA application, data, geocoder, maplayer, report
    TO fundermaps_webapp, fundermaps_webservice, grafana;

-- ---------------------------------------------------------------------------
-- fundermaps_webapp: full CRUD on every schema (TS API needs to write
-- inquiries, recovery samples, sessions, auth_keys, mapsets, etc.).
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA application, data, geocoder, maplayer, report
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

-- ---------------------------------------------------------------------------
-- grafana: read-only on everything for dashboards.
-- ---------------------------------------------------------------------------
GRANT SELECT
    ON ALL TABLES IN SCHEMA application, data, geocoder, maplayer, report
    TO grafana;

-- Better Auth tables carry secrets (session.token, auth_key.key_hash). Grafana
-- only needs the who/when columns for the Users + Operations dashboards, so
-- grant those columns explicitly instead of the whole table. (Applied to prod
-- 2026-09-07; apikey already had table-level SELECT via the default privileges.)
REVOKE SELECT ON application.session, application.auth_key FROM grafana;
GRANT SELECT (id, user_id, created_at) ON application.session TO grafana;
GRANT SELECT (user_id, name, last_used) ON application.auth_key TO grafana;

-- Grafana reads the intake pipeline state (Operations board) and the daily
-- usage rollup + refresh log in data (Usage & billing, "model refresh age").
GRANT USAGE ON SCHEMA dataops TO grafana;
GRANT SELECT ON dataops.dossier, dataops.extraction, dataops.dossier_entry, dataops.dossier_mail,
                dataops.artifact, dataops.extraction_field, dataops.verdict TO grafana;
GRANT SELECT ON data.product_tracker_daily, data.refresh_log TO grafana;
GRANT SELECT ON application.contractor TO grafana;

-- Secret-bearing tables nobody reads through these roles (migration
-- 20261009_003): application.application holds the legacy app secrets, apikey
-- the key hash and readable prefix. Grafana's usage board needs only the
-- who/when columns of apikey; the webservice keeps apikey to verify keys.
REVOKE SELECT ON application.application FROM fundermaps_webservice, grafana;
REVOKE SELECT ON application.apikey FROM grafana;
GRANT SELECT (name, reference_id, last_request, request_count, enabled)
    ON application.apikey TO grafana;

-- Passkeys (Better Auth passkey plugin): API full CRUD; nothing else reads them.
GRANT SELECT, INSERT, UPDATE, DELETE ON application.passkey TO fundermaps_webapp;
REVOKE SELECT ON application.passkey FROM fundermaps_webservice, grafana;

-- Least privilege for the read-only roles (migration 20261009_007): the
-- schema-wide SELECTs above cover objects neither reads.
REVOKE SELECT ON application.application_user, application.invitation,
                 application.organization, application.organization_custom_role,
                 application.organization_geolock_district,
                 application.organization_geolock_municipality,
                 application.organization_geolock_neighborhood, application."user",
                 data.building_elevation, data.building_geographic_region,
                 data.building_groundwater_level, data.building_height,
                 data.building_ownership, data.building_sample, data.building_subsidence,
                 data.building_subsidence_history, data.model_risk_static_2024_1,
                 data.product_tracker_daily, geocoder.building_active,
                 geocoder.municipality, geocoder.residence, geocoder.state, report.incident
    FROM fundermaps_webservice;
REVOKE ALL ON SEQUENCE report.inquiry_id_seq, report.inquiry_sample_id_seq,
                       report.recovery_id_seq, report.recovery_sample_id_seq,
                       application.attribution_id_seq
    FROM fundermaps_webservice;
REVOKE SELECT ON application.application_user, application.api_key_rate_limit,
                 application.invitation, application.organization_custom_role,
                 application.organization_user, data.model_version, geocoder.address,
                 maplayer.bundle, report.dossier_event
    FROM grafana;

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
    GRANT SELECT ON TABLES TO fundermaps_webservice, grafana;
