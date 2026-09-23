-- maplayer.facade_scan_tiles.risk_class groups the QuickScan's own risk, not the model's.
--
-- 20260918_003 added risk_class (a/b = laag, c = midden, d/e = hoog, Don's
-- mapping) but built it from `risk`, which is the MODEL risk (mg.risk in
-- maplayer.facade_scan, the column the dropped "Risico pand (model)" layer
-- painted). The QuickScan risk is `facade_scan_risk`, which is what the
-- "Risico" layer has always shown and what WebFront #303 groups into the same
-- three classes on the client.
--
-- What was true on prod on 2026-09-23, 2,398 rows in the tile table:
--   692 rows had a risk_class that does not match their facade_scan_risk
--       (e.g. 27 panden with QuickScan risk a were labelled hoog)
--   192 rows have no facade_scan_risk at all and still carried a class
--   so 884 rows change; the row count (2,398) does not
--
-- Nothing reads the column: maplayer.facade_scan() (the Martin source) does
-- not select it, so it never reached a tile, and no repo refers to it. The map
-- was right throughout. This makes the column mean what its name says before
-- anything starts to use it; the change is invisible on the map.
--
-- The procedure body is the live pg_get_functiondef with one change: the CASE
-- reads f.facade_scan_risk instead of f.risk. sql/model/create_facade_scan_tiles.sql
-- carries the same text.

CREATE OR REPLACE PROCEDURE maplayer.refresh_facade_scan_tiles()
LANGUAGE sql
AS $$
    TRUNCATE maplayer.facade_scan_tiles;

    INSERT INTO maplayer.facade_scan_tiles (
        external_id, neighborhood_id, district_id, municipality_id,
        height, owner, skewed_parallel_facade, skewed_perpendicular_facade,
        facade_type, settlement_speed, facade_scan_risk, risk, risk_class, priority, geom
    )
    SELECT
        f.external_id,
        f.neighborhood_id,
        f.district_id,
        f.municipality_id,
        f.height::double precision,
        f.owner,
        f.skewed_parallel_facade::text,
        f.skewed_perpendicular_facade::text,
        f.facade_type::text,
        f.settlement_speed::text,
        f.facade_scan_risk::text,
        f.risk::text,
        CASE f.facade_scan_risk::text
            WHEN 'a' THEN 'laag'
            WHEN 'b' THEN 'laag'
            WHEN 'c' THEN 'midden'
            WHEN 'd' THEN 'hoog'
            WHEN 'e' THEN 'hoog'
            ELSE NULL
        END,
        f.priority::text,
        ST_Multi(ST_Transform(f.geom, 3857))
    FROM maplayer.facade_scan f
    WHERE f.inquiry_type = 'facade_scan';

    ANALYZE maplayer.facade_scan_tiles;
$$;

ALTER PROCEDURE maplayer.refresh_facade_scan_tiles() OWNER TO fundermaps;

CALL maplayer.refresh_facade_scan_tiles();
