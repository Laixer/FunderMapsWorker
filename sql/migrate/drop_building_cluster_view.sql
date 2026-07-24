-- One-shot: retire the static building_cluster tile chain (applied to prod
-- 2026-07-24).
--
-- The building-cluster map layer is now served live by Martin from
-- maplayer.building_cluster_tiles (sql/model/create_building_cluster_tiles.sql,
-- WebFront #272). The old view fed a tippecanoe tileset whose tiles had been
-- frozen in Spaces since Sep 2024 (bundle row disabled); the Spaces prefix
-- fundermaps-tileset/building_cluster/ is deleted alongside.
--
-- Note: the maplayer.building_cluster(z,x,y) FUNCTION (the Martin source)
-- shares the name — functions and relations live in different namespaces,
-- so only the view goes.

DROP VIEW IF EXISTS maplayer.building_cluster;

DELETE FROM maplayer.bundle WHERE tileset = 'building_cluster';
