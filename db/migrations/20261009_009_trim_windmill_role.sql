-- Least privilege for fundermaps_windmill (Windmill's managed_pg login): drop
-- what no Windmill script or flow uses (DB grant audit, 2026-10-09).
--
-- First, maplayer.refresh_building_tiles() and refresh_building_cluster_tiles()
-- stop re-granting SELECT/INSERT/TRUNCATE/MAINTAIN on the freshly built table
-- to fundermaps_windmill on every run. Both are SECURITY DEFINER (they build
-- and swap the table as its owner), so the caller needs only EXECUTE
-- (20261009_005). The bodies below are the live prod definitions
-- (pg_get_functiondef, identical to schema.sql at 20261009_006) minus that one
-- IF block; sql/model/create_building*_tiles.sql get the same change.
--
-- True on prod 2026-10-09 (Windmill scripts/flows + Worker code it runs +
-- ~19 h of pg_stat_statements; read-only checks). Windmill uses: worker_jobs
-- INSERT/SELECT (process_tileset), product_tracker SELECT (export_product),
-- REFRESH of 14 matviews (MAINTAIN), the facade/incident tile procedures that
-- run with the caller's rights (TRUNCATE/INSERT/MAINTAIN on those 5 tile
-- tables, SELECT on what they read), dataops ingest (ingest_pending),
-- data.refresh_log INSERT, maplayer.bundle SELECT, and the manual
-- load_ownership / load_inquiry_sample / export_samples scripts. All of that
-- stays. Revoked here:
--   * every privilege on 15 application tables/views no script touches;
--   * UPDATE/DELETE on worker_jobs (it only inserts and polls);
--   * INSERT/UPDATE/DELETE on 13 matviews (meaningless on a matview);
--   * writes to 15 data tables/views nothing writes (building_ownership stays
--     for load_ownership);
--   * SELECT on data.building_cluster and data.building_geo_hierarchy (read
--     only by the two SECURITY DEFINER procedures);
--   * USAGE on 3 dataops sequences: the ids are identity columns, which need
--     no sequence privilege (20260920_004 already called these leftovers);
--   * every privilege on maplayer.building_tiles and building_cluster_tiles.
-- Deliberately kept: report.* (decision 2026-07-19), geocoder writes (parked
-- BAG-in-Windmill plan), SELECT on model/candidate tables and maplayer views.
-- Note: ad-hoc scripts that borrow this login for reads lose application.*.
--
-- The role part is skipped with a NOTICE where fundermaps_windmill does not
-- exist; the file fails if any revoked privilege survives.

CREATE OR REPLACE PROCEDURE maplayer.refresh_building_tiles()
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $procedure$
BEGIN
    -- Build the next generation NEXT TO the live table. Martin keeps serving
    -- maplayer.building_tiles untouched while this runs (~8 min for
    -- building_tiles); the old TRUNCATE + INSERT held an ACCESS EXCLUSIVE
    -- lock for the whole rebuild and every tile request timed out (15 s)
    -- twice a day.
    DROP TABLE IF EXISTS maplayer.building_tiles_next;
    CREATE TABLE maplayer.building_tiles_next
        (LIKE maplayer.building_tiles INCLUDING DEFAULTS INCLUDING CONSTRAINTS);

    INSERT INTO maplayer.building_tiles_next (
        building_id, neighborhood_id, district_id, municipality_id,
        address_count, construction_year, construction_year_reliability,
        foundation_type, foundation_type_reliability, restoration_costs,
        drystand, drystand_risk, drystand_risk_reliability,
        bio_infection_risk, bio_infection_risk_reliability,
        dewatering_depth, dewatering_depth_risk,
        dewatering_depth_risk_reliability, unclassified_risk,
        height, velocity, owner, inquiry_type, damage_cause,
        enforcement_term, overall_quality, recovery_type, contractor,
        monitoring, surface_area, geom, geom_simple
    )
    SELECT
        bgh.building_id,
        bgh.ext_neighborhood_id,
        bgh.ext_district_id,
        bgh.ext_municipality_id,
        bgh.address_count,
        bgh.construction_year,
        bgh.construction_year_reliability::text,
        bgh.foundation_type::text,
        bgh.foundation_type_reliability::text,
        bgh.restoration_costs,
        bgh.drystand,
        bgh.drystand_risk::text,
        bgh.drystand_risk_reliability::text,
        bgh.bio_infection_risk::text,
        bgh.bio_infection_risk_reliability::text,
        bgh.dewatering_depth,
        bgh.dewatering_depth_risk::text,
        bgh.dewatering_depth_risk_reliability::text,
        bgh.unclassified_risk::text,
        bgh.height::double precision,
        bgh.velocity::double precision,
        bgh.owner,
        bgh.inquiry_type::text,
        bgh.damage_cause::text,
        bgh.enforcement_term,
        bgh.overall_quality::text,
        bgh.recovery_type::text,
        con.name,
        EXISTS (
            SELECT FROM report.inquiry_sample s
            JOIN report.inquiry mi ON mi.id = s.inquiry_id
            WHERE s.building_id = bgh.building_id
              AND mi.type = 'monitoring'
        ),
        bgh.surface_area::double precision,
        ST_Transform(bgh.geom, 3857),
        -- 5.0 Mercator units ≈ 3 m at NL latitude: invisible at z12–13,
        -- collapses a 40-vertex floor plan to a handful of points.
        ST_SimplifyPreserveTopology(ST_Transform(bgh.geom, 3857), 5.0)
    FROM data.building_geo_hierarchy bgh
    -- bgh.inquiry_id is the inquiry the model picked; its attribution
    -- names the contractor that performed the research.
    LEFT JOIN report.inquiry i ON i.id = bgh.inquiry_id
    LEFT JOIN application.attribution attr ON attr.id = i.attribution_id
    LEFT JOIN application.contractor con ON con.id = attr.contractor_id
    WHERE bgh.geom IS NOT NULL;

    -- Indexes after the load (cheaper than maintaining them row by row).
    ALTER TABLE maplayer.building_tiles_next ADD PRIMARY KEY (building_id);
    CREATE INDEX building_tiles_next_geom_idx
        ON maplayer.building_tiles_next USING gist (geom);
    CREATE INDEX building_tiles_next_geom_simple_idx
        ON maplayer.building_tiles_next USING gist (geom_simple);
    ANALYZE maplayer.building_tiles_next;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        GRANT SELECT ON maplayer.building_tiles_next TO fundermaps_tileserver;
    END IF;

    -- Swap. The only exclusive lock on the live table is taken here and
    -- released at COMMIT a few milliseconds later. Rather than queue behind
    -- a slow tile query (and make every request after it queue too), give
    -- up: the old generation keeps serving and the next run rebuilds.
    PERFORM set_config('lock_timeout', '20s', true);
    DROP TABLE maplayer.building_tiles;
    ALTER TABLE maplayer.building_tiles_next RENAME TO building_tiles;
    ALTER INDEX maplayer.building_tiles_next_pkey RENAME TO building_tiles_pkey;
    ALTER INDEX maplayer.building_tiles_next_geom_idx RENAME TO building_tiles_geom_idx;
    ALTER INDEX maplayer.building_tiles_next_geom_simple_idx
        RENAME TO building_tiles_geom_simple_idx;
END;
$procedure$;

CREATE OR REPLACE PROCEDURE maplayer.refresh_building_cluster_tiles()
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $procedure$
BEGIN
    -- Build the next generation NEXT TO the live table. Martin keeps serving
    -- maplayer.building_cluster_tiles untouched while this runs (~6.5 min);
    -- the old TRUNCATE + INSERT held an ACCESS EXCLUSIVE
    -- lock for the whole rebuild and every tile request timed out (15 s)
    -- twice a day.
    DROP TABLE IF EXISTS maplayer.building_cluster_tiles_next;
    CREATE TABLE maplayer.building_cluster_tiles_next
        (LIKE maplayer.building_cluster_tiles INCLUDING DEFAULTS INCLUDING CONSTRAINTS);

    INSERT INTO maplayer.building_cluster_tiles_next (
        cluster_id, building_count, surface_area, geom, geom_simple
    )
    SELECT
        u.cluster_id,
        u.building_count,
        ST_Area(u.geom::geography, true),
        ST_Multi(ST_Transform(u.geom, 3857)),
        -- 5.0 Mercator units ≈ 3 m at NL latitude, matching building_tiles:
        -- invisible at z12–13, collapses dense outlines to a few points.
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(u.geom, 3857), 5.0))
    FROM (
        SELECT
            bc.cluster_id,
            count(*) AS building_count,
            ST_Union(ba.geom) AS geom
        FROM data.building_cluster bc
        JOIN geocoder.building_active ba ON ba.external_id = bc.building_id
        GROUP BY bc.cluster_id
    ) u;

    -- Indexes after the load (cheaper than maintaining them row by row).
    ALTER TABLE maplayer.building_cluster_tiles_next ADD PRIMARY KEY (cluster_id);
    CREATE INDEX building_cluster_tiles_next_geom_idx
        ON maplayer.building_cluster_tiles_next USING gist (geom);
    CREATE INDEX building_cluster_tiles_next_geom_simple_idx
        ON maplayer.building_cluster_tiles_next USING gist (geom_simple);
    ANALYZE maplayer.building_cluster_tiles_next;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        GRANT SELECT ON maplayer.building_cluster_tiles_next TO fundermaps_tileserver;
    END IF;

    -- Swap. The only exclusive lock on the live table is taken here and
    -- released at COMMIT a few milliseconds later. Rather than queue behind
    -- a slow tile query (and make every request after it queue too), give
    -- up: the old generation keeps serving and the next run rebuilds.
    PERFORM set_config('lock_timeout', '20s', true);
    DROP TABLE maplayer.building_cluster_tiles;
    ALTER TABLE maplayer.building_cluster_tiles_next RENAME TO building_cluster_tiles;
    ALTER INDEX maplayer.building_cluster_tiles_next_pkey RENAME TO building_cluster_tiles_pkey;
    ALTER INDEX maplayer.building_cluster_tiles_next_geom_idx RENAME TO building_cluster_tiles_geom_idx;
    ALTER INDEX maplayer.building_cluster_tiles_next_geom_simple_idx
        RENAME TO building_cluster_tiles_geom_simple_idx;
END;
$procedure$;

DO $$
DECLARE
    app_objects text[] := ARRAY[
        'application.application', 'application.application_user',
        'application.attribution', 'application.contractor',
        'application.file_resources', 'application.file_resources_orphaned',
        'application.mapset', 'application.mapset_collection', 'application.mapset_layer',
        'application.organization', 'application.organization_geolock_district',
        'application.organization_geolock_municipality',
        'application.organization_geolock_neighborhood',
        'application.organization_mapset', 'application.organization_user'];
    matviews text[] := ARRAY[
        'data.building_sample', 'data.cluster_sample', 'data.supercluster_sample',
        'data.model_risk_static_2024_1',
        'data.statistics_product_buildings_restored',
        'data.statistics_product_construction_years',
        'data.statistics_product_data_collected',
        'data.statistics_product_foundation_risk',
        'data.statistics_product_foundation_type',
        'data.statistics_product_incident_municipality',
        'data.statistics_product_incidents', 'data.statistics_product_inquiries',
        'data.statistics_product_inquiry_municipality'];
    data_unwritten text[] := ARRAY[
        'data.building_cluster', 'data.building_elevation',
        'data.building_geographic_region', 'data.building_groundwater_level',
        'data.building_pleistocene', 'data.building_precomputed',
        'data.building_subsidence', 'data.building_subsidence_history',
        'data.cluster_recovery_sample', 'data.model_gevelscan',
        'data.risk_table_priority', 'data.supercluster',
        'data.building_geo_hierarchy', 'data.building_height',
        'data.model_risk_dynamic_all'];
    sequences text[] := ARRAY[
        'dataops.dossier_address_id_seq', 'dataops.extraction_field_id_seq',
        'dataops.extraction_id_seq'];
    o text;
    leftover text;
BEGIN
    IF EXISTS (
        SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'maplayer'
          AND p.proname IN ('refresh_building_tiles', 'refresh_building_cluster_tiles')
          AND p.prosrc LIKE '%fundermaps_windmill%'
    ) THEN
        RAISE EXCEPTION 'a building tile procedure still grants to fundermaps_windmill';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_windmill') THEN
        RAISE NOTICE 'role fundermaps_windmill does not exist; grants unchanged';
        RETURN;
    END IF;

    FOREACH o IN ARRAY app_objects LOOP
        EXECUTE format('REVOKE ALL ON %s FROM fundermaps_windmill', o);
    END LOOP;
    REVOKE UPDATE, DELETE ON application.worker_jobs FROM fundermaps_windmill;
    FOREACH o IN ARRAY matviews LOOP
        EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON %s FROM fundermaps_windmill', o);
    END LOOP;
    FOREACH o IN ARRAY data_unwritten LOOP
        EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON %s FROM fundermaps_windmill', o);
    END LOOP;
    REVOKE SELECT ON data.building_cluster, data.building_geo_hierarchy FROM fundermaps_windmill;
    FOREACH o IN ARRAY sequences LOOP
        EXECUTE format('REVOKE USAGE ON SEQUENCE %s FROM fundermaps_windmill', o);
    END LOOP;
    REVOKE ALL ON maplayer.building_tiles, maplayer.building_cluster_tiles FROM fundermaps_windmill;

    SELECT string_agg(t, ', ') INTO leftover FROM unnest(app_objects) t
    WHERE has_table_privilege('fundermaps_windmill', t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN');
    IF leftover IS NOT NULL THEN
        RAISE EXCEPTION 'fundermaps_windmill still has privileges on: %', leftover;
    END IF;

    -- Any write left on data.* other than load_ownership and the refresh log.
    SELECT string_agg(c.oid::regclass::text, ', ') INTO leftover
    FROM pg_class c
    WHERE c.relnamespace = 'data'::regnamespace AND c.relkind IN ('r', 'p', 'v', 'm')
      AND c.oid NOT IN ('data.building_ownership'::regclass, 'data.refresh_log'::regclass)
      AND has_table_privilege('fundermaps_windmill', c.oid, 'INSERT, UPDATE, DELETE');
    IF leftover IS NOT NULL THEN
        RAISE EXCEPTION 'fundermaps_windmill can still write: %', leftover;
    END IF;

    IF has_table_privilege('fundermaps_windmill', 'application.worker_jobs', 'UPDATE, DELETE')
       OR has_table_privilege('fundermaps_windmill', 'data.building_cluster', 'SELECT')
       OR has_table_privilege('fundermaps_windmill', 'data.building_geo_hierarchy', 'SELECT')
       OR has_table_privilege('fundermaps_windmill', 'maplayer.building_tiles', 'SELECT, INSERT, TRUNCATE, MAINTAIN')
       OR has_table_privilege('fundermaps_windmill', 'maplayer.building_cluster_tiles', 'SELECT, INSERT, TRUNCATE, MAINTAIN')
       OR has_sequence_privilege('fundermaps_windmill', 'dataops.dossier_address_id_seq', 'USAGE')
       OR has_sequence_privilege('fundermaps_windmill', 'dataops.extraction_field_id_seq', 'USAGE')
       OR has_sequence_privilege('fundermaps_windmill', 'dataops.extraction_id_seq', 'USAGE') THEN
        RAISE EXCEPTION 'fundermaps_windmill still holds a revoked privilege';
    END IF;
END
$$;
