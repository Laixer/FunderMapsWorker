// After a rehearsal run: every insert the database confirmed (out/<run-id>.ids) must be in
// application.product_tracker exactly once. Also reports rows that only reached the old hypertable.
//   DATABASE_URL=… bun check.ts <run-id>
import postgres from "postgres";
import { readFileSync } from "node:fs";

const runId = process.argv[2];
if (!runId) { console.error("usage: bun check.ts <run-id>"); process.exit(2); }
const ids = readFileSync(`out/${runId}.ids`, "utf8").split("\n").filter(Boolean);
const sql = postgres(process.env.DATABASE_URL!, { max: 1 });

await sql`create temp table expected (identifier text primary key)`;
for (let i = 0; i < ids.length; i += 5000) {
  const chunk = ids.slice(i, i + 5000).map((identifier) => ({ identifier }));
  await sql`insert into expected ${sql(chunk)}`;
}
const [r] = await sql`
  with got as (select identifier, count(*) as n from application.product_tracker
                where identifier like ${"gen-" + runId + "-%"} group by 1)
  select (select count(*) from expected)::int as confirmed,
         (select count(*) from expected e left join got g using (identifier) where g.identifier is null)::int as missing,
         (select count(*) from got where n > 1)::int as duplicated,
         (select count(*) from got g left join expected e using (identifier) where e.identifier is null)::int as unexpected`;
console.log(`run ${runId}: confirmed inserts ${r.confirmed}, missing ${r.missing}, duplicated ${r.duplicated}, unexpected ${r.unexpected}`);
const hyperOld = (await sql`select to_regclass('application.product_tracker_hyper_old') is not null as e`)[0].e;
if (hyperOld) {
  const [s] = await sql`select count(*)::int as n from application.product_tracker_hyper_old where identifier like ${"gen-" + runId + "-%"}`;
  console.log(`   of these, also present in the old hypertable: ${s.n} (rows written before the swap, or stragglers)`);
}
await sql.end();
process.exit(r.missing || r.duplicated || r.unexpected ? 1 : 0);
