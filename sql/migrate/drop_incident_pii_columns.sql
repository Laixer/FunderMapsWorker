-- Drop the PII columns from report.incident.
--
-- Data side was anonymized in prod 2026-05-11 — all four columns set
-- to NULL across the table. This migration removes the columns
-- entirely so the schema no longer carries an empty PII footprint.
--
-- Coordinated with:
--   FunderMaps        chore/drop-incident-pii-columns
--                     drops INSERT/SELECT/UPDATE refs + Incident entity props
--   FunderMapsApi     chore/drop-incident-pii-columns
--                     drops drizzle fields + explicit SELECT in routes/incident.ts
--   FunderMapsReport  chore/drop-incident-pii-columns
--                     drops adapter mapping + IIncidentReport fields
--
-- Sequencing: apply this ONLY after the C# deploy carrying the
-- IncidentRepository edits has rolled. Otherwise the WebApi
-- ReportController.ListAllByBuildingIdAsync SELECT will reference
-- columns that no longer exist and 500 on every report-by-building
-- read.

BEGIN;

ALTER TABLE report.incident
    DROP COLUMN contact,
    DROP COLUMN contact_name,
    DROP COLUMN contact_phone_number,
    DROP COLUMN note;

COMMIT;
