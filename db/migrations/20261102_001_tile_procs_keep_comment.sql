-- The two big tile tables keep their comment through the nightly rebuild (Yorick 2026-11-02: "fix the comments in
-- the two refresh procedures").
--
-- maplayer.refresh_building_tiles() and refresh_building_cluster_tiles() build a new table (<name>_next), then drop
-- the old one and rename: a new table on every run, so the comment 20261030_004 set was gone after that night's
-- refresh. The other tile tables are truncated and keep theirs. The comment now goes on <name>_next, just before the
-- swap: the rename carries it along, and it adds no lock on the live table.
--
-- Both procedures are recreated from their live definitions (prod, 2026-11-02; identical to sql/model/*, checked);
-- the comment lines are the only change, so SECURITY DEFINER, the search_path and the swap's lock_timeout stay.
-- The tables get their comment back now as well, so they do not have to wait for the next refresh.

SET LOCAL lock_timeout = '2s';

CREATE OR REPLACE PROCEDURE maplayer.refresh_building_tiles()
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $procedure$
BEGIN
    -- Exact argument types and pg_catalog operators on purpose: this runs as
    -- its owner (SECURITY DEFINER) while PUBLIC may CREATE in schema public,
    -- so any call that needs an implicit cast (numeric 5.0 -> float8, enum or
    -- domain '=') could be won by an exact-type overload planted there.
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
            WHERE s.building_id OPERATOR(pg_catalog.=) bgh.building_id
              AND mi.type OPERATOR(pg_catalog.=) 'monitoring'
        ),
        bgh.surface_area::double precision,
        ST_Transform(bgh.geom, 3857),
        -- 5.0 Mercator units ≈ 3 m at NL latitude: invisible at z12–13,
        -- collapses a 40-vertex floor plan to a handful of points.
        ST_SimplifyPreserveTopology(ST_Transform(bgh.geom, 3857), 5.0::double precision)
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

    -- This table is new on every run, so it has to get its comment here; the rename below keeps it.
    COMMENT ON TABLE maplayer.building_tiles_next IS
        '[tiles · cache] Rows behind the public tile function maplayer.buildings(z,x,y): the default model per building with geometry. Rebuilt nightly by maplayer.refresh_building_tiles().';

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
    -- Exact argument types and pg_catalog operators on purpose: this runs as
    -- its owner (SECURITY DEFINER) while PUBLIC may CREATE in schema public,
    -- so any call that needs an implicit cast (numeric 5.0 -> float8, enum or
    -- domain '=') could be won by an exact-type overload planted there.
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
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(u.geom, 3857), 5.0::double precision))
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

    -- This table is new on every run, so it has to get its comment here; the rename below keeps it.
    COMMENT ON TABLE maplayer.building_cluster_tiles_next IS
        '[tiles · cache] Rows behind the tile function maplayer.building_cluster(z,x,y): one union geometry per cluster. Rebuilt nightly by maplayer.refresh_building_cluster_tiles().';

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

COMMENT ON TABLE maplayer.building_tiles IS $c$[tiles · cache] Rows behind the public tile function maplayer.buildings(z,x,y): the default model per building with geometry. Rebuilt nightly by maplayer.refresh_building_tiles().$c$;
COMMENT ON TABLE maplayer.building_cluster_tiles IS $c$[tiles · cache] Rows behind the tile function maplayer.building_cluster(z,x,y): one union geometry per cluster. Rebuilt nightly by maplayer.refresh_building_cluster_tiles().$c$;
