-- The scheduled jobs inside the database cluster (pg_cron).
--
-- pg_cron is installed in database `defaultdb`, NOT in `fundermaps`, and runs each job in the database named in the
-- job. So nothing in `fundermaps` shows that these jobs exist: no extension, no table, and a CALL is not recorded in
-- pg_stat_statements either. Before dropping or renaming a procedure, look here and in cron.job.
--
-- This file is the record; the migration runner does not apply it. Run a statement by hand, as doadmin, connected to
-- `defaultdb`, when a job changes, and change this file in the same pull request.
--
--   What is scheduled:   SELECT jobid, jobname, schedule, database, username, active, command FROM cron.job;
--   How the runs went:   SELECT status, count(*), max(start_time) FROM cron.job_run_details GROUP BY 1;
--   The last failures:   SELECT start_time, return_message FROM cron.job_run_details
--                         WHERE status <> 'succeeded' ORDER BY start_time DESC LIMIT 5;

-- Job 5 `cleanup-expired-tokens`, every 10 minutes, in database fundermaps, as doadmin:
-- remove expired Better Auth sessions and verification tokens (auth.cleanup_expired(), migration 20261111_002).
-- On prod the job exists since 2025; on 2026-11-11 its command was changed in place:
SELECT cron.alter_job(job_id := 5, command := 'CALL auth.cleanup_expired();');

-- To create it from nothing (a new cluster):
-- SELECT cron.schedule_in_database('cleanup-expired-tokens', '*/10 * * * *', 'CALL auth.cleanup_expired();', 'fundermaps');
