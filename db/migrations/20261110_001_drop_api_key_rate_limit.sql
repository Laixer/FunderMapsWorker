-- Drop application.api_key_rate_limit, the rate limits per API key (Laixer/FunderMapsStudio#40, Laixer/FunderMapsWebservice#16).
--
-- Replaced by application.organization_rate_limit (20261106_002). Since 2026-11-07 the Webservice reads only the new
-- table (Webservice #66) and Beheer writes only the new one (Studio #67).
--
-- True on prod 2026-11-10: no view, function or foreign key depends on it; no code on main in the Studio, the Webservice
-- or the Worker names it, nor any of the 24 Windmill scripts as deployed, nor Fundie's scripts and notes on its host
-- (Fundie read it twice, by hand, for a question). Its 30 rows are the same as organization_rate_limit's: the hand-over
-- script checks that again before applying, and refuses otherwise.
--
-- No CASCADE: if anything still depends on it, this fails and changes nothing.

SET LOCAL lock_timeout = '2s';
DROP TABLE application.api_key_rate_limit;
