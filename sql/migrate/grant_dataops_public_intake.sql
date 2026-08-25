-- The API becomes a writer at the front door, not only at the review desk.
--
-- grant_dataops_to_webapp.sql was written when the API's whole job in this
-- schema was to show a reviewer a proposal and record their decision: read
-- everything, write only `verdict`. The public form changes that. A submission
-- from the terugmeldformulier arrives over HTTP and has to become a dossier and
-- its artifacts, and the API is the only thing holding that connection.
--
-- Still deliberately narrow. The API may CREATE a dossier and its artifacts --
-- that is the front door -- but it may not UPDATE or DELETE either. Once a
-- submission is recorded, only the pipeline and a reviewer's verdict may act on
-- it. A front door that can rewrite what came through it yesterday is not a
-- record of what arrived.
--
-- The reference sequence needs granting explicitly and the identity ones do
-- not: for a GENERATED ... AS IDENTITY column Postgres checks INSERT on the
-- table and never looks at the sequence, but dataops.generate_reference()
-- calls nextval() itself, so that one is an ordinary permission check. Miss it
-- and every submission fails on `permission denied for sequence`.
--
--   psql "$ADMIN_URL" -f sql/migrate/grant_dataops_public_intake.sql

GRANT INSERT ON dataops.dossier, dataops.artifact TO fundermaps_webapp;

GRANT USAGE ON SEQUENCE dataops.dossier_reference_seq TO fundermaps_webapp;

GRANT EXECUTE ON FUNCTION dataops.generate_reference() TO fundermaps_webapp;
