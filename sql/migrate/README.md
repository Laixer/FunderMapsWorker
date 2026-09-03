# sql/migrate/

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

So this directory holds only migrations **not yet folded into `schema.sql`** —
usually empty between cleanup rounds. The applied history was last pruned
2026-05-21 (see git log for the file list); the Better Auth 1.7 pair was pruned
2026-09-03 together with the first PG 18 regeneration of `schema.sql`.
