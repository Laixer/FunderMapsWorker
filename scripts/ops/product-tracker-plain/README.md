# product_tracker: from TimescaleDB hypertable to a plain table, online

`application.product_tracker` is the usage log the bills are made from. Since 2021 it has been a TimescaleDB
hypertable (30-day chunks, ~31M rows, ~8.7 GB). Nothing uses a TimescaleDB feature on it, and TimescaleDB is in the
way of the move to Scaleway (an older version there) and of a simpler usage counter (Webservice #16). This folder
converts it to a plain table **while the Webservice and the API keep writing to it**. FunderMaps 5.0, loose end L5.

## How

```
prepare   an empty plain copy, product_tracker_new, with the same columns, defaults, NOT NULLs, owner and grants
arm       hold inserts for ~0.1 s, switch on two triggers on the hypertable and take a snapshot of that moment:
            mirror  every new row is also written into the copy
            freeze  UPDATE and DELETE fail (nothing does either; an organization delete would cascade)
          then copy every row of the snapshot into the copy, one week per statement with a short pause.
          Rows before the snapshot come from the copy, rows after it from the mirror: none twice, none missed.
index     the 3 indexes the hypertable has + 1 new one (organization_id, product, create_date), built
          concurrently; the 2 foreign keys added NOT VALID, then validated
matview   data.product_tracker_daily rebuilt on the copy (as …_next), same index, owner and grants
verify    read-only: every month equal in count and hash; every production query shape timed on both tables
swap      one transaction, only renames: the hypertable becomes product_tracker_hyper_old, the copy becomes
          product_tracker (with the original index and constraint names), the summaries swap the same way.
          The mirror stays on the old table: an INSERT that still reaches it lands in the plain table too.
detach    the freeze and the old table's foreign keys go, so cascades no longer touch it
cleanup   days later: drop the old hypertable, the old summary, the functions and the state table
abort     before the swap: back to exactly the start
rollback  after the swap: rows written since are copied back, the names swap back
```

Every step checks the live state first and refuses if it is not the expected one; every lock is requested with a
1 s timeout and retried, and only when no transaction older than 1 s touches the table. That matters because the
Webservice waits for its INSERT before it answers and neither service sets a lock timeout: any lock we queue for is
customer latency.

## What customers notice

In the rehearsal nothing lasted longer than half a second; on prod the swap held its locks 1.4 s, at an hour with
almost no traffic (see "On prod" below). Measured in the rehearsal, under 10× production's busiest minute
(20 inserts and 10 rate-limit reads a second, through PgBouncer in transaction mode with prepared statements):

| step | inserts held / slowest request | duration on 12M rows → prod's 31M |
|---|---|---|
| arm | held 54–97 ms | copy 103 s → ~4.5 min, slowest request during the copy 244 ms |
| index | — | 200 s → ~8.5 min |
| swap | locks held 332–385 ms, slowest request 342–392 ms | — |
| detach | slowest request 362 ms | — |
| rollback | slowest request ~1.1 s | — |

A first try copied in one statement: every other query stalled ~5 s (write pressure, not locks), hence the batches.

## What the rehearsal proved

The whole path at 12M rows with prod's shape (61 monthly chunks, same indexes, constraint names, grants, summary
view), TimescaleDB 2.28.2 on PostgreSQL 18, traffic running throughout. (A full-size copy of 31M rows ran in
batches for 3 minutes, latency as in the table, until the rehearsal machine's disk filled; prod has the room.)

- **No insert lost or doubled**: 23,797 inserts across 6 runs, each checked to exist exactly once afterwards,
  through a failed copy + abort, a resume mid-way, the swap, a rollback and a cleanup.
- **The mirror catches what it must**: a row in a month that had no chunk yet (TimescaleDB made a new one) was
  mirrored; a real straggler INSERT reached the old table during a swap and landed in the plain table.
- **The freeze holds**: UPDATE and DELETE fail; an organization delete is refused and changes nothing.
- **Verify is exact**: all 61 months equal in count and hash (12,019,500 rows).
- **No query gets slower**: rate limit 17.2 → 1.5 ms, Webservice dedup 13.1 → 0.6 ms, usage and export 1.5–5×
  faster, the rest equal.
- **The end state is right**: a plain table with the 4 indexes, 2 validated foreign keys, the original grants and
  NOT NULL names; the summary reads it; no leftovers; and TimescaleDB itself can then be dropped.
- Bugs it caught before prod: postgres.js drops a numeric `0` startup parameter (`statement_timeout`), a
  serialization error when the copy updated the state row, `LOCK TABLE` refusing materialized views, and the
  cleanup order. All fixed.

## Running it on prod

`DATABASE_URL` = doadmin, **direct** (port 25060, not the PgBouncer pools: the steps need session features), then
`bun switch.ts <step>` in this folder, one step at a time: `status`, `prepare`, `arm`, `index`, `matview`, `verify`,
`swap`, `detach` — and `cleanup` days later.

- Not during the model refresh (12:30 and 21:00 Amsterdam, ~50 min), the monthly export (1st, 02:30) or a
  DigitalOcean maintenance window.
- From `prepare` to `detach`: no BAG load and no organization deletes (they fail on purpose).
- Disk: the copy needs ~10 GB extra until `cleanup` (the database has room).

Afterwards, in this order: the migration that records the end state (it refuses while the table is a hypertable,
so it is merged after the swap); `cleanup`; `DROP EXTENSION timescaledb` (its owner on DO is `postgres`, so this may
need DigitalOcean); then a `schema.sql` regen.

## On prod, 2026-10-15

| step | result |
|---|---|
| arm | inserts held 20 ms; copy of 31,045,532 rows in 151 s, equal to the snapshot |
| index | 4 indexes + 2 validated foreign keys in 375 s |
| verify | 60 months equal (31,045,537 rows, count and hash) |
| swap (01:24 Amsterdam) | locks held 1.4 s (0.35 s in the rehearsal); ~1 insert per 2.5 min at that hour, so likely no request waited |
| after | plain table, 4 indexes, 2 validated foreign keys, grants and summary as before; the Webservice's INSERT as its own role lands in it (tested in a rolled-back transaction) |

Lesson: run `verify` after autovacuum has visited the new table. The first `verify` ran while the copy had no
visibility map yet, so the counting queries could not use index-only scans and four shapes looked up to 1.4× slower;
after autovacuum (minutes later) every shape was equal or faster (rate limit 107 → 58 ms, dedup 3.5 → 0.1 ms,
usage 1.5–2× faster). A `VACUUM (ANALYZE)` at the end of `index` would make that explicit.

## Rehearsing again

```
docker run -d --name l5-rehearsal --network l5net -e POSTGRES_PASSWORD=rehearsal -e POSTGRES_DB=fundermaps \
  -p 127.0.0.1:55433:5432 timescale/timescaledb:2.28.2-pg18 -c max_wal_size=2GB -c statement_timeout=60000
docker exec -i l5-rehearsal psql -U postgres -d fundermaps < rehearsal/build.sql      # 12M rows, ~10 min
docker run -d --name l5-pgbouncer --network l5net -p 127.0.0.1:56432:6432 \
  -v $PWD/rehearsal/pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro -v $PWD/rehearsal/userlist.txt:/etc/pgbouncer/userlist.txt:ro \
  edoburu/pgbouncer:latest
bash rehearsal/rehearse.sh run1 prepare arm edge:future edge:freeze index matview verify swap edge:straggler detach cleanup
```
(The passwords in `rehearsal/` are for the throwaway containers only.)
