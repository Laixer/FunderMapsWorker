-- Finish the p_oplanger -> p_wood_charger rename of 20261030_005 (Yorick 2026-10-30: "Do the "do soon" renames next").
--
-- Renaming a column does not rename its PG18 NOT NULL constraint, and data.foundation_candidate()'s comment (the
-- TileJSON metadata Martin used to publish, kept for when the candidate layer returns behind a login) still listed
-- the field under its old name. On prod (2026-10-30) these were the only two places left with the old name.

SET LOCAL lock_timeout = '2s';

ALTER TABLE data.model_foundation_2026_2
    RENAME CONSTRAINT model_foundation_2026_2_p_oplanger_not_null TO model_foundation_2026_2_p_wood_charger_not_null;

COMMENT ON FUNCTION data.foundation_candidate(integer, integer, integer) IS $c${"description": "Candidate model-2026.2 foundation family (FunderMaps B.V. only, not served to customers)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "foundation_candidate", "minzoom": 12, "maxzoom": 16, "fields": {"building_id": "String", "family": "String", "foundation_type": "String", "grade": "String", "source": "String", "p_wood_charger": "Number", "p_wood": "Number", "p_no_pile": "Number", "p_concrete": "Number", "confidence": "Number", "evidence": "String", "current_type": "String", "height": "Number"}}]}$c$;
