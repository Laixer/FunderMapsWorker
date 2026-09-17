-- The risk follow-up (API intake-risk-followup.ts, Windmill step after every
-- model refresh) looks for closed dossiers whose risk snapshot has not been
-- checked yet:
--
--   where outcome is not null
--     and payload ? 'risk_snapshot'
--     and (payload->'risk_snapshot'->>'checked_at') is null
--
-- Nothing on dataops.dossier serves that, so it is a sequential scan that
-- detoasts every payload, twice a day, and it grows with every closed
-- dossier forever (checked snapshots stay in the payload). Today 4.4k rows
-- and milliseconds; at 100k dossiers tens of MB per run.
--
-- The partial index holds only the unchecked ones, i.e. almost nothing, and
-- its predicate is the query's predicate verbatim so the planner matches it.
-- Idempotent.
CREATE INDEX IF NOT EXISTS dossier_risk_snapshot_unchecked_idx
  ON dataops.dossier (id)
  WHERE outcome IS NOT NULL
    AND payload ? 'risk_snapshot'
    AND (payload -> 'risk_snapshot' ->> 'checked_at') IS NULL;
