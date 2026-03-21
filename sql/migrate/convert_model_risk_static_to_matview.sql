-- Migration: Convert data.model_risk_static from table to materialized view
--
-- Purpose: Replace INSERT ON CONFLICT upsert pattern with REFRESH MATERIALIZED
-- VIEW CONCURRENTLY for zero-downtime, less IO contention, and no REINDEX.
--
-- Strategy: Shadow-build the matview under a temporary name, then do an atomic
-- swap. Reads hit the old table until the instant rename.
--
-- Estimated time: ~40 min (matview population) + seconds (swap) + ~30 min (stats refresh)
-- Downtime: seconds (just the rename transaction)
--
-- Prerequisites:
--   1. Disable pg_cron job 6 before running
--   2. Run during low-traffic period

-- =============================================================================
-- STEP 0: Disable pg_cron (run as doadmin in defaultdb)
-- =============================================================================
-- SELECT cron.unschedule(6);

-- =============================================================================
-- STEP 1: Build shadow matview (~40 min, no downtime)
-- =============================================================================
-- Old table still serves all reads during this step.

CREATE MATERIALIZED VIEW data.model_risk_static_new AS
SELECT
    building_id,
    external_building_id,
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
FROM data.model_risk_dynamic_all;

-- Build indexes on shadow (no contention with reads on old table)
CREATE UNIQUE INDEX model_risk_static_new_pkey ON data.model_risk_static_new USING btree (building_id);
CREATE UNIQUE INDEX model_risk_static_new_external_building_id_idx ON data.model_risk_static_new USING btree (external_building_id);
CREATE INDEX model_risk_static_new_neighborhood_idx ON data.model_risk_static_new USING btree (neighborhood_id);

-- =============================================================================
-- STEP 2: Atomic swap (seconds of downtime)
-- =============================================================================
BEGIN;

-- Drop dependent views (CASCADE from building_geo_hierarchy gets the 5 maplayer.analysis_* views)
DROP VIEW IF EXISTS data.building_geo_hierarchy CASCADE;

-- Drop statistics matviews that directly reference model_risk_static
-- CASCADE needed: maplayer.statistics_foundation_risk depends on statistics_product_foundation_risk
DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_foundation_type CASCADE;
DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_foundation_risk CASCADE;
DROP MATERIALIZED VIEW IF EXISTS data.statistics_postal_code_foundation_risk CASCADE;
DROP MATERIALIZED VIEW IF EXISTS data.statistics_postal_code_foundation_type CASCADE;

-- Rename old indexes FIRST to avoid name collision with new indexes
ALTER INDEX data.model_risk_static_pkey RENAME TO model_risk_static_pkey_old;
ALTER INDEX data.external_building_id_idx RENAME TO external_building_id_idx_old;
ALTER INDEX data.idx_mrs_neighborhood RENAME TO idx_mrs_neighborhood_old;

-- Keep old table as backup (rename instead of drop)
ALTER TABLE data.model_risk_static RENAME TO model_risk_static_backup;

-- Rename shadow matview to production name
ALTER MATERIALIZED VIEW data.model_risk_static_new RENAME TO model_risk_static;

-- Rename indexes to match old names
ALTER INDEX data.model_risk_static_new_pkey RENAME TO model_risk_static_pkey;
ALTER INDEX data.model_risk_static_new_external_building_id_idx RENAME TO external_building_id_idx;
ALTER INDEX data.model_risk_static_new_neighborhood_idx RENAME TO idx_mrs_neighborhood;

COMMIT;

-- =============================================================================
-- STEP 3: Recreate dependent views (instant)
-- =============================================================================

-- building_geo_hierarchy view
CREATE VIEW data.building_geo_hierarchy AS
SELECT mrs.building_id,
    mrs.external_building_id,
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
JOIN geocoder.building_active ba ON ba.id = mrs.building_id
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id
WHERE mrs.address_count > 0;

-- maplayer.analysis_building
CREATE VIEW maplayer.analysis_building AS
SELECT external_building_id AS building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    address_count,
    construction_year,
    construction_year_reliability,
    height,
    owner,
    geom
FROM data.building_geo_hierarchy;

-- maplayer.analysis_foundation
CREATE VIEW maplayer.analysis_foundation AS
SELECT external_building_id AS building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    foundation_type,
    foundation_type_reliability,
    height,
    owner,
    recovery_type,
    velocity,
    geom
FROM data.building_geo_hierarchy;

-- maplayer.analysis_full
CREATE VIEW maplayer.analysis_full AS
SELECT external_building_id AS building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    address_count,
    foundation_type,
    foundation_type_reliability,
    construction_year,
    construction_year_reliability,
    restoration_costs,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    unclassified_risk,
    overall_quality,
    ground_water_level,
    ground_level,
    soil,
    surface_area,
    recovery_type,
    inquiry_type,
    enforcement_term,
    damage_cause,
    velocity,
    height,
    owner,
    inquiry_id,
    geom
FROM data.building_geo_hierarchy;

-- maplayer.analysis_report
CREATE VIEW maplayer.analysis_report AS
SELECT external_building_id AS building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    height,
    owner,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    geom
FROM data.building_geo_hierarchy;

-- maplayer.analysis_risk
CREATE VIEW maplayer.analysis_risk AS
SELECT external_building_id AS building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    restoration_costs,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    unclassified_risk,
    height,
    owner,
    geom
FROM data.building_geo_hierarchy;

-- =============================================================================
-- STEP 4: Recreate statistics matviews + refresh (~30 min)
-- =============================================================================

CREATE MATERIALIZED VIEW data.statistics_product_foundation_risk AS
SELECT neighborhood_id,
    risk AS foundation_risk,
    (((count(risk))::numeric / sum(count(risk)) OVER (PARTITION BY neighborhood_id)) * (100)::numeric) AS percentage
FROM (SELECT mrs.neighborhood_id,
        (SELECT unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]) AS risk
              ORDER BY (unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]))
             LIMIT 1) AS risk
       FROM data.model_risk_static mrs) acr
WHERE (risk IS NOT NULL)
GROUP BY neighborhood_id, risk
WITH NO DATA;

CREATE UNIQUE INDEX statistics_product_foundation_risk_neighborhood_foundation_risk
    ON data.statistics_product_foundation_risk USING btree (neighborhood_id, foundation_risk);

CREATE MATERIALIZED VIEW data.statistics_product_foundation_type AS
SELECT neighborhood_id,
    foundation_type,
    (((count(foundation_type))::numeric / sum(count(foundation_type)) OVER (PARTITION BY neighborhood_id)) * (100)::numeric) AS percentage
FROM data.model_risk_static mrs
GROUP BY neighborhood_id, foundation_type
WITH NO DATA;

CREATE UNIQUE INDEX statistics_product_foundation_type_neighborhood_foundation_risk
    ON data.statistics_product_foundation_type USING btree (neighborhood_id, foundation_type);

CREATE MATERIALIZED VIEW data.statistics_postal_code_foundation_risk AS
SELECT postal_code,
    risk AS foundation_risk,
    (((count(risk))::numeric / sum(count(risk)) OVER (PARTITION BY postal_code)) * (100)::numeric) AS percentage
FROM (SELECT a.postal_code,
        (SELECT unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]) AS risk
              ORDER BY (unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]))
             LIMIT 1) AS risk
       FROM data.model_risk_static mrs
       JOIN geocoder.address_building ab ON ab.building_id = mrs.building_id
       JOIN geocoder.address a ON a.id = ab.address_id) acr
WHERE (risk IS NOT NULL)
GROUP BY postal_code, risk
WITH NO DATA;

CREATE UNIQUE INDEX statistics_postal_code_foundation_risk_postal_code_foundation_r
    ON data.statistics_postal_code_foundation_risk USING btree (postal_code, foundation_risk);

CREATE MATERIALIZED VIEW data.statistics_postal_code_foundation_type AS
SELECT a.postal_code,
    mrs.foundation_type,
    (((count(mrs.foundation_type))::numeric / sum(count(mrs.foundation_type)) OVER (PARTITION BY a.postal_code)) * (100)::numeric) AS percentage
FROM data.model_risk_static mrs
JOIN geocoder.address_building ab ON ab.building_id = mrs.building_id
JOIN geocoder.address a ON a.id = ab.address_id
GROUP BY a.postal_code, mrs.foundation_type
WITH NO DATA;

CREATE UNIQUE INDEX statistics_postal_code_foundation_type_postal_code_foundation_r
    ON data.statistics_postal_code_foundation_type USING btree (postal_code, foundation_type);

-- Recreate maplayer view that depends on statistics_product_foundation_risk
CREATE VIEW maplayer.statistics_foundation_risk AS
SELECT spfr.neighborhood_id,
    spfr.foundation_risk,
    spfr.percentage,
    n.geom
FROM data.statistics_product_foundation_risk spfr
JOIN geocoder.neighborhood n ON n.id = spfr.neighborhood_id;

-- Populate statistics matviews
REFRESH MATERIALIZED VIEW data.statistics_product_foundation_risk;
REFRESH MATERIALIZED VIEW data.statistics_product_foundation_type;
REFRESH MATERIALIZED VIEW data.statistics_postal_code_foundation_risk;
REFRESH MATERIALIZED VIEW data.statistics_postal_code_foundation_type;

-- =============================================================================
-- STEP 5: Restore GRANTs
-- =============================================================================
-- GRANTs are lost on ALL recreated objects (views, matviews), not just model_risk_static.

GRANT SELECT ON data.model_risk_static TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.building_geo_hierarchy TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_product_foundation_type TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_product_foundation_risk TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_postal_code_foundation_risk TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_postal_code_foundation_type TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON maplayer.analysis_building TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON maplayer.analysis_foundation TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON maplayer.analysis_full TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON maplayer.analysis_report TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON maplayer.analysis_risk TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON maplayer.statistics_foundation_risk TO fundermaps_webapp, fundermaps_webservice;

-- =============================================================================
-- STEP 6: Update refresh_all() procedure
-- =============================================================================

CREATE OR REPLACE PROCEDURE data.refresh_all()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Step 1: Refresh sample matviews
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.building_sample;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.cluster_sample;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.supercluster_sample;
    COMMIT;

    -- Step 2: Refresh risk model (was INSERT ON CONFLICT, now matview)
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.model_risk_static;
    COMMIT;

    -- Step 3: Refresh statistics matviews
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_inquiries;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_inquiry_municipality;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_incidents;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_incident_municipality;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_foundation_type;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_foundation_risk;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_data_collected;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_construction_years;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_buildings_restored;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_postal_code_foundation_type;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_postal_code_foundation_risk;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_postal_code_data_collected;
    COMMIT;

    -- Step 4: Submit process_mapset job to worker queue
    INSERT INTO application.worker_jobs (job_type, status) VALUES ('process_mapset', 'pending');
END;
$$;

-- =============================================================================
-- STEP 7: Drop obsolete procedure
-- =============================================================================

DROP PROCEDURE IF EXISTS data.model_risk_manifest();

-- =============================================================================
-- STEP 8: Re-enable pg_cron (run as doadmin in defaultdb)
-- =============================================================================
-- SELECT cron.schedule_in_database(6, '0 18 * * *', 'CALL data.refresh_all()', 'fundermaps');

-- =============================================================================
-- STEP 9: Cleanup (run after 24h bake-in)
-- =============================================================================
-- DROP TABLE IF EXISTS data.model_risk_static_backup;
