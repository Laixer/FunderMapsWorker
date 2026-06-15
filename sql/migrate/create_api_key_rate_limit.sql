-- Per-(API key, product) billing-event rate limits for the TS Webservice
-- (FunderMapsWebservice issue #8). One row caps the billable events
-- (= rows in application.product_tracker, post 24h-dedup) a given API key
-- can produce for a given product within a calendar window.
--
-- `source` discriminates between the two API-key tables we support:
--   - 'legacy' → application.auth_key.id (uuid → text)
--   - 'ba'     → application.apikey.id  (BA-generated 32-char string)
-- Both tables stay live until the C# Webservice retires end of Dec 2026.
--
-- Period is calendar-aligned UTC (UTC midnight for day, first-of-month for
-- month). No row for a given (key, product) pair = unlimited.
--
--   psql "$DB_URL" -f sql/migrate/create_api_key_rate_limit.sql

BEGIN;

CREATE TABLE IF NOT EXISTS application.api_key_rate_limit (
  api_key_id  text        NOT NULL,
  source      text        NOT NULL CHECK (source IN ('ba', 'legacy')),
  product     text        NOT NULL,
  period      text        NOT NULL CHECK (period IN ('day', 'month')),
  limit_count integer     NOT NULL CHECK (limit_count >= 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (api_key_id, source, product)
);

COMMENT ON TABLE application.api_key_rate_limit IS
  'Per-(API key, product) billing-event rate limits enforced by FunderMapsWebservice.';
COMMENT ON COLUMN application.api_key_rate_limit.source IS
  '''ba'' = application.apikey, ''legacy'' = application.auth_key (key id is unique within a source, not across).';
COMMENT ON COLUMN application.api_key_rate_limit.product IS
  'Tracker product name, e.g. analysis3, risk3, light3, statistics3.';
COMMENT ON COLUMN application.api_key_rate_limit.period IS
  'Calendar window: ''day'' resets at UTC midnight; ''month'' resets at first-of-month UTC.';
COMMENT ON COLUMN application.api_key_rate_limit.limit_count IS
  'Max billable events allowed within one period. Absent row = unlimited.';

-- Grants. Mirrors the role model in sql/init/grants.sql so this migration is
-- self-contained: fresh test DBs inherit these via ALTER DEFAULT PRIVILEGES,
-- but manually-migrated environments (e.g. prod, which doesn't run init_db.sh)
-- need them stated explicitly. Idempotent — safe to re-run.
--   fundermaps_webapp     — TS API admin CRUD on rate-limit config
--   fundermaps_webservice — Webservice reads config per request (read-only)
--   grafana               — dashboards / overage monitoring (read-only)
GRANT SELECT, INSERT, UPDATE, DELETE ON application.api_key_rate_limit TO fundermaps_webapp;
GRANT SELECT ON application.api_key_rate_limit TO fundermaps_webservice, grafana;

COMMIT;
