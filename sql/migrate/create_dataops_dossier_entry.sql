-- The dossier's timeline (docs/dataops-pipeline.md §11.1, agreed 2026-08-28).
--
-- One append-only log that every actor writes and nobody edits: the pipeline
-- read a document, a reviewer decided a value or wrote a remark, the outcome
-- changed, a mail went out, the melder replied. The structured facts stay in
-- their own tables (extraction, verdict, dossier_mail, outcome); this is the
-- narrative both the review screen and the melder's status page render --
-- the same rows, filtered by visible_to_melder, so the two can never tell
-- different stories.
--
-- Applied to prod 2026-09-04 (doadmin).

CREATE TYPE dataops.entry_kind AS ENUM (
    'received',     -- a channel opened or extended the dossier
    'extraction',   -- the pipeline read an artifact (links the extraction row)
    'finding',      -- another model checked something (address, BAG year, duplicate)
    'verdict',      -- a reviewer decided on a value (links the verdict row)
    'remark',       -- a reviewer wrote something down (internal)
    'question',     -- a reviewer asked the melder something -> mail out
    'reply',        -- the melder answered (email in) -> may carry artifacts
    'status'        -- outcome changed -> mail out
);

CREATE TYPE dataops.actor_kind AS ENUM ('melder', 'reviewer', 'pipeline', 'model', 'system');

CREATE TABLE dataops.dossier_entry (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dossier_id         bigint NOT NULL REFERENCES dataops.dossier (id) ON DELETE CASCADE,
    at                 timestamptz NOT NULL DEFAULT now(),
    kind               dataops.entry_kind NOT NULL,
    actor_kind         dataops.actor_kind NOT NULL,
    -- user id, model name or channel; null for the system
    actor              text,
    -- the content, shape per kind; never the only copy of a structured fact
    body               jsonb NOT NULL DEFAULT '{}'::jsonb,
    -- the human-readable line, always filled, in the reader's language (Dutch)
    text               text NOT NULL,
    artifact_id        bigint REFERENCES dataops.artifact (id) ON DELETE SET NULL,
    extraction_id      bigint REFERENCES dataops.extraction (id) ON DELETE SET NULL,
    verdict_id         bigint REFERENCES dataops.verdict (id) ON DELETE SET NULL,
    visible_to_melder  boolean NOT NULL,
    -- Message-ID of the mail this entry sent or came from; idempotency for mail
    mail_message_id    text
);

CREATE INDEX dossier_entry_dossier_idx ON dataops.dossier_entry (dossier_id, at);
CREATE UNIQUE INDEX dossier_entry_mail_idx ON dataops.dossier_entry (mail_message_id) WHERE mail_message_id IS NOT NULL;

COMMENT ON TABLE dataops.dossier_entry IS
  'Append-only timeline of a dossier. INSERT+SELECT only; an entry is never updated or deleted.';

-- Append-only is enforced by grants: nobody below doadmin can UPDATE or DELETE.
GRANT SELECT, INSERT ON dataops.dossier_entry TO fundermaps_webapp, fundermaps_windmill;
