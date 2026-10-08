-- Read-only access for `fundie_agent`, the login role of Fundie (FunderMaps'
-- AI agent for support, ops and dossier work) on its own VM.
--
-- The role is NOT created here. On DO Managed PG a login role is made with
-- `doctl databases user create <cluster-id> fundie_agent`, which generates the
-- password and makes doadmin an ADMIN member of the new role; that membership
-- is what lets this file ALTER ROLE it, as for every other service role.
-- Where the role does not exist (the CI schema bootstrap, a test VM) the file
-- raises a NOTICE and changes nothing. On prod the role must exist before this
-- file is applied: once recorded in the ledger it does not run again, and a
-- late role then needs a follow-up migration. (`fundie_ro` is a different, more
-- restricted role reserved for the product chatbot; not this one.)
--
-- True on prod 2026-10-08 (read-only catalog queries):
--   * PostgreSQL 18.6. Every table, view and matview in application, data,
--     dataops, geocoder, maplayer and report is owned by `fundermaps`
--     (20260920_003); the matviews doadmin used to own are among them.
--   * doadmin is a member of `fundermaps` (with SET) and an ADMIN member of
--     every doctl-created role, so it can GRANT on fundermaps' objects, ALTER
--     DEFAULT PRIVILEGES FOR ROLE fundermaps, and ALTER ROLE ... SET.
--   * doctl-created roles get no memberships and no attributes: before this
--     file fundie_agent can read only what PUBLIC can.
--
-- GRANTED: USAGE on the schemas application, data, dataops, geocoder,
-- maplayer, report, and SELECT on every table, view and matview in them,
-- except what is listed below. Nothing else: no INSERT/UPDATE/DELETE, no
-- sequences, no EXECUTE beyond what PUBLIC already has. Left out on purpose:
-- `public` (PostGIS catalogue and pg_stat_statements, readable by PUBLIC
-- already) and the TimescaleDB schemas (extension internals).
--
-- EXCLUDED, whole table (no SELECT at all):
--   application.verification         identifier + value hold email-verification
--                                    and password-reset tokens
--   application.jwks                 private_key is the OIDC signing key; the
--                                    other columns are of no use without it
--   application.oauth_access_token   token = live OAuth access tokens
--   application.oauth_refresh_token  token + rotation_replay_response = refresh
--                                    tokens
--
-- EXCLUDED, columns (the table is readable without them; grants per column):
--   application.account            password (credential hash), access_token,
--                                  refresh_token, id_token
--   application.session            token (a session token is a login)
--   application.auth_key           key_hash (legacy API key)
--   application.apikey             key (fmsk.* key hash), start (first
--                                  characters of the plaintext key), metadata
--                                  (free-form, not reviewed)
--   application.passkey            public_key, credential_id, counter,
--                                  transports (WebAuthn credential material;
--                                  the same cut grafana has)
--   application.application        secret (legacy OAuth client secret)
--   application.oauth_application  client_secret
--
-- READABLE ON PURPOSE: application."user" (name, email, phone; there is no
-- password column on user, passwords live in account.password) and
-- dataops.dossier.submitter (melder contact details) are personal data that
-- support and dossier work need. application.api_key_rate_limit and
-- application.product_tracker hold no secret.
--
-- Read-only rests on these privileges. The role defaults below
-- (default_transaction_read_only and the timeouts) are a second guard for an
-- agent that writes its own SQL, not the wall: a session can override them.
--
-- FUTURE TABLES: default privileges make every new table, view and matview in
-- these schemas readable for fundie_agent, whether a migration creates it
-- (doadmin) or fundermaps does (the Worker, and the SECURITY DEFINER tile
-- refresh procedures that rebuild maplayer.*_tiles every night). The price: a
-- new table holding secrets is readable too. A migration that adds an auth,
-- token or key table (or a secret column to a table listed as readable above)
-- must REVOKE it from fundie_agent in the same file. Tables with column grants
-- are the other way round: a new column there stays unreadable until granted.
--
-- Idempotent: GRANT, REVOKE, ALTER ROLE ... SET and ALTER DEFAULT PRIVILEGES
-- all converge on a re-run. The table-level REVOKE also drops the column
-- grants, which the next statements put back.

DO $$
DECLARE
    owner_role text;
    r record;
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundie_agent') THEN
        RAISE NOTICE 'role fundie_agent does not exist; nothing granted (on prod, create it with doctl databases user create BEFORE applying this file)';
        RETURN;
    END IF;

    -- Role defaults, applied at the start of every new session.
    ALTER ROLE fundie_agent SET default_transaction_read_only = on;
    ALTER ROLE fundie_agent SET statement_timeout = '60s';
    ALTER ROLE fundie_agent SET lock_timeout = '5s';
    ALTER ROLE fundie_agent SET idle_in_transaction_session_timeout = '60s';

    GRANT USAGE ON SCHEMA application, data, dataops, geocoder, maplayer, report TO fundie_agent;

    GRANT SELECT ON ALL TABLES IN SCHEMA application, data, dataops, geocoder, maplayer, report
        TO fundie_agent;

    -- A hypertable on prod: an object-level GRANT is what TimescaleDB copies
    -- onto the existing chunks (their ACLs match the parent's for every other
    -- role). A plain table elsewhere, where this is a no-op.
    GRANT SELECT ON application.product_tracker TO fundie_agent;

    -- Exclusions. REVOKE ALL on a table also removes its column grants.
    REVOKE ALL ON application.verification,
                  application.jwks,
                  application.oauth_access_token,
                  application.oauth_refresh_token,
                  application.account,
                  application.session,
                  application.auth_key,
                  application.apikey,
                  application.passkey,
                  application.application,
                  application.oauth_application
        FROM fundie_agent;

    GRANT SELECT (id, user_id, account_id, provider_id, access_token_expires_at,
                  refresh_token_expires_at, scope, created_at, updated_at, issuer)
        ON application.account TO fundie_agent;

    GRANT SELECT (id, user_id, expires_at, ip_address, user_agent, created_at, updated_at,
                  impersonated_by, active_organization_id)
        ON application.session TO fundie_agent;

    GRANT SELECT (id, user_id, name, last_used, expires_at, created_at, updated_at)
        ON application.auth_key TO fundie_agent;

    GRANT SELECT (id, config_id, name, prefix, reference_id, refill_interval, refill_amount,
                  last_refill_at, enabled, rate_limit_enabled, rate_limit_time_window,
                  rate_limit_max, request_count, remaining, last_request, expires_at,
                  created_at, updated_at, permissions)
        ON application.apikey TO fundie_agent;

    GRANT SELECT (id, name, user_id, device_type, backed_up, created_at, aaguid)
        ON application.passkey TO fundie_agent;

    GRANT SELECT (application_id, name, data, redirect_url, public, user_id)
        ON application.application TO fundie_agent;

    GRANT SELECT (id, name, icon, metadata, client_id, disabled, user_id, created_at, updated_at,
                  skip_consent, redirect_uris, post_logout_redirect_uris, scopes, grant_types,
                  response_types, contacts, require_pkce, enable_end_session, subject_type, uri,
                  tos, policy, software_id, software_version, software_statement,
                  token_endpoint_auth_method, reference_id, application_type,
                  client_credentials_scopes, client_discovery_id, backchannel_logout_uri,
                  backchannel_logout_session_required, jwks, jwks_uri, dpop_bound_access_tokens)
        ON application.oauth_application TO fundie_agent;

    -- Future objects, for each role that creates them (see FUTURE TABLES).
    FOREACH owner_role IN ARRAY ARRAY['fundermaps', 'doadmin'] LOOP
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = owner_role) THEN
            EXECUTE format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA application, data, dataops, geocoder, maplayer, report GRANT SELECT ON TABLES TO fundie_agent',
                owner_role);
        ELSE
            RAISE NOTICE 'role % does not exist; no default privileges set for it', owner_role;
        END IF;
    END LOOP;

    -- Self-check: fail the migration (and roll it back) rather than leave a
    -- secret readable or a write privilege behind.
    FOR r IN
        SELECT * FROM (VALUES
            ('application.account', 'password'),
            ('application.account', 'access_token'),
            ('application.account', 'refresh_token'),
            ('application.account', 'id_token'),
            ('application.session', 'token'),
            ('application.auth_key', 'key_hash'),
            ('application.apikey', 'key'),
            ('application.apikey', 'start'),
            ('application.apikey', 'metadata'),
            ('application.passkey', 'public_key'),
            ('application.passkey', 'credential_id'),
            ('application.application', 'secret'),
            ('application.oauth_application', 'client_secret'),
            ('application.verification', 'value'),
            ('application.verification', 'identifier'),
            ('application.jwks', 'private_key'),
            ('application.oauth_access_token', 'token'),
            ('application.oauth_refresh_token', 'token'),
            ('application.oauth_refresh_token', 'rotation_replay_response')
        ) AS s(tbl, col)
    LOOP
        IF has_column_privilege('fundie_agent', r.tbl, r.col, 'SELECT') THEN
            RAISE EXCEPTION 'fundie_agent can read %.%', r.tbl, r.col;
        END IF;
    END LOOP;

    FOR r IN
        SELECT c.oid::regclass AS rel
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('application', 'data', 'dataops', 'geocoder', 'maplayer', 'report')
          AND c.relkind IN ('r', 'v', 'm', 'p', 'f')
          AND has_table_privilege('fundie_agent', c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
    LOOP
        RAISE EXCEPTION 'fundie_agent has a write privilege on %', r.rel;
    END LOOP;

    IF NOT has_table_privilege('fundie_agent', 'report.inquiry', 'SELECT')
       OR NOT has_column_privilege('fundie_agent', 'application.account', 'provider_id', 'SELECT') THEN
        RAISE EXCEPTION 'fundie_agent is missing an expected read grant';
    END IF;
END $$;
