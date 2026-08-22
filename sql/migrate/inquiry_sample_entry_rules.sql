-- Entry rules for report.inquiry_sample, ruled by Yorick 2026-08-22 after the
-- inquiry data audit (~/fundermaps-inquiry-audit on fm-devops):
--
--  1. settlement_speed ("zakkingssnelheid") is ALWAYS entered negative
--     (zakking = -mm/yr). Before this, Ton entered positive and the
--     FunderConsult feed / Don / Aad negative, and both classifiers
--     (maplayer.facade_scan, /v4/product/facade_scan) bucketed `< 0.5 -> nil`,
--     so 1,096 of 1,277 facade-scan settlements were served as "nil".
--     Data: 1,855 positive rows flipped to negative the same day.
--  2. built_year is only filled when the document states it; otherwise it is
--     left NULL and the BAG year applies. Never the document/import date.
--     Data: 11,734 rows set to NULL (import-date stuffing, impossible/future
--     years, report year typed as build year).
--
-- Applied to prod 2026-08-22 together with the data fixes. NOT VALID + VALIDATE
-- keeps the lock short; the data was normalised first so VALIDATE passes.

BEGIN;

ALTER TABLE report.inquiry_sample
    ADD CONSTRAINT inquiry_sample_settlement_speed_nonpositive
    CHECK (settlement_speed IS NULL OR settlement_speed <= 0) NOT VALID;

ALTER TABLE report.inquiry_sample
    ADD CONSTRAINT inquiry_sample_built_year_not_future
    CHECK (built_year IS NULL OR built_year <= CURRENT_DATE) NOT VALID;

ALTER TABLE report.inquiry_sample VALIDATE CONSTRAINT inquiry_sample_settlement_speed_nonpositive;
ALTER TABLE report.inquiry_sample VALIDATE CONSTRAINT inquiry_sample_built_year_not_future;

-- Classifier on the magnitude (sql/model/fix_statistics.sql, Fix 4 block).
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
        -- settlement_speed is entered NEGATIVE (zakking = -mm/yr; CHECK <= 0 since
        -- 2026-08-22). Classify on the magnitude so the sign can never demote a
        -- sinking house to 'nil'.
        CASE
            WHEN abs(is2.settlement_speed) < 0.5 THEN 'nil'::report.rotation_type
            WHEN abs(is2.settlement_speed) >= 0.5 AND abs(is2.settlement_speed) < 2 THEN 'small'::report.rotation_type
            WHEN abs(is2.settlement_speed) >= 2 AND abs(is2.settlement_speed) < 3 THEN 'mediocre'::report.rotation_type
            WHEN abs(is2.settlement_speed) >= 3 AND abs(is2.settlement_speed) < 4 THEN 'big'::report.rotation_type
            WHEN abs(is2.settlement_speed) >= 4 THEN 'very_big'::report.rotation_type
            ELSE NULL
        END AS settlement_speed,
        is2.facade_scan_risk,
        ba.geom
    FROM report.inquiry_sample is2
    JOIN geocoder.building_active ba ON ba.external_id = is2.building_id::text
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
JOIN data.model_gevelscan mg
    ON mg.skewed_parallel = inputz.skewed_parallel_facade
   AND mg.skewed_perpendicular = inputz.skewed_perpendicular_facade
   AND mg.facade_type = inputz.facade_type
LEFT JOIN data.risk_table_priority rtp
    ON rtp.risk = mg.risk
   AND rtp.settlement_speed = inputz.settlement_speed;

COMMIT;
