-- Take `fundermaps_windmill` off the login/token tables, the migration ledger
-- and write access to the billing record; stop it being re-granted.
--
-- `fundermaps_windmill` is the login behind Windmill's `f/fundermaps/managed_pg`.
-- It had full SELECT/INSERT/UPDATE/DELETE on every Better Auth table, on
-- application.schema_migrations and on application.product_tracker (the billing
-- record), none of which Windmill uses. The source is a prod-only default
-- privilege: every table a doadmin migration creates in `application` got
-- `fundermaps_windmill=arwd`. It is in no git file; this removes it, so a table
-- Windmill does need gets its GRANT in the migration that creates it (README).
--
-- True on prod 2026-10-09 (DB grant audit; read-only checks):
--   * No Windmill script or flow, and no Worker code Windmill runs in-process
--     (ingest_pending), touches any of the 17 tables below. Since the stats
--     reset (2026-10-08) fundermaps_windmill ran 0 statements against them.
--   * The only Windmill use of product_tracker is the monthly export_product:
--     SELECT + COPY ... TO STDOUT. SELECT stays.
--   * product_tracker is a TimescaleDB hypertable; each of its 61 chunks carries
--     its own copy of the grants (owner and grantor fundermaps). Chunks are
--     inheritance children, so they are revoked here explicitly as well; new
--     chunks copy the hypertable's ACL.
--   * Untouched: everything Windmill does use (worker_jobs, product_tracker
--     SELECT, dataops ingest, matview refreshes, tile tables, refresh_log).
--
-- Where fundermaps_windmill does not exist the file raises a NOTICE and changes
-- nothing. It fails rather than records a no-op if any privilege survives.

DO $$
DECLARE
    secret_tables text[] := ARRAY[
        'application.account', 'application.session', 'application.jwks',
        'application.verification', 'application.apikey', 'application.auth_key',
        'application."user"', 'application.invitation',
        'application.organization_custom_role', 'application.oauth_access_token',
        'application.oauth_refresh_token', 'application.oauth_application',
        'application.oauth_client_assertion', 'application.oauth_client_resource',
        'application.oauth_consent', 'application.oauth_resource',
        'application.schema_migrations'];
    t text;
    chunk regclass;
    leftover text;
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_windmill') THEN
        RAISE NOTICE 'role fundermaps_windmill does not exist; nothing changed';
        RETURN;
    END IF;

    FOREACH t IN ARRAY secret_tables LOOP
        EXECUTE format('REVOKE ALL ON %s FROM fundermaps_windmill', t);
    END LOOP;

    REVOKE INSERT, UPDATE, DELETE ON application.product_tracker FROM fundermaps_windmill;
    FOR chunk IN
        SELECT inhrelid::regclass FROM pg_inherits
        WHERE inhparent = 'application.product_tracker'::regclass
    LOOP
        EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON %s FROM fundermaps_windmill', chunk);
    END LOOP;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'doadmin') THEN
        ALTER DEFAULT PRIVILEGES FOR ROLE doadmin IN SCHEMA application
            REVOKE ALL ON TABLES FROM fundermaps_windmill;
    END IF;

    -- REVOKE only removes grants made by the current role (or the owner it acts
    -- for) and stays silent otherwise; check instead of trusting it.
    SELECT string_agg(s, ', ') INTO leftover
    FROM unnest(secret_tables) AS s
    WHERE has_table_privilege('fundermaps_windmill', s, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
       OR has_any_column_privilege('fundermaps_windmill', s, 'SELECT, INSERT, UPDATE, REFERENCES');
    IF leftover IS NOT NULL THEN
        RAISE EXCEPTION 'fundermaps_windmill still has privileges on: %', leftover;
    END IF;

    SELECT string_agg(c::text, ', ') INTO leftover
    FROM (SELECT 'application.product_tracker'::regclass AS c
          UNION ALL
          SELECT inhrelid::regclass FROM pg_inherits
          WHERE inhparent = 'application.product_tracker'::regclass) AS pt
    WHERE has_table_privilege('fundermaps_windmill', c, 'INSERT, UPDATE, DELETE');
    IF leftover IS NOT NULL THEN
        RAISE EXCEPTION 'fundermaps_windmill can still write: %', leftover;
    END IF;

    IF EXISTS (
        SELECT FROM pg_default_acl d
        JOIN pg_namespace n ON n.oid = d.defaclnamespace, aclexplode(d.defaclacl) x
        WHERE n.nspname = 'application' AND x.grantee = 'fundermaps_windmill'::regrole
    ) THEN
        RAISE EXCEPTION 'a default privilege in schema application still grants to fundermaps_windmill';
    END IF;
END
$$;
