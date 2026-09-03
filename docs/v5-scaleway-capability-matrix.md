# Scaleway capability matrix (v5 hosting move)

Snapshot **2026-09-03**. DigitalOcean service → Scaleway equivalent, verified against Scaleway's
docs source (`github.com/scaleway/docs-content`, HEAD 0b895df) and the public Product Catalog API
for prices, because scaleway.com itself blocks automated fetches. Anything read only from marketing
pages is marked *unverified*. Companion: `v5-hostname-inventory.md`.

## FunderMaps read-out (what changes the plan)

| topic | verdict | consequence for v5 |
|---|---|---|
| **PostgreSQL major** | Scaleway tops out at **PG 17**; prod is 18.6 | Migration is logical (pg_dump/restore or logical replication into a PG 17 subscriber), not a physical copy. Check nothing relies on PG 18-only behaviour. Extensions we need exist: PostGIS 3.5, TimescaleDB 2.22, pg_trgm, pg_cron, pgvector. |
| **Connection pooling** | **No managed PgBouncer** | `api-pool` / `webservice-pool` on :25061 have no equivalent. App-side pooling with hard caps in Bun/postgres.js, or a self-hosted PgBouncer on a small Instance (one extra component — count it). |
| **Deploy-on-push** | **Not native** on Serverless Containers | GitHub Actions: build → push to `rg.nl-ams.scw.cloud` → `scw container container deploy`. Immutable image tags (same-tag pushes do not roll). The Dockerfiles in Api #127 / WS #37 are the input. |
| **Request timeout** | 10 s – 60 min (DO: 100 s) | PDF render lane (`/api/pdf`, 30–60 s+) stops being a problem. |
| **Long jobs (BAG ~2 h)** | Serverless Jobs: 24 h, 10 GB disk, **no VPC** | BAG load needs the DB public endpoint + ACL, or a small Instance inside the Private Network. Container CRON caps at 60 min. `/tmp` is RAM under gVisor. |
| **Uptime checks** | **Gap** — Cockpit has no synthetic monitoring | Keep an external checker for `ws /v4/health` (Better Stack per the status-page plan). |
| **Email** | TEM is fr-par only, webhooks via Topics & Events | Resend stays unless we want single-vendor; funderdata.nl DNS then moves. |
| **Redis/Valkey** | Redis 8.4 only, cache-oriented | Fine for the fail-open session/API-key cache in the Valkey plan. |
| **DNS** | External zones supported, ≈ €5.11/zone/mo | 7 zones today ≈ €36/mo; or keep DNS on DO/elsewhere — DNS does not have to move with compute. |
| **Cost** | ≈ **€362/mo** standalone PG (4C/16G), ≈ €473 HA | vs the DO bill where the DB alone is $162/mo. Composition of DB pricing is inferred, confirm in the console estimator. |

Below is the full research as delivered (agent run 2026-09-03, 117 tool calls).

---

# Scaleway migration research for FunderMaps (DO → Scaleway) — 2026-09-03

**Method / provenance.** `www.scaleway.com` (docs *and* pricing pages) returns a Cloudflare 403/JS challenge to every automated fetch (WebFetch, curl, headless Chromium), so two official machine-readable sources were used instead:

- **Docs:** Scaleway's own docs source repo `github.com/scaleway/docs-content` (this *is* the content served at scaleway.com/en/docs; HEAD read today, commit `0b895df`, 2026-09-03 17:12 +0200). URLs below are the corresponding public docs URLs.
- **Prices:** Scaleway's **public, unauthenticated Product Catalog API** — `https://api.scaleway.com/product-catalog/v2alpha1/public-catalog/products` (5,491 SKUs, retail prices in EUR, per region/zone). Developer reference: https://www.scaleway.com/en/developers/api/product-catalog/ . Every euro figure below comes from this API (nl-ams SKUs) unless stated otherwise.
- The HTML pricing pages themselves were not readable; where a number exists only there (free tiers, node vCPU/RAM of DB/Redis types) it is marked **unverified**. Monthly figures use 730 h.

---

## (a) Summary table

| DO service | Scaleway equivalent | Fit | Key constraint | Source |
|---|---|---|---|---|
| App Platform web service (buildpack/Dockerfile) | **Serverless Containers** (nl-ams available) | **Partial** | Container image only (no buildpacks); **no native deploy-on-push** — CI must push to Container Registry and call `scw container container deploy`; "redeploy" required even for same-tag pushes | [limitations](https://www.scaleway.com/en/docs/serverless-containers/reference-content/containers-limitations/), [deploy methods](https://www.scaleway.com/en/docs/serverless-containers/reference-content/deploy-container/), [FAQ](https://www.scaleway.com/en/docs/serverless-containers/faq/) |
| App Platform 100 s request timeout | Containers request timeout **10 s – 60 min** (configurable) | **Yes** (better) | — | [limitations](https://www.scaleway.com/en/docs/serverless-containers/reference-content/containers-limitations/) |
| App Platform 4 GiB ephemeral disk | Containers temp disk **up to 24,000 MiB** (max tied to RAM); Jobs **10 GB** | **Yes / partial** | Under sandbox v2 (gVisor, default) `/tmp` lives in **RAM** and counts against memory | [sandbox](https://www.scaleway.com/en/docs/serverless-containers/reference-content/containers-sandbox/), [jobs limits](https://www.scaleway.com/en/docs/serverless-jobs/reference-content/jobs-limitations/) |
| Custom domains + managed TLS | Containers custom domains (CNAME; Let's Encrypt auto-renew; 50/container) | **Yes** | Cannot bring your own cert; apex needs CNAME flattening/ALIAS | [custom domain](https://www.scaleway.com/en/docs/serverless-containers/how-to/add-a-custom-domain-to-a-container/) |
| Autoscaling / min instances | Concurrency-, CPU- or RAM-based; min-scale 0..N, max 50; scale-to-zero after 15 min | **Yes** | CPU/RAM-based autoscaling requires min-scale ≥ 1 | [autoscaling](https://www.scaleway.com/en/docs/serverless-containers/reference-content/containers-autoscaling/) |
| Health checks | Startup + liveness probes (TCP/HTTP), interval 5–120 s | **Yes** | Docker `HEALTHCHECK` ignored; failing liveness stops traffic, no restart | [concepts](https://www.scaleway.com/en/docs/serverless-containers/concepts/#health-check), changelog 2026-08-21 |
| Worker / background component | Container with min-scale 1 (must bind a port) **or** Serverless Jobs (batch, up to 24 h) | **Partial** | Jobs have **no VPC/Private Network** support | [jobs FAQ](https://www.scaleway.com/en/docs/serverless-jobs/faq/), [comparison](https://www.scaleway.com/en/docs/serverless-containers/reference-content/difference-jobs-functions-containers/) |
| Scheduled jobs | Container CRON triggers; Jobs cron triggers (multiple, with timezone) | **Yes** | Container-triggered work capped at 60 min per request | [container cron](https://www.scaleway.com/en/docs/serverless-containers/how-to/add-trigger-to-a-container/), [job triggers](https://www.scaleway.com/en/docs/serverless-jobs/how-to/manage-job-triggers/) |
| SSE / long-lived connections | HTTP/1.1, HTTP/2, **WebSockets**, gRPC supported | **Partial** | SSE not named explicitly (60-min request cap applies); HTTP/1.0 unsupported | [FAQ](https://www.scaleway.com/en/docs/serverless-containers/faq/) |
| Managed PostgreSQL 18 + PostGIS 3.5 + TimescaleDB | Managed Database for PostgreSQL — **PG 17 max**; PostGIS 3.5, TimescaleDB 2.22.1, pgvector 0.8.1, pg_cron, pg_trgm, postgis_raster/topology | **Partial** | **No PG 18**; **no built-in PgBouncer/pooler**; no PITR documented (snapshots only) | [extensions](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/reference-content/postgresql-extensions/), [PG versions](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/reference-content/pg-version-updates/) |
| DO Spaces (S3 + CDN + CORS + lifecycle) | Object Storage nl-ams (Standard Multi-AZ, One Zone, **Glacier available in nl-ams**) + Edge Services | **Yes** | Bucket names globally unique platform-wide; lifecycle transitions need ≥30 d (One Zone) / ≥90 d (Glacier); Edge Services is a paid plan (from €0.99/mo) | [FAQ](https://www.scaleway.com/en/docs/object-storage/faq/), [CORS](https://www.scaleway.com/en/docs/object-storage/api-cli/setting-cors-rules/), [Edge pricing](https://www.scaleway.com/en/docs/edge-services/reference-content/understanding-pricing/) |
| DO Container Registry | Container Registry nl-ams (`rg.nl-ams.scw.cloud`) | **Yes** | €0.027/GB/mo private; inter-region egress €0.033/GB | [registry FAQ](https://www.scaleway.com/en/docs/container-registry/faq/) |
| DO Managed Valkey | Managed Database for **Redis** 8.4 (7.2.11 deprecated) | **Partial** | No Valkey; positioned "best suited for caching", persistence not guaranteed; RAM of RED1-MICRO unverified | [Redis FAQ](https://www.scaleway.com/en/docs/managed-databases-for-redis/faq/), [persistence](https://www.scaleway.com/en/docs/managed-databases-for-redis/reference-content/ensuring-data-persistence/) |
| DO DNS | Domains and DNS — external domains supported (TXT `_scaleway-challenge`, then NS change) | **Yes** | €0.007/h per external zone (~€5.11/mo) + €0.0005/M queries; DNSSEC documented for **internal** domains only; quota 10 external domains | [add external domain](https://www.scaleway.com/en/docs/domains-and-dns/how-to/add-external-domain/), [records](https://www.scaleway.com/en/docs/domains-and-dns/how-to/manage-dns-records/) |
| DO Uptime checks | — | **Gap** | Cockpit has **no synthetic/uptime monitoring**; DNS "health check records" exist but are for routing, not alerting | [Cockpit FAQ](https://www.scaleway.com/en/docs/cockpit/faq/) |
| DO Alerting/metrics | Cockpit (Grafana + Mimir/Loki/Tempo); Scaleway-product data free, 31 d metrics / 7 d logs | **Yes** | Grafana-managed alerting **not supported** — datasource-managed rules + Scaleway alert manager only | [alerts](https://www.scaleway.com/en/docs/cockpit/how-to/configure-alerts-for-scw-resources/), [pricing](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-pricing/) |
| Resend (email) | Transactional Email (TEM): API + SMTP, SPF/DKIM/DMARC, webhooks | **Partial** | **fr-par only** (EU); default 10,000 emails/mo quota (500 / 5,000 before identity validation); webhooks only via Topics & Events (SNS-style), 1/domain on Essential; API mail ≤ 2 MB; attachment MIME allow-list | [limits](https://www.scaleway.com/en/docs/transactional-email/reference-content/tem-capabilities-and-limits/), [plans](https://www.scaleway.com/en/docs/transactional-email/how-to/manage-tem-plans/), [webhooks](https://www.scaleway.com/en/docs/transactional-email/how-to/create-webhooks/) |
| Secrets / IAM / IaC | Secret Manager; IAM (apps, API keys, policies w/ conditions, projects); Terraform provider v2.82.0 (partner-premier, 2026-09-01); `scw` CLI v2.62.0; `scaleway/action-scw` | **Yes** | Containers integrate Secret Manager "only via local secrets" (Jobs natively); IAM quotas 100 API keys / 100 apps / 50 policies / 50 users default | [IAM FAQ](https://www.scaleway.com/en/docs/iam/faq/), [SM FAQ](https://www.scaleway.com/en/docs/secret-manager/faq/), [TF registry](https://registry.terraform.io/providers/scaleway/scaleway/latest) |
| VPC / Serverless→DB private | VPC + Private Networks free; Containers attach to 1 PN (egress only) and reach Managed DB private endpoint; VPC routing supported | **Yes** (containers) / **Gap** (jobs) | Containers: no private ingress, no static IP; Jobs: no PN at all | [containers PN](https://www.scaleway.com/en/docs/serverless-containers/reference-content/containers-private-networks/), [VPC FAQ](https://www.scaleway.com/en/docs/vpc/faq/) |
| Compliance | ISO/IEC 27001:2022, HDS (French DCs, selected products), CSA STAR L1, GDPR/DPA; SecNumCloud in progress | **Yes** | No SOC 2 evidence found; HDS scope excludes nl-ams | [Trust Center](https://security.scaleway.com/), [contracts](https://www.scaleway.com/en/contracts/), [benefits page](https://www.scaleway.com/en/docs/use-cases/benefits-migration/) |

---

## (b) Per-service detail

### 1. Compute — Serverless Containers / Jobs / Kapsule

**Serverless Containers limits** ([containers-limitations](https://www.scaleway.com/en/docs/serverless-containers/reference-content/containers-limitations/), validated 2025-09-17):
- CPU **70–6000 mvCPU**; memory **128–12,228 MB**; temp disk **max 24,000 MiB** (max depends on memory); catalog tiers in nl-ams: mvCPU `100, 250, 400, 500, 750, 1000, 2000…6000`; memory `128 MB, 256 MB, 512 MB, 1, 2, 3, 4, 6, 8, 10, 12 GB` (Product Catalog SKU `/paas/caas/*/nl-ams`). "Available memory options depend on allocated vCPU" — the exact pairing matrix is **not documented** ([container-resources macro](https://www.scaleway.com/en/docs/serverless-containers/how-to/deploy-container/)).
- Request timeout **10 s to 60 min**; concurrency **80** per instance; max scale **50** instances/container; invocation rate 5,000/s; env vars 200 × 65,536 chars; 1 Private Network per container; scale-to-zero after **15 min** idle, scale-down after 30 s.
- Total memory quota: 60 GB (payment validated) / 150 GB (identity validated) = RAM × max-scale summed ([quotas](https://www.scaleway.com/en/docs/organizations-and-projects/additional-content/organization-quotas/)).
- Regions: fr-par, nl-ams, pl-waw (changelog 2022-05-01) + it-mil (changelog 2026-08-31). Catalog confirms nl-ams SKUs.
- Rolling updates, zero downtime; traffic splitting between versions ([FAQ](https://www.scaleway.com/en/docs/serverless-containers/faq/)).
- Cold start: no numbers documented; mitigations = sandbox v2, min-scale 1, CRON keep-warm. "A new container instance will always start after each deployment, even with min-scale 0."
- Private Networks: egress only, DNS via VPC resolver, cold starts "slightly longer", each instance gets its own PN IP ([containers-private-networks](https://www.scaleway.com/en/docs/serverless-containers/reference-content/containers-private-networks/)).
- Health checks: startup + liveness probes, TCP/HTTP, interval 5–120 s (default 30), failure threshold 3–50 (default 10) — console support added 2026-08-21 ([concepts](https://www.scaleway.com/en/docs/serverless-containers/concepts/#health-check)).
- Deploy: Terraform / `scw container container create|deploy` / API / Serverless Framework; external private registries **not supported**; use Scaleway registry ([deploy-container-cli](https://www.scaleway.com/en/docs/serverless-containers/api-cli/deploy-container-cli/)). GitHub Actions: `scaleway/action-scw` + [registry tutorial](https://www.scaleway.com/en/docs/tutorials/use-container-registry-github-actions/).
- **Pricing (catalog, nl-ams):** €0.00001 per vCPU-s, €0.000002 per GB-s; ephemeral storage and ingress/egress free. **Free tier 200,000 vCPU-s + 400,000 GB-s/month** (from the worked example in the [FAQ](https://www.scaleway.com/en/docs/serverless-containers/faq/#how-am-i-billed-for-serverless-containers)).

**Serverless Jobs** ([jobs-limitations](https://www.scaleway.com/en/docs/serverless-jobs/reference-content/jobs-limitations/)): max **6 vCPU / 16 GB / 10 GB ephemeral / 24 h**; 400 parallel runs/org; `linux/amd64` only; outbound ports 25/465 blocked except to TEM; **no VPC** ([FAQ](https://www.scaleway.com/en/docs/serverless-jobs/faq/)); native Secret Manager references; multiple cron triggers with timezone + automatic retries (changelog 2026-06-19). Same unit prices as containers (catalog `/paas/jobs/*/nl-ams`), free tier 200k vCPU-s + 400k GB-s ([FAQ example](https://www.scaleway.com/en/docs/serverless-jobs/faq/)).

**Kubernetes Kapsule** (fallback): mutualized control plane **€0/h** (catalog `/k8s/control-plane/nl-ams`), dedicated 4/8/16 = €0.11/0.18/0.35 per h; nodes at Instance prices (nl-ams-1: PLAY2-NANO 2 vCPU/4 GiB €0.02754/h ≈ €20.10/mo; PRO2-XXS 2/8 GiB €0.0561/h ≈ €40.95/mo; POP2-4C-16G €0.147/h); K8s 1.33–1.37 supported ([version policy](https://www.scaleway.com/en/docs/kubernetes/reference-content/version-support-policy/), [control planes](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-control-plane-offers/)). Ingress needs a Load Balancer (LB-S €0.023/h + IP €0.005/h).

### 2. Managed Database for PostgreSQL

- **Versions:** PG 17 is the newest (changelog 2025-11-18 "PG v17 support"); **no PG 18 anywhere in docs/changelog** as of today. Concepts page still lists 9.6–15 (stale). ([pg-version-updates](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/reference-content/pg-version-updates/))
- **Extensions on PG 17:** PostGIS "3.14 and 3.5" (sic), TimescaleDB **2.22.1**, pgRouting 3.7.3, pgvector 0.8.1, h3-pg 4.2.3; full list includes `postgis_raster`, `postgis_topology`, `postgis_sfcgal`, `pg_cron`, `pg_trgm`, `pg_stat_statements`, `pgaudit`, `uuid-ossp`, `hstore`, `postgres_fdw`, `ogr_fdw` ([extensions](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/reference-content/postgresql-extensions/)).
- **Pooling:** zero mentions of PgBouncer/pooler in the product docs → **not offered**. `max_connections` per node type: unverified.
- **HA vs standalone:** HA = synchronous hot standby in same DC, different rack; upgrade standalone→HA possible, not reverse; autohealing on HA ([concepts](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/concepts/), [FAQ](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/faq/)). Read replicas (same/multi-AZ), same node type as primary.
- **Storage:** Block Storage 5K or 15K IOPS, up to **15 TB**, cannot shrink; local SSD only on first-gen nodes ([manage-volumes](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/how-to/manage-volumes/)).
- **Backups:** Block volumes use **snapshots**; autobackup default 1/day, 7-day retention (configurable); manual backups on Block only ≤ 585 GB; **no PITR/WAL-based restore documented** ([backups](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/how-to/manage-backups/), [snapshots](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/how-to/manage-snapshots/)). Snapshot price €0.03/GB/mo (docs) = €0.000044/GB/h (catalog).
- **Network:** 1 Private Network per instance; public endpoint removable; ACLs; IPv6 unsupported; encryption at rest (LUKS) optional, irreversible ([connect](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/how-to/connect-database-instance/), [remove public endpoint](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/how-to/remove-public-endpoint/)).
- **Migration:** pg_dump/pg_restore; **logical replication as subscriber (PG ≥16)** for zero-downtime — Scaleway connects out via a public interface even with private endpoint; publisher role available on PG 17 ([migrating](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/reference-content/migrating-databases/), [subscriber](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/api-cli/logical-replication-as-subscriber/)). Major upgrades create a clone (both billed) ([upgrade](https://www.scaleway.com/en/docs/managed-databases-for-postgresql-and-mysql/how-to/postgresql-upgrade-version/)).
- **Node prices, nl-ams (catalog; node types are billed as "Database Node" + "Database management" SKUs):**

| Type | Node €/h | Management €/h | Standalone ≈ €/mo (node+mgmt) | HA ≈ €/mo (2 nodes+mgmt, **composition inferred**) |
|---|---|---|---|---|
| DB-PLAY2-PICO | 0.0203 | 0.003 | 17.0 | 31.8 |
| DB-PRO2-XXS | 0.0583 | 0.0517 | 80.3 | 122.9 |
| DB-PRO2-XS | 0.1166 | 0.1034 | 160.6 | 245.7 |
| DB-POP2-2C-8G | 0.076 | 0.0674 | 104.7 | 160.1 |
| **DB-POP2-4C-16G** | **0.1519** | **0.1347** | **209.2** | **320.1** |
| DB-POP2-8C-32G | 0.3069 | 0.2615 | 414.9 | 639.0 |

The node+management composition is inferred from the SKU structure and reconciles with published third-party monthly figures (PRO2-XXS €80 / €123 HA); vCPU/RAM of POP2-4C-16G taken from the name (unverified in docs). Storage: Block 5K **€0.000136/GB/h (≈ €0.0993/GB/mo)**, 15K €0.000204/GB/h, snapshot €0.000044/GB/h, backup storage €0.00004/GB/h. Zones nl-ams-1/2/3 present.

### 3. Object Storage

- S3-compatible API (subset), regional endpoint `https://s3.nl-ams.scw.cloud`, virtual-host and path style ([concepts](https://www.scaleway.com/en/docs/object-storage/concepts/)).
- Classes in **nl-ams: Standard Multi-AZ, Standard One Zone, Glacier** (Glacier physically in Paris DC4, usable from nl-ams buckets) ([FAQ](https://www.scaleway.com/en/docs/object-storage/faq/)).
- CORS via `aws s3api put-bucket-cors` ([setting-cors-rules](https://www.scaleway.com/en/docs/object-storage/api-cli/setting-cors-rules/)); lifecycle expiration/transition/abort-MPU with prefix/tag filters; **transition minimums (rules after 2026-04-01): 30 days → One Zone, 90 days → Glacier**; only top-down transitions ([lifecycle](https://www.scaleway.com/en/docs/object-storage/how-to/manage-lifecycle-rules/)). Rules evaluated daily at 00:00 UTC.
- Bucket website hosting yes ([bucket website](https://www.scaleway.com/en/docs/object-storage/how-to/use-bucket-website/)); CDN = **Edge Services** (cache + WAF + custom domain with Let's Encrypt or own cert) for buckets and Load Balancers; containers "natively integrated" ([Edge FAQ](https://www.scaleway.com/en/docs/edge-services/faq/)).
- Versioning (≤1,000 versions/object), Object Lock, SSE-C/SSE-ONE/SSE-KMS, read-after-write consistency, 5 TB objects, 1,000-part multipart 5 MB–5 GB parts.
- Glacier restore may take **minutes to 24 h to start**; restore €0.009/GB.
- **Prices (catalog, nl-ams):** Standard Multi-AZ **€0.000022/GB/h (≈ €0.0161/GB/mo)**; One Zone €0.000011/GB/h (≈ €0.008/GB/mo; price drop changelog 2026-01-05); Glacier €0.00000348/GB/h (≈ €0.0025/GB/mo); **egress to internet €0.01/GB**, ingress free, intra-region free, inter-region €0.01/GB.
- **Free tier: unverified.** Docs describe a **750 GB / 90-day trial** for new users; the "75 GB free per month" figure appears on the marketing page only (not in docs, not in catalog).
- Edge Services plans (catalog): Starter €0.99/mo, Professional €12.99/mo, Advanced €109.99/mo; extra cache egress €0.0135/GB; extra pipeline €0.005376/h; WAF add-on (Starter) €4/mo.

### 4. Container Registry
Private images **€0.027/GB/mo** (catalog €0.000037/GB/h), public images free ≤75 GB; intra-region pull free, inter-region €0.033/GB, ingress free; regions fr-par, nl-ams, pl-waw (+ it-mil 2026-08-31); unlimited versions; vulnerability scanning = private beta ([registry FAQ](https://www.scaleway.com/en/docs/container-registry/faq/)).

### 5. Managed Database for Redis
- Redis **8.4** supported (changelog 2026-02-19); 7.2.11 deprecated same day; 6.2.7/7.0.5 gone. **No Valkey**.
- Modes: standalone, 2-node HA (async replica), cluster 3–6 nodes; TLS; ACLs; Private Network (cluster mode: PN only at creation); AZs **AMS1, AMS2**, PAR1/2, WAW1/2 ([create](https://www.scaleway.com/en/docs/managed-databases-for-redis/how-to/create-a-database-for-redis/), [FAQ](https://www.scaleway.com/en/docs/managed-databases-for-redis/faq/)).
- Persistence: managed snapshots; "best suited for caching… does not guarantee data recovery" ([persistence](https://www.scaleway.com/en/docs/managed-databases-for-redis/reference-content/ensuring-data-persistence/)).
- **Prices nl-ams-1 (catalog, per node-hour):** RED1-MICRO main **€0.048** (≈ €35.04/mo), additional node €0.027; RED1-2XS €0.075; RED1-XS €0.137; RED1-S €0.205; RED1-M €0.274. RAM per node type: **unverified** (node-type API requires auth).

### 6. DNS, uptime, alerting
- **Domains and DNS:** external domains supported (TXT challenge, 48 h, then NS `ns0/ns1.dom.scw.cloud`, 14 days to finish); API + Terraform; Geo IP, weighted round-robin and HTTP health-check records; DNSSEC how-to covers **internal** domains only ([external domain](https://www.scaleway.com/en/docs/domains-and-dns/how-to/add-external-domain/), [records](https://www.scaleway.com/en/docs/domains-and-dns/how-to/manage-dns-records/)). Catalog: external domain €0, **external zone €0.007/h (≈ €5.11/mo)**, external queries €0.0005 per million; quota 10 external domains / 100 zones.
- **Cockpit:** per-Project Grafana with Mimir/Loki/Tempo; Scaleway-product metrics/logs **free** (31 d / 7 d retention); custom metrics €0.15/M samples (tiered), custom logs/traces €0.35/GB; extra retention €0.002/GB/day; Loki ingest 4 MB/s, Mimir 25k samples/s; alert rules min interval 15 s, max range 1 h ([pricing](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-pricing/), [limits](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-limitations/)). Integrated: Serverless Containers/Jobs, Managed DB (metrics+logs), Redis, Object Storage, LB, Edge, TEM (metrics) ([integration](https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-product-integration/)). Alerting: Grafana-managed alerts **unsupported**; use datasource-managed rules → Scaleway alert manager → contacts (email, Slack, webhook, SMS/on-call) ([alerts](https://www.scaleway.com/en/docs/cockpit/how-to/configure-alerts-for-scw-resources/)). **No uptime/synthetic checks product.**

### 7. Transactional Email (TEM)
API + SMTP relay `smtp.tem.scaleway.com` (587/2587 STARTTLS, 465/2465 TLS; user = Project ID, password = API secret key); SPF+DKIM required, MX recommended, DMARC; **fr-par region only**, all processing in EU, no non-EU sub-processors ([FAQ](https://www.scaleway.com/en/docs/transactional-email/faq/), [SMTP](https://www.scaleway.com/en/docs/transactional-email/reference-content/smtp-configuration/)). Quotas: default 10,000 emails/mo (500 → 5,000 before identity validation), 10 attachments, 10 recipients, API mail 2 MB, SMTP 50 MB, MIME allow-list (ZIP only on Scale), each recipient billed as one email ([limits](https://www.scaleway.com/en/docs/transactional-email/reference-content/tem-capabilities-and-limits/)). Plans: **Essential** 300 free emails/mo then €0.25/1,000 (catalog €0.00025/email), 1 webhook/domain; **Scale** €80/mo incl. 100k + €0.20/1,000, dedicated IP, 30-day commitment, 99.9% SLA ([plans](https://www.scaleway.com/en/docs/transactional-email/how-to/manage-tem-plans/)). Webhooks are delivered **only via Scaleway Topics and Events** (SNS-like), billed as such ([webhooks](https://www.scaleway.com/en/docs/transactional-email/how-to/create-webhooks/)).

### 8. Secret Manager, IAM, Terraform, CLI, CI
- Secret Manager: regions PAR/WAW/AMS, 64 KB/secret, versions, ephemeral policies, 7-day scheduled deletion; catalog **€0.00006 per version** (per hour by billing description → ≈ €0.044/version/mo, inferred) + €0.000003/request ([FAQ](https://www.scaleway.com/en/docs/secret-manager/faq/)). Containers/Functions consume secrets "only via local secrets"; Jobs reference SM natively ([comparison](https://www.scaleway.com/en/docs/serverless-containers/reference-content/difference-jobs-functions-containers/)).
- IAM: free; applications (non-human identities) + API keys + policies with conditions (e.g. `request_ip`); defaults 100 API keys, 100 apps, 50 policies, 50 groups, 50 users; Object Storage keys need a preferred Project ([IAM FAQ](https://www.scaleway.com/en/docs/iam/faq/)).
- Terraform/OpenTofu provider **v2.82.0, 2026-09-01, tier partner-premier**, 15M downloads (registry API); `scw` CLI **v2.62.0 (2026-09-01)**; GitHub Action `scaleway/action-scw` (installs CLI, runs commands, exports config); registry push tutorial ([GitHub Actions tutorial](https://www.scaleway.com/en/docs/tutorials/use-container-registry-github-actions/)).

### 9. Network
- VPC, Private Networks, VPC routing, reserved IPAM IPs: **free** ([VPC FAQ](https://www.scaleway.com/en/docs/vpc/faq/)); VPC peering €0.02/h; NACLs GA (2026-06-03).
- Serverless Containers → Managed DB over PN: **yes** (container PN egress + DB private endpoint; VPC routing compatible). Managed DB and containers each accept **1** PN.
- Public Gateway (NAT/bastion, zonal): S €0.026/h, M €0.095/h, L €0.439/h, XL €0.949/h + IP €0.005/h; traffic free ([PGW FAQ](https://www.scaleway.com/en/docs/public-gateways/faq/)). Not needed for containers (public egress via their own endpoint).
- Load Balancer nl-ams: LB-S €0.023/h (200 Mbps, 20k conns), LB-GP-M €0.054/h (500 Mbps), LB-GP-L €0.094/h (1 Gbps), LB-GP-XL €0.941/h; IPv4 €0.005/h ([LB limits](https://www.scaleway.com/en/docs/load-balancer/reference-content/load-balancers-limitations/)). LBs only take IP backends, so **not usable in front of Serverless Containers** (FAQ).

### 10. Compliance / location
- Regions fr-par, nl-ams (AZs **AMS1, AMS2, AMS3**), pl-waw, it-mil ([availability guide](https://www.scaleway.com/en/docs/account/reference-content/products-availability/); per-product matrix at https://www.scaleway.com/en/product-availability-by-region/ — Cloudflare-blocked, unverified).
- Trust Center lists **GDPR, HDS, ISO/IEC 27001 (+SoA), CSA STAR Level 1**; DPA, sub-processors, privacy policy downloadable ([security.scaleway.com](https://security.scaleway.com/), [contracts](https://www.scaleway.com/en/contracts/)). Docs: "certified under ISO/IEC 27001:2022… since July 2024 HDS… covers Elastic Metal, Dedibox, Object Storage, VPC in French datacenters (DC2–DC5)"; "customer data remains in Europe" ([benefits page](https://www.scaleway.com/en/docs/use-cases/benefits-migration/)). SecNumCloud: qualification in progress per Scaleway news pages (current status unverified). **SOC 2: no evidence.** TEM FAQ: no data leaves EU, no non-EU sub-processors for TEM.

---

## (c) Gaps and risks

1. **PostgreSQL 18 not available (17 max).** Prod is on PG 18.6 → cannot restore a physical copy; path is logical (pg_dump/restore or DO→Scaleway logical replication into a PG 17 subscriber). Check for any PG18-only SQL/behaviour before committing.
2. **No managed connection pooler.** DO PgBouncer on 25061 has no equivalent; Serverless Containers fan out to many instances → connection storms. Need app-side pooling (Bun/Drizzle) with tight caps, or a self-hosted PgBouncer on an Instance (extra component, breaks "0 droplets").
3. **No PITR** — daily (configurable) snapshots only. Define RPO explicitly; consider WAL-shipping via logical replication to a second target if needed.
4. **No deploy-on-push.** Must build the GitHub Actions pipeline: build → push `rg.nl-ams.scw.cloud` → `scw container container deploy` (or Terraform). Same-tag pushes do **not** auto-roll; use immutable tags.
5. **Serverless Jobs have no VPC.** Long BAG load (~2 h) exceeds the 60-min container cap → Jobs → Managed DB must keep a public endpoint (ACL can only allow Scaleway prefixes since Jobs have no fixed IP). Alternative: run BAG on a small Instance in the PN, or split into <60-min container CRON steps. Jobs ephemeral disk max **10 GB** (7.4 GB GPKG fits, barely).
6. **gVisor `/tmp` is RAM** on containers (v2) and Jobs; big temp files must go elsewhere on the FS or memory must be sized up.
7. **Uptime monitoring gap** — keep an external checker (DO Uptime / Better Stack) for `/v4/health`.
8. **Grafana alerting model differs** (datasource-managed only); existing Grafana-managed rules need porting.
9. **TEM ≠ Resend drop-in:** fr-par only, webhooks via Topics & Events, 1 webhook/domain on Essential, API mail 2 MB, MIME allow-list; quotas start low until identity validation. Domain `funderdata.nl` DNS records would move or be re-verified.
10. **No Valkey; Redis cache-oriented** (persistence not guaranteed) — fine for sessions/API-key cache, fail-open as planned.
11. **Object Storage bucket names are globally unique platform-wide** and the 90-day Glacier / 30-day One Zone transition minimums shape lifecycle rules; Glacier restores can take up to 24 h to begin. 75 GB free tier unverified. Egress €0.01/GB (tile/PDF traffic — Edge Services cache can offset at €0.0135/GB overage or plan quotas).
12. **Containers cannot receive private ingress and have no static IPs**; the Report renderer and Gotenberg-style internal calls go over public HTTPS with private (IAM/JWT) auth.
13. **Region-specific gaps:** TEM only in fr-par; HDS scope excludes Amsterdam (irrelevant unless municipalities ask for HDS specifically).
14. **Quotas before identity validation** (containers RAM 60 GB, 5 DB instances, TEM 500 emails/mo) — validate the Organization's identity on day one.
15. **Pricing composition for Managed DB (node + management, ×2 nodes for HA) is inferred**, not documented; confirm in the console cost estimator before sizing.

---

## (d) Rough monthly cost (nl-ams, 730 h, list prices from the Product Catalog API)

| Item | Sizing | Calculation | ≈ €/month |
|---|---|---|---|
| 2 × always-on containers | 0.5 vCPU / 1 GB, min-scale 1 | 2 × 0.5 × 2,628,000 s = 2,628,000 vCPU-s; 5,256,000 GB-s | (part of total below) |
| 1 × container | 1 vCPU / 2 GB, min-scale 1 | 2,628,000 vCPU-s; 5,256,000 GB-s | |
| **Containers total** | 5,256,000 vCPU-s − 200k free = 5,056,000 × €0.00001 = €50.56; 10,512,000 GB-s − 400k free = 10,112,000 × €0.000002 = €20.22 | | **70.8** |
| Managed PG DB-POP2-4C-16G standalone | node €0.1519 + mgmt €0.1347 = €0.2866/h | × 730 | **209.2** |
| PG Block Storage 5K | 200 GB × €0.000136/GB/h × 730 | | **19.9** |
| PG snapshots (7-day retention) | €0.032/GB/mo × retained data | 200 GB full-copy worst case €6.4; budget | **~10** |
| Object Storage Standard Multi-AZ | 300 GB × €0.000022 × 730 | (€3.6 if 75 GB free applies — unverified) | **4.8** |
| Object Storage egress | assume 200 GB × €0.01 | assumption | **2.0** |
| Container Registry | 5 GB × €0.027 | | **0.1** |
| Redis RED1-MICRO standalone | €0.048/h × 730 | | **35.0** |
| DNS: 2 external zones | 2 × €0.007/h × 730 | queries negligible | **10.2** |
| VPC / Private Network / Cockpit (Scaleway data) / IAM | free | | **0** |
| **Total (standalone PG)** | | | **≈ €362/month** |
| Option: PG HA (2 nodes + mgmt) | (2 × 0.1519 + 0.1347) × 730 = €320.1 | +€110.9 | ≈ €473 |
| Option: cheaper 4 vCPU/16 GB class — DB-PRO2-XS standalone (spec inferred from name) | (0.1166 + 0.1034) × 730 | −€48.6 | ≈ €313 |
| Not included | TEM (300 free, then €0.25/1k), Edge Services (€0.99+/mo if used as CDN), Secret Manager (~€0.044/version/mo), cold storage (Glacier €0.0025/GB/mo, One Zone €0.008/GB/mo), any Instance for BAG/PgBouncer (PLAY2-NANO ≈ €20/mo) | | |

Caveats: container costs assume exactly one instance each with no scale-out; the 500 mvCPU + 1 GB pairing is not confirmed as an allowed combination; DB node vCPU/RAM and the node+management billing composition are inferred (see §2); free tiers for Object Storage are unverified. Sources for all unit prices: `https://api.scaleway.com/product-catalog/v2alpha1/public-catalog/products` (SKUs `/paas/caas/*`, `/storage/rdb/*`, `/storage/obj/*`, `/tools/registry/*`, `/storage/redis/*`, `/network/domain/dns/*`, nl-ams localities), pulled 2026-09-03.
