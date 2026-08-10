-- The fixed benchmark a candidate model is scored against.
--
-- Step 3 of docs/model-versioning.md. Two jobs, one table:
--
--   purpose='truth'      the buildings a surveyor actually inspected, with the
--                        answer frozen at creation. Accuracy, wood recall,
--                        calibration -- everything in sql/validate/.
--   purpose='population' a stratified national sample standing in for the
--                        whole country, so a candidate that quietly
--                        reclassifies two million buildings cannot arrive
--                        unnoticed. No truth attached; it answers "what does
--                        this model say about the nation", not "is it right".
--
-- WHY THIS IS A TABLE AND NOT A VIEW, which is the whole point:
--
-- The truth set grows every day as inquiries land. A view over
-- report.inquiry_sample would mean a candidate scored on Tuesday and one scored
-- on Friday were measured against different benchmarks, and the difference
-- between them would be partly the data rather than the model. A held-out
-- benchmark has to hold still. This is frozen at creation and only replaced
-- deliberately, with the replacement recorded as a new sample_version.
--
-- Sampling is deterministic (hashtext of the building id), so the same
-- buildings are chosen on any rebuild and the train/test split never moves.
--
-- Excluded from truth: soft-deleted samples, and the ~12,645 buildings whose
-- own inspections assert different foundation types. A building that disagrees
-- with itself is a data-quality ticket, not ground truth.
--
--   psql "$DB_URL" -f sql/migrate/create_model_evaluation_sample.sql

BEGIN;

CREATE TABLE data.model_evaluation_sample (
    purpose         text NOT NULL,
    building_id     text NOT NULL,
    -- era x soil, the axes the classifier actually branches on
    stratum         text NOT NULL,
    -- Family, frozen at creation. NULL for population rows.
    observed_family text,
    -- Deterministic 70/30. NULL for population rows.
    split           text,
    -- Bump when the benchmark is deliberately regenerated, so a score always
    -- says which benchmark produced it.
    sample_version  integer NOT NULL DEFAULT 1,
    created_at      timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT model_evaluation_sample_pkey PRIMARY KEY (sample_version, purpose, building_id),
    CONSTRAINT model_evaluation_sample_purpose CHECK (purpose IN ('truth','population')),
    CONSTRAINT model_evaluation_sample_split CHECK (split IS NULL OR split IN ('train','test')),
    -- truth rows carry an answer and a split; population rows carry neither
    CONSTRAINT model_evaluation_sample_shape CHECK (
        (purpose = 'truth'      AND observed_family IS NOT NULL AND split IS NOT NULL) OR
        (purpose = 'population' AND observed_family IS NULL     AND split IS NULL)
    )
);

COMMENT ON TABLE data.model_evaluation_sample IS
    'Frozen benchmark for scoring candidate models. Deliberately a table, not a view: a growing truth set would make two candidates scored on different days incomparable. See docs/model-versioning.md.';

CREATE INDEX model_evaluation_sample_building_idx
    ON data.model_evaluation_sample (building_id);

-- ---------------------------------------------------------------------------
-- Truth: one row per building someone inspected, answer frozen.
-- ---------------------------------------------------------------------------
INSERT INTO data.model_evaluation_sample (purpose, building_id, stratum, observed_family, split)
WITH conflicted AS (
    SELECT building_id
    FROM   report.inquiry_sample
    WHERE  foundation_type IS NOT NULL AND delete_date IS NULL
    GROUP  BY building_id
    HAVING count(DISTINCT foundation_type) > 1
),
truth AS (
    SELECT DISTINCT ON (s.building_id)
           s.building_id, s.foundation_type
    FROM   report.inquiry_sample s
    JOIN   report.inquiry i ON i.id = s.inquiry_id
    WHERE  s.foundation_type IS NOT NULL
      AND  s.delete_date IS NULL
      AND  s.building_id NOT IN (SELECT building_id FROM conflicted)
    ORDER  BY s.building_id, i.document_date DESC NULLS LAST, s.id DESC
)
SELECT 'truth',
       t.building_id,
       (CASE WHEN bp.construction_year_bag < 1940 THEN 'pre1940'
             WHEN bp.construction_year_bag < 1970 THEN '1940-69'
             ELSE '1970+' END)
       || '/' ||
       (CASE WHEN gr.code IN ('hz','ni-hz','ni-du') THEN 'sandy'
             WHEN gr.code IS NULL THEN 'unknown' ELSE 'soft' END),
       CASE WHEN data.is_wood_family(t.foundation_type) THEN 'wood'
            WHEN data.is_no_pile_family(t.foundation_type) THEN 'no_pile'
            ELSE t.foundation_type::text END,
       CASE WHEN (abs(hashtext(t.building_id)) % 10) < 7 THEN 'train' ELSE 'test' END
FROM truth t
JOIN data.building_precomputed bp ON bp.building_id = t.building_id
LEFT JOIN data.building_geographic_region gr ON gr.building_id = t.building_id;

-- ---------------------------------------------------------------------------
-- Population: proportional across the nine strata, with a floor so the two
-- tiny 'unknown soil' strata are not lost. ~100k buildings, deterministic.
-- ---------------------------------------------------------------------------
INSERT INTO data.model_evaluation_sample (purpose, building_id, stratum)
SELECT 'population', building_id, stratum
FROM (
    SELECT bp.building_id,
           (CASE WHEN bp.construction_year_bag < 1940 THEN 'pre1940'
                 WHEN bp.construction_year_bag < 1970 THEN '1940-69'
                 ELSE '1970+' END)
           || '/' ||
           (CASE WHEN gr.code IN ('hz','ni-hz','ni-du') THEN 'sandy'
                 WHEN gr.code IS NULL THEN 'unknown' ELSE 'soft' END) AS stratum,
           row_number() OVER (
               PARTITION BY (CASE WHEN bp.construction_year_bag < 1940 THEN 'pre1940'
                                  WHEN bp.construction_year_bag < 1970 THEN '1940-69'
                                  ELSE '1970+' END)
                         || '/' ||
                            (CASE WHEN gr.code IN ('hz','ni-hz','ni-du') THEN 'sandy'
                                  WHEN gr.code IS NULL THEN 'unknown' ELSE 'soft' END)
               ORDER BY hashtext(bp.building_id)
           ) AS rn,
           count(*) OVER (
               PARTITION BY (CASE WHEN bp.construction_year_bag < 1940 THEN 'pre1940'
                                  WHEN bp.construction_year_bag < 1970 THEN '1940-69'
                                  ELSE '1970+' END)
                         || '/' ||
                            (CASE WHEN gr.code IN ('hz','ni-hz','ni-du') THEN 'sandy'
                                  WHEN gr.code IS NULL THEN 'unknown' ELSE 'soft' END)
           ) AS n_stratum
    FROM data.building_precomputed bp
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = bp.building_id
) x
WHERE rn <= greatest(2000, round(100000.0 * n_stratum / 11241188.0));

GRANT SELECT ON data.model_evaluation_sample TO fundermaps_windmill;

COMMIT;
