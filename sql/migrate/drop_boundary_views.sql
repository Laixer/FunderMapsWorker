-- One-shot: drop the maplayer.boundary_* views (applied to prod 2026-07-22).
--
-- The administrative-boundary feature was dead end-to-end: the WebFront
-- composable (useAdministrativeBoundries) was imported nowhere, the layer
-- configs requested a Spaces prefix that 404s (tiles were uploaded once under
-- the misspelled prefix boundry_* — and the MVT layer inside them carries the
-- same typo, so the source-layer wouldn't have matched either), and the views
-- were not in maplayer.bundle so nothing ever rebuilt the tiles. Frontend dead
-- code removed in FunderMapsWebFront; typo'd Spaces prefixes deleted.
--
-- The views were trivial projections (SELECT geom FROM geocoder.{district,
-- municipality,neighborhood}) — if admin boundaries return, serve them from
-- Martin as function sources on the geocoder tables directly.

DROP VIEW IF EXISTS
    maplayer.boundary_district,
    maplayer.boundary_municipality,
    maplayer.boundary_neighborhood;
