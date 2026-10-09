-- Least privilege for the three read-only service roles: drop the SELECTs
-- nothing reads (DB grant audit, 2026-10-09).
--
--   fundermaps_webservice  FunderMapsWebservice (billable /v4 API)
--   grafana                Grafana's FunderMaps datasource (and its own backend DB)
--   fundermaps_tileserver  Martin
--
-- True on prod 2026-10-09 (read-only checks):
--   * Webservice: origin/main reads application.apikey, auth_key,
--     organization_user, api_key_rate_limit, product_tracker, attribution,
--     contractor; data.model_risk_static, model_version, refresh_log and the
--     nine statistics_product_* matviews; geocoder.address, building,
--     neighborhood, district; report.inquiry, inquiry_sample. ~19 h of
--     pg_stat_statements (~24k billable calls) touch exactly those. The
--     grants below are C#-Webservice leftovers, incl. SELECT/UPDATE on
--     sequences a read-only service never needs.
--   * Grafana: the SQL of every panel and variable on the 6 dashboards (no
--     alert rules) reads none of the objects below; the API-key board needs
--     only the apikey/auth_key/session columns that stay.
--   * Martin: the maplayer tile functions read the 7 *_tiles tables,
--     geocoder municipality/district/neighborhood and
--     data.model_foundation_2026_2; nothing reads the two objects below.
--   * Views run with their owner's rights, so dropping a role's SELECT on an
--     underlying table does not affect views it still reads.
--
-- sql/init/grants.sql gets the same change for a fresh database. Each role is
-- skipped with a NOTICE where it does not exist; the file fails if any
-- revoked privilege survives (e.g. granted by another role).

DO $$
DECLARE
    ws_tables text[] := ARRAY[
        'application.application_user', 'application.invitation',
        'application.organization', 'application.organization_custom_role',
        'application.organization_geolock_district',
        'application.organization_geolock_municipality',
        'application.organization_geolock_neighborhood', 'application.passkey',
        'application."user"',
        'data.building_elevation', 'data.building_geographic_region',
        'data.building_groundwater_level', 'data.building_height',
        'data.building_ownership', 'data.building_sample', 'data.building_subsidence',
        'data.building_subsidence_history', 'data.model_risk_static_2024_1',
        'data.product_tracker_daily',
        'geocoder.building_active', 'geocoder.municipality', 'geocoder.residence',
        'geocoder.state',
        'report.incident'];
    ws_sequences text[] := ARRAY[
        'report.inquiry_id_seq', 'report.inquiry_sample_id_seq',
        'report.recovery_id_seq', 'report.recovery_sample_id_seq',
        'application.attribution_id_seq'];
    grafana_tables text[] := ARRAY[
        'application.application_user', 'application.api_key_rate_limit',
        'application.invitation', 'application.organization_custom_role',
        'application.organization_user', 'application.passkey',
        'data.model_version', 'geocoder.address', 'maplayer.bundle',
        'report.dossier_event'];
    tileserver_tables text[] := ARRAY['data.building_geo_hierarchy', 'geocoder.building_active'];
    o text;
    leftover text;
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webservice') THEN
        FOREACH o IN ARRAY ws_tables LOOP
            EXECUTE format('REVOKE SELECT ON %s FROM fundermaps_webservice', o);
        END LOOP;
        FOREACH o IN ARRAY ws_sequences LOOP
            EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM fundermaps_webservice', o);
        END LOOP;
        SELECT string_agg(t, ', ') INTO leftover FROM unnest(ws_tables) t
        WHERE has_table_privilege('fundermaps_webservice', t, 'SELECT');
        IF leftover IS NOT NULL THEN
            RAISE EXCEPTION 'fundermaps_webservice can still read: %', leftover;
        END IF;
        SELECT string_agg(s, ', ') INTO leftover FROM unnest(ws_sequences) s
        WHERE has_sequence_privilege('fundermaps_webservice', s, 'SELECT, UPDATE, USAGE');
        IF leftover IS NOT NULL THEN
            RAISE EXCEPTION 'fundermaps_webservice still has sequence privileges on: %', leftover;
        END IF;
    ELSE
        RAISE NOTICE 'role fundermaps_webservice does not exist; skipped';
    END IF;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafana') THEN
        -- Table-level REVOKE also removes the role's column privileges
        -- (application.passkey had column grants only).
        FOREACH o IN ARRAY grafana_tables LOOP
            EXECUTE format('REVOKE SELECT ON %s FROM grafana', o);
        END LOOP;
        -- Keep only the columns the dashboards read.
        REVOKE SELECT (active_organization_id, expires_at, impersonated_by, ip_address,
                       updated_at, user_agent)
            ON application.session FROM grafana;          -- keeps id, user_id, created_at
        REVOKE SELECT (id, created_at, expires_at, updated_at)
            ON application.auth_key FROM grafana;         -- keeps name, user_id, last_used
        SELECT string_agg(t, ', ') INTO leftover FROM unnest(grafana_tables) t
        WHERE has_any_column_privilege('grafana', t, 'SELECT');
        IF leftover IS NOT NULL THEN
            RAISE EXCEPTION 'grafana can still read: %', leftover;
        END IF;
        IF has_column_privilege('grafana', 'application.session', 'ip_address', 'SELECT')
           OR has_column_privilege('grafana', 'application.session', 'user_agent', 'SELECT')
           OR has_column_privilege('grafana', 'application.auth_key', 'expires_at', 'SELECT') THEN
            RAISE EXCEPTION 'grafana can still read trimmed session/auth_key columns';
        END IF;
    ELSE
        RAISE NOTICE 'role grafana does not exist; skipped';
    END IF;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        FOREACH o IN ARRAY tileserver_tables LOOP
            EXECUTE format('REVOKE SELECT ON %s FROM fundermaps_tileserver', o);
        END LOOP;
        SELECT string_agg(t, ', ') INTO leftover FROM unnest(tileserver_tables) t
        WHERE has_table_privilege('fundermaps_tileserver', t, 'SELECT');
        IF leftover IS NOT NULL THEN
            RAISE EXCEPTION 'fundermaps_tileserver can still read: %', leftover;
        END IF;
    ELSE
        RAISE NOTICE 'role fundermaps_tileserver does not exist; skipped';
    END IF;
END
$$;
