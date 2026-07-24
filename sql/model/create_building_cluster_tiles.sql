-- Dynamic tile source for the building-cluster ("bouwkundige eenheid")
-- map layer, served by the Martin tileserver.
--
-- Replaces the static tippecanoe tileset (frozen in Spaces since Sep 2024;
-- bundle row disabled) that rendered the old maplayer.building_cluster view.
-- Same shape as maplayer.building_tiles (create_building_tiles.sql): one
-- flat physical table with the per-cluster ST_Union precomputed and
-- pre-transformed to Web Mercator, full + simplified geometry variants,
-- and a (z,x,y) function source Martin auto-publishes.
--
-- A cluster is a structural unit: buildings constructed as one project,
-- sharing a foundation (data.building_cluster, ~1.7M clusters over ~6.4M
-- buildings). The risk model borrows foundation attributes from cluster
-- peers, which is why this layer matters beyond decoration. Rebuilt
-- nightly from the refresh_data_model flow, right after building_tiles.

CREATE TABLE IF NOT EXISTS maplayer.building_cluster_tiles (
    cluster_id uuid PRIMARY KEY,
    building_count integer NOT NULL,
    -- true-area m² of the unioned outline; drop-filter for overview zooms
    surface_area double precision,
    geom geometry(MultiPolygon, 3857),
    geom_simple geometry(MultiPolygon, 3857)
);

CREATE INDEX IF NOT EXISTS building_cluster_tiles_geom_idx
    ON maplayer.building_cluster_tiles USING gist (geom);
CREATE INDEX IF NOT EXISTS building_cluster_tiles_geom_simple_idx
    ON maplayer.building_cluster_tiles USING gist (geom_simple);

-- Population procedure. TRUNCATE + INSERT, same pattern as
-- maplayer.refresh_building_tiles().
CREATE OR REPLACE PROCEDURE maplayer.refresh_building_cluster_tiles()
LANGUAGE sql
AS $$
    TRUNCATE maplayer.building_cluster_tiles;

    INSERT INTO maplayer.building_cluster_tiles (
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

    ANALYZE maplayer.building_cluster_tiles;
$$;

-- Martin function source: GET /building_cluster/{z}/{x}/{y}. The MVT layer
-- name matches the old static tileset ("building_cluster") so WebFront's
-- building-cluster.json source-layer keeps working unchanged.
CREATE OR REPLACE FUNCTION maplayer.building_cluster(z integer, x integer, y integer)
RETURNS bytea
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    -- Below the tileset's minzoom, or nonsense coordinates
    -- (ST_TileEnvelope would error → 500): empty tile, no table hit.
    IF z < 12 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    IF z >= 14 THEN
        SELECT ST_AsMVT(tile, 'building_cluster', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                cluster_id::text AS cluster_id,
                building_count,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.building_cluster_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        -- z12–13: overview zooms. Simplified geometry, no ids (near-unique
        -- uuid strings dominate tile size), sub-pixel clusters dropped —
        -- same thresholds as building_tiles (a cluster smaller than a
        -- single big building is invisible here anyway).
        SELECT ST_AsMVT(tile, 'building_cluster', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                ST_AsMVTGeom(geom_simple, env, 4096, 8, true) AS geom
            FROM maplayer.building_cluster_tiles
            WHERE geom_simple && env
              AND surface_area >= CASE WHEN z = 12 THEN 150 ELSE 60 END
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;

-- TileJSON metadata Martin merges into the source's TileJSON. "fields" is
-- MANDATORY per TileJSON 3.0 — see create_building_tiles.sql for the
-- failure mode when it's missing. Fields list = the z14+ attribute set.
COMMENT ON FUNCTION maplayer.building_cluster(integer, integer, integer) IS
'{"description": "FunderMaps building cluster (bouwkundige eenheid) outlines (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "building_cluster", "minzoom": 12, "maxzoom": 16, "fields": {"cluster_id": "String", "building_count": "Number"}}]}';

-- Serving role (see create_building_tiles.sql).
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        GRANT USAGE ON SCHEMA maplayer TO fundermaps_tileserver;
        GRANT SELECT ON maplayer.building_cluster_tiles TO fundermaps_tileserver;
        GRANT EXECUTE ON FUNCTION maplayer.building_cluster(integer, integer, integer)
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
            ON maplayer.building_cluster_tiles TO fundermaps_windmill;
        GRANT SELECT ON data.building_cluster TO fundermaps_windmill;
        GRANT SELECT ON geocoder.building_active TO fundermaps_windmill;
    END IF;
END $$;
