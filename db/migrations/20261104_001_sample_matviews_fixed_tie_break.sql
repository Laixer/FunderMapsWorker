-- Worker #301: a fixed last sort key in the sample matviews, so tied reports stop flipping between refreshes.
--
-- The three sample matviews pick one leading report per group with DISTINCT ON, ordered by report type and document date,
-- with no unique last key. When reports tie on both, Postgres returned whichever row the query plan put first, so the same
-- data could give another foundation type at the next refresh. Every pick now ends with the newest entered report, then the
-- newest entered sample. So do the QuickScan class in building_sample and the herstel type in model-2026.3.
--
-- Measured on prod 2026-11-03: under today's ordering the same SELECT gives another result under another plan; with these
-- keys three plans give the identical result. Once, picks change on 2,259 panden, 732 clusters and 837 superclusters, which
-- gives about 17,900 panden another foundation type at the next refresh. About 8,500-9,100 panden already changed type
-- from one day to the next; those flips stop.
--
-- Not a better choice among tied reports: that is a model rule and belongs to a next version.
--
-- This also edits model-2026.3's own function, under the same slug: the second documented exception to "new logic is a new
-- slug" (Yorick 2026-11-03), since it fixes a pick that was unspecified. The frozen view keeps its ordering.
--
-- How: DROP would take data.model_risk_static_2024_1 along (it hangs on cluster_sample and supercluster_sample through
-- data.model_risk_dynamic_all, and its frozen values cannot be rebuilt), so those two are renamed and rebuilt, as
-- building_sample was in 20261103_001. building_sample has nothing frozen on it any more, so it and building_sample_2026_3
-- are simply rebuilt. model_risk_2026_3_rows names all three in its text, so it reads the new ones at the next refresh.

SET LOCAL lock_timeout = '10s';

DROP MATERIALIZED VIEW data.building_sample_2026_3;
DROP MATERIALIZED VIEW data.building_sample;

ALTER MATERIALIZED VIEW data.cluster_sample RENAME TO cluster_sample_2024_1;
ALTER INDEX data.cluster_sample_v2_cluster_id_idx RENAME TO cluster_sample_2024_1_cluster_id_idx;
COMMENT ON MATERIALIZED VIEW data.cluster_sample_2024_1 IS '[model evidence] What model-2024.1 read: cluster_sample without a fixed tie-break. Frozen, no longer refreshed.';

ALTER MATERIALIZED VIEW data.supercluster_sample RENAME TO supercluster_sample_2024_1;
ALTER INDEX data.supercluster_sample_v2_supercluster_id_idx RENAME TO supercluster_sample_2024_1_supercluster_id_idx;
COMMENT ON MATERIALIZED VIEW data.supercluster_sample_2024_1 IS '[model evidence] What model-2024.1 read: supercluster_sample without a fixed tie-break. Frozen, no longer refreshed.';

CREATE MATERIALIZED VIEW data.building_sample AS
 WITH ranked AS (
         SELECT DISTINCT ON (b.external_id) b.external_id AS building_id,
            is2.foundation_type,
            is2.enforcement_term,
            is2.damage_cause,
            is2.overall_quality,
            is2.recovery_advised,
            (date_part('year'::text, (is2.built_year)::date))::integer AS built_year,
            is2.groundwater_level_temp AS groundwater_level,
            is2.wood_level,
            is2.foundation_depth,
            i.type AS inquiry_type,
            i.document_date,
            i.id
           FROM ((report.inquiry_sample is2
             JOIN report.inquiry i ON ((is2.inquiry_id = i.id)))
             JOIN geocoder.building b ON ((b.external_id = (is2.building_id)::text)))
          WHERE ((i.document_date >= ((b.built_year)::date - '5 years'::interval)) OR ((i.audit_status = 'done'::report.audit_status) AND (i.document_date >= ((is2.built_year)::date - '5 years'::interval))))
          ORDER BY b.external_id,
                CASE i.type
                    WHEN 'foundation_research'::report.inquiry_type THEN 0
                    WHEN 'inspectionpit'::report.inquiry_type THEN 1
                    WHEN 'second_opinion'::report.inquiry_type THEN 2
                    WHEN 'note'::report.inquiry_type THEN 3
                    WHEN 'additional_research'::report.inquiry_type THEN 4
                    WHEN 'demolition_research'::report.inquiry_type THEN 5
                    WHEN 'architectural_research'::report.inquiry_type THEN 6
                    WHEN 'archive_research'::report.inquiry_type THEN 7
                    WHEN 'quickscan'::report.inquiry_type THEN 8
                    ELSE 100
                END, i.document_date DESC, i.id DESC, is2.id DESC
        ), facade AS (
         SELECT DISTINCT ON ((is2.building_id)::text) (is2.building_id)::text AS building_id,
            is2.facade_scan_risk
           FROM (report.inquiry_sample is2
             JOIN report.inquiry i ON ((i.id = is2.inquiry_id)))
          WHERE (is2.facade_scan_risk IS NOT NULL)
          ORDER BY (is2.building_id)::text, i.document_date DESC, i.id DESC, is2.id DESC
        )
 SELECT r.building_id,
    r.foundation_type,
    r.enforcement_term,
    r.damage_cause,
    r.overall_quality,
    r.recovery_advised,
    r.built_year,
    r.groundwater_level,
    r.wood_level,
    r.foundation_depth,
    f.facade_scan_risk,
    r.inquiry_type,
    r.document_date,
    r.id
   FROM (ranked r
     LEFT JOIN facade f ON ((f.building_id = r.building_id)));

CREATE UNIQUE INDEX building_sample_building_id_idx ON data.building_sample USING btree (building_id);
ALTER MATERIALIZED VIEW data.building_sample OWNER TO fundermaps;
GRANT SELECT ON data.building_sample TO fundermaps_webapp;
GRANT SELECT, MAINTAIN ON data.building_sample TO fundermaps_windmill;
COMMENT ON MATERIALIZED VIEW data.building_sample IS '[model evidence] Evidence per building from research reports, the way the risk model reads it. Refreshed by refresh_data_model.';

CREATE MATERIALIZED VIEW data.building_sample_2026_3 AS
 WITH dated AS (
         SELECT (s.building_id)::text AS building_id,
            max(i.document_date) FILTER (WHERE ((s.facade_scan_risk IS NOT NULL) AND (i.type = 'facade_scan'::report.inquiry_type))) AS qs_date,
            max(i.document_date) FILTER (WHERE (i.type = ANY (ARRAY['foundation_research'::report.inquiry_type, 'inspectionpit'::report.inquiry_type, 'second_opinion'::report.inquiry_type, 'additional_research'::report.inquiry_type]))) AS fo_date
           FROM (report.inquiry_sample s
             JOIN report.inquiry i ON ((i.id = s.inquiry_id)))
          GROUP BY (s.building_id)::text
        ), decay AS (
         SELECT (s.building_id)::text AS building_id,
            bool_or((s.wood_encroachment = ANY (ARRAY['fungus_infection'::report.wood_encroachment, 'bio_fungus_infection'::report.wood_encroachment]))) AS fungus_decay,
            bool_or((s.wood_encroachment = ANY (ARRAY['bio_infection'::report.wood_encroachment, 'bio_fungus_infection'::report.wood_encroachment]))) AS bio_decay
           FROM (report.inquiry_sample s
             JOIN data.building_sample bs ON (((bs.building_id = (s.building_id)::text) AND (bs.id = s.inquiry_id))))
          WHERE (s.wood_encroachment IS NOT NULL)
          GROUP BY (s.building_id)::text
        )
 SELECT d.building_id,
    d.qs_date,
    d.fo_date,
    COALESCE(x.fungus_decay, false) AS fungus_decay,
    COALESCE(x.bio_decay, false) AS bio_decay
   FROM (dated d
     LEFT JOIN decay x USING (building_id));

CREATE UNIQUE INDEX building_sample_2026_3_pkey ON data.building_sample_2026_3 USING btree (building_id);
ALTER MATERIALIZED VIEW data.building_sample_2026_3 OWNER TO fundermaps;
GRANT SELECT, MAINTAIN ON data.building_sample_2026_3 TO fundermaps_windmill;
COMMENT ON MATERIALIZED VIEW data.building_sample_2026_3 IS '[model evidence] Extra evidence per building for model-2026.3 (QuickScan and research dates, decay findings), built on building_sample. Refreshed by refresh_data_model.';

CREATE MATERIALIZED VIEW data.cluster_sample AS
 SELECT DISTINCT ON (bc.cluster_id) bc.cluster_id,
    is2.foundation_type,
    is2.enforcement_term,
    is2.damage_cause,
    is2.overall_quality,
    is2.recovery_advised,
    (date_part('year'::text, (is2.built_year)::date))::integer AS built_year,
    is2.groundwater_level_temp AS groundwater_level,
    is2.wood_level,
    is2.foundation_depth,
    i.type AS inquiry_type,
    i.document_date,
    i.id
   FROM (((data.building_cluster bc
     JOIN geocoder.building b ON ((b.external_id = bc.building_id)))
     JOIN report.inquiry_sample is2 ON (((is2.building_id)::text = b.external_id)))
     JOIN report.inquiry i ON ((is2.inquiry_id = i.id)))
  WHERE (i.document_date >= ((b.built_year)::date - '5 years'::interval))
  ORDER BY bc.cluster_id,
        CASE i.type
            WHEN 'foundation_research'::report.inquiry_type THEN 0
            WHEN 'inspectionpit'::report.inquiry_type THEN 1
            WHEN 'second_opinion'::report.inquiry_type THEN 2
            WHEN 'note'::report.inquiry_type THEN 3
            WHEN 'additional_research'::report.inquiry_type THEN 4
            WHEN 'demolition_research'::report.inquiry_type THEN 5
            WHEN 'architectural_research'::report.inquiry_type THEN 6
            WHEN 'archive_research'::report.inquiry_type THEN 7
            WHEN 'quickscan'::report.inquiry_type THEN 8
            ELSE 100
        END, i.document_date DESC, i.id DESC, is2.id DESC;

CREATE UNIQUE INDEX cluster_sample_v2_cluster_id_idx ON data.cluster_sample USING btree (cluster_id);
ALTER MATERIALIZED VIEW data.cluster_sample OWNER TO fundermaps;
GRANT SELECT, MAINTAIN ON data.cluster_sample TO fundermaps_windmill;
COMMENT ON MATERIALIZED VIEW data.cluster_sample IS '[model evidence] Evidence per building cluster, for buildings without a report of their own. Refreshed by refresh_data_model.';

CREATE MATERIALIZED VIEW data.supercluster_sample AS
 SELECT DISTINCT ON (s.supercluster_id) s.supercluster_id,
    is2.foundation_type,
    is2.enforcement_term,
    is2.damage_cause,
    is2.overall_quality,
    is2.recovery_advised,
    (date_part('year'::text, (is2.built_year)::date))::integer AS built_year,
    is2.groundwater_level_temp AS groundwater_level,
    is2.wood_level,
    is2.foundation_depth,
    i.type AS inquiry_type,
    i.document_date,
    i.id
   FROM ((((data.supercluster s
     JOIN data.building_cluster bc ON ((bc.cluster_id = s.cluster_id)))
     JOIN geocoder.building b ON ((b.external_id = bc.building_id)))
     JOIN report.inquiry_sample is2 ON (((is2.building_id)::text = b.external_id)))
     JOIN report.inquiry i ON ((is2.inquiry_id = i.id)))
  WHERE (i.document_date >= ((b.built_year)::date - '5 years'::interval))
  ORDER BY s.supercluster_id,
        CASE i.type
            WHEN 'foundation_research'::report.inquiry_type THEN 0
            WHEN 'inspectionpit'::report.inquiry_type THEN 1
            WHEN 'second_opinion'::report.inquiry_type THEN 2
            WHEN 'note'::report.inquiry_type THEN 3
            WHEN 'additional_research'::report.inquiry_type THEN 4
            WHEN 'demolition_research'::report.inquiry_type THEN 5
            WHEN 'architectural_research'::report.inquiry_type THEN 6
            WHEN 'archive_research'::report.inquiry_type THEN 7
            WHEN 'quickscan'::report.inquiry_type THEN 8
            ELSE 100
        END, i.document_date DESC, i.id DESC, is2.id DESC;

CREATE UNIQUE INDEX supercluster_sample_v2_supercluster_id_idx ON data.supercluster_sample USING btree (supercluster_id);
ALTER MATERIALIZED VIEW data.supercluster_sample OWNER TO fundermaps;
GRANT SELECT, MAINTAIN ON data.supercluster_sample TO fundermaps_windmill;
COMMENT ON MATERIALIZED VIEW data.supercluster_sample IS '[model evidence] Evidence per supercluster, the fallback after cluster_sample. Refreshed by refresh_data_model.';

CREATE OR REPLACE FUNCTION data.model_risk_2026_3_rows(quickscan_rules boolean DEFAULT true, term_and_quality boolean DEFAULT true, decay_floor boolean DEFAULT true, block_velocity boolean DEFAULT true, fallback_to_dewatering boolean DEFAULT true, label_by_source boolean DEFAULT true) RETURNS TABLE(building_id text, address_count integer, neighborhood_id text, construction_year integer, construction_year_reliability data.reliability, foundation_type report.foundation_type, foundation_type_reliability data.reliability, restoration_costs integer, drystand double precision, drystand_risk data.foundation_risk_indication, drystand_risk_reliability data.reliability, bio_infection_risk data.foundation_risk_indication, bio_infection_risk_reliability data.reliability, dewatering_depth double precision, dewatering_depth_risk data.foundation_risk_indication, dewatering_depth_risk_reliability data.reliability, unclassified_risk data.foundation_risk_indication, height numeric, velocity numeric, ground_water_level numeric, ground_level numeric, soil text, surface_area numeric, owner text, inquiry_id integer, inquiry_type report.inquiry_type, damage_cause report.foundation_damage_cause, enforcement_term double precision, overall_quality report.foundation_quality, recovery_type report.recovery_type, quickscan_gate text, drystand_source text, bio_infection_source text, dewatering_depth_source text, unclassified_source text)
    LANGUAGE sql STABLE
    AS $$
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
             ORDER BY rs.building_id, rs.create_date DESC, rs.id DESC
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

-- Fundie's read-only role exists on prod only.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fundie_agent') THEN
    GRANT SELECT ON data.building_sample, data.building_sample_2026_3, data.cluster_sample, data.supercluster_sample TO fundie_agent;
  END IF;
END
$$;
