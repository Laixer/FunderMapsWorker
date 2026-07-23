-- Drop the legacy C# WebApi OAuth token tables.
--
-- application.auth_access_token / auth_code / auth_refresh_token were the
-- token store of the retired C# WebApi. Verified unused (2026-07-23):
--   * zero code references in FunderMapsApi runtime, the C# monolith
--     (WebApi + Webservice), Worker, and all frontends — only orphaned
--     Drizzle declarations in the API schema (removed separately);
--   * no dependent views, no other functions, no inbound FKs;
--   * pg_stat scan counts (~4.6k/31d per table) are fully accounted for by
--     pg_cron job 5, which CALLs application.cleanup_auth_data() every
--     10 minutes — the janitor was the only visitor.
-- State at drop: auth_access_token 0 rows, auth_code 0 rows,
-- auth_refresh_token 76 rows (last issued 2026-04-30; unredeemable since
-- the issuing service is retired). Better Auth uses the separate
-- application.session / oauth_* tables — untouched here.
--
-- Run as: fundermaps (owner of the tables and the procedure).

BEGIN;

-- Trim the legacy block out of the janitor first so the 10-minute pg_cron
-- run (job 5) never sees a missing table.
CREATE OR REPLACE PROCEDURE application.cleanup_auth_data()
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE NOTICE 'Starting authentication data cleanup';

    DELETE FROM application.session
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired Better Auth sessions.', FOUND::TEXT;

    DELETE FROM application.verification
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired Better Auth verifications.', FOUND::TEXT;

    DELETE FROM application.oauth_access_token
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired OAuth access tokens.', FOUND::TEXT;

    DELETE FROM application.oauth_refresh_token
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired OAuth refresh tokens.', FOUND::TEXT;

    RAISE NOTICE 'Authentication data cleanup finished';
END;
$$;

DROP TABLE application.auth_access_token;
DROP TABLE application.auth_code;
DROP TABLE application.auth_refresh_token;

COMMIT;
