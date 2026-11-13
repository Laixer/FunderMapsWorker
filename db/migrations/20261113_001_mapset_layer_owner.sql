-- The ownership layer for the map (FunderMapsStudio #26): one more entry in the catalogue of map layers.
--
-- The new map (FunderMapsMap) draws the layer `owner` from the `owner` attribute of the building tiles and builds its
-- legend itself: only the owners that have buildings around the view, the largest with a colour of their own and the
-- rest as "Overig corporatiebezit". That is why `fields`, the fixed legend rows every other layer has, is empty here.
--
-- The row only makes the layer choosable. A mapset shows it once an administrator adds it to that mapset in the
-- Studio's Beheer; no mapset gets it from this migration. The current map app has no drawing rule for it and draws
-- nothing for it.
--
-- Prod 2026-11-13 (read-only): 30 layers, none for ownership; the highest "order" is 28 (building-cluster).

INSERT INTO application.mapset_layer (id, name, fields, "order")
VALUES ('owner', 'Eigendom', '[]'::jsonb, 29)
ON CONFLICT (id) DO NOTHING;
