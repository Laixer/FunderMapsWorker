-- model-2026.2 candidate: a probabilistic foundation-type model beside the frozen one.
--
-- Why (Worker #152; Don 2026-09-23/24, Yorick approved preparing it 2026-09-24):
-- the frozen model-2024.1 takes the foundation type from the leading report,
-- then cluster/supercluster, and for 84% of panden (9.5M) from the 2022
-- threshold tree. The read-only study of 2026-09-24 (~/ft-research on agent0,
-- explainer chapter 4) found a LightGBM model ("M6c") on pand attributes,
-- vendor soil/groundwater, neighbourhood context and nearby report labels
-- clearly better when tested per report and per municipality:
--   random 20% by report      86% vs 57% (tree) family accuracy
--   held-out municipalities    77% vs 39%
--   Utrecht                    84% vs 51% (false wood 37.5% -> 0.1%)
-- and no method works in a municipality without local reports (Sneek).
--
-- What this creates, nothing else touched:
--   data.model_foundation_2026_2      one row per pand: p(wood/no_pile/concrete),
--                                      argmax family, confidence, evidence tier.
--                                      Filled OFFLINE by model/2026-2/train_predict.py
--                                      (\copy of its CSV) — never computed in SQL.
--   maplayer.foundation_candidate()   Martin function source for a mapset that is
--                                      linked ONLY to the FunderMaps B.V. organisation
--                                      (Don: "zichtbaar voor de admin in maps").
-- Not served to customers, not read by model-2024.1, the Webservice or the API.
-- Drop with: DROP FUNCTION maplayer.foundation_candidate(integer,integer,integer);
--            DROP TABLE data.model_foundation_2026_2;

CREATE TABLE data.model_foundation_2026_2 (
    building_id   text PRIMARY KEY,
    p_wood        real NOT NULL,
    p_no_pile     real NOT NULL,
    p_concrete    real NOT NULL,
    family        text NOT NULL CHECK (family IN ('wood', 'no_pile', 'concrete')),
    confidence    real NOT NULL,
    evidence      text NOT NULL CHECK (evidence IN ('local', 'municipal', 'none')),
    model_version text NOT NULL DEFAULT 'model-2026.2-rc1',
    computed_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE data.model_foundation_2026_2 IS
'Candidate model-2026.2 (Worker #152): LightGBM foundation-family probabilities per pand, trained offline on report labels (quickscans excluded). evidence: local = a report label in the same buurt x era or within 250 m; municipal = municipality has >= 30 labels; none = neither. Served to nobody except the FunderMaps B.V. candidate mapset. Frozen model-2024.1 is untouched.';

-- Martin function source: GET /foundation_candidate/{z}/{x}/{y}.
-- Geometry comes from maplayer.building_tiles (refreshed nightly), so the
-- candidate needs no geometry of its own. Same zoom rules as building_tiles.
CREATE OR REPLACE FUNCTION maplayer.foundation_candidate(z integer, x integer, y integer)
RETURNS bytea
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
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
$$;

-- TileJSON metadata for Martin ("fields" is mandatory, see create_building_tiles.sql).
COMMENT ON FUNCTION maplayer.foundation_candidate(integer, integer, integer) IS
'{"description": "Candidate model-2026.2 foundation family (FunderMaps B.V. only, not served to customers)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "foundation_candidate", "minzoom": 12, "maxzoom": 16, "fields": {"building_id": "String", "family": "String", "p_wood": "Number", "p_no_pile": "Number", "p_concrete": "Number", "confidence": "Number", "evidence": "String", "current_type": "String", "height": "Number"}}]}';

ALTER TABLE data.model_foundation_2026_2 OWNER TO fundermaps;
ALTER FUNCTION maplayer.foundation_candidate(integer, integer, integer) OWNER TO fundermaps;

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_tileserver') THEN
        GRANT SELECT ON data.model_foundation_2026_2 TO fundermaps_tileserver;
        GRANT EXECUTE ON FUNCTION maplayer.foundation_candidate(integer, integer, integer)
            TO fundermaps_tileserver;
    END IF;
END $$;
