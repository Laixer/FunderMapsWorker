-- Worker #347: a report a person approved may overrule BAG's build year, when it states its own.
--
-- data.building_sample skips a report dated more than 5 years before the pand's BAG build year, because such a report
-- is taken to be about a predecessor building. BAG years are often estimates, so approved reports never reached the
-- model or the map. Now a report also passes when it is approved (audit_status done) and passes the same test against
-- the build year in its own sample. The model already reads that year as the pand's construction year
-- (COALESCE(established.built_year, BAG), reliability established), so the map follows.
--
-- Only approved reports: a report about a predecessor also states its own, older year, so the year alone proves
-- nothing; the person who linked the report to this pand does. Unapproved reports wait for their review and then pass
-- by themselves. Nothing that passes today stops passing.
--
-- Measured on prod 2026-11-03 against the rule below: 148 panden get a leading report, none loses one, 19 get another
-- leader (17 of them another foundation type).
--
-- How: Postgres cannot change a matview's query, and DROP would take data.model_risk_static_2024_1 along (it hangs on
-- this matview through data.model_risk_dynamic_all, and its frozen values cannot be rebuilt). So the old matview is
-- renamed, its dependents follow it by oid, model-2024.1 keeps its rule, and a new matview takes the name.
-- data.model_risk_2026_3_rows names it in its text, so model-2026.3 reads the new one at the next refresh.
-- building_sample_2026_3 is bound by oid, so it is rebuilt on the new one.

SET LOCAL lock_timeout = '10s';

ALTER MATERIALIZED VIEW data.building_sample RENAME TO building_sample_2024_1;
ALTER INDEX data.building_sample_building_id_idx RENAME TO building_sample_2024_1_building_id_idx;
COMMENT ON MATERIALIZED VIEW data.building_sample_2024_1 IS '[model evidence] What model-2024.1 read: building_sample with the BAG-only date guard, as of 2026-11-03. Frozen, no longer refreshed.';

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
          WHERE ((i.document_date >= ((b.built_year)::date - '5 years'::interval))
             OR ((i.audit_status = 'done'::report.audit_status)
                 AND (i.document_date >= ((is2.built_year)::date - '5 years'::interval))))
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
                END, i.document_date DESC
        ), facade AS (
         SELECT DISTINCT ON ((is2.building_id)::text) (is2.building_id)::text AS building_id,
            is2.facade_scan_risk
           FROM (report.inquiry_sample is2
             JOIN report.inquiry i ON ((i.id = is2.inquiry_id)))
          WHERE (is2.facade_scan_risk IS NOT NULL)
          ORDER BY (is2.building_id)::text, i.document_date DESC
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

DROP MATERIALIZED VIEW data.building_sample_2026_3;

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

-- Fundie's read-only role exists on prod only.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fundie_agent') THEN
    GRANT SELECT ON data.building_sample, data.building_sample_2026_3 TO fundie_agent;
  END IF;
END
$$;
