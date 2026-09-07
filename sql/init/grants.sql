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
GRANT SELECT (id, user_id, created_at, updated_at, expires_at, ip_address, user_agent,
              impersonated_by, active_organization_id)
    ON application.session TO grafana;
GRANT SELECT (id, user_id, name, last_used, created_at, updated_at, expires_at)
    ON application.auth_key TO grafana;

-- Grafana reads the intake pipeline state (Operations board) and the daily
-- usage rollup + refresh log in data (Usage & billing, "model refresh age").
GRANT USAGE ON SCHEMA dataops TO grafana;
GRANT SELECT ON dataops.dossier, dataops.extraction TO grafana;
GRANT SELECT ON data.product_tracker_daily, data.refresh_log TO grafana;
GRANT SELECT ON application.contractor TO grafana;

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
