-- Is data.model_risk_2026_3_rows() still model-2024.1 when every rule is switched off?
--
-- The control of model-2026.3. The function is the frozen model's SQL with one switch per rule;
-- with all of them off, every one of the 30 served columns must equal data.model_risk_static_2024_1
-- for every pand. `rows_that_differ` must be 0.
--
-- Read-only, but a full national run of the model: about as long as one model refresh. Run it
-- between two refreshes: during a run the sample matviews are newer than the 2024.1 matview and
-- the difference shows up here. A few rows right after a herstel was entered are the same effect
-- (the model reads report.recovery_sample live, the matview is a snapshot).
--
--   psql "$DB_URL" -f sql/validate/model_2026_3_control.sql
--
-- Checked on a full copy of the model's inputs, 2026-10-12: 11,321,489 rows, 0 differ.

SELECT count(*) AS rows_function,
       (SELECT count(*) FROM data.model_risk_static_2024_1) AS rows_2024_1,
       count(*) FILTER (WHERE m.building_id IS NULL) AS missing_in_2024_1,
       count(*) FILTER (WHERE (f.building_id, f.address_count, f.neighborhood_id, f.construction_year, f.construction_year_reliability,
                               f.foundation_type, f.foundation_type_reliability, f.restoration_costs, f.drystand, f.drystand_risk,
                               f.drystand_risk_reliability, f.bio_infection_risk, f.bio_infection_risk_reliability, f.dewatering_depth,
                               f.dewatering_depth_risk, f.dewatering_depth_risk_reliability, f.unclassified_risk, f.height, f.velocity,
                               f.ground_water_level, f.ground_level, f.soil, f.surface_area, f.owner, f.inquiry_id, f.inquiry_type,
                               f.damage_cause, f.enforcement_term, f.overall_quality, f.recovery_type)
                              IS DISTINCT FROM
                              (m.building_id, m.address_count, m.neighborhood_id, m.construction_year, m.construction_year_reliability,
                               m.foundation_type, m.foundation_type_reliability, m.restoration_costs, m.drystand, m.drystand_risk,
                               m.drystand_risk_reliability, m.bio_infection_risk, m.bio_infection_risk_reliability, m.dewatering_depth,
                               m.dewatering_depth_risk, m.dewatering_depth_risk_reliability, m.unclassified_risk, m.height, m.velocity,
                               m.ground_water_level, m.ground_level, m.soil, m.surface_area, m.owner, m.inquiry_id, m.inquiry_type,
                               m.damage_cause, m.enforcement_term, m.overall_quality, m.recovery_type)) AS rows_that_differ
  FROM data.model_risk_2026_3_rows(
           quickscan_rules => false,
           type_per_field => false,
           term_and_quality => false,
           term_and_quality_cluster => false,
           term_countdown => false,
           decay_floor => false,
           measured_settlement => false,
           block_velocity => false,
           fallback_in_family => false,
           label_by_source => false) f
  LEFT JOIN data.model_risk_static_2024_1 m USING (building_id);
