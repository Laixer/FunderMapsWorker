-- Step 3 of 3 of moving the Better Auth tables to their own schema, auth (Yorick 2026-11-08: "go ahead with the auth
-- schema move").
--
-- Step 1 (20261108_001) put a view per table in auth. Step 2 moved the Studio, the Webservice, the Worker and Fundie to
-- auth.*. This file drops those views and moves the tables themselves, with the six types they define or are keyed on
-- (email, phone, role, organization_role, user_id, organization_id; user_id and organization_id also type columns in other
-- tables, which keep pointing at them). Grants, column defaults, comments, indexes, constraints and the foreign keys from
-- other tables belong to the objects, not the names, so they come along. After this file application.<table> no longer
-- exists: anything that still uses an old name fails at once instead of reading stale data.
--
-- Rehearsed on a prod-shaped copy under traffic from the real Studio API and Webservice code (db-auth-schema/rehearsal/).
SET LOCAL lock_timeout = '2s';

DO $$
DECLARE
    t text;
    ty text;
    kind "char";
BEGIN
    FOREACH t IN ARRAY ARRAY['user', 'session', 'account', 'verification', 'passkey', 'apikey', 'organization',
                             'organization_user', 'invitation', 'organization_custom_role'] LOOP
        IF (SELECT relkind FROM pg_class WHERE oid = to_regclass(format('auth.%I', t))) IS DISTINCT FROM 'v' THEN
            RAISE EXCEPTION 'auth.% is not the step-1 view; stopping', t;
        END IF;
        IF (SELECT relkind FROM pg_class WHERE oid = to_regclass(format('application.%I', t))) IS DISTINCT FROM 'r' THEN
            RAISE EXCEPTION 'application.% is not a table; stopping', t;
        END IF;
        EXECUTE format('DROP VIEW auth.%I', t);
        EXECUTE format('ALTER TABLE application.%I SET SCHEMA auth', t);
    END LOOP;

    FOREACH ty IN ARRAY ARRAY['email', 'phone', 'role', 'organization_role', 'user_id', 'organization_id'] LOOP
        SELECT typtype INTO kind FROM pg_type
         WHERE typname = ty AND typnamespace = 'application'::regnamespace;
        IF kind = 'd' THEN
            EXECUTE format('ALTER DOMAIN application.%I SET SCHEMA auth', ty);
        ELSIF kind = 'e' THEN
            EXECUTE format('ALTER TYPE application.%I SET SCHEMA auth', ty);
        ELSE
            RAISE EXCEPTION 'type application.% not found as a domain or enum; stopping', ty;
        END IF;
    END LOOP;
END
$$;

COMMENT ON SCHEMA auth IS 'Better Auth''s tables: users, logins, sessions, passkeys, API keys, organisations and their '
    'members, with their types. Better Auth in the Studio API writes them. No default privileges: every grant here is explicit.';
