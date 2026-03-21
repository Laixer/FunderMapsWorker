-- data.model_risk_static — Materialized view definition
--
-- Replaces the old model_risk_manifest() INSERT ON CONFLICT procedure.
-- Now a materialized view refreshed via REFRESH MATERIALIZED VIEW CONCURRENTLY.
--
-- Source: data.model_risk_dynamic_all (large view joining building, address,
--         inquiry, recovery, subsidence, groundwater, elevation, etc.)
--
-- Indexes:
--   - building_id (unique BAG ID, required for CONCURRENTLY)
--   - neighborhood_id (used by statistics aggregation)
--
-- Refreshed daily at 18:00 UTC by data.refresh_all() via pg_cron.

CREATE MATERIALIZED VIEW data.model_risk_static AS
SELECT
    building_id,
    address_count,
    neighborhood_id,
    construction_year,
    construction_year_reliability,
    foundation_type,
    foundation_type_reliability,
    restoration_costs,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    unclassified_risk,
    height,
    velocity,
    ground_water_level,
    ground_level,
    soil,
    surface_area,
    owner,
    inquiry_id,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    recovery_type
FROM data.model_risk_dynamic_all
WITH DATA;

CREATE UNIQUE INDEX model_risk_static_pkey ON data.model_risk_static USING btree (building_id);
CREATE INDEX idx_mrs_neighborhood ON data.model_risk_static USING btree (neighborhood_id);

GRANT SELECT ON data.model_risk_static TO fundermaps_webapp;
GRANT SELECT ON data.model_risk_static TO fundermaps_webservice;
