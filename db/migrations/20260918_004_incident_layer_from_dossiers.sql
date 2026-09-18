-- The incident map layer reads the meldingen, not the dead incident table.
--
-- Found while handling gemeente Schiedam's complaint (Wietse via Don,
-- 2026-09-17 23:08 CEST; API #189). `report.incident` is frozen: 30 rows in
-- January 2026, 28 in February, 1 in March, nothing since, total 2,756. The new
-- API has no write path to it — `src/routes/intake.ts` says so itself: a
-- submission becomes a dossier and "nothing consumes that table". Meanwhile the
-- meldingen kept coming: 2,286 dossiers with a topic on 1,857 distinct panden,
-- 2,294 of them in September 2026 alone. The layer was rendering a snapshot of
-- a table that stopped being written six months ago.
--
-- Don decided both open points on 2026-09-18 05:13 UTC:
--   * privacy: the layer exposes the pand and the topic and nothing else — no
--     melder name, no e-mail, no reference, no note;
--   * scope: ALL meldingen count, open or closed.
--
-- Counting rule, chosen to keep the point layer and the three aggregates
-- consistent: one row per PAND (the most recent melding for that pand), and the
-- aggregates count panden, not meldingen. A pand with three meldingen is one dot
-- and adds one to its buurt.
--
-- `foundation_damage_cause` is kept in the view and the tile table so the
-- existing Mapbox style and TileJSON stay valid, but it is now always NULL: a
-- melding carries a topic, not a damage cause, and inventing one would be worse
-- than an empty field. The new `topic` column carries the label.
--
-- The layers stay HIDDEN on the public Schiedam mapset (Don: "But keep the
-- layers hidden"). This migration only makes the data honest; showing it again
-- is a separate config change.

-- 1. The point layer: one pand, its most recent melding.
CREATE OR REPLACE VIEW maplayer.incident AS
 SELECT m.dossier_id::text AS id,
    -- Must stay the enum type: CREATE OR REPLACE VIEW cannot change a column's
    -- type (PostgresError caught this in CI on the first attempt).
    NULL::report.foundation_damage_cause AS foundation_damage_cause,
    round(GREATEST(bh.height, 0::real)::numeric, 2) AS height,
    ba.geom,
    m.topic
   FROM ( SELECT DISTINCT ON (d.building_id) d.building_id,
            d.id AS dossier_id,
            d.payload ->> 'topic'::text AS topic
           FROM dataops.dossier d
          WHERE d.payload ->> 'topic'::text IS NOT NULL
            AND d.building_id IS NOT NULL
          ORDER BY d.building_id, d.created_at DESC) m
     JOIN geocoder.building_active ba ON ba.external_id = m.building_id
     JOIN data.building_height bh ON bh.building_id = ba.external_id;

-- 2. The three aggregates: panden per CBS area.
CREATE OR REPLACE VIEW maplayer.incident_neighborhood AS
 SELECT n.geom,
    count(*) AS incident_count
   FROM ( SELECT DISTINCT d.building_id
           FROM dataops.dossier d
          WHERE d.payload ->> 'topic'::text IS NOT NULL
            AND d.building_id IS NOT NULL) m
     JOIN geocoder.building_active ba ON ba.external_id = m.building_id
     JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
  GROUP BY n.id, n.geom;

CREATE OR REPLACE VIEW maplayer.incident_district AS
 SELECT d2.geom,
    count(*) AS incident_count
   FROM ( SELECT DISTINCT d.building_id
           FROM dataops.dossier d
          WHERE d.payload ->> 'topic'::text IS NOT NULL
            AND d.building_id IS NOT NULL) m
     JOIN geocoder.building_active ba ON ba.external_id = m.building_id
     JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
     JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
  GROUP BY d2.id, d2.geom;

CREATE OR REPLACE VIEW maplayer.incident_municipality AS
 SELECT mu.geom,
    count(*) AS incident_count
   FROM ( SELECT DISTINCT d.building_id
           FROM dataops.dossier d
          WHERE d.payload ->> 'topic'::text IS NOT NULL
            AND d.building_id IS NOT NULL) m
     JOIN geocoder.building_active ba ON ba.external_id = m.building_id
     JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
     JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
     JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text
  GROUP BY mu.id, mu.geom;

-- 3. The tile table carries the topic.
ALTER TABLE maplayer.incident_tiles
    ADD COLUMN IF NOT EXISTS topic text;

-- 4. The refresh reads the views, so the four tile tables follow the same rule.
--    The LEFT joins on the CBS chain are kept from the original: a pand without
--    a CBS id keeps its feature instead of disappearing.
CREATE OR REPLACE PROCEDURE maplayer.refresh_incident_tiles()
LANGUAGE sql
AS $$
    TRUNCATE maplayer.incident_tiles;

    INSERT INTO maplayer.incident_tiles (
        id, neighborhood_id, district_id, municipality_id,
        foundation_damage_cause, topic, height, geom
    )
    SELECT
        m.dossier_id::text,
        n.external_id,
        d2.external_id,
        mu.external_id,
        NULL::text,
        m.topic,
        round(GREATEST(bh.height, 0::real)::numeric, 2)::double precision,
        ST_Multi(ST_Transform(ba.geom, 3857))
    FROM ( SELECT DISTINCT ON (d.building_id) d.building_id,
                  d.id AS dossier_id,
                  d.payload ->> 'topic' AS topic
             FROM dataops.dossier d
            WHERE d.payload ->> 'topic' IS NOT NULL
              AND d.building_id IS NOT NULL
            ORDER BY d.building_id, d.created_at DESC) m
    JOIN geocoder.building_active ba ON ba.external_id = m.building_id
    JOIN data.building_height bh ON bh.building_id = ba.external_id
    LEFT JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    LEFT JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text;

    TRUNCATE maplayer.incident_neighborhood_tiles;

    INSERT INTO maplayer.incident_neighborhood_tiles (
        neighborhood_id, district_id, municipality_id, incident_count,
        geom, geom_simple
    )
    SELECT
        n.external_id,
        d2.external_id,
        mu.external_id,
        count(*),
        ST_Multi(ST_Transform(n.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(n.geom, 3857), 20.0))
    FROM ( SELECT DISTINCT d.building_id
             FROM dataops.dossier d
            WHERE d.payload ->> 'topic' IS NOT NULL
              AND d.building_id IS NOT NULL) m
    JOIN geocoder.building_active ba ON ba.external_id = m.building_id
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    LEFT JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text
    GROUP BY n.external_id, d2.external_id, mu.external_id, n.geom;

    TRUNCATE maplayer.incident_district_tiles;

    INSERT INTO maplayer.incident_district_tiles (
        district_id, municipality_id, incident_count, geom, geom_simple
    )
    SELECT
        d2.external_id,
        mu.external_id,
        count(*),
        ST_Multi(ST_Transform(d2.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(d2.geom, 3857), 20.0))
    FROM ( SELECT DISTINCT d.building_id
             FROM dataops.dossier d
            WHERE d.payload ->> 'topic' IS NOT NULL
              AND d.building_id IS NOT NULL) m
    JOIN geocoder.building_active ba ON ba.external_id = m.building_id
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text
    GROUP BY d2.external_id, mu.external_id, d2.geom;

    TRUNCATE maplayer.incident_municipality_tiles;

    INSERT INTO maplayer.incident_municipality_tiles (
        municipality_id, incident_count, geom, geom_simple
    )
    SELECT
        mu.external_id,
        count(*),
        ST_Multi(ST_Transform(mu.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(mu.geom, 3857), 20.0))
    FROM ( SELECT DISTINCT d.building_id
             FROM dataops.dossier d
            WHERE d.payload ->> 'topic' IS NOT NULL
              AND d.building_id IS NOT NULL) m
    JOIN geocoder.building_active ba ON ba.external_id = m.building_id
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    JOIN geocoder.district d2 ON d2.id::text = n.district_id::text
    JOIN geocoder.municipality mu ON mu.id::text = d2.municipality_id::text
    GROUP BY mu.external_id, mu.geom;

    ANALYZE maplayer.incident_tiles;
    ANALYZE maplayer.incident_neighborhood_tiles;
    ANALYZE maplayer.incident_district_tiles;
    ANALYZE maplayer.incident_municipality_tiles;
$$;

CALL maplayer.refresh_incident_tiles();
