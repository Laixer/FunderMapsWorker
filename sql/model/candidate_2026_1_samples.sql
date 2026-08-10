-- model-2026.1 candidate: believe better observations.
--
-- Named with a version suffix in `data`, matching model_risk_static_2024_1.
--
-- A schema per candidate reads nicer, but CREATE SCHEMA needs superuser and the
-- `fundermaps` role does not have it. A framework where building a candidate
-- requires doadmin defeats its own purpose, so suffixes win on the grounds that
-- anyone who can build the model can build a candidate. Prediction logic is NOT
-- touched -- every helper function is still data.*. The only change is WHICH
-- inquiry row the model believes for a building.
--
-- Four fixes, each with the evidence that motivated it:
--
--   1. delete_date IS NULL
--      The live matview does not filter soft-deleted samples, so a deleted row
--      can win the DISTINCT ON. 101 samples are soft-deleted.
--
--   2. document_date <= CURRENT_DATE
--      Six inquiries carry future dates, one reading 19229-05-27. Because the
--      tie-break is document_date DESC, a typo'd year always beats every
--      legitimate report. Ten buildings currently have their foundation decided
--      by one.
--
--   3. 'note' demoted from priority 3 to 9
--      Measured against other inquiry types on the same building, 'note'
--      disagrees 32.8% of the time -- the worst of any type -- yet outranks
--      archive_research (14.8%) and quickscan (11.5%). It now sorts last of the
--      named types.
--
--   4. Completeness before recency, within the same year
--      The same survey legitimately arrives twice (the bureau delivers it and
--      the receiving corporation delivers it -- two data streams). The tie-break
--      is document_date DESC, so which copy the model believes is decided by
--      whichever typist entered a later date: across 11,346 duplicate
--      deliveries it takes the POORER record 3,025 times. Ordering by year
--      first, then by how many fields are filled, makes the fuller copy win
--      while a genuinely newer survey still beats an older one.
--
--   psql "$DB_URL" -f sql/model/candidate_2026_1_samples.sql

BEGIN;

CREATE MATERIALIZED VIEW data.building_sample_2026_1 AS
WITH ranked AS (
    SELECT DISTINCT ON (b.external_id)
        b.external_id AS building_id,
        is2.foundation_type,
        is2.enforcement_term,
        is2.damage_cause,
        is2.overall_quality,
        is2.recovery_advised,
        date_part('year', is2.built_year::date)::integer AS built_year,
        is2.groundwater_level_temp AS groundwater_level,
        is2.wood_level,
        is2.foundation_depth,
        i.type AS inquiry_type,
        i.document_date,
        i.id
    FROM report.inquiry_sample is2
    JOIN report.inquiry i ON is2.inquiry_id = i.id
    JOIN geocoder.building b ON b.external_id = is2.building_id::text
    WHERE i.document_date >= (b.built_year::date - '5 years'::interval)
      AND is2.delete_date IS NULL                      -- fix 1
      AND i.document_date <= CURRENT_DATE              -- fix 2
    ORDER BY b.external_id,
        (CASE i.type
            WHEN 'foundation_research'::report.inquiry_type    THEN 0
            WHEN 'inspectionpit'::report.inquiry_type          THEN 1
            WHEN 'second_opinion'::report.inquiry_type         THEN 2
            WHEN 'additional_research'::report.inquiry_type    THEN 3
            WHEN 'demolition_research'::report.inquiry_type    THEN 4
            WHEN 'architectural_research'::report.inquiry_type THEN 5
            WHEN 'archive_research'::report.inquiry_type       THEN 6
            WHEN 'quickscan'::report.inquiry_type              THEN 7
            WHEN 'note'::report.inquiry_type                   THEN 9   -- fix 3
            ELSE 100
        END),
        date_part('year', i.document_date) DESC,       -- fix 4: year first…
        ( (is2.foundation_type   IS NOT NULL)::int     -- …then completeness
        + (is2.enforcement_term  IS NOT NULL)::int
        + (is2.damage_cause      IS NOT NULL)::int
        + (is2.overall_quality   IS NOT NULL)::int
        + (is2.recovery_advised  IS NOT NULL)::int
        + (is2.built_year        IS NOT NULL)::int
        + (is2.groundwater_level_temp IS NOT NULL)::int
        + (is2.wood_level        IS NOT NULL)::int
        + (is2.foundation_depth  IS NOT NULL)::int ) DESC,
        i.document_date DESC,                          -- …then exact recency
        i.id DESC                                      -- deterministic
), facade AS (
    SELECT DISTINCT ON (is2.building_id::text)
        is2.building_id::text AS building_id,
        is2.facade_scan_risk
    FROM report.inquiry_sample is2
    JOIN report.inquiry i ON i.id = is2.inquiry_id
    WHERE is2.facade_scan_risk IS NOT NULL
      AND is2.delete_date IS NULL
      AND i.document_date <= CURRENT_DATE
    ORDER BY (is2.building_id::text), i.document_date DESC
)
SELECT r.building_id, r.foundation_type, r.enforcement_term, r.damage_cause,
       r.overall_quality, r.recovery_advised, r.built_year, r.groundwater_level,
       r.wood_level, r.foundation_depth, f.facade_scan_risk, r.inquiry_type,
       r.document_date, r.id
FROM ranked r
LEFT JOIN facade f ON f.building_id = r.building_id
WITH NO DATA;

CREATE UNIQUE INDEX building_sample_2026_1_pkey
    ON data.building_sample_2026_1 (building_id);

COMMENT ON MATERIALIZED VIEW data.building_sample_2026_1 IS
    'Candidate model 2026.1 -- observation selection only. Served to nobody. Drop with one DROP MATERIALIZED VIEW.';

COMMIT;
