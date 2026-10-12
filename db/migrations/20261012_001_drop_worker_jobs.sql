-- Why: the queue worker is retired (Worker #147).
--
-- application.worker_jobs was the queue the worker droplet (fundermaps-worker-0)
-- polled. Its last job type, process_mapset (the GPKG archive export), has run
-- as the Windmill script f/fundermaps/mapset/export_tileset since the cut-over
-- of 2026-10-12 07:20 UTC, and the droplet was deleted the same day. Nothing
-- processes this queue any more, so a row inserted now would wait forever.
--
-- Prod when written (2026-10-12): 1,052 rows (1,044 completed, 8 failed, none
-- pending or processing), last created 2026-10-12 00:03 UTC. No foreign key,
-- view or function refers to the table, and application.job_status is used by
-- this table only. fundermaps_windmill holds INSERT, SELECT on it
-- (20261009_009); grants go with the table. The job history is not kept.
--
-- ORDER: apply only after the API release without /api/management/jobs is
-- live and the admin portal has lost its Jobs page. Until then the admin
-- dashboard reads this table through the API and would get a 500.

DROP TABLE application.worker_jobs;

DROP TYPE application.job_status;
