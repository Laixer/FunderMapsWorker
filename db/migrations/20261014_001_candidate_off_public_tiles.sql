-- The model-2026.2 candidate leaves the public tile server.
--
-- Infra review 2026-10-09, H4; FunderMaps 5.0 start list, loose end L6 (Yorick,
-- 2026-10-14: "L6 first"). Martin publishes every function in schema maplayer
-- to anyone who asks, without a login: tiles.fundermaps.com/foundation_candidate
-- served the per-pand candidate (type, probabilities, grade, evidence) for the
-- whole country, and /catalog listed it. "FunderMaps B.V. only" was a filter in
-- the map app, not on the tiles. A candidate is not served to customers
-- (docs/model-versioning.md), and per-pand model output is the paid product.
--
-- What this does:
--   1. moves the tile function from maplayer to data. Martin publishes only
--      maplayer (tileserver/config.yaml, auto_publish), so after its next
--      restart the source and its /catalog entry are gone;
--   2. takes EXECUTE on the function away from PUBLIC (functions get it by
--      default, so every role could call it) and from fundermaps_tileserver,
--      and SELECT on data.model_foundation_2026_2 from fundermaps_tileserver:
--      even a changed Martin config cannot read the candidate any more;
--   3. unlinks the mapset 'model-2026-2-candidate' from FunderMaps B.V., so the
--      map app stops offering a layer whose tiles no longer exist.
--
-- Kept, on purpose: the table, the function itself (now data.foundation_candidate,
-- for a staff-only tile route in the API later), the mapset and layer rows and
-- the registry row. Windmill and fundie_agent keep their read access.
--
-- Apply, then restart the tileserver (any deploy does it): until the restart
-- Martin still lists the source and its requests fail.
--
-- Roll back (and restart the tileserver):
--   ALTER FUNCTION data.foundation_candidate(integer, integer, integer) SET SCHEMA maplayer;
--   GRANT EXECUTE ON FUNCTION maplayer.foundation_candidate(integer, integer, integer) TO PUBLIC, fundermaps_tileserver;
--   GRANT SELECT ON data.model_foundation_2026_2 TO fundermaps_tileserver;
--   INSERT INTO application.organization_mapset (organization_id, mapset_id)
--   VALUES ('d8c19418-c832-4c91-8993-84b8ed641448', 'model-2026-2-candidate');
--
-- Prod on 2026-10-14 (read-only): the function is owned by fundermaps with ACL
-- {=X/fundermaps, fundermaps=X/fundermaps, fundermaps_tileserver=X/fundermaps};
-- the table grants SELECT to fundermaps_windmill, fundermaps_tileserver and
-- fundie_agent.

-- Fails loudly when the function is not where 20260928_002 put it.
ALTER FUNCTION maplayer.foundation_candidate(integer, integer, integer) SET SCHEMA data;

REVOKE EXECUTE ON FUNCTION data.foundation_candidate(integer, integer, integer) FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        REVOKE EXECUTE ON FUNCTION data.foundation_candidate(integer, integer, integer)
            FROM fundermaps_tileserver;
        REVOKE SELECT ON data.model_foundation_2026_2 FROM fundermaps_tileserver;
    END IF;
END $$;

-- The function's COMMENT (its TileJSON) stays as it is, so a rollback restores
-- the source exactly.

DELETE FROM application.organization_mapset
 WHERE mapset_id = 'model-2026-2-candidate'
   AND organization_id = 'd8c19418-c832-4c91-8993-84b8ed641448';
