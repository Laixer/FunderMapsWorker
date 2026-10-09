-- grafana sessions in this database start read-only.
--
-- grafana is the login of the analytics app (Grafana): its fundermaps
-- datasource runs whatever SQL a dashboard author types. After 20261009_007
-- it only holds SELECT on the tables it charts, but PUBLIC still has CREATE on
-- schema public, so that SQL can create objects there. A read-only default
-- makes dashboard SQL read-only unless someone switches it off on purpose;
-- it is a guard rail, not a boundary (a session can still SET it back), and
-- the root fix is REVOKE CREATE ON SCHEMA public FROM PUBLIC, which needs DO
-- support (they own the schema).
--
-- Scoped to THIS database on purpose: grafana is also Grafana's backend user
-- for its own database (grafana), which must stay writable.
--
-- True on prod 2026-10-09 (read-only checks): grafana had no role or
-- per-database settings; doadmin (the runner) has ADMIN OPTION on the role;
-- Grafana has 0 alert rules and its dashboards only read. Open sessions keep
-- their old setting until they reconnect.
--
-- Skipped with a NOTICE where the role does not exist.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafana') THEN
        RAISE NOTICE 'role grafana does not exist; nothing changed';
        RETURN;
    END IF;

    EXECUTE format('ALTER ROLE grafana IN DATABASE %I SET default_transaction_read_only = on',
                   current_database());

    IF NOT EXISTS (
        SELECT FROM pg_db_role_setting s
        JOIN pg_database d ON d.oid = s.setdatabase
        WHERE s.setrole = 'grafana'::regrole
          AND d.datname = current_database()
          AND 'default_transaction_read_only=on' = ANY (s.setconfig)
    ) THEN
        RAISE EXCEPTION 'grafana is not read-only by default in %', current_database();
    END IF;
END
$$;
