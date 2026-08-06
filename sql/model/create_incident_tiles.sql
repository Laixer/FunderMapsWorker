-- Dynamic tile sources for the four incident map layers, served by the
-- Martin tileserver.
--
-- Replaces the nightly tippecanoe builds of maplayer.incident and the
-- three incident_{district,municipality,neighborhood} aggregation views.
-- Those four builds cost ~40 of the ~50 minutes process_mapset spends
-- every night and produced 230,551 objects in fundermaps-tileset — to
-- render 5,572 features. incident_district alone took 26.5 min to tile
-- 1,016 polygons, almost all of it uploading 155,335 tile files.
--
-- The views are NOT dropped: they still feed the nightly GPKG export to
-- s3://fundermaps-data/mapset/, which is the permanent model history. The
-- refreshes below repeat the views' joins rather than selecting from them,
-- because the tiles need CBS ids the views do not expose (see below) and
-- the archived GPKG schema must not drift.
--
-- GEOFENCE — the reason the CBS ids are here. WebFront's geofence
-- (useGeographyFilter.ts) builds  any(match(<id>, fence), !has(<id>))  so a
-- feature MISSING the id is SHOWN. The static incident tiles carry no
-- municipality_id, and 'Schiedam publiek' is a PUBLIC mapset fenced to
-- GM0606 client-side (store/mapsets.ts) that includes the incident layer —
-- so it currently renders all 2,728 Dutch incidents instead of Schiedam's
-- 216. Emitting the ids makes the existing fence actually bite. This is the
-- same failure mode as the z12–13 tile slimming that leaked all of NL to
-- fenced orgs (Worker #52): any attribute the fence reads must be present
-- at every zoom.

-- ---------------------------------------------------------------------------
-- incident — building footprints, one per incident report
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS maplayer.incident_tiles (
    id text PRIMARY KEY,
    neighborhood_id text,
    district_id text,
    municipality_id text,
    -- report.foundation_damage_cause as text: ST_AsMVT emits the enum label
    -- either way, and text keeps this table independent of enum DDL.
    foundation_damage_cause text,
    -- double precision, NOT numeric: ST_AsMVT has no MVT type for numeric and
    -- encodes it as a STRING, which silently breaks fill-extrusion-height
    -- (incident.json feeds ["get","height"] straight into it). The static
    -- tippecanoe tiles emitted a number here.
    height double precision,
    geom geometry(MultiPolygon, 3857)
);

CREATE INDEX IF NOT EXISTS incident_tiles_geom_idx
    ON maplayer.incident_tiles USING gist (geom);

-- ---------------------------------------------------------------------------
-- incident_{neighborhood,district,municipality} — CBS area polygons with a
-- per-area incident count. These carry a simplified geometry variant: the
-- polygons are detailed (860k vertices over 1,016 districts) and are drawn
-- at overview zooms where that detail is far below one pixel.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS maplayer.incident_neighborhood_tiles (
    neighborhood_id text PRIMARY KEY,
    district_id text,
    municipality_id text,
    incident_count integer NOT NULL,
    geom geometry(MultiPolygon, 3857),
    geom_simple geometry(MultiPolygon, 3857)
);

CREATE INDEX IF NOT EXISTS incident_neighborhood_tiles_geom_idx
    ON maplayer.incident_neighborhood_tiles USING gist (geom);
CREATE INDEX IF NOT EXISTS incident_neighborhood_tiles_geom_simple_idx
    ON maplayer.incident_neighborhood_tiles USING gist (geom_simple);

CREATE TABLE IF NOT EXISTS maplayer.incident_district_tiles (
    district_id text PRIMARY KEY,
    municipality_id text,
    incident_count integer NOT NULL,
    geom geometry(MultiPolygon, 3857),
    geom_simple geometry(MultiPolygon, 3857)
);

CREATE INDEX IF NOT EXISTS incident_district_tiles_geom_idx
    ON maplayer.incident_district_tiles USING gist (geom);
CREATE INDEX IF NOT EXISTS incident_district_tiles_geom_simple_idx
    ON maplayer.incident_district_tiles USING gist (geom_simple);

CREATE TABLE IF NOT EXISTS maplayer.incident_municipality_tiles (
    municipality_id text PRIMARY KEY,
    incident_count integer NOT NULL,
    geom geometry(MultiPolygon, 3857),
    geom_simple geometry(MultiPolygon, 3857)
);

CREATE INDEX IF NOT EXISTS incident_municipality_tiles_geom_idx
    ON maplayer.incident_municipality_tiles USING gist (geom);
CREATE INDEX IF NOT EXISTS incident_municipality_tiles_geom_simple_idx
    ON maplayer.incident_municipality_tiles USING gist (geom_simple);

-- ---------------------------------------------------------------------------
-- Population. One procedure for all four, since they share the incident ⋈
-- building_active spine and are cheap enough (~5.5k rows) to rebuild together.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE maplayer.refresh_incident_tiles()
LANGUAGE sql
AS $$
    TRUNCATE maplayer.incident_tiles;

    INSERT INTO maplayer.incident_tiles (
        id, neighborhood_id, district_id, municipality_id,
        foundation_damage_cause, height, geom
    )
    SELECT
        i.id,
        n.external_id,
        d.external_id,
        m.external_id,
        i.foundation_damage_cause::text,
        round(GREATEST(bh.height, 0::real)::numeric, 2)::double precision,
        ST_Multi(ST_Transform(ba.geom, 3857))
    FROM report.incident i
    JOIN geocoder.building_active ba ON ba.external_id = i.building_id::text
    JOIN data.building_height bh ON bh.building_id = ba.external_id
    -- LEFT so a building with no CBS geography keeps its tile feature, matching
    -- the view's row count exactly. All 2,728 rows resolve today; a future null
    -- degrades to "shown when fenced", never to a dropped incident.
    LEFT JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    LEFT JOIN geocoder.district d ON d.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text;

    TRUNCATE maplayer.incident_neighborhood_tiles;

    INSERT INTO maplayer.incident_neighborhood_tiles (
        neighborhood_id, district_id, municipality_id, incident_count,
        geom, geom_simple
    )
    SELECT
        n.external_id,
        d.external_id,
        m.external_id,
        count(*),
        ST_Multi(ST_Transform(n.geom, 3857)),
        -- 20 Mercator units ≈ 12 m at NL latitude: sub-pixel at z11 (76 m/px)
        -- and every zoom below it, where geom_simple is used.
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(n.geom, 3857), 20.0))
    FROM report.incident i
    JOIN geocoder.building_active ba ON ba.external_id = i.building_id::text
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    LEFT JOIN geocoder.district d ON d.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text
    GROUP BY n.external_id, d.external_id, m.external_id, n.geom;

    TRUNCATE maplayer.incident_district_tiles;

    INSERT INTO maplayer.incident_district_tiles (
        district_id, municipality_id, incident_count, geom, geom_simple
    )
    SELECT
        d.external_id,
        m.external_id,
        count(*),
        ST_Multi(ST_Transform(d.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(d.geom, 3857), 20.0))
    FROM report.incident i
    JOIN geocoder.building_active ba ON ba.external_id = i.building_id::text
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    JOIN geocoder.district d ON d.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text
    GROUP BY d.external_id, m.external_id, d.geom;

    TRUNCATE maplayer.incident_municipality_tiles;

    INSERT INTO maplayer.incident_municipality_tiles (
        municipality_id, incident_count, geom, geom_simple
    )
    SELECT
        m.external_id,
        count(*),
        ST_Multi(ST_Transform(m.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(m.geom, 3857), 20.0))
    FROM report.incident i
    JOIN geocoder.building_active ba ON ba.external_id = i.building_id::text
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    JOIN geocoder.district d ON d.id::text = n.district_id::text
    JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text
    GROUP BY m.external_id, m.geom;

    ANALYZE maplayer.incident_tiles;
    ANALYZE maplayer.incident_neighborhood_tiles;
    ANALYZE maplayer.incident_district_tiles;
    ANALYZE maplayer.incident_municipality_tiles;
$$;

-- ---------------------------------------------------------------------------
-- Martin function sources. MVT layer names match the old static tilesets, so
-- every WebFront layer config (source == source-layer == tileset name) and
-- FunderMapsReport's incident-district chapter keep working unchanged.
-- Zoom ranges come from maplayer.bundle: incident 12–16, district and
-- neighborhood 10–16, municipality 7–11.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION maplayer.incident(z integer, x integer, y integer)
RETURNS bytea
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    IF z < 12 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'incident', 4096, 'geom') INTO mvt
    FROM (
        SELECT
            id,
            neighborhood_id,
            district_id,
            municipality_id,
            foundation_damage_cause,
            height,
            ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
        FROM maplayer.incident_tiles
        WHERE geom && env
    ) tile
    WHERE tile.geom IS NOT NULL;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;

COMMENT ON FUNCTION maplayer.incident(integer, integer, integer) IS
'{"description": "FunderMaps foundation incident reports (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "incident", "minzoom": 12, "maxzoom": 16, "fields": {"id": "String", "neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "foundation_damage_cause": "String", "height": "Number"}}]}';

CREATE OR REPLACE FUNCTION maplayer.incident_neighborhood(z integer, x integer, y integer)
RETURNS bytea
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    IF z < 10 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    -- Two branches rather than a CASE inside WHERE: a CASE expression over
    -- two geometry columns is not indexable, so the planner would seq-scan
    -- and evaluate && against every polygon in the table.
    IF z >= 12 THEN
        SELECT ST_AsMVT(tile, 'incident_neighborhood', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                neighborhood_id,
                district_id,
                municipality_id,
                incident_count,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.incident_neighborhood_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        SELECT ST_AsMVT(tile, 'incident_neighborhood', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                neighborhood_id,
                district_id,
                municipality_id,
                incident_count,
                ST_AsMVTGeom(geom_simple, env, 4096, 64, true) AS geom
            FROM maplayer.incident_neighborhood_tiles
            WHERE geom_simple && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;

COMMENT ON FUNCTION maplayer.incident_neighborhood(integer, integer, integer) IS
'{"description": "FunderMaps incident counts per CBS neighborhood (dynamic)", "minzoom": 10, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "incident_neighborhood", "minzoom": 10, "maxzoom": 16, "fields": {"neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "incident_count": "Number"}}]}';

CREATE OR REPLACE FUNCTION maplayer.incident_district(z integer, x integer, y integer)
RETURNS bytea
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    IF z < 10 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    -- Indexable branches, see maplayer.incident_neighborhood().
    IF z >= 12 THEN
        SELECT ST_AsMVT(tile, 'incident_district', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                district_id,
                municipality_id,
                incident_count,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.incident_district_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        SELECT ST_AsMVT(tile, 'incident_district', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                district_id,
                municipality_id,
                incident_count,
                ST_AsMVTGeom(geom_simple, env, 4096, 64, true) AS geom
            FROM maplayer.incident_district_tiles
            WHERE geom_simple && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;

COMMENT ON FUNCTION maplayer.incident_district(integer, integer, integer) IS
'{"description": "FunderMaps incident counts per CBS district (dynamic)", "minzoom": 10, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "incident_district", "minzoom": 10, "maxzoom": 16, "fields": {"district_id": "String", "municipality_id": "String", "incident_count": "Number"}}]}';

CREATE OR REPLACE FUNCTION maplayer.incident_municipality(z integer, x integer, y integer)
RETURNS bytea
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    -- This tileset is z7–11 only; geom_simple is therefore used at every
    -- zoom it serves, and the full geometry column is kept for parity with
    -- the archived GPKG and any future zoom extension.
    IF z < 7 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'incident_municipality', 4096, 'geom') INTO mvt
    FROM (
        SELECT
            municipality_id,
            incident_count,
            ST_AsMVTGeom(geom_simple, env, 4096, 64, true) AS geom
        FROM maplayer.incident_municipality_tiles
        WHERE geom_simple && env
    ) tile
    WHERE tile.geom IS NOT NULL;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;

COMMENT ON FUNCTION maplayer.incident_municipality(integer, integer, integer) IS
'{"description": "FunderMaps incident counts per municipality (dynamic)", "minzoom": 7, "maxzoom": 11, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "incident_municipality", "minzoom": 7, "maxzoom": 11, "fields": {"municipality_id": "String", "incident_count": "Number"}}]}';

-- ---------------------------------------------------------------------------
-- Grants (see create_building_tiles.sql).
-- ---------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        GRANT USAGE ON SCHEMA maplayer TO fundermaps_tileserver;
        GRANT SELECT ON
            maplayer.incident_tiles,
            maplayer.incident_neighborhood_tiles,
            maplayer.incident_district_tiles,
            maplayer.incident_municipality_tiles
            TO fundermaps_tileserver;
        GRANT EXECUTE ON FUNCTION maplayer.incident(integer, integer, integer),
            maplayer.incident_neighborhood(integer, integer, integer),
            maplayer.incident_district(integer, integer, integer),
            maplayer.incident_municipality(integer, integer, integer)
            TO fundermaps_tileserver;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_windmill') THEN
        GRANT USAGE ON SCHEMA maplayer TO fundermaps_windmill;
        GRANT SELECT, INSERT, TRUNCATE, MAINTAIN ON
            maplayer.incident_tiles,
            maplayer.incident_neighborhood_tiles,
            maplayer.incident_district_tiles,
            maplayer.incident_municipality_tiles
            TO fundermaps_windmill;
        GRANT SELECT ON report.incident TO fundermaps_windmill;
        GRANT SELECT ON data.building_height TO fundermaps_windmill;
        GRANT SELECT ON geocoder.neighborhood TO fundermaps_windmill;
        GRANT SELECT ON geocoder.district TO fundermaps_windmill;
        GRANT SELECT ON geocoder.municipality TO fundermaps_windmill;
    END IF;
END $$;
