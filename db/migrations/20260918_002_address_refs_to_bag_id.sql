-- gfm retirement, step 2 (Worker #158), part B of two. Apply only after the
-- API and Worker builds that write nummeraanduidingen are live; part A
-- (20260918_001) dropped the foreign keys so both builds could coexist.
--
-- Every stored gfm- address key becomes the BAG nummeraanduiding
-- (geocoder.address.external_id), the foreign keys come back on that column,
-- and the file refuses to finish if any gfm- value is left. geocoder.address
-- itself keeps its gfm- `id` column and primary key for now: nothing
-- references it after this, and dropping it is step 4 (needs the matview
-- data.statistics_product_data_collected and the API's echo paths changed).
--
-- Prod 2026-09-17: 488,915 sample addresses, 4,940 field addresses, 67 dossier
-- addresses, 0 dangling. Idempotent: every statement is guarded on 'gfm-%'.

-- 1. The three referencing columns.
UPDATE report.inquiry_sample s
   SET address = a.external_id
  FROM geocoder.address a
 WHERE a.id = s.address AND s.address LIKE 'gfm-%';

UPDATE dataops.extraction_field f
   SET address_id = a.external_id
  FROM geocoder.address a
 WHERE a.id = f.address_id AND f.address_id LIKE 'gfm-%';

UPDATE dataops.dossier_address d
   SET address_id = a.external_id
  FROM geocoder.address a
 WHERE a.id = d.address_id AND d.address_id LIKE 'gfm-%';

-- 2. Timeline entries carry address ids in their body (the address panel's
--    undo reads `address_id` back; `address_ids` lists what ingest found).
UPDATE dataops.dossier_entry e
   SET body = jsonb_set(e.body, '{address_id}', to_jsonb(a.external_id))
  FROM geocoder.address a
 WHERE a.id = e.body ->> 'address_id' AND e.body ->> 'address_id' LIKE 'gfm-%';

UPDATE dataops.dossier_entry e
   SET body = jsonb_set(e.body, '{from_address_id}', to_jsonb(a.external_id))
  FROM geocoder.address a
 WHERE a.id = e.body ->> 'from_address_id' AND e.body ->> 'from_address_id' LIKE 'gfm-%';

UPDATE dataops.dossier_entry e
   SET body = jsonb_set(e.body, '{address_ids}', (
         SELECT jsonb_agg(coalesce(a.external_id, x))
           FROM jsonb_array_elements_text(e.body -> 'address_ids') x
           LEFT JOIN geocoder.address a ON a.id = x))
 WHERE jsonb_typeof(e.body -> 'address_ids') = 'array'
   AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(e.body -> 'address_ids') x WHERE x LIKE 'gfm-%');

-- 3. Foreign keys, now on the nummeraanduiding (unique index address_external_id_idx).
ALTER TABLE dataops.extraction_field DROP CONSTRAINT IF EXISTS extraction_field_address_id_fkey;
ALTER TABLE dataops.extraction_field
  ADD CONSTRAINT extraction_field_address_id_fkey
  FOREIGN KEY (address_id) REFERENCES geocoder.address(external_id) ON DELETE SET NULL;

ALTER TABLE dataops.dossier_address DROP CONSTRAINT IF EXISTS dossier_address_address_id_fkey;
ALTER TABLE dataops.dossier_address
  ADD CONSTRAINT dossier_address_address_id_fkey
  FOREIGN KEY (address_id) REFERENCES geocoder.address(external_id);

-- 4. Nothing gfm- may be left in the three columns; a leftover means a row
--    pointed at an address that no longer exists, which needs a look, not a
--    silent commit.
DO $$
DECLARE n bigint;
BEGIN
  SELECT (SELECT count(*) FROM report.inquiry_sample WHERE address LIKE 'gfm-%')
       + (SELECT count(*) FROM dataops.extraction_field WHERE address_id LIKE 'gfm-%')
       + (SELECT count(*) FROM dataops.dossier_address WHERE address_id LIKE 'gfm-%')
    INTO n;
  IF n > 0 THEN
    RAISE EXCEPTION 'address rekey: % gfm- value(s) left that match no geocoder.address row', n;
  END IF;
END $$;
