-- Backfills the role grants that should have shipped with
-- add_better_auth_apikey_table.sql (PR #8). Without these, the
-- application schema's BA plugin table was owner-only on prod
-- because the schema lacks ALTER DEFAULT PRIVILEGES for these
-- roles. Applied ad-hoc to prod 2026-05-12; this file captures
-- the same grants for replicability + future env bring-up.
--
-- Supersedes grant_apikey_usage_cols_to_webservice.sql (which
-- assumed baseline SELECT was already in place — it wasn't). The
-- column-level UPDATE here is the same grant in the same final
-- shape; re-applying it is idempotent.

BEGIN;

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

COMMIT;
