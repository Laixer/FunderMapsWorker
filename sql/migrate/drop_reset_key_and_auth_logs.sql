-- Drop legacy auth tables: application.reset_key and application.auth_logs.
--
-- reset_key was the C# WebApi's password-reset-token store, superseded by
-- Better Auth's `verification` table.
-- auth_logs was the C# WebApi's audit log, never adopted by the TS API.
--
-- Both tables were referenced only by the now-retired C# WebApi
-- (FunderMaps repo, src/FunderMaps.WebApi). The still-deployed C# Webservice
-- (ws.fundermaps.com) does not read either, and no FKs in other tables
-- point at them.
--
-- The cleanup_auth_data() pg_cron procedure was DELETEing from reset_key
-- every 10 minutes — that block is removed in the same patch.

CREATE OR REPLACE PROCEDURE application.cleanup_auth_data()
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE NOTICE 'Starting authentication data cleanup';

    -- Legacy C# WebApi tables (auth_access_token / auth_code /
    -- auth_refresh_token still in use by C# Webservice).
    DELETE FROM application.auth_access_token
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired access tokens (legacy).', FOUND::TEXT;

    DELETE FROM application.auth_code
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired auth codes (legacy).', FOUND::TEXT;

    DELETE FROM application.auth_refresh_token
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired refresh tokens (legacy).', FOUND::TEXT;

    -- Better Auth tables.
    DELETE FROM application.session
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired Better Auth sessions.', FOUND::TEXT;

    DELETE FROM application.verification
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired Better Auth verifications.', FOUND::TEXT;

    DELETE FROM application.oauth_access_token
    WHERE access_token_expires_at < NOW()
      AND refresh_token_expires_at < NOW();
    RAISE NOTICE 'Deleted % fully-expired OAuth access tokens.', FOUND::TEXT;

    RAISE NOTICE 'Authentication data cleanup finished';
END;
$$;

DROP TABLE application.reset_key;
DROP TABLE application.auth_logs;
