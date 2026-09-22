-- building_number is how BAG writes an address: the huisletter attaches to the
-- number (26 + A = 26A), the huisnummertoevoeging follows a hyphen (131 + 3 =
-- 131-3). Gluing both on as bare suffixes stored 131-3 as 1313 (#195).
-- '-' || NULL is NULL and concat() skips NULLs, so no toevoeging, no hyphen.

INSERT INTO geocoder.address(building_number, postal_code, street, external_id, city, building_id)
SELECT
    concat(v.huisnummer, v.huisletter, '-' || nullif(v.toevoeging, '')),
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
    city = excluded.city,
    building_id = excluded.building_id;

INSERT INTO geocoder.address(building_number, postal_code, street, external_id, city, building_id)
SELECT
    concat(l.huisnummer, l.huisletter, '-' || nullif(l.toevoeging, '')),
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
    city = excluded.city,
    building_id = excluded.building_id;

INSERT INTO geocoder.address(building_number, postal_code, street, external_id, city, building_id)
SELECT
    concat(s.huisnummer, s.huisletter, '-' || nullif(s.toevoeging, '')),
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
    city = excluded.city,
    building_id = excluded.building_id;
