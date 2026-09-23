-- More than one damage cause and damage characteristic per sample (API #128).
--
-- report.inquiry_sample holds one damage_cause and one damage_characteristics.
-- A report routinely names several ("houtrot, negatieve kleef en zetting";
-- "scheuren, klemmende deuren en een scheve vloer"), and at entry the rest is
-- dropped: on 2026-09-21 1,021 of 1,282 characteristics were "crack" and
-- "crooked_floor_wall" appeared three times in the whole database -- what
-- surveyors pick when forced to choose one, not what they see.
--
-- The cheap path Don and Yorick settled on: a list BESIDE the scalar, the
-- scalar stays the hoofdoorzaak. /v4/product/* (Rabobank, NWWI, Calcasa), the
-- model matviews and the tiles keep reading damage_cause and do not change.
-- Array columns rather than a child table: existing reads stay untouched and
-- the lists carry no attributes of their own.
--
-- The invariant, kept by a trigger so today's single-value writers (the
-- Studio form, the dataops commit) need no change:
--   * a non-null scalar is always in its list, as the first item;
--   * a writer that changes only the scalar REPLACES the old value in the
--     list (a correction, not an addition);
--   * a writer that changes only the list makes its first item the scalar;
--   * a writer that changes both keeps its scalar, which joins the list first.
--
-- On prod 2026-09-23: 501,040 samples, 5,278 with a damage_cause, 1,287 with
-- damage_characteristics. The backfill copies those into the lists with the
-- update_date trigger disabled, so update_date does not move for 6,565 rows.

ALTER TABLE report.inquiry_sample
    ADD COLUMN damage_cause_list report.foundation_damage_cause[] NOT NULL DEFAULT '{}',
    ADD COLUMN damage_characteristics_list report.foundation_damage_characteristics[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN report.inquiry_sample.damage_cause_list IS
'Every damage cause the report names, hoofdoorzaak first. damage_cause is always its first item (trigger inquiry_sample_damage_lists).';
COMMENT ON COLUMN report.inquiry_sample.damage_characteristics_list IS
'Every damage characteristic the report names, the main one first. damage_characteristics is always its first item (trigger inquiry_sample_damage_lists).';

ALTER TABLE report.inquiry_sample DISABLE TRIGGER update_date_record;
UPDATE report.inquiry_sample SET damage_cause_list = ARRAY[damage_cause] WHERE damage_cause IS NOT NULL;
UPDATE report.inquiry_sample SET damage_characteristics_list = ARRAY[damage_characteristics] WHERE damage_characteristics IS NOT NULL;
ALTER TABLE report.inquiry_sample ENABLE TRIGGER update_date_record;

CREATE OR REPLACE FUNCTION report.inquiry_sample_damage_lists()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    old_cause report.foundation_damage_cause;
    old_cause_list report.foundation_damage_cause[];
    old_char report.foundation_damage_characteristics;
    old_char_list report.foundation_damage_characteristics[];
BEGIN
    IF TG_OP = 'UPDATE' THEN
        old_cause := OLD.damage_cause;           old_cause_list := OLD.damage_cause_list;
        old_char := OLD.damage_characteristics;  old_char_list := OLD.damage_characteristics_list;
    ELSE
        old_cause_list := '{}';
        old_char_list := '{}';
    END IF;
    NEW.damage_cause_list := coalesce(NEW.damage_cause_list, '{}');
    NEW.damage_characteristics_list := coalesce(NEW.damage_characteristics_list, '{}');

    -- damage_cause / damage_cause_list
    IF NEW.damage_cause_list IS NOT DISTINCT FROM old_cause_list
       AND NEW.damage_cause IS DISTINCT FROM old_cause THEN
        -- Only the scalar moved (a single-value writer): replace, not add.
        NEW.damage_cause_list := array_remove(NEW.damage_cause_list, old_cause);
    ELSIF NEW.damage_cause_list IS DISTINCT FROM old_cause_list
       AND NEW.damage_cause IS NOT DISTINCT FROM old_cause THEN
        -- Only the list moved (a list writer): its first item is the hoofdoorzaak.
        NEW.damage_cause := NEW.damage_cause_list[1];
    END IF;
    IF NEW.damage_cause IS NOT NULL THEN
        NEW.damage_cause_list := array_prepend(NEW.damage_cause, array_remove(NEW.damage_cause_list, NEW.damage_cause));
    ELSIF cardinality(NEW.damage_cause_list) > 0 THEN
        NEW.damage_cause := NEW.damage_cause_list[1];
    END IF;

    -- damage_characteristics / damage_characteristics_list, the same rules
    IF NEW.damage_characteristics_list IS NOT DISTINCT FROM old_char_list
       AND NEW.damage_characteristics IS DISTINCT FROM old_char THEN
        NEW.damage_characteristics_list := array_remove(NEW.damage_characteristics_list, old_char);
    ELSIF NEW.damage_characteristics_list IS DISTINCT FROM old_char_list
       AND NEW.damage_characteristics IS NOT DISTINCT FROM old_char THEN
        NEW.damage_characteristics := NEW.damage_characteristics_list[1];
    END IF;
    IF NEW.damage_characteristics IS NOT NULL THEN
        NEW.damage_characteristics_list := array_prepend(NEW.damage_characteristics, array_remove(NEW.damage_characteristics_list, NEW.damage_characteristics));
    ELSIF cardinality(NEW.damage_characteristics_list) > 0 THEN
        NEW.damage_characteristics := NEW.damage_characteristics_list[1];
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION report.inquiry_sample_damage_lists() OWNER TO fundermaps;

CREATE TRIGGER inquiry_sample_damage_lists
    BEFORE INSERT OR UPDATE OF damage_cause, damage_cause_list, damage_characteristics, damage_characteristics_list
    ON report.inquiry_sample
    FOR EACH ROW EXECUTE FUNCTION report.inquiry_sample_damage_lists();
