-- Issue #973 — Phase 2. Backfill report.inquiry.data_owner_organization_id from
-- the current attribution owner. After this, the data owner is captured durably
-- on the inquiry, independent of any later change to the processing account.
-- Idempotent (only touches rows that differ). Run AFTER add_inquiry_data_owner.sql.
--   psql "$DB_URL" -f sql/migrate/backfill_inquiry_data_owner.sql

BEGIN;

UPDATE report.inquiry i
SET data_owner_organization_id = a.owner_id
FROM application.attribution a
WHERE i.attribution_id = a.id
  AND i.data_owner_organization_id IS DISTINCT FROM a.owner_id;

-- Verify: attribution.owner_id is NOT NULL and inquiry.attribution_id is NOT NULL,
-- so every inquiry must now have a data owner. Abort if any remain null.
SELECT count(*) FILTER (WHERE data_owner_organization_id IS NULL) AS still_null,
       count(*)                                                   AS total
FROM report.inquiry;

DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM report.inquiry WHERE data_owner_organization_id IS NULL;
  IF v <> 0 THEN
    RAISE EXCEPTION 'ABORT: % inquiries still have no data_owner_organization_id', v;
  END IF;
END $$;

COMMIT;
