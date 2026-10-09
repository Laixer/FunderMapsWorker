-- Exact-type calls in the SECURITY DEFINER tile procedures (hardening,
-- infra review 2026-10-09).
--
-- maplayer.refresh_building_tiles() and refresh_building_cluster_tiles() run
-- as their owner with search_path pg_catalog, public. A call inside such a
-- routine that only resolves through an implicit cast can, in principle, be
-- resolved to a different overload with the exact argument types (the
-- search-path class of CVE-2018-1058). Make every such call exact:
--   * ST_SimplifyPreserveTopology(geom, 5.0): 5.0 is numeric, PostGIS takes
--     double precision            -> cast the literal (both procedures);
--   * mi.type = 'monitoring': report.inquiry_type is an enum, '=' resolves to
--     the polymorphic anyenum operator -> OPERATOR(pg_catalog.=);
--   * s.building_id = bgh.building_id: geocoder.geocoder_id (domain) vs text
--                                    -> OPERATOR(pg_catalog.=).
-- Every other call in both bodies already matches a pg_catalog/PostGIS
-- signature exactly (int = int, text = text, ST_Transform(geometry, int),
-- set_config with unknown literals -> text). Semantics and plans are
-- unchanged: the same operators and functions are chosen, now explicitly.
-- refresh_incident_tiles() (caller's rights) gets the same cast on its three
-- 20.0 literals for consistency.
--
-- True on prod 2026-10-09 (read-only checks): these are the only two SECURITY
-- DEFINER routines outside extensions; the bodies below are the live
-- pg_get_functiondef output with only the changes above (and a comment in the
-- two definer bodies). CREATE OR REPLACE keeps owner, grants and the
-- SECURITY DEFINER / search_path settings. sql/model/create_building*_tiles.sql
-- get the same change.
--
-- The file fails if an untyped decimal argument or the enum/domain '=' is
-- left in any of the three bodies, or if either definer lost SECURITY DEFINER.

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

CREATE OR REPLACE PROCEDURE maplayer.refresh_incident_tiles()
 LANGUAGE sql
AS $procedure$
    TRUNCATE maplayer.incident_tiles;

    INSERT INTO maplayer.incident_tiles (
        id, neighborhood_id, district_id, municipality_id,
        foundation_damage_cause, topic, height, geom
    )
    SELECT
        m.dossier_id::text,
        n.external_id,
        d2.external_id,
        mu.external_id,
        NULL::text,
        m.topic,
        round(GREATEST(bh.height, 0::real)::numeric, 2)::double precision,
        ST_Multi(ST_Transform(ba.geom, 3857))
    FROM ( SELECT DISTINCT ON (d.building_id) d.building_id,
                  d.id AS dossier_id,
                  d.payload ->> 'topic' AS topic
             FROM dataops.dossier d
            WHERE d.payload ->> 'topic' IS NOT NULL
              AND d.building_id IS NOT NULL
            ORDER BY d.building_id, d.created_at DESC) m
    JOIN geocoder.building_active ba ON ba.external_id = m.building_id
    JOIN data.building_height bh ON bh.building_id = ba.external_id
    LEFT JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    LEFT JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text;

    TRUNCATE maplayer.incident_neighborhood_tiles;

    INSERT INTO maplayer.incident_neighborhood_tiles (
        neighborhood_id, district_id, municipality_id, incident_count,
        geom, geom_simple
    )
    SELECT
        n.external_id,
        d2.external_id,
        mu.external_id,
        count(*),
        ST_Multi(ST_Transform(n.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(n.geom, 3857), 20.0::double precision))
    FROM ( SELECT DISTINCT d.building_id
             FROM dataops.dossier d
            WHERE d.payload ->> 'topic' IS NOT NULL
              AND d.building_id IS NOT NULL) m
    JOIN geocoder.building_active ba ON ba.external_id = m.building_id
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    LEFT JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text
    GROUP BY n.external_id, d2.external_id, mu.external_id, n.geom;

    TRUNCATE maplayer.incident_district_tiles;

    INSERT INTO maplayer.incident_district_tiles (
        district_id, municipality_id, incident_count, geom, geom_simple
    )
    SELECT
        d2.external_id,
        mu.external_id,
        count(*),
        ST_Multi(ST_Transform(d2.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(d2.geom, 3857), 20.0::double precision))
    FROM ( SELECT DISTINCT d.building_id
             FROM dataops.dossier d
            WHERE d.payload ->> 'topic' IS NOT NULL
              AND d.building_id IS NOT NULL) m
    JOIN geocoder.building_active ba ON ba.external_id = m.building_id
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text
    GROUP BY d2.external_id, mu.external_id, d2.geom;

    TRUNCATE maplayer.incident_municipality_tiles;

    INSERT INTO maplayer.incident_municipality_tiles (
        municipality_id, incident_count, geom, geom_simple
    )
    SELECT
        mu.external_id,
        count(*),
        ST_Multi(ST_Transform(mu.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(mu.geom, 3857), 20.0::double precision))
    FROM ( SELECT DISTINCT d.building_id
             FROM dataops.dossier d
            WHERE d.payload ->> 'topic' IS NOT NULL
              AND d.building_id IS NOT NULL) m
    JOIN geocoder.building_active ba ON ba.external_id = m.building_id
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
    JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text
    GROUP BY mu.external_id, mu.geom;

    ANALYZE maplayer.incident_tiles;
    ANALYZE maplayer.incident_neighborhood_tiles;
    ANALYZE maplayer.incident_district_tiles;
    ANALYZE maplayer.incident_municipality_tiles;
$procedure$;

DO $$
DECLARE
    bad text;
BEGIN
    SELECT string_agg(p.oid::regprocedure::text, ', ') INTO bad
    FROM pg_proc p
    WHERE p.oid IN ('maplayer.refresh_building_tiles()'::regprocedure,
                    'maplayer.refresh_building_cluster_tiles()'::regprocedure,
                    'maplayer.refresh_incident_tiles()'::regprocedure)
      AND (p.prosrc ~ ',\s*[0-9]+\.[0-9]+\s*\)'
           OR p.prosrc ~ 'mi\.type\s*=\s*'''
           OR p.prosrc ~ 's\.building_id\s*=\s*bgh\.');
    IF bad IS NOT NULL THEN
        RAISE EXCEPTION 'implicit-cast call left in: %', bad;
    END IF;

    IF NOT (SELECT bool_and(prosecdef) FROM pg_proc
            WHERE oid IN ('maplayer.refresh_building_tiles()'::regprocedure,
                          'maplayer.refresh_building_cluster_tiles()'::regprocedure)) THEN
        RAISE EXCEPTION 'a tile refresh procedure lost SECURITY DEFINER';
    END IF;
END
$$;
