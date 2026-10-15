// L5: application.product_tracker (TimescaleDB hypertable) → plain table, online.
//
//   DATABASE_URL=… bun switch.ts <step>
//
// Steps, in order (each checks the live state first and refuses if it is not the expected one):
//   status     read-only: where are we
//   prepare    new empty plain table (same columns, defaults, NOT NULLs, owner, grants) + two trigger functions
//   arm        lock old briefly, install the mirror (every new row is copied into the new table) and the
//              freeze (UPDATE/DELETE on the old table raise), export that moment's snapshot, and copy every
//              row of that snapshot into the new table. No row twice, none missed.
//   index      the three indexes (CONCURRENTLY), the two foreign keys (NOT VALID, then VALIDATE), ANALYZE
//   matview    data.product_tracker_daily_next on the new table (same definition, index, owner, grants)
//   verify     old vs new: count and hash per month; recent window; read-only
//   swap       one short transaction: both pairs swap names (tables, indexes, constraints, matviews)
//   detach     after the swap: drop the old table's foreign keys, so cascades no longer touch it
//   cleanup    days later: drop the old hypertable, the old matview, the functions and the state table
//   abort      before the swap: undo everything, the old table stays as it was
//   rollback   after the swap: copy rows that only exist in the new table back, swap the names back
import postgres from "postgres";

const url = process.env.DATABASE_URL;
if (!url) { console.error("DATABASE_URL is not set"); process.exit(2); }
const sql = postgres(url, {
  max: 4,
  onnotice: (n) => console.log("   notice:", n.message),
  connection: { application_name: "l5-product-tracker-switch", statement_timeout: "0" },
});

const OLD = "application.product_tracker";
const NEW = "application.product_tracker_new";
const HYPER_OLD = "application.product_tracker_hyper_old";
const STATE = "application.product_tracker_switch";
const MV = "data.product_tracker_daily";
const MV_NEXT = "data.product_tracker_daily_next";
const MV_OLD = "data.product_tracker_daily_old";
const COLS = "organization_id, product, building_id, create_date, identifier";
const NOT_NULL_COLS = ["organization_id", "product", "building_id", "create_date", "identifier"];
const INDEXES = [
  ["building_id_idx", "USING btree (building_id)"],
  ["create_date_idx", "USING btree (create_date DESC)"],
  ["org_prod_id_date_idx", "USING btree (organization_id, product, identifier, create_date)"],
] as const;
// Added on the plain table only: without monthly chunks, the rate limit (org, product, since the window start),
// the dedups and the usage queries need an index that ends in create_date. The three above stay as they are.
const EXTRA_INDEXES = [["org_prod_date_idx", "USING btree (organization_id, product, create_date)"]] as const;
const NEW_INDEXES = [...INDEXES, ...EXTRA_INDEXES];
const FKS = [
  ["building_id_fkey", "FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE"],
  ["organization_id_fkey", "FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE"],
] as const;
const MV_SELECT = (from: string) => `SELECT (create_date AT TIME ZONE 'Europe/Amsterdam'::text)::date AS day,
    organization_id, product, count(*) AS calls
   FROM ${from}
  GROUP BY ((create_date AT TIME ZONE 'Europe/Amsterdam'::text)::date), organization_id, product`;

const t0 = Date.now();
const say = (s: string) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1).padStart(6)}s] ${s}`);
const die = async (s: string): Promise<never> => { console.error(`STOP: ${s}`); await sql.end(); process.exit(1); };

async function one<T = any>(q: string): Promise<T> { const r = await sql.unsafe(q); return r[0] as T; }
async function exists(rel: string) { return (await one<{ r: string | null }>(`select to_regclass('${rel}')::text as r`)).r !== null; }
async function isHyper(name: string) {
  return (await one<{ h: boolean }>(`select exists (select from timescaledb_information.hypertables
     where hypertable_schema = 'application' and hypertable_name = '${name}') as h`)).h;
}
async function triggers(rel: string): Promise<string[]> {
  if (!(await exists(rel))) return [];
  return (await sql.unsafe(`select tgname from pg_trigger where tgrelid = '${rel}'::regclass and not tgisinternal order by 1`)).map((r: any) => r.tgname);
}
async function grantsLike(from: string, to: string) {
  // copy every privilege except the owner's own, by role, from one relation to another
  const rows = await sql.unsafe(`select pg_get_userbyid(a.grantee) as role, string_agg(a.privilege_type, ', ') as privs
      from pg_class c, aclexplode(c.relacl) a
     where c.oid = '${from}'::regclass and a.grantee <> c.relowner and a.grantee <> 0
     group by 1 order by 1`);
  for (const r of rows as any[]) await sql.unsafe(`GRANT ${r.privs} ON ${to} TO ${r.role}`);
  return rows.map((r: any) => `${r.role}: ${r.privs}`).join("; ");
}

// PG 18 gives NOT NULL constraints generated names; give the plain table the names the hypertable had.
async function canonicalNotNulls(tx: any, rel: string, table: string) {
  const rows = await tx.unsafe(`select c.conname, a.attname from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.conrelid = '${rel}'::regclass and c.contype = 'n'`);
  for (const r of rows as any[]) {
    const want = `${table}_${r.attname}_not_null`;
    if (r.conname !== want) await tx.unsafe(`ALTER TABLE ${rel} RENAME CONSTRAINT ${r.conname} TO ${want}`);
  }
}
const ROWHASH = `sum(hashtextextended(concat_ws('|', organization_id, product, building_id, create_date, identifier), 0)::numeric)`;

type Stage = "start" | "prepared" | "armed" | "swapped" | "detached" | "clean" | "unknown";
async function stage(): Promise<{ stage: Stage; info: Record<string, unknown> }> {
  const oldHyper = await isHyper("product_tracker");
  const hyperOldExists = await exists(HYPER_OLD);
  const newExists = await exists(NEW);
  const state = (await exists(STATE)) ? await one(`select * from ${STATE}`) : null;
  const trig = await triggers(OLD);
  const info: Record<string, unknown> = { oldHyper, newExists, hyperOldExists, triggersOnOld: trig, state };
  if (oldHyper && !newExists && !state) return { stage: "start", info };
  if (oldHyper && newExists && trig.length === 0) return { stage: "prepared", info };
  if (oldHyper && newExists && trig.length === 2) return { stage: "armed", info };
  if (!oldHyper && hyperOldExists) {
    const fks = (await one<{ n: number }>(`select count(*)::int as n from pg_constraint where conrelid = '${HYPER_OLD}'::regclass and contype = 'f'`)).n;
    return { stage: fks > 0 ? "swapped" : "detached", info: { ...info, fksOnHyperOld: fks } };
  }
  if (!oldHyper && !hyperOldExists && !newExists && !state) return { stage: "clean", info };
  return { stage: "unknown", info };
}
async function expect(...want: Stage[]) {
  const s = await stage();
  if (!want.includes(s.stage)) await die(`expected stage ${want.join(" or ")}, found ${s.stage}: ${JSON.stringify(s.info)}`);
  return s;
}

// Writers and the Webservice's rate limit have no lock_timeout and the Webservice waits for its INSERT before it
// answers: every lock we queue for is customer latency. So: never queue behind a long query (wait until the table
// is quiet), and give up a lock request after 1 s and try again.
async function waitQuiet(rels: string[], label: string) {
  const list = rels.map((r) => `to_regclass('${r}')`).join(", ");
  for (let i = 0; i < 120; i++) {
    const r = (await sql.unsafe(`select count(distinct a.pid)::int as n, max(now() - a.xact_start)::text as oldest
        from pg_locks l join pg_stat_activity a on a.pid = l.pid
       where l.relation = any (array[${list}]::oid[]) and l.granted and a.pid <> pg_backend_pid()
         and a.state <> 'idle' and a.xact_start < now() - interval '1 second'`))[0] as any;
    if (r.n === 0) return;
    say(`${label}: ${r.n} session(s) with a transaction older than 1 s on the table (oldest ${r.oldest}); waiting 5 s`);
    await Bun.sleep(5000);
  }
  await die(`${label}: the table was never quiet for 10 minutes`);
}
async function withLock<T>(label: string, attempts: number, fn: (tx: any) => Promise<T>, quiet: string[] = []): Promise<T> {
  for (let i = 1; i <= attempts; i++) {
    if (quiet.length) await waitQuiet(quiet, label);
    try {
      return await sql.begin(async (tx) => { await tx.unsafe(`SET LOCAL lock_timeout = '1s'`); return fn(tx); });
    } catch (e: any) {
      if (e?.code === "55P03" && i < attempts) { say(`${label}: lock not granted in 1 s (attempt ${i}/${attempts}), retrying in 3 s`); await Bun.sleep(3000); continue; }
      throw e;
    }
  }
  throw new Error("unreachable");
}

const steps: Record<string, () => Promise<void>> = {
  async status() {
    const s = await stage();
    console.log(JSON.stringify(s, null, 2));
  },

  async prepare() {
    await expect("start");
    const def = await one<{ n: number }>(`select count(*)::int as n from pg_attribute where attrelid = '${OLD}'::regclass and attnum > 0 and not attisdropped`);
    if (def.n !== 5) await die(`${OLD} has ${def.n} columns, expected 5`);
    await sql.begin(async (tx) => {
      await tx.unsafe(`SET LOCAL lock_timeout = '3s'`);
      await tx.unsafe(`CREATE TABLE ${NEW} (LIKE ${OLD} INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING STORAGE INCLUDING COMMENTS)`);
      await tx.unsafe(`ALTER TABLE ${NEW} OWNER TO fundermaps`);
      await tx.unsafe(`CREATE TABLE ${STATE} (id int PRIMARY KEY DEFAULT 1 CHECK (id = 1), prepared_at timestamptz NOT NULL DEFAULT clock_timestamp(),
                         armed_at timestamptz, backfilled bigint, swapped_at timestamptz, detached_at timestamptz)`);
      await tx.unsafe(`INSERT INTO ${STATE} DEFAULT VALUES`);
    });
    const newOid = (await one<{ oid: number }>(`select '${NEW}'::regclass::oid::int as oid`)).oid;
    // The mirror targets the new table by OID, so it keeps working after the names swap.
    await sql.unsafe(`CREATE FUNCTION application.product_tracker_switch_mirror() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog AS $f$
      BEGIN
        EXECUTE format('INSERT INTO %s (${COLS}) SELECT ($1).organization_id, ($1).product, ($1).building_id, ($1).create_date, ($1).identifier', ${newOid}::regclass) USING NEW;
        RETURN NULL;
      END $f$`);
    await sql.unsafe(`CREATE FUNCTION application.product_tracker_switch_frozen() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog AS $f$
      BEGIN
        RAISE EXCEPTION 'application.product_tracker is being converted to a plain table (FunderMaps 5.0 L5): UPDATE and DELETE are blocked until the switch is done'
          USING ERRCODE = 'object_not_in_prerequisite_state';
      END $f$`);
    const g = await grantsLike(OLD, NEW);
    say(`prepared: ${NEW} (oid ${newOid}, empty), grants copied (${g}), mirror + freeze functions created`);
  },

  async arm() {
    await expect("prepared");
    const n = (await one<{ n: string }>(`select count(*)::text as n from ${NEW}`)).n;
    if (n !== "0") await die(`${NEW} is not empty (${n} rows); run 'abort' and start again`);
    const a = await sql.reserve();
    const b = await sql.reserve();
    let snapshot = "", armedAt = "";
    for (let i = 1; ; i++) {
      await waitQuiet([OLD], "arm");
      try {
        await a.unsafe(`BEGIN`);
        await a.unsafe(`SET LOCAL lock_timeout = '1s'`);
        // waits for in-flight inserts to finish, blocks new ones until COMMIT (milliseconds); readers are not blocked
        await a.unsafe(`LOCK TABLE ${OLD} IN SHARE ROW EXCLUSIVE MODE`);
        break;
      } catch (e: any) {
        await a.unsafe(`ROLLBACK`).catch(() => {});
        if (e?.code === "55P03" && i < 20) { say(`arm: lock not granted in 1 s (attempt ${i}/20), retrying in 3 s`); await Bun.sleep(3000); continue; }
        a.release(); b.release(); await die(`arm: ${e.message}`);
      }
    }
    try {
      const lockedAt = Date.now();
      await a.unsafe(`CREATE TRIGGER product_tracker_switch_mirror AFTER INSERT ON ${OLD} FOR EACH ROW EXECUTE FUNCTION application.product_tracker_switch_mirror()`);
      await a.unsafe(`CREATE TRIGGER product_tracker_switch_frozen BEFORE UPDATE OR DELETE ON ${OLD} FOR EACH ROW EXECUTE FUNCTION application.product_tracker_switch_frozen()`);
      const r = (await a.unsafe(`SELECT pg_export_snapshot() AS snap, clock_timestamp()::text AS at`))[0] as any;
      snapshot = r.snap; armedAt = r.at;
      await a.unsafe(`UPDATE ${STATE} SET armed_at = '${armedAt}'`);
      // the copy must import the snapshot while this transaction is still open
      await b.unsafe(`BEGIN ISOLATION LEVEL REPEATABLE READ`);
      await b.unsafe(`SET TRANSACTION SNAPSHOT '${snapshot}'`);
      await a.unsafe(`COMMIT`);
      say(`armed at ${armedAt}: mirror + freeze live; inserts were held for ${Date.now() - lockedAt} ms; snapshot ${snapshot} imported`);
    } catch (e: any) {
      await a.unsafe(`ROLLBACK`).catch(() => {}); await b.unsafe(`ROLLBACK`).catch(() => {});
      a.release(); b.release(); await die(`arm failed before the copy, nothing changed: ${e.message}`);
    }
    a.release();
    try {
      // One week per statement with a short pause in between, all inside the one snapshot: a single 4 GB
      // INSERT stalled every other query for ~5 s in the rehearsal (write pressure, not locks).
      const pause = Number(process.env.COPY_PAUSE_MS ?? 200);
      const weeks = await b.unsafe(`select g::text as s, (g + interval '7 days')::text as e
          from generate_series(date_trunc('week', (select min(create_date) from ${OLD})),
                               (select max(create_date) from ${OLD}), interval '7 days') g`);
      say(`copying every row of the snapshot into ${NEW}: ${weeks.length} weekly batches, ${pause} ms pause between …`);
      let copied = 0, slowest = 0;
      for (let i = 0; i < weeks.length; i++) {
        const w = weeks[i] as any, t = Date.now();
        const r = await b.unsafe(`INSERT INTO ${NEW} (${COLS}) SELECT ${COLS} FROM ${OLD}
            WHERE create_date >= '${w.s}' AND create_date < '${w.e}'`);
        copied += r.count; slowest = Math.max(slowest, Date.now() - t);
        if ((i + 1) % 25 === 0 || i === weeks.length - 1) say(`  ${i + 1}/${weeks.length} batches, ${copied} rows, slowest batch ${slowest} ms`);
        if (pause) await Bun.sleep(pause);
      }
      const total = Number((await b.unsafe(`select count(*) as n from ${OLD}`))[0].n);
      if (total !== copied) throw new Error(`copied ${copied} rows but the snapshot holds ${total}`);
      // NOT inside this transaction: its snapshot predates arm's own UPDATE of the state row, so updating that
      // row here fails with a serialization error (found in the rehearsal, after a complete copy)
      await b.unsafe(`COMMIT`);
      await sql.unsafe(`UPDATE ${STATE} SET backfilled = ${copied}`);
      say(`copy done: ${copied} rows, equal to the snapshot's count`);
    } catch (e: any) {
      await b.unsafe(`ROLLBACK`).catch(() => {});
      b.release(); await die(`the copy failed and was rolled back (${e.message}). The mirror is live, so the new table now holds only mirrored rows: run 'abort', then start again from 'prepare'`);
    }
    b.release();
  },

  async index() {
    await expect("armed");
    for (const [name, def] of NEW_INDEXES) {
      const idx = `product_tracker_new_${name}`;
      const ex = await one<{ v: boolean | null }>(`select (select indisvalid from pg_index where indexrelid = to_regclass('application.${idx}')) as v`);
      if (ex.v === true) { say(`index ${idx} exists`); continue; }
      if (ex.v === false) { await sql.unsafe(`DROP INDEX CONCURRENTLY application.${idx}`); say(`dropped invalid ${idx}`); }
      say(`building ${idx} …`);
      await sql.unsafe(`CREATE INDEX CONCURRENTLY ${idx} ON ${NEW} ${def}`);
      say(`built ${idx}`);
    }
    for (const [name, def] of FKS) {
      const con = `product_tracker_new_${name}`;
      const ex = await one<{ v: boolean | null }>(`select (select convalidated from pg_constraint where conrelid = '${NEW}'::regclass and conname = '${con}') as v`);
      if (ex.v === null) {
        // briefly blocks inserts (the mirror writes into this table inside every customer INSERT)
        await withLock(`fk ${con}`, 20, (tx) => tx.unsafe(`ALTER TABLE ${NEW} ADD CONSTRAINT ${con} ${def} NOT VALID`), [NEW, "geocoder.building", "application.organization"]);
        say(`added ${con} (NOT VALID)`);
      }
      if (ex.v !== true) { say(`validating ${con} …`); await sql.unsafe(`ALTER TABLE ${NEW} VALIDATE CONSTRAINT ${con}`); say(`validated ${con}`); }
    }
    await sql.unsafe(`ANALYZE ${NEW}`);
    say(`indexes and foreign keys ready on ${NEW}, analyzed`);
  },

  async matview() {
    await expect("armed");
    if (await exists(MV_NEXT)) await sql.unsafe(`DROP MATERIALIZED VIEW ${MV_NEXT}`);
    say(`building ${MV_NEXT} …`);
    await sql.unsafe(`CREATE MATERIALIZED VIEW ${MV_NEXT} AS ${MV_SELECT(NEW)}`);
    await sql.unsafe(`CREATE UNIQUE INDEX product_tracker_daily_next_pkey ON ${MV_NEXT} USING btree (day, organization_id, product)`);
    await sql.unsafe(`ALTER MATERIALIZED VIEW ${MV_NEXT} OWNER TO fundermaps`);
    const g = await grantsLike(MV, MV_NEXT);
    // the comment belongs to the object, so it would not follow the rename swap (missed on prod 2026-10-15, see 20261015_003)
    await sql.unsafe(`DO $$ BEGIN EXECUTE format('COMMENT ON MATERIALIZED VIEW ${MV_NEXT} IS %L', obj_description('${MV}'::regclass, 'pg_class')); END $$`);
    const c = await one<{ a: string; b: string }>(`select (select count(*) from ${MV})::text as a, (select count(*) from ${MV_NEXT})::text as b`);
    say(`${MV_NEXT} built (${c.b} rows; current ${MV} has ${c.a}), grants and comment copied (${g})`);
  },

  async verify() {
    await expect("armed");
    const st = await one<{ armed_at: string; backfilled: string }>(`select armed_at::text, backfilled::text from ${STATE}`);
    say(`armed at ${st.armed_at}, ${st.backfilled} rows copied; comparing per month, rows older than 2 minutes …`);
    // one pass over each table: count and order-independent hash per month
    const bucket = (rel: string) => `select date_trunc('month', create_date) as m, count(*) as n, ${ROWHASH} as h
      from ${rel} where create_date < now() - interval '2 minutes' group by 1`;
    const rows = await sql.unsafe(`with o as (${bucket(OLD)}), n as (${bucket(NEW)})
      select coalesce(o.m, n.m)::date::text as month, coalesce(o.n, 0)::bigint::text as old_n, coalesce(n.n, 0)::bigint::text as new_n,
             (o.n is not distinct from n.n and o.h is not distinct from n.h) as same
        from o full join n on n.m = o.m order by 1`);
    const sum = (k: "old_n" | "new_n") => (rows as any[]).reduce((a, r) => a + BigInt(r[k]), 0n);
    say(`${rows.length} months compared; rows older than 2 minutes: old ${sum("old_n")}, new ${sum("new_n")}`);
    const diff = (rows as any[]).filter((r) => !r.same);
    if (diff.length) { console.table(diff); await die(`${diff.length} month(s) differ`); }
    say(`every month identical (count and hash)`);
    const fk = await one<{ n: number }>(`select count(*)::int as n from pg_constraint where conrelid = '${NEW}'::regclass and contype = 'f' and convalidated`);
    const ix = await one<{ n: number }>(`select count(*)::int as n from pg_index where indrelid = '${NEW}'::regclass and indisvalid`);
    if (fk.n !== 2 || ix.n !== NEW_INDEXES.length) await die(`new table not ready: ${ix.n}/${NEW_INDEXES.length} valid indexes, ${fk.n}/2 validated foreign keys (run 'index')`);
    if (!(await exists(MV_NEXT))) await die(`${MV_NEXT} missing (run 'matview')`);

    // Every query shape that reads the table in production, with the busiest real values, on both tables.
    const busy = await one<{ org: string; product: string }>(`select organization_id::text as org, product from ${OLD}
        where create_date >= date_trunc('month', now()) group by 1, 2 order by count(*) desc limit 1`);
    const recent = await one<{ b: string; ident: string }>(`select building_id::text as b, identifier as ident from ${OLD}
        where organization_id = '${busy.org}' and product = '${busy.product}' order by create_date desc limit 1`);
    const org = `'${busy.org}'`, prod = `'${busy.product}'`, b = `'${recent.b}'`, ident = `'${recent.ident.replace(/'/g, "''")}'`;
    const shapes: [string, (rel: string) => string][] = [
      ["WS rate limit, month window", (r) => `select count(*) from ${r} where organization_id = ${org} and product = ${prod} and create_date >= date_trunc('month', now() at time zone 'utc') at time zone 'utc'`],
      ["WS rate limit, day window", (r) => `select count(*) from ${r} where organization_id = ${org} and product = ${prod} and create_date >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'`],
      ["WS dedup (24 h)", (r) => `select 1 from ${r} where organization_id = ${org} and product = ${prod} and building_id = ${b} and create_date > current_timestamp - interval '24 hours'`],
      ["API dedup (24 h)", (r) => `select 1 from ${r} where organization_id = ${org} and product = ${prod} and building_id = ${b} and identifier = ${ident} and create_date > now() - interval '24 hours'`],
      ["WS /v4/usage per day, 30 days", (r) => `select date_trunc('day', create_date), count(*) from ${r} where organization_id = ${org} and create_date >= current_date - 30 group by 1`],
      ["WS /v4/usage per month, this year", (r) => `select date_trunc('month', create_date), count(*) from ${r} where organization_id = ${org} and create_date >= date_trunc('year', now()) group by 1`],
      ["WS /v4/usage all time", (r) => `select count(*) from ${r} where organization_id = ${org}`],
      ["API admin usage", (r) => `select product, count(*) from ${r} where organization_id = ${org} and create_date >= least(date_trunc('month', now()), now() - interval '30 days') group by 1`],
      ["export: orgs last month", (r) => `select distinct organization_id from ${r} where create_date >= date_trunc('month', now()) - interval '1 month' and create_date < date_trunc('month', now())`],
      ["export: one org last month", (r) => `select * from ${r} where organization_id = ${org} and create_date >= date_trunc('month', now()) - interval '1 month' and create_date < date_trunc('month', now())`],
      ["Grafana: last write, 3 days", (r) => `select max(create_date) from ${r} where create_date > now() - interval '3 days'`],
      ["Grafana: per hour per org, 7 days", (r) => `select date_trunc('hour', create_date), organization_id, count(*) from ${r} where create_date > now() - interval '7 days' group by 1, 2`],
    ];
    const timeOf = async (q: string) => {
      let best = Infinity;
      for (let i = 0; i < 3; i++) {
        const p = (await sql.unsafe(`EXPLAIN (ANALYZE, FORMAT JSON) ${q}`))[0]["QUERY PLAN"][0];
        best = Math.min(best, p["Planning Time"] + p["Execution Time"]);
      }
      return best;
    };
    say(`timing every query shape on both tables (busiest: ${busy.product} of ${busy.org}) …`);
    const table: any[] = [];
    let slower = 0;
    for (const [label, q] of shapes) {
      const o = await timeOf(q(OLD)), n = await timeOf(q(NEW));
      const bad = n > 2 * o + 20;
      if (bad) slower++;
      table.push({ query: label, hypertable_ms: o.toFixed(1), plain_ms: n.toFixed(1), flag: bad ? "SLOWER" : "" });
    }
    console.table(table);
    if (slower) await die(`${slower} query shape(s) are clearly slower on the plain table; look before swapping`);
    say(`ready to swap: ${NEW_INDEXES.length} valid indexes, 2 validated foreign keys, ${MV_NEXT} present, no query shape slower`);
  },

  async swap() {
    await expect("armed");
    const ready = await one<{ ix: number; fk: number; mv: boolean }>(`select
        (select count(*)::int from pg_index where indrelid = '${NEW}'::regclass and indisvalid) as ix,
        (select count(*)::int from pg_constraint where conrelid = '${NEW}'::regclass and contype = 'f' and convalidated) as fk,
        to_regclass('${MV_NEXT}') is not null as mv`);
    if (ready.ix !== NEW_INDEXES.length || ready.fk !== 2 || !ready.mv) await die(`not ready: ${JSON.stringify(ready)} (run index, matview, verify)`);
    const started = Date.now();
    const out = await withLock("swap", 20, async (tx) => {
      await tx.unsafe(`LOCK TABLE ${OLD}, ${NEW} IN ACCESS EXCLUSIVE MODE`);
      // (LOCK TABLE refuses materialized views, 42809; their RENAME below takes the same lock itself)
      const lockedAt = Date.now();
      // last check under the lock: the mirrored window must be identical (older months were checked by 'verify')
      // rows from 10 minutes before the arm on: everything the mirror wrote (an INSERT that waited for arm's lock
      // has a create_date seconds before armed_at); older rows were proven by 'verify'. Kept small: the lock is on.
      const win = (rel: string) => `select count(*)::text as n, ${ROWHASH}::text as h from ${rel}
          where create_date >= (select armed_at from ${STATE}) - interval '10 minutes'`;
      const o = (await tx.unsafe(win(OLD)))[0] as any, n = (await tx.unsafe(win(NEW)))[0] as any;
      if (o.n !== n.n || o.h !== n.h) throw new Error(`recent window differs: old ${o.n} rows, new ${n.n} rows (hash equal: ${o.h === n.h}) — not swapping`);
      const w = { o: o.n };
      // Only renames in here. The freeze and the old table's foreign keys go in 'detach', right after.
      // old → product_tracker_hyper_old; its indexes move aside so the names are free (constraint names are per
      // table, so the old table keeps its own; 'detach' drops its foreign keys by those names)
      await tx.unsafe(`ALTER TABLE ${OLD} RENAME TO product_tracker_hyper_old`);
      for (const [name] of INDEXES) await tx.unsafe(`ALTER INDEX application.product_tracker_${name} RENAME TO product_tracker_hyper_old_${name}`);
      // new → product_tracker, with the names the hypertable had (plus the one extra index)
      await tx.unsafe(`ALTER TABLE ${NEW} RENAME TO product_tracker`);
      for (const [name] of NEW_INDEXES) await tx.unsafe(`ALTER INDEX application.product_tracker_new_${name} RENAME TO product_tracker_${name}`);
      for (const [name] of FKS) await tx.unsafe(`ALTER TABLE ${OLD} RENAME CONSTRAINT product_tracker_new_${name} TO product_tracker_${name}`);
      await canonicalNotNulls(tx, OLD, "product_tracker");
      // the daily summary
      await tx.unsafe(`ALTER MATERIALIZED VIEW ${MV} RENAME TO product_tracker_daily_old`);
      await tx.unsafe(`ALTER INDEX data.product_tracker_daily_pkey RENAME TO product_tracker_daily_old_pkey`);
      await tx.unsafe(`ALTER MATERIALIZED VIEW ${MV_NEXT} RENAME TO product_tracker_daily`);
      await tx.unsafe(`ALTER INDEX data.product_tracker_daily_next_pkey RENAME TO product_tracker_daily_pkey`);
      await tx.unsafe(`UPDATE ${STATE} SET swapped_at = clock_timestamp()`);
      return { window: w.o, heldMs: Date.now() - lockedAt };
    }, [OLD, NEW, MV, MV_NEXT]);
    say(`SWAPPED: ${OLD} is now the plain table; locks held ${out.heldMs} ms (total incl. waiting ${Date.now() - started} ms); recent window ${out.window} rows equal`);
    say(`the mirror stays on ${HYPER_OLD}: a straggler insert there still lands in ${OLD}. Next: 'detach'`);
  },

  async detach() {
    await expect("swapped");
    await withLock("detach", 20, async (tx) => {
      await tx.unsafe(`DROP TRIGGER product_tracker_switch_frozen ON ${HYPER_OLD}`);
      for (const [name] of FKS) await tx.unsafe(`ALTER TABLE ${HYPER_OLD} DROP CONSTRAINT product_tracker_${name}`);
      await tx.unsafe(`UPDATE ${STATE} SET detached_at = clock_timestamp()`);
    }, [HYPER_OLD, "geocoder.building", "application.organization"]);
    say(`${HYPER_OLD}: freeze and foreign keys gone, so BAG updates and organization deletes no longer touch it (the mirror stays until cleanup)`);
  },

  async cleanup() {
    await expect("detached");
    const stray = await one<{ n: string }>(`select count(*)::text as n from ${HYPER_OLD} where create_date > (select swapped_at from ${STATE})`);
    say(`rows that reached the old table after the swap (each was mirrored): ${stray.n}`);
    await sql.unsafe(`DROP MATERIALIZED VIEW IF EXISTS ${MV_OLD}`);   // first: it reads the old table (2BP01 otherwise)
    await sql.unsafe(`DROP TABLE ${HYPER_OLD}`);
    await sql.unsafe(`DROP FUNCTION application.product_tracker_switch_mirror(), application.product_tracker_switch_frozen()`);
    await sql.unsafe(`DROP TABLE ${STATE}`);
    say(`old hypertable, old matview, functions and state table dropped. TimescaleDB itself is still installed (separate step).`);
  },

  async abort() {
    const s = await stage();
    if (!["prepared", "armed", "unknown"].includes(s.stage) || (await exists(HYPER_OLD))) await die(`abort is for before the swap; stage is ${s.stage}`);
    for (const t of await triggers(OLD)) await withLock("abort", 6, (tx) => tx.unsafe(`DROP TRIGGER ${t} ON ${OLD}`));
    await sql.unsafe(`DROP MATERIALIZED VIEW IF EXISTS ${MV_NEXT}`);
    await sql.unsafe(`DROP TABLE IF EXISTS ${NEW}`);
    await sql.unsafe(`DROP FUNCTION IF EXISTS application.product_tracker_switch_mirror(), application.product_tracker_switch_frozen()`);
    await sql.unsafe(`DROP TABLE IF EXISTS ${STATE}`);
    say(`aborted: ${OLD} is the untouched hypertable again`);
  },

  async rollback() {
    const s = await expect("swapped", "detached");
    await withLock("rollback", 20, async (tx) => {
      await tx.unsafe(`LOCK TABLE ${OLD}, ${HYPER_OLD} IN ACCESS EXCLUSIVE MODE`);
      // rows only the plain table has (written after the swap) go back into the hypertable
      const back = await tx.unsafe(`INSERT INTO ${HYPER_OLD} (${COLS})
          SELECT ${COLS} FROM ${OLD} WHERE create_date >= (select swapped_at from ${STATE}) - interval '1 hour'
          EXCEPT ALL
          SELECT ${COLS} FROM ${HYPER_OLD} WHERE create_date >= (select swapped_at from ${STATE}) - interval '1 hour'`);
      for (const t of await triggers(HYPER_OLD)) await tx.unsafe(`DROP TRIGGER ${t} ON ${HYPER_OLD}`);
      await tx.unsafe(`ALTER TABLE ${OLD} RENAME TO product_tracker_new`);
      for (const [name] of NEW_INDEXES) await tx.unsafe(`ALTER INDEX application.product_tracker_${name} RENAME TO product_tracker_new_${name}`);
      await tx.unsafe(`ALTER TABLE ${HYPER_OLD} RENAME TO product_tracker`);
      for (const [name] of INDEXES) await tx.unsafe(`ALTER INDEX application.product_tracker_hyper_old_${name} RENAME TO product_tracker_${name}`);
      // 'swapped': the hypertable still has its foreign keys under their own names; 'detached': add them back
      if (s.stage === "detached") {
        for (const [name, def] of FKS) await tx.unsafe(`ALTER TABLE ${OLD} ADD CONSTRAINT product_tracker_${name} ${def} NOT VALID`);
      }
      await tx.unsafe(`ALTER MATERIALIZED VIEW ${MV} RENAME TO product_tracker_daily_next`);
      await tx.unsafe(`ALTER INDEX data.product_tracker_daily_pkey RENAME TO product_tracker_daily_next_pkey`);
      await tx.unsafe(`ALTER MATERIALIZED VIEW ${MV_OLD} RENAME TO product_tracker_daily`);
      await tx.unsafe(`ALTER INDEX data.product_tracker_daily_old_pkey RENAME TO product_tracker_daily_pkey`);
      say(`rolled back: ${back.count} row(s) copied back; ${OLD} is the hypertable again`);
    });
    if (s.stage === "detached") for (const [name] of FKS) await sql.unsafe(`ALTER TABLE ${OLD} VALIDATE CONSTRAINT product_tracker_${name}`);
    await sql.unsafe(`DROP MATERIALIZED VIEW IF EXISTS data.product_tracker_daily_next`);
    await sql.unsafe(`DROP TABLE ${NEW}`);
    await sql.unsafe(`DROP FUNCTION application.product_tracker_switch_mirror(), application.product_tracker_switch_frozen()`);
    await sql.unsafe(`DROP TABLE ${STATE}`);
    say(`the plain copy, functions and state are gone`);
  },
};

const step = process.argv[2];
if (!step || !steps[step]) { console.error(`usage: bun switch.ts <${Object.keys(steps).join("|")}>`); process.exit(2); }
try {
  // postgres.js drops a numeric 0 startup parameter (found in the rehearsal): check what the session really has
  const st = (await one<{ statement_timeout: string }>(`show statement_timeout`)).statement_timeout;
  if (st !== "0") await die(`this session has statement_timeout ${st}; the long steps need 0`);
  await steps[step]();
} catch (e: any) { console.error(`STOP: ${step}: ${e.message}${e.code ? ` (${e.code})` : ""}`); await sql.end(); process.exit(1); }
await sql.end();
