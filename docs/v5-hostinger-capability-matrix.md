# Hostinger capability matrix (v5 hosting move — alternative check)

Snapshot **2026-09-10**. Same yardstick as `v5-scaleway-capability-matrix.md`: DigitalOcean service →
Hostinger equivalent, verified against Hostinger's support KB, legal pages, the public OpenAPI spec
(`developers.hostinger.com/openapi/openapi.json`, v1.50.0, 299 paths) and the status page. Anything read
only from marketing or third-party pages is marked *unverified*. Prices EUR ex-VAT, 24-month term.

## FunderMaps read-out (what changes the plan)

**Verdict: not a Scaleway alternative.** Hostinger is a KVM VPS reseller with a real API; it has none of
the managed layer FunderMaps 5.0 is built on. Five of the ten services we use on DO are outright gaps.

| topic | verdict | consequence for v5 |
|---|---|---|
| **Managed PostgreSQL** | **None** (verified: 0 database products in the API outside shared-hosting MySQL) | PG 18 + PostGIS + PgBouncer + pgBackRest → external S3, HA, PITR, upgrades: all self-run on a KVM VPS. No block storage; KVM 8 (400 GB NVMe) is the largest plan. |
| **Object storage** | **None** (verified: 0 `s3`/`bucket`/`object-storage` endpoints) | A second provider (Hetzner Object Storage, Scaleway, B2) is required regardless → Hostinger can never be single-vendor. |
| **VPC / private network** | **None** (verified: 0 `vpc`/`private-network`/`volume` endpoints) | DB ↔ app traffic over public IPs; WireGuard + firewall CIDR allow-lists, or everything on one box. |
| **Netherlands location** | **Not for VPS** (verified, KB: "Servers in the Netherlands … are not available for VPS, only for web and cloud plans") | Nearest EU VPS: Frankfurt (Digital Realty), Paris, Vilnius, Manchester. Location is permanent; moving = reinstall, data + backups deleted. |
| **PaaS / static sites / registry / LB** | None; Docker Manager (experimental) or Coolify/Dokploy template on your VM | Deploy-on-push = GitHub Actions → GHCR → Coolify webhook. Static SPAs served by Caddy on the VM. CDN "not available for VPS". |
| **Backups** | Weekly image, 2 retained (free); daily = US$6/mo, 2 retained; 1 snapshot, 1-day expiry; not downloadable | Disk images only, not exportable → the only DR that counts is your own pgBackRest to external S3. |
| **CPU policy** | Automatic **−25 %/h throttling** on sustained high CPU, manual reset once a week (KB) | Fights the monthly 2 h BAG import and the 45-min nightly refresh on a shared-CPU box. |
| **IaC** | API v1.50 (90 req/min), Go CLI, official Terraform provider v0.1.22 (VPS, SSH key, post-install, DNS; no firewall) | Thin but real. VM creation is a purchase flow that may end "complete in hPanel manually". |
| **Compliance** | ISO/IEC 27001 (TÜV Thüringen); **no SOC 2**; DPA entity in Cyprus, Cyprus law; sub-processors AWS/GCP/Cloudflare/Anthropic | Bank and municipality questionnaires will ask about NL residency (impossible for VPS) and SOC 2. |
| **SLA / support** | 99.9 %, credit 5 % of monthly fee to future purchases; 24/7 chat (AI first), no phone, no enterprise tier | Thin for a bank-facing API. |
| **Cost** | KVM 8 + KVM 4 + daily backups + external S3 ≈ **€97/mo** at renewal (24-mo prepay ≈ €800 up front), ≈ €120/mo on monthly terms; promo €52/mo first term | ≈ 4× cheaper than DO (~$420 ex-VAT) and Scaleway (€362–473) — the saving is exactly the managed DB, S3, VPC, PITR and PaaS you no longer get, plus ~4–8 h/month of DBA/ops for one developer. |

If price is the driver, the honest budget comparison is **Hetzner** (Falkenstein/Nuremberg: object storage, private
networks, volumes, load balancers), not Hostinger. Scaleway stays the plan.

Verified by hand 2026-09-10: OpenAPI keyword census (`postgres` 2 hits = shared-hosting MySQL/agency schemas; `bucket`,
`s3`, `registry` hits are WHOIS/mail text, not products; `vpc`, `private-network`, `object-storage`, `load-balancer` = 0);
the "Europe (Netherlands)" example in the spec belongs to `AgencyHosting…DatacenterResource`, not `VPS…DataCenter`; the
server-locations KB page quoted above.

Below is the full research as delivered (agent run 2026-09-10, ≈50 fetches + OpenAPI spec + status-page JSON).

---

Research complete (≈50 fetches/searches plus a direct pull of Hostinger's OpenAPI spec and status-page JSON). Here's the report.

---

# Hostinger as a FunderMaps host — feasibility report (2026-09-10)

Legend: **[V]** = read on hostinger.com / support / docs / API spec / statuspage; **[U]** = only from marketing copy or third-party pages. Prices are **EUR, ex-VAT** (the NL page footer states "De getoonde prijzen zijn exclusief btw" [V]), 24-month term unless stated.

## (a) Summary table

| DO service today | Hostinger equivalent | Fit | Key constraint | Source |
|---|---|---|---|---|
| App Platform (Bun API, product API, Martin, Windmill, Gotenberg) | KVM VPS + Docker Manager / Coolify / Dokploy template | Partial | No PaaS; you run Docker on a VM. Docker Manager API is marked "experimental" [V]. No autoscaling, no zero-downtime deploy primitive | https://docs.hostinger.com/api-reference/endpoints/vps/docker-manager ; https://www.hostinger.com/support/1583571-what-are-the-available-operating-systems-for-vps-at-hostinger/ |
| Static sites (4 SPAs + marketing, deploy-on-push, custom domains, TLS) | None for VPS. Serve from a reverse proxy on the VPS, or external (Cloudflare Pages) | Gap | No static-site product with git deploy outside shared hosting; Hostinger CDN "is not available for VPS" [V] | https://www.hostinger.com/support/hostinger-cdn-vs-cloudflare/ |
| Managed PostgreSQL 18 + PostGIS/Timescale, backups+PITR, pooler | **None.** Self-host PG on a KVM VPS | Gap | No managed DB product outside shared-hosting MySQL. Backups/PITR/HA/pooler = DIY. Weekly VPS image backup, 2 retained; daily = US$6/mo add-on, 2 retained; 1 snapshot, expires after 1 day [V] | https://www.hostinger.com/support/1583232-how-to-back-up-or-restore-a-vps-at-hostinger/ ; https://www.hostinger.com/support/1665153-how-to-activate-daily-backups |
| S3 object storage (250 GB, CORS, presign, lifecycle) | **None.** "RustFS" is a self-hosted Docker template on your own VPS [V] | Gap | Zero `s3`/`object storage` in the API spec. Need Hetzner Object Storage / Scaleway / B2 | https://www.hostinger.com/applications/rustfs ; https://developers.hostinger.com/openapi/openapi.json |
| Container registry | None | Gap | Use GHCR | (absence: OpenAPI spec, 299 paths, no registry) |
| Private VPC | **None.** No private network, VPC, private IP, floating IP or volume resources in the API [V] | Gap | DB↔app traffic crosses public IPs; need WireGuard/Tailscale + firewall CIDR allow-lists, or a single box | OpenAPI spec (0 hits for "private network", "vpc", "block storage", "load balancer") |
| Scheduled jobs (nightly 45 min; monthly 2 h BAG, 30 GB scratch, 8 GB RAM) | Cron/Windmill on the VPS | Partial | Sustained high CPU triggers **automatic 25 %/hour CPU throttling** (limit liftable once/week in hPanel) [V]. Disk is fixed to plan (no block storage) | https://www.hostinger.com/support/6899741-what-is-the-cpu-use-limit-for-vps-at-hostinger/ |
| Managed DNS (7 zones), uptime checks, metrics/alerts | DNS: yes (free, API + Terraform). Uptime/alerting: no for VPS | Partial | DNSSEC "not supported" on Hostinger nameservers [V]. hPanel "Monitoring" covers Hostinger-hosted *websites* only, max 10 alerts [V]. VPS has metrics API but no documented alerting | https://www.hostinger.com/support/3667267-how-to-use-dnssec-records-at-hostinger/ ; https://docs.hostinger.com/websites/monitoring |
| Compliance (EU residency, ISO 27001) | ISO/IEC 27001 (TÜV Thüringen), GDPR DPA with EU SCCs; **no SOC 2** listed | Partial | **Netherlands is NOT a VPS location** per the KB [V] (contradicted by NL marketing page — see H). Nearest: Frankfurt (Digital Realty). DPA entity is Cyprus (Hostinger International Ltd), Cyprus law | https://www.hostinger.com/support/1583267-where-are-hostinger-servers-located/ ; https://trust.hostinger.com/ ; https://www.hostinger.com/legal/dpa |
| Deploy: GH Actions, API, CLI, Terraform | API (363 endpoints, v1.50.0), Go CLI, PHP/Python/TS SDKs, MCP server, official Terraform provider v0.1.22 | Partial | Terraform: VPS, SSH key, post-install script, DNS only — no firewall resource. `POST /vps/v1/virtual-machines` is a *purchase* and can return 202 "complete in hPanel manually" [V]. 90 req/min/IP | https://docs.hostinger.com/api-reference/overview.md ; https://github.com/hostinger/terraform-provider-hostinger |
| Load balancer / managed TLS / CDN / DDoS | None / DIY (Caddy, Traefik) / not for VPS / "Wanguard" filtering | Partial | Marketing mentions of "load balancer" are third-party fluff; API has none. Firewall is inbound-only, CIDR sources, ~2 min propagation [V] | https://www.hostinger.com/support/8172641-how-to-use-a-managed-vps-firewall-at-hostinger/ |
| SLA / support | 99.9 % uptime, credit = 5 % of monthly fee to future purchases, claim within 30 days; 24/7 chat (AI first) + email, no phone, no enterprise tier | Partial | Excludes DDoS; VPS support scope stops at infrastructure [V] | https://www.hostinger.com/legal/hosting-agreement ; https://www.hostinger.com/support/1583780-how-to-contact-hostinger-support/ |

## (b) Detail A–K

### A. Product lines (what exists vs. marketing)
- **Web/shared hosting** (Premium/Business), **"Cloud hosting"** = shared hPanel hosting with more resources; **no root, no Docker, no Bun** [V]. https://www.hostinger.com/cloud-hosting
- **Managed WordPress / WooCommerce / Agency hosting** — hPanel products, irrelevant here [V].
- **KVM VPS** — the only product with root/Docker [V].
- **Horizons** — AI web-app builder; merged into "Hostinger AI Builder" on 2026-08-18 [U, cybernews/vibecoding]. Not infrastructure.
- **Container/PaaS product:** none. "Docker Manager" is a Compose UI/API on your own VPS, flagged *experimental* [V].
- **Managed database:** none outside shared-hosting MySQL (the API's "database" endpoints are `hosting_*` = shared plans) [V].
- **Object storage:** none [V]. **Kubernetes:** none — only tutorials [V].
- Status page lists no per-DC VPS components, only "Hostinger VPS API" [V]. https://statuspage.hostinger.com/

### B. VPS
Plans (NL page, EUR ex-VAT, 24-month term) [V] https://www.hostinger.com/nl/vps-hosting :

| Plan | vCPU | RAM | NVMe | BW | Promo /mo | **Renewal /mo** | Struck-through "list" price |
|---|---|---|---|---|---|---|---|
| KVM 1 | 1 | 4 GB | 50 GB | 4 TB | €5.49 | **€11.99** | €17.99 |
| KVM 2 | 2 | 8 GB | 100 GB | 8 TB | €7.99 | **€14.99** | €21.99 |
| KVM 4 | 4 | 16 GB | 200 GB | 16 TB | €10.99 | **€27.99** | €35.99 |
| KVM 8 | 8 | 32 GB | 400 GB | 32 TB | €21.99 | **€49.99** | €64.99 |

- Renewal text: "Wordt verlengd voor € X/mnd voor 2 jaar" — renewal is also a 2-year prepay [V]. "Alle plannen worden vooraf betaald" [V].
- Terms: KVM VPS billing periods are **1, 12 or 24 months** [V] https://www.hostinger.com/support/1583589-how-to-pay-for-hostinger-services-in-advance/ . Monthly/12-month prices are not on the site (JS cart). The struck-through prices above are very likely the 1-month rate **[U]**; vpsbenchmarks lists KVM 8 at US$73.99/mo monthly, US$53.99 yearly [U] https://www.vpsbenchmarks.com/hosters/hostinger/plans/kvm-8 .
- **KVM 8 is the largest plan; "can't be upgraded, as they are the highest tier"** [V] https://www.hostinger.com/support/1583229-how-to-upgrade-a-vps-server/ . No dedicated-CPU tier; vpsbenchmarks marks CPU "shared" [U]. Upgrades are in place (~10 min, data kept) [V]; downgrade not documented.
- **Data centres for VPS:** France (Paris, FR-INT), Germany (Frankfurt DE-FRA, Düsseldorf DE-DUS), Lithuania (Vilnius), UK (Manchester), India, Indonesia, Malaysia, US Phoenix/Boston, Brazil [V, KB + statuspage components]. **"Servers in the Netherlands … are not available for VPS, only for web and cloud plans"** [V]. Frankfurt = Digital Realty facility, launched 2024-10-08 [V] https://www.hostinger.com/blog/frankfurt-data-center/ . Location can't be changed after setup — only reinstall, which "will permanently delete all existing data, including backups and snapshots" [V] https://www.hostinger.com/support/10289743-how-to-transfer-your-vps-to-a-different-location-in-hostinger/
- **Backups:** weekly free, 2 retained; daily add-on US$6.00/mo, 2 retained; **1 snapshot, overwritten on create, expires after 1 day**; "Downloading backups or snapshots directly to a local device is not supported" [V]. Backup location example in API: `nl-srv-nodebackups` [V]; "stored in Lithuania" claim is [U].
- **Private networking:** none [V, API]. **Firewall:** managed, inbound-only, TCP/UDP/ICMP/GRE + presets incl. PostgreSQL, CIDR sources, default drop, API-managed [V]. **IPs:** one IPv4 + IPv6 per VM (`ipv6` field in API) [V]; no additional IPs [U]. **1 Gbps port** [V marketing].
- **Templates:** Ubuntu 22.04/24.04/26.04, Debian 11–13, Alma/Rocky 8–10, NixOS, plus Docker, Coolify, Dokploy, Portainer, Dokku, n8n, Supabase, Windmill (Docker catalog) [V]. No custom ISO [V].
- **API/CLI/Terraform:** base `https://developers.hostinger.com/api`, Bearer token, **90 req/min/IP**, SDKs PHP/Python/TS, Go CLI (`brew install hostinger/tap/hostinger`), MCP server `@hostinger/mcp` [V]. Terraform `hostinger/hostinger` v0.1.22, official, resources: vps, vps_ssh_key, vps_post_install_script, dns zone/records; **no firewall/snapshot resources** [V].

### C. Managed PostgreSQL
**None.** Plainly: Hostinger sells no managed Postgres or MySQL outside shared hosting. Implications: PG 18 + PostGIS + Timescale on a KVM 8; backups via pgBackRest/WAL-G to *external* S3 (Hostinger's own backups are whole-disk images, 2 copies, not exportable); PITR, failover, pooler (PgBouncer), minor upgrades, vacuum tuning, disk monitoring — all yours. **No block storage**: 400 GB is the ceiling for DB + WAL + 30 GB BAG scratch.

### D. Object storage
**None.** RustFS/MinIO template = you host it, on plan NVMe, with plan-level backups (see B). Not acceptable for 250 GB of customer uploads. External: Hetzner Object Storage, Scaleway, Backblaze B2 (prices below are from memory, **[U]**).

### E. LB / TLS / CDN / DDoS
No LB, no floating IP [V API]. TLS: Docker Manager auto-HTTPS only for a handful of catalog apps; otherwise Caddy/Traefik/Coolify + Let's Encrypt (DIY). **CDN not available on VPS** [V]. DDoS: "Wanguard DDoS-filtering" on the product page [V wording, capacity U]; managed firewall explicitly "not intended to block … DDoS" [V]. SLA excludes DDoS [V].

### F. Monitoring
hPanel Server Usage: CPU/RAM/disk/traffic, 24h–1y views; API `GET …/metrics` (CPU, memory, disk, network, uptime) [V]. **No documented VPS alerting or uptime checks**; the "Monitoring" product = Hostinger-hosted websites, ≤10 alerts [V]. Keep Grafana + an external pinger (Better Stack).

### G. DNS
Free zones for external domains pointed at `*.dns-parking.com` NS [V]; API: `GET/PUT/DELETE /dns/v1/zones/{domain}`, reset, validate, snapshots+restore (8 endpoints) [V]; Terraform DNS resources [V]. **DNSSEC not supported** [V]. Anycast/POPs: not stated [U].

### H. Compliance / ownership / incidents
- ISO/IEC 27001 via TÜV Thüringen, cert 1512124260 (blog Sept 2024 says 27001:2017; Trust Center says :2022) [V]. **No SOC 2** on the Trust Center [V]. Sub-processors: AWS EMEA, Google Cloud EMEA, Cloudflare, MailChannels, Proofpoint, **Anthropic Ireland**, spectra tech UAB; DPA entity Hostinger International Ltd (Cyprus) / UK Ltd / Global S.à r.l (Lux); Cyprus law; breach notice "without undue delay" [V] https://www.hostinger.com/legal/dpa
- **NL DC:** status page component "NL-SRV Shared/Cloud servers (Amsterdam, NL)" [V]; operator not published. The NL VPS page advertises "Datacenters in Amsterdam" as a plan feature [V wording] while the KB says NL is not a VPS location — **confirm the hPanel dropdown before buying**.
- **Ownership:** founded Kaunas 2004, HQ Vilnius; ConHostinger GmbH (Equivia-backed, Cologne) ~30–31 % since 2021; rest founders/team; Tesonet early investor; CEO Giedrius Zakaitis; 2025 revenue €275 M [V about page + U Wikipedia]. **Kilo Health is not an owner** — that premise was wrong.
- **Incidents:** 2019 breach, ~14 M customers (API token) [U, TechCrunch]. Statuspage last 50 incidents (Aug 14 – Sep 9 2026): 42 none/6 minor/2 major (Sep 8 "Increased Mail Queue", Sep 2 "Horizons Downtime"); the rest are per-server shared-hosting emergencies (IN/ID/BR/DE/FR) [V]. StatusGator counts 128 incidents/90 days, 9 major [U]. No VPS-network incident found for 2025–26; also no VPS components on the status page, so absence proves little.

### I. SLA & support
99.9 %/month; credit 5 % of monthly fee, future purchases only, claim ≤30 days; exclusions include DDoS, ISP, third-party apps [V]. Support: 24/7 chat (Hostinger Agent AI first, human "Customer Success Specialist" can join), WhatsApp, email; **no phone, no priority/enterprise tier, no response-time commitment** [V]. Scope for VPS = infrastructure [U]. Refunds: 30 days incl. KVM renewals; upgrades non-refundable; 180-day cooldown after a VPS refund [V].

### J. Cost model (EUR ex-VAT; add 21 % for NL BTW)

| Item | Renewal, 24-mo term | Promo first 24 mo | Monthly term [U] |
|---|---|---|---|
| KVM 8 (DB, Frankfurt) | €49.99 | €21.99 | ~€64.99 |
| KVM 4 (apps: API, WS, Martin, Windmill, Gotenberg, static) | €27.99 | €10.99 | ~€35.99 |
| Daily backups ×2 (US$6 each) | ~€11 | ~€11 | ~€11 |
| External S3 250 GB (Hetzner OS ~€6 / Scaleway ~€4 / B2 ~€2) [U] | ~€6 | ~€6 | ~€6 |
| Off-site PG backups (pgBackRest → S3, ~100 GB) [U] | ~€2 | ~€2 | ~€2 |
| Uptime/alerting (Better Stack free) | €0 | €0 | €0 |
| **Total** | **≈ €97/mo** (≈ €117 incl. VAT) | **≈ €52/mo**, but **€792 prepaid** for 2 years of VMs | **≈ €120/mo** |

Optional: third VM (KVM 2, €14.99) to isolate Windmill/jobs: **≈ €112/mo**. Versus **DO ~€400** and **Scaleway €362–473**: roughly **4× cheaper** — but the €300/mo you save is exactly the managed DB, managed S3, VPC, LB, PITR, and PaaS you no longer get. Not covered: managed PG, S3, registry, VPC, LB, static hosting, alerting.

### K. Migration feasibility
**Shape:** KVM 8 (Frankfurt) = PostgreSQL 18/PostGIS/Timescale + PgBouncer + pgBackRest→external S3. KVM 4 (same DC) = Coolify or Dokploy (both are Hostinger templates) running the Bun API, product API, Martin, Windmill (+ its own PG or shared), Gotenberg, and Caddy serving the 4 SPAs + marketing site from GHCR-built images; deploy-on-push via GitHub Actions → Coolify webhook. DB reachable only via WireGuard between the two VMs + Hostinger firewall rule allowing 5432 from the app VM's public IP. Object storage external (Hetzner/Scaleway) with CORS + presign. DNS on Hostinger (no DNSSEC) or stay on DO/Cloudflare.

**Single points of failure:** one DB VM (no HA, no floating IP, disk fixed at 400 GB, 1-day snapshot); one app VM hosting the bank-facing product API; the DC choice is permanent; **CPU auto-throttle at −25 %/h on "sustained high usage"** with a once-a-week manual reset — a 2 h BAG import or a PostGIS refresh on a shared-CPU box is a plausible trigger; abuse-team suspensions without warning are a recurring third-party complaint [U].

**Operational burden for one developer:** you become the DBA, backup operator, network engineer (WireGuard), TLS operator, and on-call for a VM class where support ends at the hypervisor. Realistically +4–8 h/month steady state plus a DR runbook you must test yourself.

## (c) What changes the plan (read-out)
1. **No Netherlands VPS location** per Hostinger's KB — closest EU is Frankfurt (Digital Realty). Marketing page says otherwise; verify in hPanel before committing.
2. **No managed Postgres, no S3, no VPC, no LB, no registry** — five of the ten DO services are outright gaps, not partial fits.
3. Object storage must go to a *second* provider anyway (Hetzner/Scaleway/B2), so Hostinger can never be the single vendor.
4. KVM 8 (8 vCPU/32 GB/400 GB) is the ceiling; no bigger plan, no block storage, no dedicated CPU tier.
5. Sustained-CPU throttling policy (−25 %/h) is incompatible with a monthly 2 h ETL on the DB host unless you accept the risk or split/throttle the job.
6. Backups are 2-copy disk images you can't export; the only DR that counts is your own pgBackRest to external S3.
7. Cheapest price requires 24-month prepay (~€800 up front) and renews at 2× promo; the 1-month term is roughly the struck-through "list" price.
8. IaC exists and is real (API v1.50, official Terraform, CLI, SDKs) but thin: no firewall in Terraform, Docker Manager "experimental", VM creation = purchase flow.
9. No SOC 2; ISO 27001 yes; DPA governed by Cyprus law with AWS/GCP/Cloudflare/Anthropic as sub-processors — bank/municipality due-diligence questionnaires will ask.
10. Support is chat-first AI, no phone, no enterprise tier, SLA credit is 5 % — for a bank-facing API that's thin.
11. Reputation signal: strong with beginners (Trustpilot 4.6), weak with power users (throttling, suspensions) [U] — I couldn't find a VPS-network incident, but VPS isn't even a status-page component.
12. Cost: ~€100–120/mo vs ~€400 — the savings are real but they're the price of the missing managed layer, not a free lunch.

## (d) Verdict
**No — Hostinger is not a credible Scaleway alternative for this workload.** It is a good, cheap KVM VPS reseller with a surprisingly decent API, and nothing more. FunderMaps needs a managed Postgres with PITR, S3 with presigned browser uploads, a private network, and an NL/EU footprint bank customers will accept; Hostinger has none of the first three and — by its own KB — no Dutch VPS location. You could build FunderMaps on two Hostinger VMs for ~€100/mo, but you'd be building and operating the database, storage, backups, and networking layers yourself, alone, on shared CPUs with an automatic throttle that fights your monthly BAG import, and you'd still need Hetzner or Scaleway for object storage. If the goal is "cheaper than DO with fewer components for one developer", Hostinger moves in the wrong direction on components. Keep Scaleway (managed PG + S3 + Paris/Amsterdam) as the plan; if raw price is the driver, Hetzner (Falkenstein/Nuremberg, object storage, private networks, volumes) is the honest budget comparison, not Hostinger. The foundation here is cheap, but it's sitting on peat.