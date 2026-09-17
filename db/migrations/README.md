# db/migrations/

Ledger-tracked schema migrations. `bun run migrate` applies what the database
has not seen yet and records it in `application.schema_migrations`.

```bash
DATABASE_URL=postgres://... bun run migrate --dry-run     # show the plan
DATABASE_URL=postgres://... bun run migrate               # apply
DATABASE_URL=postgres://... bun run migrate --status      # ledger vs files
```

## A migration

- File name `<YYYYMMDD>_<NNN>_<snake_name>.sql`, e.g. `20260917_001_reviewer_extraction_unique.sql`.
  The prefix is the version; it sorts chronologically and must be unique.
- Forward only. There is no down file: a mistake is undone by the next migration.
- One transaction per file: everything applies or nothing does, and the ledger
  row commits with it. A file whose first lines carry `-- migrate: no-transaction`
  runs outside a transaction instead (for `CREATE INDEX CONCURRENTLY`); such a
  file must be idempotent, because a failure half-way is retried by rerunning.
- Plain SQL, the way `sql/migrate/` always was. Grants belong in the migration
  that creates or widens the object they grant; the runner runs as the object
  owner (`doadmin` on prod), so `GRANT` works as written.
- Applied means frozen. The runner stores the file's sha256 and refuses to run
  when an applied file differs from disk. Need a change? Write a new file.
- Start every file with a comment saying why, and what was true on prod when
  it was written.

## How prod and a fresh database stay in step

`schema.sql` is the prod dump and still the way a fresh database is
bootstrapped (`scripts/init_db.sh`). `BASELINE` holds the version of the last
migration that `schema.sql` already contains. On a database bootstrapped from
`schema.sql`, the runner *stamps* every migration at or below `BASELINE`
(ledger row, nothing executed) and applies the rest. On prod the ledger is the
truth and `BASELINE` is irrelevant.

So the loop for a schema change is:

1. Add `db/migrations/<version>_<name>.sql`. Open the PR. CI bootstraps
   `schema.sql` on PostGIS 18 and runs `bun run migrate` on top: the migration
   must apply cleanly on the current schema.
2. Merge. Apply on prod from this VM, as doadmin:
   `DATABASE_URL=postgres://doadmin:...@private-db-pg-ams3-0-....:25060/fundermaps?sslmode=require bun run migrate --allow-prod`
3. Regenerate `schema.sql` (recipe in `docs/risk-model.md`), set `BASELINE` to
   the version you just applied, commit both. From then on a fresh database gets
   that change from `schema.sql` and the runner stamps the file instead of
   re-running it. Files at or below `BASELINE` can be deleted once they are
   older than the last prod restore you would ever roll back to; the ledger
   keeps reporting them as "no file", which is fine.

## Where the old migrations went

`sql/migrate/` holds the pre-ledger, hand-applied files (all applied on prod,
most already folded into `schema.sql`). They stay as history and are not
replayed. New migrations go here.
