-- model-2026.3 candidate: count only QuickScan (addendum) reports as a QuickScan.
--
-- Why (Don, 2026-09-23): "je moet de voorwaarde koppelen aan het inquiry_id".
-- 20260923_002 dated a pand's QuickScan by max(document_date) over EVERY sample
-- carrying a facade_scan_risk, whatever the report type. On prod 2026-09-23,
-- 231 panden have that date from a non-QuickScan report (archive_research,
-- note, ...): 217 carry a QuickScan class only on such reports, and for 144 the
-- 3-year gate flips (a recent archive/note date made the class count as a
-- valid QuickScan). Restrict the qs CTE to report.inquiry.type = 'facade_scan'
-- (Studio: "QuickScan (addendum)"). Everything else in the function is copied
-- unchanged from 20260923_002. The candidate is not served; the live model
-- (2024.1) is untouched. Re-run CALL data.refresh_model_risk_2026_3() after.

CREATE OR REPLACE FUNCTION data.model_risk_2026_3_compute(apply_rule boolean)
RETURNS TABLE (
    building_id text,
    neighborhood_id text,
    gate text,
    qs_risk data.foundation_risk_indication,
    qs_date date,
    fo_date date,
    drystand_risk data.foundation_risk_indication,
    drystand_risk_reliability data.reliability,
    bio_infection_risk data.foundation_risk_indication,
    bio_infection_risk_reliability data.reliability,
    dewatering_depth_risk data.foundation_risk_indication,
    dewatering_depth_risk_reliability data.reliability,
    unclassified_risk data.foundation_risk_indication
)
LANGUAGE sql STABLE AS $$
WITH scope AS (
    SELECT bs.building_id
      FROM data.building_sample bs
     WHERE bs.facade_scan_risk IS NOT NULL
),
-- Date of the QuickScan risk the sample carries. building_sample picks the
-- facade_scan_risk of the most recent inquiry that has one, so its date is
-- the max document_date over those inquiries (ties cannot change the date).
qs AS (
    SELECT s.building_id::text AS building_id, max(i.document_date) AS qs_date
      FROM report.inquiry_sample s
      JOIN report.inquiry i ON i.id = s.inquiry_id
     WHERE s.facade_scan_risk IS NOT NULL
       AND i.type = 'facade_scan'
       AND s.building_id::text IN (SELECT building_id FROM scope)
     GROUP BY 1
),
fo AS (
    SELECT s.building_id::text AS building_id, max(i.document_date) AS fo_date
      FROM report.inquiry_sample s
      JOIN report.inquiry i ON i.id = s.inquiry_id
     WHERE i.type IN ('foundation_research', 'inspectionpit', 'second_opinion', 'additional_research')
       AND s.building_id::text IN (SELECT building_id FROM scope)
     GROUP BY 1
),
gated AS (
    SELECT sc.building_id, qs.qs_date, fo.fo_date,
           CASE
               WHEN fo.fo_date >= current_date - interval '5 years' THEN 'fo_leading'
               WHEN qs.qs_date >= current_date - interval '3 years' THEN 'qs_valid'
               ELSE 'qs_expired'
           END AS gate
      FROM scope sc
      LEFT JOIN qs ON qs.building_id = sc.building_id
      LEFT JOIN fo ON fo.building_id = sc.building_id
)
SELECT
    base.building_id,
    base.neighborhood_id,
    base.gate,
    base.qs_risk,
    base.qs_date,
    base.fo_date,
    base.drystand_risk,
    base.drystand_risk_reliability,
    base.bio_infection_risk,
    base.bio_infection_risk_reliability,
    base.dewatering_depth_risk,
    base.dewatering_depth_risk_reliability,
    -- Construction-year fallback, verbatim from 2024.1 (issue #1002).
    COALESCE(
        base.unclassified_risk,
        CASE
            WHEN base.drystand_risk IS NULL
             AND base.bio_infection_risk IS NULL
             AND base.dewatering_depth_risk IS NULL
            THEN CASE
                WHEN base.construction_year < 1970
                    THEN 'd'::data.foundation_risk_indication
                WHEN base.construction_year >= 1970
                    THEN 'b'::data.foundation_risk_indication
                ELSE NULL
            END
            ELSE NULL
        END
    ) AS unclassified_risk
FROM (
SELECT
    bp.building_id,
    bp.neighborhood_id,
    g.gate,
    established.facade_scan_risk::text::data.foundation_risk_indication AS qs_risk,
    g.qs_date,
    g.fo_date,
    COALESCE(established.built_year, bp.construction_year_bag) AS construction_year,

    -- THE CHANGE: the QuickScan term, gated. With apply_rule = false it is
    -- established.facade_scan_risk unconditionally, exactly as in 2024.1.
    COALESCE(
        qs_term.risk,
        data.compute_damage_risk(
            recovery.type IS NOT NULL,
            established.damage_cause,
            ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[],
            established.enforcement_term, established.overall_quality, established.recovery_advised
        ),
        qs_fallback.risk,
        data.compute_damage_risk(
            false,
            cluster.damage_cause,
            ARRAY['drystand', 'fungus_infection', 'bio_fungus_infection']::report.foundation_damage_cause[],
            cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised
        ),
        data.compute_indicative_drystand_risk(
            foundation_type.ft, bs.velocity, gwl.level, recovery.type IS NOT NULL
        )
    ) AS drystand_risk,
    CASE
        WHEN qs_term.risk IS NOT NULL THEN 'established'::data.reliability
        WHEN established.id IS NOT NULL THEN 'established'::data.reliability
        WHEN cluster.id IS NOT NULL THEN 'cluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS drystand_risk_reliability,

    COALESCE(
        qs_term.risk,
        data.compute_damage_risk(
            recovery.type IS NOT NULL,
            established.damage_cause,
            ARRAY['bio_infection']::report.foundation_damage_cause[],
            established.enforcement_term, established.overall_quality, established.recovery_advised
        ),
        qs_fallback.risk,
        data.compute_damage_risk(
            false,
            cluster.damage_cause,
            ARRAY['bio_infection']::report.foundation_damage_cause[],
            cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised
        ),
        data.compute_indicative_bio_risk(
            foundation_type.ft, pile_length.pile_length, bs.velocity, recovery.type IS NOT NULL
        )
    ) AS bio_infection_risk,
    CASE
        WHEN qs_term.risk IS NOT NULL THEN 'established'::data.reliability
        WHEN established.id IS NOT NULL THEN 'established'::data.reliability
        WHEN cluster.id IS NOT NULL THEN 'cluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS bio_infection_risk_reliability,

    COALESCE(
        qs_term.risk,
        data.compute_damage_risk(
            recovery.type IS NOT NULL,
            established.damage_cause,
            ARRAY['drainage']::report.foundation_damage_cause[],
            established.enforcement_term, established.overall_quality, established.recovery_advised
        ),
        qs_fallback.risk,
        data.compute_damage_risk(
            false,
            cluster.damage_cause,
            ARRAY['drainage']::report.foundation_damage_cause[],
            cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised
        ),
        data.compute_indicative_dewatering_risk(
            foundation_type.ft, bs.velocity, gwl.level, recovery.type IS NOT NULL
        )
    ) AS dewatering_depth_risk,
    CASE
        WHEN qs_term.risk IS NOT NULL THEN 'established'::data.reliability
        WHEN established.id IS NOT NULL THEN 'established'::data.reliability
        WHEN cluster.id IS NOT NULL THEN 'cluster'::data.reliability
        ELSE 'indicative'::data.reliability
    END AS dewatering_depth_risk_reliability,

    COALESCE(
        qs_term.risk,
        data.compute_unclassified_risk(
            recovery.type IS NOT NULL, 'a', 'e',
            established.enforcement_term, established.overall_quality,
            established.recovery_advised, established.damage_cause
        ),
        qs_fallback.risk,
        data.compute_unclassified_risk(
            cluster_recovery_sample.type IS NOT NULL, 'e', 'd',
            cluster.enforcement_term, cluster.overall_quality,
            cluster.recovery_advised, cluster.damage_cause
        )
    ) AS unclassified_risk

FROM gated g
    JOIN data.building_precomputed bp ON bp.building_id = g.building_id
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = bp.building_id
    LEFT JOIN data.building_groundwater_level gwl ON gwl.building_id = bp.building_id
    LEFT JOIN data.building_subsidence bs ON bs.building_id = bp.building_id
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
    LATERAL (SELECT round((bp.ground_level - bpl.depth)::numeric, 2)) AS pile_length(pile_length),
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
    )) AS foundation_type(ft),
    LATERAL (SELECT CASE
        WHEN NOT apply_rule OR g.gate = 'qs_valid'
            THEN established.facade_scan_risk::text::data.foundation_risk_indication
    END) AS qs_term(risk),
    -- Reading B (Yorick, 2026-09-23): under fo_leading the onderzoek's own
    -- terms come first; where they produce nothing for a field, a QuickScan
    -- that is still within 3 years fills it, ahead of cluster and indicative.
    LATERAL (SELECT CASE
        WHEN apply_rule AND g.gate = 'fo_leading'
         AND g.qs_date >= current_date - interval '3 years'
            THEN established.facade_scan_risk::text::data.foundation_risk_indication
    END) AS qs_fallback(risk)
) base;
$$;

ALTER FUNCTION data.model_risk_2026_3_compute(boolean) OWNER TO fundermaps;
