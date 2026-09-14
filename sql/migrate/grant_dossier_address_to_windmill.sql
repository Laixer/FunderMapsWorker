-- ClientApp #333 part D: the pipeline records the addresses a document names
-- that are not on the pand the dossier was filed under, as pipeline rows in
-- dataops.dossier_address (state pending), so the review screen's address
-- panel is filled from ingest rather than derived from the values. The
-- ingest runs as fundermaps_windmill, which so far could only read the table
-- (create_dataops_dossier_address.sql).
--
-- Additive. Reversible with two REVOKEs.
--
--   psql "$DB_URL" -f sql/migrate/grant_dossier_address_to_windmill.sql

BEGIN;

GRANT INSERT ON dataops.dossier_address TO fundermaps_windmill;
GRANT USAGE ON SEQUENCE dataops.dossier_address_id_seq TO fundermaps_windmill;

COMMIT;
