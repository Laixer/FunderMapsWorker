-- Evaluation benchmark v2: clean truth, with provenance recorded.
--
-- v1 drew 33.4% of its answers from `quickscan` inquiries. Per Don
-- (2026-08-12), the foundation type in a QuickScan PDF is almost always
-- FunderMaps' own data read back to us -- which is why it is no longer entered.
-- ~126,000 historical quickscan samples predate that policy, so a third of v1
-- was the model being scored against itself. Measured distortion was modest
-- (67.5% accuracy on real evidence vs 68.1% overall) but it is exactly the
-- circularity that made validation/risk_model_reference.csv worthless, and it
-- must not sit inside the benchmark.
--
-- Two changes from v1:
--
--   1. `quickscan` is excluded from truth entirely. Not graded, not weighted --
--      excluded, because it is not an observation.
--
--   2. The answer is picked by BEST EVIDENCE, then recency -- not recency
--      alone. A building with both a dig and a note now yields the dig.
--      v1 would have taken whichever was typed later.
--
-- Grades, from Don's account of what each type actually carries:
--
--   physical    someone dug or opened the foundation
--   documented  a drawing exists (archive_research is always drawing-backed
--               and AI/human verified)
--   opinion     a professional's assertion with no evidence behind it (`note`)
--
-- Recording the grade rather than hard-filtering to one lets a score say which
-- evidence it rests on, and stops the next person silently mixing them.
--
--   psql "$DB_URL" -f sql/migrate/create_model_evaluation_sample_v2.sql

BEGIN;

ALTER TABLE data.model_evaluation_sample
    ADD COLUMN IF NOT EXISTS truth_source   text,
    ADD COLUMN IF NOT EXISTS evidence_grade text;

COMMENT ON COLUMN data.model_evaluation_sample.evidence_grade IS
    'physical (dug) > documented (drawing) > opinion (assertion). quickscan is never present: its foundation type is our own output.';

-- ---------------------------------------------------------------------------
-- v2 truth
-- ---------------------------------------------------------------------------
INSERT INTO data.model_evaluation_sample
    (sample_version, purpose, building_id, stratum, observed_family, split,
     truth_source, evidence_grade)
WITH graded AS (
    SELECT s.building_id, s.foundation_type, s.id AS sample_id,
           i.type::text AS src_type, i.document_date,
           CASE i.type::text
             WHEN 'foundation_research' THEN 'physical'
             WHEN 'inspectionpit'       THEN 'physical'
             WHEN 'second_opinion'      THEN 'physical'
             WHEN 'archive_research'    THEN 'documented'
             WHEN 'demolition_research' THEN 'documented'
             WHEN 'architectural_research' THEN 'documented'
             WHEN 'additional_research' THEN 'documented'
             WHEN 'ground_water_level_research' THEN 'documented'
             ELSE 'opinion'
           END AS grade
    FROM report.inquiry_sample s
    JOIN report.inquiry i ON i.id = s.inquiry_id
    WHERE s.foundation_type IS NOT NULL
      AND s.delete_date IS NULL
      AND i.document_date <= CURRENT_DATE          -- six inquiries are future-dated
      AND i.type <> 'quickscan'                    -- circular: our own output
),
conflicted AS (
    -- a building that disagrees with itself is a data-quality ticket, not truth
    SELECT building_id FROM graded
    GROUP BY building_id HAVING count(DISTINCT foundation_type) > 1
),
best AS (
    SELECT DISTINCT ON (g.building_id) g.*
    FROM graded g
    WHERE g.building_id NOT IN (SELECT building_id FROM conflicted)
    ORDER BY g.building_id,
             CASE g.grade WHEN 'physical' THEN 0 WHEN 'documented' THEN 1 ELSE 2 END,
             g.document_date DESC NULLS LAST, g.sample_id DESC
)
SELECT 2, 'truth', b.building_id,
       (CASE WHEN bp.construction_year_bag < 1940 THEN 'pre1940'
             WHEN bp.construction_year_bag < 1970 THEN '1940-69'
             ELSE '1970+' END)
       || '/' ||
       (CASE WHEN gr.code IN ('hz','ni-hz','ni-du') THEN 'sandy'
             WHEN gr.code IS NULL THEN 'unknown' ELSE 'soft' END),
       CASE WHEN data.is_wood_family(b.foundation_type) THEN 'wood'
            WHEN data.is_no_pile_family(b.foundation_type) THEN 'no_pile'
            ELSE b.foundation_type::text END,
       -- same deterministic split as v1, so a building never changes sides
       CASE WHEN (abs(hashtext(b.building_id)) % 10) < 7 THEN 'train' ELSE 'test' END,
       b.src_type, b.grade
FROM best b
JOIN data.building_precomputed bp ON bp.building_id = b.building_id
LEFT JOIN data.building_geographic_region gr ON gr.building_id = b.building_id;

-- ---------------------------------------------------------------------------
-- v2 population: identical membership to v1, so national figures stay
-- comparable across versions.
-- ---------------------------------------------------------------------------
INSERT INTO data.model_evaluation_sample
    (sample_version, purpose, building_id, stratum, observed_family, split)
SELECT 2, 'population', building_id, stratum, NULL, NULL
FROM data.model_evaluation_sample
WHERE sample_version = 1 AND purpose = 'population';

INSERT INTO data.model_evaluation_stratum_weight (sample_version, stratum, national_buildings, sampled)
SELECT 2, stratum, national_buildings, sampled
FROM data.model_evaluation_stratum_weight WHERE sample_version = 1;

COMMIT;
