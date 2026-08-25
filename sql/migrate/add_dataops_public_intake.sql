-- Data Ops — the public front door.
--
-- The terugmeldformulier (FunderMapsIntake) delivers documents from outside the
-- building: a homeowner with an archive drawing, a makelaar with a QuickScan, a
-- corporation with a herstelbewijs. Until now the only public intake path wrote
-- straight to report.incident.
--
-- That was wrong, and not merely in name. Nothing consumes report.incident --
-- two read-only GET endpoints across nine repositories, no Studio route, no
-- worker, no Windmill flow. A funderingsonderzoek delivered that way lands in a
-- table nobody works from and never reaches the review queue. Most of what this
-- form receives is not an incident at all; it is a document.
--
-- docs/dataops-pipeline.md already had the answer in §2: a dossier resolves to
-- ONE OF incident, report or recovery, and that choice belongs to stage 10
-- (COMMIT), made by a reviewer. So every submission becomes a dossier -- with
-- documents or without -- and an incident is one of the things it may turn into,
-- not the thing it is.
--
-- What a form supplies that a bulk drop does not:
--
--   * the building, stated by the person, not inferred from the document. This
--     is better evidence than stage 4 (RESOLVE) can produce on its own, and
--     there was nowhere in the schema to put it.
--   * a submitter we can write back to.
--   * what they say they are delivering, which is not the same as what the
--     document turns out to be -- both are worth keeping.
--
-- §5.4 already called for "raw payloads in a jsonb column alongside typed
-- columns when the email and JSON channels land". This is that, for the form.
--
-- Additive only. Every column is nullable; the 891 existing bulk_drop dossiers
-- are untouched and keep working unchanged.
--
--   psql "$DB_URL" -f sql/migrate/add_dataops_public_intake.sql

BEGIN;

-- How far stage 4 got. Named in docs/dataops-pipeline.md §4 and never built,
-- because bulk_drop had no address to resolve. The form hands us one.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'dataops' AND t.typname = 'resolution_status') THEN
    CREATE TYPE dataops.resolution_status AS ENUM ('resolved', 'stale_bag', 'ambiguous', 'absent');
  END IF;
END $$;

-- What a reviewer decided about the whole dossier, in terms a melder can be
-- told. Distinct from dataops.review_state, which is per proposed value: a
-- dossier can be accepted while three of its eight fields were corrected.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'dataops' AND t.typname = 'dossier_outcome') THEN
    CREATE TYPE dataops.dossier_outcome AS ENUM ('accepted', 'rejected', 'duplicate');
  END IF;
END $$;

-- The melder-facing code. One per submission, whatever the submission turns
-- into -- the person gets a single receipt and should not have to care whether
-- their drawing became an inquiry and their complaint an incident.
--
-- Sequential, so it is trivially enumerable: FM2026-000042 is one away from
-- somebody else's. The status endpoint therefore requires the submitting email
-- as well, and answers a wrong email exactly as it answers a missing code.
CREATE SEQUENCE IF NOT EXISTS dataops.dossier_reference_seq;

CREATE OR REPLACE FUNCTION dataops.generate_reference() RETURNS text
    LANGUAGE sql
    AS $_$
      SELECT 'FM' || date_part('year', CURRENT_DATE)::int || '-' ||
             lpad(nextval('dataops.dossier_reference_seq')::text, 6, '0');
    $_$;

COMMENT ON FUNCTION dataops.generate_reference() IS
  'Melder-facing dossier reference, e.g. FM2026-000042. Not a secret: sequential by design, so anything reading by reference must also check the submitter.';

ALTER TABLE dataops.dossier
  -- The meldcode. Nullable: the 891 bulk_drop dossiers never had one and no
  -- human is waiting on them.
  ADD COLUMN IF NOT EXISTS reference text,
  -- BAG nummeraanduiding as the melder chose it, in whichever of the two forms
  -- their entry point produced. Left exactly as given; resolution to a pand is
  -- the API's job, and keeping the original means a bad resolution can be
  -- re-run later against a fresher BAG (issue #992).
  ADD COLUMN IF NOT EXISTS bag_id text,
  -- NL.IMBAG.PAND.*, once resolved.
  ADD COLUMN IF NOT EXISTS building_id text,
  ADD COLUMN IF NOT EXISTS resolution_status dataops.resolution_status,
  -- Personal data, deliberately in its own column rather than buried in the
  -- payload: a retention or erasure request has to be able to find it without
  -- parsing everything else the form sent.
  ADD COLUMN IF NOT EXISTS submitter jsonb,
  -- What the melder said they were doing: topic, their answers, form version,
  -- and the request provenance. Their claim, not a finding.
  ADD COLUMN IF NOT EXISTS payload jsonb,
  ADD COLUMN IF NOT EXISTS outcome dataops.dossier_outcome,
  -- Why, in words a melder can read. Don asked for this on the review screen:
  -- "Fout needs a text field as to why". Same field, one audience further on.
  ADD COLUMN IF NOT EXISTS outcome_note text,
  ADD COLUMN IF NOT EXISTS outcome_at timestamptz;

-- One reference, one dossier. Partial, because most dossiers have none.
CREATE UNIQUE INDEX IF NOT EXISTS dossier_reference_key
  ON dataops.dossier (reference) WHERE reference IS NOT NULL;

-- The status lookup: reference plus submitting email, never reference alone.
CREATE INDEX IF NOT EXISTS dossier_submitter_email_idx
  ON dataops.dossier ((lower(submitter ->> 'email'))) WHERE submitter IS NOT NULL;

-- "What else has this building sent us" — stage 5 (ENRICH) wants this, and so
-- does a reviewer looking at a second delivery for an address.
CREATE INDEX IF NOT EXISTS dossier_building_idx
  ON dataops.dossier (building_id) WHERE building_id IS NOT NULL;

COMMENT ON COLUMN dataops.dossier.reference IS 'Melder-facing code (FM2026-000042). Sequential, not a credential.';
COMMENT ON COLUMN dataops.dossier.bag_id IS 'BAG nummeraanduiding exactly as the melder supplied it, before resolution.';
COMMENT ON COLUMN dataops.dossier.building_id IS 'NL.IMBAG.PAND.* resolved from bag_id.';
COMMENT ON COLUMN dataops.dossier.submitter IS 'Contact details. Personal data — isolated so erasure can find it.';
COMMENT ON COLUMN dataops.dossier.payload IS 'What the melder claimed: topic, answers, form version, request provenance.';
COMMENT ON COLUMN dataops.dossier.outcome IS 'Dossier-level decision. Per-value decisions live in dataops.verdict.';

COMMIT;
