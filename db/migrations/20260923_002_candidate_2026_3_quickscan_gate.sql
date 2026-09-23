-- model-2026.3 candidate: Don's QuickScan rule, as a precedence gate beside the frozen model.
--
-- The rule (Don, 2026-07-27; clarified 2026-09-06 and 2026-09-11):
--   A QuickScan result overrides the whole FunderMaps risk for 3 years after
--   its execution date. Exception: a funderingsonderzoek from the last 5 years
--   is leading, even when it is older than the QuickScan. A QuickScan is a
--   preliminary investigation; recency never makes it stronger evidence.
--
-- What model-2024.1 does instead (sql/model/recreate_model_risk_dynamic_all.sql):
-- the most recent facade_scan_risk is the first term of every risk COALESCE,
-- with no time window and ahead of any funderingsonderzoek. Dry run on prod
-- 2026-09-23 (BEGIN ... ROLLBACK), 10,597 panden in scope:
--   9,433 qs_valid    unchanged
--     788 qs_expired  a QuickScan older than 3 years that still wins today
--     376 fo_leading  a funderingsonderzoek from the last 5 years loses to it
--     841 panden change in at least one risk field (788 + 53); none ends
--         with no risk. Control (rule off vs model_risk_static_2024_1): 0.
--
-- For qs_expired most changes are a risk becoming NULL: that is the rule.
-- 777 lose the unclassified class Worker #181 gave them from the QuickScan
-- on 2026-09-20. For fo_leading, reading A (the QuickScan ignored outright)
-- emptied the unclassified class of 299 of the 376, because the onderzoek's
-- record carries none of the fields compute_unclassified_risk reads, while
-- 371 still had a valid QuickScan. Reading B (below, chosen by Yorick
-- 2026-09-23) lets a valid QuickScan fill what the onderzoek leaves empty:
-- 53 panden change, all but 3 to a different class, not to nothing.
--
-- What this candidate is. The frozen model's SQL with ONE change: the
-- QuickScan term of the four risk COALESCEs (and the matching reliability
-- CASEs) only fires when the gate says so. Everything else is copied verbatim
-- from data.model_risk_dynamic_all as it stood on 2026-09-23 (after
-- 20260920_005), including the construction-year fallback wrapper.
--
--   gate 'fo_leading'  a funderingsonderzoek dated within 5 years exists
--                      -> the onderzoek's own terms lead; where they give
--                         nothing for a field, a QuickScan within 3 years
--                         fills it before cluster and indicative (reading B)
--   gate 'qs_valid'    otherwise, QuickScan dated within 3 years
--                      -> the QuickScan overrides all four risks (as today)
--   gate 'qs_expired'  otherwise -> the QuickScan does not override
--
-- Funderingsonderzoek = inquiry types foundation_research, inspectionpit,
-- second_opinion, additional_research: the evidence-bearing top of the
-- building_sample priority list (note, archive and architectural research
-- are not onderzoek). Execution date = report.inquiry.document_date, the same
-- column the Webservice uses for its 3-year QuickScan window.
--
-- Reliability of a QuickScan-driven risk stays 'established', as in 2024.1,
-- so the diff shows the rule and nothing else (Yorick, 2026-09-23). Which
-- label a QuickScan risk should carry is a separate product decision.
--
-- Scope (docs/model-versioning.md section 6): only the panden where
-- data.building_sample carries a facade_scan_risk -- the only panden where
-- the rule can change anything. Everywhere else the candidate equals 2024.1
-- by construction.
--
-- Faithfulness check, built in: data.model_risk_2026_3_compute(false) runs
-- the same SQL with the gate forced open, which IS model-2024.1. Compared
-- against data.model_risk_static_2024_1 it must differ only by matview
-- refresh timing. The procedure below records that count in the registry.
--
-- Output:
--   data.model_risk_2026_3     one row per pand in scope: gate, dates, the
--                              four risks and their reliabilities
--   data.model_compare_2026_3  one row per (pand, risk field) that differs
--                              from 2024.1: before, after, direction, gate
-- Rebuild both with CALL data.refresh_model_risk_2026_3(); it is NOT in the
-- nightly flow (candidates are scored, not served).
--
-- Additive: two tables, one function, one procedure, one registry row.
-- Reversible with DROP and DELETE FROM data.model_version.

-- ---------------------------------------------------------------------------
-- The model. apply_rule = false reproduces model-2024.1 (the control).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Candidate output and the diff against 2024.1.
-- ---------------------------------------------------------------------------
CREATE TABLE data.model_risk_2026_3 (
    building_id text PRIMARY KEY,
    neighborhood_id text,
    gate text NOT NULL,
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
);

COMMENT ON TABLE data.model_risk_2026_3 IS
'Candidate model-2026.3-rc1 (Don''s QuickScan rule as a gate), for the panden whose building_sample carries a facade_scan_risk. Rebuilt by CALL data.refresh_model_risk_2026_3(). Not served.';

CREATE TABLE data.model_compare_2026_3 (
    building_id text NOT NULL,
    field text NOT NULL,
    neighborhood_id text,
    gate text NOT NULL,
    frozen_risk data.foundation_risk_indication,
    candidate_risk data.foundation_risk_indication,
    frozen_reliability data.reliability,
    candidate_reliability data.reliability,
    -- 'better' / 'worse' = candidate class lower / higher than 2024.1 (a best,
    -- e worst); 'gained' / 'lost' = one side null; 'reliability_only'.
    direction text NOT NULL,
    PRIMARY KEY (building_id, field)
);

CREATE INDEX model_compare_2026_3_gate_idx ON data.model_compare_2026_3 (gate, field);

COMMENT ON TABLE data.model_compare_2026_3 IS
'Every (pand, risk field) where candidate model-2026.3-rc1 differs from model-2024.1 (data.model_risk_static_2024_1). Rebuilt with data.model_risk_2026_3.';

CREATE OR REPLACE PROCEDURE data.refresh_model_risk_2026_3()
LANGUAGE sql AS $$
    TRUNCATE data.model_risk_2026_3, data.model_compare_2026_3;

    INSERT INTO data.model_risk_2026_3
    SELECT * FROM data.model_risk_2026_3_compute(true);

    INSERT INTO data.model_compare_2026_3
    SELECT c.building_id, f.field, c.neighborhood_id, c.gate,
           f.frozen_risk, f.candidate_risk, f.frozen_rel, f.candidate_rel,
           CASE
               WHEN f.frozen_risk IS NULL THEN 'gained'
               WHEN f.candidate_risk IS NULL THEN 'lost'
               WHEN f.candidate_risk < f.frozen_risk THEN 'better'
               WHEN f.candidate_risk > f.frozen_risk THEN 'worse'
               ELSE 'reliability_only'
           END
      FROM data.model_risk_2026_3 c
      JOIN data.model_risk_static_2024_1 m ON m.building_id = c.building_id
     CROSS JOIN LATERAL (VALUES
           ('drystand', m.drystand_risk, c.drystand_risk, m.drystand_risk_reliability, c.drystand_risk_reliability),
           ('bio_infection', m.bio_infection_risk, c.bio_infection_risk, m.bio_infection_risk_reliability, c.bio_infection_risk_reliability),
           ('dewatering_depth', m.dewatering_depth_risk, c.dewatering_depth_risk, m.dewatering_depth_risk_reliability, c.dewatering_depth_risk_reliability),
           ('unclassified', m.unclassified_risk, c.unclassified_risk, NULL::data.reliability, NULL::data.reliability)
         ) AS f(field, frozen_risk, candidate_risk, frozen_rel, candidate_rel)
     WHERE f.frozen_risk IS DISTINCT FROM f.candidate_risk
        OR f.frozen_rel IS DISTINCT FROM f.candidate_rel;

    ANALYZE data.model_risk_2026_3;
    ANALYZE data.model_compare_2026_3;
$$;

ALTER FUNCTION data.model_risk_2026_3_compute(boolean) OWNER TO fundermaps;
ALTER TABLE data.model_risk_2026_3 OWNER TO fundermaps;
ALTER TABLE data.model_compare_2026_3 OWNER TO fundermaps;
ALTER PROCEDURE data.refresh_model_risk_2026_3() OWNER TO fundermaps;

GRANT SELECT ON data.model_risk_2026_3 TO fundermaps_windmill;
GRANT SELECT ON data.model_compare_2026_3 TO fundermaps_windmill;

-- ---------------------------------------------------------------------------
-- Build and register. A schema-only database (the CI bootstrap from
-- schema.sql) has the sample and model matviews unpopulated, and reading them
-- errors; there the candidate is registered but not built.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    populated boolean := (SELECT bool_and(relispopulated) FROM pg_class
                           WHERE oid IN ('data.building_sample'::regclass,
                                         'data.cluster_sample'::regclass,
                                         'data.supercluster_sample'::regclass,
                                         'data.model_risk_static_2024_1'::regclass));
    fingerprint jsonb;
BEGIN
    IF populated THEN
        CALL data.refresh_model_risk_2026_3();
        fingerprint := jsonb_build_object(
            'note', 'row counts are fingerprints taken when this row was inserted',
            'scope_rows',         (SELECT count(*) FROM data.model_risk_2026_3),
            'gate',               (SELECT jsonb_object_agg(gate, n) FROM (SELECT gate, count(*) n FROM data.model_risk_2026_3 GROUP BY gate) x),
            'panden_changed',     (SELECT count(DISTINCT building_id) FROM data.model_compare_2026_3),
            'control_mismatches', (SELECT count(*) FROM data.model_risk_2026_3_compute(false) c
                                     JOIN data.model_risk_static_2024_1 m USING (building_id)
                                    WHERE (c.drystand_risk, c.bio_infection_risk, c.dewatering_depth_risk, c.unclassified_risk,
                                           c.drystand_risk_reliability, c.bio_infection_risk_reliability, c.dewatering_depth_risk_reliability)
                                          IS DISTINCT FROM
                                          (m.drystand_risk, m.bio_infection_risk, m.dewatering_depth_risk, m.unclassified_risk,
                                           m.drystand_risk_reliability, m.bio_infection_risk_reliability, m.dewatering_depth_risk_reliability)),
            'building_sample',    jsonb_build_object('rows', (SELECT count(*) FROM data.building_sample)),
            'inquiry',            jsonb_build_object('rows', (SELECT count(*) FROM report.inquiry))
        );
    ELSE
        fingerprint := jsonb_build_object(
            'note', 'not built: sample/model matviews unpopulated (schema-only database); CALL data.refresh_model_risk_2026_3() after the first refresh');
    END IF;

    INSERT INTO data.model_version (slug, title, status, is_default, notes, inputs)
    SELECT
        'model-2026.3-rc1',
        'QuickScan precedence gate: 3-year window, recent onderzoek leads (candidate)',
        'candidate',
        false,
        'model-2024.1 with one change: the QuickScan override of the four risks fires only when no funderingsonderzoek (foundation_research, inspectionpit, second_opinion, additional_research) is dated within 5 years AND the QuickScan is dated within 3 years (Don''s rule, 2026-07-27/09-06/09-11). Reliability of a QuickScan-driven risk unchanged (established). Built for the panden whose building_sample carries a facade_scan_risk; elsewhere identical to 2024.1 by construction. Diff: data.model_compare_2026_3.',
        fingerprint
    WHERE NOT EXISTS (SELECT 1 FROM data.model_version WHERE slug = 'model-2026.3-rc1');
END $$;
