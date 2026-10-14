// Rehearsal traffic: writes and reads like the Webservice and the API, through long-lived pooled connections
// with prepared statements (postgres.js default), so cached plans cross the swap like they will on prod.
//
//   DATABASE_URL_WS=… DATABASE_URL_API=… bun load.ts <run-id> <seconds> [inserts-per-second] [reads-per-second]
//
// Every insert carries a unique identifier; the ones the database confirms (1 row) are appended to
// out/<run-id>.ids. Per second it prints how many inserts/reads succeeded, failed, and the slowest of each.
import postgres from "postgres";
import { appendFileSync, mkdirSync, existsSync } from "node:fs";

const [runId, secondsArg, ipsArg = "20", rpsArg = "10"] = process.argv.slice(2);
if (!runId || !secondsArg) { console.error("usage: bun load.ts <run-id> <seconds> [ips] [rps]"); process.exit(2); }
const seconds = Number(secondsArg), ips = Number(ipsArg), rps = Number(rpsArg);
mkdirSync("out", { recursive: true });
const idsFile = `out/${runId}.ids`, errFile = `out/${runId}.errors`;

// Like the services: a pool per service, prepared statements on, statement_timeout from the role.
const ws = postgres(process.env.DATABASE_URL_WS!, { max: 10, idle_timeout: 0, connection: { application_name: "load-ws" } });
const api = postgres(process.env.DATABASE_URL_API!, { max: 5, idle_timeout: 0, connection: { application_name: "load-api" } });

const orgs = Array.from({ length: 60 }, (_, i) => new Bun.CryptoHasher("md5").update(`org${i + 1}`).digest("hex").replace(/(.{8})(.{4})(.{4})(.{4})(.{12})/, "$1-$2-$3-$4-$5"));
const products = ["analysis3", "risk3", "light3", "statistics3", "facade_scan4"];
const pick = <T>(a: T[]) => a[Math.floor(Math.random() * a.length)];
const building = () => "NL.IMBAG.PAND." + String(1 + Math.floor(Math.random() * 2_000_000)).padStart(16, "0");

let seq = 0;
const sec = { ins: 0, insErr: 0, insMax: 0, rd: 0, rdErr: 0, rdMax: 0 };
const total = { ins: 0, insErr: 0, rd: 0, rdErr: 0, insMax: 0, rdMax: 0 };

async function insertWs() {
  const id = `gen-${runId}-ws-${++seq}`, org = pick(orgs), product = pick(products), b = building();
  const t = performance.now();
  try {
    // Webservice shape: 24 h dedup on (org, product, pand); create_date from the column default
    const r = await ws`insert into application.product_tracker (organization_id, product, building_id, identifier)
      select ${org}, ${product}, ${b}, ${id}
      where not exists (select 1 from application.product_tracker
                         where organization_id = ${org} and product = ${product} and building_id = ${b}
                           and create_date > now() - interval '24 hours')`;
    if (r.count === 1) appendFileSync(idsFile, id + "\n");
    sec.ins++;
  } catch (e: any) { sec.insErr++; appendFileSync(errFile, `${new Date().toISOString()} ws-insert ${id} ${e.code ?? ""} ${e.message}\n`); }
  const ms = performance.now() - t; sec.insMax = Math.max(sec.insMax, ms);
}
async function insertApi() {
  const id = `gen-${runId}-api-${++seq}`, org = pick(orgs), b = building();
  const t = performance.now();
  try {
    // API shape: dedup includes the identifier (the user)
    const r = await api`insert into application.product_tracker (organization_id, product, building_id, identifier)
      select ${org}, 'analysis', ${b}, ${id}
      where not exists (select 1 from application.product_tracker
                         where organization_id = ${org} and product = 'analysis' and building_id = ${b} and identifier = ${id}
                           and create_date > now() - interval '24 hours')`;
    if (r.count === 1) appendFileSync(idsFile, id + "\n");
    sec.ins++;
  } catch (e: any) { sec.insErr++; appendFileSync(errFile, `${new Date().toISOString()} api-insert ${id} ${e.code ?? ""} ${e.message}\n`); }
  const ms = performance.now() - t; sec.insMax = Math.max(sec.insMax, ms);
}
async function readRateLimit() {
  const t = performance.now();
  try {
    // Webservice rate limit: calls of (org, product) since the start of the UTC month
    await ws`select count(*) from application.product_tracker
              where organization_id = ${pick(orgs)} and product = ${pick(products)}
                and create_date >= date_trunc('month', now() at time zone 'utc') at time zone 'utc'`;
    sec.rd++;
  } catch (e: any) { sec.rdErr++; appendFileSync(errFile, `${new Date().toISOString()} read ${e.code ?? ""} ${e.message}\n`); }
  const ms = performance.now() - t; sec.rdMax = Math.max(sec.rdMax, ms);
}

const stopAt = Date.now() + seconds * 1000;
const pending = new Set<Promise<void>>();
const fire = (p: Promise<void>) => { pending.add(p); p.finally(() => pending.delete(p)); };
const tick = setInterval(() => {
  const line = `${new Date().toISOString().slice(11, 19)} ins ${String(sec.ins).padStart(3)} err ${sec.insErr} max ${sec.insMax.toFixed(0).padStart(5)} ms | read ${String(sec.rd).padStart(3)} err ${sec.rdErr} max ${sec.rdMax.toFixed(0).padStart(5)} ms | in flight ${pending.size}`;
  console.log(line);
  total.ins += sec.ins; total.insErr += sec.insErr; total.rd += sec.rd; total.rdErr += sec.rdErr;
  total.insMax = Math.max(total.insMax, sec.insMax); total.rdMax = Math.max(total.rdMax, sec.rdMax);
  Object.assign(sec, { ins: 0, insErr: 0, insMax: 0, rd: 0, rdErr: 0, rdMax: 0 });
}, 1000);
const insTimer = setInterval(() => { if (Date.now() < stopAt && !existsSync(`out/${runId}.stop`)) fire(Math.random() < 0.8 ? insertWs() : insertApi()); }, 1000 / ips);
const rdTimer = setInterval(() => { if (Date.now() < stopAt && !existsSync(`out/${runId}.stop`)) fire(readRateLimit()); }, 1000 / rps);

while (Date.now() < stopAt && !existsSync(`out/${runId}.stop`)) await Bun.sleep(250);
clearInterval(insTimer); clearInterval(rdTimer);
await Promise.allSettled([...pending]);
await Bun.sleep(1100); clearInterval(tick);
console.log(`DONE run ${runId}: inserts ok ${total.ins} (failed ${total.insErr}, slowest ${total.insMax.toFixed(0)} ms), reads ok ${total.rd} (failed ${total.rdErr}, slowest ${total.rdMax.toFixed(0)} ms)`);
await ws.end(); await api.end();
