-- HotSpot map layer for the Risico mapset (issue Laixer/FunderMaps#919).
--
-- A HotSpot is a building whose HIGHEST risk class across the two
-- groundwater-driven models is D or E:
--
--     MAX(drystand_risk, dewatering_depth_risk) >= 'd'
--
-- The classes are ordered a < b < c < d < e, so "the maximum" is simply the
-- worse of the two; A/B/C are excluded entirely. The layer is a fast visual
-- answer to "where should we look first", not a new model.
--
-- No data work is needed: maplayer.building_tiles already carries both
-- drystand_risk and dewatering_depth_risk, and maplayer.buildings(z,x,y)
-- emits both at every zoom (z12-13 included), so the whole layer is a
-- MapLibre filter + paint expression over the existing 'buildings' tile
-- source. Styling lives in FunderMapsWebFront src/config/layers/hotspot.json
-- and must stay in sync with the legend below.
--
-- Scope on 2026-07-26: 165,286 of 6,449,590 buildings (2.6%) qualify -
-- 8,817 with a worst class of E, 156,469 with D.

--------------------------------------------------------------------------------
-- 1. Legend. Two entries, reusing the exact D and E colors of the existing
--    drystand-risk / dewatering-depth-risk legends so the HotSpot layer reads
--    as a summary of those two rather than a separate scale.
--    "order" = 0 puts HotSpot at the top of the Risico legend, above the
--    individual model layers it summarizes.
--------------------------------------------------------------------------------

INSERT INTO application.mapset_layer (id, name, fields, "order") VALUES (
    'hotspot',
    'HotSpot',
    '[
        {"name": "Verhoogd risico (D)", "color": "FFAC33"},
        {"name": "Hoog risico (E)",     "color": "FF5533"}
    ]'::jsonb,
    0
)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, fields = EXCLUDED.fields;

--------------------------------------------------------------------------------
-- 2. Attach to the Risico mapset.
--------------------------------------------------------------------------------

UPDATE application.mapset
SET layers = array_append(layers, 'hotspot')
WHERE id = 'clcqkaaea000714o1v1jmdqwf'
  AND NOT ('hotspot' = ANY (layers));
