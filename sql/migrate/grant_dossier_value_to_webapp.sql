-- "Waarde toevoegen" (API #175, POST /api/dataops/dossier/:id/value) writes a
-- reviewer extraction with one confirmed field, a verdict and, when the value
-- names an address, a dossier_address row. The API role could insert verdicts
-- and dossier addresses but not extractions or fields, so the first real use
-- (dossier 5165, 2026-09-17 10:25 CEST) failed with
--   permission denied for table extraction
-- Same shape as grant_dossier_payload_to_webapp.sql (#146). Run as doadmin.
--
--   psql "$DB_URL" -f sql/migrate/grant_dossier_value_to_webapp.sql

BEGIN;

GRANT INSERT ON dataops.extraction        TO fundermaps_webapp;
GRANT INSERT ON dataops.extraction_field  TO fundermaps_webapp;

COMMIT;

-- verify:
-- SELECT has_table_privilege('fundermaps_webapp', 'dataops.extraction', 'INSERT'),
--        has_table_privilege('fundermaps_webapp', 'dataops.extraction_field', 'INSERT');
