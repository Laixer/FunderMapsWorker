-- Monitoring layer regression (WebFront #268 / Martin cutover): the
-- tippecanoe-era analysis_monitoring tileset was server-side filtered to
-- buildings with a monitoring-type inquiry; the dynamic buildings source is
-- not, so WebFront's monitoring layer painted every building (reported by
-- gemeente Schiedam 2026-09-10).
--
-- Fix: a boolean `monitoring` attribute on maplayer.building_tiles, exposed
-- at every zoom by maplayer.buildings(); WebFront filters on it.
-- Membership = ANY monitoring inquiry with a sample on the building (the
-- old view's definition). inquiry_type='monitoring' is NOT equivalent: it is
-- the single inquiry the model picked, and ~1,400 monitored buildings have a
-- higher-priority research that wins.
--
-- Canonical definitions updated alongside in sql/model/create_building_tiles.sql.
-- Run as a role that owns maplayer.building_tiles (fundermaps).

\set ON_ERROR_STOP on

--------------------------------------------------------------------------------
-- 1. Tile table + refresh + function source
--------------------------------------------------------------------------------

ALTER TABLE maplayer.building_tiles
    ADD COLUMN IF NOT EXISTS monitoring boolean NOT NULL DEFAULT false;

-- Population procedure: build a shadow table, swap it in (lock-free for
-- readers; see the body). ~6.4M rows, ~8 min.
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

-- Martin function source: one URL, zoom decides which geometry variant.
CREATE OR REPLACE FUNCTION maplayer.buildings(z integer, x integer, y integer)
RETURNS bytea
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    -- Below the building tilesets' minzoom, or nonsense coordinates
    -- (ST_TileEnvelope would error → 500): empty tile, no table hit.
    IF z < 12 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    IF z >= 14 THEN
        SELECT ST_AsMVT(tile, 'buildings', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                building_id, neighborhood_id, district_id, municipality_id,
                address_count, construction_year, construction_year_reliability,
                foundation_type, foundation_type_reliability, restoration_costs,
                drystand, drystand_risk, drystand_risk_reliability,
                bio_infection_risk, bio_infection_risk_reliability,
                dewatering_depth, dewatering_depth_risk,
                dewatering_depth_risk_reliability, unclassified_risk,
                height, velocity, owner, inquiry_type, damage_cause,
                enforcement_term, overall_quality, recovery_type, contractor,
                monitoring,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.building_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        -- z12–13: overview zooms. Slim tiles three ways (measured on the
        -- densest tile in the country, Amsterdam z12/2103/1346):
        --   * simplified geometry            (7.4 MB → 4.6 MB)
        --   * style attributes only, no ids  (unique building_id strings
        --     alone double a tile)           (4.6 MB → ~1.3 MB)
        --   * sub-pixel buildings dropped    (~1.3 MB → ~0.3 MB,
        --     ≈ today's static tippecanoe tile which drop-densest'd
        --     to ~0.15 MB)
        -- Click-to-select needs building_id → works from z14 up.
        SELECT ST_AsMVT(tile, 'buildings', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                -- Geofence ids are load-bearing at EVERY zoom: WebFront's
                -- geography filter shows any feature missing them (the
                -- '!has' fallback), so dropping them here exposed the whole
                -- country to fenced orgs at z12–13. They dictionary-encode
                -- well; building_id stays z14+ (near-unique = the size cost).
                neighborhood_id, district_id, municipality_id,
                construction_year, foundation_type, foundation_type_reliability,
                drystand_risk, bio_infection_risk, dewatering_depth_risk,
                unclassified_risk, recovery_type, velocity, damage_cause,
                -- contractor is set on ~5% of buildings and has ~55
                -- distinct values → dictionary-encodes to near-nothing
                inquiry_type, contractor,
                -- monitoring is a boolean on ~3.8k buildings: free
                monitoring,
                -- WebFront paints with these even at z12–13: every layer
                -- extrudes on height; owner/restoration-cost/enforcement-term/
                -- overall-quality layers and address_count filters break
                -- without them. All low-cardinality → MVT dictionary-encodes
                -- them cheaply (building_id stays z14+, it's the size killer).
                address_count, height, owner, restoration_costs,
                enforcement_term, overall_quality,
                ST_AsMVTGeom(geom_simple, env, 4096, 8, true) AS geom
            FROM maplayer.building_tiles
            WHERE geom_simple && env
              AND surface_area >= CASE WHEN z = 12 THEN 150 ELSE 60 END
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;

-- TileJSON metadata Martin merges into the source's TileJSON (auto-published
-- sources only). "fields" is MANDATORY per TileJSON 3.0 — without it Martin's
-- strict re-deserialization fails and the whole comment is silently dropped
-- ("Failed to deserialize merged function comment tilejson: missing field
-- `fields`"), which leaves clients without vector_layers and breaks e.g. the
-- Martin web UI. Fields list = the z14+ attribute set; z12–13 tiles carry the
-- style-attribute subset (ids are z14+ only).
COMMENT ON FUNCTION maplayer.buildings(integer, integer, integer) IS
'{"description": "FunderMaps building foundation tiles (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "buildings", "minzoom": 12, "maxzoom": 16, "fields": {"building_id": "String", "neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "address_count": "Number", "construction_year": "Number", "construction_year_reliability": "String", "foundation_type": "String", "foundation_type_reliability": "String", "restoration_costs": "Number", "drystand": "Number", "drystand_risk": "String", "drystand_risk_reliability": "String", "bio_infection_risk": "String", "bio_infection_risk_reliability": "String", "dewatering_depth": "Number", "dewatering_depth_risk": "String", "dewatering_depth_risk_reliability": "String", "unclassified_risk": "String", "height": "Number", "velocity": "Number", "owner": "String", "inquiry_type": "String", "damage_cause": "String", "enforcement_term": "Number", "overall_quality": "String", "recovery_type": "String", "contractor": "String", "monitoring": "Boolean"}}]}';

--------------------------------------------------------------------------------
-- 2. One-off backfill so the layer works before the next nightly rebuild
--    (~3.8k of 6.45M rows; the refresh procedure computes it from then on).
--------------------------------------------------------------------------------

UPDATE maplayer.building_tiles bt
SET monitoring = true
WHERE EXISTS (
    SELECT FROM report.inquiry_sample s
    JOIN report.inquiry mi ON mi.id = s.inquiry_id
    WHERE s.building_id = bt.building_id
      AND mi.type = 'monitoring'
);
