-- The register of which risk models exist, what they were built from, and where
-- each one is in its life.
--
-- The current model's logic is final and will not change again; everything new
-- (Model 4 with GeoTOP and InSAR, the QuickScan override, the wood
-- under-prediction fix) has to arrive as a *different* model running beside it.
-- That is only possible if we can say which model produced a given answer, and
-- what it was built from.
--
-- Why the provenance columns are not optional: the same SQL over a newer BAG
-- import produces different output, so a version that records only its logic
-- makes every future diff unreadable — did the model change, or the ground
-- under it? `validation/risk_model_reference.csv` carried no stamp, and when it
-- was finally compared against the model, 52% of the reported "drift" turned out
-- to be a merged fix behaving exactly as intended (issue #78). Establishing that
-- took an afternoon. One recorded git SHA would have made it a lookup.
--
-- Additive only: one enum, one table, one row. Nothing reads it yet — see
-- docs/model-versioning.md for the steps that will. Reversible with two DROPs.
--
--   psql "$DB_URL" -f sql/migrate/create_model_version_registry.sql

BEGIN;

-- draft      — SQL exists, nothing materialised
-- candidate  — runs on the evaluation sample only; scored, never served
-- active     — fully materialised, served as the default
-- frozen     — logic will not change again, still refreshed against live data
-- deprecated — served only to customers pinned to it; no new pins
-- retired    — matview dropped
CREATE TYPE data.model_status AS ENUM (
    'draft',
    'candidate',
    'active',
    'frozen',
    'deprecated',
    'retired'
);

CREATE TABLE data.model_version (
    id           integer GENERATED ALWAYS AS IDENTITY NOT NULL,
    -- Release-style, and deliberately NOT 'v3'/'v4': those already mean API
    -- versions (/api/v3 on the C# Webservice, /v4/product/* on the TS one).
    -- Letting the two axes share a vocabulary makes every support conversation
    -- ambiguous. The CHECK keeps that decision enforced rather than remembered.
    slug         text NOT NULL,
    title        text NOT NULL,
    status       data.model_status NOT NULL,

    -- Commit of the sql/model/ tree the model was built from. Nullable because
    -- a draft may not be committed yet; required in practice from 'candidate' on.
    sql_git_sha  text,

    -- Vintage AND fingerprint of every input the model consumed. jsonb because
    -- Model 4 adds sources nobody has named yet, and a column per input would
    -- need a migration each time. Row counts are recorded alongside dates: most
    -- of these tables carry no date column at all, and a count is a better
    -- change-detector than a hand-typed date nobody updates.
    inputs       jsonb NOT NULL DEFAULT '{}'::jsonb,

    -- Records intent. Until the pointer view in step 2 of
    -- docs/model-versioning.md exists, `data.model_risk_static` is the
    -- authority on what is actually served; step 2 makes the two agree.
    is_default   boolean NOT NULL DEFAULT false,

    notes        text,
    created_at   timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activated_at timestamptz,
    frozen_at    timestamptz,
    -- The support promise for a deprecated version customers may still be
    -- pinned to. A commercial decision, recorded here so it is not folklore.
    retire_after date,

    CONSTRAINT model_version_pkey PRIMARY KEY (id),
    CONSTRAINT model_version_slug_key UNIQUE (slug),
    CONSTRAINT model_version_slug_format CHECK (slug ~ '^model-[0-9]{4}\.[0-9]+(-rc[0-9]+)?$'),
    CONSTRAINT model_version_inputs_is_object CHECK (jsonb_typeof(inputs) = 'object')
);

COMMENT ON TABLE data.model_version IS
    'Registry of risk model versions: what each was built from, and where it is in its lifecycle. See docs/model-versioning.md.';
COMMENT ON COLUMN data.model_version.inputs IS
    'Vintage and row-count fingerprint of each input dataset, so a diff between versions can attribute itself to logic or to data.';

-- Exactly one default, enforced rather than assumed.
CREATE UNIQUE INDEX model_version_one_default_idx ON data.model_version (is_default)
    WHERE is_default;

-- ---------------------------------------------------------------------------
-- Register the model that exists today.
--
-- sql_git_sha is the last commit touching sql/model/ (3d76339, 2026-08-06).
-- Note it is a tile fix: the last change to the *risk logic* was #1005 and
-- #1002 on 2026-07-21, both recorded in notes below.
--
-- Input fingerprints are live counts, taken at the moment this migration runs,
-- so they describe the data this model is actually standing on.
-- ---------------------------------------------------------------------------
INSERT INTO data.model_version (slug, title, status, sql_git_sha, is_default, frozen_at, notes, inputs)
SELECT
    'model-2024.1',
    'Foundation risk model (frozen)',
    'frozen',
    '3d763393c764b187eed1c4b66af3c77133cdcf77',
    true,
    CURRENT_TIMESTAMP,
    'The model as it stood when its logic was frozen on 2026-08-09. Last risk-logic changes: #1005 (stop risk inheritance from the supercluster tier) and #1002 (construction-year fallback), both 2026-07-21. Known limitations measured on this version, see sql/validate/: 67.3% family accuracy and 60.2% wood recall on held-out surveyed buildings; wood is under-predicted where no inquiry exists (1.86% at the indicative tier against 39.8% where surveyed).',
    jsonb_build_object(
        'note', 'row counts are fingerprints taken when this row was inserted; dates are recorded only where the source carries one',
        'bag_building',      jsonb_build_object('rows', (SELECT count(*) FROM geocoder.building)),
        'building_elevation',        jsonb_build_object('rows', (SELECT count(*) FROM data.building_elevation)),
        'building_groundwater_level',jsonb_build_object('rows', (SELECT count(*) FROM data.building_groundwater_level)),
        'building_geographic_region',jsonb_build_object('rows', (SELECT count(*) FROM data.building_geographic_region)),
        'building_pleistocene',      jsonb_build_object('rows', (SELECT count(*) FROM data.building_pleistocene)),
        'building_subsidence',       jsonb_build_object('rows', (SELECT count(*) FROM data.building_subsidence),
                                                        'vintage', (SELECT max(mark_at) FROM data.building_subsidence_history)),
        'inquiry_sample',            jsonb_build_object('rows', (SELECT count(*) FROM report.inquiry_sample WHERE delete_date IS NULL))
    );

-- ---------------------------------------------------------------------------
-- Grants. Read-only for everyone: the registry is written by migrations, not
-- by services. The API and Webservice need SELECT so a response can eventually
-- state which model answered it.
-- ---------------------------------------------------------------------------
GRANT SELECT ON data.model_version TO fundermaps_webapp;
GRANT SELECT ON data.model_version TO fundermaps_webservice;
GRANT SELECT ON data.model_version TO fundermaps_windmill;
GRANT SELECT ON data.model_version TO grafana;

COMMIT;
