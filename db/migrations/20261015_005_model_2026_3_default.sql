-- model-2026.3 becomes the default model (Yorick, 2026-10-12: "2026.3 will become the default";
-- built to the spec #283 by 20261015_004; closes Worker #222, #235, #236, #242, #278 via #283).
--
-- Three things move together, because they are three different switches:
--   1. the DATA: data.model_risk_static, the pointer view every consumer reads (Webservice
--      /v4/product/*, API product and intake routes), now selects from
--      data.model_risk_static_2026_3 (built by 20261015_004) instead of the 2024.1 matview. It
--      selects that matview's first 30 columns by name; the explaining columns after them stay
--      unserved;
--   2. the STAMP: data.model_version.is_default moves to model-2026.3. The Webservice reads the
--      default slug from there for modelVersion and X-FunderMaps-Version (60 s cache);
--   3. the DERIVED objects, which were still bound to the concrete 2024.1 matview (left that way
--      on 2026-08-09, "a required decision when the default changes"): they now read the pointer,
--      so they follow whatever is default from here on and the next switch does not touch them.
--        data.building_geo_hierarchy               -> maplayer.analysis_full -> map tiles
--                                                     (maplayer.refresh_building_tiles) and the
--                                                     GPKG / GeoParquet archive export
--        data.statistics_product_foundation_risk   -> /statistics of Webservice and API
--        data.statistics_product_foundation_type   -> same (its numbers do not change: 2026.3
--                                                     leaves the foundation type alone)
--
-- What changes for a reader: the four risks and their three labels, as the spec #283 says. On a
-- full copy of the model's inputs (2026-10-15): 139,550 of 11,321,489 panden change a risk letter,
-- the worst letter gets better on 65,988 and worse on 14,143, no pand ends without a risk, and the
-- labels move on 478,226 panden (a risk is labelled by the rule that produced it). Foundation type
-- and every other column are unchanged. ship-2026-3.sh prints the numbers of the day before it runs
-- this file.
--
-- The model-2024.1 matview stays and keeps refreshing (it is the way back).
--
-- Locks. The two statistics matviews cannot be changed in place, so they are built again under
-- a temporary name first (about a minute, nothing is blocked), and only then swapped in. All
-- statements that need an exclusive lock on something customers read come after that and are
-- instant; lock_timeout makes the file fail and roll back instead of queueing product reads
-- behind a long reader (the tile refresh reads data.building_geo_hierarchy for minutes: do not
-- apply this during a refresh run).
--
-- After this file: run the refresh flow once (f/fundermaps/data/refresh_data_model). The new
-- statistics matviews are built while the pointer still shows 2024.1, and the map tiles and the
-- archive export only pick the new default up at a refresh. The flow also logs the run, which is
-- what moves calculatedAt.
--
-- Going back is the same switch the other way: CREATE OR REPLACE VIEW data.model_risk_static
-- ... FROM data.model_risk_static_2024_1, move is_default back, refresh.

-- ---------------------------------------------------------------------------
-- Refuse on a state this file was not written for.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    -- Only the build to the spec (20261015_004), never the QuickScan-only build of 20261012_002.
    IF NOT EXISTS (SELECT 1 FROM data.model_version
                    WHERE slug = 'model-2026.3' AND title = 'Foundation risk model 2026.3') THEN
        RAISE EXCEPTION 'model-2026.3 is not the build to the spec: apply 20261015_004 first';
    END IF;
    IF (SELECT relispopulated FROM pg_class WHERE oid = 'data.model_risk_static_2024_1'::regclass)
       AND NOT (SELECT relispopulated FROM pg_class WHERE oid = 'data.model_risk_static_2026_3'::regclass) THEN
        RAISE EXCEPTION 'data.model_risk_static_2026_3 is not populated while model-2024.1 is: the default would serve nothing';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1. The statistics matviews, rebuilt on the pointer under a temporary name.
--    Same query text as the live ones (schema.sql), the pointer instead of the
--    2024.1 matview. The slow part; holds no lock a reader waits for.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW data.statistics_product_foundation_risk_next AS
 SELECT neighborhood_id,
    risk AS foundation_risk,
    count(risk)::numeric / sum(count(risk)) OVER (PARTITION BY neighborhood_id) * 100::numeric AS percentage
   FROM ( SELECT mrs.neighborhood_id,
            ( SELECT unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]) AS risk
                  ORDER BY (unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]))
                 LIMIT 1) AS risk
           FROM data.model_risk_static mrs) acr
  WHERE risk IS NOT NULL
  GROUP BY neighborhood_id, risk
WITH NO DATA;

CREATE MATERIALIZED VIEW data.statistics_product_foundation_type_next AS
 SELECT neighborhood_id,
    foundation_type,
    count(foundation_type)::numeric / sum(count(foundation_type)) OVER (PARTITION BY neighborhood_id) * 100::numeric AS percentage
   FROM data.model_risk_static mrs
  GROUP BY neighborhood_id, foundation_type
WITH NO DATA;

-- A schema-only database has the model matviews unpopulated and reading them errors; there the
-- statistics stay unpopulated too, as they were.
DO $$
BEGIN
    IF (SELECT relispopulated FROM pg_class WHERE oid = 'data.model_risk_static_2024_1'::regclass) THEN
        REFRESH MATERIALIZED VIEW data.statistics_product_foundation_risk_next;
        REFRESH MATERIALIZED VIEW data.statistics_product_foundation_type_next;
    END IF;
END $$;

-- The unique indexes REFRESH ... CONCURRENTLY needs; they get the live names in step 2.
CREATE UNIQUE INDEX statistics_product_foundation_risk_next_idx
    ON data.statistics_product_foundation_risk_next (neighborhood_id, foundation_risk);
CREATE UNIQUE INDEX statistics_product_foundation_type_next_idx
    ON data.statistics_product_foundation_type_next (neighborhood_id, foundation_type);

-- ---------------------------------------------------------------------------
-- 2. The switch. Everything from here is instant. The view a long reader may
--    hold goes first, so a timeout hits before anything customers read is locked.
-- ---------------------------------------------------------------------------
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE VIEW data.building_geo_hierarchy AS
 SELECT mrs.building_id,
    mrs.address_count,
    mrs.neighborhood_id,
    mrs.construction_year,
    mrs.construction_year_reliability,
    mrs.foundation_type,
    mrs.foundation_type_reliability,
    mrs.restoration_costs,
    mrs.drystand,
    mrs.drystand_risk,
    mrs.drystand_risk_reliability,
    mrs.bio_infection_risk,
    mrs.bio_infection_risk_reliability,
    mrs.dewatering_depth,
    mrs.dewatering_depth_risk,
    mrs.dewatering_depth_risk_reliability,
    mrs.unclassified_risk,
    mrs.height,
    mrs.velocity,
    mrs.ground_water_level,
    mrs.ground_level,
    mrs.soil,
    mrs.surface_area,
    mrs.owner,
    mrs.inquiry_id,
    mrs.inquiry_type,
    mrs.damage_cause,
    mrs.enforcement_term,
    mrs.overall_quality,
    mrs.recovery_type,
    ba.geom,
    n.external_id AS ext_neighborhood_id,
    d.external_id AS ext_district_id,
    m.external_id AS ext_municipality_id
   FROM data.model_risk_static mrs
     JOIN geocoder.building_active ba ON ba.external_id = mrs.building_id
     JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
     JOIN geocoder.district d ON d.id::text = n.district_id::text
     JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text
  WHERE mrs.address_count > 0;

-- Nothing depends on the two statistics matviews (checked on prod 2026-10-12); if something
-- does by now, these DROPs fail and the whole file rolls back.
DROP MATERIALIZED VIEW data.statistics_product_foundation_risk;
ALTER MATERIALIZED VIEW data.statistics_product_foundation_risk_next RENAME TO statistics_product_foundation_risk;
ALTER INDEX data.statistics_product_foundation_risk_next_idx RENAME TO statistics_product_foundation_risk_neighborhood_idx;

DROP MATERIALIZED VIEW data.statistics_product_foundation_type;
ALTER MATERIALIZED VIEW data.statistics_product_foundation_type_next RENAME TO statistics_product_foundation_type;
ALTER INDEX data.statistics_product_foundation_type_next_idx RENAME TO statistics_product_foundation_type_neighborhood_idx;

-- The pointer. Same 30 columns in the same order (20261012_002 checked that), so owner, grants
-- and comment of the view stay as they are.
CREATE OR REPLACE VIEW data.model_risk_static AS
 SELECT building_id,
    address_count,
    neighborhood_id,
    construction_year,
    construction_year_reliability,
    foundation_type,
    foundation_type_reliability,
    restoration_costs,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    unclassified_risk,
    height,
    velocity,
    ground_water_level,
    ground_level,
    soil,
    surface_area,
    owner,
    inquiry_id,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    recovery_type
   FROM data.model_risk_static_2026_3;

-- The registry. One default at a time (partial unique index), so the old one goes first.
UPDATE data.model_version
   SET is_default = false
 WHERE slug = 'model-2024.1';

UPDATE data.model_version
   SET is_default = true,
       status = 'active',
       activated_at = now()
 WHERE slug = 'model-2026.3';

DO $$
BEGIN
    IF (SELECT string_agg(slug, ',') FROM data.model_version WHERE is_default) IS DISTINCT FROM 'model-2026.3' THEN
        RAISE EXCEPTION 'the default model is not model-2026.3 after the switch';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Owner and grants of the two rebuilt matviews, as the dropped ones had them
--    (prod 2026-10-12: read for the two application roles, read + refresh for the flow).
-- ---------------------------------------------------------------------------
ALTER MATERIALIZED VIEW data.statistics_product_foundation_risk OWNER TO fundermaps;
ALTER MATERIALIZED VIEW data.statistics_product_foundation_type OWNER TO fundermaps;

GRANT SELECT ON data.statistics_product_foundation_risk TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_product_foundation_type TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT, MAINTAIN ON data.statistics_product_foundation_risk TO fundermaps_windmill;
GRANT SELECT, MAINTAIN ON data.statistics_product_foundation_type TO fundermaps_windmill;
