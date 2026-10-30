-- Rename the "do soon" objects from the DB map (Yorick 2026-10-30: "Do the "do soon" renames next"):
-- English names (names, enum values and keys are English) and names that say what a thing is.
--
--   dataops.dossier_rapportage               -> dataops.dossier_inquiry      (+ its constraints, indexes, sequence)
--   data.model_gevelscan                     -> data.facade_scan_risk_rule
--   data.risk_table_priority                 -> data.facade_scan_priority_rule
--   data.model_foundation_2026_2.p_oplanger  -> p_wood_charger               (+ data.foundation_candidate())
--   report.last_record_update()              -> report.set_update_date()     (5 triggers follow)
--   geocoder.geocoder_generate_id()          -> geocoder.generate_id()       (5 column defaults follow)
--   application.file_resources               -> application.file_resource    (+ its constraints, indexes)
--
-- Views, triggers and column defaults point at an object by OID and follow a rename (maplayer.facade_scan reads
-- both facade-scan rule tables). Function bodies name things by text and do not, so data.foundation_candidate()
-- is recreated from its live definition with only p_oplanger changed. No function body names the renamed tables,
-- and nothing names their constraints or indexes (prod, 2026-10-30, read-only).
--
-- The old API (api-prod, FunderMapsApi) still reads and writes dossier_rapportage and file_resources, and a saved
-- Fundie script reads dossier_rapportage. So both old names stay, as plain views over the new tables: such a view is
-- automatically updatable (SELECT, INSERT ... RETURNING, UPDATE, DELETE), and omitted columns get the table's own
-- defaults and identity. Same owner and grants as the tables. Drop the two views once api-prod is deleted and
-- Studio/api names the new tables.
--
-- Not renamed: the four maplayer.incident* views. maplayer.refresh_incident_tiles() builds its tile tables from
-- dataops.dossier itself, so nothing reads them; 20261030_004 described them wrongly, which is corrected below.

SET LOCAL lock_timeout = '2s';

-- 1. Tables
ALTER TABLE dataops.dossier_rapportage RENAME TO dossier_inquiry;
ALTER TABLE application.file_resources RENAME TO file_resource;
ALTER TABLE data.model_gevelscan RENAME TO facade_scan_risk_rule;
ALTER TABLE data.risk_table_priority RENAME TO facade_scan_priority_rule;

-- Constraints, indexes and sequences that carry the old table name. Renaming a primary key or unique constraint
-- renames its index too; the index loop then only finds the plain indexes.
DO $$
DECLARE t record; r record;
BEGIN
    FOR t IN SELECT * FROM (VALUES ('dataops', 'dossier_inquiry', 'dossier_rapportage'),
                                   ('application', 'file_resource', 'file_resources')) v(sch, tbl, old) LOOP
        FOR r IN SELECT conname FROM pg_constraint
                  WHERE conrelid = format('%I.%I', t.sch, t.tbl)::regclass AND starts_with(conname, t.old) LOOP
            EXECUTE format('ALTER TABLE %I.%I RENAME CONSTRAINT %I TO %I', t.sch, t.tbl, r.conname,
                           t.tbl || substr(r.conname, length(t.old) + 1));
        END LOOP;
        FOR r IN SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
                  WHERE i.indrelid = format('%I.%I', t.sch, t.tbl)::regclass AND starts_with(c.relname, t.old) LOOP
            EXECUTE format('ALTER INDEX %I.%I RENAME TO %I', t.sch, r.relname, t.tbl || substr(r.relname, length(t.old) + 1));
        END LOOP;
        FOR r IN SELECT c.relname FROM pg_class c JOIN pg_depend d ON d.objid = c.oid AND d.deptype IN ('a', 'i')
                  WHERE c.relkind = 'S' AND d.refobjid = format('%I.%I', t.sch, t.tbl)::regclass AND starts_with(c.relname, t.old) LOOP
            EXECUTE format('ALTER SEQUENCE %I.%I RENAME TO %I', t.sch, r.relname, t.tbl || substr(r.relname, length(t.old) + 1));
        END LOOP;
    END LOOP;
END
$$;

-- 2. The old names as views, for api-prod and saved scripts
CREATE VIEW dataops.dossier_rapportage AS SELECT * FROM dataops.dossier_inquiry;
CREATE VIEW application.file_resources AS SELECT * FROM application.file_resource;
ALTER VIEW dataops.dossier_rapportage OWNER TO fundermaps;
ALTER VIEW application.file_resources OWNER TO fundermaps;

-- The grants the tables have, skipped with a NOTICE where a role does not exist (a fresh test database).
DO $$
DECLARE g record;
BEGIN
    FOR g IN SELECT * FROM (VALUES ('dataops.dossier_rapportage', 'fundermaps_webapp', 'INSERT, SELECT'),
                                   ('dataops.dossier_rapportage', 'fundermaps_windmill', 'SELECT'),
                                   ('dataops.dossier_rapportage', 'fundie_agent', 'SELECT'),
                                   ('application.file_resources', 'fundermaps_webapp', 'INSERT, SELECT, UPDATE'),
                                   ('application.file_resources', 'fundie_agent', 'SELECT')) v(obj, role, privs) LOOP
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = g.role) THEN
            EXECUTE format('GRANT %s ON %s TO %I', g.privs, g.obj, g.role);
        ELSE
            RAISE NOTICE 'role % does not exist; no grant on %', g.role, g.obj;
        END IF;
    END LOOP;
END
$$;

-- 3. The model column, and the one function that names it
ALTER TABLE data.model_foundation_2026_2 RENAME COLUMN p_oplanger TO p_wood_charger;

CREATE OR REPLACE FUNCTION data.foundation_candidate(z integer, x integer, y integer)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE PARALLEL SAFE
AS $function$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    IF z < 12 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    IF z >= 14 THEN
        SELECT ST_AsMVT(tile, 'foundation_candidate', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                t.building_id,
                c.family,
                c.foundation_type,
                c.grade,
                c.source,
                c.p_wood_charger::double precision AS p_wood_charger,
                c.p_wood::double precision     AS p_wood,
                c.p_no_pile::double precision  AS p_no_pile,
                c.p_concrete::double precision AS p_concrete,
                c.confidence::double precision AS confidence,
                c.evidence,
                t.foundation_type              AS current_type,
                t.height,
                ST_AsMVTGeom(t.geom, env, 4096, 64, true) AS geom
            FROM maplayer.building_tiles t
            JOIN data.model_foundation_2026_2 c ON c.building_id = t.building_id
            WHERE t.geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        SELECT ST_AsMVT(tile, 'foundation_candidate', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                c.family,
                c.foundation_type,
                c.grade,
                c.confidence::double precision AS confidence,
                c.evidence,
                t.height,
                ST_AsMVTGeom(t.geom_simple, env, 4096, 8, true) AS geom
            FROM maplayer.building_tiles t
            JOIN data.model_foundation_2026_2 c ON c.building_id = t.building_id
            WHERE t.geom_simple && env
              AND t.surface_area >= CASE WHEN z = 12 THEN 150 ELSE 60 END
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$function$;

-- 4. Functions (triggers and defaults follow by OID)
ALTER FUNCTION report.last_record_update() RENAME TO set_update_date;
ALTER FUNCTION geocoder.geocoder_generate_id() RENAME TO generate_id;

-- 5. Comments: the renamed objects keep theirs; these texts named the old names, or (the incident views) were wrong.
COMMENT ON TABLE data.model_foundation_2026_2 IS $c$[model candidate] Candidate model-2026.2 (Worker #152, rc2 2026-09-27): blend of two LightGBM foundation-family models (c where the buurt has report labels, else mean of a and c) plus model d for the wood-pile / wood-pile-with-concrete-top split, trained offline on report labels (quickscan and facade_scan excluded). p_* = blend probabilities, p_wood_charger = P(concrete top | wood). family/foundation_type = own evidence when source is report or quickscan (grade vastgesteld), else the model. evidence: buurt = a label in the same buurt x era; nabij = only a label within 250 m; municipal = municipality has >= 30 labels; none = neither. grade from the out-of-sample lookup (zeer betrouwbaar ~96%, betrouwbaar ~83% correct). Served to nobody except the FunderMaps B.V. candidate mapset. Frozen model-2024.1 is untouched.$c$;
COMMENT ON TABLE dataops.dossier_inquiry IS $c$[intake] The verdict per inquiry of a dossier (Don, 2026-10-09). One row per group of documents the reviewer formed at commit; the closing mail combines the answers into one message to the reporter.$c$;
COMMENT ON VIEW dataops.dossier_rapportage IS $c$[legacy] Old name of dataops.dossier_inquiry, kept so the old API (api-prod) and saved scripts keep working; reads and writes go to the table. Drop when api-prod is gone and Studio/api names the table.$c$;
COMMENT ON VIEW application.file_resources IS $c$[legacy] Old name of application.file_resource, kept so the old API (api-prod) keeps working; reads and writes go to the table. Drop when api-prod is gone and Studio/api names the table.$c$;
COMMENT ON VIEW maplayer.incident IS $c$[unused] Incident reports (dossiers with a topic) per building. Nothing reads this view: maplayer.refresh_incident_tiles() builds incident_tiles from dataops.dossier itself. Candidate to drop.$c$;
COMMENT ON VIEW maplayer.incident_district IS $c$[unused] Incident count per district. Nothing reads this view: maplayer.refresh_incident_tiles() builds incident_district_tiles from dataops.dossier itself. Candidate to drop.$c$;
COMMENT ON VIEW maplayer.incident_municipality IS $c$[unused] Incident count per municipality. Nothing reads this view: maplayer.refresh_incident_tiles() builds incident_municipality_tiles from dataops.dossier itself. Candidate to drop.$c$;
COMMENT ON VIEW maplayer.incident_neighborhood IS $c$[unused] Incident count per neighbourhood. Nothing reads this view: maplayer.refresh_incident_tiles() builds incident_neighborhood_tiles from dataops.dossier itself. Candidate to drop.$c$;
