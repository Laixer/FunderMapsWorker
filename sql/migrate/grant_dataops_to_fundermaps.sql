-- The worker runs as `fundermaps`, but dataops had to be created by doadmin
-- (only a superuser can CREATE SCHEMA on this cluster), so the owner is not the
-- role that uses it. Without these grants ingest-dossier fails on its first
-- INSERT with a permission error that reads like a bug in the command.
--
-- Applied to production 2026-08-21 alongside create_dataops_ingest.sql.
--
--   psql "$ADMIN_URL" -f sql/migrate/grant_dataops_to_fundermaps.sql

GRANT USAGE ON SCHEMA dataops TO fundermaps;
GRANT ALL ON ALL TABLES IN SCHEMA dataops TO fundermaps;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA dataops TO fundermaps;

-- so tables added by a later migration do not need this file run again
ALTER DEFAULT PRIVILEGES IN SCHEMA dataops GRANT ALL ON TABLES TO fundermaps;
