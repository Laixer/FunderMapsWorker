-- Put back the description of data.product_tracker_daily (FunderMaps 5.0, loose end L5).
--
-- The online product_tracker switch (scripts/ops/product-tracker-plain, 2026-10-15) rebuilt this summary on the
-- plain table and swapped it in with the same unique index, owner and grants, but not its COMMENT: the
-- schema.sql regeneration after 20261015_002 showed it missing on prod. The text is the one schema.sql carried
-- before the switch. The tool now copies the comment too.

COMMENT ON MATERIALIZED VIEW data.product_tracker_daily IS 'Webservice/map usage per Amsterdam-local day, organization and product. Source: application.product_tracker. Refreshed by the refresh_data_model flow.';
