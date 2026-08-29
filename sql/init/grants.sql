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
--   fundermaps_webapp      -- TS API (full CRUD on app/report data)
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
