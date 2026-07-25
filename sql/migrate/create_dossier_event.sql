-- Append-only trail of what happened to a dossier.
--
-- Every status transition in the API (`/status_review`, `/status_rejected`,
-- `/status_approved`, `/reset`) is a destructive `UPDATE ... SET audit_status`
-- that keeps no trace, so the sequence a dossier took is unrecoverable — only
-- its current position. `update_date` is no help either: the #973 attribution
-- backfill stamped 2026-06-27 onto 20,954 of 26,633 inquiries (79%), and a
-- 2026-03-07 migration did the same to 442,698 samples, so it records
-- migrations rather than people.
--
-- This table is the missing record. It also closes a smaller hole: a rejection
-- motivation is currently passed to Mailgun and stored nowhere, so the person
-- who has to fix the report can only learn why from their inbox — and api-prod
-- has no MAILGUN_* envs, so that mail may never arrive.
--
-- Additive, `report.*` only, no change to any existing table or enum — so the
-- C# Webservice (EOL Aug 2026) is untouched. Reversible with two DROPs.
--
--   psql "$DB_URL" -f sql/migrate/create_dossier_event.sql

BEGIN;

-- `imported` and `proposed` are the Data Ops pipeline's entries (see
-- docs/dataops-pipeline.md): a dossier that arrived as a document rather than
-- being typed, and a field the pipeline filled in for a reviewer to confirm.
CREATE TYPE report.dossier_event_kind AS ENUM (
    'created',
    'submitted',
    'approved',
    'rejected',
    'reopened',
    'imported',
    'proposed'
);

-- One nullable FK per dossier kind rather than a (type, text id) pair: the
-- three id types differ (incident ids are text), and the API hard-deletes
-- inquiries — `DELETE FROM report.inquiry` — so without a real FK this table
-- would silently accumulate orphans.
CREATE TABLE report.dossier_event (
    id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    kind report.dossier_event_kind NOT NULL,
    inquiry_id integer,
    recovery_id integer,
    incident_id text,
    -- NULL means the actor is not a person: a pipeline step, a Windmill flow,
    -- or a user deleted since (the FK sets this to NULL rather than dropping
    -- the event — that something happened outlives who did it).
    actor application.user_id,
    -- Free text the event carried: a rejection motivation, an import source.
    note text,
    -- Structured payload for machine-made events (artifact id, confidence,
    -- which field was proposed). Kept out of `note`, which is human prose.
    metadata jsonb,
    CONSTRAINT dossier_event_pkey PRIMARY KEY (id),
    CONSTRAINT dossier_event_one_subject CHECK (
        (inquiry_id IS NOT NULL)::integer
      + (recovery_id IS NOT NULL)::integer
      + (incident_id IS NOT NULL)::integer = 1
    ),
    CONSTRAINT dossier_event_inquiry_id_fkey FOREIGN KEY (inquiry_id)
        REFERENCES report.inquiry(id) ON DELETE CASCADE,
    CONSTRAINT dossier_event_recovery_id_fkey FOREIGN KEY (recovery_id)
        REFERENCES report.recovery(id) ON DELETE CASCADE,
    CONSTRAINT dossier_event_incident_id_fkey FOREIGN KEY (incident_id)
        REFERENCES report.incident(id) ON DELETE CASCADE,
    CONSTRAINT dossier_event_actor_fkey FOREIGN KEY (actor)
        REFERENCES application."user"(id) ON DELETE SET NULL
);

COMMENT ON TABLE report.dossier_event IS
    'Append-only trail of dossier lifecycle events. Exactly one of inquiry_id / recovery_id / incident_id is set.';

-- The only read pattern is "the trail for this dossier, oldest first". Partial
-- so each index covers just its own dossier kind; the incident one stays empty
-- until incidents get a writer.
CREATE INDEX dossier_event_inquiry_idx ON report.dossier_event (inquiry_id, create_date)
    WHERE inquiry_id IS NOT NULL;
CREATE INDEX dossier_event_recovery_idx ON report.dossier_event (recovery_id, create_date)
    WHERE recovery_id IS NOT NULL;
CREATE INDEX dossier_event_incident_idx ON report.dossier_event (incident_id, create_date)
    WHERE incident_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Grants
--
-- Prod has no default privileges for fundermaps_webapp in `report` (only
-- fundermaps_windmill=SELECT, set by doadmin), so these are explicit.
--
-- Append-only by permission, not just by convention: the API gets INSERT and
-- SELECT and no UPDATE or DELETE, so a trail it wrote cannot be rewritten by
-- the service that wrote it. Rows leave only by cascade when the dossier does.
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT ON report.dossier_event TO fundermaps_webapp;
GRANT SELECT, INSERT ON report.dossier_event TO fundermaps_windmill;
GRANT SELECT ON report.dossier_event TO grafana;

-- ---------------------------------------------------------------------------
-- Backfill: one truthful `created` event per existing dossier.
--
-- `create_date` and attribution.creator_id are the two facts about a dossier's
-- history that no migration has overwritten. Everything else that happened to
-- these 26k dossiers is gone, and inventing a plausible `submitted` from
-- update_date would be worse than a short trail.
-- ---------------------------------------------------------------------------
INSERT INTO report.dossier_event (kind, inquiry_id, create_date, actor)
SELECT 'created', i.id, i.create_date, a.creator_id
FROM report.inquiry i
JOIN application.attribution a ON a.id = i.attribution_id;

INSERT INTO report.dossier_event (kind, recovery_id, create_date, actor)
SELECT 'created', r.id, r.create_date, a.creator_id
FROM report.recovery r
JOIN application.attribution a ON a.id = r.attribution_id;

COMMIT;
