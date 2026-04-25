-- Phase A: rename application.attribution FK columns to _id convention.
-- Wire format preserved by app-layer aliases (Drizzle: name arg; C#: AS-alias on SELECT).
-- Coordinated deploy required: backend code must be updated to use new column names
-- before this migration runs, OR backends accept brief downtime during deploy window.
-- Run as: fundermaps (owner)

BEGIN;

ALTER TABLE application.attribution RENAME COLUMN contractor TO contractor_id;
ALTER TABLE application.attribution RENAME COLUMN creator    TO creator_id;
ALTER TABLE application.attribution RENAME COLUMN owner      TO owner_id;
ALTER TABLE application.attribution RENAME COLUMN reviewer   TO reviewer_id;

ALTER TABLE application.attribution RENAME CONSTRAINT attribution_contractor_fkey TO attribution_contractor_id_fkey;
ALTER TABLE application.attribution RENAME CONSTRAINT attribution_creator_fkey    TO attribution_creator_id_fkey;
ALTER TABLE application.attribution RENAME CONSTRAINT attribution_owner_fkey      TO attribution_owner_id_fkey;
ALTER TABLE application.attribution RENAME CONSTRAINT attribution_reviewer_fkey   TO attribution_reviewer_id_fkey;

ALTER INDEX application.attribution_contractor_idx RENAME TO attribution_contractor_id_idx;
ALTER INDEX application.attribution_creator_idx    RENAME TO attribution_creator_id_idx;
ALTER INDEX application.attribution_owner_idx      RENAME TO attribution_owner_id_idx;
ALTER INDEX application.attribution_reviewer_idx   RENAME TO attribution_reviewer_id_idx;

COMMIT;
