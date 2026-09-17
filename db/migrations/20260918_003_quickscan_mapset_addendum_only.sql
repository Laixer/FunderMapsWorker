-- QuickScan mapset: addendum only, one risk layer, three risk classes.
--
-- Don's three points (Telegram 2026-09-17 20:30 CEST, approved by Yorick the
-- same evening; WebFront #302):
--   1. the QuickScan map must show QuickScan (addendum) only;
--   2. the layer "Risico pand (model)" is obsolete and goes;
--   3. "Risico pand (vastgesteld)" becomes "Risico" with Laag/Midden/Hoog only.
--
-- Measured before writing this (prod, 2026-09-17): maplayer.facade_scan filters
-- on data, not on inquiry type — both plumb-line values plus any crack field —
-- so the map carries 2,645 addendum buildings AND 1,164 from foundation_research
-- (plus 22 from other types). QuickScan (vervallen) contributes 14 of its
-- 130,037 samples, which is why nobody noticed it was not the source.
--
-- Where the change lands. The view keeps feeding the nightly GPKG export to
-- s3://fundermaps-data/mapset/, which is the permanent model history, so its
-- row set must NOT shrink: dropping 1,164 buildings from the archive would
-- rewrite history that has already been archived. The view therefore only
-- gains one column (inquiry_type) and the filter happens in the tile table,
-- which is what Martin serves and what the map reads.
--
-- risk_class groups the established A–E risk the way the melder mails do:
-- A/B = laag, C = midden, D/E = hoog (Don's mapping, confirmed 2026-09-17).
-- The Mapbox style (mapbox://styles/laixer/cliynyd6g01b801pges0bb7wh) still
-- paints five A–E stops; it must be pointed at risk_class right after this
-- migration, or the map shows five colours under a three-class legend.

-- 1. The view gains the inquiry type of the sample it picked per building.
--    CREATE OR REPLACE VIEW can only append columns, which is what this does;
--    the GPKG export gains a column and loses no rows.
CREATE OR REPLACE VIEW maplayer.facade_scan AS SELECT inputz.external_id,
    inputz.neighborhood_id,
    inputz.district_id,
    inputz.municipality_id,
    inputz.height,
    inputz.owner,
    inputz.skewed_parallel_facade,
    inputz.skewed_perpendicular_facade,
    inputz.facade_type,
    inputz.settlement_speed,
    inputz.facade_scan_risk,
    mg.risk,
    rtp.priority,
    inputz.geom,
    inputz.inquiry_type
   FROM ( SELECT DISTINCT ON (ba.external_id) ba.external_id,
            n.external_id AS neighborhood_id,
            d.external_id AS district_id,
            m.external_id AS municipality_id,
            round(GREATEST(bh.height, 0::real)::numeric, 2) AS height,
            bo.owner,
            COALESCE(is2.skewed_parallel_facade,
                CASE
                    WHEN is2.skewed_parallel::numeric < 75::numeric THEN 'very_big'::report.rotation_type
                    WHEN is2.skewed_parallel::numeric >= 75::numeric AND is2.skewed_parallel::numeric < 100::numeric THEN 'big'::report.rotation_type
                    WHEN is2.skewed_parallel::numeric >= 100::numeric AND is2.skewed_parallel::numeric < 200::numeric THEN 'mediocre'::report.rotation_type
                    WHEN is2.skewed_parallel::numeric >= 200::numeric AND is2.skewed_parallel::numeric < 300::numeric THEN 'small'::report.rotation_type
                    WHEN is2.skewed_parallel::numeric >= 300::numeric THEN 'nil'::report.rotation_type
                    ELSE NULL::report.rotation_type
                END) AS skewed_parallel_facade,
            COALESCE(is2.skewed_perpendicular_facade,
                CASE
                    WHEN is2.skewed_perpendicular::numeric < 75::numeric THEN 'very_big'::report.rotation_type
                    WHEN is2.skewed_perpendicular::numeric >= 75::numeric AND is2.skewed_perpendicular::numeric < 100::numeric THEN 'big'::report.rotation_type
                    WHEN is2.skewed_perpendicular::numeric >= 100::numeric AND is2.skewed_perpendicular::numeric < 200::numeric THEN 'mediocre'::report.rotation_type
                    WHEN is2.skewed_perpendicular::numeric >= 200::numeric AND is2.skewed_perpendicular::numeric < 300::numeric THEN 'small'::report.rotation_type
                    WHEN is2.skewed_perpendicular::numeric >= 300::numeric THEN 'nil'::report.rotation_type
                    ELSE NULL::report.rotation_type
                END) AS skewed_perpendicular_facade,
            GREATEST(COALESCE(is2.crack_facade_front_type,
                CASE
                    WHEN is2.crack_facade_front_size::integer = 0 THEN 'nil'::report.crack_type
                    WHEN is2.crack_facade_front_size::integer = 1 THEN 'small'::report.crack_type
                    WHEN is2.crack_facade_front_size::integer > 1 AND is2.crack_facade_front_size::integer < 3 THEN 'mediocre'::report.crack_type
                    WHEN is2.crack_facade_front_size::integer >= 3 THEN 'big'::report.crack_type
                    ELSE NULL::report.crack_type
                END), COALESCE(is2.crack_facade_back_type,
                CASE
                    WHEN is2.crack_facade_back_size::integer = 0 THEN 'nil'::report.crack_type
                    WHEN is2.crack_facade_back_size::integer = 1 THEN 'small'::report.crack_type
                    WHEN is2.crack_facade_back_size::integer > 1 AND is2.crack_facade_back_size::integer < 3 THEN 'mediocre'::report.crack_type
                    WHEN is2.crack_facade_back_size::integer >= 3 THEN 'big'::report.crack_type
                    ELSE NULL::report.crack_type
                END), COALESCE(is2.crack_facade_left_type,
                CASE
                    WHEN is2.crack_facade_left_size::integer = 0 THEN 'nil'::report.crack_type
                    WHEN is2.crack_facade_left_size::integer = 1 THEN 'small'::report.crack_type
                    WHEN is2.crack_facade_left_size::integer > 1 AND is2.crack_facade_left_size::integer < 3 THEN 'mediocre'::report.crack_type
                    WHEN is2.crack_facade_left_size::integer >= 3 THEN 'big'::report.crack_type
                    ELSE NULL::report.crack_type
                END), COALESCE(is2.crack_facade_right_type,
                CASE
                    WHEN is2.crack_facade_right_size::integer = 0 THEN 'nil'::report.crack_type
                    WHEN is2.crack_facade_right_size::integer = 1 THEN 'small'::report.crack_type
                    WHEN is2.crack_facade_right_size::integer > 1 AND is2.crack_facade_right_size::integer < 3 THEN 'mediocre'::report.crack_type
                    WHEN is2.crack_facade_right_size::integer >= 3 THEN 'big'::report.crack_type
                    ELSE NULL::report.crack_type
                END)) AS facade_type,
                CASE
                    WHEN abs(is2.settlement_speed) < 0.5::double precision THEN 'nil'::report.rotation_type
                    WHEN abs(is2.settlement_speed) >= 0.5::double precision AND abs(is2.settlement_speed) < 2::double precision THEN 'small'::report.rotation_type
                    WHEN abs(is2.settlement_speed) >= 2::double precision AND abs(is2.settlement_speed) < 3::double precision THEN 'mediocre'::report.rotation_type
                    WHEN abs(is2.settlement_speed) >= 3::double precision AND abs(is2.settlement_speed) < 4::double precision THEN 'big'::report.rotation_type
                    WHEN abs(is2.settlement_speed) >= 4::double precision THEN 'very_big'::report.rotation_type
                    ELSE NULL::report.rotation_type
                END AS settlement_speed,
            is2.facade_scan_risk,
            ba.geom,
            i.type::text AS inquiry_type
           FROM report.inquiry_sample is2
             JOIN report.inquiry i ON i.id = is2.inquiry_id
             JOIN geocoder.building_active ba ON ba.external_id = is2.building_id::text
             JOIN data.building_height bh ON bh.building_id = ba.external_id
             LEFT JOIN data.building_ownership bo ON bo.building_id = ba.external_id
             JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
             JOIN geocoder.district d ON d.id::text = n.district_id::text
             JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text
          WHERE is2.skewed_parallel IS NOT NULL AND is2.skewed_perpendicular IS NOT NULL AND (is2.crack_facade_front_type IS NOT NULL OR is2.crack_facade_front_size IS NOT NULL OR is2.crack_facade_back_type IS NOT NULL OR is2.crack_facade_back_size IS NOT NULL OR is2.crack_facade_left_type IS NOT NULL OR is2.crack_facade_left_size IS NOT NULL OR is2.crack_facade_right_type IS NOT NULL OR is2.crack_facade_right_size IS NOT NULL)
          ORDER BY ba.external_id, is2.create_date DESC) inputz
     JOIN data.model_gevelscan mg ON mg.skewed_parallel = inputz.skewed_parallel_facade AND mg.skewed_perpendicular = inputz.skewed_perpendicular_facade AND mg.facade_type = inputz.facade_type
     LEFT JOIN data.risk_table_priority rtp ON rtp.risk = mg.risk AND rtp.settlement_speed = inputz.settlement_speed;

-- 2. The tile table gains risk_class; Martin publishes it with the rest.
ALTER TABLE maplayer.facade_scan_tiles
    ADD COLUMN IF NOT EXISTS risk_class text;

-- 3. The refresh keeps addendum rows only and fills risk_class.
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
        CASE f.risk::text
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

CALL maplayer.refresh_facade_scan_tiles();

-- 4. The mapset config: drop the obsolete layer, rename the other, three classes.
UPDATE application.mapset
   SET layers = array_remove(layers, 'facade-risk')
 WHERE id = 'cliynyd6g01b801pges0bb7wh';

UPDATE application.mapset_layer
   SET name = 'Risico',
       fields = '[{"name":"Laag","color":"42FF33"},{"name":"Midden","color":"FFEC33"},{"name":"Hoog","color":"FF5533"}]'::jsonb
 WHERE id = 'facade-risk-established';
