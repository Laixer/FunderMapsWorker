-- Drop application.mapset.style (Yorick 2026-10-26: "Remove all traces of mapbox").
--
-- On prod (2026-10-26) the column holds a mapbox://styles/laixer/... URL on all
-- 11 mapsets. Nothing draws with it: every map uses the tileserver's basemap,
-- and the Mapbox token was revoked on 2026-10-26. The API stopped selecting it
-- (FunderMapsApi #299, live b7cff63); the map app and the admin portal dropped
-- it from their interfaces (WebFront #337, ManagementFront #95).
--
-- Its only dependent is the view application.mapset_collection (owner
-- fundermaps; SELECT for fundermaps_webapp and fundie_agent; no comments). The
-- view is recreated here with the same definition minus `style`, the same owner
-- and the same grants. Refuses if a mapset holds a style that is not a Mapbox
-- URL (that would be something nobody here knows about).

SET LOCAL lock_timeout = '2s';

DO $$
BEGIN
    IF EXISTS (SELECT FROM application.mapset WHERE style IS NOT NULL AND style NOT LIKE 'mapbox://%') THEN
        RAISE EXCEPTION 'application.mapset.style holds a value that is not a mapbox:// URL; stopping';
    END IF;
END
$$;

DROP VIEW application.mapset_collection;

ALTER TABLE application.mapset DROP COLUMN style;

CREATE VIEW application.mapset_collection AS
 SELECT id,
    name,
    lower(regexp_replace(name, '\s+'::text, '-'::text, 'g'::text)) AS slug,
    metadata,
    public,
    consent,
    note,
    icon,
    "order",
    ( SELECT jsonb_agg(maplayers.layer) AS jsonb_agg
           FROM ( SELECT l.*::application.mapset_layer AS layer
                   FROM application.mapset_layer l
                  WHERE (l.id IN ( SELECT unnest(m2.layers) AS unnest
                           FROM application.mapset m2
                          WHERE (m2.id = m.id)))
                  ORDER BY l."order") maplayers) AS layerset
   FROM application.mapset m;

ALTER VIEW application.mapset_collection OWNER TO fundermaps;

-- The grants the view had (a DROP + CREATE loses them). Skipped with a NOTICE
-- where a role does not exist (a fresh test database).
DO $$
DECLARE r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['fundermaps_webapp', 'fundie_agent'] LOOP
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('GRANT SELECT ON application.mapset_collection TO %I', r);
        ELSE
            RAISE NOTICE 'role % does not exist; no grant', r;
        END IF;
    END LOOP;
END
$$;
