-- model-2026.3, built for every pand beside the frozen model (docs/model-versioning.md, step 4).
--
-- Why (Yorick, 2026-10-12: "We have a go for model switch. 2026.3 will become the default"):
-- a default has to answer for every pand. Until now model-2026.3 only existed as the candidate
-- table data.model_risk_2026_3, holding the panden with a QuickScan class (20260923_002,
-- 20260928_003, 20260928_004). This file gives it the shape of the model it replaces: one row per
-- pand, the same 30 columns, the same two indexes.
--
-- NOTHING IS SERVED FROM IT YET. data.model_risk_static still points at model-2024.1 and the
-- registry default does not move; that is the next migration (model_2026_3_default).
--
-- What model-2026.3 is: model-2024.1 with three rules on the QuickScan term.
--   * A QuickScan overrides the four risks only within 3 years of its date, and only when there is
--     no funderingsonderzoek from the last 5 years; under a recent onderzoek a valid QuickScan
--     only fills what the onderzoek leaves empty (20260923_002; Don 2026-07-27, 09-06, 09-11).
--   * Only a QuickScan addendum (inquiry type facade_scan) counts as a QuickScan (20260928_003).
--   * An executed herstel beats a QuickScan (20260928_004, Worker #222).
-- All three can only change a pand whose building_sample carries a facade_scan_risk. So the
-- national output is the model-2024.1 row of every pand, with the four risks and the three risk
-- labels taken from data.model_risk_2026_3_compute(true) on those panden. That is the query below.
--
-- Why on top of the 2024.1 matview, and not a second copy of the whole model SQL:
--   * model-2024.1 keeps refreshing anyway (frozen = the logic is frozen, the data keeps flowing);
--   * the rebuild costs about a minute, not a second national run of ~18 minutes (the SELECT
--     below ran in 32 s on prod, 2026-10-12);
--   * "equal to 2024.1 outside the QuickScan panden" holds by construction instead of by test.
-- The price: the refresh order matters (2024.1 first, then this one; refresh_risk_model does
-- both in that order), and this matview cannot outlive data.model_risk_static_2024_1. A version
-- that changes rules for every pand (Worker #235, #236, #242) brings its own SQL and its own slug.
--
-- FROM NOW ON data.model_risk_2026_3_compute(boolean) IS MODEL LOGIC THAT GETS SERVED. Do not
-- CREATE OR REPLACE it again (the candidate was edited in place twice); new logic is a new slug.
--
-- Prod, 2026-10-12 15:30 CEST, read-only and between two refreshes:
--   11,321,489 rows; 11,577 panden with a QuickScan class
--   (qs_valid 10,188 / qs_expired 1,024 / fo_leading 365);
--   1,110 panden differ from model-2024.1 in at least one risk letter, 0 in a label only,
--   none ends without a risk; worst letter per pand: 103 better, 576 worse (524 of them an
--   expired QuickScan), 431 unchanged; control (rule off against 2024.1): 0 mismatches.

CREATE MATERIALIZED VIEW data.model_risk_static_2026_3 AS
SELECT
    d.building_id,
    d.address_count,
    d.neighborhood_id,
    d.construction_year,
    d.construction_year_reliability,
    d.foundation_type,
    d.foundation_type_reliability,
    d.restoration_costs,
    d.drystand,
    CASE WHEN q.building_id IS NULL THEN d.drystand_risk ELSE q.drystand_risk END AS drystand_risk,
    CASE WHEN q.building_id IS NULL THEN d.drystand_risk_reliability ELSE q.drystand_risk_reliability END AS drystand_risk_reliability,
    CASE WHEN q.building_id IS NULL THEN d.bio_infection_risk ELSE q.bio_infection_risk END AS bio_infection_risk,
    CASE WHEN q.building_id IS NULL THEN d.bio_infection_risk_reliability ELSE q.bio_infection_risk_reliability END AS bio_infection_risk_reliability,
    d.dewatering_depth,
    CASE WHEN q.building_id IS NULL THEN d.dewatering_depth_risk ELSE q.dewatering_depth_risk END AS dewatering_depth_risk,
    CASE WHEN q.building_id IS NULL THEN d.dewatering_depth_risk_reliability ELSE q.dewatering_depth_risk_reliability END AS dewatering_depth_risk_reliability,
    CASE WHEN q.building_id IS NULL THEN d.unclassified_risk ELSE q.unclassified_risk END AS unclassified_risk,
    d.height,
    d.velocity,
    d.ground_water_level,
    d.ground_level,
    d.soil,
    d.surface_area,
    d.owner,
    d.inquiry_id,
    d.inquiry_type,
    d.damage_cause,
    d.enforcement_term,
    d.overall_quality,
    d.recovery_type
FROM data.model_risk_static_2024_1 d
LEFT JOIN data.model_risk_2026_3_compute(true) q ON q.building_id = d.building_id
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW data.model_risk_static_2026_3 IS
'model-2026.3 for every pand: the model-2024.1 row, with the four risks and three risk labels from data.model_risk_2026_3_compute(true) where the pand has a QuickScan class. Refresh after data.model_risk_static_2024_1 (Windmill f/fundermaps/data/refresh_risk_model). See docs/model-versioning.md.';

-- Same two indexes as 2024.1. The unique one is what REFRESH ... CONCURRENTLY needs.
CREATE UNIQUE INDEX model_risk_static_2026_3_pkey
    ON data.model_risk_static_2026_3 (building_id);
CREATE INDEX model_risk_static_2026_3_neighborhood_id_idx
    ON data.model_risk_static_2026_3 (neighborhood_id);

-- The pointer view is switched with CREATE OR REPLACE VIEW, which only works when the new
-- matview has exactly the columns of the old one: same names, same types, same order.
DO $$
DECLARE
    differing integer;
BEGIN
    SELECT count(*) INTO differing
      FROM (SELECT attnum, attname, atttypid, atttypmod FROM pg_attribute
             WHERE attrelid = 'data.model_risk_static_2024_1'::regclass AND attnum > 0 AND NOT attisdropped) o
      FULL JOIN (SELECT attnum, attname, atttypid, atttypmod FROM pg_attribute
                  WHERE attrelid = 'data.model_risk_static_2026_3'::regclass AND attnum > 0 AND NOT attisdropped) n
        USING (attnum, attname, atttypid, atttypmod)
     WHERE o.attnum IS NULL OR n.attnum IS NULL;
    IF differing > 0 THEN
        RAISE EXCEPTION 'data.model_risk_static_2026_3 does not have the columns of data.model_risk_static_2024_1 (% differ)', differing;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Build and register. A schema-only database (the CI bootstrap from schema.sql)
-- has the sample and model matviews unpopulated, and reading them errors; there
-- the version is registered but not built, like 2024.1 itself on such a database.
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
        REFRESH MATERIALIZED VIEW data.model_risk_static_2026_3;
        ANALYZE data.model_risk_static_2026_3;

        SELECT count(*) INTO rows_new FROM data.model_risk_static_2026_3;
        SELECT count(*) INTO rows_old FROM data.model_risk_static_2024_1;
        IF rows_new <> rows_old THEN
            RAISE EXCEPTION 'model-2026.3 has % rows, model-2024.1 has %: one row per pand expected', rows_new, rows_old;
        END IF;

        fingerprint := jsonb_build_object(
            'note', 'row counts are fingerprints taken when this row was inserted',
            'rows',               rows_new,
            'quickscan_panden',   (SELECT count(*) FROM data.model_risk_2026_3_compute(true)),
            'gate',               (SELECT jsonb_object_agg(gate, n) FROM (SELECT gate, count(*) n FROM data.model_risk_2026_3_compute(true) GROUP BY gate) x),
            'panden_changed',     (SELECT count(*) FROM data.model_risk_static_2026_3 n
                                     JOIN data.model_risk_static_2024_1 o USING (building_id)
                                    WHERE (n.drystand_risk, n.bio_infection_risk, n.dewatering_depth_risk, n.unclassified_risk,
                                           n.drystand_risk_reliability, n.bio_infection_risk_reliability, n.dewatering_depth_risk_reliability)
                                          IS DISTINCT FROM
                                          (o.drystand_risk, o.bio_infection_risk, o.dewatering_depth_risk, o.unclassified_risk,
                                           o.drystand_risk_reliability, o.bio_infection_risk_reliability, o.dewatering_depth_risk_reliability)),
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
            'note', 'not built: sample/model matviews unpopulated (schema-only database); REFRESH MATERIALIZED VIEW data.model_risk_static_2026_3 after data.model_risk_static_2024_1');
    END IF;

    INSERT INTO data.model_version (slug, title, status, is_default, notes, inputs)
    SELECT
        'model-2026.3',
        'Foundation risk model with the QuickScan rules',
        'candidate',
        false,
        'model-2024.1 with three rules on the QuickScan term. (1) A QuickScan overrides the four risks only within 3 years of its date and only when no funderingsonderzoek (foundation_research, inspectionpit, second_opinion, additional_research) is dated within 5 years; under a recent onderzoek a valid QuickScan fills only what the onderzoek leaves empty (Don, 2026-07-27/09-06/09-11). (2) Only a QuickScan addendum (inquiry type facade_scan) counts as a QuickScan. (3) An executed herstel beats a QuickScan (Worker #222). Reliability of a QuickScan-driven risk unchanged (established). Output data.model_risk_static_2026_3: the 2024.1 row of every pand, recomputed where the pand has a QuickScan class. Supersedes the candidate model-2026.3-rc1 (data.model_risk_2026_3).',
        fingerprint
    WHERE NOT EXISTS (SELECT 1 FROM data.model_version WHERE slug = 'model-2026.3');
END $$;

-- Hand over last. A refresh runs the query as the matview's owner, and the first build above has
-- to work wherever this file runs: on a database bootstrapped from schema.sql the fundermaps role
-- owns nothing and cannot read the data schema. On prod fundermaps owns everything it reads.
ALTER MATERIALIZED VIEW data.model_risk_static_2026_3 OWNER TO fundermaps;

-- The refresh flow runs as fundermaps_windmill (the 2024.1 matview carries the same two rights).
-- The application roles get nothing here: they read the pointer view, never a versioned matview.
GRANT SELECT, MAINTAIN ON data.model_risk_static_2026_3 TO fundermaps_windmill;
