-- One-shot: remove the Grafana OIDC client from the Better Auth OAuth provider.
--
-- Grafana (analytics.fundermaps.com) is internal-only in FunderMaps 5.0 and
-- uses local logins. Its "Sign in with FunderMaps" SSO was switched off on
-- 2026-09-07 (sso_setting row deleted, GF_AUTH_GENERIC_OAUTH_ENABLED=false in
-- the app spec) and this client never issued a single token: 0 access, 0
-- refresh, 0 consents since it was registered on 2026-04-25.
--
-- The three first-party PKCE clients (webfront, clientapp, managementfront)
-- stay until the cookie-auth move retires the oauthProvider plugin as a whole.
--
-- Run as doadmin (fundermaps lacks DELETE on the token tables). Applied to prod 2026-09-07.
DELETE FROM application.oauth_client_resource WHERE client_id = 'grafana';
DELETE FROM application.oauth_consent        WHERE client_id = 'grafana';
DELETE FROM application.oauth_refresh_token  WHERE client_id = 'grafana';
DELETE FROM application.oauth_access_token   WHERE client_id = 'grafana';
DELETE FROM application.oauth_application    WHERE client_id = 'grafana';
