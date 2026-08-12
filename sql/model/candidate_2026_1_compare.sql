-- Per-building comparison of the frozen model against candidate 2026.1.
--
-- Exists so the change can be SEEN rather than quoted. "452,000 homes gain a
-- rot warning" is not a number anyone can make a decision on; a map of which
-- homes, in a city you know, is.
--
-- Deliberately carries NO geometry: it joins to maplayer.building_tiles.geom
-- when rendering, so this costs ~11.2M narrow rows instead of duplicating
-- 4.4 GB of polygons.
--
-- Only indicative-tier buildings can differ. Where an inquiry exists, both
-- models believe the inquiry, so frozen and candidate agree by construction --
-- those rows are carried anyway so a map has full context.
--
-- Threshold 0.45: the operating point that matches today's false-alarm rate
-- (12.7% vs 11.0%), so the comparison isn't flattered by simply alarming more.
--
-- One-off. Not refreshed nightly, not served by Martin -- the tileserver is
-- public and unauthenticated, and this is a candidate nobody has approved.
--
--   psql "$DB_URL" -f sql/model/candidate_2026_1_compare.sql

BEGIN;

DROP TABLE IF EXISTS data.model_compare_2026_1;

CREATE TABLE data.model_compare_2026_1 AS
SELECT
    m.building_id,
    m.neighborhood_id,
    m.foundation_type_reliability::text            AS tier,
    m.foundation_type::text                        AS frozen_ft,
    c.cand_ft::text                                AS cand_ft,
    m.drystand_risk::text                          AS frozen_rot,
    c.cand_rot::text                               AS cand_rot,
    -- what a homeowner would see change
    CASE
      WHEN (m.drystand_risk IS NULL OR m.drystand_risk IN ('a','b'))
       AND  c.cand_rot IN ('c','d','e')                     THEN 'gains_warning'
      WHEN  m.drystand_risk IN ('c','d','e')
       AND (c.cand_rot IS NULL OR c.cand_rot IN ('a','b'))  THEN 'loses_warning'
      WHEN  m.drystand_risk IS DISTINCT FROM c.cand_rot     THEN 'changes_severity'
      ELSE 'unchanged'
    END AS change_kind
FROM data.model_risk_static m
JOIN LATERAL (
    SELECT ft.cand_ft,
           CASE WHEN m.foundation_type_reliability = 'indicative'
                THEN data.compute_indicative_drystand_risk(
                        ft.cand_ft, bs.velocity, gwl.level,
                        EXISTS (SELECT 1 FROM report.recovery_sample rs
                                WHERE rs.building_id = m.building_id))
                ELSE m.drystand_risk
           END AS cand_rot
    FROM data.building_precomputed bp
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = bp.building_id
    LEFT JOIN data.building_subsidence bs        ON bs.building_id = bp.building_id
    LEFT JOIN data.building_groundwater_level gwl ON gwl.building_id = bp.building_id
    LEFT JOIN data.foundation_type_lookup_2026_1 l
      ON l.cell = data.ft_cell_2026_1(bp.construction_year_bag, bp.height, gr.code,
                                      bp.ground_level, bp.surface_area, bp.address_count)
    CROSS JOIN LATERAL (
        SELECT CASE
                 -- an inquiry outranks the classifier in both models
                 WHEN m.foundation_type_reliability <> 'indicative' THEN m.foundation_type
                 WHEN l.p_wood IS NULL              THEN m.foundation_type   -- unseen cell: fall back
                 WHEN l.p_wood >= 0.45              THEN 'wood'::report.foundation_type
                 WHEN l.p_no_pile >= l.p_concrete   THEN 'no_pile'::report.foundation_type
                 ELSE 'concrete'::report.foundation_type
               END AS cand_ft
    ) ft
    WHERE bp.building_id = m.building_id
) c ON true;

ALTER TABLE data.model_compare_2026_1 ADD PRIMARY KEY (building_id);
CREATE INDEX model_compare_2026_1_change_idx
    ON data.model_compare_2026_1 (change_kind) WHERE change_kind <> 'unchanged';
CREATE INDEX model_compare_2026_1_nb_idx ON data.model_compare_2026_1 (neighborhood_id);

COMMENT ON TABLE data.model_compare_2026_1 IS
    'One-off frozen-vs-candidate comparison for decision support. Not served, not refreshed. Drop freely.';

COMMIT;
