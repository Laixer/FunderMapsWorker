-- One-shot: drop the five retired maplayer.analysis_* tile-source views
-- (applied to prod 2026-07-24).
--
-- The Martin tileserver cutover (tiles.fundermaps.com, 2026-07-23) moved all
-- analysis layers in WebFront (#268) and Report (#56) onto the dynamic
-- 'buildings' source backed by maplayer.building_tiles. The static
-- tippecanoe tilesets for these views were disabled in maplayer.bundle and
-- no layer config references them anymore, leaving the views orphaned.
--
-- Kept on purpose:
--   - maplayer.analysis_full: bundle row is alive as GPKG-export-only; it
--     feeds the nightly dataset archive (model-run diff raw material).
--   - maplayer.building_cluster: WebFront's "Pand" mapset still ships the
--     building-cluster layer against its (stale) static tiles — pending a
--     separate keep-or-drop decision.
--
-- The four thin views were plain projections of data.building_geo_hierarchy;
-- analysis_monitoring queried report.inquiry_sample directly. If any of them
-- return, serve them from Martin as function sources instead.
--
-- NOTE: sql/model/consolidate_analysis_views.sql and sql/model/
-- fix_statistics.sql (Fix 5) still contain CREATE OR REPLACE statements for
-- these views — do not re-run those blocks as-is (trim tracked separately).

DROP VIEW IF EXISTS
    maplayer.analysis_building,
    maplayer.analysis_foundation,
    maplayer.analysis_monitoring,
    maplayer.analysis_report,
    maplayer.analysis_risk;
