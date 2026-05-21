-- Register ClientApp (the invoer app, app.fundermaps.com) as a trusted
-- first-party OIDC client. Part of the Better Auth migration Step 4
-- (auth.fundermaps.com SSO): ClientApp now signs in via authorization-code +
-- PKCE through the auth app instead of a local email/password form.
--
-- Public client (no secret), PKCE required, consent skipped (first-party,
-- trusted — same shape as the grafana row but public + PKCE). Idempotent:
-- re-running updates the mutable fields.
--
-- Pairs with FunderMapsApi#feat/oidc-auth-spa, FunderMapsAuth#feat/oidc-resume,
-- FunderMapsClientApp#feat/oidc-client. Apply BEFORE the ClientApp deploy.
--
--   psql "$DB_URL" -f sql/migrate/register_clientapp_oidc_client.sql

BEGIN;

INSERT INTO application.oauth_application
  (id, name, client_id, client_secret, type, public, token_endpoint_auth_method,
   skip_consent, require_pkce, disabled,
   redirect_uris, grant_types, response_types, scopes)
VALUES
  ('clientapp', 'ClientApp', 'clientapp', NULL, 'web', true, 'none',
   true, true, false,
   '{https://app.fundermaps.com/auth/callback}',
   '{authorization_code,refresh_token}', '{code}', '{openid,email,profile}')
ON CONFLICT (client_id) DO UPDATE SET
  name                       = EXCLUDED.name,
  public                     = EXCLUDED.public,
  token_endpoint_auth_method = EXCLUDED.token_endpoint_auth_method,
  skip_consent               = EXCLUDED.skip_consent,
  require_pkce               = EXCLUDED.require_pkce,
  disabled                   = EXCLUDED.disabled,
  redirect_uris              = EXCLUDED.redirect_uris,
  grant_types                = EXCLUDED.grant_types,
  response_types             = EXCLUDED.response_types,
  scopes                     = EXCLUDED.scopes,
  updated_at                 = now();

COMMIT;
