-- Backfill companion to FunderMapsApi's attach-time file_resources
-- transitions: uploads already referenced by an inquiry/recovery document
-- move 'uploaded' → 'active' so the file_resources_orphaned sweep stops
-- treating attached documents as orphan candidates. The API keeps rows
-- current from here on; this catches everything attached before that fix
-- deployed. Keys are the full S3 object key ('<folder>/<filename>') while
-- report.*.document_file stores the bare filename.
--
-- Run as the `fundermaps` role. Idempotent.
--   psql "$DB_URL" -f sql/migrate/backfill_file_resources_active.sql

BEGIN;

UPDATE application.file_resources fr
SET status = 'active',
    updated_at = now()
WHERE fr.status = 'uploaded'
  AND (
    EXISTS (
      SELECT 1 FROM report.inquiry i
      WHERE 'inquiry-report/' || i.document_file = fr.key
    )
    OR EXISTS (
      SELECT 1 FROM report.recovery r
      WHERE 'recovery-report/' || r.document_file = fr.key
    )
  );

COMMIT;
