-- windmill_user cannot log in any more.
--
-- windmill_user is the row-level-security role Windmill uses inside its own
-- backend database `windmill` on the same cluster: the Windmill server and its
-- worker log in as windmill_admin, a member, and SET ROLE to it. Nobody logs in
-- as windmill_user itself (0 sessions, 0 statements since the stats reset;
-- no DATABASE_URL or Windmill resource names it). It has LOGIN only because
-- doctl creates every user with LOGIN. SET ROLE works without it.
-- (Its last odd member, fundermaps_windmill, left in 20261009_001.)
--
-- doadmin (the runner) has CREATEROLE and ADMIN OPTION on the role. Skipped
-- with a NOTICE where the role does not exist.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'windmill_user') THEN
        RAISE NOTICE 'role windmill_user does not exist; nothing changed';
        RETURN;
    END IF;

    ALTER ROLE windmill_user NOLOGIN;

    IF (SELECT rolcanlogin FROM pg_roles WHERE rolname = 'windmill_user') THEN
        RAISE EXCEPTION 'windmill_user can still log in';
    END IF;
END
$$;
