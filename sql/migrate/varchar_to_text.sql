-- Convert varchar/character-varying columns to text where the length cap
-- is arbitrary or absent. Per Postgres docs and our 17.9 build:
-- ALTER COLUMN ... TYPE text from varchar(N) or varchar (no len) is
-- metadata-only when no constraint is dropped that would invalidate
-- existing rows. All three columns below have actual max lengths well
-- below their declared caps (verified 2026-04-25).
--
-- Skipped intentionally:
--   * geocoder.postal_code.postal_code  varchar(6) — meaningful length
--     constraint for Dutch postal codes; keep as-is.
--   * maplayer.facade_scan.priority — column on a view, can't ALTER
--     directly; would need to fix the view's underlying expression.
--
-- Run as: fundermaps (owner)

BEGIN;

-- application.worker_jobs.job_type: varchar(255) → text (max actual: 14)
ALTER TABLE application.worker_jobs
    ALTER COLUMN job_type TYPE text;

-- report.incident.contact_name: varchar (uncapped) → text (max actual: 82)
ALTER TABLE report.incident
    ALTER COLUMN contact_name TYPE text;

-- report.incident.contact_phone_number: varchar (uncapped) → text (max actual: 29)
ALTER TABLE report.incident
    ALTER COLUMN contact_phone_number TYPE text;

COMMIT;
