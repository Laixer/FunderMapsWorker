-- Drop the OAuth 2.1/OIDC provider tables and the JWKS table (cookie-auth
-- Phase D).
--
-- Since the cookie-auth migration (2026-09) every app — maps, studio, admin,
-- the auth SPA — authenticates with the Better Auth session cookie.
-- FunderMapsApi#236 removed the `oauthProvider` and `jwt` plugins, the OAuth
-- access-token branch of the auth middleware and the Drizzle definitions of
-- these tables. APPLY ONLY AFTER THAT API IS DEPLOYED: the previous API still
-- reads them.
--
-- True on prod 2026-10-09 (read-only checks):
--   * Nothing uses the provider: no OIDC code in any app, last refresh token
--     issued 2026-09-09, no consent rows, Grafana's generic OAuth disabled,
--     no /oauth2/authorize or /oauth2/token calls in the API logs.
--   * Contents: jwks 1 key, oauth_application 3 clients (webfront, clientapp,
--     managementfront), a handful of expired tokens; ~1.4 MB in total.
--   * Foreign keys only point FROM these tables (to "user", session, or each
--     other); no view, trigger or other function depends on them, except
--     application.cleanup_auth_data(), which pg_cron (job 5, database
--     defaultdb) CALLs every 10 minutes and which still deletes expired rows
--     from oauth_access_token and oauth_refresh_token. PL/pgSQL bodies are not
--     dependency-tracked, so it is trimmed first; otherwise the drop succeeds
--     and every cron run fails afterwards.
--   * Tables and procedure are owned by fundermaps; the runner (doadmin) is a
--     member, and CREATE OR REPLACE keeps the owner and the ACL.

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

    RAISE NOTICE 'Authentication data cleanup finished';
END;
$$;

DROP TABLE
    application.oauth_access_token,
    application.oauth_refresh_token,
    application.oauth_consent,
    application.oauth_client_resource,
    application.oauth_client_assertion,
    application.oauth_resource,
    application.oauth_application,
    application.jwks;

DO $$
DECLARE
    leftover text;
BEGIN
    SELECT string_agg(relname, ', ') INTO leftover
    FROM pg_class
    WHERE relnamespace = 'application'::regnamespace
      AND (relname LIKE 'oauth\_%' OR relname = 'jwks');
    IF leftover IS NOT NULL THEN
        RAISE EXCEPTION 'still present: %', leftover;
    END IF;

    IF EXISTS (
        SELECT FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname IN ('application', 'data', 'dataops', 'geocoder', 'maplayer', 'report')
          AND p.prosrc ~ '(oauth_|jwks)'
    ) THEN
        RAISE EXCEPTION 'a function in our schemas still references oauth_* or jwks';
    END IF;
END
$$;

-- The janitor must still run: one call, the same as a pg_cron tick.
CALL application.cleanup_auth_data();
