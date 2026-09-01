-- The document lane (2026-09-01): the whole PDF read in one model call.
-- Applied to prod 2026-09-01 (doadmin owns the type).
ALTER TYPE dataops.read_lane ADD VALUE IF NOT EXISTS 'document';
