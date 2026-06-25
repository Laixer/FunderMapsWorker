-- Write access for the TS API on the contractor (uitvoerder) reference table
-- (FunderMaps issue #997). The management portal now lets admins add and rename
-- contractors so the inquiry "Uitvoerder" dropdown can grow without a code
-- change, which means fundermaps_webapp needs INSERT/UPDATE here — until now it
-- only held SELECT (contractor was externally-seeded reference data).
--
-- sql/init/grants.sql already covers this for fresh DBs (GRANT ... ON ALL TABLES
-- plus ALTER DEFAULT PRIVILEGES), but production drifted: contractor ended up
-- with only SELECT for fundermaps_webapp (the table was recreated by the ETL
-- owner at some point without re-running grants). This restates the grants
-- explicitly for manually-migrated environments (e.g. prod, which doesn't run
-- init_db.sh). Idempotent — safe to re-run.
--
--   psql "$DB_URL" -f sql/migrate/grant_contractor_webapp_write.sql
--
-- No DELETE: the management API intentionally exposes create + rename only;
-- contractors are referenced by attribution/recovery_sample (ON DELETE RESTRICT)
-- and removing them would erase the record of who carried out the work.

BEGIN;

GRANT INSERT, UPDATE ON application.contractor TO fundermaps_webapp;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE application.contractor_id_seq TO fundermaps_webapp;

COMMIT;
