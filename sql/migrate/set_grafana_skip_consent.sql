-- Flip the Grafana OIDC client to skip the consent screen.
--
-- Background: `add_oauth_application_skip_consent.sql` (Phase 1, step 3) added
-- `skip_consent boolean NOT NULL DEFAULT false` and noted that "a first-party
-- SSO row is flipped to true explicitly" — but that flip for Grafana was never
-- actually applied. Under the bundled `oidc-provider` plugin this went
-- unnoticed because consent-skip came from a hardcoded `trustedClients` array
-- in FunderMapsApi, not the column.
--
-- After the `@better-auth/oauth-provider` swap (oauth_provider_v2_migration.sql
-- + FunderMapsApi#55), the new plugin reads ONLY `oauth_application.skip_consent`
-- per-client: `if (client.skipConsent) <issue code> else <redirect to consentPage>`.
-- With Grafana at the default `false`, every login lands on the consent page
-- (a stub URL on ManagementFront that 404s/renders empty), so SSO breaks.
--
-- Grafana is a trusted first-party SSO client and must skip consent. This sets
-- the column accordingly. Idempotent — safe to re-run.

BEGIN;

UPDATE application.oauth_application
   SET skip_consent = true
 WHERE client_id = 'grafana'
   AND skip_consent IS DISTINCT FROM true;

COMMIT;
