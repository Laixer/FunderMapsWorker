-- Phase 1, step 3 of the Better Auth migration plan: generalize OIDC
-- `trustedClients` from a hardcoded array in FunderMapsApi src/lib/auth.ts
-- to a DB lookup. The bundled `better-auth/plugins/oidc-provider`'s
-- getClient() reads oauth_application rows but does NOT expose skipConsent
-- (or requirePKCE) on the returned shape — verified against installed
-- version. So FunderMapsApi loads rows where skip_consent = true at
-- startup and feeds them into the plugin's `trustedClients` array, which
-- short-circuits the DB lookup for first-party SSO consumers.
--
-- The column starts NOT NULL DEFAULT false: existing rows (and any future
-- third-party OIDC consumers) keep showing the consent screen by default;
-- a first-party SSO row is flipped to true explicitly.
--
-- Cross-stack coordination: the matching Drizzle field + the trustedClients
-- loader land in the FunderMapsApi paired PR. No C# changes — the OIDC
-- provider surface is TS-only.

BEGIN;

ALTER TABLE application.oauth_application
    ADD COLUMN IF NOT EXISTS skip_consent boolean NOT NULL DEFAULT false;

COMMIT;
