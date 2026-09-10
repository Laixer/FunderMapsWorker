# Hetzner capability matrix (v5 hosting move — alternative check)

Snapshot **2026-09-10**. Same yardstick as `v5-scaleway-capability-matrix.md` and `v5-hostinger-capability-matrix.md`:
DigitalOcean service → Hetzner equivalent, verified against docs.hetzner.com, the Hetzner Cloud OpenAPI spec
(`docs.hetzner.cloud/cloud.spec.json`, 151 paths, 18 resource groups), status.hetzner.com and the hetznercloud
GitHub org. Anything read only from marketing or third-party pages is marked *unverified*. Prices EUR ex-VAT,
Falkenstein/Nuremberg/Helsinki (same price). **No Netherlands or Benelux location** (fsn1, nbg1, hel1, ash, hil, sin).

## FunderMaps read-out (what changes the plan)

**Verdict: conditional no as the 5.0 platform; yes for cheap compute on the side.** Hetzner can host every
component (VMs, private networks, load balancers, S3-compatible storage, free DNS, strong German compliance paper)
but replaces none of the managed layer the plan depends on, and 2026 added two new negatives.

| topic | verdict | consequence for v5 |
|---|---|---|
| **Managed PostgreSQL** | **None** (verified: Cloud API resources = actions, certificates, datacenters, firewalls, floating_ips, images, isos, load_balancer_types, load_balancers, locations, networks, placement_groups, pricing, primary_ips, server_types, servers, ssh_keys, volumes, zones — nothing else) | PG 18 + PostGIS + PgBouncer + pgBackRest → Object Storage, all self-run on a CCX23. Volumes have no snapshots; server backups are 7 daily root-disk images. |
| **Container platform / static sites / registry** | **None** | Coolify or Dokploy on a CPX42 = App Platform on one box you operate; images on GHCR. |
| **2026 price hikes** | **Verified**: 15 June 2026 08:00 CEST, new orders + rescales. CPX32 €13.99→**€35.49**, CPX42 €25.49→**€69.49**, CCX23 €31.49→**€85.99**, CCX33 €62.49→**€138.49**. Legacy price survives only while the server is never rescaled. | "Hetzner is 4× cheaper" is stale. Realistic FunderMaps build ≈ **€210/mo** (CCX23 + CPX42 + backups + LB11 + Object Storage), €150 with a shared-vCPU DB box. |
| **Server rationing** | **Verified, still open**: status notice since 2026-06-26 — "restrict the creation of new cloud servers for both new customers and some of our existing customers … selection … made at random". Cost-Optimized CX/CAX lines not orderable. | A bank-facing API cannot carry "maybe no replacement server today" without a pre-provisioned spare. This alone disqualifies Hetzner as the primary platform right now. |
| **Object Storage** | GA in fsn1/nbg1/hel1; CORS, presigned URLs, lifecycle, versioning yes; **Standard class only** (no cold tier), no custom domains, HDD-based, 750 req/s per bucket; standing timeout notice since 2026-01-15, 42 h fsn1 degradation in March, another 2026-09-07 | Fine for PDFs/uploads and as a pgBackRest target (put it in hel1, away from fsn1 compute); not for hot assets. The KEEPER archive would lose its cold tier. |
| **VPC / LB / TLS** | Networks + Firewalls free; LB11 with HA and health checks; **managed Let's Encrypt only for domains on Hetzner DNS** (verified in the spec) | Works. DNS move becomes step 1 of any migration. |
| **Compliance** | ISO/IEC 27001:2022 (SOCOTEC; NBG/FSN/HEL), **BSI C5 Type 2**, KRITIS §8a, DPA online, TÜV-audited TOMs; no SOC 2; data in DE/FI | Stronger paper than DO for Rabobank/NWWI questionnaires; still no NL residency. |
| **IaC** | hcloud CLI, Partner-tier Terraform provider (18.7 M downloads), DNS in the same API, official k8s CCM + CSI, `setup-hcloud` GitHub Action | Best automation story of the three candidates. The gap is the platform above it. |
| **Support / SLA** | Tickets only for Cloud; 99.9 % "economically reasonable efforts", liability capped at one month, no credits | Thin for a mission-critical API. |
| **What it IS good for** | Hourly boxes (BAG import 2 h/month ≈ €0.12; model runs; CI), an off-provider pgBackRest bucket in hel1, the fallback if Scaleway's managed PG or Serverless Containers disappoint | Use it tactically, not as the platform. |

Versus **DO ≈ $420 ex-VAT** and **Scaleway €362–473**: Hetzner saves ≈ €150–200/mo and removes nothing from the
one-developer burden — the database, deploy layer, TLS and monitoring all become yours. At ~3 h/month of that
work the saving is gone. Scaleway stays the plan.

Verified by hand 2026-09-10: price-adjustment doc (dates + table), status incident 0a75c7ae (rationing, open),
Cloud OpenAPI spec census (0 hits for postgres/kubernetes/container/registry/bucket; "database" hits are label
examples), certificate schema text "Only domains managed by Hetzner DNS are supported".

Below is the full research as delivered (agent run 2026-09-10, ≈45 fetches incl. the OpenAPI spec and status page).

---

# Hetzner as a FunderMaps host — research report (2026-09-10)

Sources: ~45 fetches, mostly docs.hetzner.com / docs.hetzner.cloud (OpenAPI spec) / status.hetzner.com / hetznercloud GitHub. Anything only from third parties is marked **[unverified]**. Prices EUR/month ex-VAT, Falkenstein (fsn1) / Nuremberg (nbg1) / Helsinki (hel1) — same price in all three (eu-central zone). **No Netherlands or Benelux location exists**; the six locations are fsn1, nbg1, hel1, ash, hil, sin ([locations](https://docs.hetzner.com/cloud/general/locations/)).

Three findings that reframe everything, up front:

1. **Hetzner raised cloud prices twice in 2026.** April 1 (+~30% across the board, applied to existing customers too) and **15 June 2026** (new orders/rescales only): CPX ×2.4–2.75, CCX ×2.1–2.7. CCX23 went €31.49 → **€85.99**; CPX32 €13.99 → **€35.49** ([official table](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/), [reason FAQ](https://docs.hetzner.com/general/infrastructure-and-availability/faq-standardization-and-price-adjustment/)). The "Hetzner is 4× cheaper" mental model is stale.
2. **Hetzner is currently rationing cloud servers.** Status notice open since 2026-06-26: "we are currently required to restrict the creation of new cloud servers for both new customers and some of our existing customers. The selection of affected existing customers is made at random." ([status](https://status.hetzner.com/incident/0a75c7ae-3377-41dc-aabe-601063724d24), [FAQ](https://docs.hetzner.com/cloud/general/faq/)). The whole Cost-Optimized line (CX/CAX) shows "not available" on hetzner.com today (verified in page HTML).
3. **Object Storage is under capacity stress.** Open status notice since 2026-01-15 ("high traffic may lead to timeouts"), a 42-hour fsn1 degradation 3–5 March 2026, another fsn1 degradation 7 Sept 2026, and an official FAQ admitting temporary 503 rate limits in NBG and bucket migrations between clusters ([FAQ](https://docs.hetzner.com/storage/object-storage/faq/general/), [incident](https://status.hetzner.com/incident/066d87a3-4529-4344-b16a-3788ca76129b)).

## (a) Summary table — DO service → Hetzner equivalent

| # | DO service today | Hetzner equivalent | Fit | Key constraint | Source |
|---|---|---|---|---|---|
| 1 | App Platform (API, WS, Martin, Windmill, Gotenberg) | None. Cloud VM + self-run Coolify/Dokploy or k3s | **Gap** | No PaaS, no container service; you run the deploy layer | [cloud overview](https://docs.hetzner.com/cloud/servers/overview/), [API spec](https://docs.hetzner.cloud/cloud.spec.json) (no such endpoints) |
| 2 | Static sites (4 SPAs + marketing), deploy-on-push, managed TLS | Coolify/Dokploy static apps, or Caddy on a VM; TLS via Caddy/LB | **Partial** | Self-run; LB managed Let's Encrypt only for domains on Hetzner DNS | [API certificates](https://docs.hetzner.cloud/cloud.spec.json) |
| 3 | Managed PG 18 + PostGIS/Timescale, PITR, pooler | None. Self-host PG on CCX/CPX + pgBackRest → Object Storage | **Gap** | No managed DB at all; Volumes have no snapshots/backups; you own HA/PITR | [volumes](https://docs.hetzner.com/cloud/volumes/overview/), [backups](https://docs.hetzner.com/cloud/servers/backups-snapshots/overview/) |
| 4 | Spaces S3 (CORS, presigned, lifecycle, cold tier) | Hetzner Object Storage (fsn1/nbg1/hel1) | **Partial** | CORS/presigned/lifecycle/versioning yes; single storage class (no cold tier); no custom domains; HDD-based, 750 req/s per bucket, capacity incidents | [supported actions](https://docs.hetzner.com/storage/object-storage/supported-actions/), [CORS](https://docs.hetzner.com/storage/object-storage/howto-protect-objects/cors/), [lifecycle](https://docs.hetzner.com/storage/object-storage/howto-protect-objects/manage-lifecycle/), [overview](https://docs.hetzner.com/storage/object-storage/overview/) |
| 5 | Container registry | None → keep GHCR | **Gap** (cheap workaround) | Not in portfolio | betterstack review [unverified], API spec has no registry |
| 6 | VPC | Cloud Networks (free), Firewalls (free), vSwitch to dedicated | **Yes** | Single network zone per Network; 100 attached resources | [networks](https://docs.hetzner.com/cloud/networks/overview/), [firewalls](https://docs.hetzner.com/cloud/firewalls/overview/) |
| 7 | Scheduled jobs (nightly 45 min; monthly BAG 2 h, 8 GB, 30 GB scratch) | Windmill on your VM; ephemeral CPX server via hcloud for BAG | **Yes** | You schedule it; hourly billing makes an ephemeral 8–16 GB box ~€0.10–0.25 per run | [billing FAQ](https://docs.hetzner.com/cloud/billing/faq/) |
| 8 | DNS (7 zones), uptime checks, metrics/alerting, email | DNS: Hetzner DNS in Console, free, API/Terraform. Uptime: none. Metrics: basic cpu/disk/net via API, no alerting. Email: keep Resend | **Partial** | 25 zones/500 records default; no uptime product; no alert rules | [DNS](https://docs.hetzner.com/networking/dns/overview/), [DNS integrations](https://docs.hetzner.com/networking/dns/migration-to-hetzner-console/features-and-differences/) |
| 9 | EU residency, ISO 27001 | ISO/IEC 27001:2022 (SOCOTEC; NBG, FSN, HEL), **BSI C5 Type 2**, KRITIS §8a, DPA online, TÜV-audited TOMs | **Yes** (Germany/Finland, not NL) | Data in DE/FI; no NL location; no SOC 2 | [certificates](https://docs.hetzner.com/general/others/certificates/), [Zertifizierung](https://www.hetzner.com/unternehmen/zertifizierung/), [data protection](https://docs.hetzner.com/general/company-and-policy/data-protection-at-hetzner/) |
| 10 | GitHub Actions deploy-on-push, API/CLI/Terraform | API + hcloud CLI + terraform-provider-hcloud (Partner tier) + `hetznercloud/setup-hcloud` action; deploy-on-push = Coolify/Dokploy webhooks | **Partial** | IaC is first-class; app deploy pipeline is yours to build | [cli](https://github.com/hetznercloud/cli), [provider](https://registry.terraform.io/providers/hetznercloud/hcloud/latest), [setup-hcloud](https://github.com/hetznercloud/setup-hcloud) |

## (b) Detail A–K

### A. Product lines (2026)
- **Cloud**: servers (CX/CAX cost-optimized — *not orderable now*; CPX regular; CCX dedicated vCPU), Volumes, Networks, Load Balancers, Primary/Floating IPs, Firewalls, Backups/Snapshots, Placement Groups, Apps (one-click images, e.g. Docker CE) — [overview](https://docs.hetzner.com/cloud/servers/overview/). Default limits: 5 servers, 8 dedicated-resource servers, 20 LBs, 30 snapshots (raiseable by ticket).
- **Object Storage**: GA (no beta label on docs; launched 2024), fsn1/nbg1/hel1 only — [overview](https://docs.hetzner.com/storage/object-storage/overview/).
- **Storage Box** (BX11 1 TB … BX41 20 TB; SFTP/SMB/rsync/WebDAV/Borg/restic; DE or FI; snapshots) — [page](https://www.hetzner.com/storage/storage-box/); prices JS-rendered, not captured.
- **Dedicated (Robot)**: AX/EX/SX/DX/GEX lines, now fixed configs (e.g. AX42-1 €97.30 + €49 setup) — [price doc](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/).
- **Managed Server / konsoleH**: Hetzner-managed Debian, no root, Apache/PHP/MySQL/PostgreSQL via panel — not usable for PostGIS/Timescale/containers — [comparison](https://docs.hetzner.com/managed/managed-server/managed-vs-bare-metal-server/).
- **DNS**: in Hetzner Console since Oct 2025, free, in Cloud API — [whats-new](https://docs.hetzner.cloud/whats-new).
- **Managed PostgreSQL: NO. Managed Kubernetes: NO. PaaS/container service: NO. Container registry: NO.** Nothing in the OpenAPI spec, docs, or changelog. Only an "experiments.hetzner.com" AI inference preview (Aug 2026, "not production-ready"). Third parties fill the gap on top of Hetzner (Ubicloud managed PG "from $19/mo" in Hetzner DE DCs, Syself/Cloudfleet managed k8s) [unverified beyond their own pages].

### B. Cloud servers — plan table (post 15 June 2026, official)
Specs from hetzner.com page HTML; prices from the [official adjustment doc](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/). EU = fsn1/nbg1/hel1.

| Plan | vCPU | RAM | NVMe | EU €/mo | US €/mo | SIN €/mo |
|---|---|---|---|---|---|---|
| CPX22 (shared AMD) | 2 | 4 GB | 80 GB | 19.49 | (CPX21 31.99) | 26.49 |
| CPX32 | 4 | 8 GB | 160 GB | 35.49 | (CPX31 62.49) | 48.99 |
| CPX42 | 8 | 16 GB | 320 GB | 69.49 | (CPX41 120.49) | 93.49 |
| CPX52 | 12 | 24 GB | 480 GB | 100.49 | (CPX51 237.99) | 134.49 |
| CCX13 (dedicated AMD) | 2 | 8 GB | 80 GB | 42.99 | 43.49 | 53.99 |
| CCX23 | 4 | 16 GB | 160 GB | 85.99 | 87.49 | 108.49 |
| CCX33 | 8 | 32 GB | 240 GB | 138.49 | 140.99 | 174.49 |
| CX23/CX33/CX43 (Intel/AMD, old gen) | 2/4/8 | 4/8/16 GB | 40/80/160 GB | 5.49/8.49/15.99 | n/a | n/a | **not orderable** |
| CAX11/21/31/41 (Ampere ARM) | 2/4/8/16 | 4/8/16/32 GB | 40–320 GB | 5.99/10.49/20.99/40.99 | n/a | n/a | **not orderable** |

- Traffic: EU plans include ≥20 TB (page text); US 1 TB; SIN 0.5 TB. Overage €1/TB EU [unverified]. Only egress billed ([billing FAQ](https://docs.hetzner.com/cloud/billing/faq/)).
- IPv4 Primary IP **€0.50/mo**, IPv6 free ([servers overview](https://docs.hetzner.com/cloud/servers/overview/)). Floating IPv4 €3/mo, IPv6 €1/mo ([floating IPs](https://docs.hetzner.com/cloud/floating-ips/overview/)).
- Backups: **20% of server price, 7 rolling daily slots**, exclude Volumes (official). Snapshots €0.0143/GB [unverified]. Volumes €0.0572/GB [unverified]; 10 GB–10 TB; up to 5,000 sustained / 7,500 burst IOPS, 200/300 MB/s; **no Volume snapshots or backups** (official).
- Networks free, Firewalls free, Placement Groups free (spread, max 10 servers).
- LB11/21/31: 5/15/30 services, 25/75/150 targets, 10/25/50 certs, 1/2/3 TB traffic, 10k/20k/40k connections; HA with automatic failover; HTTP/HTTPS/TCP, HTTP/2, PROXY protocol, health checks; TLS terminates at LB, LB→target is plain HTTP (or TCP passthrough). LB11 €7.49 [unverified]. **Managed Let's Encrypt certs: "Only domains managed by Hetzner DNS are supported"** (API spec) — otherwise upload your own cert.
- API: 3,600 req/h per project, burst allowed, `RateLimit-*` headers (spec). hcloud CLI v1.67.0 (Jul 2026), terraform-provider-hcloud v1.68.0 (Jul 2026), Terraform Registry tier **partner**, 18.7M downloads, resources incl. zone/zone_rrset/storage_box/managed_certificate. GitHub Actions: `hetznercloud/setup-hcloud`, `hetznercloud/tps-action`. cloud-init supported (Apps built with Packer + cloud-init).
- Existing servers keep old prices as long as you never rescale (rescale = new order at new price).

### C. Managed PostgreSQL — none
Consequences for FunderMaps (70 GB, PostGIS 3.5 + TimescaleDB + pg_trgm, PITR, PgBouncer):
- Self-host on **CCX23** (4 dedicated vCPU / 16 GB / 160 GB local NVMe) — local NVMe is faster than a Volume and the 70 GB DB fits; add a Volume only for headroom. PgBouncer as a sidecar on the same box.
- Backups: Hetzner server Backups snapshot the root disk daily (crash-consistent, 7 slots) — acceptable as a last-resort image, **not** a PITR strategy. Real answer: **pgBackRest → Hetzner Object Storage** (standard S3 repo config works; community reports it with `repo-s3-endpoint=nbg1.your-objectstorage.com` [unverified]); full weekly + incremental daily + WAL archive gives PITR. Test restores yourself.
- HA: single node + pgBackRest is the honest one-dev setup. Patroni (2 PG + 3 etcd) or CloudNativePG on k3s buys automatic failover at 2–3× compute and a serious operational tax. Ubicloud's managed PG in Hetzner DE DCs is the only "managed" option, and it is a third-party contract [unverified].
- Compare: on DO/Scaleway you get PITR + failover + pooler by ticking boxes.

### D. Object Storage
- GA, fsn1/nbg1/hel1 (US/SIN excluded). Endpoint `<bucket>.fsn1.your-objectstorage.com`, path-style also works. Data of a bucket sits in a **single data center**, erasure-coded across servers (survives 3 server failures); no cross-location replication (do it with rclone + cron).
- Pricing: base fee with 1 TB storage + 1 TB egress included; overage per TB-hour and €1/TB egress; ingress and S3 calls free; min billable object 64 KB (official structure). Base fee **€6.49/mo** since April 2026 [unverified; launch price €4.99 per Hetzner news]. 250 GB fits entirely in the base fee.
- Features (official): CORS yes, presigned URLs yes, lifecycle (Expiration, NoncurrentVersionExpiration/NoncurrentDays only, AbortIncompleteMultipartUpload) yes, versioning yes, object lock yes, SSE-C only, bucket policies not listed as exception (so presumably supported). **Not supported**: custom domains, replication, tagging, notifications, logging, website hosting, Intelligent Tiering. **Storage classes: Standard only** — no cold tier equivalent.
- Limits: 100 buckets, 100 TB/bucket, 50M objects, 5 GB single PUT, **750 req/s per bucket and per source IP**, 256 parallel sessions per IP, 200 credentials. Bucket names are unique Hetzner-wide.
- Hetzner's own guidance: HDD-based, "not a CDN", not for many <1 MB files at high frequency, prefer files ≥1 MB, use multipart >100 MB. Ongoing capacity incidents (see top). For FunderMaps' report PDFs/uploads this is fine; for hot tile assets it is not (tiles are on Martin now anyway).

### E. Kubernetes and PaaS
- No managed k8s. Official pieces: `hcloud-cloud-controller-manager` v1.36.0 (LB + private-network routes) and `csi-driver` v2.23.0 (RWO Volumes, k8s ≥1.19) — both actively maintained (pushed this week). `kube-hetzner` (3.9k stars, v3.2.1, k3s/RKE2 on openSUSE Leap Micro, HA, autoscaler) and `hetzner-k3s` (3.7k stars) are solid community installers.
- PaaS on a VM: Coolify (61.6k stars) and Dokploy (37k stars) both target Hetzner explicitly (Coolify has a Hetzner promo page). Either gives Dockerfile/Nixpacks builds from GitHub push, static sites, Let's Encrypt, env/secrets — i.e. roughly App Platform on one box.
- Honest read for one dev: k3s adds a control plane, CNI, ingress, cert-manager, CSI, upgrades and etcd to babysit — for 5 containers that is negative value. Coolify/Dokploy on one CPX/CCX is the realistic path; it is one more thing that can break at 03:00 and it is yours.

### F. Monitoring/alerting
Console shows cpu/disk/network graphs; API exposes `/servers/{id}/metrics` (cpu, disk, network) and `/load_balancers/{id}/metrics` (spec). No alert rules, no uptime checks, no log product. Cost alerts by email only. → External: Better Stack/UptimeRobot for uptime (your existing status-page plan), Grafana + node_exporter/postgres_exporter for metrics (analytics-prod already exists).

### G. DNS
Hetzner DNS inside Hetzner Console, **free**, 25 zones / 500 records per zone default (raiseable), record types A/AAAA/CAA/CNAME/DS/HTTPS/MX/NS/PTR/SRV/SVCB/TLSA/TXT, secondary zones with TSIG, protection flags. In the Cloud API (`/zones`, rrsets), official support in hcloud CLI, terraform-provider-hcloud ≥1.54, Ansible `hetzner.hcloud`, official external-dns and cert-manager webhooks ([features](https://docs.hetzner.com/networking/dns/migration-to-hetzner-console/features-and-differences/)). Old DNS Console/API shut down May 2026 [unverified]; the community `hetznerdns` Terraform providers are for the old API — use `hcloud_zone`. **DNSSEC**: DS records can be stored, but no statement that Hetzner signs zones — treat as unsupported until proven [unverified].

### H. Compliance / security / company
- Hetzner Online GmbH, Industriestr. 25, 91710 Gunzenhausen; HRB 6089 Ansbach; MDs Martin Hetzner, Stephan Konvickova, Günther Müller ([legal notice](https://www.hetzner.com/legal/legal-notice/)). Founded 1997, family-owned, ~€367M revenue (2021, Wikipedia [unverified]). Owns its DC parks in Nuremberg, Falkenstein, Helsinki (Tuusula); US/SIN are colocation.
- **ISO/IEC 27001:2022** (SOCOTEC) covering all hosting services and the NBG/FSN/HEL DCs; **BSI C5 Type 2**; KRITIS §8a BSIG; PCI DSS via Computop; no SOC 2 by choice ([certificates](https://docs.hetzner.com/general/others/certificates/)). C5 Type 2 is the German banking-grade attestation — a genuine plus when talking to Rabobank/NWWI.
- DPA (Art. 28) concluded online in the account; sub-processor list PDF; TOMs audited yearly by TÜV Rheinland with report in the portal; master data always EU; authority requests only via German/Finnish courts for EU DCs.
- DDoS protection free for all customers, Arbor/Nokia/Juniper, multi-layer scrubbing ([DDoS](https://www.hetzner.com/unternehmen/ddos-schutz/)).
- Reputation: KYC on first order (iDenfy partnership, March 2026 [unverified]); long-running pattern of unexplained account locks/"decision is final" for new accounts (LowEndTalk/HN threads, [unverified], mostly individuals). Incidents 2026: Object Storage fsn1 degraded 42 h (Mar), rationing of cloud servers since June, Object Storage timeouts since Jan, HEL1-DC4 switch fault Aug 21 [unverified]. Betterstack's claim "no ISO 27001" is wrong per Hetzner's own docs.

### I. SLA and support
T&C §3.3: "economically reasonable efforts to achieve an annual average network availability of 99.9%"; liability capped at one month's rent (§9.1); no service credits. Cloud support = tickets in Console; phone Mon–Fri 08–18 CET for general/billing; 24/7 phone technicians only for dedicated/colocation ([support](https://www.hetzner.com/support/)). No response-time commitments, no paid support tiers.

### J. Cost model (EUR/mo ex-VAT, fsn1, post-June prices)

**Option 1 — "like-for-like-ish" VMs + Coolify/Dokploy**

| Item | Spec | €/mo |
|---|---|---|
| DB host CCX23 | 4 ded. vCPU / 16 GB / 160 GB NVMe | 85.99 |
| DB Backups (20%) | 7 daily images | 17.20 |
| Volume 150 GB (pgBackRest spool / headroom) | | 8.58 [unverified rate] |
| App host CPX42 | 8 vCPU / 16 GB / 320 GB — API, WS, Martin, Windmill, Gotenberg, Coolify, 5 static sites | 69.49 |
| App Backups (20%) | | 13.90 |
| LB11 (TLS, HA front door) | | 7.49 [unverified] |
| Object Storage base (250 GB, ≤1 TB egress) | | 6.49 [unverified] |
| 2 × IPv4 | | 1.00 |
| Snapshots ~40 GB | | 0.57 [unverified] |
| Ephemeral CPX32 for BAG import (2 h/mo) | | 0.12 |
| Networks, firewalls, DNS | | 0 |
| **Total** | | **≈ €211** |

**Option 1-lite** (CPX32 for DB, shared vCPU, 8 GB — same as DO today): ≈ €150.
**Option 2 — one dedicated AX42-1** (8c Ryzen 8700GE, 64 GB ECC, 2×512 NVMe, unlimited 1 Gbit): €97.30 + €49 setup, + IPv4, + Object Storage 6.49 ≈ **€105–110**, everything on one box (pure SPOF, Robot not Cloud API, hardware swap = hours).
**Option 3 — k3s (kube-hetzner)**: 3 × CPX32 + CCX23 DB node + LB11 ≈ €300 and the most work.

Versus **DO ≈ €390** and **Scaleway €362–473**: Option 1 saves ~€180/mo (~€2.1k/yr). Before June it would have saved ~€300/mo. **Not covered by any of these numbers**: managed PG (PITR, failover, pooler, patching), uptime checks/alerting (≈€0–25 external), a PaaS (your time), container registry (GHCR free), and the developer-hours to build and keep the above alive — at even 3 h/month the saving is gone.

### K. Migration architecture and burden
- **Shape**: fsn1 project; private Network 10.0.0.0/16; Firewall (22 from Tailscale only, 80/443 from LB only). LB11 → `apps` (CPX42) running Coolify/Dokploy: `fundermaps-api`, `fundermaps-ws`, `martin`, `windmill` (+ its own PG or the main one), `gotenberg`, 5 static sites with Caddy; `db` (CCX23) PG 18 + PostGIS + Timescale + PgBouncer, only on the private net; pgBackRest to a hel1 bucket (different location from fsn1 compute = cheap geo-separation); Hetzner DNS for the 7 zones so LB managed certs work; GHCR for images; GitHub Actions → Coolify webhook. Windmill schedules nightly refresh; BAG import = `hcloud server create --type cpx32 --user-data …` from Windmill, deleted after.
- **SPOFs**: the DB box (no failover), the apps box (all services), Coolify itself, the fsn1 location (Object Storage bucket is single-DC too), and Hetzner capacity policy (you might be unable to create a replacement server on a bad day — that is new and real).
- **Burden for one dev**: OS patching + reboots for 2 VMs, PG major/minor upgrades and extension builds, pgBackRest restore drills, Coolify upgrades, cert hygiene if any zone stays outside Hetzner DNS, capacity/disk growth, and on-call for all of it with ticket-only support. Scaleway with managed PG + Serverless Containers removes the DB, the PaaS and TLS from that list; Hetzner removes nothing — it only lowers the invoice.

## (c) What changes the plan
- Hetzner's price advantage over Scaleway shrank to roughly €150–200/mo after the 2026 hikes; at pre-June prices this would have been a much easier call.
- Cloud-server rationing since June (random existing customers included) is a supply risk a bank-facing API should not carry without a pre-provisioned spare.
- Object Storage has had two multi-hour fsn1 degradations in 2026 and a standing timeout notice; put the pgBackRest repo in hel1 and keep uploads modest, or keep DO Spaces for a while.
- Cost-Optimized (CX/CAX) is not orderable; budget with CPX/CCX only.
- Existing servers keep their price only while never rescaled — vertical scaling later means paying the new rate.
- No managed PG anywhere in the portfolio; PITR is pgBackRest you operate, and Volumes cannot be snapshotted.
- LB managed TLS requires the zones on Hetzner DNS — the DNS move becomes step 1 of the migration, not an afterthought.
- BSI C5 Type 2 + ISO 27001:2022 + online DPA is stronger paper than DO offers for Dutch banks; no NL location remains (Germany/Finland only).
- IaC is genuinely good (Partner Terraform provider, hcloud CLI, DNS in the same API, official k8s CCM/CSI) — the gap is the platform layer above it, not automation.
- Support is tickets; 99.9% is a best-efforts clause with no credits.
- Ephemeral hourly boxes make the monthly BAG import and any benchmark almost free — a real workflow win.
- A single AX42 dedicated box at ~€110 is the cheapest possible FunderMaps, and also the least defensible architecture to show a bank.

## (d) Verdict
**Conditional no for the current platform plan; yes as a compute/dev sandbox.** Hetzner can host every FunderMaps component technically (VMs, private network, LB, S3-compatible storage, free DNS, strong German compliance paper), and even after the 2026 price hikes lands around €210/mo against Scaleway's €362–473. But it substitutes nothing for DO's or Scaleway's managed layer: no managed PostgreSQL, no container platform, no uptime checks, and this year it added two new negatives — rationed server creation and a strained Object Storage — that hit exactly the "mission-critical, banks call it" property. For a one-developer team whose whole 5.0 plan is fewer moving parts, moving the database and deploy layer from managed to self-run to save ~€150–200/mo is the wrong trade. Where Hetzner does make sense: cheap hourly boxes for BAG/model runs and CI, a hel1 bucket as an off-provider pgBackRest target, and as the fallback if Scaleway's managed PG or Serverless Containers disappoint in the trial. If Scaleway is rejected, the least-bad Hetzner build is Option 1 (CCX23 + CPX42 + LB11 + Coolify/Dokploy + pgBackRest→hel1), with the DNS move first and a written restore drill before any customer traffic.