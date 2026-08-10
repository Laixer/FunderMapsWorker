-- Frozen stratum weights for the evaluation sample.
--
-- The population sample is proportional EXCEPT for a floor of 2,000 rows per
-- stratum, which stops the two tiny 'unknown soil' strata from vanishing. That
-- floor makes the raw sample non-representative: 'unknown' strata are ~1.9% of
-- the sample against ~0.2% of the country.
--
-- So any national figure computed from purpose='population' -- national wood
-- share being the obvious one -- MUST be weighted by these numbers, not
-- averaged raw. Averaging raw over-weights the unknown-soil strata by roughly
-- tenfold and will quietly produce a wrong national estimate.
--
-- Frozen at creation for the same reason as the sample itself: a weight that
-- moves makes two candidates scored on different days incomparable.
--
--   SELECT sum(w.national_buildings * s.wood_rate) / sum(w.national_buildings)
--   FROM  (…per-stratum candidate wood rate…) s
--   JOIN  data.model_evaluation_stratum_weight w USING (stratum)
--   WHERE w.sample_version = 1;
--
--   psql "$DB_URL" -f sql/migrate/create_model_evaluation_stratum_weights.sql

BEGIN;

CREATE TABLE data.model_evaluation_stratum_weight (
    sample_version     integer NOT NULL,
    stratum            text NOT NULL,
    national_buildings bigint NOT NULL,
    sampled            bigint NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT model_evaluation_stratum_weight_pkey PRIMARY KEY (sample_version, stratum)
);

COMMENT ON TABLE data.model_evaluation_stratum_weight IS
    'True national size of each evaluation stratum. The population sample is floored at 2,000 per stratum and is therefore NOT proportional -- weight by national_buildings before quoting any national figure.';

INSERT INTO data.model_evaluation_stratum_weight (sample_version, stratum, national_buildings, sampled)
SELECT 1, x.stratum, x.national,
       COALESCE((SELECT count(*) FROM data.model_evaluation_sample s
                 WHERE s.purpose = 'population' AND s.sample_version = 1
                   AND s.stratum = x.stratum), 0)
FROM (
    SELECT (CASE WHEN bp.construction_year_bag < 1940 THEN 'pre1940'
                 WHEN bp.construction_year_bag < 1970 THEN '1940-69'
                 ELSE '1970+' END)
           || '/' ||
           (CASE WHEN gr.code IN ('hz','ni-hz','ni-du') THEN 'sandy'
                 WHEN gr.code IS NULL THEN 'unknown' ELSE 'soft' END) AS stratum,
           count(*) AS national
    FROM data.building_precomputed bp
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = bp.building_id
    GROUP BY 1
) x;

GRANT SELECT ON data.model_evaluation_stratum_weight TO fundermaps_windmill;

COMMIT;
