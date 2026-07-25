-- Dynamic admin-boundary tile source for the Martin tileserver.
--
-- Serves the municipality/district/neighborhood outlines the basemap style
-- draws as purple lines. Replaces the dead laixer.* boundary tilesets that
-- the legacy Mapbox Studio style read (uploaded to Mapbox years ago, never
-- refreshed) — this reads geocoder.* directly, so boundaries stay as fresh
-- as the BAG/CBS imports.
--
-- One function source, three vector layers in one tile: an MVT tile is a
-- sequence of layer messages, so concatenating the per-level ST_AsMVT
-- buffers yields a single valid tile. One request instead of three.
--
-- Row counts are small (355 / 3.2k / 14k) and Martin caches rendered
-- tiles, so the per-request 4326→3857 transform is fine. If it ever shows
-- up in profiles, materialize a 3857 copy like maplayer.building_tiles.

CREATE OR REPLACE FUNCTION maplayer.boundaries(z integer, x integer, y integer)
RETURNS bytea
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    env geometry;
    env4326 geometry;
    -- one MVT pixel at this zoom, for simplification
    tol double precision;
    mvt bytea := ''::bytea;
    part bytea;
BEGIN
    -- Below municipality minzoom, or nonsense coordinates
    -- (ST_TileEnvelope would error → 500): empty tile, no table hit.
    IF z < 7 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);
    env4326 := ST_Transform(env, 4326);
    tol := (40075016.686 / (1 << z)) / 4096;

    SELECT ST_AsMVT(tile, 'municipality', 4096, 'geom') INTO part
    FROM (
        SELECT external_id AS id, name,
               ST_AsMVTGeom(
                   ST_SimplifyPreserveTopology(ST_Transform(geom, 3857), tol),
                   env, 4096, 64, true) AS geom
        FROM geocoder.municipality
        WHERE geom && env4326 AND NOT water
    ) tile
    WHERE tile.geom IS NOT NULL;
    mvt := mvt || coalesce(part, ''::bytea);

    IF z >= 10 THEN
        SELECT ST_AsMVT(tile, 'district', 4096, 'geom') INTO part
        FROM (
            SELECT external_id AS id, name,
                   ST_AsMVTGeom(
                       ST_SimplifyPreserveTopology(ST_Transform(geom, 3857), tol),
                       env, 4096, 64, true) AS geom
            FROM geocoder.district
            WHERE geom && env4326 AND NOT water
        ) tile
        WHERE tile.geom IS NOT NULL;
        mvt := mvt || coalesce(part, ''::bytea);

        SELECT ST_AsMVT(tile, 'neighborhood', 4096, 'geom') INTO part
        FROM (
            SELECT external_id AS id, name,
                   ST_AsMVTGeom(
                       ST_SimplifyPreserveTopology(ST_Transform(geom, 3857), tol),
                       env, 4096, 64, true) AS geom
            FROM geocoder.neighborhood
            WHERE geom && env4326 AND NOT water
        ) tile
        WHERE tile.geom IS NOT NULL;
        mvt := mvt || coalesce(part, ''::bytea);
    END IF;

    RETURN mvt;
END;
$$;

-- TileJSON metadata Martin merges into the source's TileJSON. "fields" is
-- MANDATORY per TileJSON 3.0 — without it Martin silently drops the whole
-- comment (see maplayer.buildings).
COMMENT ON FUNCTION maplayer.boundaries(integer, integer, integer) IS
'{"description": "FunderMaps admin boundaries (municipality/district/neighborhood)", "minzoom": 7, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "municipality", "minzoom": 7, "maxzoom": 16, "fields": {"id": "String", "name": "String"}}, {"id": "district", "minzoom": 10, "maxzoom": 16, "fields": {"id": "String", "name": "String"}}, {"id": "neighborhood", "minzoom": 10, "maxzoom": 16, "fields": {"id": "String", "name": "String"}}]}';

-- Serving role: boundary geometry is public data (CBS admin borders).
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        GRANT USAGE ON SCHEMA geocoder TO fundermaps_tileserver;
        GRANT SELECT ON geocoder.municipality, geocoder.district,
            geocoder.neighborhood TO fundermaps_tileserver;
        GRANT EXECUTE ON FUNCTION maplayer.boundaries(integer, integer, integer)
            TO fundermaps_tileserver;
    END IF;
END $$;
