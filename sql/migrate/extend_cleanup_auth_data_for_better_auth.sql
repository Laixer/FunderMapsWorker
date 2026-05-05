-- Extend application.cleanup_auth_data() to prune Better Auth tables.
--
-- pg_cron Job 5 runs this procedure every 10 minutes. It originally only
-- handled the legacy C# WebApi auth tables (auth_access_token, auth_code,
-- auth_refresh_token, reset_key). Better Auth (TS API) writes to its own
-- tables which were leaking expired rows.
--
-- Added pruning for:
--   * application.session              — delete when expires_at < NOW()
--   * application.verification         — delete when expires_at < NOW()
--                                        (password reset / email confirm codes)
--   * application.oauth_access_token   — delete only when BOTH access and
--                                        refresh tokens have expired (so a
--                                        valid refresh can still mint a new
--                                        access token)

CREATE OR REPLACE PROCEDURE application.cleanup_auth_data()
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE NOTICE 'Starting authentication data cleanup';

    -- Legacy C# WebApi tables --------------------------------------------------

    DELETE FROM application.auth_access_token
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired access tokens (legacy).', FOUND::TEXT;

    DELETE FROM application.auth_code
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired auth codes (legacy).', FOUND::TEXT;

    DELETE FROM application.auth_refresh_token
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired refresh tokens (legacy).', FOUND::TEXT;

    DELETE FROM application.reset_key
    WHERE create_date < (NOW() - INTERVAL '1 hour');
    RAISE NOTICE 'Deleted % old reset keys (legacy).', FOUND::TEXT;

    -- Better Auth tables -------------------------------------------------------

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
