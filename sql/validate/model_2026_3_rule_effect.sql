-- What does ONE rule of model-2026.3 change?
--
-- Compares the model with every rule on (data.model_risk_static_2026_3) against the same model
-- with one rule switched off. "Worst" is the worst of a pand's four risk letters: what
-- /v4/product/light overallRisk and the map colour follow.
--
-- Read-only, but a full national run of the model: about as long as one model refresh. Run it
-- between two refreshes.
--
--   psql "$DB_URL" -v rule=block_velocity -f sql/validate/model_2026_3_rule_effect.sql
--
-- rule is one switch of data.model_risk_2026_3_rows(): quickscan_rules, type_per_field,
-- term_and_quality, term_and_quality_cluster, term_countdown, decay_floor, measured_settlement,
-- block_velocity, fallback_in_family, label_by_source.

\echo rule switched off: :rule

CREATE TEMP TABLE rule_effect AS
SELECT f.building_id,
       f.foundation_type AS type_without, m.foundation_type AS type_with,
       f.drystand_risk AS dry_without, m.drystand_risk AS dry_with,
       f.bio_infection_risk AS bio_without, m.bio_infection_risk AS bio_with,
       f.dewatering_depth_risk AS dew_without, m.dewatering_depth_risk AS dew_with,
       f.unclassified_risk AS unc_without, m.unclassified_risk AS unc_with,
       (f.drystand_risk_reliability, f.bio_infection_risk_reliability, f.dewatering_depth_risk_reliability)
           IS DISTINCT FROM (m.drystand_risk_reliability, m.bio_infection_risk_reliability, m.dewatering_depth_risk_reliability) AS label_changed,
       (SELECT max(r) FROM unnest(ARRAY[f.drystand_risk, f.bio_infection_risk, f.dewatering_depth_risk, f.unclassified_risk]) r) AS worst_without,
       (SELECT max(r) FROM unnest(ARRAY[m.drystand_risk, m.bio_infection_risk, m.dewatering_depth_risk, m.unclassified_risk]) r) AS worst_with
  FROM data.model_risk_2026_3_rows(:rule => false) f
  JOIN data.model_risk_static_2026_3 m USING (building_id)
 WHERE (f.foundation_type, f.drystand_risk, f.bio_infection_risk, f.dewatering_depth_risk, f.unclassified_risk,
        f.drystand_risk_reliability, f.bio_infection_risk_reliability, f.dewatering_depth_risk_reliability)
       IS DISTINCT FROM
       (m.foundation_type, m.drystand_risk, m.bio_infection_risk, m.dewatering_depth_risk, m.unclassified_risk,
        m.drystand_risk_reliability, m.bio_infection_risk_reliability, m.dewatering_depth_risk_reliability);

SELECT count(*) AS panden_changed,
       count(*) FILTER (WHERE (dry_without, bio_without, dew_without, unc_without) IS DISTINCT FROM (dry_with, bio_with, dew_with, unc_with)) AS letter_changed,
       count(*) FILTER (WHERE label_changed) AS label_changed,
       count(*) FILTER (WHERE type_without IS DISTINCT FROM type_with) AS type_changed,
       count(*) FILTER (WHERE worst_with < worst_without) AS worst_better,
       count(*) FILTER (WHERE worst_with > worst_without) AS worst_worse,
       count(*) FILTER (WHERE worst_without IS NOT NULL AND worst_with IS NULL) AS left_without_risk
  FROM rule_effect;

SELECT v.field,
       count(*) FILTER (WHERE v.rule_off IS NULL AND v.rule_on IS NOT NULL) AS gained,
       count(*) FILTER (WHERE v.rule_off IS NOT NULL AND v.rule_on IS NULL) AS lost,
       count(*) FILTER (WHERE v.rule_on < v.rule_off) AS better,
       count(*) FILTER (WHERE v.rule_on > v.rule_off) AS worse
  FROM rule_effect e
 CROSS JOIN LATERAL (VALUES ('drystand', e.dry_without, e.dry_with),
                            ('bio_infection', e.bio_without, e.bio_with),
                            ('dewatering_depth', e.dew_without, e.dew_with),
                            ('unclassified', e.unc_without, e.unc_with)) AS v(field, rule_off, rule_on)
 WHERE v.rule_off IS DISTINCT FROM v.rule_on
 GROUP BY 1 ORDER BY 1;
