INSERT INTO geocoder.building(built_year, is_active, geom, external_id, building_type, neighborhood_id, zone_function)
SELECT
    case
        when p.bouwjaar > 2099 then null
        when p.bouwjaar < 899 then null
        else to_date(p.bouwjaar::text, 'YYYY')
    end,
    case lower(p.status)
        when 'bouwvergunning verleend' then false
        else true
    end,
    ST_Multi(ST_Transform(p.geom, 4326)),
    p.identificatie,
    'house',
    null,
    (
        SELECT
            array_agg(
                CASE zone_function
                    when 'bijeenkomstfunctie' then 'assembly'::geocoder.zone_function
                    when 'sportfunctie' then 'sport'::geocoder.zone_function
                    when 'celfunctie' then 'prison'::geocoder.zone_function
                    when 'gezondheidszorgfunctie' then 'medical'::geocoder.zone_function
                    when 'industriefunctie' then 'industry'::geocoder.zone_function
                    when 'kantoorfunctie' then 'office'::geocoder.zone_function
                    when 'logiesfunctie' then 'accommodation'::geocoder.zone_function
                    when 'onderwijsfunctie' then 'education'::geocoder.zone_function
                    when 'winkelfunctie' then 'retail'::geocoder.zone_function
                    when 'woonfunctie' then 'residential'::geocoder.zone_function
                    else 'other'::geocoder.zone_function
                END
            )
        FROM (
            SELECT pa.identificatie, unnest(string_to_array(pa.gebruiksdoel, ',')) AS zone_function
            FROM public.pand pa
            WHERE pa.identificatie = p.identificatie
        )
    )
FROM public.pand p
ON CONFLICT (external_id)
DO UPDATE
    SET built_year = excluded.built_year,
    is_active = excluded.is_active,
    geom = excluded.geom,
    zone_function = excluded.zone_function;

INSERT INTO geocoder.building(built_year, is_active, geom, external_id, building_type, neighborhood_id)
SELECT
    null,
    true,
    ST_Multi(ST_Transform(l.geom, 4326)),
    l.identificatie,
    'houseboat',
    null
FROM public.ligplaats l
ON CONFLICT (external_id)
DO UPDATE
    SET geom = excluded.geom;
    
INSERT INTO geocoder.building(built_year, is_active, geom, external_id, building_type, neighborhood_id)
SELECT
    null,
    true,
    ST_Multi(ST_Transform(s.geom, 4326)),
    s.identificatie,
    'mobile_home',
    null
FROM public.standplaats s
ON CONFLICT (external_id)
DO UPDATE
    SET geom = excluded.geom;

UPDATE geocoder.building
SET is_active = false
WHERE NOT EXISTS (
    SELECT 1
    FROM public.pand
    WHERE public.pand.identificatie = geocoder.building.external_id
)
AND geocoder.building.is_active = true
AND geocoder.building.external_id like 'NL.IMBAG.PAND.%';

UPDATE geocoder.building
SET neighborhood_id = n.id
FROM geocoder.neighborhood n
WHERE ST_Contains(n.geom, geocoder.building.geom)
AND neighborhood_id IS NULL;
