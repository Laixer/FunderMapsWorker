-- Grants for the model-2026.2 candidate objects.
--
-- 20260920_001 created the two tables and the two functions as doadmin (the
-- runner's role on prod), so nothing else could read them: the ETL role
-- `fundermaps`, which owns every other table in `data`, got permission denied
-- on the first sanity query after the apply.
--
-- This matches the neighbouring model tables: `fundermaps` owns and writes,
-- `fundermaps_windmill` reads (it runs the model refresh flows). The candidate
-- is never served, so the webapp and webservice roles are deliberately NOT
-- granted anything — a candidate that the product can read is a candidate
-- waiting to be shipped by accident.
--
-- db/migrations/README.md: grants belong in the migration that creates or
-- widens the object; this is the follow-up because the first file predates
-- that rule being applied to it.

ALTER TABLE data.foundation_type_prior_2026_2 OWNER TO fundermaps;
ALTER TABLE data.foundation_type_2026_2 OWNER TO fundermaps;
ALTER FUNCTION data.ft_cell_2026_2(integer, double precision, text, numeric, integer) OWNER TO fundermaps;
ALTER FUNCTION data.ft_cell_coarse_2026_2(text) OWNER TO fundermaps;

GRANT SELECT ON data.foundation_type_prior_2026_2 TO fundermaps_windmill;
GRANT SELECT ON data.foundation_type_2026_2 TO fundermaps_windmill;
