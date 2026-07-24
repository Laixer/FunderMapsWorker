-- One-shot: delete retired maplayer.bundle rows (applied to prod 2026-07-24).
--
-- All six rows were already enabled = FALSE, so process_mapset never
-- selected them; this just removes the dead config. The five analysis_*
-- rows lost their source views in drop_analysis_tile_views.sql (Martin
-- cutover); building_supercluster lost its view earlier in
-- drop_country_model_supply_supercluster.sql.
--
-- Kept: analysis_full (GPKG-export-only, feeds the dataset archive),
-- facade_scan + incident* (live tippecanoe tilesets), and building_cluster
-- (disabled but keep-or-drop still pending — WebFront's "Pand" mapset
-- still references its stale static tiles).
--
-- Verified no other consumers: the C# monolith's BundleRepository is
-- referenced by no deployed endpoint, and the Bun webservice never reads
-- maplayer.bundle.

DELETE FROM maplayer.bundle
WHERE tileset IN (
    'analysis_building',
    'analysis_foundation',
    'analysis_monitoring',
    'analysis_report',
    'analysis_risk',
    'building_supercluster'
);
