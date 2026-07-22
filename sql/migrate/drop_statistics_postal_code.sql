-- One-shot: drop the postal-code statistics matviews (applied to prod 2026-07-22).
--
-- Refreshed nightly by the Windmill flow but read by nothing: no queries in
-- FunderMapsApi/Webservice/C#, no dashboard reads in the stats window (scan
-- count equalled the refresh count exactly). Yorick 2026-07-22: fewer moving
-- parts. The three f/fundermaps/data/refresh_statistics_postal_code_* Windmill
-- scripts are archived and their flow steps removed in the same change.
--
-- Definitions live in git history (schema.sql before this commit) if a
-- postal-code statistics product ever materializes; they rebuild from
-- geocoder.address + data.model_risk_static in minutes.

DROP MATERIALIZED VIEW IF EXISTS
    data.statistics_postal_code_data_collected,
    data.statistics_postal_code_foundation_risk,
    data.statistics_postal_code_foundation_type;
