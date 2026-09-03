# Hostname-bound configuration inventory (v5 prep)

Snapshot **2026-09-03**. Every place a hostname is pinned, so the v5 hosting move
(DigitalOcean → Scaleway, internal apps → `*.funderdata.nl`) can be scripted instead
of discovered. Sources: `doctl apps spec get` for all 15 apps, `doctl compute domain
records list` for all 7 zones, `get_bucket_cors` on all 5 Spaces buckets,
`application.oauth_application` on prod, Windmill settings/resources, and a grep of
every repo under `~/src` (76 literal hits, list at the end).

**Rule of thumb:** the SPAs are hostname-agnostic (`window.location.origin` everywhere),
so a frontend move is *only* DNS + App Platform domain + the three server-side allowlists
(OIDC `redirect_uris`, API `TRUSTED_ORIGINS`/ingress CORS, Spaces CORS). The API and the
tile server are the two things with their **own** hostname baked into other components.

## 1. Public hostnames → what serves them

| hostname | DNS (zone fundermaps.com unless noted) | App Platform app | component | repo |
|---|---|---|---|---|
| fundermaps.com, www, fundermaps.nl, www.fundermaps.nl | A/AAAA @ → DO edge (172.66.0.96 / 162.159.140.98), www CNAME → fundermaps-pages-74uho | fundermaps-pages | static | FunderMapsPages |
| **api.fundermaps.com** | CNAME → fundermaps-api-test-grcaa | fundermaps-api-prod | service :8080, ingress `/api` | FunderMapsApi |
| **ws.fundermaps.com** | CNAME → fundermaps-webservice-prod-dti3d | fundermaps-webservice-prod | service :8080, ingress `/v4` only | FunderMapsWebservice |
| ws-staging.fundermaps.com | CNAME → fundermaps-webservice-staging-aordk | fundermaps-webservice-staging | service, ingress `/v4` | FunderMapsWebservice |
| **tiles.fundermaps.com** | CNAME → fundermaps-tileserver-test-72oja | fundermaps-tileserver-prod | service :3000 (Martin, `tileserver/Dockerfile`) | FunderMapsWorker |
| auth.fundermaps.com | CNAME → fundermaps-auth-test-7e3bf | fundermaps-auth-test | static | FunderMapsAuth |
| maps.fundermaps.com, funderingskaart.nl (+www), funderingsrisicokaart.nl (+www) | CNAME → fundermaps-maps-prod-oizh4; apex A/AAAA → DO edge | fundermaps-maps-prod | static | FunderMapsWebFront |
| studio.fundermaps.com (primary), app.fundermaps.com | CNAME → fundermaps-app-prod-3oyrr | fundermaps-app-prod | static | FunderMapsClientApp |
| admin.fundermaps.com | CNAME → sea-turtle-app-33ode | fundermaps-admin-prod | static, ingress cors allow_credentials | FundermapsManagementFront |
| report.fundermaps.com | CNAME → whale-app-nm9uv | fundermaps-report-prod | static | FunderMapsReport |
| melden.fundermaps.com | CNAME → fundermaps-intake-prod-rkedq | fundermaps-intake-prod | service :8080 (Nuxt/Nitro) | FunderMapsIntake |
| windmill.fundermaps.com | CNAME → fundermaps-windmill-test-tzi63 | fundermaps-windmill-prod | image windmill :8000 | — |
| analytics.fundermaps.com | CNAME → grafana-app-prod-vnp86 | fundermaps-analytics-prod | image grafana :3000 | — |
| *(none)* | — | fundermaps-docgen | image gotenberg :3000, reached as `orca-app-wxi4e.ondigitalocean.app` | — |
| laixer.nl (primary), laixer.com, www.* | www CNAME → laixer-salespage-test-p73c4; apex A/AAAA → DO edge | laixer-pages | static (build broken) | LaixerSalesPage |

Default `*.ondigitalocean.app` hostnames that are **referenced by config** (they die with
the DO apps): `whale-app-nm9uv` (Report; used as `REPORT_RENDER_URL` by the API and in
tileset CORS), `orca-app-wxi4e` (Gotenberg; `GOTENBERG_URL`), `fundermaps-intake-prod-rkedq`
(Spaces CORS on bucket `fundermaps`), `fundermaps-api-test-grcaa` (only in `.env.example`
files and `WebFront/index.html` preconnect).

Non-web DNS in the same zones (must be re-created wherever DNS ends up): Microsoft 365 mail
for fundermaps.com / laixer.com / laixer.nl (MX, SPF, DKIM selector1/2, autodiscover, DMARC
p=reject), CAA letsencrypt.org on fundermaps.com/.nl/laixer.com, 1Password + MS + Google
verification TXTs. **funderdata.nl** carries only Resend (DKIM `resend._domainkey`, `send`
and `rsend` CNAMEs → forge.rmta.net, MX → inbound-smtp.eu-west-1.amazonaws.com, DMARC p=none).

External monitor: DO Uptime check `ws-prod /v4/health` → https://ws.fundermaps.com/v4/health
(only external availability check in the estate).

## 2. Server-side allowlists (the three that break logins/uploads when a hostname moves)

### 2a. OIDC clients — `application.oauth_application` (prod)

| client_id | redirect_uris | post_logout_redirect_uris |
|---|---|---|
| webfront | https://maps.fundermaps.com/auth/callback | https://maps.fundermaps.com/ |
| clientapp | https://app.fundermaps.com/auth/callback, https://studio.fundermaps.com/auth/callback | https://app.fundermaps.com/login, https://studio.fundermaps.com/login |
| managementfront | https://admin.fundermaps.com/auth/callback | https://admin.fundermaps.com/login |
| grafana | https://analytics.fundermaps.com/login/generic_oauth | — |

The SPAs build `redirect_uri` from `window.location.origin` (`src/services/oidc.ts` in all
three), so a new hostname needs only a new row entry here. Registration SQL for the current
rows: `sql/migrate/register_*_oidc_client.sql`, `add_studio_origin_clientapp.sql`,
`enable_clientapp_end_session.sql` (git history). Note the funderingskaart.nl /
funderingsrisicokaart.nl aliases of maps are **not** registered → login only works on
maps.fundermaps.com.

### 2b. API origin allowlists — fundermaps-api-prod

- `TRUSTED_ORIGINS` (env, Better Auth CSRF allowlist **and** the credentialed CORS in
  `src/index.ts`): `https://admin.fundermaps.com, https://app.fundermaps.com,
  https://studio.fundermaps.com, https://maps.fundermaps.com, https://auth.fundermaps.com,
  https://api.fundermaps.com`
- App Platform ingress CORS on `/api`: the same six origins, `allow_credentials`, methods
  GET/POST/PUT/OPTIONS/PATCH/DELETE — a second copy of the list that must be kept in sync.
- `BASE_URL=https://api.fundermaps.com` (Better Auth issuer/base; cookies are host-only on
  this host — no `crossSubDomainCookies`, so a `*.funderdata.nl` frontend + fundermaps.com
  API cannot share a cookie; see the open design call in the 5.0 plan).
- `LOGIN_PAGE_URL` default `https://auth.fundermaps.com/login` (config.ts), `consentPage`
  hard-coded `https://admin.fundermaps.com/oauth/consent` (auth.ts; never reached).
- Defaults in `src/config.ts` that are hostnames: `STUDIO_URL=https://studio.fundermaps.com`
  (links in report e-mails), `INTAKE_URL=https://melden.fundermaps.com` (links in melder
  e-mails), `REPORT_RENDER_URL=https://whale-app-nm9uv.ondigitalocean.app` (what Gotenberg
  renders), `MAIL_FROM` / `INTAKE_REPLY_TO` on `funderdata.nl`.
- Prod env values that are hostnames: `GOTENBERG_URL=https://orca-app-wxi4e.ondigitalocean.app`,
  `S3_ENDPOINT=https://ams3.digitaloceanspaces.com`, `S3_BUCKET=fundermaps`,
  `DATABASE_URL` via App Platform bindable `${db-pg-ams3-0.HOSTNAME}:25061/api-pool`.

### 2c. Spaces CORS (bucket → allowed origins)

| bucket | methods | origins |
|---|---|---|
| fundermaps | PUT (content-type) | https://melden.fundermaps.com, https://fundermaps-intake-prod-rkedq.ondigitalocean.app |
| fundermaps-development | PUT | http://localhost:3000, http://localhost:4321 |
| fundermaps-tileset | GET, HEAD | https://maps.fundermaps.com, https://app.fundermaps.com, https://report.fundermaps.com, https://funderingskaart.nl, https://funderingsrisicokaart.nl, https://whale-app-nm9uv.ondigitalocean.app, https://fundermaps-development.ams3.digitaloceanspaces.com |
| fundermaps-data, fundermaps-archive | none | — |

The tileset CORS is largely legacy (static tiles are purged; Martin serves them), but
`VITE_FUNDERMAPS_TILES_URL` still points at the bucket in maps-prod and report-prod.

## 3. Frontend build-time URLs (`VITE_*`, baked into the bundle at build)

| app | var | prod value |
|---|---|---|
| admin, auth, studio/app, report | `VITE_FUNDERMAPS_URL` | https://api.fundermaps.com |
| maps | `VITE_FUNDERMAPS_URL` | https://api.fundermaps.com |
| maps, report | `VITE_FUNDERMAPS_TILESERVER_URL` | https://tiles.fundermaps.com/{SOURCE}/{z}/{x}/{y} |
| maps, report | `VITE_FUNDERMAPS_TILES_URL` | https://fundermaps-tileset.ams3.digitaloceanspaces.com/{SOURCE}/{z}/{x}/{y}.pbf |
| maps | `VITE_FUNDERMAPS_BASE_STYLE` | https://tiles.fundermaps.com/style/fundermaps-basemap |
| maps | `VITE_PDOK_LOCATIONSERVICE` | https://api.pdok.nl/bzk/locatieserver/search/v3_1 (external) |
| report | `VITE_AUTH_KEY` | build-time platform API key (secret; see security audit) |
| intake (runtime, Nitro) | `NUXT_API_BASE`, `NUXT_PUBLIC_API_BASE` | https://api.fundermaps.com; Spaces endpoint/bucket hard-coded in `nuxt.config.ts` |

Hard-coded in source (not env): `tiles.fundermaps.com/style/fundermaps-basemap` in
`WebFront/src/components/Mapbox/Map.vue`, `WebFront/src/views/NotFound.vue`,
`ClientApp/src/components/Mapbox/SampleMap.vue`; `maps.fundermaps.com` +
`admin.fundermaps.com` app-switcher links in `ClientApp/src/components/UserMenu.vue`;
`api-test-grcaa` / tiles / tileset `<link rel=preconnect>` in `WebFront/index.html`;
`feedback.fundermaps.com` + `incident.fundermaps.com` in `WebFront/src/config/index.ts`
(**dead: no DNS records exist for either** — portals left our infra ~Mar 2026);
`fundermaps.com` OG/canonical URLs in `Pages/src/_partials/meta.html`.

## 4. Tile server (Martin) — self-referencing hostname

`tileserver/styles/fundermaps-basemap.json` pins `https://tiles.fundermaps.com/boundaries`,
`/sprite/basemap`, `/font/{fontstack}/{range}` (style JSON must be absolute; Chrome Local
Network Access is why fonts/sprites/styles live on this host and not on Spaces). Moving the
tile host = edit the style JSON + rebuild the image + the three `VITE_*` values above.

## 5. Orchestration / data plane

- **Windmill**: instance `base_url` = https://windmill.fundermaps.com; resource
  `f/fundermaps/managed_pg` → `private-db-pg-ams3-0-…:25060` as `fundermaps_windmill`;
  resource `f/fundermaps/s3` → `https://ams3.digitaloceanspaces.com`, bucket
  `fundermaps-data`; 5 schedules notify `yorick@laixer.com`. Workspace mirror:
  `windmill/` in this repo.
- **Database**: DO managed PG `db-pg-ams3-0` — public and private hostnames, ports 25060 /
  25061 (PgBouncer pools `api-pool`, `webservice-pool`, db `windmill`); App Platform injects
  it through `${db-pg-ams3-0.*}` bindables in api-prod, webservice-prod/-staging,
  windmill-prod, analytics-prod. Tileserver has a literal `DATABASE_URL` secret.
- **Object storage**: endpoint `ams3.digitaloceanspaces.com`; buckets `fundermaps`,
  `fundermaps-tileset`, `fundermaps-data`, `fundermaps-development`, `fundermaps-archive`
  (cold). Virtual-host URLs of `fundermaps-tileset` are baked into two frontends (§3).
- **E-mail**: Resend on `funderdata.nl` (DNS §1); `MAIL_FROM` default `noreply@funderdata.nl`.
- **Grafana**: `GF_SERVER_ROOT_URL=https://analytics.fundermaps.com`; its generic-OAuth
  config is not in the app spec (set in Grafana itself); OIDC row in §2a.

## 6. Move checklist per hostname class

1. **API host** (api.fundermaps.com): 7 `VITE_FUNDERMAPS_URL` builds + Intake `NUXT_*`,
   `BASE_URL`, both `TRUSTED_ORIGINS` copies, OIDC issuer for Grafana, `preconnect` in
   WebFront, docs/README examples.
2. **Frontend host** (any SPA): DNS + App Platform domain, OIDC `redirect_uris` +
   `post_logout_redirect_uris`, `TRUSTED_ORIGINS` (env + ingress CORS), Spaces CORS if it
   uploads/reads Spaces directly, `STUDIO_URL`/`INTAKE_URL` if it is studio/melden,
   `REPORT_RENDER_URL` + tileset CORS if it is report, UserMenu links if maps/admin.
3. **Tile host**: style JSON in `tileserver/styles/`, 3 `VITE_*` values, 3 hard-coded
   style URLs, WebFront preconnect.
4. **Storage endpoint**: `S3_ENDPOINT` (api), Intake `nuxt.config.ts`, Windmill `s3`
   resource, `VITE_FUNDERMAPS_TILES_URL` ×2, all Spaces CORS rules.
5. **Mail domain**: Resend DNS set, `MAIL_FROM`, `INTAKE_REPLY_TO`.

## Appendix — raw grep (repos under ~/src, excl. C# monolith, lockfiles, node_modules)

```
FunderMapsApi/docs/external-provider-onboarding.md:20:https://api.fundermaps.com
FunderMapsApi/docs/inquiry-recovery-api-reference.md:16:https://api.fundermaps.com
FunderMapsApi/docs/inquiry-recovery-api-reference.md:480:https://api.fundermaps.com
FunderMapsApi/.env.example:12:http://localhost:3000
FunderMapsApi/.env.example:14:https://auth.fundermaps.com/login
FunderMapsApi/.env.example:28:https://studio.fundermaps.com
FunderMapsApi/.env.example:34:https://whale-app-nm9uv.ondigitalocean.app
FunderMapsApi/src/config.ts:21:https://auth.fundermaps.com/login.
FunderMapsApi/src/config.ts:22:https://auth.fundermaps.com/login
FunderMapsApi/src/config.ts:50:https://studio.fundermaps.com
FunderMapsApi/src/config.ts:61:https://whale-app-nm9uv.ondigitalocean.app
FunderMapsApi/src/config.ts:72:https://melden.fundermaps.com
FunderMapsApi/src/lib/auth-schema.test.ts:15:http://localhost:3000
FunderMapsApi/src/lib/auth.ts:268:https://admin.fundermaps.com/oauth/consent
FunderMapsApi/src/lib/intake-emails.test.ts:100:https://melden.fundermaps.com/melding/FM2026-000042
FunderMapsApi/src/lib/intake-emails.test.ts:109:https://melden.fundermaps.com/melding/FM2026-000042
FunderMapsApi/src/lib/intake-emails.test.ts:109:https://melden.fundermaps.com/melding/FM2026-000042
FunderMapsApi/src/lib/intake-emails.test.ts:152:https://melden.fundermaps.com/melding/FM2026-000042
FunderMapsApi/src/lib/intake-emails.test.ts:85:https://melden.fundermaps.com/melding/FM2026-000042
FunderMapsAuth/.env.example:3:https://api.fundermaps.com
FunderMapsAuth/.env.example:5:https://fundermaps-api-test-grcaa.ondigitalocean.app
FunderMapsAuth/.env.example:6:https://api.fundermaps.com
FunderMapsAuth/README.md:35:https://api.fundermaps.com
FunderMapsAuth/README.md:36:https://auth.fundermaps.com
FunderMapsClientApp/.env.example:1:https://fundermaps-api-test-grcaa.ondigitalocean.app
FunderMapsClientApp/.env.example:6:https://tiles.fundermaps.com/style/fundermaps-basemap
FunderMapsClientApp/src/components/Mapbox/SampleMap.vue:46:https://tiles.fundermaps.com/style/fundermaps-basemap
FunderMapsClientApp/src/components/UserMenu.vue:64:https://maps.fundermaps.com
FunderMapsClientApp/src/components/UserMenu.vue:67:https://admin.fundermaps.com
FunderMaps/contrib/etc/_appsettings.Development.json:31:https://ams3.digitaloceanspaces.com/
FunderMaps/contrib/etc/_appsettings.Production.json:30:https://ams3.digitaloceanspaces.com/
FunderMapsIntake/nuxt.config.ts:18:https://ams3.digitaloceanspaces.com
FunderMapsIntake/README.md:133:https://ams3.digitaloceanspaces.com
FunderMapsPages/CLAUDE.md:14:http://localhost:8000
FunderMapsPages/src/artikelen.html:1063:https://app.fundermaps.com
FunderMapsPages/src/_partials/meta.html:15:https://fundermaps.com/{{
FunderMapsPages/src/_partials/meta.html:16:https://fundermaps.com/og-image.jpg
FunderMapsPages/src/_partials/meta.html:25:https://fundermaps.com/og-image.jpg
FunderMapsPages/src/_partials/meta.html:37:https://fundermaps.com/
FunderMapsPages/src/_partials/meta.html:38:https://fundermaps.com/logo.png
FunderMapsPages/src/_partials/meta.html:8:https://fundermaps.com/{{
FunderMapsWebFront/index.html:30:https://fundermaps-api-test-grcaa.ondigitalocean.app
FunderMapsWebFront/index.html:39:https://tiles.fundermaps.com
FunderMapsWebFront/index.html:40:https://fundermaps-tileset.ams3.digitaloceanspaces.com
FunderMapsWebFront/src/components/Mapbox/Map.vue:55:https://tiles.fundermaps.com/style/fundermaps-basemap
FunderMapsWebFront/src/config/index.ts:6:https://feedback.fundermaps.com/building/
FunderMapsWebFront/src/config/index.ts:7:https://incident.fundermaps.com/
FunderMapsWebFront/src/views/NotFound.vue:12:https://tiles.fundermaps.com/style/fundermaps-basemap
FunderMapsWebservice/MIGRATION.md:109:https://ws.fundermaps.com/v4/mcp
FunderMapsWebservice/MIGRATION.md:14:https://ws-staging.fundermaps.com/v4/product/analysis/{id}
FunderMapsWebservice/MIGRATION.md:15:https://ws-staging.fundermaps.com/v4/product/statistics/{id}
FunderMapsWebservice/MIGRATION.md:22:https://ws-staging.fundermaps.com/v4/product/analysis/NL.IMBAG.PAND.1734101000021359
FunderMapsWebservice/MIGRATION.md:33:https://ws.fundermaps.com/api/v3/product/analysis/{id}
FunderMapsWebservice/MIGRATION.md:34:https://ws.fundermaps.com/api/v3/product/statistics/{id}
FunderMapsWebservice/MIGRATION.md:366:https://ws.fundermaps.com/v4/health
FunderMapsWebservice/MIGRATION.md:37:https://ws.fundermaps.com/v4/product/analysis/{id}
FunderMapsWebservice/MIGRATION.md:380:https://ws-staging.fundermaps.com/v4/health
FunderMapsWebservice/MIGRATION.md:384:https://ws-staging.fundermaps.com/v4/...
FunderMapsWebservice/MIGRATION.md:38:https://ws.fundermaps.com/v4/product/statistics/{id}
FunderMapsWorker/sql/migrate/add_studio_origin_clientapp.sql:27:https://studio.fundermaps.com/auth/callback
FunderMapsWorker/sql/migrate/add_studio_origin_clientapp.sql:30:https://studio.fundermaps.com/auth/callback
FunderMapsWorker/sql/migrate/add_studio_origin_clientapp.sql:35:https://studio.fundermaps.com/login
FunderMapsWorker/sql/migrate/add_studio_origin_clientapp.sql:38:https://studio.fundermaps.com/login
FunderMapsWorker/sql/migrate/add_studio_origin_clientapp.sql:8:https://studio.fundermaps.com/auth/callback
FunderMapsWorker/sql/migrate/add_studio_origin_clientapp.sql:9:https://studio.fundermaps.com/login
FunderMapsWorker/sql/migrate/enable_clientapp_end_session.sql:16:https://app.fundermaps.com/login}
FunderMapsWorker/sql/migrate/register_clientapp_oidc_client.sql:24:https://app.fundermaps.com/auth/callback}
FunderMapsWorker/sql/migrate/register_managementfront_oidc_client.sql:23:https://admin.fundermaps.com/auth/callback}
FunderMapsWorker/sql/migrate/register_managementfront_oidc_client.sql:24:https://admin.fundermaps.com/login}
FunderMapsWorker/sql/migrate/register_webfront_oidc_client.sql:22:https://maps.fundermaps.com/auth/callback}
FunderMapsWorker/sql/migrate/register_webfront_oidc_client.sql:23:https://maps.fundermaps.com/}
FunderMapsWorker/tileserver/README.md:48:https://tiles.fundermaps.com/buildings/14/8415/5384
FunderMapsWorker/tileserver/README.md:49:https://tiles.fundermaps.com/catalog
FunderMapsWorker/tileserver/styles/fundermaps-basemap.json:18:https://tiles.fundermaps.com/boundaries
FunderMapsWorker/tileserver/styles/fundermaps-basemap.json:21:https://tiles.fundermaps.com/sprite/basemap
FunderMapsWorker/tileserver/styles/fundermaps-basemap.json:22:https://tiles.fundermaps.com/font/{fontstack}/{range}
```
