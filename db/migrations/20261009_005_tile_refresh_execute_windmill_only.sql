-- Only Windmill (plus the owner) may run the tile refresh procedures.
--
-- maplayer.refresh_building_tiles() and refresh_building_cluster_tiles() are
-- SECURITY DEFINER (owner `fundermaps`) and rebuild the building tile tables:
-- minutes of heavy work each, and two overlapping runs collide on the same
-- `_next` table. Like every function, they were executable by PUBLIC, so any
-- login (grafana, the tileserver, the webservice, fundie_agent) could start a
-- rebuild. refresh_facade_scan_tiles() and refresh_incident_tiles() run with
-- the caller's rights, so PUBLIC could not do much with them; they get the same
-- rule so all four are alike.
--
-- True on prod 2026-10-09 (DB grant audit; read-only checks):
--   * The only callers are Windmill (`refresh_building_tiles`,
--     `refresh_building_cluster_tiles`, `refresh_layer_tiles` scripts, as
--     fundermaps_windmill) and migrations (as doadmin, a member of the owner
--     fundermaps). The owner and its members keep EXECUTE without a grant.
--   * None of the four had an explicit ACL (default: PUBLIC EXECUTE).
--
-- CREATE OR REPLACE PROCEDURE keeps these privileges; DROP + CREATE resets them
-- to PUBLIC, so a migration that does that must repeat this.
--
-- Where fundermaps_windmill does not exist the file raises a NOTICE and changes
-- nothing. It fails if PUBLIC can still execute any of them afterwards.

DO $$
DECLARE
    leftover text;
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_windmill') THEN
        RAISE NOTICE 'role fundermaps_windmill does not exist; nothing changed';
        RETURN;
    END IF;

    REVOKE EXECUTE ON PROCEDURE
        maplayer.refresh_building_tiles(),
        maplayer.refresh_building_cluster_tiles(),
        maplayer.refresh_facade_scan_tiles(),
        maplayer.refresh_incident_tiles()
        FROM PUBLIC;
    GRANT EXECUTE ON PROCEDURE
        maplayer.refresh_building_tiles(),
        maplayer.refresh_building_cluster_tiles(),
        maplayer.refresh_facade_scan_tiles(),
        maplayer.refresh_incident_tiles()
        TO fundermaps_windmill;

    SELECT string_agg(p.oid::regprocedure::text, ', ') INTO leftover
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'maplayer'
      AND p.proname IN ('refresh_building_tiles', 'refresh_building_cluster_tiles',
                        'refresh_facade_scan_tiles', 'refresh_incident_tiles')
      AND (EXISTS (SELECT FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
                   WHERE x.grantee = 0 AND x.privilege_type = 'EXECUTE')
           OR NOT has_function_privilege('fundermaps_windmill', p.oid, 'EXECUTE'));
    IF leftover IS NOT NULL THEN
        RAISE EXCEPTION 'PUBLIC can still execute, or fundermaps_windmill cannot: %', leftover;
    END IF;
END
$$;
