-- Dossier questions by mail (docs/dataops-pipeline.md §11): a reviewer asks
-- the melder something from the review screen and the question goes out as a
-- Resend mail from melding@funderdata.nl. That adds a third mail kind,
-- 'question' -- and unlike the ontvangstbevestiging and the afronding, a
-- dossier can carry MORE than one of them.
--
-- So the (dossier, kind) idempotency guard narrows to the two
-- one-per-dossier moments. It stays the ON CONFLICT arbiter for those (the
-- API's claim() infers it by columns + predicate); question rows are plain
-- INSERTs, one per question asked.
--
-- Reversible: re-add the constraint after deleting question rows.
--
--   psql "$DB_URL" -f sql/migrate/alter_dossier_mail_question.sql

BEGIN;

ALTER TABLE dataops.dossier_mail DROP CONSTRAINT dossier_mail_kind_check;
ALTER TABLE dataops.dossier_mail
  ADD CONSTRAINT dossier_mail_kind_check
  CHECK (kind IN ('received', 'closed', 'question'));

ALTER TABLE dataops.dossier_mail DROP CONSTRAINT dossier_mail_once;
CREATE UNIQUE INDEX dossier_mail_once ON dataops.dossier_mail (dossier_id, kind)
  WHERE kind IN ('received', 'closed');

COMMENT ON COLUMN dataops.dossier_mail.kind IS
  'received (ontvangstbevestiging) | closed (afronding) | question (vraag aan de melder). received/closed at most once per dossier; question repeatable.';

COMMIT;
