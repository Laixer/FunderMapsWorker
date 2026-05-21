-- Register WebFront (the maps app, maps.fundermaps.com) as a trusted OIDC
-- client. Better Auth migration Step 4: WebFront signs in via the auth app.
--
-- Like the clientapp row, but with:
--   - offline_access scope → the provider issues a refresh token, so WebFront
--     silently renews the 1h access token (no mid-session map reload);
--   - end-session enabled, post-logout back to the map root (guest mode).
--
-- Public client (no secret), PKCE required, consent skipped. Idempotent.
--
--   psql "$DB_URL" -f sql/migrate/register_webfront_oidc_client.sql

BEGIN;

INSERT INTO application.oauth_application
  (id, name, client_id, client_secret, type, public, token_endpoint_auth_method,
   skip_consent, require_pkce, disabled, enable_end_session,
   redirect_uris, post_logout_redirect_uris, grant_types, response_types, scopes)
VALUES
  ('webfront', 'WebFront (maps)', 'webfront', NULL, 'web', true, 'none',
   true, true, false, true,
   '{https://maps.fundermaps.com/auth/callback}',
   '{https://maps.fundermaps.com/}',
   '{authorization_code,refresh_token}', '{code}',
   '{openid,email,profile,offline_access}')
ON CONFLICT (client_id) DO UPDATE SET
  name                       = EXCLUDED.name,
  public                     = EXCLUDED.public,
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
