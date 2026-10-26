# sql/migrate/

**Legacy.** Since 2026-09-17 new migrations go to `db/migrations/` and are applied
with `bun run migrate`, which keeps a ledger (see `db/migrations/README.md`). The
files here are the pre-ledger history: hand-applied on prod, not replayed.

One-shot, hand-applied schema/data migrations. The worker does **not** auto-apply
these — they're run manually against the target database with `psql`:

```bash
psql "$DB_URL" -f sql/migrate/<file>.sql
```

## Convention

- **`schema.sql` (repo root) is the source of truth for the current structure.**
  A fresh database is bootstrapped from `schema.sql` + `sql/init/` + `sql/model/`
  + `sql/load/` — never by replaying this directory.
- A migration lands here, gets applied to prod, and is regenerated into
  `schema.sql` (`pg_dump`). **Once it's baked into `schema.sql` it's pruned from
  this directory.** The full SQL of every past migration stays in git history:

  ```bash
  git log --all --diff-filter=D -- 'sql/migrate/*.sql'   # find a pruned migration
  git show <commit>:sql/migrate/<file>.sql               # read its contents
  ```

Since 2026-09-17 nothing lands here any more (new migrations go to `db/migrations/`),
so the directory stays empty. Prune rounds: 2026-05-21; the Better Auth 1.7 pair on
2026-09-03; the last 77 files (applied 2026-05-21 → 2026-09-17, all in `schema.sql`)
on 2026-10-26. Comments elsewhere that name a `sql/migrate/<file>.sql` point at that
history: find it with the `git log` line above.
