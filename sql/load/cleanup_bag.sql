-- Final BAG load step: drop the ogr2ogr staging tables.
--
-- Run after load_building/load_address/load_residence have committed. The
-- staging tables are ~28 GB (pand 10 GB, verblijfsobject 18 GB) and have no
-- consumers once the geocoder tables are loaded — ogr2ogr recreates them with
-- -overwrite on the next load_dataset run, so leaving them around only burns
-- managed-PG disk between (infrequent, manual) BAG imports.

DROP TABLE IF EXISTS
    public.pand,
    public.ligplaats,
    public.standplaats,
    public.verblijfsobject;
