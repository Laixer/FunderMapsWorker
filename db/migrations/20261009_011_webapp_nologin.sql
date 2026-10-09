-- fundermaps_webapp cannot log in any more; it stays as the API's grant role.
--
-- fundermaps_webapp was the C# WebApi's login. Today it only holds the API's
-- privileges: FunderMapsApi logs in as fundermaps_api, a member of
-- fundermaps_webapp, and inherits them (membership does not need LOGIN).
-- Every migration keeps granting to fundermaps_webapp.
--
-- True on prod 2026-10-09 (read-only checks): 0 sessions and 0 statements as
-- fundermaps_webapp since the stats reset (2026-10-08 17:25 UTC); no app spec
-- DATABASE_URL, Windmill resource or repo connection string uses it. Its last
-- reference, a database attachment with db_user fundermaps_webapp on the
-- tileserver app that Martin never read, was removed from that app spec
-- before this was applied.
--
-- doadmin (the runner) has CREATEROLE and ADMIN OPTION on the role. Skipped
-- with a NOTICE where the role does not exist.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        RAISE NOTICE 'role fundermaps_webapp does not exist; nothing changed';
        RETURN;
    END IF;

    ALTER ROLE fundermaps_webapp NOLOGIN;

    IF (SELECT rolcanlogin FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        RAISE EXCEPTION 'fundermaps_webapp can still log in';
    END IF;
END
$$;
