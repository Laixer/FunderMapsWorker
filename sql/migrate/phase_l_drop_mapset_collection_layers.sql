-- Phase L: drop redundant `layers` column from application.mapset_collection.
--
-- IMPORTANT CORRECTION: mapset_collection is a VIEW (not a table), so
-- DROP COLUMN is not supported. Instead we redefine the view to omit
-- the `layers` passthrough.
--
-- The underlying application.mapset.layers column STAYS — it's the
-- source of truth for which layer IDs belong to a mapset, and the
-- view's `layerset` jsonb_agg JOINs through it. We're only stripping
-- the column from the view's projection so API consumers stop
-- receiving the redundant text array.
--
-- Verified 2026-04-25:
--   * Zero views/matviews depend on mapset_collection
--   * Zero frontend consumers actually read the layers field
--   * C# MapsetRepository.cs has already had c.layers removed from
--     all 3 SELECT lists (FunderMaps commit 83986779)
--   * TS API + WebFront + Report interfaces already updated
--
-- Run as: fundermaps (owner)

BEGIN;

DROP VIEW application.mapset_collection;

CREATE VIEW application.mapset_collection AS
SELECT
    m.id,
    m.name,
    lower(regexp_replace(m.name, '\s+'::text, '-'::text, 'g'::text)) AS slug,
    m.style,
    m.metadata,
    m.public,
    m.consent,
    m.note,
    m.icon,
    m."order",
    (
        SELECT jsonb_agg(maplayers.layer) AS jsonb_agg
        FROM (
            SELECT l.*::application.mapset_layer AS layer
            FROM application.mapset_layer l
            WHERE l.id IN (
                SELECT unnest(m2.layers) AS unnest
                FROM application.mapset m2
                WHERE m2.id = m.id
            )
            ORDER BY l."order"
        ) maplayers
    ) AS layerset
FROM application.mapset m;

-- DROP VIEW destroys grants — re-establish to match sibling tables
-- (mapset, mapset_layer) which both grant SELECT to fundermaps_webapp
-- only.
GRANT SELECT ON application.mapset_collection TO fundermaps_webapp;

COMMIT;
