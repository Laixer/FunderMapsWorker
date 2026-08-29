-- Better Auth 1.7 schema upgrade — phase A (FunderMapsApi better-auth 1.6.30 → 1.7.2).
--
-- Why: better-auth 1.7.0 (2026-08-18) changed the models behind the OAuth
-- provider, JWT and core account plugins. The Drizzle adapter throws at
-- RUNTIME on the first column it does not know, which is how the 1.7.1 bump
-- took every OIDC login down for 3 h on 2026-08-23. This file is the DDL half
-- of the deliberate migration; the Drizzle half is FunderMapsApi
-- chore/better-auth-1.7 (src/lib/auth-schema.test.ts proves they agree).
--
-- Exact expectations were taken from getAuthTables() of 1.7.2 with our
-- plugin set (bearer, jwt, organization, admin, api-key, oauth-provider).
-- organization / admin / api-key / session / user models are unchanged.
--
-- BACKWARD COMPATIBLE BY DESIGN: the 1.6 API keeps working after this runs —
--   * account.issuer gets a DEFAULT, so 1.6 inserts (which do not set it) succeed;
--   * oauth_application.type loses its NOT NULL (1.7 never writes it) but is
--     kept, so a 1.6 rollback still has it;
--   * everything else is nullable or defaulted.
-- Rollback of the app is therefore "redeploy the previous build"; the schema
-- stays. Phase B (drop_better_auth_legacy_client_columns.sql) removes the
-- legacy columns once 1.7 has been live for a while.
--
-- Run as `doadmin`: the oauth_* and jwks tables are owned by doadmin (Better
-- Auth created them through the DO database binding the API runs on);
-- account is owned by fundermaps. Idempotent — safe to re-run.
--   psql "$DOADMIN_URL" -v ON_ERROR_STOP=1 -f sql/migrate/upgrade_better_auth_1_7.sql

BEGIN;

-- ── account: identity is now (issuer, account_id) ─────────────────────────
-- Password accounts carry the synthetic issuer 'local:credential' and
-- account_id = user id; 1.7's sign-in matches on all three, so a wrong
-- backfill locks everyone out. Prod has only credential accounts.

ALTER TABLE application.account ADD COLUMN IF NOT EXISTS issuer text;

UPDATE application.account
   SET issuer = 'local:credential'
 WHERE issuer IS NULL AND provider_id = 'credential';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM application.account WHERE issuer IS NULL) THEN
    RAISE EXCEPTION 'account rows with a non-credential provider_id need a manual issuer (see the 1.7 upgrade guide)';
  END IF;
  IF EXISTS (SELECT 1 FROM application.account
              WHERE provider_id = 'credential' AND account_id <> user_id::text) THEN
    RAISE EXCEPTION 'credential account rows where account_id <> user_id: 1.7 sign-in would reject them';
  END IF;
END $$;

ALTER TABLE application.account ALTER COLUMN issuer SET DEFAULT 'local:credential';
ALTER TABLE application.account ALTER COLUMN issuer SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS account_issuer_account_id_key
  ON application.account (issuer, account_id);

-- ── jwks: per-key algorithm / curve ────────────────────────────────────────
-- NULL inherits the plugin's keyPairConfig (EdDSA/Ed25519), which is exactly
-- what the existing key is; set it explicitly so the row is self-describing.

ALTER TABLE application.jwks
  ADD COLUMN IF NOT EXISTS alg text,
  ADD COLUMN IF NOT EXISTS crv text;

UPDATE application.jwks
   SET alg = 'EdDSA', crv = 'Ed25519'
 WHERE alg IS NULL AND (public_key::jsonb ->> 'crv') = 'Ed25519';

-- ── oauth_application (BA model oauthClient) ───────────────────────────────

ALTER TABLE application.oauth_application
  ADD COLUMN IF NOT EXISTS application_type text,
  ADD COLUMN IF NOT EXISTS client_credentials_scopes text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS client_discovery_id text,
  ADD COLUMN IF NOT EXISTS backchannel_logout_uri text,
  ADD COLUMN IF NOT EXISTS backchannel_logout_session_required boolean,
  ADD COLUMN IF NOT EXISTS jwks text,
  ADD COLUMN IF NOT EXISTS jwks_uri text,
  ADD COLUMN IF NOT EXISTS dpop_bound_access_tokens boolean DEFAULT false;

-- 1.7 replaces the legacy type/public pair: application_type is 'web' |
-- 'native', and token_endpoint_auth_method = 'none' is what marks a public
-- client. All four prod rows are type='web'; the three SPAs already say
-- 'none'. Grafana (confidential, has a secret) had NULL, which 1.7 treats as
-- client_secret_basic — write that down explicitly.
UPDATE application.oauth_application
   SET application_type = COALESCE(type, 'web')
 WHERE application_type IS NULL;

UPDATE application.oauth_application
   SET token_endpoint_auth_method = 'none'
 WHERE public IS TRUE AND token_endpoint_auth_method IS NULL;

UPDATE application.oauth_application
   SET token_endpoint_auth_method = 'client_secret_basic'
 WHERE token_endpoint_auth_method IS NULL AND client_secret IS NOT NULL;

-- 1.7 no longer writes `type`; keep the column for a 1.6 rollback but let
-- 1.7 insert clients. Dropped together with `public` in phase B.
ALTER TABLE application.oauth_application ALTER COLUMN type DROP NOT NULL;

-- ── oauth_access_token ─────────────────────────────────────────────────────

ALTER TABLE application.oauth_access_token
  ADD COLUMN IF NOT EXISTS authorization_code_id text,
  ADD COLUMN IF NOT EXISTS resources text[],
  ADD COLUMN IF NOT EXISTS requested_user_info_claims text[],
  ADD COLUMN IF NOT EXISTS revoked timestamp without time zone,
  ADD COLUMN IF NOT EXISTS confirmation jsonb;

-- ── oauth_refresh_token: rotation + replay window ──────────────────────────

ALTER TABLE application.oauth_refresh_token
  ADD COLUMN IF NOT EXISTS authorization_code_id text,
  ADD COLUMN IF NOT EXISTS resources text[],
  ADD COLUMN IF NOT EXISTS requested_user_info_claims text[],
  ADD COLUMN IF NOT EXISTS rotated_at timestamp without time zone,
  ADD COLUMN IF NOT EXISTS rotation_replay_response text,
  ADD COLUMN IF NOT EXISTS rotation_replay_expires_at timestamp without time zone,
  ADD COLUMN IF NOT EXISTS confirmation jsonb;

-- ── oauth_consent ──────────────────────────────────────────────────────────

ALTER TABLE application.oauth_consent
  ADD COLUMN IF NOT EXISTS resources text[],
  ADD COLUMN IF NOT EXISTS requested_user_info_claims text[];

-- ── new tables ─────────────────────────────────────────────────────────────
-- Protected resources (RFC 8707) + client↔resource links. Empty for us —
-- no first-party app requests resource indicators — but the token path
-- selects from them. oauth_client_assertion is the single-use jti registry
-- for private_key_jwt client auth (RFC 7523); id IS the jti.

CREATE TABLE IF NOT EXISTS application.oauth_resource (
    id text PRIMARY KEY,
    identifier text NOT NULL UNIQUE,
    name text NOT NULL,
    access_token_ttl integer,
    refresh_token_ttl integer,
    signing_algorithm text,
    signing_key_id text,
    allowed_scopes text[],
    custom_claims jsonb,
    dpop_bound_access_tokens_required boolean NOT NULL DEFAULT false,
    disabled boolean NOT NULL DEFAULT false,
    policy_version integer NOT NULL DEFAULT 1,
    metadata jsonb,
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    updated_at timestamp without time zone NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS application.oauth_client_resource (
    id text PRIMARY KEY,
    client_id text NOT NULL REFERENCES application.oauth_application (client_id) ON DELETE CASCADE,
    resource_id text NOT NULL REFERENCES application.oauth_resource (identifier) ON DELETE CASCADE,
    metadata jsonb,
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT oauth_client_resource_client_id_resource_id_key UNIQUE (client_id, resource_id)
);

CREATE TABLE IF NOT EXISTS application.oauth_client_assertion (
    id text PRIMARY KEY,
    expires_at timestamp without time zone NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_oauth_client_assertion_expires_at
  ON application.oauth_client_assertion (expires_at);

-- Mirror the ACL the existing oauth_* tables carry: the API connects as
-- fundermaps_webapp (DO binding, PgBouncer api-pool) and 1.7's token path
-- SELECTs from these tables on every exchange — a missing grant here is a
-- 500 on login. fundermaps = ETL owner role, fundermaps_windmill = flows.
GRANT SELECT, INSERT, UPDATE, DELETE ON application.oauth_resource,
  application.oauth_client_resource, application.oauth_client_assertion
  TO fundermaps, fundermaps_webapp, fundermaps_windmill;

COMMIT;
