-- Put the model output behind a pointer, so a second model can exist.
--
-- Step 2 of docs/model-versioning.md. The matview keeping the generic name is
-- what blocks a second model: there is no room for `model-2026.1` while
-- `model_risk_static` IS the 2024.1 output rather than pointing at it.
--
-- After this, `data.model_risk_static` is a view onto the current default and
-- every consumer that names it keeps working untouched -- which is all of them:
-- FunderMapsWebservice/src/routes/product.ts (the billable product),
-- FunderMapsApi/src/routes/product.ts and its Drizzle schema, sql/validate/,
-- and the three database objects below. None need changing.
--
-- TWO THINGS DO BREAK and are handled outside this file, because you cannot
-- REFRESH a view:
--   * Windmill f/fundermaps/data/refresh_risk_model -- updated to the new name
--     in the same session as this migration. If it is missed, the next
--     scheduled refresh fails.
--   * scripts/build_seed.ts:443 -- same statement, dev seed path.
--
-- The three dependents (data.building_geo_hierarchy,
-- data.statistics_product_foundation_risk, data.statistics_product_foundation_type,
-- and maplayer.analysis_full behind them) follow the rename automatically,
-- because Postgres tracks dependencies by OID rather than by name. They end up
-- bound to the concrete 2024.1 matview rather than to the pointer.
--
-- That is deliberate and identical in behaviour today, since 2024.1 IS the
-- default. It becomes a decision at step 4, when a different model becomes
-- default: each of those objects then has to be pointed at either the pointer
-- view (track the default) or a specific version (stay put). Repointing the two
-- statistics matviews needs DROP ... CASCADE through maplayer.analysis_full, so
-- it is not worth doing tonight for zero behavioural change.
--
-- Reversible: DROP the view, rename the matview and its indexes back.
--
--   psql "$DB_URL" -f sql/migrate/rename_model_risk_static_to_version.sql

BEGIN;

ALTER MATERIALIZED VIEW data.model_risk_static RENAME TO model_risk_static_2024_1;

-- Indexes do not follow a rename, and 'model_risk_static_pkey' sitting on the
-- 2024.1 matview would be actively misleading once a second model exists.
-- The pkey is also what makes REFRESH ... CONCURRENTLY possible, so it matters
-- that it stays attached and findable.
ALTER INDEX data.model_risk_static_pkey
    RENAME TO model_risk_static_2024_1_pkey;
ALTER INDEX data.model_risk_static_neighborhood_id_idx
    RENAME TO model_risk_static_2024_1_neighborhood_id_idx;

-- The pointer. Switching the default later is a CREATE OR REPLACE VIEW.
CREATE VIEW data.model_risk_static AS
SELECT * FROM data.model_risk_static_2024_1;

COMMENT ON VIEW data.model_risk_static IS
    'Pointer at the default model version. Consumers should name this, not a versioned matview. Switch the default with CREATE OR REPLACE VIEW. See docs/model-versioning.md.';

-- Match the grants the matview carried: read for the two application roles.
-- fundermaps_windmill keeps its own rights on the underlying matview, which is
-- what it needs to REFRESH; it gets read on the pointer for convenience.
GRANT SELECT ON data.model_risk_static TO fundermaps_webapp;
GRANT SELECT ON data.model_risk_static TO fundermaps_webservice;
GRANT SELECT ON data.model_risk_static TO fundermaps_windmill;

COMMIT;
