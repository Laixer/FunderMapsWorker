DO $$
DECLARE
    r record;
    velocity_date date;
    c int;
BEGIN
    CREATE TEMPORARY TABLE temp_table_name (
        identificatie text not null,
        velocity float8 not null,
        date date not null
    ) ON COMMIT DROP;

    FOR r IN SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'buildings' AND column_name ~ 'v_[0-9]{8}'
    LOOP
        SELECT TO_DATE(REPLACE(r.column_name, 'v_', ''), 'YYYYMMDD') INTO velocity_date;
        EXECUTE format('INSERT INTO temp_table_name SELECT identifica, %s, %s FROM public.buildings WHERE %s <> 0', r.column_name, quote_literal(to_char(velocity_date, 'YYYY-MM-DD')), r.column_name);

        INSERT INTO data.subsidence_history
        SELECT b.external_id, ttn.velocity, ttn."date"
        FROM temp_table_name ttn
        JOIN geocoder.building b ON b.external_id = 'NL.IMBAG.PAND.' || ttn.identificatie
        WHERE ttn.velocity <> 0
        ON conflict ON constraint subsidence_history_pkey DO nothing;
        TRUNCATE temp_table_name;
    END LOOP;
END;
$$;
