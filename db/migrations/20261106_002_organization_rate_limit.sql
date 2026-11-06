-- Rate limits per organisation, and a counter instead of counting (Laixer/FunderMapsStudio#40,
-- Laixer/FunderMapsWebservice#16).
--
-- A limit is set on an API key, but what it limits is the organisation: the count already covers all of
-- that organisation's rows. So a second key starts unlimited, which blocks letting customers make their
-- own keys. And the check counts rows on every request to a limited key, which grows with the customer's
-- volume in the window.
--
-- True on prod 2026-11-05: no organisation has two limited keys, so every limit maps onto one organisation
-- and product without a conflict, and no other key of those organisations has ever been used. The count
-- takes 38 ms on average and up to 1.66 s.
--
-- Nothing changes for anyone until the Webservice and the API move over: they still use
-- application.api_key_rate_limit, which stays until a later migration. Rows already in the counter are
-- this month's, which is all a limit can look at.
--
-- The caller waits for a billing insert, so the lock has to be short. This month's rows are counted while
-- inserts go on, except the last five minutes: those are counted under the lock, which takes milliseconds,
-- and then the trigger takes over. So no row is counted twice or not at all.

SET LOCAL lock_timeout = '2s';

-- The previous migration's index, in case its build failed and a rerun passed over the leftovers.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_index
        WHERE indexrelid = to_regclass('application.product_tracker_org_prod_building_date_idx') AND indisvalid
    ) THEN
        RAISE EXCEPTION 'product_tracker_org_prod_building_date_idx is missing or invalid: DROP INDEX CONCURRENTLY it, CREATE it again as in 20261106_001, and rerun';
    END IF;
END
$$;

-- The limits.
CREATE TABLE application.organization_rate_limit (
    organization_id uuid NOT NULL REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE,
    product text NOT NULL,
    period text NOT NULL CHECK (period IN ('day', 'month')),
    limit_count integer NOT NULL CHECK (limit_count >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, product)
);
COMMENT ON TABLE application.organization_rate_limit IS
    '[billing] Per-(organization, product) limits on billable events, enforced by FunderMapsWebservice. No row = unlimited; limit_count 0 = no access to that product.';

-- Every limit must belong to exactly one organisation, or it isn't clear what it means now.
DO $$
DECLARE
    unclear bigint;
BEGIN
    SELECT count(*) INTO unclear
    FROM application.api_key_rate_limit r
    WHERE 1 <> (
        SELECT count(DISTINCT ou.organization_id)
        FROM application.organization_user ou
        WHERE ou.user_id::text = (
            SELECT k.reference_id::text FROM application.apikey k WHERE r.source = 'ba' AND k.id::text = r.api_key_id
            UNION ALL
            SELECT a.user_id::text FROM application.auth_key a WHERE r.source = 'legacy' AND a.id::text = r.api_key_id
        )
    );
    IF unclear > 0 THEN
        RAISE EXCEPTION '% rate limit(s) are on a key without exactly one organisation; nothing changed', unclear;
    END IF;
END
$$;

-- Two keys of one organisation with different limits fail on the primary key, which is right: someone has
-- to choose. The same limit twice is one limit.
INSERT INTO application.organization_rate_limit (organization_id, product, period, limit_count, created_at, updated_at)
SELECT ou.organization_id, r.product, r.period, r.limit_count, min(r.created_at), max(r.updated_at)
FROM application.api_key_rate_limit r
LEFT JOIN application.apikey k ON r.source = 'ba' AND k.id::text = r.api_key_id
LEFT JOIN application.auth_key a ON r.source = 'legacy' AND a.id::text = r.api_key_id
JOIN application.organization_user ou ON ou.user_id::text = coalesce(k.reference_id::text, a.user_id::text)
GROUP BY ou.organization_id, r.product, r.period, r.limit_count;

COMMENT ON TABLE application.api_key_rate_limit IS
    '[billing] Replaced by organization_rate_limit (2026-11-05). Stays until the Webservice and the API have moved; a later migration drops it.';

-- The counter.
CREATE TABLE application.product_tracker_count (
    organization_id uuid NOT NULL REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE,
    product text NOT NULL,
    day date NOT NULL,
    count bigint NOT NULL,
    PRIMARY KEY (organization_id, product, day)
) WITH (fillfactor = 50);
COMMENT ON TABLE application.product_tracker_count IS
    '[billing] Rows of application.product_tracker per organisation, product and UTC day, kept by a trigger, so a rate limit reads at most 31 rows instead of counting. Complete from the month it was created in. product_tracker stays the billing record; deleting rows there does not lower this.';

CREATE FUNCTION application.product_tracker_count_insert() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO application.product_tracker_count AS c (organization_id, product, day, count)
    VALUES (NEW.organization_id, NEW.product, (NEW.create_date AT TIME ZONE 'UTC')::date, 1)
    ON CONFLICT (organization_id, product, day) DO UPDATE SET count = c.count + 1;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    -- The billing row matters more than the counter. Callers swallow a failed insert, so an error here
    -- would lose it without a trace; a count that's one short is the smaller mistake.
    RAISE WARNING 'product_tracker_count not updated: %', SQLERRM;
    RETURN NULL;
END;
$$;

-- Up to five minutes ago, with inserts going on. An insert is one statement that finishes within seconds, so
-- no older row can still arrive after this.
CREATE TEMP TABLE product_tracker_count_so_far ON COMMIT DROP AS
SELECT organization_id, product, (create_date AT TIME ZONE 'UTC')::date AS day, count(*) AS count
FROM application.product_tracker
WHERE create_date >= date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
  AND create_date < now() - interval '5 minutes'
GROUP BY 1, 2, 3;

LOCK TABLE application.product_tracker IN SHARE ROW EXCLUSIVE MODE;

INSERT INTO application.product_tracker_count (organization_id, product, day, count)
SELECT organization_id, product, day, sum(count)
FROM (
    SELECT organization_id, product, day, count FROM product_tracker_count_so_far
    UNION ALL
    SELECT organization_id, product, (create_date AT TIME ZONE 'UTC')::date, count(*)
    FROM application.product_tracker
    WHERE create_date >= greatest(
        now() - interval '5 minutes',
        date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
    )
    GROUP BY 1, 2, 3
) counted
GROUP BY organization_id, product, day;

CREATE TRIGGER product_tracker_count_insert
    AFTER INSERT ON application.product_tracker
    FOR EACH ROW EXECUTE FUNCTION application.product_tracker_count_insert();

ALTER TABLE application.organization_rate_limit OWNER TO fundermaps;
ALTER TABLE application.product_tracker_count OWNER TO fundermaps;
ALTER FUNCTION application.product_tracker_count_insert() OWNER TO fundermaps;

-- As the old table, and whoever may insert a billing row must be able to count it. Each checked, because
-- a missing grant on the counter wouldn't show anywhere but in a warning.
DO $$
DECLARE
    role_name text;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['fundermaps_webapp', 'fundermaps_webservice'] LOOP
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = role_name) THEN
            RAISE NOTICE 'role % does not exist; no grants for it', role_name;
            CONTINUE;
        END IF;
        EXECUTE format('GRANT SELECT, INSERT, UPDATE ON application.product_tracker_count TO %I', role_name);
        IF NOT has_table_privilege(role_name, 'application.product_tracker_count', 'SELECT, INSERT, UPDATE') THEN
            RAISE EXCEPTION '% still cannot keep application.product_tracker_count', role_name;
        END IF;
    END LOOP;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON application.organization_rate_limit TO fundermaps_webapp;
    END IF;
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webservice') THEN
        GRANT SELECT ON application.organization_rate_limit TO fundermaps_webservice;
    END IF;
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundie_agent') THEN
        GRANT SELECT ON application.organization_rate_limit TO fundie_agent;
    END IF;
END
$$;
