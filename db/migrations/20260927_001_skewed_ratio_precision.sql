-- Widen report.inquiry_sample.skewed_parallel / skewed_perpendicular from numeric(5,2) to numeric(7,2) (Worker #223).
--
-- Why: these hold the lintvoeg ratio denominator (1 : n). numeric(5,2) tops out at 999.99, so a measurement of
-- 1 : 1000 or flatter -- a BETTER pand -- cannot be stored. 2026-09-25 16:20 CEST the commit of dossier 5599
-- (1 : 1117) failed with "numeric field overflow" (API 500). Prod values (Worker #223): median 300, p90 ~700.
--
-- The columns use the domain report.length (numeric(5,2), shared with many level columns), so they move to a plain
-- numeric(7,2) instead of widening the domain. report.inquiry_sample is small (rewrite, if any, is quick). The only dependent object is the view
-- maplayer.facade_scan (live pg_depend, 2026-09-27; nothing depends on the view itself), so it is dropped and
-- recreated with its LIVE definition (pg_get_viewdef, 2026-09-27), unchanged, plus its owner and grants.
-- maplayer.facade_scan(z,x,y) is plpgsql and resolves the view at run time, so it needs nothing.

DROP VIEW maplayer.facade_scan;

ALTER TABLE report.inquiry_sample
    ALTER COLUMN skewed_parallel TYPE numeric(7,2),
    ALTER COLUMN skewed_perpendicular TYPE numeric(7,2);

CREATE VIEW maplayer.facade_scan AS
 SELECT inputz.external_id,
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
     LEFT JOIN data.risk_table_priority rtp ON rtp.risk = mg.risk AND rtp.settlement_speed = inputz.settlement_speed
;

ALTER VIEW maplayer.facade_scan OWNER TO fundermaps;

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_windmill') THEN
        GRANT SELECT ON maplayer.facade_scan TO fundermaps_windmill;
    END IF;
END $$;
