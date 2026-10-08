-- no_pile_bearing_floor gets a dewatering risk like the rest of the no-pile family.
--
-- Don, 2026-10-08, on a melding about a 1938 pand in Vlaardingen with a
-- "vastgestelde" D: "Dat is gewoon een type in de familie no_pile. Dit is een
-- bug in het huidige model en moet aangepast worden."
--
-- data.compute_indicative_dewatering_risk listed the no-pile family without
-- no_pile_bearing_floor ("excl bearing_floor for risk calc, matching current
-- behavior"; no reason found in the history). Those panden got no
-- dewatering risk even with a groundwater level, all three risk components
-- stayed NULL, and the construction-year fallback (#1002) put them in
-- unclassified_risk: D before 1970. That field is the one the map labels as
-- established and the light product returns since 2026-09-03 (Worker #242).
--
-- Prod on 2026-10-08, 1,396 panden with no_pile_bearing_floor (1,743
-- addresses); dewatering risk after this change vs the fallback today:
--   fallback d -> dewatering b   1,156 panden
--   fallback d -> dewatering c     110
--   fallback d -> dewatering d      15
--   fallback b -> dewatering b      95
--   fallback b -> dewatering d       8
--   other / unchanged               12
-- so about 1,266 panden leave the build-year D. 4 stay NULL (no
-- groundwater level) and keep the fallback.
--
-- Only this function changes (compute_restoration_costs uses its own,
-- unchanged list). It lands at the next model refresh (12:30 / 21:00 CEST),
-- not on apply. Same text as sql/model/create_helper_functions.sql. The
-- current model is otherwise frozen; this is a bug fix on Don's word, for
-- Yorick to approve.

CREATE OR REPLACE FUNCTION data.compute_indicative_dewatering_risk(
    ft report.foundation_type,
    velocity double precision,
    gwl double precision,
    has_recovery boolean
)
RETURNS data.foundation_risk_indication
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication
        WHEN data.is_safe_foundation(ft) THEN 'a'::data.foundation_risk_indication

        -- No-pile family, bearing_floor included (Don, 2026-10-08: "gewoon een type in de familie
        -- no_pile"; leaving it out sent 1,396 panden to the construction-year fallback)
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity IS NULL AND gwl < 0.6
            THEN 'c'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity IS NULL AND gwl >= 0.6
            THEN 'b'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity < -1.0 AND gwl < 0.6
            THEN 'e'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity < -1.0 AND gwl >= 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity >= -1.0 AND gwl < 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor')
             AND velocity >= -1.0 AND gwl >= 0.6
            THEN 'c'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;

ALTER FUNCTION data.compute_indicative_dewatering_risk(report.foundation_type, double precision, double precision, boolean) OWNER TO fundermaps;
