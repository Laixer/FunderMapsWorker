-- Issue Laixer/FunderMaps#882 — contractor layer in the report mapset,
-- tailored to the dynamic (Martin) tile pipeline: the tippecanoe-era
-- "analysis_report tileset" no longer exists, so the contractor lands as an
-- attribute in maplayer.building_tiles / the maplayer.buildings function
-- source, plus a layer + legend entry in the Rapportage mapset config.
--
-- Contractor = application.contractor named by the attribution of the
-- inquiry the model picked for the building (building_geo_hierarchy
-- .inquiry_id) — the same inquiry inquiry_type/damage_cause/… come from.
--
-- Canonical definitions updated alongside in sql/model/create_building_tiles.sql.
-- Run as a role that owns maplayer.building_tiles (fundermaps).

\set ON_ERROR_STOP on

--------------------------------------------------------------------------------
-- 1. Tile table + refresh + function source
--------------------------------------------------------------------------------

ALTER TABLE maplayer.building_tiles ADD COLUMN IF NOT EXISTS contractor text;

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

    ANALYZE maplayer.building_tiles;
$$;

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

COMMENT ON FUNCTION maplayer.buildings(integer, integer, integer) IS
'{"description": "FunderMaps building foundation tiles (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "buildings", "minzoom": 12, "maxzoom": 16, "fields": {"building_id": "String", "neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "address_count": "Number", "construction_year": "Number", "construction_year_reliability": "String", "foundation_type": "String", "foundation_type_reliability": "String", "restoration_costs": "Number", "drystand": "Number", "drystand_risk": "String", "drystand_risk_reliability": "String", "bio_infection_risk": "String", "bio_infection_risk_reliability": "String", "dewatering_depth": "Number", "dewatering_depth_risk": "String", "dewatering_depth_risk_reliability": "String", "unclassified_risk": "String", "height": "Number", "velocity": "Number", "owner": "String", "inquiry_type": "String", "damage_cause": "String", "enforcement_term": "Number", "overall_quality": "String", "recovery_type": "String", "contractor": "String"}}]}';

--------------------------------------------------------------------------------
-- 2. One-off backfill so the layer works before the next nightly rebuild
--    (~320k of 6.45M rows have an established inquiry with a contractor).
--------------------------------------------------------------------------------

UPDATE maplayer.building_tiles bt
SET contractor = src.name
FROM (
    SELECT mrs.building_id, con.name
    FROM data.model_risk_static mrs
    JOIN report.inquiry i ON i.id = mrs.inquiry_id
    JOIN application.attribution attr ON attr.id = i.attribution_id
    JOIN application.contractor con ON con.id = attr.contractor_id
) src
WHERE bt.building_id = src.building_id;

--------------------------------------------------------------------------------
-- 3. Mapset config: legend + layer list for the Rapportage mapset.
--    Legend = top-12 contractors by researched-building count (97% of the
--    321k sampled buildings) in "Legenda-default" design-token colors
--    (assigned with a stride so near-identical neighboring greens don't sit
--    next to each other), plus grey for the ~45 small "Overig" contractors.
--    Styling lives in FunderMapsWebFront src/config/layers/contractor.json —
--    names there must match application.contractor.name exactly.
--------------------------------------------------------------------------------

INSERT INTO application.mapset_layer (id, name, fields, "order") VALUES (
    'contractor',
    'Uitvoerder',
    '[
        {"name": "KCAF",                "color": "85DBBE"},
        {"name": "FunderMaps B.V.",     "color": "96ED51"},
        {"name": "Gemeente Haarlem",    "color": "B59E3C"},
        {"name": "Gemeente Rotterdam",  "color": "7EDF9A"},
        {"name": "Perfectkeur",         "color": "BDF450"},
        {"name": "Funderingsloket",     "color": "9D592D"},
        {"name": "Elkien",              "color": "79E370"},
        {"name": "Gemeente Dordrecht",  "color": "D3E14D"},
        {"name": "Wareco",              "color": "8C3A28"},
        {"name": "Gemeente Schiedam",   "color": "7EE587"},
        {"name": "VastgoedNED",         "color": "C9B441"},
        {"name": "Gemeente Zaanstad",   "color": "7B2A2D"},
        {"name": "Overig",              "color": "6A6C70"}
    ]'::jsonb,
    13
)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, fields = EXCLUDED.fields;

-- Rapportage mapset
UPDATE application.mapset
SET layers = array_append(layers, 'contractor')
WHERE id = 'clcqk9m5n000a14qel71c83m2'
  AND NOT ('contractor' = ANY (layers));
