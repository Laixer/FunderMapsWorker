-- Bring back the cleanup of expired Better Auth sessions and verification tokens (Yorick 2026-11-11: "Do 1. first").
--
-- pg_cron job 5 runs every 10 minutes and called application.cleanup_auth_data(). That procedure was dropped on
-- 2026-10-30 (20261030_001) as unused. The check behind that drop looked for pg_cron in this database only; pg_cron
-- lives in the cluster's defaultdb and schedules into this one. The job has failed on every run since, and expired
-- rows stayed: on 2026-11-11, 109 of 174 sessions and 12 of 13 verification tokens. Better Auth does not remove them.
--
-- The procedure comes back in auth, next to the tables it cleans (they moved there on 2026-11-08). expires_at is a
-- timestamp without time zone that holds UTC, so it is compared with the UTC wall clock, whatever the time zone of the
-- session that calls it. The body is bound to the tables themselves (BEGIN ATOMIC), so it follows a rename, as a view
-- does. OR REPLACE, so a database that already has it from schema.sql takes this file without an error.
-- The job is pointed at it by hand, as doadmin in defaultdb: db/cron.sql.
CREATE OR REPLACE PROCEDURE auth.cleanup_expired()
    LANGUAGE sql
BEGIN ATOMIC
    DELETE FROM auth.session WHERE expires_at < (now() AT TIME ZONE 'UTC');
    DELETE FROM auth.verification WHERE expires_at < (now() AT TIME ZONE 'UTC');
END;

ALTER PROCEDURE auth.cleanup_expired() OWNER TO fundermaps;
REVOKE ALL ON PROCEDURE auth.cleanup_expired() FROM PUBLIC;

COMMENT ON PROCEDURE auth.cleanup_expired() IS
    '[Better Auth] Deletes expired sessions and verification tokens. Called every 10 minutes by pg_cron job 5, which '
    'lives in database defaultdb (db/cron.sql in FunderMapsWorker). Do not drop or rename it without changing that job.';
