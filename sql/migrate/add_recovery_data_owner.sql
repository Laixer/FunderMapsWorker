-- Issue #973 ("Users / Data vereenvoudiging") — Phase 1 (recovery mirror).
-- Same change as add_inquiry_data_owner.sql, applied to report.recovery so the
-- two report tables stay symmetric. data_owner_organization_id is the durable
-- owning organization, independent of the processing/attribution account.
--
-- Nullable: filled by backfill_recovery_data_owner.sql and set explicitly at
-- entry time going forward. Idempotent — safe to re-run.
--   psql "$DB_URL" -f sql/migrate/add_recovery_data_owner.sql

BEGIN;

ALTER TABLE report.recovery
  ADD COLUMN IF NOT EXISTS data_owner_organization_id application.organization_id;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recovery_data_owner_organization_id_fkey'
      AND conrelid = 'report.recovery'::regclass
  ) THEN
    ALTER TABLE report.recovery
      ADD CONSTRAINT recovery_data_owner_organization_id_fkey
      FOREIGN KEY (data_owner_organization_id)
      REFERENCES application.organization(id)
      ON UPDATE CASCADE ON DELETE RESTRICT;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS recovery_data_owner_organization_id_idx
  ON report.recovery USING btree (data_owner_organization_id);

COMMENT ON COLUMN report.recovery.data_owner_organization_id IS
  'Organization that owns this recovery''s data (#973). Durable owner, independent of the processing/attribution account; nullable until backfilled, then falls back to attribution.owner_id in the API.';

COMMIT;
