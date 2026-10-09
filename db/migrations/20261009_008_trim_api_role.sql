-- Least privilege for the API role: drop privileges no code path uses
-- (DB grant audit, 2026-10-09). FunderMapsApi logs in as fundermaps_api, a
-- member of fundermaps_webapp, which holds the grants.
--
-- True on prod 2026-10-09 (FunderMapsApi origin/main + ~19 h of
-- pg_stat_statements; read-only checks):
--   * No code writes: application.auth_key (INSERT; keys are only read,
--     touched and deleted), application_user / dossier_address (DELETE; rows
--     go only through FK cascades, which run with the table owner's rights),
--     the organization_geolock_* tables and organization_mapset (UPDATE; they
--     are inserted and deleted), report.incident (read-only route).
--   * No code reads the data/geocoder/maplayer objects below; the views the
--     API does read (e.g. data.model_risk_static) run with their owner's
--     rights.
-- Deliberately NOT here (Better Auth internals, needs a closer look): the
-- SELECT/UPDATE on serial sequences, verification UPDATE, invitation writes.
--
-- Skipped with a NOTICE where fundermaps_webapp does not exist; fails if any
-- revoked privilege survives.

DO $$
DECLARE
    unread text[] := ARRAY[
        'data.building_cluster', 'data.building_elevation',
        'data.building_geographic_region', 'data.building_groundwater_level',
        'data.building_height', 'data.building_ownership', 'data.building_pleistocene',
        'data.model_risk_static_2024_1', 'data.model_version', 'data.product_tracker_daily',
        'data.supercluster', 'geocoder.building_active', 'maplayer.bundle'];
    o text;
    leftover text;
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        RAISE NOTICE 'role fundermaps_webapp does not exist; nothing changed';
        RETURN;
    END IF;

    REVOKE INSERT ON application.auth_key FROM fundermaps_webapp;
    REVOKE DELETE ON application.application_user, dataops.dossier_address FROM fundermaps_webapp;
    REVOKE UPDATE ON application.organization_geolock_district,
                     application.organization_geolock_municipality,
                     application.organization_geolock_neighborhood,
                     application.organization_mapset
        FROM fundermaps_webapp;
    REVOKE INSERT, UPDATE, DELETE ON report.incident FROM fundermaps_webapp;
    FOREACH o IN ARRAY unread LOOP
        EXECUTE format('REVOKE SELECT ON %s FROM fundermaps_webapp', o);
    END LOOP;

    SELECT string_agg(t, ', ') INTO leftover FROM unnest(unread) t
    WHERE has_table_privilege('fundermaps_webapp', t, 'SELECT');
    IF leftover IS NOT NULL THEN
        RAISE EXCEPTION 'fundermaps_webapp can still read: %', leftover;
    END IF;
    IF has_table_privilege('fundermaps_webapp', 'application.auth_key', 'INSERT')
       OR has_table_privilege('fundermaps_webapp', 'application.application_user', 'DELETE')
       OR has_table_privilege('fundermaps_webapp', 'dataops.dossier_address', 'DELETE')
       OR has_table_privilege('fundermaps_webapp', 'application.organization_geolock_district', 'UPDATE')
       OR has_table_privilege('fundermaps_webapp', 'application.organization_geolock_municipality', 'UPDATE')
       OR has_table_privilege('fundermaps_webapp', 'application.organization_geolock_neighborhood', 'UPDATE')
       OR has_table_privilege('fundermaps_webapp', 'application.organization_mapset', 'UPDATE')
       OR has_table_privilege('fundermaps_webapp', 'report.incident', 'INSERT, UPDATE, DELETE') THEN
        RAISE EXCEPTION 'fundermaps_webapp still holds a revoked write privilege';
    END IF;
END
$$;
