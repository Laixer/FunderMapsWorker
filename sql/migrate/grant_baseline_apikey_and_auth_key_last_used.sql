-- Consolidated baseline grants for both BA-plugin and legacy api-key
-- tables, captured so future env bring-ups get the full set in a
-- single apply.
--
-- Supersedes:
--   - grant_apikey_usage_cols_to_webservice.sql (column UPDATE only,
--     incorrectly assumed baseline SELECT was already in place)
--   - grant_apikey_baseline.sql (apikey grants only; missed the
--     symmetric UPDATE (last_used) grant on application.auth_key
--     needed for Phase C drain observability on legacy keys)
--
-- All grants are idempotent; safe to re-apply.
--
-- Applied ad-hoc to prod:
--   - apikey baseline: 2026-05-12
--   - auth_key.last_used column UPDATE: 2026-05-12
--
-- Result mirrors application.auth_key's existing grant shape:
--   fundermaps_webapp  = SELECT/INSERT/UPDATE/DELETE
--   fundermaps_webservice = SELECT + column UPDATE on usage cols
--   grafana = SELECT (read-only monitoring)

BEGIN;

-- application.apikey (Better Auth api-key plugin table)

GRANT SELECT, INSERT, UPDATE, DELETE
   ON application.apikey
   TO fundermaps_webapp;

GRANT SELECT
   ON application.apikey
   TO fundermaps_webservice;

GRANT SELECT
   ON application.apikey
   TO grafana;

GRANT UPDATE (last_request, request_count)
   ON application.apikey
   TO fundermaps_webservice;

-- application.auth_key (legacy fmsk. keys)
-- Baseline SELECT/INSERT/UPDATE/DELETE for webapp and SELECT for
-- webservice already shipped with the original table; only the
-- column-level UPDATE on last_used was missing, blocking the
-- Webservice from recording usage on legacy keys during the drain.

GRANT UPDATE (last_used)
   ON application.auth_key
   TO fundermaps_webservice;

COMMIT;
