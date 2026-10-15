-- Small text corrections in what the map app shows from this database.
--
-- Found by the cosmetic sweep of 2026-10-13/14 (map app, left side bar). The
-- legends and the notes behind the "i" of a mapset are rows here; nothing in
-- the map app's repository holds these texts. Text only: no layer is added,
-- removed or reordered, no colour changes.
--
-- Every statement names the text it replaces, so a row that was edited in the
-- meantime is left alone. A database built from schema.sql has none of these
-- rows: every statement then changes nothing.

-- A Dutch compound is one word.
UPDATE application.mapset_layer SET name = 'Rapportagetype'
    WHERE id = 'inquiry-type' AND name = 'Rapportage type';

-- An amount is written with a space after the euro sign, as the pand panel does ("€ 76.400,00").
UPDATE application.mapset_layer
    SET fields = replace(fields::text, '€', '€ ')::jsonb
    WHERE id = 'restoration-cost' AND fields::text LIKE '%€2%' AND fields::text NOT LIKE '%€ %';

-- "... zijn modelberekeningen gemaakt en worden op pandniveau ontsloten": the second half had lost its subject.
UPDATE application.mapset
    SET note = replace(note, 'zijn modelberekeningen gemaakt en worden op pandniveau ontsloten.',
                             'zijn modelberekeningen gemaakt. Deze worden op pandniveau ontsloten.')
    WHERE note LIKE '%zijn modelberekeningen gemaakt en worden op pandniveau ontsloten.%';

-- The mapset has a layer per buurt as well as per wijk and per gemeente.
UPDATE application.mapset
    SET note = replace(note, 'op wijk- en gemeenteniveau', 'op buurt-, wijk- en gemeenteniveau')
    WHERE note LIKE '%aantal op wijk- en gemeenteniveau%';

-- "Gevelscan" is written with one capital everywhere else.
UPDATE application.mapset
    SET note = replace(note, 'GevelScan-richtlijn', 'Gevelscan-richtlijn')
    WHERE note LIKE '%GevelScan-richtlijn%';

-- "plaatsvinden" is one word, and the two lines under "Monitoring" and "Incident" are questions.
UPDATE application.mapset
    SET note = replace(note, 'of gaat het plaats vinden.', 'of gaat het plaatsvinden?')
    WHERE note LIKE '%of gaat het plaats vinden.%';
UPDATE application.mapset
    SET note = replace(note, 'wordt de fundering op dit moment gemonitord.', 'wordt de fundering op dit moment gemonitord?')
    WHERE note LIKE '%wordt de fundering op dit moment gemonitord.%';

-- "Hotspot" with one capital, and its legend names the class first, as the pand panel does ("D (Hoog risico)").
UPDATE application.mapset_layer SET name = 'Hotspot'
    WHERE id = 'hotspot' AND name = 'HotSpot';
UPDATE application.mapset_layer
    SET fields = replace(replace(fields::text,
            '"Hoog risico (D)"', '"D (Hoog risico)"'),
            '"Aanzienlijk hoog risico (E)"', '"E (Aanzienlijk hoog risico)"')::jsonb
    WHERE id = 'hotspot' AND fields::text LIKE '%"Hoog risico (D)"%';

-- Notes that end in empty lines (they show as a gap under the text).
UPDATE application.mapset
    SET note = regexp_replace(note, '\s+$', '')
    WHERE note ~ '\s+$';
