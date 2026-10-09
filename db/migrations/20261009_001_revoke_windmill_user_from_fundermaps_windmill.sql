-- Take `fundermaps_windmill` out of the role `windmill_user`.
--
-- `fundermaps_windmill` is the login behind the Windmill resource
-- `f/fundermaps/managed_pg`: the role FunderMaps' Windmill scripts use on THIS
-- database. `windmill_user` is a different thing: the row-level-security role
-- Windmill itself uses in its own backend database `windmill`, on the same
-- cluster. Being a member gave the scripts' login access to Windmill's own
-- backend tables, which it has no business with. Nothing in FunderMaps needs
-- it. Probably a "GRANT windmill_user TO <db user>" from Windmill's
-- non-superuser setup, run for the wrong user.
--
-- True on prod 2026-10-09 (read-only catalog queries, DB grant audit):
--   * fundermaps_windmill is a direct member of windmill_user, granted by
--     doadmin, so doadmin (the runner on prod) can revoke it.
--   * In this database windmill_user has no grants, no schema USAGE and no
--     default privileges: revoking changes nothing for the Windmill scripts.
--   * The Windmill server and its worker log in as windmill_admin, which is a
--     member of windmill_user in its own right; that membership stays.
--   * Since the stats reset (2026-10-08 17:25 UTC) fundermaps_windmill ran
--     statements only in database `fundermaps`, never in `windmill`.
--
-- Where either role does not exist, or the membership is already gone (the CI
-- schema bootstrap, a test VM), the file raises a NOTICE and changes nothing.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_auth_members am
        JOIN pg_roles g ON g.oid = am.roleid
        JOIN pg_roles m ON m.oid = am.member
        WHERE g.rolname = 'windmill_user' AND m.rolname = 'fundermaps_windmill'
    ) THEN
        RAISE NOTICE 'fundermaps_windmill is not a member of windmill_user; nothing to revoke';
        RETURN;
    END IF;

    REVOKE windmill_user FROM fundermaps_windmill;

    -- REVOKE only removes grants made by the current role and merely warns
    -- otherwise; fail the migration rather than record a no-op.
    IF EXISTS (
        SELECT FROM pg_auth_members am
        JOIN pg_roles g ON g.oid = am.roleid
        JOIN pg_roles m ON m.oid = am.member
        WHERE g.rolname = 'windmill_user' AND m.rolname = 'fundermaps_windmill'
    ) THEN
        RAISE EXCEPTION 'fundermaps_windmill is still a member of windmill_user (granted by another role?)';
    END IF;
END
$$;
