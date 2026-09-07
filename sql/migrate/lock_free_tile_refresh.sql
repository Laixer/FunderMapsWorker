-- Lock-free rebuild of the Martin tile tables.
--
-- maplayer.refresh_building_tiles() and refresh_building_cluster_tiles()
-- were TRUNCATE + INSERT inside one transaction. TRUNCATE takes an ACCESS
-- EXCLUSIVE lock that is held until COMMIT, i.e. for the whole rebuild
-- (~8 min + ~6.5 min, twice a day from f/fundermaps/data/refresh_data_model
-- at 12:30 and 21:00 CEST). Every maplayer.buildings()/building_cluster()
-- call queued behind it and died on fundermaps_tileserver's 15 s
-- statement_timeout: "Unable to get tile … from buildings: db error".
-- That is also the unexplained 2026-08-07 tile outage.
--
-- New shape: build <table>_next beside the live table, index + ANALYZE it,
-- then DROP old / RENAME new. The exclusive lock lasts milliseconds.
-- SECURITY DEFINER so the new table is owned by the procedure owner
-- (fundermaps) regardless of the caller. Apply as `fundermaps`.
--
-- Applied to prod 2026-09-07. Canonical copies: sql/model/create_building_tiles.sql
-- and sql/model/create_building_cluster_tiles.sql.

CREATE OR REPLACE PROCEDURE maplayer.refresh_building_tiles()
LANGUAGE plpgsql
-- Runs as the table owner so the new generation is owned by the same role
-- as the one it replaces, whoever calls it (Windmill calls as
-- fundermaps_windmill).
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
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
        surface_area, geom, geom_simple
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
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_windmill') THEN
        GRANT SELECT, INSERT, TRUNCATE, MAINTAIN ON maplayer.building_tiles_next TO fundermaps_windmill;
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
$$;

CREATE OR REPLACE PROCEDURE maplayer.refresh_building_cluster_tiles()
LANGUAGE plpgsql
-- Runs as the table owner so the new generation is owned by the same role
-- as the one it replaces, whoever calls it (Windmill calls as
-- fundermaps_windmill).
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
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
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_windmill') THEN
        GRANT SELECT, INSERT, TRUNCATE, MAINTAIN ON maplayer.building_cluster_tiles_next TO fundermaps_windmill;
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
$$;
