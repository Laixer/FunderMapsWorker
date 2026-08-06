-- Dynamic tile source for the QuickScan (gevelscan) map layer, served by
-- the Martin tileserver.
--
-- Replaces the nightly tippecanoe build of the maplayer.facade_scan view
-- (~1 min/night, 1,090 objects in fundermaps-tileset). Same shape as
-- maplayer.building_cluster_tiles: one flat physical table with the
-- geometry pre-transformed to Web Mercator, plus a (z,x,y) function
-- source Martin auto-publishes from the maplayer schema.
--
-- The whole dataset is ~3,200 building footprints / ~25k vertices
-- (540 kB of geometry), so there is deliberately NO simplified geometry
-- variant here — the entire layer is smaller than a single dense
-- building_tiles z12 tile. Attributes are a full 1:1 copy of the view's
-- column list so the dynamic tiles are drop-in identical to the static
-- ones the five QuickScan layer configs consume today.
--
-- maplayer.facade_scan (the view) is NOT dropped: it still feeds the
-- nightly GPKG export to s3://fundermaps-data/mapset/, which is the
-- permanent model history. The refresh below repeats the view's joins
-- rather than selecting from it, because the tiles need the CBS ids the
-- view does not expose and the archived GPKG schema must not drift.

CREATE TABLE IF NOT EXISTS maplayer.facade_scan_tiles (
    external_id text PRIMARY KEY,
    -- CBS codes. The view already exposes these; they are also what the
    -- WebFront geofence filters on (see create_incident_tiles.sql for why
    -- a missing id is worse than a wrong one).
    neighborhood_id text,
    district_id text,
    municipality_id text,
    -- double precision, NOT numeric: ST_AsMVT has no MVT type for numeric and
    -- encodes it as a STRING, which silently breaks fill-extrusion-height
    -- (["get","height"] must yield a number or the layer renders flat).
    -- The static tippecanoe tiles emitted a number here; building_tiles has
    -- always used double precision for the same reason.
    height double precision,
    owner text,
    -- report.rotation_type / report.crack_type / report.facade_scan_risk /
    -- data.foundation_risk_indication stored as text: ST_AsMVT emits the
    -- enum label either way, and text keeps this table independent of
    -- enum DDL (see the 2026-07-23 enum→text outage on application.*).
    skewed_parallel_facade text,
    skewed_perpendicular_facade text,
    facade_type text,
    settlement_speed text,
    facade_scan_risk text,
    risk text,
    priority text,
    geom geometry(MultiPolygon, 3857)
);

CREATE INDEX IF NOT EXISTS facade_scan_tiles_geom_idx
    ON maplayer.facade_scan_tiles USING gist (geom);

-- Population procedure. TRUNCATE + INSERT, same pattern as
-- maplayer.refresh_building_tiles().
CREATE OR REPLACE PROCEDURE maplayer.refresh_facade_scan_tiles()
LANGUAGE sql
AS $$
    TRUNCATE maplayer.facade_scan_tiles;

    INSERT INTO maplayer.facade_scan_tiles (
        external_id, neighborhood_id, district_id, municipality_id,
        height, owner, skewed_parallel_facade, skewed_perpendicular_facade,
        facade_type, settlement_speed, facade_scan_risk, risk, priority, geom
    )
    SELECT
        f.external_id,
        f.neighborhood_id,
        f.district_id,
        f.municipality_id,
        f.height::double precision,
        f.owner,
        f.skewed_parallel_facade::text,
        f.skewed_perpendicular_facade::text,
        f.facade_type::text,
        f.settlement_speed::text,
        f.facade_scan_risk::text,
        f.risk::text,
        f.priority::text,
        ST_Multi(ST_Transform(f.geom, 3857))
    FROM maplayer.facade_scan f;

    ANALYZE maplayer.facade_scan_tiles;
$$;

-- Martin function source: GET /facade_scan/{z}/{x}/{y}. The MVT layer name
-- matches the old static tileset ("facade_scan") so the five WebFront
-- QuickScan layer configs keep working with no change at all.
CREATE OR REPLACE FUNCTION maplayer.facade_scan(z integer, x integer, y integer)
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

    SELECT ST_AsMVT(tile, 'facade_scan', 4096, 'geom') INTO mvt
    FROM (
        SELECT
            external_id,
            neighborhood_id,
            district_id,
            municipality_id,
            height,
            owner,
            skewed_parallel_facade,
            skewed_perpendicular_facade,
            facade_type,
            settlement_speed,
            facade_scan_risk,
            risk,
            priority,
            ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
        FROM maplayer.facade_scan_tiles
        WHERE geom && env
    ) tile
    WHERE tile.geom IS NOT NULL;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;

-- TileJSON metadata Martin merges into the source's TileJSON. "fields" is
-- MANDATORY per TileJSON 3.0 — without it Martin fails to deserialize the
-- patch and silently drops the WHOLE comment (see create_building_tiles.sql).
COMMENT ON FUNCTION maplayer.facade_scan(integer, integer, integer) IS
'{"description": "FunderMaps QuickScan facade observations (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "facade_scan", "minzoom": 12, "maxzoom": 16, "fields": {"external_id": "String", "neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "height": "Number", "owner": "String", "skewed_parallel_facade": "String", "skewed_perpendicular_facade": "String", "facade_type": "String", "settlement_speed": "String", "facade_scan_risk": "String", "risk": "String", "priority": "String"}}]}';

-- Serving role (see create_building_tiles.sql).
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        GRANT USAGE ON SCHEMA maplayer TO fundermaps_tileserver;
        GRANT SELECT ON maplayer.facade_scan_tiles TO fundermaps_tileserver;
        GRANT EXECUTE ON FUNCTION maplayer.facade_scan(integer, integer, integer)
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
            ON maplayer.facade_scan_tiles TO fundermaps_windmill;
        GRANT SELECT ON maplayer.facade_scan TO fundermaps_windmill;
    END IF;
END $$;
