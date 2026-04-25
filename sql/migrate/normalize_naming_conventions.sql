-- Normalize database naming conventions to match PostgreSQL defaults
-- Safe, non-breaking: only renames indexes and constraints (no column changes)
-- Run as: fundermaps (owner)

BEGIN;

-- =============================================================================
-- INDEXES: fix idx_ prefix → _idx suffix, add missing table prefixes
-- =============================================================================

-- application.file_resources
ALTER INDEX application.idx_file_resources_created_at RENAME TO file_resources_created_at_idx;
ALTER INDEX application.idx_file_resources_key RENAME TO file_resources_key_idx;
ALTER INDEX application.idx_file_resources_status RENAME TO file_resources_status_idx;

-- application.worker_jobs
ALTER INDEX application.idx_worker_jobs_created_at RENAME TO worker_jobs_created_at_idx;
ALTER INDEX application.idx_worker_jobs_job_type RENAME TO worker_jobs_job_type_idx;
ALTER INDEX application.idx_worker_jobs_priority RENAME TO worker_jobs_priority_idx;
ALTER INDEX application.idx_worker_jobs_status_process_after RENAME TO worker_jobs_status_process_after_idx;

-- geocoder.address
ALTER INDEX geocoder.idx_address_postal_code RENAME TO address_postal_code_idx;

-- data.building_precomputed
ALTER INDEX data.idx_bp_neighborhood RENAME TO building_precomputed_neighborhood_id_idx;

-- data.model_risk_static (matview)
ALTER INDEX data.idx_mrs_neighborhood RENAME TO model_risk_static_neighborhood_id_idx;

-- =============================================================================
-- PRIMARY KEYS: _pk → _pkey
-- =============================================================================

ALTER TABLE geocoder.postal_code RENAME CONSTRAINT postal_code_pk TO postal_code_pkey;
ALTER TABLE data.cluster_recovery_sample RENAME CONSTRAINT cluster_recovery_sample_pk TO cluster_recovery_sample_pkey;

-- =============================================================================
-- FOREIGN KEYS: _fk → _fkey, fix table prefixes, add missing column names
-- =============================================================================

-- geocoder schema
ALTER TABLE geocoder.address RENAME CONSTRAINT address_building_fk TO address_building_id_fkey;
ALTER TABLE geocoder.building RENAME CONSTRAINT building_neighborhood_id TO building_neighborhood_id_fkey;
ALTER TABLE geocoder.district RENAME CONSTRAINT district_country_fk TO district_municipality_id_fkey;
ALTER TABLE geocoder.neighborhood RENAME CONSTRAINT neighborhood_district_fk TO neighborhood_district_id_fkey;
ALTER TABLE geocoder.state RENAME CONSTRAINT state_country_fk TO state_country_id_fkey;
ALTER TABLE geocoder.residence RENAME CONSTRAINT residence_address_fk TO residence_address_id_fkey;
ALTER TABLE geocoder.residence RENAME CONSTRAINT residence_building_fk TO residence_building_id_fkey;

-- data schema
ALTER TABLE data.building_subsidence RENAME CONSTRAINT building_subsidence_building_fk TO building_subsidence_building_id_fkey;
ALTER TABLE data.subsidence_history RENAME CONSTRAINT subsidence_history_building_fk TO subsidence_history_building_id_fkey;

-- application schema: fix too-generic names (add column)
ALTER TABLE application.auth_key RENAME CONSTRAINT auth_key_fkey TO auth_key_user_id_fkey;
ALTER TABLE application.reset_key RENAME CONSTRAINT reset_key_fkey TO reset_key_user_id_fkey;

-- application schema: fix wrong table prefix
ALTER TABLE application.auth_refresh_token RENAME CONSTRAINT refresh_token_pkey TO auth_refresh_token_pkey;
ALTER TABLE application.auth_refresh_token RENAME CONSTRAINT refresh_token_application_id_fkey TO auth_refresh_token_application_id_fkey;
ALTER TABLE application.auth_refresh_token RENAME CONSTRAINT refresh_token_user_id_fkey TO auth_refresh_token_user_id_fkey;

-- application schema: fix stale table name reference
ALTER TABLE application.organization_mapset RENAME CONSTRAINT map_organization_organization_id_fkey TO organization_mapset_organization_id_fkey;

-- data schema: add missing _id in column portion of FK name (column is building_id, constraint says building)
ALTER TABLE data.building_cluster RENAME CONSTRAINT building_cluster_building_fkey TO building_cluster_building_id_fkey;
ALTER TABLE data.building_elevation RENAME CONSTRAINT building_elevation_building_fkey TO building_elevation_building_id_fkey;
ALTER TABLE data.building_geographic_region RENAME CONSTRAINT building_geographic_region_building_fkey TO building_geographic_region_building_id_fkey;
ALTER TABLE data.building_groundwater_level RENAME CONSTRAINT building_groundwater_level_building_fkey TO building_groundwater_level_building_id_fkey;
ALTER TABLE data.building_ownership RENAME CONSTRAINT building_ownership_building_fkey TO building_ownership_building_id_fkey;
ALTER TABLE data.building_pleistocene RENAME CONSTRAINT building_pleistocene_building_fkey TO building_pleistocene_building_id_fkey;

-- report schema: same pattern
ALTER TABLE report.recovery_sample RENAME CONSTRAINT recovery_sample_building_fkey TO recovery_sample_building_id_fkey;

COMMIT;
