-- "Waarde toevoegen" (API #175, live 2026-09-16): a reviewer records a value
-- the model did not find. The route creates one 'reviewer' extraction per
-- dossier and an extraction_field under it, then a verdict. The API role had
-- SELECT only on those two tables, so every call has failed with
-- "permission denied for table extraction" since the deploy (first seen on
-- dossier 5165, 2026-09-17 08:25Z). verdict INSERT was already granted.
--
-- The id columns are identity columns, so no sequence privileges are needed.
-- Verified 2026-09-17 in a rolled-back transaction: with these two grants the
-- route's three inserts succeed as fundermaps_api.
--
-- Idempotent.
GRANT INSERT ON dataops.extraction TO fundermaps_webapp;
GRANT INSERT ON dataops.extraction_field TO fundermaps_webapp;
