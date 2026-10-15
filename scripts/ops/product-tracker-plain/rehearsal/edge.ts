// Rehearsal-only edge tests, run between the steps of switch.ts.  DATABASE_URL=… bun edge.ts <test>
//   future     (armed)   a row in a month without a chunk yet → TimescaleDB makes a new chunk; it must be mirrored
//   freeze     (armed)   UPDATE on the old table and an organization delete (cascade) must fail, changing nothing
//   straggler  (swapped) an INSERT that still reaches the old hypertable must land in the plain table
import postgres from "postgres";

const sql = postgres(process.env.DATABASE_URL!, { max: 1, onnotice: () => {} });
const ws = postgres(process.env.DATABASE_URL!.replace("postgres:rehearsal@", "fundermaps_webservice:ws@"), { max: 1 });
const ok = (s: string) => console.log(`   EDGE OK   ${s}`);
const bad = async (s: string) => { console.log(`   EDGE FAIL ${s}`); await sql.end(); await ws.end(); process.exit(1); };
const org = (await sql`select id::text from application.organization order by id limit 1`)[0].id;
const bld = (await sql`select external_id::text as b from geocoder.building order by id limit 1`)[0].b;
const tag = `edge-${Date.now()}`;

const tests: Record<string, () => Promise<void>> = {
  async future() {
    const before = (await sql`select count(*)::int as n from timescaledb_information.chunks where hypertable_name = 'product_tracker'`)[0].n;
    await ws`insert into application.product_tracker (organization_id, product, building_id, create_date, identifier)
             values (${org}, 'analysis3', ${bld}, '2027-03-15 12:00+00', ${tag + "-future"})`;
    const after = (await sql`select count(*)::int as n from timescaledb_information.chunks where hypertable_name = 'product_tracker'`)[0].n;
    const mirrored = (await sql`select count(*)::int as n from application.product_tracker_new where identifier = ${tag + "-future"}`)[0].n;
    if (after !== before + 1) await bad(`expected a new chunk (${before} → ${after})`);
    if (mirrored !== 1) await bad(`row in a brand-new chunk was mirrored ${mirrored} times`);
    ok(`a row in a new chunk (${before} → ${after} chunks) was mirrored once`);
    // keep the tables equal but out of the real data: remove it from both under the freeze's nose is not possible
    // (DELETE is blocked); it stays in both and is ignored by verify (future month) and equal in the swap window.
  },
  async freeze() {
    // a row trigger only fires for rows that match: update one specific, existing row
    // A unique traffic row (identifier gen-…). Not by timestamp: postgres.js passes timestamps through a JS Date,
    // which drops the microseconds, and then the UPDATE matches nothing (that sank the first two attempts).
    const row = (await sql`select identifier from application.product_tracker where identifier like 'gen-%' limit 1`)[0];
    const hit = (await sql`select count(*)::int as n from application.product_tracker where identifier = ${row.identifier}`)[0].n;
    if (hit !== 1) await bad(`test row ${row.identifier} found ${hit} times; the test would prove nothing`);
    try { await sql`update application.product_tracker set product = product where identifier = ${row.identifier}`; await bad("UPDATE on the old table was not blocked"); }
    catch (e: any) { if (e.code !== "55000") await bad(`UPDATE failed with an unexpected error: ${e.code} ${e.message}`); ok(`UPDATE blocked (${e.code}): ${e.message.slice(0, 70)}…`); }
    const victim = (await sql`select organization_id::text as o from application.product_tracker where create_date > now() - interval '30 days' limit 1`)[0].o;
    const rows = async () => Number((await sql`select count(*) as n from application.product_tracker where organization_id = ${victim}`)[0].n);
    const n0 = await rows();
    try { await sql`delete from application.organization where id = ${victim}`; await bad("organization delete went through during the switch"); }
    catch (e: any) {
      const still = (await sql`select count(*)::int as n from application.organization where id = ${victim}`)[0].n;
      if (still !== 1 || (await rows()) !== n0) await bad("organization delete failed but changed something");
      ok(`organization delete refused (${e.code}), organization and its ${n0} rows unchanged`);
    }
  },
  async straggler() {
    await ws`insert into application.product_tracker_hyper_old (organization_id, product, building_id, identifier)
             values (${org}, 'analysis3', ${bld}, ${tag + "-straggler"})`;
    const plain = (await sql`select count(*)::int as n from application.product_tracker where identifier = ${tag + "-straggler"}`)[0].n;
    if (plain !== 1) await bad(`a straggler insert into the old hypertable reached the plain table ${plain} times`);
    ok("a straggler insert into the old hypertable landed in the plain table once");
  },
};
const t = process.argv[2];
if (!t || !tests[t]) { console.error(`usage: bun edge.ts <${Object.keys(tests).join("|")}>`); process.exit(2); }
await tests[t]();
await sql.end(); await ws.end();
