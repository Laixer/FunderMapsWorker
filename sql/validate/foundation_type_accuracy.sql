-- Foundation-type accuracy harness (v1)
-- Compares data.indicative_foundation_type() -- the guess used where no inquiry
-- exists -- against what a surveyor actually recorded, on buildings where
-- someone physically looked.
--
-- Leakage guard: construction_year_bag ONLY. Production passes
-- COALESCE(established.built_year, bp.construction_year_bag), which would let
-- the tree read the answer off the inquiry it is being scored against.

\set truth_status :truth_status

DROP TABLE IF EXISTS _acc;
CREATE TEMP TABLE _acc AS
WITH conflicted AS (
    SELECT building_id
    FROM   report.inquiry_sample
    WHERE  foundation_type IS NOT NULL
    GROUP  BY building_id
    HAVING count(DISTINCT foundation_type) > 1
),
truth AS (
    SELECT DISTINCT ON (s.building_id)
           s.building_id,
           s.foundation_type AS observed
    FROM   report.inquiry_sample s
    JOIN   report.inquiry i ON i.id = s.inquiry_id
    WHERE  s.foundation_type IS NOT NULL
      AND  s.delete_date IS NULL
      AND  (:'truth_status' = 'ALL' OR i.audit_status::text = :'truth_status')
      AND  s.building_id NOT IN (SELECT building_id FROM conflicted)
    ORDER  BY s.building_id, i.document_date DESC NULLS LAST, s.id DESC
)
SELECT t.building_id,
       t.observed,
       data.indicative_foundation_type(
           bp.construction_year_bag, bp.height, gr.code, bp.address_count
       ) AS predicted,
       bp.construction_year_bag AS year_bag,
       gr.code AS soil
FROM   truth t
JOIN   data.building_precomputed bp ON bp.building_id = t.building_id
LEFT   JOIN data.building_geographic_region gr ON gr.building_id = t.building_id;

-- family folding: the tree can only emit wood / wood_charger / no_pile / concrete,
-- so score the family, not the sub-type.
CREATE OR REPLACE FUNCTION pg_temp.fam(ft report.foundation_type) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN ft IS NULL THEN NULL
    WHEN data.is_wood_family(ft) THEN 'wood'
    WHEN data.is_no_pile_family(ft) THEN 'no_pile'
    WHEN data.is_concrete_family(ft) THEN 'concrete'
    ELSE ft::text
  END $$;

\echo ''
\echo '=== headline ==='
SELECT count(*) AS buildings_scored,
       round(100.0 * count(*) FILTER (WHERE pg_temp.fam(observed) = pg_temp.fam(predicted)) / count(*), 1) AS family_accuracy_pct,
       round(100.0 * count(*) FILTER (WHERE observed = predicted) / count(*), 1) AS exact_accuracy_pct
FROM _acc;

\echo ''
\echo '=== majority-class baseline (guess the most common family every time) ==='
SELECT pg_temp.fam(observed) AS always_guess_this, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM _acc GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== confusion matrix (family) ==='
SELECT pg_temp.fam(observed) AS observed, pg_temp.fam(predicted) AS predicted, count(*)
FROM _acc GROUP BY 1,2 ORDER BY 3 DESC;

\echo ''
\echo '=== per-family recall: of buildings that REALLY are X, how many did we call X? ==='
SELECT pg_temp.fam(observed) AS really_is, count(*) AS n,
       count(*) FILTER (WHERE pg_temp.fam(observed)=pg_temp.fam(predicted)) AS got_right,
       round(100.0 * count(*) FILTER (WHERE pg_temp.fam(observed)=pg_temp.fam(predicted)) / count(*), 1) AS recall_pct
FROM _acc GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== the expensive error: really wood, we said something safe ==='
SELECT pg_temp.fam(predicted) AS we_said, count(*)
FROM _acc WHERE pg_temp.fam(observed)='wood' AND pg_temp.fam(predicted) <> 'wood'
GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== weakest branches: accuracy by era x soil ==='
SELECT CASE WHEN year_bag < 1700 THEN 'pre-1700'
            WHEN year_bag < 1800 THEN '1700-1799'
            WHEN year_bag < 1940 THEN '1800-1939'
            WHEN year_bag < 1965 THEN '1940-1964'
            ELSE '1965+' END AS era,
       CASE WHEN soil IN ('hz','ni-hz','ni-du') THEN 'sandy' WHEN soil IS NULL THEN 'unknown' ELSE 'soft' END AS soil_kind,
       count(*) AS n,
       round(100.0 * count(*) FILTER (WHERE pg_temp.fam(observed)=pg_temp.fam(predicted)) / count(*), 1) AS acc_pct
FROM _acc GROUP BY 1,2 HAVING count(*) >= 25 ORDER BY 4 ASC;
