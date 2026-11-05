-- Remove what the grafana role can reach (Yorick 2026-11-05: "go, remove it"). The Grafana app no longer exists.
--
-- Its login goes first, so the password stops working whatever happens next. DROP OWNED then revokes its grants in this
-- database. It raises a WARNING, not an error, for grants made by postgres (spatial_ref_sys), which doadmin cannot revoke;
-- those are harmless once the role cannot log in. The role and its own database are managed by DigitalOcean and are
-- deleted through doctl right after this file; rolling that into this file is not possible.
--
-- A fresh database (CI, a test VM) no longer creates the role, hence the guard. A role that owns anything here stops the
-- file: DROP OWNED would drop those objects too, and on prod it owns nothing in this database.
SET LOCAL lock_timeout = '2s';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana') THEN
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_shdepend s
                 JOIN pg_database d ON d.oid = s.dbid
                WHERE d.datname = current_database()
                  AND s.refobjid = (SELECT oid FROM pg_roles WHERE rolname = 'grafana')
                  AND s.deptype = 'o') THEN
        RAISE EXCEPTION 'grafana owns objects in this database; stopping';
    END IF;
    ALTER ROLE grafana NOLOGIN;
    DROP OWNED BY grafana;
END
$$;
