-- Where each risk indication came from, per building, for the default model (Laixer/FunderMapsStudio#87: explain why
-- a building has its risk indication).
--
-- The 2026.3 model already records this next to every letter: quickscan, research, herstel, cluster, model or
-- build_year, and whether a QuickScan or a recent foundation report took the lead. Those five columns are not in
-- data.model_risk_static, which serves the 30 columns every model version has. This view serves them beside it,
-- read-only. Nothing in the model changes.
--
-- A pointer, like data.model_risk_static: when the default model switches, repoint both in the same migration.
-- True on prod 2026-11-12: data.model_risk_static selects from data.model_risk_static_2026_3; fundermaps_webapp may
-- read the pointer view and not the versioned matview.

CREATE VIEW data.model_risk_static_source AS
SELECT building_id,
       quickscan_gate,
       drystand_source,
       bio_infection_source,
       dewatering_depth_source,
       unclassified_source
FROM data.model_risk_static_2026_3;

COMMENT ON VIEW data.model_risk_static_source IS
    '[model output] Per building, where each risk of the default model came from (quickscan, research, herstel, cluster, model, build_year) and the QuickScan gate. Pointer beside data.model_risk_static: repoint both together. See docs/model-versioning.md.';

ALTER VIEW data.model_risk_static_source OWNER TO fundermaps;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        RAISE NOTICE 'role fundermaps_webapp does not exist; no grants';
        RETURN;
    END IF;
    REVOKE ALL ON data.model_risk_static_source FROM fundermaps_webapp;
    GRANT SELECT ON data.model_risk_static_source TO fundermaps_webapp;
END
$$;
