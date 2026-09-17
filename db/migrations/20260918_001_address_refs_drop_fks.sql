-- gfm retirement, step 2 (Worker #158), part A of two.
--
-- The three columns that still hold the internal gfm- address key are moved
-- to the BAG nummeraanduiding (geocoder.address.external_id):
--   report.inquiry_sample.address, dataops.extraction_field.address_id,
--   dataops.dossier_address.address_id.
--
-- Part A only drops the two foreign keys that pin them to address(id). With
-- the keys gone, the API and Worker build that writes nummeraanduidingen and
-- the build that still writes gfm- ids can both run against the database, so
-- the code deploys carry no failure window. Part B (20260918_002) rewrites
-- every value and adds the keys back on address(external_id); it is applied
-- only after both deploys are live.
--
-- Nothing is rewritten here. Idempotent.
ALTER TABLE dataops.extraction_field DROP CONSTRAINT IF EXISTS extraction_field_address_id_fkey;
ALTER TABLE dataops.dossier_address DROP CONSTRAINT IF EXISTS dossier_address_address_id_fkey;
