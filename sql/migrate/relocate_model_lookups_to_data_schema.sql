-- Relocate model lookup tables from public to data schema.
--
-- public.model_gevelscan (125 rows) and public.risk_table_priority (25 rows)
-- are static lookup tables driving maplayer.facade_scan. They were left
-- in `public` historically; everything else FunderMaps-specific lives
-- under application/data/geocoder/maplayer/report, so these two were
-- the only reason schema.sql had hand-spliced public-schema objects
-- (commit 279210b added the splice in the dump).
--
-- ALTER TABLE ... SET SCHEMA preserves the table OID, so the view
-- maplayer.facade_scan that references public.model_gevelscan /
-- public.risk_table_priority keeps working with the OID — pg_get_viewdef
-- will subsequently show the data.* qualification automatically.
-- No view rewrite needed.

BEGIN;

ALTER TABLE public.model_gevelscan SET SCHEMA data;
ALTER TABLE public.risk_table_priority SET SCHEMA data;

COMMIT;
