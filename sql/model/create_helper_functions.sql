-- Phase A1: Helper Functions for Risk Model Pipeline
-- All functions are IMMUTABLE and PARALLEL SAFE unless noted.
-- These extract repeated logic from data.model_risk_dynamic_all.
--
-- Run this file idempotently: CREATE OR REPLACE throughout.

--------------------------------------------------------------------------------
-- Foundation type classification
--------------------------------------------------------------------------------

-- All wood-family types (including wood_charger)
CREATE OR REPLACE FUNCTION data.is_wood_family(ft report.foundation_type)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT ft IN (
        'wood', 'wood_charger', 'wood_amsterdam', 'wood_rotterdam',
        'wood_rotterdam_amsterdam', 'wood_amsterdam_arch', 'wood_rotterdam_arch'
    );
$$;

-- Wood pile types (excludes wood_charger — charger has different velocity/GWL thresholds)
CREATE OR REPLACE FUNCTION data.is_wood_pile(ft report.foundation_type)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT ft IN (
        'wood', 'wood_amsterdam', 'wood_rotterdam',
        'wood_rotterdam_amsterdam', 'wood_amsterdam_arch', 'wood_rotterdam_arch'
    );
$$;

-- No-pile family types
CREATE OR REPLACE FUNCTION data.is_no_pile_family(ft report.foundation_type)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT ft IN (
        'no_pile', 'no_pile_masonry', 'no_pile_strips',
        'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor'
    );
$$;

-- Safe foundation types (no risk)
CREATE OR REPLACE FUNCTION data.is_safe_foundation(ft report.foundation_type)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT ft IN ('concrete', 'weighted_pile');
$$;

--------------------------------------------------------------------------------
-- Enforcement term → interval mapping
-- Handles both old (term05/term510/term1020) and new (term5/term10/.../term40) enums
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data.enforcement_term_years(term report.enforcement_term)
RETURNS interval
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE term
        WHEN 'term05'   THEN interval '5 years'
        WHEN 'term510'  THEN interval '10 years'
        WHEN 'term1020' THEN interval '20 years'
        WHEN 'term5'    THEN interval '5 years'
        WHEN 'term10'   THEN interval '10 years'
        WHEN 'term15'   THEN interval '15 years'
        WHEN 'term20'   THEN interval '20 years'
        WHEN 'term25'   THEN interval '25 years'
        WHEN 'term30'   THEN interval '30 years'
        WHEN 'term40'   THEN interval '40 years'
        ELSE NULL
    END;
$$;

--------------------------------------------------------------------------------
-- Restoration cost estimate
-- Wood family: €1950/m², no-pile family (excl bearing_floor): €350/m²
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data.compute_restoration_costs(
    ft report.foundation_type,
    surface_area numeric
)
RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN data.is_wood_family(ft)
            THEN (round((surface_area * 1950), -2))::integer
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
            THEN (round((surface_area * 350), -2))::integer
        ELSE NULL
    END;
$$;

--------------------------------------------------------------------------------
-- Indicative foundation type decision tree
-- Extracted verbatim from model_risk_dynamic_all LATERAL indicative_foundation_type
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data.indicative_foundation_type(
    construction_year integer,
    height double precision,
    soil_code text,
    address_count integer
)
RETURNS report.foundation_type
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE
        -- Post-1940 large buildings: concrete
        WHEN construction_year >= 1940 AND construction_year < 1965
             AND address_count >= 8
            THEN 'concrete'::report.foundation_type

        -- Post-1965, low/unknown height, sandy soil: no_pile
        WHEN construction_year >= 1965
             AND (height < 14 OR height IS NULL)
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'no_pile'::report.foundation_type

        -- Post-1965, low/unknown height, non-sandy/unknown soil: concrete
        WHEN construction_year >= 1965
             AND (height < 14 OR height IS NULL)
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'concrete'::report.foundation_type

        -- Post-1965, tall: concrete
        WHEN construction_year >= 1965
             AND height >= 14
            THEN 'concrete'::report.foundation_type

        -- 1700-1800, low/unknown, sandy: no_pile
        WHEN construction_year >= 1700 AND construction_year < 1800
             AND (height < 14 OR height IS NULL)
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'no_pile'::report.foundation_type

        -- 1700-1800, tall, sandy: wood
        WHEN construction_year >= 1700 AND construction_year < 1800
             AND height >= 14
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'wood'::report.foundation_type

        -- 1700-1800, short, non-sandy/unknown: no_pile
        WHEN construction_year >= 1700 AND construction_year < 1800
             AND height < 8.5
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'no_pile'::report.foundation_type

        -- 1700-1800, not-short/unknown, non-sandy/unknown: wood
        WHEN construction_year >= 1700 AND construction_year < 1800
             AND (height >= 8.5 OR height IS NULL)
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'wood'::report.foundation_type

        -- 1800-1965, low/unknown, sandy: no_pile
        WHEN construction_year >= 1800 AND construction_year < 1965
             AND (height < 14 OR height IS NULL)
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'no_pile'::report.foundation_type

        -- 1800-1965, tall, sandy: wood
        WHEN construction_year >= 1800 AND construction_year < 1965
             AND height >= 14
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'wood'::report.foundation_type

        -- 1800-1965, short, non-sandy/unknown: no_pile
        WHEN construction_year >= 1800 AND construction_year < 1965
             AND height < 8.5
             AND soil_code NOT IN ('hz', 'ni-hz', 'ni-du')
             AND (soil_code <> 'ni-du' OR soil_code IS NULL)
            THEN 'no_pile'::report.foundation_type

        -- 1800-1920, not-short/unknown, non-sandy/unknown: wood
        WHEN construction_year >= 1800 AND construction_year < 1920
             AND (height >= 8.5 OR height IS NULL)
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'wood'::report.foundation_type

        -- 1920-1965, not-short/unknown, non-sandy/unknown: wood_charger
        WHEN construction_year >= 1920 AND construction_year < 1965
             AND (height >= 8.5 OR height IS NULL)
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'wood_charger'::report.foundation_type

        -- Pre-1700: no_pile
        WHEN construction_year < 1700
            THEN 'no_pile'::report.foundation_type

        -- Fallback by height
        WHEN height >= 10.5
            THEN 'wood'::report.foundation_type
        WHEN height < 10.5
            THEN 'no_pile'::report.foundation_type

        ELSE 'other'::report.foundation_type
    END;
$$;

--------------------------------------------------------------------------------
-- Damage-cause risk (established and cluster tiers)
--
-- Used for drystand, dewatering, and bio_infection risk at established/cluster level.
-- The same enforcement_term → risk mapping is used for all three, differing only
-- in which damage_causes are relevant.
--
-- Parameters:
--   has_recovery:   true if building has a recovery record (established tier only)
--   damage_cause:   the sample's damage_cause value
--   target_causes:  which causes apply (e.g. ARRAY['drystand','fungus_infection','bio_fungus_infection'])
--   enforcement_term: the sample's enforcement_term
--   overall_quality:  the sample's overall_quality
--   recovery_advised: the sample's recovery_advised flag
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data.compute_damage_risk(
    has_recovery boolean,
    damage_cause report.foundation_damage_cause,
    target_causes report.foundation_damage_cause[],
    enforcement_term report.enforcement_term,
    overall_quality report.foundation_quality,
    recovery_advised boolean
)
RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE
        -- Recovery exists → safe (established tier only)
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication

        -- Urgent: short enforcement term, recovery advised, or bad quality
        WHEN damage_cause = ANY(target_causes)
             AND (enforcement_term IN ('term05', 'term5')
                  OR recovery_advised
                  OR overall_quality = 'bad')
            THEN 'e'::data.foundation_risk_indication

        -- Concerning: medium enforcement term or mediocre-bad quality
        WHEN damage_cause = ANY(target_causes)
             AND (enforcement_term IN ('term510', 'term10')
                  OR overall_quality = 'mediocre_bad')
            THEN 'd'::data.foundation_risk_indication

        -- Moderate: longer term or mediocre/tolerable quality
        WHEN damage_cause = ANY(target_causes)
             AND (enforcement_term IN ('term1020', 'term15', 'term20')
                  OR overall_quality IN ('mediocre', 'tolerable'))
            THEN 'c'::data.foundation_risk_indication

        -- Low: long term or good quality
        WHEN damage_cause = ANY(target_causes)
             AND (enforcement_term IN ('term25', 'term30', 'term40')
                  OR overall_quality IN ('good', 'mediocre_good'))
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;

--------------------------------------------------------------------------------
-- Unclassified risk (catch-all when damage cause doesn't match specific categories)
--
-- Established tier: recovery → 'a', urgent → 'e', long → 'b'
-- Cluster tier:     cluster_recovery → 'e', urgent → 'd', long → 'b'
--
-- Parameterized with risk levels to handle both tiers.
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data.compute_unclassified_risk(
    has_recovery boolean,
    recovery_risk data.foundation_risk_indication,   -- 'a' for established, 'e' for cluster
    urgent_risk data.foundation_risk_indication,     -- 'e' for established, 'd' for cluster
    enforcement_term report.enforcement_term,
    overall_quality report.foundation_quality,
    recovery_advised boolean,
    damage_cause report.foundation_damage_cause
)
RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN has_recovery THEN recovery_risk

        WHEN enforcement_term IN ('term05', 'term5', 'term510', 'term10',
                                   'term15', 'term1020', 'term20')
             OR recovery_advised
             OR overall_quality IN ('bad', 'mediocre_bad', 'mediocre')
             OR damage_cause IS NOT NULL
            THEN urgent_risk

        WHEN enforcement_term IN ('term25', 'term30', 'term40')
             OR overall_quality IN ('good', 'mediocre_good', 'tolerable')
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;

--------------------------------------------------------------------------------
-- Indicative drystand risk
-- Wood pile (excl charger): velocity threshold -2.0, GWL threshold 1.5
-- Wood charger:             velocity threshold -1.0, GWL threshold 2.5
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data.compute_indicative_drystand_risk(
    ft report.foundation_type,
    velocity double precision,
    gwl double precision,
    has_recovery boolean
)
RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication
        WHEN data.is_safe_foundation(ft) THEN 'a'::data.foundation_risk_indication

        -- Wood pile types (threshold: velocity -2.0, GWL 1.5)
        WHEN data.is_wood_pile(ft) AND velocity IS NULL AND gwl >= 1.5
            THEN 'c'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity IS NULL AND gwl < 1.5
            THEN 'b'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity < -2.0 AND gwl >= 1.5
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity >= -2.0 AND gwl >= 1.5
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity < -2.0 AND gwl < 1.5
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity >= -2.0 AND gwl < 1.5
            THEN 'c'::data.foundation_risk_indication

        -- Wood charger (threshold: velocity -1.0, GWL 2.5)
        WHEN ft = 'wood_charger' AND velocity IS NULL AND gwl >= 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity IS NULL AND gwl < 2.5
            THEN 'b'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity < -1.0 AND gwl >= 2.5
            THEN 'e'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity < -1.0 AND gwl < 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity >= -1.0 AND gwl >= 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity >= -1.0 AND gwl < 2.5
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;

--------------------------------------------------------------------------------
-- Indicative dewatering depth risk
-- No-pile family: velocity threshold -1.0, GWL threshold 0.6
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data.compute_indicative_dewatering_risk(
    ft report.foundation_type,
    velocity double precision,
    gwl double precision,
    has_recovery boolean
)
RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication
        WHEN data.is_safe_foundation(ft) THEN 'a'::data.foundation_risk_indication

        -- No-pile family (excl bearing_floor for risk calc, matching current behavior)
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity IS NULL AND gwl < 0.6
            THEN 'c'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity IS NULL AND gwl >= 0.6
            THEN 'b'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity < -1.0 AND gwl < 0.6
            THEN 'e'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity < -1.0 AND gwl >= 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity >= -1.0 AND gwl < 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity >= -1.0 AND gwl >= 0.6
            THEN 'c'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;

--------------------------------------------------------------------------------
-- Indicative bio infection risk
-- Wood family (including charger): based on pile length and velocity
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data.compute_indicative_bio_risk(
    ft report.foundation_type,
    pile_length numeric,
    velocity double precision,
    has_recovery boolean
)
RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication

        -- Short piles (≤12m)
        WHEN data.is_wood_family(ft) AND pile_length <= 12 AND velocity < -2.0
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length <= 12
            THEN 'd'::data.foundation_risk_indication

        -- Medium piles (12-15m)
        WHEN data.is_wood_family(ft) AND pile_length > 12 AND pile_length <= 15
             AND velocity < -2.0
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length > 12 AND pile_length <= 15
            THEN 'c'::data.foundation_risk_indication

        -- Long piles (>15m)
        WHEN data.is_wood_family(ft) AND pile_length > 15 AND velocity < -2.0
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length > 15
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;
