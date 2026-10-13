-- model-2026.3 with every decided rule, as its own model: own function, own helper copies, own
-- sample extras. Still a candidate: nothing is served from it and the default does not move here.
--
-- Why (Yorick, 2026-10-12): "holding the switch and ship everything at once". The 2026.3 that was
-- built that morning (20261012_002) holds the QuickScan rules only, as "the 2024.1 row of every
-- pand, with the QuickScan panden recomputed". The rules below change panden everywhere, so the
-- version gets the full model SQL, and the switch waits until all of it is reviewed.
--
-- The rules, each behind its own switch of data.model_risk_2026_3_rows():
--   quickscan_rules           the candidate of 20260923_002 / 20260928_003 / 20260928_004 (Worker #222):
--                             a QuickScan counts for 3 years, a funderingsonderzoek from the last
--                             5 years leads, only an addendum is a QuickScan, executed herstel first
--   type_per_field            Worker #243: a foundation type the leading report does not name comes
--                             from the best report that does (pand, block and wider block alike)
--   term_and_quality          Worker #278: enforcement term, overall quality and herstel advice count
--                             without a damage cause, for the risks of the foundation family
--                             (wood: drystand + bio; shallow: dewatering depth)
--   term_and_quality_cluster  ... also when the report is that of another pand in the same block
--   term_countdown            Worker #278: the term counts down from the date of the report
--   decay_floor               Worker #278 (addition): decay found in the wood = at least d
--   measured_settlement       Worker #278 (addition): settlement measured at the pand before InSAR
--   block_velocity            Worker #236, variant V5: a measured pand takes the median subsidence of
--                             its block, and the thresholds get a margin of 0.3 mm/year; an unmeasured
--                             pand stays unmeasured
--   fallback_in_family        Worker #242: the build-year estimate goes to the foundation's own risk
--                             (shallow: dewatering depth; wood: drystand + bio), not the overall class
--   label_by_source           Worker #235: a risk is labelled by the rule that produced its value
--
-- With every switch off the function IS model-2024.1, and with only quickscan_rules on it is the
-- build of 20261012_002. Both were checked on a full copy of the model's inputs (taken from prod
-- 2026-10-12 18:24 CEST, PostGIS 18): 11,321,489 rows, all 30 columns, 0 differences, twice.
--
-- Built on what was decided; where nothing was decided the rule is left out or behind its own
-- switch (see the pull request): skew is not used (no thresholds), the other foundation families
-- (steel, combined, other) keep model-2024.1's place for the build-year estimate, per-field
-- selection is for the foundation type only, the overall class (compute_unclassified_risk) is
-- untouched, and the QuickScan outcome stays a to e (Worker #213).
--
-- The frozen model is not touched: data.compute_damage_risk and the three indicative functions keep
-- their text; model-2026.3 calls its own copies. The helpers no rule changes (the family
-- predicates, indicative_foundation_type, compute_restoration_costs, compute_unclassified_risk,
-- enforcement_term_years) are still shared by both models.
--
-- Cost: model-2026.3 is a full national run now, about as long as the model-2024.1 refresh, and
-- three small sample matviews are refreshed with the three existing ones. On prod the first build
-- in this file takes about as long as one model refresh; it locks nothing a reader uses.

-- ---------------------------------------------------------------------------
-- 1. What the model reads beside the leading record
-- ---------------------------------------------------------------------------

-- What model-2026.3 reads from the reports BESIDE the leading record of data.building_sample,
-- data.cluster_sample and data.supercluster_sample (which it keeps reading, like model-2024.1).
-- Three small matviews, refreshed in the same flow step as the three frozen ones.

CREATE MATERIALIZED VIEW data.building_sample_2026_3 AS
WITH typed AS (
    -- Worker #243: the foundation type of the highest-ranked report that names one. Same ranking
    -- and the same "not older than the building" filter as data.building_sample; the sample id
    -- settles a tie, so the choice is the same at every refresh.
    SELECT DISTINCT ON (b.external_id)
           b.external_id AS building_id,
           is2.foundation_type
      FROM report.inquiry_sample is2
      JOIN report.inquiry i ON is2.inquiry_id = i.id
      JOIN geocoder.building b ON b.external_id = is2.building_id::text
     WHERE i.document_date >= (b.built_year::date - interval '5 years')
       AND is2.foundation_type IS NOT NULL
     ORDER BY b.external_id,
              CASE i.type
                  WHEN 'foundation_research' THEN 0
                  WHEN 'inspectionpit' THEN 1
                  WHEN 'second_opinion' THEN 2
                  WHEN 'note' THEN 3
                  WHEN 'additional_research' THEN 4
                  WHEN 'demolition_research' THEN 5
                  WHEN 'architectural_research' THEN 6
                  WHEN 'archive_research' THEN 7
                  WHEN 'quickscan' THEN 8
                  ELSE 100
              END, i.document_date DESC, is2.id DESC
),
dated AS (
    -- The dates the QuickScan rules need, read exactly as the candidate of 20260928_004 read them:
    -- the QuickScan date is the newest QuickScan addendum (inquiry type facade_scan) that carries a
    -- class; the onderzoek date is the newest funderingsonderzoek of the pand.
    SELECT s.building_id::text AS building_id,
           max(i.document_date) FILTER (WHERE s.facade_scan_risk IS NOT NULL AND i.type = 'facade_scan') AS qs_date,
           max(i.document_date) FILTER (WHERE i.type IN ('foundation_research', 'inspectionpit', 'second_opinion', 'additional_research')) AS fo_date,
           -- Worker #278 (addition of 2026-10-12): decay found in the wood, and the settlement
           -- measured at the pand (the newest report that has one).
           COALESCE(bool_or(s.wood_encroachment IN ('fungus_infection', 'bio_fungus_infection')), false) AS fungus_decay,
           COALESCE(bool_or(s.wood_encroachment IN ('bio_infection', 'bio_fungus_infection')), false) AS bio_decay,
           (array_agg(s.settlement_speed ORDER BY i.document_date DESC, s.id DESC) FILTER (WHERE s.settlement_speed IS NOT NULL))[1] AS settlement_speed
      FROM report.inquiry_sample s
      JOIN report.inquiry i ON i.id = s.inquiry_id
     GROUP BY 1
)
SELECT d.building_id,
       t.foundation_type AS foundation_type_best,
       d.qs_date,
       d.fo_date,
       d.fungus_decay,
       d.bio_decay,
       d.settlement_speed
  FROM dated d
  LEFT JOIN typed t USING (building_id)
WITH NO DATA;

CREATE UNIQUE INDEX building_sample_2026_3_pkey ON data.building_sample_2026_3 (building_id);

CREATE MATERIALIZED VIEW data.cluster_sample_2026_3 AS
SELECT DISTINCT ON (bc.cluster_id)
       bc.cluster_id,
       is2.foundation_type AS foundation_type_best
  FROM data.building_cluster bc
  JOIN geocoder.building b ON b.external_id = bc.building_id
  JOIN report.inquiry_sample is2 ON is2.building_id::text = b.external_id
  JOIN report.inquiry i ON is2.inquiry_id = i.id
 WHERE i.document_date >= (b.built_year::date - interval '5 years')
   AND is2.foundation_type IS NOT NULL
 ORDER BY bc.cluster_id,
          CASE i.type
              WHEN 'foundation_research' THEN 0
              WHEN 'inspectionpit' THEN 1
              WHEN 'second_opinion' THEN 2
              WHEN 'note' THEN 3
              WHEN 'additional_research' THEN 4
              WHEN 'demolition_research' THEN 5
              WHEN 'architectural_research' THEN 6
              WHEN 'archive_research' THEN 7
              WHEN 'quickscan' THEN 8
              ELSE 100
          END, i.document_date DESC, is2.id DESC
WITH NO DATA;

CREATE UNIQUE INDEX cluster_sample_2026_3_pkey ON data.cluster_sample_2026_3 (cluster_id);

CREATE MATERIALIZED VIEW data.supercluster_sample_2026_3 AS
SELECT DISTINCT ON (s.supercluster_id)
       s.supercluster_id,
       is2.foundation_type AS foundation_type_best
  FROM data.supercluster s
  JOIN data.building_cluster bc ON bc.cluster_id = s.cluster_id
  JOIN geocoder.building b ON b.external_id = bc.building_id
  JOIN report.inquiry_sample is2 ON is2.building_id::text = b.external_id
  JOIN report.inquiry i ON is2.inquiry_id = i.id
 WHERE i.document_date >= (b.built_year::date - interval '5 years')
   AND is2.foundation_type IS NOT NULL
 ORDER BY s.supercluster_id,
          CASE i.type
              WHEN 'foundation_research' THEN 0
              WHEN 'inspectionpit' THEN 1
              WHEN 'second_opinion' THEN 2
              WHEN 'note' THEN 3
              WHEN 'additional_research' THEN 4
              WHEN 'demolition_research' THEN 5
              WHEN 'architectural_research' THEN 6
              WHEN 'archive_research' THEN 7
              WHEN 'quickscan' THEN 8
              ELSE 100
          END, i.document_date DESC, is2.id DESC
WITH NO DATA;

CREATE UNIQUE INDEX supercluster_sample_2026_3_pkey ON data.supercluster_sample_2026_3 (supercluster_id);

-- ---------------------------------------------------------------------------
-- 2. Own copies of the helpers whose rules change
-- ---------------------------------------------------------------------------

-- model-2026.3: its own copies of the helpers whose rules change. The frozen model keeps calling
-- the originals (data.compute_damage_risk, data.compute_indicative_*), which are not touched.

-- The class an enforcement term gives. Without the countdown: the term as written in the report,
-- exactly as data.compute_damage_risk reads it. With the countdown (Don, 2026-10-12, Worker #278):
-- the years that are LEFT today, counted from the date of the report ("25 years" in a report of
-- 2021 is 20 years in 2026). Up to 5 years left = e, up to 10 = d, up to 20 = c, more = b; a term
-- that has run out is e. A report is never dated in the future, so the countdown can only keep a
-- class or make it worse.
CREATE FUNCTION data.term_class_2026_3(term report.enforcement_term, document_date date, countdown boolean)
RETURNS data.foundation_risk_indication
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN term IS NULL THEN NULL
        WHEN countdown AND document_date IS NOT NULL THEN
            CASE
                WHEN document_date + data.enforcement_term_years(term) <= current_date + interval '5 years'
                    THEN 'e'::data.foundation_risk_indication
                WHEN document_date + data.enforcement_term_years(term) <= current_date + interval '10 years'
                    THEN 'd'::data.foundation_risk_indication
                WHEN document_date + data.enforcement_term_years(term) <= current_date + interval '20 years'
                    THEN 'c'::data.foundation_risk_indication
                ELSE 'b'::data.foundation_risk_indication
            END
        WHEN term IN ('term05', 'term5') THEN 'e'::data.foundation_risk_indication
        WHEN term IN ('term510', 'term10') THEN 'd'::data.foundation_risk_indication
        WHEN term IN ('term1020', 'term15', 'term20') THEN 'c'::data.foundation_risk_indication
        WHEN term IN ('term25', 'term30', 'term40') THEN 'b'::data.foundation_risk_indication
    END;
$$;

-- The risk a report gives: herstel = a; otherwise the worst of what the enforcement term, the
-- overall quality and a herstel advice say. `applies` is decided by the caller: the damage cause
-- belongs to this risk (as in model-2024.1) or, under Worker #278, there is no damage cause and the
-- risk belongs to the foundation family. With countdown = false and applies = "the damage cause
-- belongs to this risk" this is data.compute_damage_risk, case for case.
CREATE FUNCTION data.compute_damage_risk_2026_3(
    has_recovery boolean,
    applies boolean,
    term report.enforcement_term,
    document_date date,
    countdown boolean,
    overall_quality report.foundation_quality,
    recovery_advised boolean
) RETURNS data.foundation_risk_indication
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication
        WHEN applies THEN GREATEST(
            data.term_class_2026_3(term, document_date, countdown),
            CASE overall_quality
                WHEN 'bad' THEN 'e'::data.foundation_risk_indication
                WHEN 'mediocre_bad' THEN 'd'::data.foundation_risk_indication
                WHEN 'mediocre' THEN 'c'::data.foundation_risk_indication
                WHEN 'tolerable' THEN 'c'::data.foundation_risk_indication
                WHEN 'good' THEN 'b'::data.foundation_risk_indication
                WHEN 'mediocre_good' THEN 'b'::data.foundation_risk_indication
            END,
            CASE WHEN recovery_advised THEN 'e'::data.foundation_risk_indication END
        )
    END;
$$;

-- The three indicative rules, copied from model-2024.1 with one addition: `margin`, in mm/year,
-- moves the subsidence threshold further down (Worker #236: a value just past the threshold is
-- noise, not a different class). margin = 0 is the frozen rule, case for case.
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

CREATE FUNCTION data.compute_indicative_bio_risk_2026_3(
    ft report.foundation_type, pile_length numeric, velocity double precision, has_recovery boolean, margin double precision
) RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication

        -- Short piles (≤12m)
        WHEN data.is_wood_family(ft) AND pile_length <= 12 AND velocity < -2.0 - margin
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length <= 12
            THEN 'd'::data.foundation_risk_indication

        -- Medium piles (12-15m)
        WHEN data.is_wood_family(ft) AND pile_length > 12 AND pile_length <= 15
             AND velocity < -2.0 - margin
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length > 12 AND pile_length <= 15
            THEN 'c'::data.foundation_risk_indication

        -- Long piles (>15m)
        WHEN data.is_wood_family(ft) AND pile_length > 15 AND velocity < -2.0 - margin
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length > 15
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
        WHEN data.is_no_pile_family(ft) AND velocity IS NULL AND gwl < 0.6
            THEN 'c'::data.foundation_risk_indication
        WHEN data.is_no_pile_family(ft) AND velocity IS NULL AND gwl >= 0.6
            THEN 'b'::data.foundation_risk_indication
        WHEN data.is_no_pile_family(ft) AND velocity < -1.0 - margin AND gwl < 0.6
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_no_pile_family(ft) AND velocity < -1.0 - margin AND gwl >= 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_no_pile_family(ft) AND velocity >= -1.0 - margin AND gwl < 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_no_pile_family(ft) AND velocity >= -1.0 - margin AND gwl >= 0.6
            THEN 'c'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;

-- ---------------------------------------------------------------------------
-- 3. The model
-- ---------------------------------------------------------------------------

-- model-2026.3 for every pand, as one function with a switch per rule.
--
-- With every switch off it is model-2024.1 (data.model_risk_dynamic_all), column for column: that
-- is the control. Each switch is one decided rule, so its effect can be measured on its own. The
-- matview data.model_risk_static_2026_3 calls it with every switch on. A SQL function with constant
-- arguments is inlined by the planner, so the switches cost nothing at run time.
--
-- The first 30 columns are the model's contract (the pointer view data.model_risk_static). The
-- columns after them say where each risk came from; they are not served, they explain.

CREATE FUNCTION data.model_risk_2026_3_rows(
    quickscan_rules boolean DEFAULT true,        -- 20260923_002 + 20260928_003 + 20260928_004 (#222)
    type_per_field boolean DEFAULT true,         -- Worker #243
    term_and_quality boolean DEFAULT true,       -- Worker #278: term and quality count without a damage cause
    term_and_quality_cluster boolean DEFAULT true, -- ... also for the report of a pand in the same block
    term_countdown boolean DEFAULT true,         -- Worker #278: the term counts down from the report date
    decay_floor boolean DEFAULT true,            -- Worker #278 (addition): decay found in the wood = at least d
    measured_settlement boolean DEFAULT true,    -- Worker #278 (addition): settlement measured at the pand before InSAR
    block_velocity boolean DEFAULT true,         -- Worker #236, variant V5
    fallback_in_family boolean DEFAULT true,     -- Worker #242
    label_by_source boolean DEFAULT true         -- Worker #235
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

    COALESCE(t.dry, fb.dry) AS drystand_risk,
    CASE
        WHEN NOT label_by_source THEN t.label_2024_1
        WHEN t.dry_source IN ('quickscan', 'research', 'herstel') THEN 'established'::data.reliability
        WHEN t.dry_source = 'cluster' THEN 'cluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS drystand_risk_reliability,

    COALESCE(t.bio, fb.bio) AS bio_infection_risk,
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
    COALESCE(t.dry_source, CASE WHEN fb.dry IS NOT NULL THEN 'build_year' END) AS drystand_source,
    COALESCE(t.bio_source, CASE WHEN fb.bio IS NOT NULL THEN 'build_year' END) AS bio_infection_source,
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
            WHEN own_type.ft IS NOT NULL THEN 'established'::data.reliability
            WHEN cluster_type.ft IS NOT NULL THEN 'cluster'::data.reliability
            WHEN supercluster_type.ft IS NOT NULL THEN 'supercluster'::data.reliability
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
        COALESCE(qs.term, CASE WHEN lift.dry THEN 'd'::data.foundation_risk_indication ELSE chain.dry END) AS dry,
        CASE
            WHEN qs.term IS NOT NULL THEN 'quickscan'
            WHEN lift.dry THEN 'research'
            WHEN dry.own IS NOT NULL THEN CASE WHEN recovery.type IS NOT NULL THEN 'herstel' ELSE 'research' END
            WHEN qs.fallback IS NOT NULL THEN 'quickscan'
            WHEN dry.block IS NOT NULL THEN 'cluster'
            WHEN dry.model IS NOT NULL THEN 'model'
        END AS dry_source,

        COALESCE(qs.term, CASE WHEN lift.bio THEN 'd'::data.foundation_risk_indication ELSE chain.bio END) AS bio,
        CASE
            WHEN qs.term IS NOT NULL THEN 'quickscan'
            WHEN lift.bio THEN 'research'
            WHEN bio.own IS NOT NULL THEN CASE WHEN recovery.type IS NOT NULL THEN 'herstel' ELSE 'research' END
            WHEN qs.fallback IS NOT NULL THEN 'quickscan'
            WHEN bio.block IS NOT NULL THEN 'cluster'
            WHEN bio.model IS NOT NULL THEN 'model'
        END AS bio_source,

        COALESCE(qs.term, chain.dew) AS dew,
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
        -- what 2026.3 reads beside the leading record
        LEFT JOIN data.building_sample_2026_3 own_extra ON own_extra.building_id = bp.building_id
        LEFT JOIN data.cluster_sample_2026_3 cluster_extra ON cluster_extra.cluster_id = bc.cluster_id
        LEFT JOIN data.supercluster_sample_2026_3 supercluster_extra ON supercluster_extra.supercluster_id = bsc.supercluster_id
        -- Worker #236: the block's subsidence = the median over the panden of the block that have
        -- an InSAR measurement, whatever their foundation
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
        -- The QuickScan gate only: an executed, not deleted herstel (Worker #222). The herstel term
        -- of the risks keeps model-2024.1's choice (`recovery` above).
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

        -- Foundation type. Worker #243: a type the pand's leading report does not name is taken
        -- from the best report that does name one, before anything is derived from neighbours.
        LATERAL (SELECT COALESCE(established.foundation_type,
                                 CASE WHEN type_per_field THEN own_extra.foundation_type_best END)) AS own_type(ft),
        LATERAL (SELECT COALESCE(cluster.foundation_type,
                                 CASE WHEN type_per_field THEN cluster_extra.foundation_type_best END)) AS cluster_type(ft),
        LATERAL (SELECT COALESCE(supercluster.foundation_type,
                                 CASE WHEN type_per_field THEN supercluster_extra.foundation_type_best END)) AS supercluster_type(ft),
        LATERAL (SELECT COALESCE(
            own_type.ft,
            cluster_type.ft,
            supercluster_type.ft,
            data.indicative_foundation_type(cy.construction_year, bp.height, gr.code, bp.address_count)
        )) AS foundation_type(ft),

        -- The QuickScan rules (Don, 2026-07-27 / 09-06 / 09-11; Yorick, 2026-09-23 and 10-02), as in
        -- the candidate of 20260928_004.
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

        -- The subsidence the indicative rules use. Worker #236, variant V5: a measured pand takes
        -- its block's median, an unmeasured pand stays unmeasured. Worker #278 (addition): a
        -- settlement measured at the pand in a report goes before InSAR.
        LATERAL (SELECT
            CASE
                WHEN measured_settlement AND own_extra.settlement_speed IS NOT NULL THEN own_extra.settlement_speed
                WHEN block_velocity AND bs.velocity IS NOT NULL THEN COALESCE(block.velocity, bs.velocity)
                ELSE bs.velocity
            END AS velocity,
            CASE WHEN block_velocity THEN 0.3::double precision ELSE 0::double precision END AS margin
        ) AS subsidence,

        -- Worker #278: with no damage cause in the report, term and quality still count, for the
        -- risks that belong to the foundation family.
        LATERAL (SELECT
            term_and_quality AND established.damage_cause IS NULL AND data.is_wood_family(foundation_type.ft) AS own_wood,
            term_and_quality AND established.damage_cause IS NULL AND data.is_no_pile_family(foundation_type.ft) AS own_no_pile,
            term_and_quality AND term_and_quality_cluster AND cluster.damage_cause IS NULL AND data.is_wood_family(foundation_type.ft) AS block_wood,
            term_and_quality AND term_and_quality_cluster AND cluster.damage_cause IS NULL AND data.is_no_pile_family(foundation_type.ft) AS block_no_pile
        ) AS family,

        LATERAL (SELECT
            data.compute_damage_risk_2026_3(
                recovery.type IS NOT NULL,
                established.damage_cause = ANY (ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[]) OR family.own_wood,
                established.enforcement_term, established.document_date, term_countdown,
                established.overall_quality, established.recovery_advised) AS own,
            data.compute_damage_risk_2026_3(
                false,
                cluster.damage_cause = ANY (ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[]) OR family.block_wood,
                cluster.enforcement_term, cluster.document_date, term_countdown,
                cluster.overall_quality, cluster.recovery_advised) AS block,
            data.compute_indicative_drystand_risk_2026_3(
                foundation_type.ft, subsidence.velocity, gwl.level, recovery.type IS NOT NULL, subsidence.margin) AS model
        ) AS dry,

        LATERAL (SELECT
            data.compute_damage_risk_2026_3(
                recovery.type IS NOT NULL,
                established.damage_cause = ANY (ARRAY['bio_infection']::report.foundation_damage_cause[]) OR family.own_wood,
                established.enforcement_term, established.document_date, term_countdown,
                established.overall_quality, established.recovery_advised) AS own,
            data.compute_damage_risk_2026_3(
                false,
                cluster.damage_cause = ANY (ARRAY['bio_infection']::report.foundation_damage_cause[]) OR family.block_wood,
                cluster.enforcement_term, cluster.document_date, term_countdown,
                cluster.overall_quality, cluster.recovery_advised) AS block,
            data.compute_indicative_bio_risk_2026_3(
                foundation_type.ft, pile_length.pile_length, subsidence.velocity, recovery.type IS NOT NULL, subsidence.margin) AS model
        ) AS bio,

        LATERAL (SELECT
            data.compute_damage_risk_2026_3(
                recovery.type IS NOT NULL,
                established.damage_cause = ANY (ARRAY['drainage']::report.foundation_damage_cause[]) OR family.own_no_pile,
                established.enforcement_term, established.document_date, term_countdown,
                established.overall_quality, established.recovery_advised) AS own,
            data.compute_damage_risk_2026_3(
                false,
                cluster.damage_cause = ANY (ARRAY['drainage']::report.foundation_damage_cause[]) OR family.block_no_pile,
                cluster.enforcement_term, cluster.document_date, term_countdown,
                cluster.overall_quality, cluster.recovery_advised) AS block,
            data.compute_indicative_dewatering_risk_2026_3(
                foundation_type.ft, subsidence.velocity, gwl.level, recovery.type IS NOT NULL, subsidence.margin) AS model
        ) AS dew,

        -- What the rules below the QuickScan say, in order: the pand's own report, a QuickScan
        -- under a leading onderzoek, the report of a pand in the same block, the indicative rule.
        LATERAL (SELECT
            COALESCE(dry.own, qs.fallback, dry.block, dry.model) AS dry,
            COALESCE(bio.own, qs.fallback, bio.block, bio.model) AS bio,
            COALESCE(dew.own, qs.fallback, dew.block, dew.model) AS dew
        ) AS chain,

        -- Worker #278 (addition): decay found in the wood makes that risk at least d. It lifts
        -- whatever the rules above arrive at, it never lowers it; a herstel and a valid QuickScan
        -- still go first.
        LATERAL (SELECT
            decay_floor AND own_extra.fungus_decay AND recovery.type IS NULL
                AND (chain.dry IS NULL OR chain.dry < 'd'::data.foundation_risk_indication) AS dry,
            decay_floor AND own_extra.bio_decay AND recovery.type IS NULL
                AND (chain.bio IS NULL OR chain.bio < 'd'::data.foundation_risk_indication) AS bio
        ) AS lift,

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
-- before 1970 = d, from 1970 = b). Model-2024.1 writes it into the overall class, where it reads
-- as research. Worker #242: it belongs in the foundation's own risk, as an estimate. The other
-- foundation families (steel, combined, other) are undecided and keep model-2024.1's place.
LATERAL (SELECT
    CASE
        WHEN t.unc IS NULL AND t.dry IS NULL AND t.bio IS NULL AND t.dew IS NULL THEN
            CASE
                WHEN t.construction_year < 1970 THEN 'd'::data.foundation_risk_indication
                WHEN t.construction_year >= 1970 THEN 'b'::data.foundation_risk_indication
            END
    END AS letter,
    fallback_in_family AND data.is_wood_family(t.foundation_type) AS to_wood,
    fallback_in_family AND data.is_no_pile_family(t.foundation_type) AS to_no_pile
) AS est,
LATERAL (SELECT
    CASE WHEN est.to_wood THEN est.letter END AS dry,
    CASE WHEN est.to_wood THEN est.letter END AS bio,
    CASE WHEN est.to_no_pile THEN est.letter END AS dew,
    CASE WHEN NOT COALESCE(est.to_wood, false) AND NOT COALESCE(est.to_no_pile, false) THEN est.letter END AS unc
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
    type_per_field => true,
    term_and_quality => true,
    term_and_quality_cluster => true,
    term_countdown => true,
    decay_floor => true,
    measured_settlement => true,
    block_velocity => true,
    fallback_in_family => true,
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
        REFRESH MATERIALIZED VIEW data.cluster_sample_2026_3;
        REFRESH MATERIALIZED VIEW data.supercluster_sample_2026_3;
        ANALYZE data.building_sample_2026_3;
        ANALYZE data.cluster_sample_2026_3;
        ANALYZE data.supercluster_sample_2026_3;
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
            'note', 'not built: sample/model matviews unpopulated (schema-only database); refresh the three *_sample_2026_3 matviews, then data.model_risk_static_2026_3');
    END IF;

    UPDATE data.model_version
       SET title = 'Foundation risk model 2026.3',
           notes = 'model-2024.1 with the rules decided in 2026, each a switch of data.model_risk_2026_3_rows(): the QuickScan rules (3-year window, a funderingsonderzoek from the last 5 years leads, addendum only, executed herstel first; Worker #222), foundation type per field (#243), enforcement term and quality without a damage cause, with the term counting down, decay = at least d and measured settlement before InSAR (#278), block median subsidence with a 0.3 mm/year margin (#236, V5), the build-year estimate in the foundation''s own risk (#242), and risk labels by the rule that produced the value (#235). Every switch off is model-2024.1. Output: data.model_risk_static_2026_3.',
           inputs = fingerprint
     WHERE slug = 'model-2026.3';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'model-2026.3 is not registered: apply 20261012_002 first';
    END IF;
END $$;

-- Hand over last: a refresh runs the query as the matview's owner, and the first build above has
-- to work wherever this file runs (on a database bootstrapped from schema.sql the fundermaps role
-- owns nothing). On prod fundermaps owns everything these objects read.
ALTER MATERIALIZED VIEW data.building_sample_2026_3 OWNER TO fundermaps;
ALTER MATERIALIZED VIEW data.cluster_sample_2026_3 OWNER TO fundermaps;
ALTER MATERIALIZED VIEW data.supercluster_sample_2026_3 OWNER TO fundermaps;
ALTER MATERIALIZED VIEW data.model_risk_static_2026_3 OWNER TO fundermaps;
ALTER FUNCTION data.term_class_2026_3(report.enforcement_term, date, boolean) OWNER TO fundermaps;
ALTER FUNCTION data.compute_damage_risk_2026_3(boolean, boolean, report.enforcement_term, date, boolean, report.foundation_quality, boolean) OWNER TO fundermaps;
ALTER FUNCTION data.compute_indicative_drystand_risk_2026_3(report.foundation_type, double precision, double precision, boolean, double precision) OWNER TO fundermaps;
ALTER FUNCTION data.compute_indicative_bio_risk_2026_3(report.foundation_type, numeric, double precision, boolean, double precision) OWNER TO fundermaps;
ALTER FUNCTION data.compute_indicative_dewatering_risk_2026_3(report.foundation_type, double precision, double precision, boolean, double precision) OWNER TO fundermaps;
ALTER FUNCTION data.model_risk_2026_3_rows(boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) OWNER TO fundermaps;

-- The refresh flow runs as fundermaps_windmill. The application roles get nothing here: they read
-- the pointer view, never a versioned matview.
GRANT SELECT, MAINTAIN ON data.building_sample_2026_3, data.cluster_sample_2026_3,
                          data.supercluster_sample_2026_3, data.model_risk_static_2026_3
    TO fundermaps_windmill;
