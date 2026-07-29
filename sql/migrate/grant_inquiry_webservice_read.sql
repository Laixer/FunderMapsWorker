-- Read access for the TS Webservice on report.inquiry (FunderMaps issue #1003).
--
-- The /v4/product/facade_scan and /v4/product/foundation-research endpoints join
-- report.inquiry (for type, document_date and attribution) onto
-- report.inquiry_sample. fundermaps_webservice held SELECT on inquiry_sample but
-- not on inquiry, so both endpoints returned 500 ("permission denied for table
-- inquiry") for every request — including on ws-staging, where they have been
-- live and broken since #22 shipped.
--
-- sql/init/grants.sql already covers this for fresh DBs (GRANT SELECT ON ALL
-- TABLES IN SCHEMA ... report plus ALTER DEFAULT PRIVILEGES), but production
-- drifted: only incident and inquiry_sample carry the grant, while inquiry,
-- recovery, recovery_sample and dossier_event do not. Same drift pattern as
-- issue #997 (application.contractor). Idempotent — safe to re-run.
--
--   psql "$DB_URL" -f sql/migrate/grant_inquiry_webservice_read.sql
--
-- Scoped to inquiry only, deliberately. This is a billable, internet-facing,
-- read-only role; the remaining report.* tables are not read by any v4 endpoint,
-- so they stay ungranted rather than being restored to the grants.sql baseline
-- wholesale. Widen this if a future product endpoint needs recovery data.

BEGIN;

GRANT SELECT ON report.inquiry TO fundermaps_webservice;

COMMIT;
