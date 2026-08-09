-- Is the wood shortfall real, or just an artefact of who gets inspected?
--
-- The model reports 39.8% wood where a surveyor looked and 1.86% where it is
-- guessing. The obvious objection is selection bias: we inspect buildings we
-- already suspect. This script is the answer to that objection.
--
-- Method: compare INSIDE single neighbourhoods — what inspections found,
-- against what the model says about the uninspected buildings next door — and
-- band the neighbourhoods by how thoroughly they have been inspected.
-- Foundation type is strongly spatially autocorrelated (one street, one
-- builder, one year, one soil), so neighbours are a fair comparison.
--
-- The test: if bias explained the gap, it would SHRINK as a neighbourhood
-- approaches full coverage, because there is less room left for an unrepresentative
-- sample. Measured 2026-08-09, it does the opposite — 26.7 points at 50%
-- coverage, 41.8 points at 90%. The objection does not survive.
--
-- Also reports what a building loses when it is called non-wood: rot and
-- bio-infection are wood-pile failure modes, so a misclassified building does
-- not get an "unknown" rating, it gets an affirmative "safe" one.
--
--   psql "$DB_URL" -f sql/validate/wood_underprediction.sql

CREATE TEMP TABLE t AS
SELECT DISTINCT ON (s.building_id) s.building_id, s.foundation_type AS observed
FROM report.inquiry_sample s JOIN report.inquiry i ON i.id=s.inquiry_id
WHERE s.foundation_type IS NOT NULL AND s.delete_date IS NULL
ORDER BY s.building_id, i.document_date DESC NULLS LAST, s.id DESC;
CREATE INDEX ON t(building_id); ANALYZE t;

CREATE TEMP TABLE nb AS
SELECT bp.neighborhood_id,
       count(*) AS n_total,
       count(t.building_id) AS n_insp,
       count(*) FILTER (WHERE t.building_id IS NULL) AS n_uninsp,
       count(*) FILTER (WHERE t.building_id IS NOT NULL AND data.is_wood_family(t.observed)) AS obs_wood,
       count(*) FILTER (WHERE t.building_id IS NULL AND data.is_wood_family(m.foundation_type)) AS pred_wood
FROM data.model_risk_static m
JOIN data.building_precomputed bp ON bp.building_id = m.building_id
LEFT JOIN t ON t.building_id = m.building_id
WHERE bp.neighborhood_id IS NOT NULL
GROUP BY 1;
ANALYZE nb;

\echo '=== ROBUSTNESS: does the gap survive as coverage approaches 100%? ==='
\echo '(if selection bias explained it, the gap should shrink toward zero here)'
WITH bands AS (
  SELECT 0.50 AS lo UNION ALL SELECT 0.60 UNION ALL SELECT 0.70
  UNION ALL SELECT 0.80 UNION ALL SELECT 0.90)
SELECT b.lo AS min_coverage,
       count(*) AS nbhoods,
       sum(n.n_insp) AS inspected,
       round(100.0*sum(n.obs_wood)/nullif(sum(n.n_insp),0),1) AS observed_wood_pct,
       sum(n.n_uninsp) AS uninspected,
       round(100.0*sum(n.pred_wood)/nullif(sum(n.n_uninsp),0),1) AS model_wood_pct,
       round(100.0*sum(n.obs_wood)/nullif(sum(n.n_insp),0) - 100.0*sum(n.pred_wood)/nullif(sum(n.n_uninsp),0),1) AS gap_pts
FROM bands b JOIN nb n ON n.n_insp::numeric/n.n_total >= b.lo
WHERE n.n_total >= 50 AND n.n_uninsp >= 10
GROUP BY b.lo ORDER BY b.lo;

\echo ''
\echo '=== CONSEQUENCE: what a building loses when we call it non-wood ==='
SELECT data.is_wood_family(foundation_type) AS is_wood,
       count(*) AS buildings,
       count(drystand_risk) AS gets_rot_risk,
       count(bio_infection_risk) AS gets_bio_risk,
       count(*) FILTER (WHERE drystand_risk = 'a') AS rated_safe_a
FROM data.model_risk_static GROUP BY 1;

\echo ''
\echo '=== how many indicative buildings sit in a neighbourhood that HAS inspection evidence? ==='
SELECT count(*) AS indicative_buildings,
       count(*) FILTER (WHERE n.n_insp >= 5) AS in_nbhood_with_evidence,
       round(100.0*count(*) FILTER (WHERE n.n_insp >= 5)/count(*),1) AS pct
FROM data.model_risk_static m
JOIN data.building_precomputed bp ON bp.building_id=m.building_id
LEFT JOIN nb n ON n.neighborhood_id = bp.neighborhood_id
WHERE m.foundation_type_reliability = 'indicative';
