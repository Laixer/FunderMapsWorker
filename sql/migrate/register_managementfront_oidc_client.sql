-- Register ManagementFront (the admin app, admin.fundermaps.com) as a trusted
-- OIDC client. Better Auth migration Step 4.
--
-- NOTE: this registers the client row only — ManagementFront's frontend is NOT
-- yet wired as an OIDC client (that's a later change). The row is inert until
-- then (nothing redirects to /auth/callback yet); registering it now is harmless.
--
-- Public PKCE client, skip_consent, end-session enabled, offline_access (admin
-- sessions want silent refresh — ManagementFront already has a refresh-token
-- model). Mirrors the webfront row but for admin.fundermaps.com. Idempotent.
--
--   psql "$DB_URL" -f sql/migrate/register_managementfront_oidc_client.sql

BEGIN;

INSERT INTO application.oauth_application
  (id, name, client_id, client_secret, application_type, token_endpoint_auth_method,
   skip_consent, require_pkce, disabled, enable_end_session,
   redirect_uris, post_logout_redirect_uris, grant_types, response_types, scopes)
VALUES
  ('managementfront', 'ManagementFront (admin)', 'managementfront', NULL, 'web', 'none',
   true, true, false, true,
   '{https://admin.fundermaps.com/auth/callback}',
   '{https://admin.fundermaps.com/login}',
   '{authorization_code,refresh_token}', '{code}',
   '{openid,email,profile,offline_access}')
ON CONFLICT (client_id) DO UPDATE SET
  name                       = EXCLUDED.name,
  application_type           = EXCLUDED.application_type,
  token_endpoint_auth_method = EXCLUDED.token_endpoint_auth_method,
  skip_consent               = EXCLUDED.skip_consent,
  require_pkce               = EXCLUDED.require_pkce,
  disabled                   = EXCLUDED.disabled,
  enable_end_session         = EXCLUDED.enable_end_session,
  redirect_uris              = EXCLUDED.redirect_uris,
  post_logout_redirect_uris  = EXCLUDED.post_logout_redirect_uris,
  grant_types                = EXCLUDED.grant_types,
  response_types             = EXCLUDED.response_types,
  scopes                     = EXCLUDED.scopes,
  updated_at                 = now();

COMMIT;
