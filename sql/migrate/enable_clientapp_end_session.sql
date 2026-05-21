-- Enable RP-initiated logout (OIDC end-session) for the ClientApp OIDC client.
-- ClientApp's logout now redirects to /oauth2/end-session to end the SSO session
-- at the provider; without it a local-only logout would silently re-log the user
-- back in via the still-alive session. Sets the per-client enable_end_session
-- flag and the post-logout redirect target (back to /login for a fresh login).
--
-- Follows register_clientapp_oidc_client.sql (the row already exists in prod).
-- Idempotent. Pairs with FunderMapsClientApp's RP-logout change.
--
--   psql "$DB_URL" -f sql/migrate/enable_clientapp_end_session.sql

BEGIN;

UPDATE application.oauth_application
SET enable_end_session     = true,
    post_logout_redirect_uris = '{https://app.fundermaps.com/login}',
    updated_at             = now()
WHERE client_id = 'clientapp';

COMMIT;
