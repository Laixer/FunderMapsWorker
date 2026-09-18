-- gfm retirement, step 4a (Worker #158): geocoder.address loses its gfm- `id`.
-- Apply only after the API build that no longer selects address.id is live
-- (Laixer/FunderMapsApi#190); the Worker stopped reading it in the PR that
-- carried 20260918_006.
--
-- Prod 2026-09-18, after 20260918_005 + _006: nothing references address.id —
-- no foreign key, no view, no function. pg_depend lists only the primary key,
-- the NOT NULL and the default on the column itself. `external_id` (the BAG
-- nummeraanduiding) is NOT NULL and unique (address_external_id_idx), and three
-- foreign keys already point at it (residence, extraction_field,
-- dossier_address), so it becomes the primary key by promoting that index: no
-- rebuild, no rescan of the referencing tables, the index keeps its oid and the
-- foreign keys stay attached.
--
-- DROP COLUMN is a catalog change; the ~10 M rows are not rewritten. The space
-- comes back on the next BAG reload, which rewrites the table anyway.
--
-- geocoder_generate_id() and the geocoder_id domain stay: building, residence
-- and the CBS hierarchy still use them (steps 3 and 4b).

-- Refuse to run while anything still stores a gfm- address key.
DO $$
DECLARE n bigint;
BEGIN
  SELECT (SELECT count(*) FROM report.inquiry_sample WHERE address LIKE 'gfm-%')
       + (SELECT count(*) FROM dataops.extraction_field WHERE address_id LIKE 'gfm-%')
       + (SELECT count(*) FROM dataops.dossier_address WHERE address_id LIKE 'gfm-%')
    INTO n;
  IF n > 0 THEN
    RAISE EXCEPTION 'address.id drop: % row(s) still store a gfm- address key; they would become unresolvable', n;
  END IF;
END $$;

ALTER TABLE geocoder.address DROP CONSTRAINT address_pkey;
ALTER TABLE geocoder.address ADD CONSTRAINT address_pkey PRIMARY KEY USING INDEX address_external_id_idx;
ALTER TABLE geocoder.address DROP COLUMN id;
