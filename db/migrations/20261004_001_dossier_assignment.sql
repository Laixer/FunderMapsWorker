-- A dossier can be handed to a colleague: dataops.dossier.assigned_to (API #222).
--
-- Reviewers sometimes need a decision from a specific person (usually Don) on
-- a dossier: which document leads, reject or not. A dossier has no owner today;
-- the Studio's work packages are only filters on the queue, so a hand-over
-- happened outside the system and the dossier stayed in the general queue.
--
-- The API's POST /api/dataops/dossier/:id/assign sets or clears the person and
-- writes a 'status' entry on the timeline; GET /api/dataops/queue?assignedTo=me
-- lists what is waiting for you.
--
-- On prod 2026-10-04 (read-only): 5,358 dossiers; application.user.id is uuid;
-- dataops.dossier has column-scoped UPDATE grants for fundermaps_webapp
-- (fundermaps_api is a member), so the new columns need their own grant.
-- Two nullable columns without a default: a catalogue change, no rewrite.

ALTER TABLE dataops.dossier
    ADD COLUMN assigned_to uuid REFERENCES application."user"(id) ON DELETE SET NULL,
    ADD COLUMN assigned_at timestamptz;

CREATE INDEX dossier_assigned_to_idx ON dataops.dossier (assigned_to) WHERE assigned_to IS NOT NULL;

COMMENT ON COLUMN dataops.dossier.assigned_to IS
'The colleague this dossier is handed to (API #222). NULL = in the general queue. Set and cleared by POST /api/dataops/dossier/:id/assign.';
COMMENT ON COLUMN dataops.dossier.assigned_at IS
'When assigned_to was last set; NULL when nobody holds the dossier.';

GRANT UPDATE (assigned_to, assigned_at) ON dataops.dossier TO fundermaps_webapp;
