-- Identify a model by what is deployed, not by what is committed.
--
-- create_model_version_registry.sql stamped the current model with
-- `sql_git_sha` = the last commit touching sql/model/. That is a weak identity
-- for three reasons:
--
--   1. That commit (3d76339) is `fix(tiles): height must be double precision`.
--      A tile fix. Read literally it says the model changed on 2026-08-06; the
--      last change to risk logic was #1005 and #1002, on 2026-07-21.
--   2. sql/model/ also holds tile builders, statistics and boundary layers, any
--      of which bump the SHA without touching a risk calculation.
--   3. It records the repository, not the database. It asserts that prod
--      matches git -- which is precisely the assumption that failed in the
--      2026-07-21 view clobber.
--
-- So add a hash computed from the deployed definitions themselves: the view
-- that calculates the model, the three sample matviews it selects through, and
-- every helper function it calls. Seventeen objects. This cannot drift from
-- reality, because it is derived from reality.
--
-- `sql_git_sha` stays, demoted to what it honestly is: a pointer to the intent
-- in version control. `definition_sha256` is the identity.
--
-- CAVEAT, read before treating a change as an alarm: pg_get_viewdef and
-- pg_get_functiondef pretty-print, and a PostgreSQL major upgrade can change
-- that formatting without any semantic change. We went 17 -> 18 on 2026-08-07.
-- A hash mismatch therefore means INVESTIGATE, not "the model changed" -- and
-- the baseline should be re-taken deliberately after each major upgrade.
--
--   psql "$DB_URL" -f sql/migrate/add_model_definition_hash.sql

BEGIN;

-- The set of objects hashed IS the definition of "the model". Changing this
-- function changes every hash, so change it deliberately and re-baseline.
CREATE OR REPLACE FUNCTION data.model_definition_sha256()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    WITH defs AS (
        SELECT 'view:' || c.relname AS obj, pg_get_viewdef(c.oid, true) AS src
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'data'
          AND c.relname IN ('model_risk_dynamic_all', 'model_risk_static',
                            'building_sample', 'cluster_sample', 'supercluster_sample')
        UNION ALL
        SELECT 'func:' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
               pg_get_functiondef(p.oid)
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'data'
          AND (p.proname LIKE 'compute_%'
            OR p.proname LIKE 'is_%'
            OR p.proname IN ('indicative_foundation_type', 'enforcement_term_years'))
    )
    SELECT encode(sha256(string_agg(obj || E'\n' || src, E'\n---\n' ORDER BY obj)::bytea), 'hex')
    FROM defs;
$$;

COMMENT ON FUNCTION data.model_definition_sha256() IS
    'Content hash of the deployed model: the calculation view, the three sample matviews and every helper function. Compare against model_version.definition_sha256 to detect drift between what is registered and what is running.';

ALTER TABLE data.model_version
    ADD COLUMN definition_sha256 text;

COMMENT ON COLUMN data.model_version.definition_sha256 IS
    'Hash of the deployed definitions when this version was registered. The identity of the model. sql_git_sha points at intent in version control; this records what actually ran.';

COMMENT ON COLUMN data.model_version.sql_git_sha IS
    'Commit of the sql/model/ tree, as a pointer to intent. NOT the model identity -- see definition_sha256.';

-- Baseline the frozen model against what is deployed right now.
UPDATE data.model_version
SET definition_sha256 = data.model_definition_sha256()
WHERE slug = 'model-2024.1';

-- A registered version must carry its identity once it is anything more than a
-- draft; a draft may legitimately have no deployed definition yet.
ALTER TABLE data.model_version
    ADD CONSTRAINT model_version_identified_when_real
    CHECK (status = 'draft' OR definition_sha256 IS NOT NULL);

GRANT EXECUTE ON FUNCTION data.model_definition_sha256() TO fundermaps_windmill;
GRANT EXECUTE ON FUNCTION data.model_definition_sha256() TO grafana;

COMMIT;
