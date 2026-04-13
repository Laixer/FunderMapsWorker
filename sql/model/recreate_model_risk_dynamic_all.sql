-- Phase A4: Rewrite model_risk_dynamic_all
--
-- Depends on:
--   - Phase A1: Helper functions (data.is_wood_family, compute_damage_risk, etc.)
--   - Phase A2: data.building_precomputed (surface_area, address_count, height, ground_level)
--   - Phase A3: Fixed sample matviews (building_sample, cluster_sample, supercluster_sample)
--
-- Changes from current view:
--   - FROM building_precomputed instead of building_active (eliminates ST_Area, address count, double elevation scan)
--   - LEFT JOINs reduced from 14 to 10 (no building_elevation, no building_height)
--   - Risk LATERALs replaced by function calls
--   - Wood/no-pile checks use helper functions
--   - Bug fixes:
--     * Duplicate wood_rotterdam_arch in drystand CASE removed
--     * dewatering_depth cluster branch: checks foundation_depth IS NOT NULL (was wood_level)
--     * wood_rotterdam_amsterdam removed from no-pile dewatering_depth types

CREATE OR REPLACE VIEW data.model_risk_dynamic_all AS
SELECT
    bp.building_id,
    bp.address_count,
    bp.neighborhood_id,

    -- Construction year: established inquiry overrides BAG
    COALESCE(established.built_year, bp.construction_year_bag) AS construction_year,
    CASE
        WHEN established.built_year IS NOT NULL THEN 'established'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS construction_year_reliability,

    -- Foundation type: established > cluster > supercluster > indicative
    foundation_type.ft AS foundation_type,
    CASE
        WHEN established.foundation_type IS NOT NULL THEN 'established'::data.reliability
        WHEN cluster.foundation_type IS NOT NULL THEN 'cluster'::data.reliability
        WHEN supercluster.foundation_type IS NOT NULL THEN 'supercluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS foundation_type_reliability,

    -- Restoration costs
    data.compute_restoration_costs(foundation_type.ft, bp.surface_area) AS restoration_costs,

    -- Drystand (wood level - groundwater level, or indicative estimate)
    CASE
        WHEN established.wood_level IS NOT NULL AND established.groundwater_level IS NOT NULL
            THEN (established.wood_level::numeric - established.groundwater_level::numeric)::double precision
        WHEN cluster.wood_level IS NOT NULL AND cluster.groundwater_level IS NOT NULL
            THEN (cluster.wood_level::numeric - cluster.groundwater_level::numeric)::double precision
        WHEN supercluster.wood_level IS NOT NULL AND supercluster.groundwater_level IS NOT NULL
            THEN (supercluster.wood_level::numeric - supercluster.groundwater_level::numeric)::double precision
        WHEN foundation_type.ft = 'wood_charger'
            THEN gwl.level - 2.5
        WHEN data.is_wood_pile(foundation_type.ft)
            THEN gwl.level - 1.5
        ELSE NULL
    END AS drystand,

    -- Drystand risk (established > cluster > supercluster > indicative)
    COALESCE(
        data.compute_damage_risk(
            recovery.type IS NOT NULL,
            established.damage_cause,
            ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[],
            established.enforcement_term, established.overall_quality, established.recovery_advised
        ),
        data.compute_damage_risk(
            false,
            cluster.damage_cause,
            ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[],
            cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised
        ),
        data.compute_damage_risk(
            false,
            supercluster.damage_cause,
            ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[],
            supercluster.enforcement_term, supercluster.overall_quality, supercluster.recovery_advised
        ),
        data.compute_indicative_drystand_risk(
            foundation_type.ft, bs.velocity, gwl.level, recovery.type IS NOT NULL
        )
    ) AS drystand_risk,
    CASE
        WHEN established.id IS NOT NULL THEN 'established'::data.reliability
        WHEN cluster.id IS NOT NULL THEN 'cluster'::data.reliability
        WHEN supercluster.id IS NOT NULL THEN 'supercluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS drystand_risk_reliability,

    -- Bio infection risk (established > cluster > supercluster > indicative)
    COALESCE(
        data.compute_damage_risk(
            recovery.type IS NOT NULL,
            established.damage_cause,
            ARRAY['bio_infection']::report.foundation_damage_cause[],
            established.enforcement_term, established.overall_quality, established.recovery_advised
        ),
        data.compute_damage_risk(
            false,
            cluster.damage_cause,
            ARRAY['bio_infection']::report.foundation_damage_cause[],
            cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised
        ),
        data.compute_damage_risk(
            false,
            supercluster.damage_cause,
            ARRAY['bio_infection']::report.foundation_damage_cause[],
            supercluster.enforcement_term, supercluster.overall_quality, supercluster.recovery_advised
        ),
        data.compute_indicative_bio_risk(
            foundation_type.ft, pile_length.pile_length, bs.velocity, recovery.type IS NOT NULL
        )
    ) AS bio_infection_risk,
    CASE
        WHEN established.id IS NOT NULL THEN 'established'::data.reliability
        WHEN cluster.id IS NOT NULL THEN 'cluster'::data.reliability
        WHEN supercluster.id IS NOT NULL THEN 'supercluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS bio_infection_risk_reliability,

    -- Dewatering depth
    -- BUG FIX: cluster branch now checks foundation_depth IS NOT NULL (was wood_level)
    CASE
        WHEN established.foundation_depth IS NOT NULL AND established.groundwater_level IS NOT NULL
            THEN ((established.foundation_depth::numeric - established.groundwater_level::numeric) - 0.6)::double precision
        WHEN cluster.foundation_depth IS NOT NULL AND cluster.groundwater_level IS NOT NULL
            THEN ((cluster.foundation_depth::numeric - cluster.groundwater_level::numeric) - 0.6)::double precision
        WHEN supercluster.foundation_depth IS NOT NULL AND supercluster.groundwater_level IS NOT NULL
            THEN ((supercluster.foundation_depth::numeric - supercluster.groundwater_level::numeric) - 0.6)::double precision
        -- BUG FIX: wood_rotterdam_amsterdam removed from no-pile types
        WHEN data.is_no_pile_family(foundation_type.ft)
            THEN gwl.level - 0.6
        ELSE NULL
    END AS dewatering_depth,

    -- Dewatering depth risk (established > cluster > supercluster > indicative)
    COALESCE(
        data.compute_damage_risk(
            recovery.type IS NOT NULL,
            established.damage_cause,
            ARRAY['drainage']::report.foundation_damage_cause[],
            established.enforcement_term, established.overall_quality, established.recovery_advised
        ),
        data.compute_damage_risk(
            false,
            cluster.damage_cause,
            ARRAY['drainage']::report.foundation_damage_cause[],
            cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised
        ),
        data.compute_damage_risk(
            false,
            supercluster.damage_cause,
            ARRAY['drainage']::report.foundation_damage_cause[],
            supercluster.enforcement_term, supercluster.overall_quality, supercluster.recovery_advised
        ),
        data.compute_indicative_dewatering_risk(
            foundation_type.ft, bs.velocity, gwl.level, recovery.type IS NOT NULL
        )
    ) AS dewatering_depth_risk,
    CASE
        WHEN established.id IS NOT NULL THEN 'established'::data.reliability
        WHEN cluster.id IS NOT NULL THEN 'cluster'::data.reliability
        WHEN supercluster.id IS NOT NULL THEN 'supercluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS dewatering_depth_risk_reliability,

    -- Unclassified risk (established > cluster > supercluster)
    COALESCE(
        data.compute_unclassified_risk(
            recovery.type IS NOT NULL, 'a', 'e',
            established.enforcement_term, established.overall_quality,
            established.recovery_advised, established.damage_cause
        ),
        data.compute_unclassified_risk(
            cluster_recovery_sample.type IS NOT NULL, 'e', 'd',
            cluster.enforcement_term, cluster.overall_quality,
            cluster.recovery_advised, cluster.damage_cause
        ),
        data.compute_unclassified_risk(
            false, 'e', 'd',
            supercluster.enforcement_term, supercluster.overall_quality,
            supercluster.recovery_advised, supercluster.damage_cause
        )
    ) AS unclassified_risk,

    -- Physical measurements
    bp.height::numeric(10,2) AS height,
    round(bs.velocity::numeric, 2) AS velocity,
    round(gwl.level::numeric, 2) AS ground_water_level,
    bp.ground_level,
    gr.code AS soil,
    bp.surface_area,
    bo.owner,

    -- Best inquiry info
    COALESCE(established.id, cluster.id, supercluster.id) AS inquiry_id,
    COALESCE(established.inquiry_type, cluster.inquiry_type, supercluster.inquiry_type) AS inquiry_type,
    COALESCE(established.damage_cause, cluster.damage_cause, supercluster.damage_cause) AS damage_cause,

    -- Enforcement term remaining years
    date_part('years', age(
        (COALESCE(established.document_date, cluster.document_date, supercluster.document_date)
         + data.enforcement_term_years(COALESCE(established.enforcement_term, cluster.enforcement_term, supercluster.enforcement_term))
        )::timestamp with time zone,
        CURRENT_TIMESTAMP
    )) AS enforcement_term,

    COALESCE(established.overall_quality, cluster.overall_quality, supercluster.overall_quality) AS overall_quality,
    recovery.type AS recovery_type

FROM data.building_precomputed bp
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = bp.building_id
    LEFT JOIN data.building_groundwater_level gwl ON gwl.building_id = bp.building_id
    LEFT JOIN data.building_subsidence bs ON bs.building_id = bp.building_id
    LEFT JOIN data.building_ownership bo ON bo.building_id = bp.building_id
    LEFT JOIN data.building_pleistocene bpl ON bpl.building_id = bp.building_id
    LEFT JOIN data.building_cluster bc ON bc.building_id = bp.building_id
    LEFT JOIN data.supercluster bsc ON bsc.cluster_id = bc.cluster_id
    LEFT JOIN data.building_sample established ON established.building_id = bp.building_id
    LEFT JOIN data.cluster_sample cluster ON cluster.cluster_id = bc.cluster_id
    LEFT JOIN data.supercluster_sample supercluster ON supercluster.supercluster_id = bsc.supercluster_id
    LEFT JOIN LATERAL (
        SELECT DISTINCT ON (rs.building_id) rs.building_id, rs.type
        FROM report.recovery_sample rs
        WHERE rs.building_id = bp.building_id
        ORDER BY rs.building_id, rs.create_date DESC
    ) recovery ON true
    LEFT JOIN data.cluster_recovery_sample ON cluster_recovery_sample.cluster_id = bc.cluster_id,
    -- Pile length: ground_level - pleistocene depth
    LATERAL (SELECT round((bp.ground_level - bpl.depth)::numeric, 2)) AS pile_length(pile_length),
    -- Foundation type resolution: established > cluster > supercluster > indicative
    LATERAL (SELECT COALESCE(
        established.foundation_type,
        cluster.foundation_type,
        supercluster.foundation_type,
        data.indicative_foundation_type(
            COALESCE(established.built_year, bp.construction_year_bag),
            bp.height,
            gr.code,
            bp.address_count
        )
    )) AS foundation_type(ft);
