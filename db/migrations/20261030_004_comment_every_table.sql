-- Give every table, view and materialized view a comment that starts with its owner tag
-- (Yorick 2026-10-30: "You can do the comment migration right now").
--
-- Why: on prod (2026-10-30) 60 of the 105 tables and views had no comment, and nothing in the database said
-- which tables Better Auth owns or which part of the system each one belongs to. The tag makes that visible in
-- every DB tool and in schema.sql. Comments only: no rename, no data change.
--
-- Tags: [Better Auth · core | passkey | api-key | organization] tables Better Auth owns (change only through a
-- Better Auth upgrade) · [legacy] still read, on the way out · [access] [maps] [billing] [records] [files] [ops]
-- · [model input | evidence | output | output · frozen | registry | candidate | benchmark] [facade scan]
-- [statistics] [usage] [export] · [intake] [intake · staff] · [BAG] [areas] · [tiles · cache | source].
-- 20 objects keep their existing text after the tag; the other 85 get new text.
--
-- COMMENT takes a short lock on each object; lock_timeout makes the file fail and roll back instead of
-- waiting behind a running refresh.

SET LOCAL lock_timeout = '2s';

-- application
COMMENT ON TABLE application.account IS $c$[Better Auth · core] Login methods per user: one row per provider; for email login it holds the password hash.$c$;
COMMENT ON TABLE application.api_key_rate_limit IS $c$[billing] Per-(API key, product) billing-event rate limits enforced by FunderMapsWebservice.$c$;
COMMENT ON TABLE application.apikey IS $c$[Better Auth · api-key] API keys issued by the plugin (prefix fmsk.): hashed key, owner (reference_id), enabled flag and expiry. Per-product billing limits live in application.api_key_rate_limit.$c$;
COMMENT ON TABLE application.application IS $c$[legacy] Registry of the old FunderMaps apps and portals (21 rows, most unused). application_user hangs off it.$c$;
COMMENT ON TABLE application.application_user IS $c$[access] Per-user settings for an app (JSON metadata), keyed by user and application_id.$c$;
COMMENT ON TABLE application.attribution IS $c$[records] Intermediate object between an uploaded sample or report and the assigned user reviewer or owner. In case of user deletion a reference still exists, only the reference to said user or owner will be set to NULL.$c$;
COMMENT ON TABLE application.auth_key IS $c$[legacy] API keys from before Better Auth (hashed). Still read next to application.apikey until the last customers have moved to fmsk. keys; then drop.$c$;
COMMENT ON TABLE application.contractor IS $c$[records] Contractors (research and repair firms) that reports are attributed to.$c$;
COMMENT ON TABLE application.file_resources IS $c$[files] Metadata of uploaded files in S3-compatible storage. Status uploaded until a record links the file (then active); replaced or deleted files become archived.$c$;
COMMENT ON TABLE application.invitation IS $c$[Better Auth · organization] Invitations to join an organisation. Not used yet.$c$;
COMMENT ON TABLE application.mapset IS $c$[maps] A map in the map app: a named, ordered list of layer ids (layers), public or shared per organisation via organization_mapset.$c$;
COMMENT ON VIEW application.mapset_collection IS $c$[maps] Each mapset with its layers inlined as one JSON array (layerset), the way the map app loads it.$c$;
COMMENT ON TABLE application.mapset_layer IS $c$[maps] One map layer: its fields (the legend) and display order. Mapsets list layer ids.$c$;
COMMENT ON TABLE application.organization IS $c$[Better Auth · organization] Organisations: customers and our own. Our existing table, mapped onto the plugin's organization model.$c$;
COMMENT ON TABLE application.organization_custom_role IS $c$[Better Auth · organization] Better Auth dynamic access control: admin-defined per-organization roles with a JSON permission map (resource -> actions). Named *_custom_role because application.organization_role is the role enum type.$c$;
COMMENT ON TABLE application.organization_geolock_district IS $c$[access] Limits an organisation's data to these districts. Supported, but no organisation uses it.$c$;
COMMENT ON TABLE application.organization_geolock_municipality IS $c$[access] Limits an organisation's data to these municipalities.$c$;
COMMENT ON TABLE application.organization_geolock_neighborhood IS $c$[access] Limits an organisation's data to these neighbourhoods.$c$;
COMMENT ON TABLE application.organization_mapset IS $c$[access] Which organisation sees which mapset (non-public maps).$c$;
COMMENT ON TABLE application.organization_user IS $c$[Better Auth · organization] Membership of a user in an organisation, with their role (superuser, verifier, writer, reader). The plugin's member model, renamed in auth.ts.$c$;
COMMENT ON TABLE application.passkey IS $c$[Better Auth · passkey] WebAuthn credentials (Better Auth passkey plugin). One row per registered passkey; rpID fundermaps.com.$c$;
COMMENT ON TABLE application.product_tracker IS $c$[billing] The billing record: one row per billable lookup (organisation, product, building, time). Never edit or prune.$c$;
COMMENT ON TABLE application.schema_migrations IS $c$[ops] Ledger of the Worker migrations runner (bun run migrate): version, checksum, who applied it and when.$c$;
COMMENT ON TABLE application.session IS $c$[Better Auth · core] Login sessions (the cookie token). The admin plugin adds impersonated_by, the organization plugin active_organization_id.$c$;
COMMENT ON TABLE application."user" IS $c$[Better Auth · core] People who can log in. The admin plugin adds role, banned, ban_reason and ban_expires; we add given_name, last_name, job_title and phone_number; Better Auth's image is our avatar.$c$;
COMMENT ON TABLE application.verification IS $c$[Better Auth · core] Short-lived tokens for password reset and email checks.$c$;

-- data
COMMENT ON TABLE data.building_cluster IS $c$[model input] The cluster each building belongs to: nearby buildings that share evidence.$c$;
COMMENT ON TABLE data.building_elevation IS $c$[model input] Ground level, roof level and height per building.$c$;
COMMENT ON VIEW data.building_geo_hierarchy IS $c$[export] The default model per building with its neighbourhood, district and municipality. Feeds maplayer.analysis_full (the archive export).$c$;
COMMENT ON TABLE data.building_geographic_region IS $c$[model input] Soil region (code) per building.$c$;
COMMENT ON TABLE data.building_groundwater_level IS $c$[model input] Groundwater level per building.$c$;
COMMENT ON VIEW data.building_height IS $c$[model input] Absolute building height, from data.building_elevation.$c$;
COMMENT ON TABLE data.building_ownership IS $c$[model input] Owner per building, where known.$c$;
COMMENT ON TABLE data.building_pleistocene IS $c$[model input] Depth of the Pleistocene layer per building.$c$;
COMMENT ON TABLE data.building_precomputed IS $c$[model input] One row per active house with its basic inputs (neighbourhood, surface area, addresses, BAG build year, height, ground level). Rebuilt by data.refresh_building_precomputed() after a BAG load.$c$;
COMMENT ON MATERIALIZED VIEW data.building_sample IS $c$[model evidence] Evidence per building from research reports, the way the risk model reads it. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.building_sample_2026_3 IS $c$[model evidence] Extra evidence per building for model-2026.3 (QuickScan and research dates, decay findings), built on building_sample. Refreshed by refresh_data_model.$c$;
COMMENT ON TABLE data.building_subsidence IS $c$[model input] Current subsidence velocity per building.$c$;
COMMENT ON TABLE data.building_subsidence_history IS $c$[model input] Subsidence measurement series per building (one row per building and mark_at). The largest table in the database.$c$;
COMMENT ON TABLE data.cluster_recovery_sample IS $c$[model evidence] Recovery types per building cluster.$c$;
COMMENT ON MATERIALIZED VIEW data.cluster_sample IS $c$[model evidence] Evidence per building cluster, for buildings without a report of their own. Refreshed by refresh_data_model.$c$;
COMMENT ON TABLE data.model_evaluation_sample IS $c$[model benchmark] Frozen benchmark for scoring candidate models. Deliberately a table, not a view: a growing truth set would make two candidates scored on different days incomparable. See docs/model-versioning.md.$c$;
COMMENT ON TABLE data.model_evaluation_stratum_weight IS $c$[model benchmark] True national size of each evaluation stratum. The population sample is floored at 2,000 per stratum and is therefore NOT proportional -- weight by national_buildings before quoting any national figure.$c$;
COMMENT ON TABLE data.model_foundation_2026_2 IS $c$[model candidate] Candidate model-2026.2 (Worker #152, rc2 2026-09-27): blend of two LightGBM foundation-family models (c where the buurt has report labels, else mean of a and c) plus model d for the wood-pile / wood-pile-with-concrete-top split, trained offline on report labels (quickscan and facade_scan excluded). p_* = blend probabilities, p_oplanger = P(concrete top | wood). family/foundation_type = own evidence when source is report or quickscan (grade vastgesteld), else the model. evidence: buurt = a label in the same buurt x era; nabij = only a label within 250 m; municipal = municipality has >= 30 labels; none = neither. grade from the out-of-sample lookup (zeer betrouwbaar ~96%, betrouwbaar ~83% correct). Served to nobody except the FunderMaps B.V. candidate mapset. Frozen model-2024.1 is untouched.$c$;
COMMENT ON TABLE data.model_gevelscan IS $c$[facade scan] Decision table: facade skew (parallel, perpendicular) and facade type give the facade-scan risk (a to e). Read by maplayer.facade_scan.$c$;
COMMENT ON VIEW data.model_risk_dynamic_all IS $c$[model output · frozen] The model-2024.1 logic as a live view. Only source of the frozen matview model_risk_static_2024_1; nothing else reads it.$c$;
COMMENT ON VIEW data.model_risk_static IS $c$[model output] Pointer at the default model version. Consumers should name this, not a versioned matview. Switch the default with CREATE OR REPLACE VIEW. See docs/model-versioning.md.$c$;
COMMENT ON MATERIALIZED VIEW data.model_risk_static_2024_1 IS $c$[model output · frozen] model-2024.1 for every building. Frozen: not refreshed since 2026-10-19, when model-2026.3 became the default. Kept as the baseline for sql/validate/model_2026_3_control.sql.$c$;
COMMENT ON MATERIALIZED VIEW data.model_risk_static_2026_3 IS $c$[model output] model-2026.3 for every pand: data.model_risk_2026_3_rows() with every rule on. The first 30 columns are the model contract (the pointer view selects them by name); the columns after them say where each risk came from and are not served. Refreshed by Windmill f/fundermaps/data/refresh_risk_model, after the sample matviews. See docs/model-versioning.md.$c$;
COMMENT ON TABLE data.model_version IS $c$[model registry] Registry of risk model versions: what each was built from, and where it is in its lifecycle. See docs/model-versioning.md.$c$;
COMMENT ON MATERIALIZED VIEW data.product_tracker_daily IS $c$[usage] Webservice/map usage per Amsterdam-local day, organization and product. Source: application.product_tracker. Refreshed by the refresh_data_model flow.$c$;
COMMENT ON TABLE data.refresh_log IS $c$[ops] One row per completed scheduled job (e.g. refresh_data_model). Read by Grafana and, later, /health/nightly as a dead-man switch.$c$;
COMMENT ON TABLE data.risk_table_priority IS $c$[facade scan] Decision table: risk and settlement speed give a priority label. Read by maplayer.facade_scan.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_buildings_restored IS $c$[statistics] Webservice statistics product: number of restored buildings per neighbourhood. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_construction_years IS $c$[statistics] Webservice statistics product: buildings per construction-year bucket (year_from) per neighbourhood. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_data_collected IS $c$[statistics] Webservice statistics product: share of buildings with collected data per neighbourhood. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_foundation_risk IS $c$[statistics] Webservice statistics product: share of buildings per foundation risk per neighbourhood. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_foundation_type IS $c$[statistics] Webservice statistics product: share of buildings per foundation type per neighbourhood. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_incident_municipality IS $c$[statistics] Webservice statistics product: incidents per year per municipality. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_incidents IS $c$[statistics] Webservice statistics product: incidents per year per neighbourhood. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_inquiries IS $c$[statistics] Webservice statistics product: research reports per year per neighbourhood. Refreshed by refresh_data_model.$c$;
COMMENT ON MATERIALIZED VIEW data.statistics_product_inquiry_municipality IS $c$[statistics] Webservice statistics product: research reports per year per municipality. Refreshed by refresh_data_model.$c$;
COMMENT ON TABLE data.supercluster IS $c$[model input] The supercluster each cluster belongs to: the next level up when a cluster has no evidence of its own.$c$;
COMMENT ON MATERIALIZED VIEW data.supercluster_sample IS $c$[model evidence] Evidence per supercluster, the fallback after cluster_sample. Refreshed by refresh_data_model.$c$;

-- dataops
COMMENT ON TABLE dataops.artifact IS $c$[intake] One file in a dossier (upload, mail attachment or a part split from one): storage key, type, size, pages and reading lane.$c$;
COMMENT ON TABLE dataops.artifact_page IS $c$[intake] Page-level triage. Routing photographs and blanks to a human before extraction is the cheapest accuracy this pipeline has: 2% vs 73-89% on the same field.$c$;
COMMENT ON TABLE dataops.dossier IS $c$[intake] An intake case: what came in (channel, submitter, payload), which building it is about, who handles it, and the outcome. Its history is dossier_entry.$c$;
COMMENT ON TABLE dataops.dossier_address IS $c$[intake] The addresses a dossier is about, and what the reviewer decided about each (ClientApp #333 part C). A value's own address_id says where the value was read; this row says whether that address belongs to the dossier at all.$c$;
COMMENT ON TABLE dataops.dossier_entry IS $c$[intake] Append-only timeline of a dossier. INSERT+SELECT only; an entry is never updated or deleted.$c$;
COMMENT ON TABLE dataops.dossier_mail IS $c$[intake] Send log for melder-facing mail (#1020). One row per (dossier, kind), claimed before the send; the unique key is the idempotency guard.$c$;
COMMENT ON TABLE dataops.dossier_rapportage IS $c$[intake] The verdict per rapportage of a dossier (Don, 2026-10-09). One row per group of documents the reviewer formed at commit; the closing mail combines the answers into one message to the melder.$c$;
COMMENT ON TABLE dataops.extraction IS $c$[intake] One AI reading of an artifact: model, prompt version, lane, pages sent, tokens, cost and any error.$c$;
COMMENT ON TABLE dataops.extraction_field IS $c$[intake] One value an extraction read, with confidence, evidence (page and offset), the address it belongs to and its review state.$c$;
COMMENT ON TABLE dataops.staff_capacity IS $c$[intake · staff] How much review-queue work a colleague takes, for the dispatcher (FunderMapsApi #277). No row or active = false: the dispatcher assigns this person nothing.$c$;
COMMENT ON TABLE dataops.verdict IS $c$[intake] Every human confirmation and correction, kept as a labelled example. Today's labels come from cover sheets an invoerder writes before uploading; once this pipeline reads documents instead, nobody writes those any more and this table becomes the only source of new training data.$c$;
COMMENT ON TABLE dataops.work_package_assignment IS $c$[intake · staff] Work packages (Studio Vandaag filters) the admin assigned to a colleague. One row per user and package; the set is replaced as a whole by PUT /api/management/work-packages/:userId. No rows = the user picks their own packages in the browser.$c$;

-- geocoder
COMMENT ON TABLE geocoder.address IS $c$[BAG] BAG addresses in our own format, with a tsvector column for full-text search.$c$;
COMMENT ON TABLE geocoder.building IS $c$[BAG] BAG buildings in our own format: geometry, build year, type, status and neighbourhood.$c$;
COMMENT ON VIEW geocoder.building_active IS $c$[BAG] The buildings from geocoder.building whose status is active.$c$;
COMMENT ON VIEW geocoder.building_geocoder IS $c$[BAG] Each building with its residence location and the names and ids of its neighbourhood, district, municipality and province, for geocoder lookups.$c$;
COMMENT ON TABLE geocoder.district IS $c$[areas] Districts (CBS), with geometry.$c$;
COMMENT ON TABLE geocoder.municipality IS $c$[areas] Municipalities (CBS), with geometry.$c$;
COMMENT ON TABLE geocoder.neighborhood IS $c$[areas] Neighbourhoods (CBS), with geometry.$c$;
COMMENT ON TABLE geocoder.residence IS $c$[BAG] BAG residences (dwelling units): the link between an address and a building.$c$;
COMMENT ON TABLE geocoder.state IS $c$[areas] The 12 provinces.$c$;

-- maplayer
COMMENT ON VIEW maplayer.analysis_full IS $c$[export] The default model per building with its area ids, as exported twice a day to the archive (GeoPackage + GeoParquet).$c$;
COMMENT ON TABLE maplayer.building_cluster_tiles IS $c$[tiles · cache] Rows behind the tile function maplayer.building_cluster(z,x,y): one union geometry per cluster. Rebuilt nightly by maplayer.refresh_building_cluster_tiles().$c$;
COMMENT ON TABLE maplayer.building_tiles IS $c$[tiles · cache] Rows behind the public tile function maplayer.buildings(z,x,y): the default model per building with geometry. Rebuilt nightly by maplayer.refresh_building_tiles().$c$;
COMMENT ON TABLE maplayer.bundle IS $c$[export] Which maplayer views the archive export (Windmill f/fundermaps/mapset/export_tileset) writes to GeoPackage. Only enabled and upload_dataset are read; the zoom and generate_tileset columns are left over from the old tilesets.$c$;
COMMENT ON VIEW maplayer.facade_scan IS $c$[tiles · source] What maplayer.refresh_facade_scan_tiles() copies into facade_scan_tiles; also an archive export layer (maplayer.bundle). Not the tile function of the same name.$c$;
COMMENT ON TABLE maplayer.facade_scan_tiles IS $c$[tiles · cache] Rows behind the tile function maplayer.facade_scan(z,x,y). Rebuilt by maplayer.refresh_facade_scan_tiles().$c$;
COMMENT ON VIEW maplayer.incident IS $c$[tiles · source] Incident reports (dossiers with a topic) per building; maplayer.refresh_incident_tiles() copies it into incident_tiles. Not the tile function of the same name.$c$;
COMMENT ON VIEW maplayer.incident_district IS $c$[tiles · source] Incident count per district; copied into incident_district_tiles by maplayer.refresh_incident_tiles(). Not the tile function of the same name.$c$;
COMMENT ON TABLE maplayer.incident_district_tiles IS $c$[tiles · cache] Rows behind the tile function maplayer.incident_district(z,x,y): incident count per district. Rebuilt by maplayer.refresh_incident_tiles().$c$;
COMMENT ON VIEW maplayer.incident_municipality IS $c$[tiles · source] Incident count per municipality; copied into incident_municipality_tiles by maplayer.refresh_incident_tiles(). Not the tile function of the same name.$c$;
COMMENT ON TABLE maplayer.incident_municipality_tiles IS $c$[tiles · cache] Rows behind the tile function maplayer.incident_municipality(z,x,y): incident count per municipality. Rebuilt by maplayer.refresh_incident_tiles().$c$;
COMMENT ON VIEW maplayer.incident_neighborhood IS $c$[tiles · source] Incident count per neighbourhood; copied into incident_neighborhood_tiles by maplayer.refresh_incident_tiles(). Not the tile function of the same name.$c$;
COMMENT ON TABLE maplayer.incident_neighborhood_tiles IS $c$[tiles · cache] Rows behind the tile function maplayer.incident_neighborhood(z,x,y): incident count per neighbourhood. Rebuilt by maplayer.refresh_incident_tiles().$c$;
COMMENT ON TABLE maplayer.incident_tiles IS $c$[tiles · cache] Rows behind the tile function maplayer.incident(z,x,y). Rebuilt by maplayer.refresh_incident_tiles().$c$;

-- report
COMMENT ON TABLE report.dossier_event IS $c$[records] Append-only history of an inquiry, recovery or incident (created, submitted, approved, …); not dataops.dossier. Exactly one of inquiry_id / recovery_id / incident_id is set.$c$;
COMMENT ON TABLE report.incident IS $c$[records] Incident reports about a building: what the reporter saw and asked.$c$;
COMMENT ON TABLE report.inquiry IS $c$[records] Research reports: one row per report (type, document date, audit status). The findings per building are in inquiry_sample.$c$;
COMMENT ON TABLE report.inquiry_sample IS $c$[records] One building's findings in a research report: foundation type, quality, damage, measurements.$c$;
COMMENT ON TABLE report.recovery IS $c$[records] Foundation recoveries (repairs): one row per recovery document.$c$;
COMMENT ON TABLE report.recovery_sample IS $c$[records] One building in a recovery: recovery type, status and date.$c$;
