-- Vendor GPKG uses velocity = 0 as "no measurement" (such buildings never carry per-date
-- displacement columns either; load_subsidence_history.sql already skips zeros). Keeping
-- them would make the model read "stable" where there is no data — 11,725 such rows were
-- removed from prod on 2026-08-21. A real 0.0 mm/yr never survives float rounding anyway.
INSERT INTO "data".building_subsidence
SELECT b.external_id, p.velocity
FROM public.buildings AS p
JOIN geocoder.building AS b ON b.external_id = 'NL.IMBAG.PAND.' || p.identifica
WHERE p.velocity IS NOT NULL
  AND p.velocity <> 0
ON conflict ON CONSTRAINT building_subsidence_pkey DO nothing;
