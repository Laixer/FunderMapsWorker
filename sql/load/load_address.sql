INSERT INTO geocoder.address(building_number, postal_code, street, external_id, city, building_id)
SELECT
    concat(v.huisnummer, v.huisletter, v.toevoeging),
    v.postcode,
    v.openbare_ruimte_naam,
    v.nummeraanduiding_hoofdadres_identificatie,
    v.woonplaats_naam,
    b.external_id
FROM public.verblijfsobject v
JOIN geocoder.building b ON b.external_id = v.pand_identificatie
ON CONFLICT (external_id)
DO UPDATE
    SET building_number = excluded.building_number,
    postal_code = excluded.postal_code,
    street = excluded.street,
    city = excluded.city;
    
INSERT INTO geocoder.address(building_number, postal_code, street, external_id, city, building_id)
SELECT
    concat(l.huisnummer, l.huisletter, l.toevoeging),
    l.postcode,
    l.openbare_ruimte_naam,
    concat('NL.IMBAG.NUMMERAANDUIDING.', l.nummeraanduiding_hoofdadres_identificatie),
    l.woonplaats_naam,
    b.external_id
FROM public.ligplaats l
JOIN geocoder.building b ON b.external_id = l.identificatie
ON CONFLICT (external_id)
DO UPDATE
    SET building_number = excluded.building_number,
    postal_code = excluded.postal_code,
    street = excluded.street,
    city = excluded.city;

INSERT INTO geocoder.address(building_number, postal_code, street, external_id, city, building_id)
SELECT
    concat(s.huisnummer, s.huisletter, s.toevoeging),
    s.postcode,
    s.openbare_ruimte_naam,
    concat('NL.IMBAG.NUMMERAANDUIDING.', s.nummeraanduiding_hoofdadres_identificatie),
    s.woonplaats_naam,
    b.external_id
FROM public.standplaats s
JOIN geocoder.building b ON b.external_id = s.identificatie
ON CONFLICT (external_id)
DO UPDATE
    SET building_number = excluded.building_number,
    postal_code = excluded.postal_code,
    street = excluded.street,
    city = excluded.city;
