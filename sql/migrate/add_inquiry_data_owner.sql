-- Issue #973 ("Users / Data vereenvoudiging") — Phase 1.
-- Add a durable "data owner" organization to report.inquiry.
--
-- Why: once inquiries are entered under a central processing account, the
-- attribution.owner_id no longer reliably reflects the organization that
-- actually owns the data. data_owner_organization_id is the lasting field that
-- holds the real owning organization, independent of who processed the inquiry.
-- Access scoping (Phase 4) will switch from attribution.owner_id to this column.
--
-- Nullable: filled by the Phase 2 backfill (data_owner_organization_id :=
-- attribution.owner_id) and set explicitly at entry time going forward. Rows
-- without a value fall back to attribution.owner_id in the API until backfilled.
--
-- Idempotent — safe to re-run.
--   psql "$DB_URL" -f sql/migrate/add_inquiry_data_owner.sql

BEGIN;

ALTER TABLE report.inquiry
  ADD COLUMN IF NOT EXISTS data_owner_organization_id application.organization_id;

-- FK guarded so the migration stays idempotent (ADD CONSTRAINT has no IF NOT EXISTS).
-- ON DELETE RESTRICT: an organization that still owns inquiry data cannot be
-- deleted out from under it (mirrors the conservative attribution owner FK).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'inquiry_data_owner_organization_id_fkey'
      AND conrelid = 'report.inquiry'::regclass
  ) THEN
    ALTER TABLE report.inquiry
      ADD CONSTRAINT inquiry_data_owner_organization_id_fkey
      FOREIGN KEY (data_owner_organization_id)
      REFERENCES application.organization(id)
      ON UPDATE CASCADE ON DELETE RESTRICT;
  END IF;
END $$;

-- Phase 4 scopes the inquiry list/CRUD on this column.
CREATE INDEX IF NOT EXISTS inquiry_data_owner_organization_id_idx
  ON report.inquiry USING btree (data_owner_organization_id);

COMMENT ON COLUMN report.inquiry.data_owner_organization_id IS
  'Organization that owns this inquiry''s data (#973). Durable owner, independent of the processing/attribution account; nullable until backfilled (Phase 2), then falls back to attribution.owner_id in the API.';

COMMIT;
