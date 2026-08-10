-- What a candidate model does to the RISK LETTERS a customer actually sees.
--
-- Foundation type is not the product; the risk letters are. And they cascade:
-- rot and bio-infection are wood-pile failure modes, so a building the model
-- calls concrete gets no rot assessment at all -- it shows as safe. Reclassify
-- it as wood and a warning appears. This measures that movement, which is the
-- only form in which the change can sensibly be put to Don or a customer.
--
-- Scoped to INDICATIVE-tier buildings: the ~9.46M where the classifier decides
-- and no inquiry overrides it. Uses the real production risk functions, and the
-- frozen stratum weights so the sampling floor does not distort the national
-- figure.
--
-- WATCH THE NULLs. A non-wood building has NULL rot risk, and avg() silently
-- drops NULL rows -- computing a rate without COALESCE excludes exactly the
-- buildings the change is about and inflates the result several-fold. Every
-- rate below is COALESCEd to 0.
--
--   psql "$DB_URL" -f sql/validate/candidate_risk_movement.sql
-- Restricted to indicative-tier buildings -- the 9.46M where the classifier
-- decides and no inquiry overrides it. Uses the real production risk functions.
CREATE TEMP TABLE rm AS
SELECT es.building_id, es.stratum,
       f.frozen_ft, f.cand_ft,
       data.compute_indicative_drystand_risk(f.frozen_ft, f.velocity, f.gwl, f.has_rec) AS froz_dry,
       data.compute_indicative_drystand_risk(f.cand_ft,   f.velocity, f.gwl, f.has_rec) AS cand_dry,
       data.compute_indicative_bio_risk(f.frozen_ft, f.pile_len, f.velocity, f.has_rec) AS froz_bio,
       data.compute_indicative_bio_risk(f.cand_ft,   f.pile_len, f.velocity, f.has_rec) AS cand_bio
FROM data.model_evaluation_sample es
JOIN LATERAL (
    SELECT data.indicative_foundation_type(bp.construction_year_bag, bp.height, gr.code, bp.address_count) AS frozen_ft,
           (CASE WHEN l.p_wood >= 0.45 THEN 'wood'
                 WHEN l.p_no_pile >= l.p_concrete THEN 'no_pile'
                 ELSE 'concrete' END)::report.foundation_type AS cand_ft,
           bs.velocity, gwl.level AS gwl,
           round((bp.ground_level - bpl.depth)::numeric, 2) AS pile_len,
           EXISTS (SELECT 1 FROM report.recovery_sample rs WHERE rs.building_id = es.building_id) AS has_rec
    FROM data.building_precomputed bp
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = bp.building_id
    LEFT JOIN data.building_subsidence bs ON bs.building_id = bp.building_id
    LEFT JOIN data.building_groundwater_level gwl ON gwl.building_id = bp.building_id
    LEFT JOIN data.building_pleistocene bpl ON bpl.building_id = bp.building_id
    LEFT JOIN data.foundation_type_lookup_2026_1 l
      ON l.cell = data.ft_cell_2026_1(bp.construction_year_bag, bp.height, gr.code,
                                      bp.ground_level, bp.surface_area, bp.address_count)
    WHERE bp.building_id = es.building_id AND l.p_wood IS NOT NULL
) f ON true
JOIN data.model_risk_static m ON m.building_id = es.building_id
WHERE es.purpose='population' AND es.sample_version=1
  AND m.foundation_type_reliability = 'indicative';
ANALYZE rm;

\echo '=== how many indicative buildings are in scope ==='
SELECT count(*) AS sampled_indicative FROM rm;

\echo ''
\echo '=== ROT RISK: what a house shows today vs under 2026.1 ==='
\echo '(no warning = no rot risk computed, or a/b.  warning = c/d/e)'
WITH cls AS (
  SELECT stratum,
    (froz_dry IS NULL OR froz_dry IN ('a','b')) AS froz_quiet,
    (cand_dry IS NULL OR cand_dry IN ('a','b')) AS cand_quiet
  FROM rm),
per AS (
  SELECT stratum,
    avg((froz_quiet AND NOT cand_quiet)::int::numeric) AS gains_warning,
    avg((NOT froz_quiet AND cand_quiet)::int::numeric) AS loses_warning,
    avg((NOT froz_quiet)::int::numeric)                AS warned_before,
    avg((NOT cand_quiet)::int::numeric)                AS warned_after
  FROM cls GROUP BY 1)
SELECT round(sum(w.national_buildings*p.warned_before)) AS buildings_warned_today,
       round(sum(w.national_buildings*p.warned_after))  AS buildings_warned_under_2026_1,
       round(sum(w.national_buildings*p.gains_warning)) AS newly_warned,
       round(sum(w.national_buildings*p.loses_warning)) AS warning_removed
FROM per p JOIN data.model_evaluation_stratum_weight w USING (stratum) WHERE w.sample_version=1;

\echo ''
\echo '=== the severe end: d or e (urgent) ==='
WITH per AS (
  SELECT stratum,
    avg(COALESCE((froz_dry IN ('d','e'))::int,0)::numeric) AS sev_before,
    avg(COALESCE((cand_dry IN ('d','e'))::int,0)::numeric) AS sev_after
  FROM rm GROUP BY 1)
SELECT round(sum(w.national_buildings*p.sev_before)) AS severe_today,
       round(sum(w.national_buildings*p.sev_after))  AS severe_under_2026_1
FROM per p JOIN data.model_evaluation_stratum_weight w USING (stratum) WHERE w.sample_version=1;

\echo ''
\echo '=== bio-infection risk, same view ==='
WITH per AS (
  SELECT stratum,
    avg((froz_bio IS NOT NULL)::int::numeric) AS before_any,
    avg((cand_bio IS NOT NULL)::int::numeric) AS after_any
  FROM rm GROUP BY 1)
SELECT round(sum(w.national_buildings*p.before_any)) AS bio_assessed_today,
       round(sum(w.national_buildings*p.after_any))  AS bio_assessed_under_2026_1
FROM per p JOIN data.model_evaluation_stratum_weight w USING (stratum) WHERE w.sample_version=1;
