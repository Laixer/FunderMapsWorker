INSERT INTO geocoder.residence(id, address_id, building_id, geom)
SELECT
    v.identificatie,
    a.external_id,
    b.external_id,
    ST_Transform(v.geom, 4326)
FROM public.verblijfsobject v
join geocoder.address a on a.external_id = v.nummeraanduiding_hoofdadres_identificatie
join geocoder.building b on b.external_id = v.pand_identificatie
ON CONFLICT (id, address_id, building_id)
DO NOTHING;