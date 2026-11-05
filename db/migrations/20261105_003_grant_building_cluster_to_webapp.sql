-- Studio #14: the API may read data.building_cluster, to pre-select the block when panden are chosen on the map (Worker #307:
-- same cluster and same build year).
--
-- True on prod 2026-11-04: a plain table, ~6.35M rows, not rebuilt by the refresh, so the grant holds; indexed on building_id
-- and on (cluster_id, building_id). fundermaps_api, the API's role, inherits from fundermaps_webapp and can't read it yet.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
    RAISE NOTICE 'role fundermaps_webapp does not exist; nothing changed';
    RETURN;
  END IF;

  GRANT SELECT ON data.building_cluster TO fundermaps_webapp;

  IF NOT has_table_privilege('fundermaps_webapp', 'data.building_cluster', 'SELECT') THEN
    RAISE EXCEPTION 'fundermaps_webapp still cannot read data.building_cluster';
  END IF;
END $$;
