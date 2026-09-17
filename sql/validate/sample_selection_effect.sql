-- #152 step 1: what do the four observation-selection fixes change?
--
-- Compares the production sample matview (data.building_sample, one winning
-- inquiry per building) with the candidate one (data.building_sample_2026_1,
-- same query plus: soft-deleted rows excluded, future document dates excluded,
-- 'note' demoted below 'quickscan', completeness before recency within a
-- year). Read-only: SELECT plus temp tables. Both matviews must be freshly
-- refreshed, otherwise the diff is partly the refresh gap.
--
-- Scoring is family level (wood / no_pile / concrete) against the frozen
-- benchmark v2 truth (data.model_evaluation_sample, sample_version 2), which
-- picks the answer by evidence grade (physical > documented > opinion) rather
-- than by inquiry-type priority. Agreement here therefore reads: "how often
-- does the selection rule land on the evidence-graded answer". Train and test
-- rows are both used; nothing is fitted.
--
--   psql "$DB_URL" -f sql/validate/sample_selection_effect.sql

CREATE OR REPLACE FUNCTION pg_temp.fam(ft report.foundation_type) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN ft IS NULL THEN NULL
    WHEN data.is_wood_family(ft) THEN 'wood'
    WHEN data.is_no_pile_family(ft) THEN 'no_pile'
    WHEN data.is_concrete_family(ft) THEN 'concrete'
    ELSE 'other'
  END $$;

DROP TABLE IF EXISTS _sel;
CREATE TEMP TABLE _sel AS
SELECT COALESCE(p.building_id, c.building_id) AS building_id,
       p.id            AS prod_inquiry,  c.id            AS cand_inquiry,
       p.inquiry_type  AS prod_type,     c.inquiry_type  AS cand_type,
       p.document_date AS prod_date,     c.document_date AS cand_date,
       pg_temp.fam(p.foundation_type) AS prod_fam,
       pg_temp.fam(c.foundation_type) AS cand_fam,
       p.foundation_type AS prod_ft, c.foundation_type AS cand_ft
FROM data.building_sample p
FULL JOIN data.building_sample_2026_1 c ON c.building_id = p.building_id;

\echo ''
\echo '=== 1. membership: which buildings have a winning sample at all ==='
SELECT count(*) FILTER (WHERE prod_inquiry IS NOT NULL AND cand_inquiry IS NOT NULL) AS in_both,
       count(*) FILTER (WHERE cand_inquiry IS NULL) AS only_prod,
       count(*) FILTER (WHERE prod_inquiry IS NULL) AS only_cand
FROM _sel;

\echo ''
\echo '=== 2. among buildings in both: did the winning inquiry change, did the type change ==='
SELECT count(*) AS in_both,
       count(*) FILTER (WHERE prod_inquiry <> cand_inquiry) AS winner_changed,
       count(*) FILTER (WHERE prod_inquiry <> cand_inquiry AND prod_ft IS DISTINCT FROM cand_ft) AS exact_type_changed,
       count(*) FILTER (WHERE prod_inquiry <> cand_inquiry AND prod_fam IS DISTINCT FROM cand_fam) AS family_changed,
       count(*) FILTER (WHERE prod_inquiry <> cand_inquiry AND prod_fam IS DISTINCT FROM cand_fam AND cand_fam = 'wood') AS became_wood,
       count(*) FILTER (WHERE prod_inquiry <> cand_inquiry AND prod_fam IS DISTINCT FROM cand_fam AND prod_fam = 'wood') AS stopped_being_wood
FROM _sel
WHERE prod_inquiry IS NOT NULL AND cand_inquiry IS NOT NULL;

\echo ''
\echo '=== 3. why the winner changed: first matching fix ==='
WITH changed AS (
  SELECT s.*,
         (SELECT bool_or(ps.delete_date IS NOT NULL) FROM report.inquiry_sample ps
           WHERE ps.inquiry_id = s.prod_inquiry AND ps.building_id::text = s.building_id) AS prod_deleted,
         (SELECT pi.document_date > CURRENT_DATE FROM report.inquiry pi WHERE pi.id = s.prod_inquiry) AS prod_future
  FROM _sel s
  WHERE s.prod_inquiry <> s.cand_inquiry
), reasoned AS (
  SELECT CASE
           WHEN prod_deleted THEN 'fix 1: prod winner was soft-deleted'
           WHEN prod_future THEN 'fix 2: prod winner had a future date'
           WHEN prod_type = 'note' THEN 'fix 3: note demoted'
           WHEN date_part('year', prod_date) = date_part('year', cand_date) THEN 'fix 4: completeness within the same year'
           ELSE 'other (priority order change)'
         END AS reason,
         prod_fam, cand_fam
  FROM changed
)
SELECT reason, count(*) AS buildings,
       count(*) FILTER (WHERE prod_fam IS DISTINCT FROM cand_fam) AS family_changed
FROM reasoned GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== 4. agreement with benchmark v2 truth (family), prod vs candidate ==='
WITH t AS (
  SELECT e.building_id, e.observed_family, e.evidence_grade, s.prod_fam, s.cand_fam
  FROM data.model_evaluation_sample e
  LEFT JOIN _sel s ON s.building_id = e.building_id
  WHERE e.sample_version = 2 AND e.purpose = 'truth'
    AND e.observed_family IN ('wood','no_pile','concrete')
)
SELECT count(*) AS truth_buildings,
       round(100.0 * count(*) FILTER (WHERE prod_fam = observed_family) / count(*), 2) AS prod_agree_pct,
       round(100.0 * count(*) FILTER (WHERE cand_fam = observed_family) / count(*), 2) AS cand_agree_pct,
       count(*) FILTER (WHERE prod_fam IS NULL) AS prod_no_answer,
       count(*) FILTER (WHERE cand_fam IS NULL) AS cand_no_answer,
       round(100.0 * count(*) FILTER (WHERE observed_family = 'wood' AND prod_fam = 'wood') / NULLIF(count(*) FILTER (WHERE observed_family = 'wood'), 0), 2) AS prod_wood_recall_pct,
       round(100.0 * count(*) FILTER (WHERE observed_family = 'wood' AND cand_fam = 'wood') / NULLIF(count(*) FILTER (WHERE observed_family = 'wood'), 0), 2) AS cand_wood_recall_pct
FROM t;

\echo ''
\echo '=== 4b. same, per evidence grade of the truth ==='
WITH t AS (
  SELECT e.building_id, e.observed_family, e.evidence_grade, s.prod_fam, s.cand_fam
  FROM data.model_evaluation_sample e
  JOIN _sel s ON s.building_id = e.building_id
  WHERE e.sample_version = 2 AND e.purpose = 'truth'
    AND e.observed_family IN ('wood','no_pile','concrete')
)
SELECT evidence_grade, count(*) AS n,
       round(100.0 * count(*) FILTER (WHERE prod_fam = observed_family) / count(*), 2) AS prod_agree_pct,
       round(100.0 * count(*) FILTER (WHERE cand_fam = observed_family) / count(*), 2) AS cand_agree_pct
FROM t GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== 5. the buildings where the two rules disagree AND truth exists: who is right ==='
WITH t AS (
  SELECT e.observed_family, s.prod_fam, s.cand_fam
  FROM data.model_evaluation_sample e
  JOIN _sel s ON s.building_id = e.building_id
  WHERE e.sample_version = 2 AND e.purpose = 'truth'
    AND e.observed_family IN ('wood','no_pile','concrete')
    AND s.prod_fam IS DISTINCT FROM s.cand_fam
)
SELECT count(*) AS disagreements,
       count(*) FILTER (WHERE prod_fam = observed_family) AS prod_right,
       count(*) FILTER (WHERE cand_fam = observed_family) AS cand_right,
       count(*) FILTER (WHERE prod_fam <> observed_family AND cand_fam <> observed_family) AS neither
FROM t;
