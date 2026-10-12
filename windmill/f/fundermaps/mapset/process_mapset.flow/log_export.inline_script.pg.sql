-- $1 tileset
-- $2 key
-- $3 bytes
-- $4 features
-- $5 seconds
-- One row per archive export (Worker #147): size and row count of what was
-- written, so a missing or shrinking snapshot shows up on a dashboard.
-- Readers of data.refresh_log filter on job = 'refresh_data_model'; this job
-- name does not touch them. A skipped export has no key and logs nothing.
INSERT INTO data.refresh_log (job, status, detail)
SELECT 'export_tileset', 'ok',
       jsonb_build_object(
         'tileset', $1::text,
         'key', $2::text,
         'bytes', $3::bigint,
         'features', $4::bigint,
         'seconds', $5::int)
WHERE $2::text IS NOT NULL
RETURNING id, job, finished_at, detail
