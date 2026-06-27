-- Issue #973 — Phase 2 (recovery mirror). Backfill
-- report.recovery.data_owner_organization_id from the current attribution owner.
-- Idempotent (only touches rows that differ). Run AFTER add_recovery_data_owner.sql.
--   psql "$DB_URL" -f sql/migrate/backfill_recovery_data_owner.sql

BEGIN;

UPDATE report.recovery r
SET data_owner_organization_id = a.owner_id
FROM application.attribution a
WHERE r.attribution_id = a.id
  AND r.data_owner_organization_id IS DISTINCT FROM a.owner_id;

-- attribution.owner_id is NOT NULL and recovery.attribution_id is NOT NULL,
-- so every recovery must now have a data owner. Abort if any remain null.
SELECT count(*) FILTER (WHERE data_owner_organization_id IS NULL) AS still_null,
       count(*)                                                   AS total
FROM report.recovery;

DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM report.recovery WHERE data_owner_organization_id IS NULL;
  IF v <> 0 THEN
    RAISE EXCEPTION 'ABORT: % recoveries still have no data_owner_organization_id', v;
  END IF;
END $$;

COMMIT;
