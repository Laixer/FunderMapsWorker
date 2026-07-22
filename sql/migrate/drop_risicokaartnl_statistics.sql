-- One-shot: retire RisicokaartNL and the statistics_foundation_risk tile chain.
--
-- The RisicokaartNL mapset was internal-only (FunderMaps B.V.) and style-only:
-- it rendered from the Mapbox-hosted tileset laixer.statistics_foundation_risk
-- (baked into style laixer/cljwpspv0022v01p5a74ba87v), which was last uploaded
-- 2024-08-27 by the retired C# MapboxService pipeline — frozen ever since.
-- Meanwhile the nightly tippecanoe build of maplayer.statistics_foundation_risk
-- to Spaces had no consumer at all (WebFront read the layer from the Mapbox
-- composite source; FunderMapsReport uses analysis_building/incident_district).
--
-- Leaves data.statistics_product_foundation_risk untouched — the API/WS
-- statistics endpoints still serve it. Manual follow-up outside this DB:
-- delete the Mapbox style + tileset in Studio, and the
-- fundermaps-tileset/statistics_foundation_risk/ prefix in Spaces.
--
-- Row snapshots (for rollback):
--   mapset: {"id":"cljwpspv0022v01p5a74ba87v","name":"RisicokaartNL",
--            "style":"mapbox://styles/laixer/cljwpspv0022v01p5a74ba87v",
--            "layers":null,"public":false,"order":0}
--   organization_mapset: org d8c19418-c832-4c91-8993-84b8ed641448
--   bundle: {"tileset":"statistics_foundation_risk","enabled":true,
--            "name":"RiskNL","zoom_min_level":7,"zoom_max_level":11,
--            "generate_tileset":false,"upload_dataset":false}

BEGIN;

-- organization_mapset rows cascade via FK.
DELETE FROM application.mapset WHERE id = 'cljwpspv0022v01p5a74ba87v';

DELETE FROM maplayer.bundle WHERE tileset = 'statistics_foundation_risk';

DROP VIEW IF EXISTS maplayer.statistics_foundation_risk;

COMMIT;
