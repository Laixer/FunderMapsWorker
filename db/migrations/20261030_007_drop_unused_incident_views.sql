-- Drop the four unused maplayer incident views and their disabled export rows
-- (Yorick 2026-10-30: "drop the incident views").
--
-- maplayer.incident, incident_district, incident_municipality and incident_neighborhood were the sources of the old
-- tippecanoe tilesets. Since the Martin switch, maplayer.refresh_incident_tiles() builds incident_tiles and the three
-- *_tiles aggregates from dataops.dossier itself, and the tile functions of the same names (maplayer.incident(z,x,y)
-- and its three siblings, the public tile URLs) read those tables. The functions stay.
--
-- Nothing reads the views (prod, 2026-10-30, read-only): no view, function or procedure depends on or names them
-- (one function's code comment names the function maplayer.incident_neighborhood()), no repository or live Windmill
-- script does, and their maplayer.bundle rows are disabled, so the archive export skips them. Those rows go too:
-- they would point at views that no longer exist. No CASCADE: if something depends on the views by now, this file
-- fails and rolls back.

SET LOCAL lock_timeout = '2s';

DO $$
BEGIN
    IF EXISTS (SELECT FROM maplayer.bundle
                WHERE tileset IN ('incident', 'incident_district', 'incident_municipality', 'incident_neighborhood') AND enabled) THEN
        RAISE EXCEPTION 'an incident bundle row is enabled, so the archive export reads that view; stopping';
    END IF;
END
$$;

DELETE FROM maplayer.bundle WHERE tileset IN ('incident', 'incident_district', 'incident_municipality', 'incident_neighborhood');

DROP VIEW maplayer.incident;
DROP VIEW maplayer.incident_district;
DROP VIEW maplayer.incident_municipality;
DROP VIEW maplayer.incident_neighborhood;
