-- The API reads the review queue; it does not run the pipeline.
--
-- grant_dataops_to_fundermaps.sql gave the worker role full DML, because the
-- worker writes every row. The API connects as `fundermaps_webapp` and needs
-- much less: it shows a reviewer what was proposed and records what they
-- decided. Without this it fails with "permission denied for schema dataops"
-- on every studio page load, since the sidebar counter calls the queue.
--
-- Deliberately narrow:
--   read everything, because the review screen shows the whole dossier;
--   write only `verdict`, and only `state` on `extraction_field` — a reviewer's
--   decision. The API must never edit a proposal, a document record or a page
--   classification: those are the pipeline's account of what it did, and a
--   record that can be edited by the thing being audited is not a record.
--
-- Nothing is granted on dataops to fundermaps_webservice or
-- fundermaps_tileserver. The review lane is staff-only and has no place in a
-- billable product API or a public tile server.
--
--   psql "$ADMIN_URL" -f sql/migrate/grant_dataops_to_webapp.sql

GRANT USAGE ON SCHEMA dataops TO fundermaps_webapp;

GRANT SELECT ON
    dataops.dossier,
    dataops.artifact,
    dataops.artifact_page,
    dataops.extraction,
    dataops.extraction_field,
    dataops.verdict
TO fundermaps_webapp;

-- the reviewer's decision
GRANT INSERT ON dataops.verdict TO fundermaps_webapp;
GRANT UPDATE (state) ON dataops.extraction_field TO fundermaps_webapp;

-- closing a dossier as a whole (POST /dataops/dossier/:id/outcome, API #115).
-- Column-scoped on purpose: the API may say what became of a submission, and
-- nothing else about it. Applied to prod 2026-08-27 after the first reviewer
-- hit "permission denied for table dossier" on the first real close.
GRANT UPDATE (outcome, outcome_note, outcome_at) ON dataops.dossier TO fundermaps_webapp;

-- and the same for tables a later migration adds
ALTER DEFAULT PRIVILEGES IN SCHEMA dataops GRANT SELECT ON TABLES TO fundermaps_webapp;
