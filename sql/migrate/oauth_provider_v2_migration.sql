-- Phase 1, step 4 of the Better Auth migration plan: swap the bundled
-- `better-auth/plugins/oidc-provider` (deprecated, slated for removal in
-- BA 1.7) for `@better-auth/oauth-provider`. The new plugin's schema is
-- substantially different — this migration reshapes the existing tables
-- to match in place rather than creating a parallel set.
--
-- *** This migration MUST ship with the paired FunderMapsApi swap. ***
-- The bundled plugin reads `oauth_application.redirect_urls` (CSV text)
-- and a plaintext `client_secret`. After this migration runs, both shapes
-- are incompatible — the bundled plugin will start failing immediately.
--
-- Cross-stack coordination:
--  1. Apply this migration on prod.
--  2. Deploy the paired FunderMapsApi PR (which configures the new plugin
--     and the Drizzle schema overrides).
--
-- Side effects:
--  * All active OIDC sessions (Grafana) invalidate — oauth_access_token /
--    oauth_consent are truncated. Users sign back in via Grafana → OK.
--  * `oauth_application.client_secret` is hashed in-place using the new
--    plugin's defaultHasher (SHA-256 → base64url-no-padding). Grafana keeps
--    sending the SAME plaintext secret it sends today; the plugin verifies
--    hash(received) === stored at request time.

BEGIN;

-- 1. Extend oauth_application with all new plugin fields.
ALTER TABLE application.oauth_application
    ADD COLUMN IF NOT EXISTS redirect_uris               text[],
    ADD COLUMN IF NOT EXISTS post_logout_redirect_uris   text[],
    ADD COLUMN IF NOT EXISTS scopes                      text[],
    ADD COLUMN IF NOT EXISTS grant_types                 text[],
    ADD COLUMN IF NOT EXISTS response_types              text[],
    ADD COLUMN IF NOT EXISTS contacts                    text[],
    ADD COLUMN IF NOT EXISTS require_pkce                boolean,
    ADD COLUMN IF NOT EXISTS "public"                    boolean,
    ADD COLUMN IF NOT EXISTS enable_end_session          boolean,
    ADD COLUMN IF NOT EXISTS subject_type                text,
    ADD COLUMN IF NOT EXISTS uri                         text,
    ADD COLUMN IF NOT EXISTS tos                         text,
    ADD COLUMN IF NOT EXISTS policy                      text,
    ADD COLUMN IF NOT EXISTS software_id                 text,
    ADD COLUMN IF NOT EXISTS software_version            text,
    ADD COLUMN IF NOT EXISTS software_statement          text,
    ADD COLUMN IF NOT EXISTS token_endpoint_auth_method  text,
    ADD COLUMN IF NOT EXISTS reference_id                text;

-- 2. Convert redirect_urls (CSV text) → redirect_uris (text[]).
UPDATE application.oauth_application
   SET redirect_uris = string_to_array(redirect_urls, ',')
 WHERE redirect_uris IS NULL AND redirect_urls IS NOT NULL;

ALTER TABLE application.oauth_application
    ALTER COLUMN redirect_uris SET NOT NULL;

ALTER TABLE application.oauth_application
    DROP COLUMN redirect_urls;

-- 3. Convert metadata text → jsonb. Existing rows hold valid JSON or NULL.
ALTER TABLE application.oauth_application
    ALTER COLUMN metadata TYPE jsonb USING
        CASE WHEN metadata IS NULL OR metadata = '' THEN NULL::jsonb
             ELSE metadata::jsonb END;

-- 4. Hash any plaintext client_secrets in-place. SHA-256 → base64url
--    (no padding) matches the new plugin's defaultHasher.
--    Length guard: 43 chars = SHA-256/base64url-no-pad, treat as already
--    hashed. If you somehow have a 43-char plaintext, manually rotate.
UPDATE application.oauth_application
   SET client_secret = translate(
           encode(digest(client_secret, 'sha256'), 'base64'),
           '+/=', '-_'
       )
 WHERE client_secret IS NOT NULL
   AND length(client_secret) <> 43;

-- 4b. Preserve the bundled plugin's `requirePKCE: false` plugin-wide
--     behavior for pre-migration clients. The new plugin defaults to PKCE
--     required when require_pkce IS NULL, which would break Grafana's
--     generic_oauth client (no code_verifier sent). Explicit false on the
--     existing rows; new clients should leave it null/true.
UPDATE application.oauth_application
   SET require_pkce = false
 WHERE require_pkce IS NULL;

-- 5. Wipe active OIDC sessions — old row shape is incompatible with the
--    new plugin. Users re-login.
TRUNCATE application.oauth_access_token CASCADE;
TRUNCATE application.oauth_consent CASCADE;

-- 6. Reshape oauth_access_token to match the new plugin's `oauthAccessToken`
--    model (separates access + refresh into two tables).
ALTER TABLE application.oauth_access_token
    DROP COLUMN refresh_token,
    DROP COLUMN refresh_token_expires_at,
    DROP COLUMN updated_at;

ALTER TABLE application.oauth_access_token
    RENAME COLUMN access_token TO token;

ALTER TABLE application.oauth_access_token
    RENAME COLUMN access_token_expires_at TO expires_at;

ALTER TABLE application.oauth_access_token
    ADD COLUMN session_id   text REFERENCES application.session(id) ON DELETE SET NULL,
    ADD COLUMN reference_id text,
    ADD COLUMN refresh_id   text;

-- scopes text → text[]. Was space-separated by the bundled plugin.
ALTER TABLE application.oauth_access_token
    ALTER COLUMN scopes TYPE text[] USING string_to_array(scopes, ' ');

-- 7. Create the new oauth_refresh_token table (the new plugin separates
--    access + refresh; the bundled plugin packed both into one row).
CREATE TABLE IF NOT EXISTS application.oauth_refresh_token (
    id           text PRIMARY KEY,
    token        text NOT NULL UNIQUE,
    client_id    text NOT NULL
                 REFERENCES application.oauth_application(client_id)
                 ON DELETE CASCADE,
    session_id   text REFERENCES application.session(id) ON DELETE SET NULL,
    user_id      uuid NOT NULL
                 REFERENCES application."user"(id) ON DELETE CASCADE,
    reference_id text,
    expires_at   timestamp without time zone NOT NULL,
    created_at   timestamp without time zone NOT NULL DEFAULT now(),
    revoked      timestamp without time zone,
    auth_time    timestamp without time zone,
    scopes       text[] NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_oauth_refresh_token_client_id
    ON application.oauth_refresh_token(client_id);
CREATE INDEX IF NOT EXISTS idx_oauth_refresh_token_session_id
    ON application.oauth_refresh_token(session_id);
CREATE INDEX IF NOT EXISTS idx_oauth_refresh_token_user_id
    ON application.oauth_refresh_token(user_id);

-- Hook refresh_id FK now that the refresh table exists.
ALTER TABLE application.oauth_access_token
    ADD CONSTRAINT oauth_access_token_refresh_id_fkey
    FOREIGN KEY (refresh_id)
    REFERENCES application.oauth_refresh_token(id)
    ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_oauth_access_token_session_id
    ON application.oauth_access_token(session_id);
CREATE INDEX IF NOT EXISTS idx_oauth_access_token_refresh_id
    ON application.oauth_access_token(refresh_id);

-- 8. Reshape oauth_consent. The new plugin treats row existence as consent
--    (no consent_given flag), allows user_id to be NULL when consent is
--    bound to a reference_id (e.g. org/team scoping later), and stores
--    scopes as an array.
ALTER TABLE application.oauth_consent
    DROP COLUMN consent_given,
    ALTER COLUMN user_id DROP NOT NULL,
    ADD COLUMN reference_id text;

ALTER TABLE application.oauth_consent
    ALTER COLUMN scopes TYPE text[] USING string_to_array(scopes, ' ');

-- 9. Grant the webapp role the privileges it had on oauth_application
--    extended to the new oauth_refresh_token table. Grants for
--    oauth_access_token / oauth_consent carry over since the table
--    identity is unchanged.
GRANT SELECT, INSERT, UPDATE, DELETE
   ON application.oauth_refresh_token
   TO fundermaps_webapp;

-- 10. The cleanup_auth_data() pg_cron procedure references the dropped
--     column names (access_token_expires_at, refresh_token_expires_at);
--     rewrite it for the new schema. Access + refresh tokens are now in
--     separate tables and share an `expires_at` column name.
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

    -- Better Auth tables -------------------------------------------------------

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

COMMIT;
