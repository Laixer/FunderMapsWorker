-- model-2026.3 as specified in Worker #283, as its own model: own function, own helper copies, one
-- small sample matview. Still a candidate: nothing is served from it and the default does not move
-- here (that is the switch, a migration of its own).
--
-- Why (Yorick, 2026-10-12): "holding the switch and ship everything at once"; 2026-10-15: the spec
-- #283 is approved. The 2026.3 built on 2026-10-12 (20261012_002) holds the QuickScan rules only, as
-- "the 2024.1 row of every pand, with the QuickScan panden recomputed". The spec changes panden
-- everywhere, so the version gets the full model SQL.
--
-- One switch of data.model_risk_2026_3_rows() per section of the spec:
--   quickscan_rules         0, 1: the QuickScan gate of the candidate (3-year window, a
--                           funderingsonderzoek from the last 5 years leads, addendum only) and an
--                           executed herstel ahead of any QuickScan (#222)
--   term_and_quality        2: a report without a damage cause still gives a class from its
--                           enforcement term (counting down in whole years), overall quality and
--                           herstel advice, the worse one winning, for the risks of the foundation
--                           family (wood: drystand + bio; shallow: dewatering depth); own report and
--                           block alike. A report with a matching damage cause keeps 2024.1's ladder.
--   decay_floor             3: decay found by the governing report = at least d for that risk
--   block_velocity          4 (#236, V5): the drystand and dewatering rules use the block's median
--                           subsidence for a measured pand, with the threshold 0.3 mm/year further;
--                           an unmeasured pand stays unmeasured
--   fallback_to_dewatering  5 (#242): the build-year estimate goes to dewatering_depth_risk,
--                           labelled indicative, not to the overall class
--   label_by_source         5 (#235): a risk is labelled by the rule that produced its value
--
-- Foundation type stays as in model-2024.1 (spec, Scope). Not in this version (spec, "Not in
-- 2026.3"): measured settlement, skew, foundation type per field (#243), other quality fields.
--
-- With every switch off the function IS model-2024.1, and with only quickscan_rules on it is the
-- build of 20261012_002. Both are checked on a full copy of the model's inputs taken from prod,
-- all 30 columns of every row, both sides computed on the same calendar day (the model reads
-- today's date): see the pull request.
--
-- The frozen model is not touched: data.compute_damage_risk and the indicative functions keep their
-- text; model-2026.3 calls its own copies where the spec changes a rule. The helpers no rule changes
-- (compute_damage_risk for a matching damage cause, compute_indicative_bio_risk, the family
-- predicates, indicative_foundation_type, compute_restoration_costs, compute_unclassified_risk,
-- enforcement_term_years) are shared by both models.
--
-- Cost: model-2026.3 becomes a full national run, about as long as the model-2024.1 refresh, and one
-- small sample matview is refreshed after data.building_sample. On prod the first build in this
-- file takes about as long as one model refresh; it locks nothing a reader uses.

-- ---------------------------------------------------------------------------
-- 1. What the model reads beside the leading record
-- ---------------------------------------------------------------------------

-- What model-2026.3 reads from the reports beside the leading record of data.building_sample
-- (which it keeps reading, like model-2024.1). One small matview, refreshed right after
-- data.building_sample in the same flow step.

CREATE MATERIALIZED VIEW data.building_sample_2026_3 AS
WITH dated AS (
    -- The dates the QuickScan gate needs (spec #283, section 0), read exactly as the candidate of
    -- 20260928_004 read them: the newest QuickScan addendum (inquiry type facade_scan) that carries
    -- a class, and the newest funderingsonderzoek of the pand.
    SELECT s.building_id::text AS building_id,
           max(i.document_date) FILTER (WHERE s.facade_scan_risk IS NOT NULL AND i.type = 'facade_scan') AS qs_date,
           max(i.document_date) FILTER (WHERE i.type IN ('foundation_research', 'inspectionpit', 'second_opinion', 'additional_research')) AS fo_date
      FROM report.inquiry_sample s
      JOIN report.inquiry i ON i.id = s.inquiry_id
     GROUP BY 1
),
decay AS (
    -- Spec #283, section 3: decay found in the wood by the governing report of the pand (the
    -- inquiry data.building_sample took the leading record from).
    SELECT s.building_id::text AS building_id,
           bool_or(s.wood_encroachment IN ('fungus_infection', 'bio_fungus_infection')) AS fungus_decay,
           bool_or(s.wood_encroachment IN ('bio_infection', 'bio_fungus_infection')) AS bio_decay
      FROM report.inquiry_sample s
      JOIN data.building_sample bs ON bs.building_id = s.building_id::text AND bs.id = s.inquiry_id
     WHERE s.wood_encroachment IS NOT NULL
     GROUP BY 1
)
SELECT d.building_id,
       d.qs_date,
       d.fo_date,
       COALESCE(x.fungus_decay, false) AS fungus_decay,
       COALESCE(x.bio_decay, false) AS bio_decay
  FROM dated d
  LEFT JOIN decay x USING (building_id)
WITH NO DATA;

CREATE UNIQUE INDEX building_sample_2026_3_pkey ON data.building_sample_2026_3 (building_id);

-- ---------------------------------------------------------------------------
-- 2. Own copies of the helpers whose rules change
-- ---------------------------------------------------------------------------

-- model-2026.3: its own copies of the helpers whose rules change (spec #283). The frozen model keeps
-- calling the originals, which are not touched.

-- Spec #283, section 2: the class a report gives when it names no damage cause. The worst of what
-- the enforcement term, the overall quality and a herstel advice say. The term counts down in whole
-- years: years left = term - (current year - year of the report); the ranges count as their upper
-- bound (term05 = 5, term510 = 10, term1020 = 20). Up to 5 years left = e, up to 10 = d, up to 20 =
-- c, more = b. A report that names a damage cause keeps model-2024.1's ladder
-- (data.compute_damage_risk), without the countdown.
CREATE FUNCTION data.document_risk_2026_3(
    term report.enforcement_term,
    document_date date,
    overall_quality report.foundation_quality,
    recovery_advised boolean
) RETURNS data.foundation_risk_indication
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT GREATEST(
        CASE
            WHEN term IS NULL OR document_date IS NULL THEN NULL
            WHEN extract(year FROM data.enforcement_term_years(term))
                 - (extract(year FROM current_date) - extract(year FROM document_date)) <= 5
                THEN 'e'::data.foundation_risk_indication
            WHEN extract(year FROM data.enforcement_term_years(term))
                 - (extract(year FROM current_date) - extract(year FROM document_date)) <= 10
                THEN 'd'::data.foundation_risk_indication
            WHEN extract(year FROM data.enforcement_term_years(term))
                 - (extract(year FROM current_date) - extract(year FROM document_date)) <= 20
                THEN 'c'::data.foundation_risk_indication
            ELSE 'b'::data.foundation_risk_indication
        END,
        CASE overall_quality
            WHEN 'bad' THEN 'e'::data.foundation_risk_indication
            WHEN 'mediocre_bad' THEN 'd'::data.foundation_risk_indication
            WHEN 'mediocre' THEN 'c'::data.foundation_risk_indication
            WHEN 'tolerable' THEN 'c'::data.foundation_risk_indication
            WHEN 'good' THEN 'b'::data.foundation_risk_indication
            WHEN 'mediocre_good' THEN 'b'::data.foundation_risk_indication
        END,
        CASE WHEN recovery_advised THEN 'e'::data.foundation_risk_indication END
    );
$$;

-- Spec #283, section 4: the two indicative rules that read subsidence, copied from model-2024.1 with
-- one addition: `margin`, in mm/year, moves the velocity threshold further down. margin = 0 is the
-- frozen rule, case for case. The bacterial-decay rule is not in section 4 and keeps the frozen
-- function.
CREATE FUNCTION data.compute_indicative_drystand_risk_2026_3(
    ft report.foundation_type, velocity double precision, gwl double precision, has_recovery boolean, margin double precision
) RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication
        WHEN data.is_safe_foundation(ft) THEN 'a'::data.foundation_risk_indication

        -- Wood pile types (threshold: velocity -2.0, GWL 1.5)
        WHEN data.is_wood_pile(ft) AND velocity IS NULL AND gwl >= 1.5
            THEN 'c'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity IS NULL AND gwl < 1.5
            THEN 'b'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity < -2.0 - margin AND gwl >= 1.5
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity >= -2.0 - margin AND gwl >= 1.5
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity < -2.0 - margin AND gwl < 1.5
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity >= -2.0 - margin AND gwl < 1.5
            THEN 'c'::data.foundation_risk_indication

        -- Wood charger (threshold: velocity -1.0, GWL 2.5)
        WHEN ft = 'wood_charger' AND velocity IS NULL AND gwl >= 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity IS NULL AND gwl < 2.5
            THEN 'b'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity < -1.0 - margin AND gwl >= 2.5
            THEN 'e'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity < -1.0 - margin AND gwl < 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity >= -1.0 - margin AND gwl >= 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity >= -1.0 - margin AND gwl < 2.5
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;

CREATE FUNCTION data.compute_indicative_dewatering_risk_2026_3(
    ft report.foundation_type, velocity double precision, gwl double precision, has_recovery boolean, margin double precision
) RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication
        WHEN data.is_safe_foundation(ft) THEN 'a'::data.foundation_risk_indication

        -- No-pile family (threshold: velocity -1.0, GWL 0.6)
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity IS NULL AND gwl < 0.6
            THEN 'c'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity IS NULL AND gwl >= 0.6
            THEN 'b'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity < -1.0 - margin AND gwl < 0.6
            THEN 'e'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity < -1.0 - margin AND gwl >= 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity >= -1.0 - margin AND gwl < 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity >= -1.0 - margin AND gwl >= 0.6
            THEN 'c'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;

-- ---------------------------------------------------------------------------
-- 3. The model
-- ---------------------------------------------------------------------------

-- model-2026.3 for every pand, as one function with a switch per rule of the spec (Worker #283).
--
-- With every switch off it is model-2024.1 (data.model_risk_dynamic_all), column for column: that
-- is the control. Each switch is one section of the spec, so its effect can be measured on its own.
-- The matview data.model_risk_static_2026_3 calls it with every switch on. A SQL function with
-- constant arguments is inlined by the planner, so the switches cost nothing at run time.
--
-- The first 30 columns are the model's contract (the pointer view data.model_risk_static). The
-- columns after them say where each risk came from; they are not served, they explain.

CREATE FUNCTION data.model_risk_2026_3_rows(
    quickscan_rules boolean DEFAULT true,          -- spec sections 0 and 1: QuickScan gate, herstel first (#222)
    term_and_quality boolean DEFAULT true,         -- spec section 2 (#278): the report's class without a damage cause
    decay_floor boolean DEFAULT true,              -- spec section 3 (#278): decay found = at least d
    block_velocity boolean DEFAULT true,           -- spec section 4 (#236, V5): block median subsidence + margin
    fallback_to_dewatering boolean DEFAULT true,   -- spec section 5 (#242): the build-year estimate in dewatering depth
    label_by_source boolean DEFAULT true           -- spec section 5 (#235): a risk is labelled by the rule that produced it
)
RETURNS TABLE (
    building_id text,
    address_count integer,
    neighborhood_id text,
    construction_year integer,
    construction_year_reliability data.reliability,
    foundation_type report.foundation_type,
    foundation_type_reliability data.reliability,
    restoration_costs integer,
    drystand double precision,
    drystand_risk data.foundation_risk_indication,
    drystand_risk_reliability data.reliability,
    bio_infection_risk data.foundation_risk_indication,
    bio_infection_risk_reliability data.reliability,
    dewatering_depth double precision,
    dewatering_depth_risk data.foundation_risk_indication,
    dewatering_depth_risk_reliability data.reliability,
    unclassified_risk data.foundation_risk_indication,
    height numeric(10,2),
    velocity numeric,
    ground_water_level numeric,
    ground_level numeric(5,2),
    soil text,
    surface_area numeric(10,2),
    owner text,
    inquiry_id integer,
    inquiry_type report.inquiry_type,
    damage_cause report.foundation_damage_cause,
    enforcement_term double precision,
    overall_quality report.foundation_quality,
    recovery_type report.recovery_type,
    -- not served: where each value came from
    quickscan_gate text,
    drystand_source text,
    bio_infection_source text,
    dewatering_depth_source text,
    unclassified_source text
)
LANGUAGE sql STABLE AS $$
SELECT
    t.building_id,
    t.address_count,
    t.neighborhood_id,
    t.construction_year,
    t.construction_year_reliability,
    t.foundation_type,
    t.foundation_type_reliability,
    t.restoration_costs,
    t.drystand,

    t.dry AS drystand_risk,
    CASE
        WHEN NOT label_by_source THEN t.label_2024_1
        WHEN t.dry_source IN ('quickscan', 'research', 'herstel') THEN 'established'::data.reliability
        WHEN t.dry_source = 'cluster' THEN 'cluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS drystand_risk_reliability,

    t.bio AS bio_infection_risk,
    CASE
        WHEN NOT label_by_source THEN t.label_2024_1
        WHEN t.bio_source IN ('quickscan', 'research', 'herstel') THEN 'established'::data.reliability
        WHEN t.bio_source = 'cluster' THEN 'cluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS bio_infection_risk_reliability,

    t.dewatering_depth,

    COALESCE(t.dew, fb.dew) AS dewatering_depth_risk,
    CASE
        WHEN NOT label_by_source THEN t.label_2024_1
        WHEN t.dew_source IN ('quickscan', 'research', 'herstel') THEN 'established'::data.reliability
        WHEN t.dew_source = 'cluster' THEN 'cluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS dewatering_depth_risk_reliability,

    COALESCE(t.unc, fb.unc) AS unclassified_risk,

    t.height,
    t.velocity,
    t.ground_water_level,
    t.ground_level,
    t.soil,
    t.surface_area,
    t.owner,
    t.inquiry_id,
    t.inquiry_type,
    t.damage_cause,
    t.enforcement_term,
    t.overall_quality,
    t.recovery_type,

    t.gate AS quickscan_gate,
    t.dry_source AS drystand_source,
    t.bio_source AS bio_infection_source,
    COALESCE(t.dew_source, CASE WHEN fb.dew IS NOT NULL THEN 'build_year' END) AS dewatering_depth_source,
    COALESCE(t.unc_source, CASE WHEN fb.unc IS NOT NULL THEN 'build_year' END) AS unclassified_source
FROM (
    SELECT
        bp.building_id,
        bp.address_count,
        bp.neighborhood_id,
        cy.construction_year,
        CASE
            WHEN established.built_year IS NOT NULL THEN 'established'::data.reliability
            ELSE 'indicative'::data.reliability
        END AS construction_year_reliability,
        foundation_type.ft AS foundation_type,
        CASE
            WHEN established.foundation_type IS NOT NULL THEN 'established'::data.reliability
            WHEN cluster.foundation_type IS NOT NULL THEN 'cluster'::data.reliability
            WHEN supercluster.foundation_type IS NOT NULL THEN 'supercluster'::data.reliability
            ELSE 'indicative'::data.reliability
        END AS foundation_type_reliability,
        data.compute_restoration_costs(foundation_type.ft, bp.surface_area) AS restoration_costs,
        CASE
            WHEN established.wood_level IS NOT NULL AND established.groundwater_level IS NOT NULL
                THEN (established.wood_level::numeric - established.groundwater_level::numeric)::double precision
            WHEN cluster.wood_level IS NOT NULL AND cluster.groundwater_level IS NOT NULL
                THEN (cluster.wood_level::numeric - cluster.groundwater_level::numeric)::double precision
            WHEN foundation_type.ft = 'wood_charger' THEN gwl.level - 2.5::double precision
            WHEN data.is_wood_pile(foundation_type.ft) THEN gwl.level - 1.5::double precision
            ELSE NULL::double precision
        END AS drystand,
        CASE
            WHEN established.foundation_depth IS NOT NULL AND established.groundwater_level IS NOT NULL
                THEN (established.foundation_depth::numeric - established.groundwater_level::numeric - 0.6)::double precision
            WHEN cluster.foundation_depth IS NOT NULL AND cluster.groundwater_level IS NOT NULL
                THEN (cluster.foundation_depth::numeric - cluster.groundwater_level::numeric - 0.6)::double precision
            WHEN data.is_no_pile_family(foundation_type.ft) THEN gwl.level - 0.6::double precision
            ELSE NULL::double precision
        END AS dewatering_depth,

        -- Each risk: QuickScan, the pand's own report, a QuickScan under a leading onderzoek, the
        -- report of a pand in the same block, the indicative rule. First one that says something.
        COALESCE(qs.term, dry.own, qs.fallback, dry.block, dry.model) AS dry,
        CASE
            WHEN qs.term IS NOT NULL THEN 'quickscan'
            WHEN dry.own IS NOT NULL THEN CASE WHEN recovery.type IS NOT NULL THEN 'herstel' ELSE 'research' END
            WHEN qs.fallback IS NOT NULL THEN 'quickscan'
            WHEN dry.block IS NOT NULL THEN 'cluster'
            WHEN dry.model IS NOT NULL THEN 'model'
        END AS dry_source,

        COALESCE(qs.term, bio.own, qs.fallback, bio.block, bio.model) AS bio,
        CASE
            WHEN qs.term IS NOT NULL THEN 'quickscan'
            WHEN bio.own IS NOT NULL THEN CASE WHEN recovery.type IS NOT NULL THEN 'herstel' ELSE 'research' END
            WHEN qs.fallback IS NOT NULL THEN 'quickscan'
            WHEN bio.block IS NOT NULL THEN 'cluster'
            WHEN bio.model IS NOT NULL THEN 'model'
        END AS bio_source,

        COALESCE(qs.term, dew.own, qs.fallback, dew.block, dew.model) AS dew,
        CASE
            WHEN qs.term IS NOT NULL THEN 'quickscan'
            WHEN dew.own IS NOT NULL THEN CASE WHEN recovery.type IS NOT NULL THEN 'herstel' ELSE 'research' END
            WHEN qs.fallback IS NOT NULL THEN 'quickscan'
            WHEN dew.block IS NOT NULL THEN 'cluster'
            WHEN dew.model IS NOT NULL THEN 'model'
        END AS dew_source,

        COALESCE(qs.term, unc.own, qs.fallback, unc.block) AS unc,
        CASE
            WHEN qs.term IS NOT NULL THEN 'quickscan'
            WHEN unc.own IS NOT NULL THEN CASE WHEN recovery.type IS NOT NULL THEN 'herstel' ELSE 'research' END
            WHEN qs.fallback IS NOT NULL THEN 'quickscan'
            WHEN unc.block IS NOT NULL THEN 'cluster'
        END AS unc_source,

        -- The label model-2024.1 gives all three risks: by which sample exists, not by which term
        -- produced the value (Worker #235).
        CASE
            WHEN qs.term IS NOT NULL THEN 'established'::data.reliability
            WHEN established.id IS NOT NULL THEN 'established'::data.reliability
            WHEN cluster.id IS NOT NULL THEN 'cluster'::data.reliability
            ELSE 'indicative'::data.reliability
        END AS label_2024_1,

        bp.height::numeric(10,2) AS height,
        round(bs.velocity::numeric, 2) AS velocity,
        round(gwl.level::numeric, 2) AS ground_water_level,
        bp.ground_level,
        gr.code AS soil,
        bp.surface_area,
        bo.owner,
        established.id AS inquiry_id,
        established.inquiry_type,
        COALESCE(established.damage_cause, cluster.damage_cause) AS damage_cause,
        date_part('years', age((COALESCE(established.document_date, cluster.document_date)
            + data.enforcement_term_years(COALESCE(established.enforcement_term, cluster.enforcement_term)))::timestamp with time zone,
            CURRENT_TIMESTAMP)) AS enforcement_term,
        COALESCE(established.overall_quality, cluster.overall_quality) AS overall_quality,
        recovery.type AS recovery_type,
        gate.gate
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
        -- what 2026.3 reads beside the leading record: QuickScan and onderzoek dates, decay
        LEFT JOIN data.building_sample_2026_3 own_extra ON own_extra.building_id = bp.building_id
        -- Spec section 4: the block's subsidence = the median over the panden of the block that
        -- have an InSAR measurement, whatever their foundation
        LEFT JOIN (
            SELECT m.cluster_id, percentile_cont(0.5) WITHIN GROUP (ORDER BY v.velocity) AS velocity
              FROM data.building_cluster m
              JOIN data.building_subsidence v ON v.building_id = m.building_id
             WHERE v.velocity IS NOT NULL
             GROUP BY m.cluster_id
        ) block ON block.cluster_id = bc.cluster_id
        LEFT JOIN LATERAL (
            SELECT DISTINCT ON (rs.building_id) rs.building_id, rs.type
              FROM report.recovery_sample rs
             WHERE rs.building_id = bp.building_id
             ORDER BY rs.building_id, rs.create_date DESC
        ) recovery ON true
        -- Spec section 1: an executed, not deleted herstel beats any QuickScan (Worker #222). The
        -- herstel term of the risks keeps model-2024.1's choice (`recovery` above).
        LEFT JOIN LATERAL (
            SELECT true AS yes
              FROM report.recovery_sample rs
             WHERE rs.building_id = bp.building_id
               AND rs.status = 'executed'
               AND rs.delete_date IS NULL
             LIMIT 1
        ) executed_recovery ON true
        LEFT JOIN data.cluster_recovery_sample ON cluster_recovery_sample.cluster_id = bc.cluster_id,
        LATERAL (SELECT COALESCE(established.built_year, bp.construction_year_bag) AS construction_year) AS cy,
        LATERAL (SELECT round((bp.ground_level::double precision - bpl.depth)::numeric, 2)) AS pile_length(pile_length),
        -- Foundation type: as in model-2024.1 (spec, Scope).
        LATERAL (SELECT COALESCE(
            established.foundation_type,
            cluster.foundation_type,
            supercluster.foundation_type,
            data.indicative_foundation_type(cy.construction_year, bp.height, gr.code, bp.address_count)
        )) AS foundation_type(ft),

        -- Spec section 0: the QuickScan gate, as in the candidate of 20260928_004.
        LATERAL (SELECT CASE
            WHEN established.facade_scan_risk IS NULL THEN NULL
            WHEN own_extra.fo_date >= current_date - interval '5 years' THEN 'fo_leading'
            WHEN own_extra.qs_date >= current_date - interval '3 years' THEN 'qs_valid'
            ELSE 'qs_expired'
        END) AS gate(gate),
        LATERAL (SELECT
            CASE
                WHEN NOT quickscan_rules
                    THEN established.facade_scan_risk::text::data.foundation_risk_indication
                WHEN gate.gate = 'qs_valid' AND executed_recovery.yes IS NULL
                    THEN established.facade_scan_risk::text::data.foundation_risk_indication
            END AS term,
            CASE
                WHEN quickscan_rules AND gate.gate = 'fo_leading'
                 AND own_extra.qs_date >= current_date - interval '3 years'
                 AND executed_recovery.yes IS NULL
                    THEN established.facade_scan_risk::text::data.foundation_risk_indication
            END AS fallback
        ) AS qs,

        -- Spec section 4 (V5): for the drystand and dewatering rules, a measured pand takes its
        -- block's median and the threshold moves 0.3 mm/year; an unmeasured pand stays unmeasured.
        LATERAL (SELECT
            CASE
                WHEN block_velocity AND bs.velocity IS NOT NULL THEN COALESCE(block.velocity, bs.velocity)
                ELSE bs.velocity
            END AS velocity,
            CASE WHEN block_velocity THEN 0.3::double precision ELSE 0::double precision END AS margin
        ) AS subsidence,

        -- Spec section 2: with no damage cause, the report's term, quality and herstel advice give a
        -- class, for the risks that belong to the foundation family; the same for the report of a
        -- pand in the same block. Spec section 3: decay found by the governing report = at least d.
        LATERAL (SELECT
            CASE WHEN term_and_quality AND established.id IS NOT NULL AND established.damage_cause IS NULL
                 THEN data.document_risk_2026_3(established.enforcement_term, established.document_date,
                                                established.overall_quality, established.recovery_advised) END AS own,
            CASE WHEN term_and_quality AND cluster.id IS NOT NULL AND cluster.damage_cause IS NULL
                 THEN data.document_risk_2026_3(cluster.enforcement_term, cluster.document_date,
                                                cluster.overall_quality, cluster.recovery_advised) END AS block
        ) AS doc,

        LATERAL (SELECT
            CASE
                WHEN decay_floor AND own_extra.fungus_decay AND recovery.type IS NULL THEN GREATEST(r.own, 'd'::data.foundation_risk_indication)
                ELSE r.own
            END AS own,
            r.block,
            data.compute_indicative_drystand_risk_2026_3(
                foundation_type.ft, subsidence.velocity, gwl.level, recovery.type IS NOT NULL, subsidence.margin) AS model
          FROM (SELECT
                    COALESCE(
                        data.compute_damage_risk(
                            recovery.type IS NOT NULL, established.damage_cause,
                            ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[],
                            established.enforcement_term, established.overall_quality, established.recovery_advised),
                        CASE WHEN data.is_wood_family(foundation_type.ft) THEN doc.own END) AS own,
                    COALESCE(
                        data.compute_damage_risk(
                            false, cluster.damage_cause,
                            ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[],
                            cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised),
                        CASE WHEN data.is_wood_family(foundation_type.ft) THEN doc.block END) AS block
               ) r
        ) AS dry,

        LATERAL (SELECT
            CASE
                WHEN decay_floor AND own_extra.bio_decay AND recovery.type IS NULL THEN GREATEST(r.own, 'd'::data.foundation_risk_indication)
                ELSE r.own
            END AS own,
            r.block,
            data.compute_indicative_bio_risk(
                foundation_type.ft, pile_length.pile_length, bs.velocity, recovery.type IS NOT NULL) AS model
          FROM (SELECT
                    COALESCE(
                        data.compute_damage_risk(
                            recovery.type IS NOT NULL, established.damage_cause,
                            ARRAY['bio_infection']::report.foundation_damage_cause[],
                            established.enforcement_term, established.overall_quality, established.recovery_advised),
                        CASE WHEN data.is_wood_family(foundation_type.ft) THEN doc.own END) AS own,
                    COALESCE(
                        data.compute_damage_risk(
                            false, cluster.damage_cause,
                            ARRAY['bio_infection']::report.foundation_damage_cause[],
                            cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised),
                        CASE WHEN data.is_wood_family(foundation_type.ft) THEN doc.block END) AS block
               ) r
        ) AS bio,

        LATERAL (SELECT
            COALESCE(
                data.compute_damage_risk(
                    recovery.type IS NOT NULL, established.damage_cause,
                    ARRAY['drainage']::report.foundation_damage_cause[],
                    established.enforcement_term, established.overall_quality, established.recovery_advised),
                CASE WHEN data.is_no_pile_family(foundation_type.ft) THEN doc.own END) AS own,
            COALESCE(
                data.compute_damage_risk(
                    false, cluster.damage_cause,
                    ARRAY['drainage']::report.foundation_damage_cause[],
                    cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised),
                CASE WHEN data.is_no_pile_family(foundation_type.ft) THEN doc.block END) AS block,
            data.compute_indicative_dewatering_risk_2026_3(
                foundation_type.ft, subsidence.velocity, gwl.level, recovery.type IS NOT NULL, subsidence.margin) AS model
        ) AS dew,

        -- The overall class from the report: unchanged from model-2024.1.
        LATERAL (SELECT
            data.compute_unclassified_risk(
                recovery.type IS NOT NULL, 'a', 'e',
                established.enforcement_term, established.overall_quality,
                established.recovery_advised, established.damage_cause) AS own,
            data.compute_unclassified_risk(
                cluster_recovery_sample.type IS NOT NULL, 'e', 'd',
                cluster.enforcement_term, cluster.overall_quality,
                cluster.recovery_advised, cluster.damage_cause) AS block
        ) AS unc
) t,
-- The build-year estimate, for a pand none of the rules above says anything about (issue #1002:
-- before 1970 = d, from 1970 = b). Model-2024.1 writes it into the overall class, where it reads as
-- research. Spec section 5 (#242): it goes to dewatering_depth_risk, labelled indicative, and the
-- overall class is no longer filled by an estimate.
LATERAL (SELECT
    CASE
        WHEN t.unc IS NULL AND t.dry IS NULL AND t.bio IS NULL AND t.dew IS NULL THEN
            CASE
                WHEN t.construction_year < 1970 THEN 'd'::data.foundation_risk_indication
                WHEN t.construction_year >= 1970 THEN 'b'::data.foundation_risk_indication
            END
    END AS letter
) AS est,
LATERAL (SELECT
    CASE WHEN fallback_to_dewatering THEN est.letter END AS dew,
    CASE WHEN NOT fallback_to_dewatering THEN est.letter END AS unc
) AS fb;
$$;

-- ---------------------------------------------------------------------------
-- The output. data.model_risk_static_2026_3 was built on 2026-10-12 (20261012_002) as "the 2024.1
-- row of every pand, with the QuickScan panden recomputed". That shape cannot carry rules that
-- change every pand, and a matview's query cannot be altered, so it is dropped and built again on
-- the function above. Nothing reads it: the pointer view still selects from the 2024.1 matview.
-- If something does depend on it by now, the DROP fails and the whole file rolls back.
-- ---------------------------------------------------------------------------
DROP MATERIALIZED VIEW data.model_risk_static_2026_3;

CREATE MATERIALIZED VIEW data.model_risk_static_2026_3 AS
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
    height::numeric(10,2) AS height,          -- a function result carries no precision; the pointer view needs the exact type
    velocity,
    ground_water_level,
    ground_level::numeric(5,2) AS ground_level,
    soil,
    surface_area::numeric(10,2) AS surface_area,
    owner,
    inquiry_id,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    recovery_type,
    -- Not part of the contract: where each risk came from (quickscan, research, herstel, cluster,
    -- model, build_year) and the QuickScan gate. The pointer view selects the 30 columns above by
    -- name, so these are not served; they are here to answer "why is this pand a d" without a
    -- second run of the model.
    quickscan_gate,
    drystand_source,
    bio_infection_source,
    dewatering_depth_source,
    unclassified_source
FROM data.model_risk_2026_3_rows(
    quickscan_rules => true,
    term_and_quality => true,
    decay_floor => true,
    block_velocity => true,
    fallback_to_dewatering => true,
    label_by_source => true
)
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW data.model_risk_static_2026_3 IS
'model-2026.3 for every pand: data.model_risk_2026_3_rows() with every rule on. The first 30 columns are the model contract (the pointer view selects them by name); the columns after them say where each risk came from and are not served. Refreshed by Windmill f/fundermaps/data/refresh_risk_model, after the sample matviews. See docs/model-versioning.md.';

CREATE UNIQUE INDEX model_risk_static_2026_3_pkey
    ON data.model_risk_static_2026_3 (building_id);
CREATE INDEX model_risk_static_2026_3_neighborhood_id_idx
    ON data.model_risk_static_2026_3 (neighborhood_id);

-- The pointer view is switched with CREATE OR REPLACE VIEW, which only works when the 30 columns it
-- selects have exactly the names, types and order of the 2024.1 matview's columns.
DO $$
DECLARE
    differing integer;
BEGIN
    SELECT count(*) INTO differing
      FROM (SELECT attnum, attname, atttypid, atttypmod FROM pg_attribute
             WHERE attrelid = 'data.model_risk_static_2024_1'::regclass AND attnum > 0 AND NOT attisdropped) o
      FULL JOIN (SELECT attnum, attname, atttypid, atttypmod FROM pg_attribute
                  WHERE attrelid = 'data.model_risk_static_2026_3'::regclass AND attnum BETWEEN 1 AND 30 AND NOT attisdropped) n
        USING (attnum, attname, atttypid, atttypmod)
     WHERE o.attnum IS NULL OR n.attnum IS NULL;
    IF differing > 0 THEN
        RAISE EXCEPTION 'the first 30 columns of data.model_risk_static_2026_3 are not the columns of data.model_risk_static_2024_1 (% differ)', differing;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Build and record. A schema-only database (the CI bootstrap from schema.sql) has the sample and
-- model matviews unpopulated, and reading them errors; there nothing is built, like 2024.1 itself.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    populated boolean := (SELECT bool_and(relispopulated) FROM pg_class
                           WHERE oid IN ('data.building_sample'::regclass,
                                         'data.cluster_sample'::regclass,
                                         'data.supercluster_sample'::regclass,
                                         'data.model_risk_static_2024_1'::regclass));
    rows_new bigint;
    rows_old bigint;
    fingerprint jsonb;
BEGIN
    IF populated THEN
        REFRESH MATERIALIZED VIEW data.building_sample_2026_3;
        ANALYZE data.building_sample_2026_3;
        REFRESH MATERIALIZED VIEW data.model_risk_static_2026_3;
        ANALYZE data.model_risk_static_2026_3;

        SELECT count(*) INTO rows_new FROM data.model_risk_static_2026_3;
        SELECT count(*) INTO rows_old FROM data.model_risk_static_2024_1;
        IF rows_new <> rows_old THEN
            RAISE EXCEPTION 'model-2026.3 has % rows, model-2024.1 has %: one row per pand expected', rows_new, rows_old;
        END IF;

        SELECT jsonb_build_object(
                   'note', 'row counts are fingerprints taken when this row was last built; differences are against model-2024.1 at that moment',
                   'rows', rows_new,
                   'panden_letter_changed', count(*) FILTER (WHERE
                        (n.drystand_risk, n.bio_infection_risk, n.dewatering_depth_risk, n.unclassified_risk)
                        IS DISTINCT FROM (o.drystand_risk, o.bio_infection_risk, o.dewatering_depth_risk, o.unclassified_risk)),
                   'panden_label_changed', count(*) FILTER (WHERE
                        (n.drystand_risk_reliability, n.bio_infection_risk_reliability, n.dewatering_depth_risk_reliability)
                        IS DISTINCT FROM (o.drystand_risk_reliability, o.bio_infection_risk_reliability, o.dewatering_depth_risk_reliability)),
                   'panden_type_changed', count(*) FILTER (WHERE n.foundation_type IS DISTINCT FROM o.foundation_type),
                   'building_sample', jsonb_build_object('rows', (SELECT count(*) FROM data.building_sample)),
                   'inquiry', jsonb_build_object('rows', (SELECT count(*) FROM report.inquiry)))
          INTO fingerprint
          FROM data.model_risk_static_2026_3 n
          JOIN data.model_risk_static_2024_1 o USING (building_id);
    ELSE
        fingerprint := jsonb_build_object(
            'note', 'not built: sample/model matviews unpopulated (schema-only database); refresh data.building_sample_2026_3, then data.model_risk_static_2026_3');
    END IF;

    -- An upsert: on prod the row exists since 20261012_002; a database bootstrapped from a
    -- schema.sql that already contains that migration has no registry rows at all.
    INSERT INTO data.model_version (slug, title, status, is_default, notes, inputs)
    VALUES ('model-2026.3', 'Foundation risk model 2026.3', 'candidate', false,
            'model-2024.1 with the risk rules of the spec, Worker #283; each section is a switch of data.model_risk_2026_3_rows(). 0-1: the QuickScan gate (3-year window, a funderingsonderzoek from the last 5 years leads, addendum only) and executed herstel first (#222). 2: without a damage cause the report''s enforcement term (counting down in whole years), quality and herstel advice give the risk of the foundation family, own report and block (#278). 3: decay found = at least d (#278). 4: block median subsidence with a 0.3 mm/year margin for drystand and dewatering (#236, V5). 5: risk labels by the rule that produced the value (#235); the build-year estimate in dewatering depth (#242). Foundation type as in 2024.1. Every switch off is model-2024.1. Output: data.model_risk_static_2026_3.',
            fingerprint)
    ON CONFLICT (slug) DO UPDATE
       SET title = EXCLUDED.title,
           notes = EXCLUDED.notes,
           inputs = EXCLUDED.inputs;
END $$;

-- Hand over last: a refresh runs the query as the matview's owner, and the first build above has
-- to work wherever this file runs (on a database bootstrapped from schema.sql the fundermaps role
-- owns nothing). On prod fundermaps owns everything these objects read.
ALTER MATERIALIZED VIEW data.building_sample_2026_3 OWNER TO fundermaps;
ALTER MATERIALIZED VIEW data.model_risk_static_2026_3 OWNER TO fundermaps;
ALTER FUNCTION data.document_risk_2026_3(report.enforcement_term, date, report.foundation_quality, boolean) OWNER TO fundermaps;
ALTER FUNCTION data.compute_indicative_drystand_risk_2026_3(report.foundation_type, double precision, double precision, boolean, double precision) OWNER TO fundermaps;
ALTER FUNCTION data.compute_indicative_dewatering_risk_2026_3(report.foundation_type, double precision, double precision, boolean, double precision) OWNER TO fundermaps;
ALTER FUNCTION data.model_risk_2026_3_rows(boolean, boolean, boolean, boolean, boolean, boolean) OWNER TO fundermaps;

-- The refresh flow runs as fundermaps_windmill. The application roles get nothing here: they read
-- the pointer view, never a versioned matview.
GRANT SELECT, MAINTAIN ON data.building_sample_2026_3, data.model_risk_static_2026_3
    TO fundermaps_windmill;
