-- Drop two objects nothing uses (Yorick 2026-10-30, after the DB object audit:
-- "drop application.cleanup_auth_data(), application.file_resources_orphaned").
--
-- application.cleanup_auth_data() — procedure that deleted expired Better Auth
-- sessions and verifications. Its only caller was pg_cron job 5, and pg_cron is
-- not installed since the PG18 upgrade (2026-08-07); no code, Windmill script or
-- flow calls it. Better Auth cleans up its own expired rows.
--
-- application.file_resources_orphaned — view over application.file_resources
-- (status uploaded/processing, untouched for a day). Meant for a cleanup sweep
-- that was never built: no code, Windmill script or flow reads it, only API
-- comments mention it. On prod it lists 477 rows; those uploads stay where they
-- are, only the view goes.
--
-- On prod (2026-10-30): both owned by fundermaps, no dependent objects; the view
-- had SELECT for fundie_agent (unused), which goes with it.

SET LOCAL lock_timeout = '2s';

DROP PROCEDURE application.cleanup_auth_data();

DROP VIEW application.file_resources_orphaned;
