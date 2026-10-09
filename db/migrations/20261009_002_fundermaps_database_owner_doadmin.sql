-- Hand the database itself from `windmill_admin` to `doadmin`.
--
-- `windmill_admin` is the login of the Windmill server and its worker, for
-- Windmill's own backend database `windmill` on the same cluster. It also
-- owned this database, which lets it drop it, create schemas in it and act as
-- pg_database_owner here. Nothing needs that: Windmill's FunderMaps scripts
-- log in as `fundermaps_windmill`, and every object in our schemas belongs to
-- `fundermaps` (20260920_003). `doadmin` is what DO makes the owner of a
-- database it creates, and the role the migration runner applies as on prod.
--
-- True on prod 2026-10-09 (read-only catalog queries, DB grant audit):
--   * windmill_admin owns no relation, function, type or schema in this
--     database and ran no statement in it since the stats reset (2026-10-08).
--   * Windmill runs its own schema migrations (sqlx, 671 so far) in database
--     `windmill`, which windmill_admin owns and keeps owning; there is no
--     trace of them here. FunderMaps' migrations run as doadmin.
--   * doadmin is a member of windmill_admin (INHERIT, SET) and has CREATEDB,
--     which is what ALTER DATABASE ... OWNER needs.
--   * TimescaleDB job 3 ("Job History Log Retention Policy") is owned by
--     windmill_admin and has failed every run since 2026-03-05 with "not
--     supported under the current apache license"; it keeps failing the same
--     way. The explicit CONNECT grant to fundermaps_windmill survives; its
--     grantor becomes the new owner.
--
-- Where the database is not owned by windmill_admin (CI bootstrap, a test VM)
-- or doadmin does not exist, the file raises a NOTICE and changes nothing.

DO $$
DECLARE
    owner_now text;
BEGIN
    SELECT pg_get_userbyid(datdba) INTO owner_now
    FROM pg_database WHERE datname = current_database();

    IF owner_now <> 'windmill_admin' THEN
        RAISE NOTICE 'database % is owned by %, not windmill_admin; nothing changed', current_database(), owner_now;
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'doadmin') THEN
        RAISE NOTICE 'role doadmin does not exist; nothing changed';
        RETURN;
    END IF;

    EXECUTE format('ALTER DATABASE %I OWNER TO doadmin', current_database());
END
$$;
