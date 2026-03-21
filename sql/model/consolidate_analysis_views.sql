-- Phase A6: Consolidate Analysis Views + Add Indexes
--
-- Problem: 5 analysis views (analysis_building, analysis_foundation, analysis_full,
-- analysis_report, analysis_risk) repeat the same 4-way JOIN and WHERE clause.
-- They also use unnecessary DISTINCT ON — the PK on model_risk_static guarantees
-- uniqueness.
--
-- Fix: Create a shared base view (building_geo_hierarchy), then make each
-- analysis view a thin column projection.
--
-- Note: analysis_monitoring is different (queries inquiry_sample directly,
-- not model_risk_static) and is left unchanged here.

--------------------------------------------------------------------------------
-- Shared base view
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW data.building_geo_hierarchy AS
SELECT
    mrs.*,
    ba.geom,
    n.external_id AS ext_neighborhood_id,
    d.external_id AS ext_district_id,
    m.external_id AS ext_municipality_id
FROM data.model_risk_static mrs
JOIN geocoder.building_active ba ON ba.external_id = mrs.building_id
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id
WHERE mrs.address_count > 0;

--------------------------------------------------------------------------------
-- Thin projection views (no DISTINCT ON needed — PK guarantees uniqueness)
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW maplayer.analysis_building AS
SELECT
    building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    address_count,
    construction_year,
    construction_year_reliability,
    height,
    owner,
    geom
FROM data.building_geo_hierarchy;

---

CREATE OR REPLACE VIEW maplayer.analysis_foundation AS
SELECT
    building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    foundation_type,
    foundation_type_reliability,
    height,
    owner,
    recovery_type,
    velocity,
    geom
FROM data.building_geo_hierarchy;

---

CREATE OR REPLACE VIEW maplayer.analysis_full AS
SELECT
    building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    address_count,
    foundation_type,
    foundation_type_reliability,
    construction_year,
    construction_year_reliability,
    restoration_costs,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    unclassified_risk,
    overall_quality,
    ground_water_level,
    ground_level,
    soil,
    surface_area,
    recovery_type,
    inquiry_type,
    enforcement_term,
    damage_cause,
    velocity,
    height,
    owner,
    inquiry_id,
    geom
FROM data.building_geo_hierarchy;

---

CREATE OR REPLACE VIEW maplayer.analysis_report AS
SELECT
    building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    height,
    owner,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    geom
FROM data.building_geo_hierarchy;

---

CREATE OR REPLACE VIEW maplayer.analysis_risk AS
SELECT
    building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    restoration_costs,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    unclassified_risk,
    height,
    owner,
    geom
FROM data.building_geo_hierarchy;

--------------------------------------------------------------------------------
-- Missing indexes
--------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_mrs_neighborhood
    ON data.model_risk_static (neighborhood_id);

CREATE INDEX IF NOT EXISTS idx_address_postal_code
    ON geocoder.address (postal_code);
