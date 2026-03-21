-- Migration: report.inquiry_sample.building + geocoder.address.building_id from GFM to BAG IDs
-- Part of GFM→BAG migration step 2+3 (must migrate together due to shared matviews)
--
-- inquiry_sample: 443K rows
-- address: 10.4M rows (building_id NOT NULL: 10.4M)
--
-- Prerequisites:
--   - building_external_id_idx (unique) exists on geocoder.building(external_id)
--   - Zero orphans on both tables (verified pre-migration)
--
-- Gotchas from step 1:
--   - Drop FK BEFORE update (old FK validates new values)
--   - Re-GRANT SELECT after dropping/recreating matviews
--
-- Run as: fundermaps role (owner)

BEGIN;

-- ============================================================================
-- PHASE 1: Drop FKs (unblock updates)
-- ============================================================================

ALTER TABLE report.inquiry_sample DROP CONSTRAINT inquiry_sample_building_fkey;
ALTER TABLE geocoder.address DROP CONSTRAINT address_building_fk;

-- ============================================================================
-- PHASE 2: Update data (GFM → BAG)
-- ============================================================================

-- inquiry_sample: 443K rows
UPDATE report.inquiry_sample is2
SET building = b.external_id
FROM geocoder.building b
WHERE is2.building = b.id;

-- address: 10.4M rows (may take a minute)
UPDATE geocoder.address a
SET building_id = b.external_id
FROM geocoder.building b
WHERE a.building_id = b.id;

-- ============================================================================
-- PHASE 3: Create new FKs (pointing to building.external_id = BAG)
-- ============================================================================

ALTER TABLE report.inquiry_sample
    ADD CONSTRAINT inquiry_sample_building_fkey
    FOREIGN KEY (building) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE geocoder.address
    ADD CONSTRAINT address_building_fk
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id);

-- ============================================================================
-- PHASE 4: Recreate views
-- ============================================================================

-- 4a. address_building: change JOIN, keep outputting ba.id (GFM) as building_id
--     because model_risk_static and other consumers still use GFM building IDs
CREATE OR REPLACE VIEW geocoder.address_building AS
SELECT addr.id AS address_id,
    ba.id AS building_id,
    ba.geom
FROM geocoder.address addr
JOIN geocoder.building_active ba ON addr.building_id = ba.external_id;

-- 4b. model_risk_dynamic_all: change address lateral subquery
--     Old: a_1.building_id = ba.id (GFM=GFM)
--     New: a_1.building_id = ba.external_id (BAG=BAG)
--     Note: cannot use CREATE OR REPLACE (depends on dropped matviews), will recreate after matviews

-- 4c. maplayer.analysis_monitoring: change join
CREATE OR REPLACE VIEW maplayer.analysis_monitoring AS
SELECT DISTINCT ON (ba.external_id) ba.external_id AS building_id,
    round((GREATEST(bh.height, (0)::real))::numeric, 2) AS height,
    n.external_id AS neighborhood_id,
    d.external_id AS district_id,
    m.external_id AS municipality_id,
    ba.geom
FROM report.inquiry_sample is2
JOIN report.inquiry i ON i.id = is2.inquiry
JOIN geocoder.building_active ba ON ba.external_id = is2.building
JOIN data.building_height bh ON bh.building_id = ba.external_id
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id
WHERE i.type = 'monitoring'::report.inquiry_type;

-- 4d. maplayer.facade_scan: change is2.building join
CREATE OR REPLACE VIEW maplayer.facade_scan AS
SELECT inputz.external_id,
    inputz.neighborhood_id,
    inputz.district_id,
    inputz.municipality_id,
    inputz.height,
    inputz.owner,
    inputz.skewed_parallel_facade,
    inputz.skewed_perpendicular_facade,
    inputz.facade_type,
    inputz.settlement_speed,
    inputz.facade_scan_risk,
    mg.risk,
    rtp.priority,
    inputz.geom
FROM (( SELECT DISTINCT ON (ba.external_id) ba.external_id,
            n.external_id AS neighborhood_id,
            d.external_id AS district_id,
            m.external_id AS municipality_id,
            round((GREATEST(bh.height, (0)::real))::numeric, 2) AS height,
            bo.owner,
            COALESCE(is2.skewed_parallel_facade,
                CASE
                    WHEN is2.skewed_parallel::numeric < 75::numeric THEN 'very_big'::report.rotation_type
                    WHEN is2.skewed_parallel::numeric >= 75::numeric AND is2.skewed_parallel::numeric < 100::numeric THEN 'big'::report.rotation_type
                    WHEN is2.skewed_parallel::numeric >= 100::numeric AND is2.skewed_parallel::numeric < 200::numeric THEN 'mediocre'::report.rotation_type
                    WHEN is2.skewed_parallel::numeric >= 200::numeric AND is2.skewed_parallel::numeric < 300::numeric THEN 'small'::report.rotation_type
                    WHEN is2.skewed_parallel::numeric >= 300::numeric THEN 'nil'::report.rotation_type
                    ELSE NULL::report.rotation_type
                END) AS skewed_parallel_facade,
            COALESCE(is2.skewed_perpendicular_facade,
                CASE
                    WHEN is2.skewed_perpendicular::numeric < 75::numeric THEN 'very_big'::report.rotation_type
                    WHEN is2.skewed_perpendicular::numeric >= 75::numeric AND is2.skewed_perpendicular::numeric < 100::numeric THEN 'big'::report.rotation_type
                    WHEN is2.skewed_perpendicular::numeric >= 100::numeric AND is2.skewed_perpendicular::numeric < 200::numeric THEN 'mediocre'::report.rotation_type
                    WHEN is2.skewed_perpendicular::numeric >= 200::numeric AND is2.skewed_perpendicular::numeric < 300::numeric THEN 'small'::report.rotation_type
                    WHEN is2.skewed_perpendicular::numeric >= 300::numeric THEN 'nil'::report.rotation_type
                    ELSE NULL::report.rotation_type
                END) AS skewed_perpendicular_facade,
            GREATEST(
                COALESCE(is2.crack_facade_front_type,
                    CASE
                        WHEN is2.crack_facade_front_size::integer = 0 THEN 'nil'::report.crack_type
                        WHEN is2.crack_facade_front_size::integer = 1 THEN 'small'::report.crack_type
                        WHEN is2.crack_facade_front_size::integer > 1 AND is2.crack_facade_front_size::integer < 3 THEN 'mediocre'::report.crack_type
                        WHEN is2.crack_facade_front_size::integer >= 3 THEN 'big'::report.crack_type
                        ELSE NULL::report.crack_type
                    END),
                COALESCE(is2.crack_facade_back_type,
                    CASE
                        WHEN is2.crack_facade_back_size::integer = 0 THEN 'nil'::report.crack_type
                        WHEN is2.crack_facade_back_size::integer = 1 THEN 'small'::report.crack_type
                        WHEN is2.crack_facade_back_size::integer > 1 AND is2.crack_facade_back_size::integer < 3 THEN 'mediocre'::report.crack_type
                        WHEN is2.crack_facade_back_size::integer >= 3 THEN 'big'::report.crack_type
                        ELSE NULL::report.crack_type
                    END),
                COALESCE(is2.crack_facade_left_type,
                    CASE
                        WHEN is2.crack_facade_left_size::integer = 0 THEN 'nil'::report.crack_type
                        WHEN is2.crack_facade_left_size::integer = 1 THEN 'small'::report.crack_type
                        WHEN is2.crack_facade_left_size::integer > 1 AND is2.crack_facade_left_size::integer < 3 THEN 'mediocre'::report.crack_type
                        WHEN is2.crack_facade_left_size::integer >= 3 THEN 'big'::report.crack_type
                        ELSE NULL::report.crack_type
                    END),
                COALESCE(is2.crack_facade_right_type,
                    CASE
                        WHEN is2.crack_facade_right_size::integer = 0 THEN 'nil'::report.crack_type
                        WHEN is2.crack_facade_right_size::integer = 1 THEN 'small'::report.crack_type
                        WHEN is2.crack_facade_right_size::integer > 1 AND is2.crack_facade_right_size::integer < 3 THEN 'mediocre'::report.crack_type
                        WHEN is2.crack_facade_right_size::integer >= 3 THEN 'big'::report.crack_type
                        ELSE NULL::report.crack_type
                    END)
            ) AS facade_type,
            CASE
                WHEN is2.settlement_speed < 0.5::double precision THEN 'nil'::report.rotation_type
                WHEN is2.settlement_speed >= 0.5::double precision AND is2.settlement_speed::numeric < 2::numeric THEN 'small'::report.rotation_type
                WHEN is2.settlement_speed >= 2::double precision AND is2.settlement_speed::numeric < 3::numeric THEN 'mediocre'::report.rotation_type
                WHEN is2.settlement_speed >= 3::double precision AND is2.settlement_speed::numeric < 3::numeric THEN 'big'::report.rotation_type
                WHEN is2.settlement_speed >= 4::double precision THEN 'very_big'::report.rotation_type
                ELSE NULL::report.rotation_type
            END AS settlement_speed,
            is2.facade_scan_risk,
            ba.geom
        FROM report.inquiry_sample is2
        JOIN geocoder.building_active ba ON ba.external_id = is2.building
        JOIN data.building_height bh ON bh.building_id = ba.external_id
        LEFT JOIN data.building_ownership bo ON bo.building_id = ba.external_id
        JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
        JOIN geocoder.district d ON d.id = n.district_id
        JOIN geocoder.municipality m ON m.id = d.municipality_id
        WHERE is2.skewed_parallel IS NOT NULL
          AND is2.skewed_perpendicular IS NOT NULL
          AND (is2.crack_facade_front_type IS NOT NULL OR is2.crack_facade_front_size IS NOT NULL
            OR is2.crack_facade_back_type IS NOT NULL OR is2.crack_facade_back_size IS NOT NULL
            OR is2.crack_facade_left_type IS NOT NULL OR is2.crack_facade_left_size IS NOT NULL
            OR is2.crack_facade_right_type IS NOT NULL OR is2.crack_facade_right_size IS NOT NULL)
    ) inputz
    JOIN model_gevelscan mg ON mg.skewed_parallel = inputz.skewed_parallel_facade
        AND mg.skewed_perpendicular = inputz.skewed_perpendicular_facade
        AND mg.facade_type = inputz.facade_type)
    LEFT JOIN risk_table_priority rtp ON rtp.risk = mg.risk
        AND rtp.settlement_speed = inputz.settlement_speed;

-- ============================================================================
-- PHASE 5: Drop and recreate materialized views
-- ============================================================================
-- Order matters: model_risk_dynamic_all depends on building_sample, cluster_sample, supercluster_sample
-- Must drop dependent view first, then matviews, then recreate in order

-- 5a. Drop model_risk_dynamic_all (depends on building_sample, cluster_sample, supercluster_sample)
DROP VIEW IF EXISTS data.model_risk_dynamic_all CASCADE;

-- 5b. Drop matviews (inquiry_sample joins)
DROP MATERIALIZED VIEW IF EXISTS data.building_sample;
DROP MATERIALIZED VIEW IF EXISTS data.cluster_sample;
DROP MATERIALIZED VIEW IF EXISTS data.supercluster_sample;
DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_inquiries;
DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_inquiry_municipality;

-- 5c. Drop matviews (shared inquiry_sample + address joins)
DROP MATERIALIZED VIEW IF EXISTS data.statistics_postal_code_data_collected;
DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_data_collected;

-- 5d. Drop matviews (address_building dependents — already updated view, but need rebuild)
DROP MATERIALIZED VIEW IF EXISTS data.statistics_postal_code_foundation_risk;
DROP MATERIALIZED VIEW IF EXISTS data.statistics_postal_code_foundation_type;

-- 5e. Recreate building_sample
CREATE MATERIALIZED VIEW data.building_sample AS
SELECT building_id,
    (array_agg(foundation_type) FILTER (WHERE foundation_type IS NOT NULL))[1] AS foundation_type,
    (array_agg(enforcement_term) FILTER (WHERE enforcement_term IS NOT NULL))[1] AS enforcement_term,
    (array_agg(damage_cause) FILTER (WHERE damage_cause IS NOT NULL))[1] AS damage_cause,
    (array_agg(overall_quality) FILTER (WHERE overall_quality IS NOT NULL))[1] AS overall_quality,
    (array_agg(recovery_advised) FILTER (WHERE recovery_advised IS NOT NULL))[1] AS recovery_advised,
    (array_agg(date_part('year'::text, built_year::date)) FILTER (WHERE built_year IS NOT NULL))[1] AS built_year,
    (array_agg(groundwater_level_temp) FILTER (WHERE groundwater_level_temp IS NOT NULL))[1] AS groundwater_level,
    (array_agg(wood_level) FILTER (WHERE wood_level IS NOT NULL))[1] AS wood_level,
    (array_agg(foundation_depth) FILTER (WHERE foundation_depth IS NOT NULL))[1] AS foundation_depth,
    (array_agg(type) FILTER (WHERE type IS NOT NULL))[1] AS inquiry_type,
    (array_agg(document_date) FILTER (WHERE document_date IS NOT NULL))[1] AS document_date,
    (array_agg(id) FILTER (WHERE id IS NOT NULL))[1] AS id
FROM ( SELECT b.external_id AS building_id,
            is2.foundation_type, is2.enforcement_term, is2.damage_cause,
            is2.overall_quality, is2.recovery_advised, is2.built_year,
            is2.groundwater_level_temp, is2.wood_level, is2.foundation_depth,
            i.type, i.document_date, i.id
        FROM report.inquiry_sample is2
        JOIN report.inquiry i ON is2.inquiry = i.id
        JOIN geocoder.building b ON b.external_id = is2.building
        WHERE i.document_date >= (b.built_year::date - '5 years'::interval)
        ORDER BY is2.building,
            CASE
                WHEN i.type = 'foundation_research'::report.inquiry_type THEN 0
                WHEN i.type = 'inspectionpit'::report.inquiry_type THEN 1
                WHEN i.type = 'second_opinion'::report.inquiry_type THEN 2
                WHEN i.type = 'note'::report.inquiry_type THEN 3
                WHEN i.type = 'additional_research'::report.inquiry_type THEN 4
                WHEN i.type = 'demolition_research'::report.inquiry_type THEN 5
                WHEN i.type = 'architectural_research'::report.inquiry_type THEN 6
                WHEN i.type = 'archieve_research'::report.inquiry_type THEN 7
                WHEN i.type = 'quickscan'::report.inquiry_type THEN 8
                ELSE 100
            END, i.document_date DESC
    ) q
GROUP BY building_id;

-- 5f. Recreate cluster_sample
CREATE MATERIALIZED VIEW data.cluster_sample AS
SELECT cluster_id,
    (array_agg(foundation_type) FILTER (WHERE foundation_type IS NOT NULL))[1] AS foundation_type,
    (array_agg(enforcement_term) FILTER (WHERE enforcement_term IS NOT NULL))[1] AS enforcement_term,
    (array_agg(damage_cause) FILTER (WHERE damage_cause IS NOT NULL))[1] AS damage_cause,
    (array_agg(overall_quality) FILTER (WHERE overall_quality IS NOT NULL))[1] AS overall_quality,
    (array_agg(recovery_advised) FILTER (WHERE recovery_advised IS NOT NULL))[1] AS recovery_advised,
    (array_agg(date_part('year'::text, built_year::date)) FILTER (WHERE built_year IS NOT NULL))[1] AS built_year,
    (array_agg(groundwater_level_temp) FILTER (WHERE groundwater_level_temp IS NOT NULL))[1] AS groundwater_level,
    (array_agg(wood_level) FILTER (WHERE wood_level IS NOT NULL))[1] AS wood_level,
    (array_agg(foundation_depth) FILTER (WHERE foundation_depth IS NOT NULL))[1] AS foundation_depth,
    (array_agg(type) FILTER (WHERE type IS NOT NULL))[1] AS inquiry_type,
    (array_agg(document_date) FILTER (WHERE document_date IS NOT NULL))[1] AS document_date,
    (array_agg(id) FILTER (WHERE id IS NOT NULL))[1] AS id
FROM ( SELECT bc.cluster_id,
            is2.foundation_type, is2.enforcement_term, is2.damage_cause,
            is2.overall_quality, is2.recovery_advised, is2.built_year,
            is2.groundwater_level_temp, is2.wood_level, is2.foundation_depth,
            i.type, i.document_date, i.id
        FROM data.building_cluster bc
        JOIN geocoder.building b ON b.external_id = bc.building_id
        JOIN report.inquiry_sample is2 ON is2.building = b.external_id
        JOIN report.inquiry i ON is2.inquiry = i.id
        WHERE i.document_date >= (b.built_year::date - '5 years'::interval)
        ORDER BY bc.cluster_id,
            CASE
                WHEN i.type = 'foundation_research'::report.inquiry_type THEN 0
                WHEN i.type = 'inspectionpit'::report.inquiry_type THEN 1
                WHEN i.type = 'second_opinion'::report.inquiry_type THEN 2
                WHEN i.type = 'note'::report.inquiry_type THEN 3
                WHEN i.type = 'additional_research'::report.inquiry_type THEN 4
                WHEN i.type = 'demolition_research'::report.inquiry_type THEN 5
                WHEN i.type = 'architectural_research'::report.inquiry_type THEN 6
                WHEN i.type = 'archieve_research'::report.inquiry_type THEN 7
                WHEN i.type = 'quickscan'::report.inquiry_type THEN 8
                ELSE 100
            END, i.document_date DESC
    ) q
GROUP BY cluster_id;

-- 5g. Recreate supercluster_sample
CREATE MATERIALIZED VIEW data.supercluster_sample AS
SELECT supercluster_id,
    (array_agg(foundation_type) FILTER (WHERE foundation_type IS NOT NULL))[1] AS foundation_type,
    (array_agg(enforcement_term) FILTER (WHERE enforcement_term IS NOT NULL))[1] AS enforcement_term,
    (array_agg(damage_cause) FILTER (WHERE damage_cause IS NOT NULL))[1] AS damage_cause,
    (array_agg(overall_quality) FILTER (WHERE overall_quality IS NOT NULL))[1] AS overall_quality,
    (array_agg(recovery_advised) FILTER (WHERE recovery_advised IS NOT NULL))[1] AS recovery_advised,
    (array_agg(date_part('year'::text, built_year::date)) FILTER (WHERE built_year IS NOT NULL))[1] AS built_year,
    (array_agg(groundwater_level_temp) FILTER (WHERE groundwater_level_temp IS NOT NULL))[1] AS groundwater_level,
    (array_agg(wood_level) FILTER (WHERE wood_level IS NOT NULL))[1] AS wood_level,
    (array_agg(foundation_depth) FILTER (WHERE foundation_depth IS NOT NULL))[1] AS foundation_depth,
    (array_agg(type) FILTER (WHERE type IS NOT NULL))[1] AS inquiry_type,
    (array_agg(document_date) FILTER (WHERE document_date IS NOT NULL))[1] AS document_date,
    (array_agg(id) FILTER (WHERE id IS NOT NULL))[1] AS id
FROM ( SELECT s.supercluster_id,
            is2.foundation_type, is2.enforcement_term, is2.damage_cause,
            is2.overall_quality, is2.recovery_advised, is2.built_year,
            is2.groundwater_level_temp, is2.wood_level, is2.foundation_depth,
            i.type, i.document_date, i.id
        FROM data.supercluster s
        JOIN data.building_cluster bc ON bc.cluster_id = s.cluster_id
        JOIN geocoder.building b ON b.external_id = bc.building_id
        JOIN report.inquiry_sample is2 ON is2.building = b.external_id
        JOIN report.inquiry i ON is2.inquiry = i.id
        WHERE i.document_date >= (b.built_year::date - '5 years'::interval)
        ORDER BY s.supercluster_id,
            CASE
                WHEN i.type = 'foundation_research'::report.inquiry_type THEN 0
                WHEN i.type = 'inspectionpit'::report.inquiry_type THEN 1
                WHEN i.type = 'second_opinion'::report.inquiry_type THEN 2
                WHEN i.type = 'note'::report.inquiry_type THEN 3
                WHEN i.type = 'additional_research'::report.inquiry_type THEN 4
                WHEN i.type = 'demolition_research'::report.inquiry_type THEN 5
                WHEN i.type = 'architectural_research'::report.inquiry_type THEN 6
                WHEN i.type = 'archieve_research'::report.inquiry_type THEN 7
                WHEN i.type = 'quickscan'::report.inquiry_type THEN 8
                ELSE 100
            END, i.document_date DESC
    ) q
GROUP BY supercluster_id;

-- 5h. Recreate statistics_product_inquiries
CREATE MATERIALIZED VIEW data.statistics_product_inquiries AS
SELECT ba.neighborhood_id,
    year.year,
    count(i.id) AS count
FROM report.inquiry i
JOIN report.inquiry_sample is2 ON is2.inquiry = i.id
JOIN geocoder.building_active ba ON ba.external_id = is2.building,
    LATERAL CAST((date_part('year'::text, i.document_date))::integer AS integer) year(year)
GROUP BY ba.neighborhood_id, year.year;

-- 5i. Recreate statistics_product_inquiry_municipality
CREATE MATERIALIZED VIEW data.statistics_product_inquiry_municipality AS
SELECT m.id AS municipality_id,
    year.year,
    count(is2.id) AS count
FROM report.inquiry_sample is2
JOIN geocoder.building_active ba ON ba.external_id = is2.building
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id,
    LATERAL CAST((date_part('year'::text, is2.create_date))::integer AS integer) year(year)
GROUP BY m.id, year.year;

-- 5j. Recreate statistics_postal_code_data_collected (shared: inquiry_sample + address)
CREATE MATERIALIZED VIEW data.statistics_postal_code_data_collected AS
SELECT a.postal_code,
    ((count(a.id) FILTER (WHERE i.id IS NOT NULL))::double precision
        / (count(a.id))::double precision * 100::double precision) AS percentage
FROM geocoder.address a
LEFT JOIN report.inquiry_sample i ON i.building = a.building_id
GROUP BY a.postal_code;

-- 5k. Recreate statistics_product_data_collected (shared: inquiry_sample + address)
CREATE MATERIALIZED VIEW data.statistics_product_data_collected AS
SELECT ba.neighborhood_id,
    ((count(a.id) FILTER (WHERE i.id IS NOT NULL))::double precision
        / (count(a.id))::double precision * 100::double precision) AS percentage
FROM geocoder.address a
JOIN geocoder.building_active ba ON a.building_id = ba.external_id
LEFT JOIN report.inquiry_sample i ON i.building = a.building_id
GROUP BY ba.neighborhood_id;

-- 5l. Recreate statistics_postal_code_foundation_risk (uses address_building view)
CREATE MATERIALIZED VIEW data.statistics_postal_code_foundation_risk AS
SELECT postal_code,
    risk AS foundation_risk,
    ((count(risk)::numeric / sum(count(risk)) OVER (PARTITION BY postal_code)) * 100::numeric) AS percentage
FROM ( SELECT a.postal_code,
            ( SELECT unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]) AS risk
                ORDER BY unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk])
                LIMIT 1) AS risk
        FROM data.model_risk_static mrs
        JOIN geocoder.address_building ab ON ab.building_id::text = mrs.building_id::text
        JOIN geocoder.address a ON a.id::text = ab.address_id::text
    ) acr
WHERE risk IS NOT NULL
GROUP BY postal_code, risk;

-- 5m. Recreate statistics_postal_code_foundation_type (uses address_building view)
CREATE MATERIALIZED VIEW data.statistics_postal_code_foundation_type AS
SELECT a.postal_code,
    mrs.foundation_type,
    ((count(mrs.foundation_type)::numeric / sum(count(mrs.foundation_type)) OVER (PARTITION BY a.postal_code)) * 100::numeric) AS percentage
FROM data.model_risk_static mrs
JOIN geocoder.address_building ab ON ab.building_id::text = mrs.building_id::text
JOIN geocoder.address a ON a.id::text = ab.address_id::text
GROUP BY a.postal_code, mrs.foundation_type;

-- 5n. Recreate model_risk_dynamic_all view (depends on building_sample, cluster_sample, supercluster_sample)
--     Generated from DB with surgical replacement: a_1.building_id = ba.external_id (was ba.id)
\i /tmp/model_risk_dynamic_all_new.sql

-- ============================================================================
-- PHASE 6: Recreate unique indexes on matviews
-- ============================================================================

CREATE UNIQUE INDEX building_sample_building_id_idx ON data.building_sample (building_id);
CREATE UNIQUE INDEX cluster_sample_cluster_id_idx ON data.cluster_sample (cluster_id);
CREATE UNIQUE INDEX supercluster_sample_supercluster_id_idx ON data.supercluster_sample (supercluster_id);
CREATE UNIQUE INDEX statistics_product_inquiries_neighborhood_year_idx ON data.statistics_product_inquiries (neighborhood_id, year);
CREATE UNIQUE INDEX statistics_product_inquiry_municipality_municipality_year_idx ON data.statistics_product_inquiry_municipality (municipality_id, year);
CREATE UNIQUE INDEX statistics_postal_code_data_collected_postal_code_idx ON data.statistics_postal_code_data_collected (postal_code);
CREATE UNIQUE INDEX statistics_product_data_collected_neighborhood_idx ON data.statistics_product_data_collected (neighborhood_id);
CREATE UNIQUE INDEX statistics_postal_code_foundation_risk_postal_code_foundation_r ON data.statistics_postal_code_foundation_risk (postal_code, foundation_risk);
CREATE UNIQUE INDEX statistics_postal_code_foundation_type_postal_code_foundation_r ON data.statistics_postal_code_foundation_type (postal_code, foundation_type);

-- ============================================================================
-- PHASE 7: Re-GRANT SELECT to webapp and webservice roles
-- ============================================================================

GRANT SELECT ON data.statistics_postal_code_data_collected TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_postal_code_foundation_risk TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_postal_code_foundation_type TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_product_data_collected TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_product_inquiries TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT ON data.statistics_product_inquiry_municipality TO fundermaps_webapp, fundermaps_webservice;

-- ============================================================================
-- PHASE 8: Verify
-- ============================================================================

DO $$
DECLARE
    gfm_is integer;
    gfm_addr integer;
BEGIN
    SELECT count(*) INTO gfm_is FROM report.inquiry_sample WHERE building LIKE 'gfm-%';
    SELECT count(*) INTO gfm_addr FROM geocoder.address WHERE building_id LIKE 'gfm-%';

    IF gfm_is > 0 THEN
        RAISE EXCEPTION 'Migration failed: % inquiry_sample rows still have GFM IDs', gfm_is;
    END IF;
    IF gfm_addr > 0 THEN
        RAISE EXCEPTION 'Migration failed: % address rows still have GFM IDs', gfm_addr;
    END IF;

    RAISE NOTICE 'Migration verified: 0 GFM IDs remaining in inquiry_sample and address';
END $$;

COMMIT;
