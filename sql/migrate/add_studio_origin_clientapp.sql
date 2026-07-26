-- Allow ClientApp to be served from studio.fundermaps.com as well as
-- app.fundermaps.com.
--
-- The invoer app was rebuilt as the FunderMaps Data Studio and moves to
-- studio.fundermaps.com; app.fundermaps.com stays attached and 301s across.
-- ClientApp derives its OIDC redirect_uri from `window.location.origin` (see
-- services/oidc.ts), so the new host produces
-- `https://studio.fundermaps.com/auth/callback` and, on logout,
-- `https://studio.fundermaps.com/login`. Neither is registered, and the
-- provider rejects an unregistered redirect_uri — so without this, login on the
-- new host fails for everyone.
--
-- **Additive on purpose.** The app.fundermaps.com entries stay: they keep the
-- old host working during the cutover and are the rollback path if the redirect
-- has to come off in a hurry. Drop them only once nothing resolves to the old
-- host any more.
--
-- Apply BEFORE studio.fundermaps.com is attached to the DO app. Idempotent —
-- the guards make a re-run a no-op rather than a duplicate array entry.
--
--   psql "$DB_URL" -f sql/migrate/add_studio_origin_clientapp.sql

BEGIN;

UPDATE application.oauth_application
   SET redirect_uris = array_append(redirect_uris,
                                    'https://studio.fundermaps.com/auth/callback'),
       updated_at    = now()
 WHERE client_id = 'clientapp'
   AND NOT ('https://studio.fundermaps.com/auth/callback' = ANY (redirect_uris));

UPDATE application.oauth_application
   SET post_logout_redirect_uris = array_append(
         coalesce(post_logout_redirect_uris, '{}'),
         'https://studio.fundermaps.com/login'),
       updated_at = now()
 WHERE client_id = 'clientapp'
   AND NOT ('https://studio.fundermaps.com/login'
            = ANY (coalesce(post_logout_redirect_uris, '{}')));

COMMIT;
