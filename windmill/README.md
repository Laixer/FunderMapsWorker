# Windmill workspace mirror

Git mirror of the Windmill workspace `fundermaps` (https://windmill.fundermaps.com/),
pulled with the Windmill CLI. This is the source of truth for reviewing changes to
scripts, flows and schedules; the workspace itself is still edited in the Windmill UI.

Layout follows the Windmill CLI convention: `f/fundermaps/<folder>/<name>.{ts,py,pg.sql}`
with a `.script.yaml` (metadata + schema) and a `.script.lock` (resolved dependencies) per
script, `*.flow/flow.yaml` per flow, and `*.schedule.yaml` per schedule. Resources,
variables and secrets are NOT pulled (`skip*` in `wmill.yaml`); scripts reference them as
`$res:` / `$var:` paths only.

## Refresh

```sh
bun install -g windmill-cli@<backend version>   # match `curl https://windmill.fundermaps.com/api/version`
cd windmill
wmill workspace add fundermaps fundermaps https://windmill.fundermaps.com/   # once, token from the UI
wmill sync pull --yes
```

Push in the other direction (`wmill sync push`) is deliberate and manual; nothing in CI
pushes to the workspace.
