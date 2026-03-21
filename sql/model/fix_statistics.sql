-- Phase A7: Fix Statistics Matviews & Related Views
--
-- Each fix is an independent CREATE OR REPLACE / DROP + CREATE statement.
-- Run in order. Matviews need DROP + CREATE (can't ALTER definition).

--------------------------------------------------------------------------------
-- Fix 1: statistics_product_buildings_restored
--
-- Bug: DISTINCT ON (neighborhood_id) without ORDER BY.
-- The UNION produces rows with count > 0 (actual) and count = 0 (filler).
-- Without ORDER BY, PostgreSQL may pick the 0-count row over the real count.
--
-- Fix: LEFT JOIN + COALESCE instead of UNION + DISTINCT ON.
--------------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_buildings_restored;

CREATE MATERIALIZED VIEW data.statistics_product_buildings_restored AS
SELECT
    ba.neighborhood_id,
    COALESCE(rs_count.count, 0) AS count
FROM (
    SELECT DISTINCT neighborhood_id
    FROM geocoder.building_active
) ba
LEFT JOIN (
    SELECT ba2.neighborhood_id, count(*) AS count
    FROM report.recovery_sample rs
    JOIN geocoder.building_active ba2 ON ba2.external_id = rs.building_id
    GROUP BY ba2.neighborhood_id
) rs_count ON rs_count.neighborhood_id = ba.neighborhood_id
WITH NO DATA;

CREATE UNIQUE INDEX statistics_product_buildings_restored_neighborhood_idx
    ON data.statistics_product_buildings_restored (neighborhood_id);

-- Restore grants
GRANT SELECT ON data.statistics_product_buildings_restored TO fundermaps_webapp;
GRANT SELECT ON data.statistics_product_buildings_restored TO fundermaps_webservice;

--------------------------------------------------------------------------------
-- Fix 2: statistics_product_incident_municipality
--
-- Bug: Uses geocoder.building (includes inactive) instead of
-- geocoder.building_active. The neighborhood-level equivalent
-- (statistics_product_incidents) uses building_active.
--
-- Fix: Change to building_active for consistency.
--------------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_incident_municipality;

CREATE MATERIALIZED VIEW data.statistics_product_incident_municipality AS
SELECT
    m.id AS municipality_id,
    date_part('year', i.create_date)::integer AS year,
    count(i.id) AS count
FROM report.incident i
JOIN geocoder.building_active ba ON ba.external_id = i.building::text
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id
GROUP BY m.id, date_part('year', i.create_date)::integer
WITH NO DATA;

CREATE UNIQUE INDEX statistics_product_incident_municipality_municipality_year_idx
    ON data.statistics_product_incident_municipality (municipality_id, year);

-- Restore grants (check schema.sql for current grants)
GRANT SELECT ON data.statistics_product_incident_municipality TO fundermaps_webapp;
GRANT SELECT ON data.statistics_product_incident_municipality TO fundermaps_webservice;

--------------------------------------------------------------------------------
-- Fix 3: statistics_product_inquiry_municipality
--
-- Bug: Uses is2.create_date (inquiry_sample creation timestamp) instead of
-- i.document_date (inquiry document date). The neighborhood-level equivalent
-- (statistics_product_inquiries) uses i.document_date.
--
-- Fix: JOIN to inquiry table and use i.document_date.
--------------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_inquiry_municipality;

CREATE MATERIALIZED VIEW data.statistics_product_inquiry_municipality AS
SELECT
    m.id AS municipality_id,
    date_part('year', i.document_date)::integer AS year,
    count(is2.id) AS count
FROM report.inquiry_sample is2
JOIN report.inquiry i ON i.id = is2.inquiry
JOIN geocoder.building_active ba ON ba.external_id = is2.building::text
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id
GROUP BY m.id, date_part('year', i.document_date)::integer
WITH NO DATA;

CREATE UNIQUE INDEX statistics_product_inquiry_municipality_municipality_year_idx
    ON data.statistics_product_inquiry_municipality (municipality_id, year);

-- Restore grants
GRANT SELECT ON data.statistics_product_inquiry_municipality TO fundermaps_webapp;
GRANT SELECT ON data.statistics_product_inquiry_municipality TO fundermaps_webservice;

--------------------------------------------------------------------------------
-- Fix 4: facade_scan settlement_speed dead branch
--
-- Bug: Line 5370 has `>= 3 AND < 3` which is always false.
-- Values in [3,4) get NULL instead of 'big'.
--
-- Fix: Change to `>= 3 AND < 4`.
--
-- Also: DISTINCT ON without ORDER BY — add ORDER BY create_date DESC
-- to deterministically pick the most recent sample per building.
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW maplayer.facade_scan AS
SELECT
    inputz.external_id,
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
FROM (
    SELECT DISTINCT ON (ba.external_id)
        ba.external_id,
        n.external_id AS neighborhood_id,
        d.external_id AS district_id,
        m.external_id AS municipality_id,
        round(GREATEST(bh.height, 0::real)::numeric, 2) AS height,
        bo.owner,
        COALESCE(is2.skewed_parallel_facade,
            CASE
                WHEN is2.skewed_parallel::numeric < 75 THEN 'very_big'::report.rotation_type
                WHEN is2.skewed_parallel::numeric >= 75 AND is2.skewed_parallel::numeric < 100 THEN 'big'::report.rotation_type
                WHEN is2.skewed_parallel::numeric >= 100 AND is2.skewed_parallel::numeric < 200 THEN 'mediocre'::report.rotation_type
                WHEN is2.skewed_parallel::numeric >= 200 AND is2.skewed_parallel::numeric < 300 THEN 'small'::report.rotation_type
                WHEN is2.skewed_parallel::numeric >= 300 THEN 'nil'::report.rotation_type
                ELSE NULL
            END
        ) AS skewed_parallel_facade,
        COALESCE(is2.skewed_perpendicular_facade,
            CASE
                WHEN is2.skewed_perpendicular::numeric < 75 THEN 'very_big'::report.rotation_type
                WHEN is2.skewed_perpendicular::numeric >= 75 AND is2.skewed_perpendicular::numeric < 100 THEN 'big'::report.rotation_type
                WHEN is2.skewed_perpendicular::numeric >= 100 AND is2.skewed_perpendicular::numeric < 200 THEN 'mediocre'::report.rotation_type
                WHEN is2.skewed_perpendicular::numeric >= 200 AND is2.skewed_perpendicular::numeric < 300 THEN 'small'::report.rotation_type
                WHEN is2.skewed_perpendicular::numeric >= 300 THEN 'nil'::report.rotation_type
                ELSE NULL
            END
        ) AS skewed_perpendicular_facade,
        GREATEST(
            COALESCE(is2.crack_facade_front_type,
                CASE
                    WHEN is2.crack_facade_front_size::integer = 0 THEN 'nil'::report.crack_type
                    WHEN is2.crack_facade_front_size::integer = 1 THEN 'small'::report.crack_type
                    WHEN is2.crack_facade_front_size::integer > 1 AND is2.crack_facade_front_size::integer < 3 THEN 'mediocre'::report.crack_type
                    WHEN is2.crack_facade_front_size::integer >= 3 THEN 'big'::report.crack_type
                    ELSE NULL
                END),
            COALESCE(is2.crack_facade_back_type,
                CASE
                    WHEN is2.crack_facade_back_size::integer = 0 THEN 'nil'::report.crack_type
                    WHEN is2.crack_facade_back_size::integer = 1 THEN 'small'::report.crack_type
                    WHEN is2.crack_facade_back_size::integer > 1 AND is2.crack_facade_back_size::integer < 3 THEN 'mediocre'::report.crack_type
                    WHEN is2.crack_facade_back_size::integer >= 3 THEN 'big'::report.crack_type
                    ELSE NULL
                END),
            COALESCE(is2.crack_facade_left_type,
                CASE
                    WHEN is2.crack_facade_left_size::integer = 0 THEN 'nil'::report.crack_type
                    WHEN is2.crack_facade_left_size::integer = 1 THEN 'small'::report.crack_type
                    WHEN is2.crack_facade_left_size::integer > 1 AND is2.crack_facade_left_size::integer < 3 THEN 'mediocre'::report.crack_type
                    WHEN is2.crack_facade_left_size::integer >= 3 THEN 'big'::report.crack_type
                    ELSE NULL
                END),
            COALESCE(is2.crack_facade_right_type,
                CASE
                    WHEN is2.crack_facade_right_size::integer = 0 THEN 'nil'::report.crack_type
                    WHEN is2.crack_facade_right_size::integer = 1 THEN 'small'::report.crack_type
                    WHEN is2.crack_facade_right_size::integer > 1 AND is2.crack_facade_right_size::integer < 3 THEN 'mediocre'::report.crack_type
                    WHEN is2.crack_facade_right_size::integer >= 3 THEN 'big'::report.crack_type
                    ELSE NULL
                END)
        ) AS facade_type,
        -- BUG FIX: line 5370 had >= 3 AND < 3 (always false). Fixed to >= 3 AND < 4.
        CASE
            WHEN is2.settlement_speed < 0.5 THEN 'nil'::report.rotation_type
            WHEN is2.settlement_speed >= 0.5 AND is2.settlement_speed < 2 THEN 'small'::report.rotation_type
            WHEN is2.settlement_speed >= 2 AND is2.settlement_speed < 3 THEN 'mediocre'::report.rotation_type
            WHEN is2.settlement_speed >= 3 AND is2.settlement_speed < 4 THEN 'big'::report.rotation_type
            WHEN is2.settlement_speed >= 4 THEN 'very_big'::report.rotation_type
            ELSE NULL
        END AS settlement_speed,
        is2.facade_scan_risk,
        ba.geom
    FROM report.inquiry_sample is2
    JOIN geocoder.building_active ba ON ba.external_id = is2.building::text
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
    -- BUG FIX: Added ORDER BY for deterministic DISTINCT ON
    ORDER BY ba.external_id, is2.create_date DESC
) inputz
JOIN public.model_gevelscan mg
    ON mg.skewed_parallel = inputz.skewed_parallel_facade
   AND mg.skewed_perpendicular = inputz.skewed_perpendicular_facade
   AND mg.facade_type = inputz.facade_type
LEFT JOIN public.risk_table_priority rtp
    ON rtp.risk = mg.risk
   AND rtp.settlement_speed = inputz.settlement_speed;

--------------------------------------------------------------------------------
-- Fix 5: analysis_monitoring
--
-- Bug: DISTINCT ON without ORDER BY — nondeterministic row selection.
--
-- Fix: Add ORDER BY create_date DESC (or document_date DESC from inquiry).
-- Note: This view queries inquiry_sample directly, not model_risk_static.
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW maplayer.analysis_monitoring AS
SELECT DISTINCT ON (ba.external_id)
    ba.external_id AS building_id,
    round(GREATEST(bh.height, 0::real)::numeric, 2) AS height,
    n.external_id AS neighborhood_id,
    d.external_id AS district_id,
    m.external_id AS municipality_id,
    ba.geom
FROM report.inquiry_sample is2
JOIN report.inquiry i ON i.id = is2.inquiry
JOIN geocoder.building_active ba ON ba.external_id = is2.building::text
JOIN data.building_height bh ON bh.building_id = ba.external_id
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id
WHERE i.type = 'monitoring'
ORDER BY ba.external_id, i.document_date DESC;
