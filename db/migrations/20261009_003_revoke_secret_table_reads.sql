-- Stop `grafana` and `fundermaps_webservice` reading two secret-bearing tables
-- they never use.
--
--   application.application  legacy app registry; `secret` is set on every row
--   application.apikey       the fmsk.* keys; `key` (hash), `start` (readable
--                            prefix) and `metadata`
--
-- Both roles had table-level SELECT on application.application, and grafana
-- also had it on application.apikey. Least privilege: drop what nothing reads,
-- and give grafana only the apikey columns its usage board shows.
--
-- True on prod 2026-10-09 (DB grant audit; read-only checks):
--   * FunderMapsWebservice (origin/main) never references
--     application.application, and ran 0 statements against it since the stats
--     reset (2026-10-08). It keeps its SELECT on application.apikey, which it
--     verifies keys against.
--   * No Grafana panel (6 dashboards) or dashboard variable reads
--     application.application. The three API-key panels read apikey.name,
--     reference_id, enabled, last_request and request_count only.
--   * All four grants were made by `fundermaps`, the table owner, so the runner
--     (doadmin, a member of fundermaps) can revoke them.
--
-- sql/init/grants.sql gets the same change, so a fresh database matches prod.
-- Where a role does not exist, its part is skipped with a NOTICE.

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafana') THEN
        REVOKE SELECT ON application.application FROM grafana;
        REVOKE SELECT ON application.apikey FROM grafana;
        GRANT SELECT (name, reference_id, last_request, request_count, enabled)
            ON application.apikey TO grafana;

        IF has_table_privilege('grafana', 'application.application', 'SELECT')
           OR has_table_privilege('grafana', 'application.apikey', 'SELECT')
           OR has_column_privilege('grafana', 'application.apikey', 'key', 'SELECT') THEN
            RAISE EXCEPTION 'grafana can still read application.application or apikey.key (granted by another role?)';
        END IF;
    ELSE
        RAISE NOTICE 'role grafana does not exist; skipped';
    END IF;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webservice') THEN
        REVOKE SELECT ON application.application FROM fundermaps_webservice;

        IF has_table_privilege('fundermaps_webservice', 'application.application', 'SELECT') THEN
            RAISE EXCEPTION 'fundermaps_webservice can still read application.application (granted by another role?)';
        END IF;
    ELSE
        RAISE NOTICE 'role fundermaps_webservice does not exist; skipped';
    END IF;
END
$$;
