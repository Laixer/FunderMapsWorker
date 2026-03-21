-- Phase A2: Precomputed Building Facts
--
-- Materializes expensive-to-compute columns that only change on BAG reload:
-- - ST_Area(geography) — most expensive per-row operation
-- - Address count — correlated subquery in current view
-- - Building height — currently double-scanned via building_elevation + building_height
-- - Ground level — from building_elevation
--
-- Only needs refreshing after BAG reload (quarterly), NOT on every risk refresh.

-- Create table if not exists (idempotent)
CREATE TABLE IF NOT EXISTS data.building_precomputed (
    building_id text PRIMARY KEY,               -- ba.external_id (BAG ID)
    neighborhood_id text,                        -- ba.neighborhood_id
    surface_area numeric(10,2),                  -- ST_Area(geom::geography)
    address_count integer NOT NULL DEFAULT 0,    -- count of geocoder.address rows
    construction_year_bag integer,               -- date_part('year', built_year)
    height double precision,                     -- GREATEST(roof - ground, 0)
    ground_level numeric(5,2)                    -- building_elevation.ground
);

CREATE INDEX IF NOT EXISTS idx_bp_neighborhood
    ON data.building_precomputed (neighborhood_id);

-- Population procedure
-- TRUNCATE + INSERT is faster than upsert for full refresh
CREATE OR REPLACE PROCEDURE data.refresh_building_precomputed()
LANGUAGE sql
AS $$
    TRUNCATE data.building_precomputed;

    INSERT INTO data.building_precomputed (
        building_id,
        neighborhood_id,
        surface_area,
        address_count,
        construction_year_bag,
        height,
        ground_level
    )
    SELECT
        ba.external_id,
        ba.neighborhood_id,
        round(ST_Area(ba.geom::geography, true)::numeric, 2),
        COALESCE(addr.cnt, 0),
        date_part('year', ba.built_year::date)::integer,
        GREATEST(bh.height, 0)::double precision,
        round(be.ground::numeric, 2)
    FROM geocoder.building_active ba
    LEFT JOIN data.building_elevation be ON be.building_id = ba.external_id
    LEFT JOIN data.building_height bh ON bh.building_id = ba.external_id
    LEFT JOIN (
        SELECT building_id, count(*)::integer AS cnt
        FROM geocoder.address
        GROUP BY building_id
    ) addr ON addr.building_id::text = ba.external_id
    WHERE ba.building_type = 'house';
$$;
