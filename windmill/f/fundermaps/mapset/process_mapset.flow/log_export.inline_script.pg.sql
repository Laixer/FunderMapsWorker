-- $1 tileset
-- $2 key
-- $3 bytes
-- $4 features
-- $5 seconds
-- $6 parquet_bytes
-- One row per archive export (Worker #147): size and row count of what was
-- written, so a missing or shrinking snapshot shows up on a dashboard.
-- Readers of data.refresh_log filter on job = 'refresh_data_model'; this job
-- name does not touch them. A skipped export has no key and logs nothing.
-- parquet_bytes is null when the GeoParquet copy failed (the export itself
-- still succeeded).
INSERT INTO data.refresh_log (job, status, detail)
SELECT 'export_tileset', 'ok',
       jsonb_build_object(
         'tileset', $1::text,
         'key', $2::text,
         'bytes', $3::bigint,
         'features', $4::bigint,
         'seconds', $5::int,
         'parquet_bytes', $6::bigint)
WHERE $2::text IS NOT NULL
RETURNING id, job, finished_at, detail
