-- model-2026.2 candidate: the map layer, visible ONLY to FunderMaps B.V.
-- Apply AFTER the migration 20260924_001 and AFTER the table is loaded
-- (see README.md). Plain configuration rows; remove with the three DELETEs
-- at the bottom (commented out).
--
-- WebFront reads the layer style from src/config/layers/foundation-candidate.json
-- (WebFront PR "feat: candidate model-2026.2 layer"); the tile source
-- "foundation_candidate" is the Martin function maplayer.foundation_candidate.

BEGIN;

INSERT INTO application.mapset_layer (id, name, fields, "order")
VALUES ('foundation-candidate', 'Funderingstype kandidaat 2026.2',
        '[{"name": "Houten paal", "color": "8c3a28"},
          {"name": "Betonnen paal", "color": "6a6c70"},
          {"name": "Ondiepe fundering", "color": "ce0015"},
          {"name": "Lichte kleur = geen lokaal bewijs", "color": "c9a79f"}]'::jsonb,
        0);

INSERT INTO application.mapset (id, name, style, layers, public, icon, note, "order")
VALUES ('model-2026-2-candidate', 'Kandidaat funderingstype 2026.2',
        'mapbox://styles/laixer/clcqkb4vp006w14qhzv7rfznm',
        ARRAY['foundation-candidate'], false, 'foundation',
        'Proefmodel (Worker #152), alleen FunderMaps B.V. Niet voor klanten.', 99);

INSERT INTO application.organization_mapset (organization_id, mapset_id)
VALUES ('d8c19418-c832-4c91-8993-84b8ed641448', 'model-2026-2-candidate');  -- FunderMaps B.V.

COMMIT;

-- Remove again:
-- DELETE FROM application.organization_mapset WHERE mapset_id = 'model-2026-2-candidate';
-- DELETE FROM application.mapset WHERE id = 'model-2026-2-candidate';
-- DELETE FROM application.mapset_layer WHERE id = 'foundation-candidate';
