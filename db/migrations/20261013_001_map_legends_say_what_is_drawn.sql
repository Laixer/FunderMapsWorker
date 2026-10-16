-- The map's legends say what is drawn.
--
-- Decision 28 and 29 of the logged-in sweep (Yorick, 2026-10-13). A legend is a
-- row here (`application.mapset_layer.fields`); the drawing rule is a file in
-- FunderMapsWebFront (`src/config/layers/<id>.json`). Checked against each other
-- for every value the tiles hold, 23 values were drawn in a colour no legend
-- row had. The rules that were wrong are fixed there (WebFront #324: a herstel
-- type drawn red through a misspelt key, three soorten rapportage sharing one
-- rule, risk class C filtered out). This file corrects the legends that were
-- wrong on this side. With both, the same check finds none.
--
-- Only `fields` and one name change: no layer is added to a mapset, no order
-- changes. Colours are written as the map draws them.
--
-- A database built from schema.sql has no legend rows: every statement then
-- changes nothing.

-- HotSpot: D and E in the words the pand panel and the report use ("Hoog", "Aanzienlijk hoog");
-- it said "Verhoogd" for D, which is the word for C.
UPDATE application.mapset_layer SET fields = '[
        {"name": "Hoog risico (D)", "color": "FFAC33"},
        {"name": "Aanzienlijk hoog risico (E)", "color": "FF5533"}
    ]'::jsonb
    WHERE id = 'hotspot';

-- Hersteld: "Paalkopverlaging" is one word.
UPDATE application.mapset_layer SET fields = '[
        {"name": "Volledig herstel", "color": "5cbe55"},
        {"name": "Partieel herstel", "color": "47baa5"},
        {"name": "Paalkopverlaging", "color": "8c4bb6"},
        {"name": "Grondverbetering", "color": "c67e70"},
        {"name": "Onbekend", "color": "5B4AB7"}
    ]'::jsonb
    WHERE id = 'foundation-recovery';

-- Funderingstype (three layers): concrete, steel and weighted piles are drawn in 7F8FA4, the row
-- said 6A6C70 and named concrete only; gecombineerd and overig are drawn and had no row. The
-- indicative class holds neither of those two, so its legend does not list them.
UPDATE application.mapset_layer SET fields = '[
        {"name": "Houten paal", "color": "8C3A28"},
        {"name": "Houten paal met oplanger", "color": "B59E3C"},
        {"name": "Betonnen of stalen paal", "color": "7F8FA4"},
        {"name": "Ondiepe fundering", "color": "CE0015"},
        {"name": "Gecombineerd", "color": "B271DE"},
        {"name": "Overig", "color": "FFEC33"}
    ]'::jsonb
    WHERE id = 'foundation-type-established';
UPDATE application.mapset_layer SET fields = '[
        {"name": "Houten paal", "color": "8C3A28"},
        {"name": "Houten paal met oplanger", "color": "B59E3C"},
        {"name": "Betonnen of stalen paal", "color": "7F8FA4"},
        {"name": "Ondiepe fundering", "color": "CE0015"},
        {"name": "Gecombineerd", "color": "B271DE"},
        {"name": "Overig", "color": "FFEC33"}
    ]'::jsonb
    WHERE id = 'foundation-type-cluster';
UPDATE application.mapset_layer SET fields = '[
        {"name": "Houten paal", "color": "8C3A28"},
        {"name": "Houten paal met oplanger", "color": "B59E3C"},
        {"name": "Betonnen of stalen paal", "color": "7F8FA4"},
        {"name": "Ondiepe fundering", "color": "CE0015"}
    ]'::jsonb
    WHERE id = 'foundation-type-indicative';

-- Bouwjaar: 2010 t/m 2020 carried the colour of the class before it (the map draws BA2351 at 2020).
UPDATE application.mapset_layer SET fields = '[
        {"name": "< 1960", "color": "293575"},
        {"name": "1960 t/m 1970", "color": "1261A3"},
        {"name": "1970 t/m 1980", "color": "69A8DE"},
        {"name": "1980 t/m 1990", "color": "99C1E9"},
        {"name": "1990 t/m 2000", "color": "B378B1"},
        {"name": "2000 t/m 2010", "color": "bd6495"},
        {"name": "2010 t/m 2020", "color": "BA2351"},
        {"name": "> 2020", "color": "d11313"}
    ]'::jsonb
    WHERE id = 'construction-year';

-- Handhavingstermijn: -10 t/m -15 carried the colour of the class before it (the map draws BB7F1E at -15).
UPDATE application.mapset_layer SET fields = '[
        {"name": "> 25", "color": "64DEBC"},
        {"name": "20 t/m 25", "color": "55E293"},
        {"name": "15 t/m 20", "color": "46E65F"},
        {"name": "10 t/m 15", "color": "4CEB36"},
        {"name": "5 t/m 10", "color": "77F025"},
        {"name": "0 t/m 5", "color": "AEF614"},
        {"name": "0 t/m -5", "color": "D0E218"},
        {"name": "-5 t/m -10", "color": "CEB31B"},
        {"name": "-10 t/m -15", "color": "BB7F1E"},
        {"name": "-15 t/m -20", "color": "A85520"},
        {"name": "-20 t/m -25", "color": "973321"},
        {"name": "< -25", "color": "86222A"}
    ]'::jsonb
    WHERE id = 'enforcement-term';

-- Rapportage: the names the pand panel uses (it said "Snelle scan", "Sloop onderzoek", "FunderScan"),
-- the colours that are drawn (Grondonderzoek and Gevelscan had another), and a row for every
-- soort that is drawn (Onderzoeksput had none).
UPDATE application.mapset_layer SET fields = '[
        {"name": "Monitoring", "color": "B54CB0"},
        {"name": "Notitie", "color": "8C4BB6"},
        {"name": "QuickScan", "color": "5B4AB7"},
        {"name": "Sloopgrensonderzoek", "color": "4767B8"},
        {"name": "Second opinion", "color": "489BB9"},
        {"name": "Archiefonderzoek", "color": "47BAA5"},
        {"name": "Bouwkundig onderzoek", "color": "4EBC77"},
        {"name": "Funderingsadvies", "color": "5CBE55"},
        {"name": "Onderzoeksput", "color": "90C05D"},
        {"name": "Funderingsonderzoek", "color": "BDC262"},
        {"name": "Aanvullend onderzoek", "color": "C4A169"},
        {"name": "Grondwateronderzoek", "color": "C67F71"},
        {"name": "Grondonderzoek", "color": "F4A9E2"},
        {"name": "Gevelscan", "color": "EC0909"},
        {"name": "Onbekend", "color": "6A6C70"}
    ]'::jsonb
    WHERE id = 'inquiry-type';

-- Incident per wijk / buurt / gemeente: classes that follow each other; it said
-- "tot en met 9 meldingen" and then ">10 meldingen".
UPDATE application.mapset_layer SET fields = '[
        {"name": "1 melding", "color": "c1d4e6"},
        {"name": "2 of 3 meldingen", "color": "91bad6"},
        {"name": "4 of 5 meldingen", "color": "528aad"},
        {"name": "6 t/m 9 meldingen", "color": "38658a"},
        {"name": "10 of meer meldingen", "color": "1e3f67"}
    ]'::jsonb
    WHERE id = 'incident-district';
UPDATE application.mapset_layer SET fields = '[
        {"name": "1 melding", "color": "c1d4e6"},
        {"name": "2 of 3 meldingen", "color": "91bad6"},
        {"name": "4 of 5 meldingen", "color": "528aad"},
        {"name": "6 t/m 9 meldingen", "color": "38658a"},
        {"name": "10 of meer meldingen", "color": "1e3f67"}
    ]'::jsonb
    WHERE id = 'incident-neighborhood';
UPDATE application.mapset_layer SET fields = '[
        {"name": "1 melding", "color": "c1d4e6"},
        {"name": "2 of 3 meldingen", "color": "91bad6"},
        {"name": "4 of 5 meldingen", "color": "528aad"},
        {"name": "6 t/m 9 meldingen", "color": "38658a"},
        {"name": "10 of meer meldingen", "color": "1e3f67"}
    ]'::jsonb
    WHERE id = 'incident-municipality';

-- Bouwkundige eenheid: the outline is drawn in this blue.
UPDATE application.mapset_layer SET fields = '[
        {"name": "Indicatief", "color": "0039D6"}
    ]'::jsonb
    WHERE id = 'building-cluster';

-- The layer title on the Risico mapset: "Bacteriele" without its trema.
UPDATE application.mapset_layer SET name = 'Bacteriële aantasting'
    WHERE id = 'bio-infection-risk' AND name = 'Bacteriele aantasting';

-- The layer "Eigenaar" goes (decision 29). Its legend named a handful of
-- organisations to every user of the mapset it was on, with spellings that did
-- not match the drawing rule, and it drew nothing in most of the country. On
-- 2026-10-13 one mapset listed it. The `owner` value stays in the tiles: the
-- switch "Filter op eigendom" in the map app uses it.
UPDATE application.mapset SET layers = array_remove(layers, 'owner')
    WHERE 'owner' = ANY (layers);
DELETE FROM application.mapset_layer WHERE id = 'owner';
