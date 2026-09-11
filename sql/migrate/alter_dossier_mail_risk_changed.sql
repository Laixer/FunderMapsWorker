-- Risk follow-up mail (API #143 option B, Don 2026-09-11): after the model
-- refresh, a melder whose registered risk moved gets ONE mail saying so. That
-- is a fourth mail kind, 'risk_changed', and like received/closed it is
-- once-per-dossier -- so it joins the partial unique index the API's claim()
-- uses as its ON CONFLICT arbiter (the predicate must match exactly).
--
-- Reversible: drop the kind again after deleting its rows.
--
--   psql "$DB_URL" -f sql/migrate/alter_dossier_mail_risk_changed.sql

BEGIN;

ALTER TABLE dataops.dossier_mail DROP CONSTRAINT dossier_mail_kind_check;
ALTER TABLE dataops.dossier_mail
  ADD CONSTRAINT dossier_mail_kind_check
  CHECK (kind IN ('received', 'closed', 'question', 'risk_changed'));

DROP INDEX dataops.dossier_mail_once;
CREATE UNIQUE INDEX dossier_mail_once ON dataops.dossier_mail (dossier_id, kind)
  WHERE kind IN ('received', 'closed', 'risk_changed');

COMMENT ON COLUMN dataops.dossier_mail.kind IS
  'received (ontvangstbevestiging) | closed (afronding) | question (vraag aan de melder) | risk_changed (risico herberekend). received/closed/risk_changed at most once per dossier; question repeatable.';

COMMIT;
