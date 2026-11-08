-- Step 1 of 3 of moving the Better Auth tables to their own schema, auth (Yorick 2026-11-08: "go ahead with the auth
-- schema move").
--
-- The 10 tables Better Auth reads and writes live in application, next to our own tables. They move to auth in three
-- steps, so that every app switches on its own and can go back on its own:
--   1. this file: schema auth, with a view per table onto the table in application. Nothing uses them yet.
--   2. Studio, Webservice, Worker and Fundie switch to auth.*, one at a time.
--   3. one transaction drops these views and moves the tables (ALTER TABLE ... SET SCHEMA auth), with their types.
--
-- Each view copies what its table has: the grants, column by column (Fundie and the Webservice only get some columns),
-- and the column defaults, so an insert through the view gets the same ids and timestamps. Views like these are
-- updatable, RETURNING and ON CONFLICT included. auth gets no default privileges: unlike in application, a new table
-- here is not readable by Fundie until someone grants it.
--
-- On prod on 2026-11-08: 10 tables, no view, function, trigger or search_path naming them, no row-level security, 19
-- foreign keys from other tables into user and organization (they follow the move by themselves).
SET LOCAL lock_timeout = '2s';

DO $$
DECLARE
    t text;
    base oid;
    owner_oid oid;
    d record;
    g record;
    n_defaults int := 0;
    n_grants int := 0;
BEGIN
    IF EXISTS (SELECT FROM pg_namespace WHERE nspname = 'auth') THEN
        RAISE EXCEPTION 'schema auth already exists; stopping';
    END IF;
    -- AUTHORIZATION, not ALTER SCHEMA ... OWNER TO: a new schema owner needs CREATE on the database, which fundermaps
    -- does not have on prod; this form only asks it of the role that runs the file (doadmin).
    CREATE SCHEMA auth AUTHORIZATION fundermaps;

    FOREACH t IN ARRAY ARRAY['user', 'session', 'account', 'verification', 'passkey', 'apikey', 'organization',
                             'organization_user', 'invitation', 'organization_custom_role'] LOOP
        base := format('application.%I', t)::regclass;
        SELECT relowner INTO owner_oid FROM pg_class WHERE oid = base;
        EXECUTE format('CREATE VIEW auth.%I AS SELECT * FROM application.%I', t, t);
        EXECUTE format('ALTER VIEW auth.%I OWNER TO fundermaps', t);
        EXECUTE format('COMMENT ON VIEW auth.%I IS %L', t,
            '[Better Auth] Stand-in for application.' || t || ' while the Better Auth tables move to auth: '
            || 'the table itself takes this name in step 3 of 3.');

        FOR d IN SELECT a.attname, pg_get_expr(ad.adbin, ad.adrelid) AS expr
                   FROM pg_attrdef ad JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
                  WHERE ad.adrelid = base AND a.attgenerated = '' LOOP
            EXECUTE format('ALTER VIEW auth.%I ALTER COLUMN %I SET DEFAULT %s', t, d.attname, d.expr);
            n_defaults := n_defaults + 1;
        END LOOP;

        FOR g IN SELECT x.privilege_type, x.grantee::regrole::text AS grantee
                   FROM pg_class c, aclexplode(c.relacl) x
                  WHERE c.oid = base AND x.grantee NOT IN (owner_oid, 0) LOOP
            EXECUTE format('GRANT %s ON auth.%I TO %s', g.privilege_type, t, g.grantee);
            n_grants := n_grants + 1;
        END LOOP;

        FOR g IN SELECT a.attname, x.privilege_type, x.grantee::regrole::text AS grantee
                   FROM pg_attribute a, aclexplode(a.attacl) x
                  WHERE a.attrelid = base AND a.attnum > 0 AND NOT a.attisdropped AND x.grantee NOT IN (owner_oid, 0) LOOP
            EXECUTE format('GRANT %s (%I) ON auth.%I TO %s', g.privilege_type, g.attname, t, g.grantee);
            n_grants := n_grants + 1;
        END LOOP;
    END LOOP;

    -- Every role that can reach one of the tables can reach the schema; nothing else can.
    FOR g IN SELECT DISTINCT x.grantee::regrole::text AS grantee
               FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(c.relacl) x
              WHERE n.nspname = 'auth' AND x.grantee NOT IN (c.relowner, 0)
             UNION
             SELECT DISTINCT x.grantee::regrole::text
               FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               JOIN pg_attribute a ON a.attrelid = c.oid, aclexplode(a.attacl) x
              WHERE n.nspname = 'auth' AND x.grantee NOT IN (c.relowner, 0) LOOP
        EXECUTE format('GRANT USAGE ON SCHEMA auth TO %s', g.grantee);
    END LOOP;

    RAISE NOTICE 'auth: 10 views, % defaults and % grants copied from application', n_defaults, n_grants;
END
$$;

COMMENT ON SCHEMA auth IS 'Better Auth''s tables: users, logins, sessions, passkeys, API keys, organisations and their '
    'members. Better Auth in the Studio API writes them. No default privileges: every grant here is explicit.';
