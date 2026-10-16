-- An incident on the map carries its pand, so a click opens that pand.
--
-- Decision 30 of the logged-in sweep (Yorick, 2026-10-13). On the mapset
-- "Incidenten" a click on a marked pand opened "Geen data beschikbaar": the
-- tile's `id` was the number of the melding (`dataops.dossier.id`), and the map
-- app opens whatever id the clicked feature carries as a pand. Since
-- 20260918_004 the layer is one row per pand (its most recent melding), so the
-- pand is the natural key: `id` is now the pand's BAG id. The app needs no
-- change (it reads `building_id`, `external_id` or `id`), and the number of a
-- melding no longer travels in a tile, which nothing used and which Don's rule
-- for this layer ("the pand and the topic and nothing else", 2026-09-18) does
-- not allow for.
--
-- Nothing else changes: the same panden, the same topic, the same three
-- aggregates. Both definitions below are the live ones of 2026-10-13 (read
-- with pg_get_viewdef / pg_get_functiondef) with that one column changed.
-- Owner and grants stay as they are: CREATE OR REPLACE keeps both.
--
-- Prod on 2026-10-13: 2,115 rows in maplayer.incident_tiles, one per pand.

CREATE OR REPLACE VIEW maplayer.incident AS
 SELECT m.building_id AS id,
    NULL::report.foundation_damage_cause AS foundation_damage_cause,
    round(GREATEST(bh.height, 0::real)::numeric, 2) AS height,
    ba.geom,
    m.topic
   FROM ( SELECT DISTINCT ON (d.building_id) d.building_id,
            d.payload ->> 'topic'::text AS topic
           FROM dataops.dossier d
          WHERE d.payload ->> 'topic'::text IS NOT NULL
            AND d.building_id IS NOT NULL
          ORDER BY d.building_id, d.created_at DESC) m
     JOIN geocoder.building_active ba ON ba.external_id = m.building_id
     JOIN data.building_height bh ON bh.building_id = ba.external_id;

CREATE OR REPLACE PROCEDURE maplayer.refresh_incident_tiles()
 LANGUAGE sql
AS $procedure$
    TRUNCATE maplayer.incident_tiles;

    INSERT INTO maplayer.incident_tiles (
        id, neighborhood_id, district_id, municipality_id,
        foundation_damage_cause, topic, height, geom
    )
    SELECT
        m.building_id,
        n.external_id,
        d2.external_id,
        mu.external_id,
        NULL::text,
        m.topic,
        round(GREATEST(bh.height, 0::real)::numeric, 2)::double precision,
        ST_Multi(ST_Transform(ba.geom, 3857))
    FROM ( SELECT DISTINCT ON (d.building_id) d.building_id,
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
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(n.geom, 3857), 20.0::double precision))
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
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(d2.geom, 3857), 20.0::double precision))
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
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(mu.geom, 3857), 20.0::double precision))
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
$procedure$;

-- The tiles are rebuilt twice a day with the model refresh; do it now, so the
-- click works from the moment this is applied.
CALL maplayer.refresh_incident_tiles();
