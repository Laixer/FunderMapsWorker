-- Dynamic tile source for the Martin tileserver (hybrid tile pipeline).
--
-- One flat physical table replaces the per-request join through
-- data.building_geo_hierarchy (model_risk_static ⋈ building_active): all
-- attributes the five tile-generating analysis_* views expose today, plus
-- the geometry pre-transformed to Web Mercator in two variants — full
-- detail for z14+ and a simplified copy for z12–13 (a building is only a
-- few pixels there; without simplification a dense-city z12 tile is ~7 MB).
--
-- Rebuilt nightly right after model_risk_static
-- refreshes (attributes change nightly; geometry only on BAG reload —
-- a future optimization is trigger-based partial refresh, see the
-- tileserver plan).
--
-- maplayer.buildings(z,x,y) is a Martin "function source": Martin serves
-- GET /buildings/{z}/{x}/{y} by calling it. The attribute set is exactly
-- the union of what analysis_{building,foundation,monitoring,report,risk}
-- put into the public tippecanoe tiles today — tiles are public, so this
-- function must not expose more than that union.

CREATE TABLE IF NOT EXISTS maplayer.building_tiles (
    building_id text PRIMARY KEY,
    -- CBS codes, exposed under the same names the analysis views use
    neighborhood_id text,
    district_id text,
    municipality_id text,
    address_count integer,
    construction_year integer,
    construction_year_reliability text,
    foundation_type text,
    foundation_type_reliability text,
    restoration_costs integer,
    drystand double precision,
    drystand_risk text,
    drystand_risk_reliability text,
    bio_infection_risk text,
    bio_infection_risk_reliability text,
    dewatering_depth double precision,
    dewatering_depth_risk text,
    dewatering_depth_risk_reliability text,
    unclassified_risk text,
    height double precision,
    velocity double precision,
    owner text,
    inquiry_type text,
    damage_cause text,
    enforcement_term double precision,
    overall_quality text,
    recovery_type text,
    -- drop-filter only, never exposed in tiles: at z12 a pixel is ~38 m,
    -- so small buildings are sub-pixel and tippecanoe used to drop them too
    surface_area double precision,
    geom geometry(MultiPolygon, 3857),
    geom_simple geometry(MultiPolygon, 3857)
);

CREATE INDEX IF NOT EXISTS building_tiles_geom_idx
    ON maplayer.building_tiles USING gist (geom);
CREATE INDEX IF NOT EXISTS building_tiles_geom_simple_idx
    ON maplayer.building_tiles USING gist (geom_simple);

-- Population procedure. TRUNCATE + INSERT, same pattern as
-- data.refresh_building_precomputed(). ~12.6M rows.
CREATE OR REPLACE PROCEDURE maplayer.refresh_building_tiles()
LANGUAGE sql
AS $$
    TRUNCATE maplayer.building_tiles;

    INSERT INTO maplayer.building_tiles (
        building_id, neighborhood_id, district_id, municipality_id,
        address_count, construction_year, construction_year_reliability,
        foundation_type, foundation_type_reliability, restoration_costs,
        drystand, drystand_risk, drystand_risk_reliability,
        bio_infection_risk, bio_infection_risk_reliability,
        dewatering_depth, dewatering_depth_risk,
        dewatering_depth_risk_reliability, unclassified_risk,
        height, velocity, owner, inquiry_type, damage_cause,
        enforcement_term, overall_quality, recovery_type,
        surface_area, geom, geom_simple
    )
    SELECT
        building_id,
        ext_neighborhood_id,
        ext_district_id,
        ext_municipality_id,
        address_count,
        construction_year,
        construction_year_reliability::text,
        foundation_type::text,
        foundation_type_reliability::text,
        restoration_costs,
        drystand,
        drystand_risk::text,
        drystand_risk_reliability::text,
        bio_infection_risk::text,
        bio_infection_risk_reliability::text,
        dewatering_depth,
        dewatering_depth_risk::text,
        dewatering_depth_risk_reliability::text,
        unclassified_risk::text,
        height::double precision,
        velocity::double precision,
        owner,
        inquiry_type::text,
        damage_cause::text,
        enforcement_term,
        overall_quality::text,
        recovery_type::text,
        surface_area::double precision,
        ST_Transform(geom, 3857),
        -- 5.0 Mercator units ≈ 3 m at NL latitude: invisible at z12–13,
        -- collapses a 40-vertex floor plan to a handful of points.
        ST_SimplifyPreserveTopology(ST_Transform(geom, 3857), 5.0)
    FROM data.building_geo_hierarchy
    WHERE geom IS NOT NULL;

    ANALYZE maplayer.building_tiles;
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
                enforcement_term, overall_quality, recovery_type,
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
                inquiry_type,
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
'{"description": "FunderMaps building foundation tiles (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "buildings", "minzoom": 12, "maxzoom": 16, "fields": {"building_id": "String", "neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "address_count": "Number", "construction_year": "Number", "construction_year_reliability": "String", "foundation_type": "String", "foundation_type_reliability": "String", "restoration_costs": "Number", "drystand": "Number", "drystand_risk": "String", "drystand_risk_reliability": "String", "bio_infection_risk": "String", "bio_infection_risk_reliability": "String", "dewatering_depth": "Number", "dewatering_depth_risk": "String", "dewatering_depth_risk_reliability": "String", "unclassified_risk": "String", "height": "Number", "velocity": "Number", "owner": "String", "inquiry_type": "String", "damage_cause": "String", "enforcement_term": "Number", "overall_quality": "String", "recovery_type": "String"}}]}';

-- Serving role (created on prod with LOGIN, CONNECTION LIMIT 5 and
-- statement_timeout=15s; password lives outside the repo).
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        GRANT USAGE ON SCHEMA maplayer TO fundermaps_tileserver;
        GRANT SELECT ON maplayer.building_tiles TO fundermaps_tileserver;
        GRANT EXECUTE ON FUNCTION maplayer.buildings(integer, integer, integer)
            TO fundermaps_tileserver;
    END IF;
END $$;

-- The nightly rebuild runs from the Windmill flow
-- f/fundermaps/data/refresh_data_model as fundermaps_windmill.
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_windmill') THEN
        GRANT USAGE ON SCHEMA maplayer TO fundermaps_windmill;
        GRANT SELECT, INSERT, TRUNCATE, MAINTAIN
            ON maplayer.building_tiles TO fundermaps_windmill;
        GRANT SELECT ON data.building_geo_hierarchy TO fundermaps_windmill;
    END IF;
END $$;
