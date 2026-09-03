--
-- PostgreSQL database dump
--

\restrict 78jk05M09uaP5i49W6qAj48tXlBg5K8V3GPpE2ciCL3To7NlcwdyPykBiY6WVHm

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6 (Ubuntu 18.6-1.pgdg24.04+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: timescaledb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data (Apache 2 Edition)';


--
-- Name: application; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA application;


--
-- Name: data; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA data;


--
-- Name: dataops; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA dataops;


--
-- Name: geocoder; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA geocoder;


--
-- Name: maplayer; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA maplayer;


--
-- Name: report; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA report;


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: access_policy; Type: TYPE; Schema: application; Owner: -
--

CREATE TYPE application.access_policy AS ENUM (
    'public',
    'private'
);


--
-- Name: email; Type: DOMAIN; Schema: application; Owner: -
--

CREATE DOMAIN application.email AS text
	CONSTRAINT at CHECK (("position"(VALUE, '@'::text) > 0));


--
-- Name: DOMAIN email; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON DOMAIN application.email IS 'Domain for an email address.';


--
-- Name: job_status; Type: TYPE; Schema: application; Owner: -
--

CREATE TYPE application.job_status AS ENUM (
    'pending',
    'processing',
    'completed',
    'failed',
    'retry'
);


--
-- Name: organization_id; Type: DOMAIN; Schema: application; Owner: -
--

CREATE DOMAIN application.organization_id AS uuid;


--
-- Name: DOMAIN organization_id; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON DOMAIN application.organization_id IS 'Domain for an organization identifier.';


--
-- Name: organization_role; Type: TYPE; Schema: application; Owner: -
--

CREATE TYPE application.organization_role AS ENUM (
    'superuser',
    'verifier',
    'writer',
    'reader'
);


--
-- Name: phone; Type: DOMAIN; Schema: application; Owner: -
--

CREATE DOMAIN application.phone AS text
	CONSTRAINT all_int CHECK ((VALUE ~* '^[0-9]+$'::text));


--
-- Name: DOMAIN phone; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON DOMAIN application.phone IS 'Domain for a phone number.';


--
-- Name: role; Type: TYPE; Schema: application; Owner: -
--

CREATE TYPE application.role AS ENUM (
    'administrator',
    'user'
);


--
-- Name: user_id; Type: DOMAIN; Schema: application; Owner: -
--

CREATE DOMAIN application.user_id AS uuid;


--
-- Name: DOMAIN user_id; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON DOMAIN application.user_id IS 'Domain for a user identifier.';


--
-- Name: foundation_risk_indication; Type: TYPE; Schema: data; Owner: -
--

CREATE TYPE data.foundation_risk_indication AS ENUM (
    'a',
    'b',
    'c',
    'd',
    'e'
);


--
-- Name: model_status; Type: TYPE; Schema: data; Owner: -
--

CREATE TYPE data.model_status AS ENUM (
    'draft',
    'candidate',
    'active',
    'frozen',
    'deprecated',
    'retired'
);


--
-- Name: reliability; Type: TYPE; Schema: data; Owner: -
--

CREATE TYPE data.reliability AS ENUM (
    'indicative',
    'established',
    'cluster',
    'supercluster'
);


--
-- Name: dossier_outcome; Type: TYPE; Schema: dataops; Owner: -
--

CREATE TYPE dataops.dossier_outcome AS ENUM (
    'accepted',
    'rejected',
    'duplicate',
    'no_data'
);


--
-- Name: intake_channel; Type: TYPE; Schema: dataops; Owner: -
--

CREATE TYPE dataops.intake_channel AS ENUM (
    'email',
    'upload',
    'bulk_drop',
    'api',
    'invoer_app'
);


--
-- Name: material; Type: TYPE; Schema: dataops; Owner: -
--

CREATE TYPE dataops.material AS ENUM (
    'drawing',
    'archive_document',
    'report',
    'photo',
    'map',
    'blank',
    'other'
);


--
-- Name: read_lane; Type: TYPE; Schema: dataops; Owner: -
--

CREATE TYPE dataops.read_lane AS ENUM (
    'vision',
    'text',
    'none',
    'document'
);


--
-- Name: resolution_status; Type: TYPE; Schema: dataops; Owner: -
--

CREATE TYPE dataops.resolution_status AS ENUM (
    'resolved',
    'stale_bag',
    'ambiguous',
    'absent'
);


--
-- Name: review_state; Type: TYPE; Schema: dataops; Owner: -
--

CREATE TYPE dataops.review_state AS ENUM (
    'pending',
    'auto_accepted',
    'confirmed',
    'corrected',
    'rejected',
    'superseded'
);


--
-- Name: building_type; Type: TYPE; Schema: geocoder; Owner: -
--

CREATE TYPE geocoder.building_type AS ENUM (
    'house',
    'shed',
    'houseboat',
    'mobile_home'
);


--
-- Name: geocoder_id; Type: DOMAIN; Schema: geocoder; Owner: -
--

CREATE DOMAIN geocoder.geocoder_id AS text;


--
-- Name: DOMAIN geocoder_id; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON DOMAIN geocoder.geocoder_id IS 'Domain for our internal geocoder identifier.';


--
-- Name: year; Type: DOMAIN; Schema: geocoder; Owner: -
--

CREATE DOMAIN geocoder.year AS date DEFAULT CURRENT_TIMESTAMP
	CONSTRAINT range CHECK (((date_part('Y'::text, VALUE) > (900)::double precision) AND (date_part('Y'::text, VALUE) < (2100)::double precision)));


--
-- Name: DOMAIN year; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON DOMAIN geocoder.year IS 'Domain for a year between 900 and 2100.';


--
-- Name: zone_function; Type: TYPE; Schema: geocoder; Owner: -
--

CREATE TYPE geocoder.zone_function AS ENUM (
    'industry',
    'residential',
    'assembly',
    'education',
    'office',
    'retail',
    'accommodation',
    'sport',
    'medical',
    'other',
    'prison'
);


--
-- Name: resource_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.resource_status AS ENUM (
    'uploaded',
    'processing',
    'active',
    'archived'
);


--
-- Name: audit_status; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.audit_status AS ENUM (
    'todo',
    'pending',
    'done',
    'discarded',
    'rejected',
    'pending_review'
);


--
-- Name: construction_pile; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.construction_pile AS ENUM (
    'punched',
    'broken',
    'pinched',
    'pressed',
    'perished',
    'decay',
    'root_growth'
);


--
-- Name: crack_size; Type: DOMAIN; Schema: report; Owner: -
--

CREATE DOMAIN report.crack_size AS integer
	CONSTRAINT crack_size_check CHECK (((VALUE >= 0) AND (VALUE <= 999)));


--
-- Name: DOMAIN crack_size; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON DOMAIN report.crack_size IS 'Domain for crack size.';


--
-- Name: crack_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.crack_type AS ENUM (
    'none',
    'nil',
    'small',
    'mediocre',
    'big'
);


--
-- Name: diameter; Type: DOMAIN; Schema: report; Owner: -
--

CREATE DOMAIN report.diameter AS numeric(5,2);


--
-- Name: DOMAIN diameter; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON DOMAIN report.diameter IS 'Domain for the diameter of an object.';


--
-- Name: dossier_event_kind; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.dossier_event_kind AS ENUM (
    'created',
    'submitted',
    'approved',
    'rejected',
    'reopened',
    'imported',
    'proposed'
);


--
-- Name: enforcement_term; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.enforcement_term AS ENUM (
    'term05',
    'term510',
    'term1020',
    'term5',
    'term10',
    'term15',
    'term20',
    'term25',
    'term30',
    'term40'
);


--
-- Name: environment_damage_characteristics; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.environment_damage_characteristics AS ENUM (
    'subsidence',
    'sagging_sewer_connection',
    'sagging_cables_pipes',
    'flooding',
    'foundation_damage_nearby',
    'elevation',
    'increasing_traffic',
    'construction_nearby',
    'vegetation_nearby',
    'sewage_leakage',
    'low_ground_water'
);


--
-- Name: facade; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.facade AS ENUM (
    'front',
    'sidewall_left',
    'sidewall_right',
    'rear'
);


--
-- Name: facade_scan_risk; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.facade_scan_risk AS ENUM (
    'a',
    'b',
    'c',
    'd',
    'e'
);


--
-- Name: foundation_damage_cause; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.foundation_damage_cause AS ENUM (
    'drainage',
    'construction_flaw',
    'drystand',
    'overcharge',
    'overcharge_negative_cling',
    'negative_cling',
    'bio_infection',
    'fungus_infection',
    'bio_fungus_infection',
    'foundation_flaw',
    'construction_heave',
    'subsidence',
    'vegetation',
    'gas',
    'vibrations',
    'partial_foundation_recovery',
    'japanese_knotweed',
    'groundwater_level_reduction'
);


--
-- Name: foundation_damage_characteristics; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.foundation_damage_characteristics AS ENUM (
    'jamming_door_window',
    'crack',
    'skewed',
    'crawlspace_flooding',
    'threshold_above_subsurface',
    'threshold_below_subsurface',
    'crooked_floor_wall'
);


--
-- Name: foundation_quality; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.foundation_quality AS ENUM (
    'bad',
    'mediocre',
    'tolerable',
    'good',
    'mediocre_good',
    'mediocre_bad'
);


--
-- Name: foundation_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.foundation_type AS ENUM (
    'wood',
    'concrete',
    'no_pile',
    'wood_charger',
    'weighted_pile',
    'combined',
    'steel_pile',
    'other',
    'no_pile_masonry',
    'no_pile_strips',
    'no_pile_concrete_floor',
    'no_pile_slit',
    'wood_amsterdam',
    'wood_rotterdam',
    'no_pile_bearing_floor',
    'wood_rotterdam_amsterdam',
    'wood_rotterdam_arch',
    'wood_amsterdam_arch'
);


--
-- Name: height; Type: DOMAIN; Schema: report; Owner: -
--

CREATE DOMAIN report.height AS numeric(5,2);


--
-- Name: DOMAIN height; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON DOMAIN report.height IS 'Domain for the height of an object.';


--
-- Name: incident_question_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.incident_question_type AS ENUM (
    'buy_sell',
    'registration',
    'legal',
    'financial',
    'guidance',
    'recovery',
    'research',
    'other'
);


--
-- Name: inquiry_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.inquiry_type AS ENUM (
    'monitoring',
    'note',
    'quickscan',
    'unknown',
    'demolition_research',
    'second_opinion',
    'archive_research',
    'architectural_research',
    'foundation_advice',
    'inspectionpit',
    'foundation_research',
    'additional_research',
    'ground_water_level_research',
    'soil_investigation',
    'facade_scan'
);


--
-- Name: length; Type: DOMAIN; Schema: report; Owner: -
--

CREATE DOMAIN report.length AS numeric(5,2);


--
-- Name: DOMAIN length; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON DOMAIN report.length IS 'Domain for the length of an object.';


--
-- Name: pile_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.pile_type AS ENUM (
    'press',
    'internally_driven',
    'segment'
);


--
-- Name: quality; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.quality AS ENUM (
    'nil',
    'small',
    'mediocre',
    'large'
);


--
-- Name: recovery_document_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.recovery_document_type AS ENUM (
    'permit',
    'foundation_report',
    'archive_report',
    'owner_evidence',
    'unknown'
);


--
-- Name: recovery_status; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.recovery_status AS ENUM (
    'planned',
    'requested',
    'executed'
);


--
-- Name: recovery_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.recovery_type AS ENUM (
    'table',
    'beam_on_pile',
    'pile_lowering',
    'pile_in_wall',
    'injection',
    'unknown'
);


--
-- Name: rotation_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.rotation_type AS ENUM (
    'nil',
    'small',
    'mediocre',
    'big',
    'very_big'
);


--
-- Name: substructure; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.substructure AS ENUM (
    'basement',
    'cellar',
    'crawlspace',
    'none'
);


--
-- Name: wood_encroachment; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.wood_encroachment AS ENUM (
    'fungus_infection',
    'bio_fungus_infection',
    'bio_infection'
);


--
-- Name: wood_quality; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.wood_quality AS ENUM (
    'area1',
    'area2',
    'area3',
    'area4'
);


--
-- Name: wood_type; Type: TYPE; Schema: report; Owner: -
--

CREATE TYPE report.wood_type AS ENUM (
    'pine',
    'spruce'
);


--
-- Name: year; Type: DOMAIN; Schema: report; Owner: -
--

CREATE DOMAIN report.year AS date DEFAULT CURRENT_TIMESTAMP
	CONSTRAINT range CHECK (((date_part('Y'::text, VALUE) > (900)::double precision) AND (date_part('Y'::text, VALUE) < (2100)::double precision)));


--
-- Name: DOMAIN year; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON DOMAIN report.year IS 'Domain for a year between 900 and 2100.';


--
-- Name: cleanup_auth_data(); Type: PROCEDURE; Schema: application; Owner: -
--

CREATE PROCEDURE application.cleanup_auth_data()
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE NOTICE 'Starting authentication data cleanup';

    DELETE FROM application.session
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired Better Auth sessions.', FOUND::TEXT;

    DELETE FROM application.verification
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired Better Auth verifications.', FOUND::TEXT;

    DELETE FROM application.oauth_access_token
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired OAuth access tokens.', FOUND::TEXT;

    DELETE FROM application.oauth_refresh_token
    WHERE expires_at < NOW();
    RAISE NOTICE 'Deleted % expired OAuth refresh tokens.', FOUND::TEXT;

    RAISE NOTICE 'Authentication data cleanup finished';
END;
$$;


--
-- Name: random_string(integer); Type: FUNCTION; Schema: application; Owner: -
--

CREATE FUNCTION application.random_string(length integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    chars TEXT[] := '{2,3,4,5,6,7,8,9,a,b,c,d,e,f,g,h,j,k,m,n,p,q,r,s,t,u,v,w,x,y,z}';
    result TEXT := '';
    i INTEGER := 0;
BEGIN
    IF length < 0 THEN
        RAISE EXCEPTION 'Given length cannot be less than 0';
    END IF;

    FOR i IN 1..length LOOP
        result := result || chars[1 + floor(random() * array_length(chars, 1))];
    END LOOP;

    RETURN result;
END;
$$;


--
-- Name: compute_damage_risk(boolean, report.foundation_damage_cause, report.foundation_damage_cause[], report.enforcement_term, report.foundation_quality, boolean); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.compute_damage_risk(has_recovery boolean, damage_cause report.foundation_damage_cause, target_causes report.foundation_damage_cause[], enforcement_term report.enforcement_term, overall_quality report.foundation_quality, recovery_advised boolean) RETURNS data.foundation_risk_indication
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE
        -- Recovery exists → safe (established tier only)
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication

        -- Urgent: short enforcement term, recovery advised, or bad quality
        WHEN damage_cause = ANY(target_causes)
             AND (enforcement_term IN ('term05', 'term5')
                  OR recovery_advised
                  OR overall_quality = 'bad')
            THEN 'e'::data.foundation_risk_indication

        -- Concerning: medium enforcement term or mediocre-bad quality
        WHEN damage_cause = ANY(target_causes)
             AND (enforcement_term IN ('term510', 'term10')
                  OR overall_quality = 'mediocre_bad')
            THEN 'd'::data.foundation_risk_indication

        -- Moderate: longer term or mediocre/tolerable quality
        WHEN damage_cause = ANY(target_causes)
             AND (enforcement_term IN ('term1020', 'term15', 'term20')
                  OR overall_quality IN ('mediocre', 'tolerable'))
            THEN 'c'::data.foundation_risk_indication

        -- Low: long term or good quality
        WHEN damage_cause = ANY(target_causes)
             AND (enforcement_term IN ('term25', 'term30', 'term40')
                  OR overall_quality IN ('good', 'mediocre_good'))
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;


--
-- Name: compute_indicative_bio_risk(report.foundation_type, numeric, double precision, boolean); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.compute_indicative_bio_risk(ft report.foundation_type, pile_length numeric, velocity double precision, has_recovery boolean) RETURNS data.foundation_risk_indication
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication

        -- Short piles (≤12m)
        WHEN data.is_wood_family(ft) AND pile_length <= 12 AND velocity < -2.0
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length <= 12
            THEN 'd'::data.foundation_risk_indication

        -- Medium piles (12-15m)
        WHEN data.is_wood_family(ft) AND pile_length > 12 AND pile_length <= 15
             AND velocity < -2.0
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length > 12 AND pile_length <= 15
            THEN 'c'::data.foundation_risk_indication

        -- Long piles (>15m)
        WHEN data.is_wood_family(ft) AND pile_length > 15 AND velocity < -2.0
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_family(ft) AND pile_length > 15
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;


--
-- Name: compute_indicative_dewatering_risk(report.foundation_type, double precision, double precision, boolean); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.compute_indicative_dewatering_risk(ft report.foundation_type, velocity double precision, gwl double precision, has_recovery boolean) RETURNS data.foundation_risk_indication
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication
        WHEN data.is_safe_foundation(ft) THEN 'a'::data.foundation_risk_indication

        -- No-pile family (excl bearing_floor for risk calc, matching current behavior)
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity IS NULL AND gwl < 0.6
            THEN 'c'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity IS NULL AND gwl >= 0.6
            THEN 'b'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity < -1.0 AND gwl < 0.6
            THEN 'e'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity < -1.0 AND gwl >= 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity >= -1.0 AND gwl < 0.6
            THEN 'd'::data.foundation_risk_indication
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
             AND velocity >= -1.0 AND gwl >= 0.6
            THEN 'c'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;


--
-- Name: compute_indicative_drystand_risk(report.foundation_type, double precision, double precision, boolean); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.compute_indicative_drystand_risk(ft report.foundation_type, velocity double precision, gwl double precision, has_recovery boolean) RETURNS data.foundation_risk_indication
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE
        WHEN has_recovery THEN 'a'::data.foundation_risk_indication
        WHEN data.is_safe_foundation(ft) THEN 'a'::data.foundation_risk_indication

        -- Wood pile types (threshold: velocity -2.0, GWL 1.5)
        WHEN data.is_wood_pile(ft) AND velocity IS NULL AND gwl >= 1.5
            THEN 'c'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity IS NULL AND gwl < 1.5
            THEN 'b'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity < -2.0 AND gwl >= 1.5
            THEN 'e'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity >= -2.0 AND gwl >= 1.5
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity < -2.0 AND gwl < 1.5
            THEN 'd'::data.foundation_risk_indication
        WHEN data.is_wood_pile(ft) AND velocity >= -2.0 AND gwl < 1.5
            THEN 'c'::data.foundation_risk_indication

        -- Wood charger (threshold: velocity -1.0, GWL 2.5)
        WHEN ft = 'wood_charger' AND velocity IS NULL AND gwl >= 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity IS NULL AND gwl < 2.5
            THEN 'b'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity < -1.0 AND gwl >= 2.5
            THEN 'e'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity < -1.0 AND gwl < 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity >= -1.0 AND gwl >= 2.5
            THEN 'c'::data.foundation_risk_indication
        WHEN ft = 'wood_charger' AND velocity >= -1.0 AND gwl < 2.5
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;


--
-- Name: compute_restoration_costs(report.foundation_type, numeric); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.compute_restoration_costs(ft report.foundation_type, surface_area numeric) RETURNS integer
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE
        WHEN data.is_wood_family(ft)
            THEN (round((surface_area * 1950), -2))::integer
        WHEN ft IN ('no_pile', 'no_pile_masonry', 'no_pile_strips',
                    'no_pile_concrete_floor', 'no_pile_slit')
            THEN (round((surface_area * 350), -2))::integer
        ELSE NULL
    END;
$$;


--
-- Name: compute_unclassified_risk(boolean, data.foundation_risk_indication, data.foundation_risk_indication, report.enforcement_term, report.foundation_quality, boolean, report.foundation_damage_cause); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.compute_unclassified_risk(has_recovery boolean, recovery_risk data.foundation_risk_indication, urgent_risk data.foundation_risk_indication, enforcement_term report.enforcement_term, overall_quality report.foundation_quality, recovery_advised boolean, damage_cause report.foundation_damage_cause) RETURNS data.foundation_risk_indication
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE
        WHEN has_recovery THEN recovery_risk

        WHEN enforcement_term IN ('term05', 'term5', 'term510', 'term10',
                                   'term15', 'term1020', 'term20')
             OR recovery_advised
             OR overall_quality IN ('bad', 'mediocre_bad', 'mediocre')
             OR damage_cause IS NOT NULL
            THEN urgent_risk

        WHEN enforcement_term IN ('term25', 'term30', 'term40')
             OR overall_quality IN ('good', 'mediocre_good', 'tolerable')
            THEN 'b'::data.foundation_risk_indication

        ELSE NULL
    END;
$$;


--
-- Name: enforcement_term_years(report.enforcement_term); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.enforcement_term_years(term report.enforcement_term) RETURNS interval
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE term
        WHEN 'term05'   THEN interval '5 years'
        WHEN 'term510'  THEN interval '10 years'
        WHEN 'term1020' THEN interval '20 years'
        WHEN 'term5'    THEN interval '5 years'
        WHEN 'term10'   THEN interval '10 years'
        WHEN 'term15'   THEN interval '15 years'
        WHEN 'term20'   THEN interval '20 years'
        WHEN 'term25'   THEN interval '25 years'
        WHEN 'term30'   THEN interval '30 years'
        WHEN 'term40'   THEN interval '40 years'
        ELSE NULL
    END;
$$;


--
-- Name: ft_cell_2026_1(integer, double precision, text, numeric, numeric, integer); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.ft_cell_2026_1(construction_year integer, height double precision, soil_code text, ground_level numeric, surface_area numeric, address_count integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT
    (CASE WHEN construction_year < 1700 THEN 'a' WHEN construction_year < 1800 THEN 'b'
          WHEN construction_year < 1880 THEN 'c' WHEN construction_year < 1920 THEN 'd'
          WHEN construction_year < 1940 THEN 'e' WHEN construction_year < 1965 THEN 'f'
          WHEN construction_year < 1980 THEN 'g' ELSE 'h' END) || '|' ||
    (CASE WHEN soil_code IN ('hz','ni-hz','ni-du') THEN 'sand'
          WHEN soil_code IS NULL THEN 'unk' ELSE 'soft' END) || '|' ||
    (CASE WHEN height IS NULL THEN 'u' WHEN height < 7 THEN '0' WHEN height < 8.5 THEN '1'
          WHEN height < 10 THEN '2' WHEN height < 12 THEN '3' WHEN height < 14 THEN '4'
          WHEN height < 20 THEN '5' ELSE '6' END) || '|' ||
    (CASE WHEN ground_level IS NULL THEN 'u' WHEN ground_level < -1 THEN '0'
          WHEN ground_level < 0 THEN '1' WHEN ground_level < 1 THEN '2'
          WHEN ground_level < 3 THEN '3' WHEN ground_level < 8 THEN '4' ELSE '5' END) || '|' ||
    (CASE WHEN surface_area IS NULL THEN 'u' WHEN surface_area < 60 THEN '0'
          WHEN surface_area < 100 THEN '1' WHEN surface_area < 175 THEN '2'
          WHEN surface_area < 400 THEN '3' ELSE '4' END) || '|' ||
    (CASE WHEN address_count <= 1 THEN '0' WHEN address_count < 8 THEN '1' ELSE '2' END)
$$;


--
-- Name: ft_cell_coarse_2026_1(text); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.ft_cell_coarse_2026_1(cell text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT split_part(cell,'|',1)||'|'||split_part(cell,'|',2)||'|'||split_part(cell,'|',3)
$$;


--
-- Name: indicative_foundation_type(integer, double precision, text, integer); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.indicative_foundation_type(construction_year integer, height double precision, soil_code text, address_count integer) RETURNS report.foundation_type
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE
        -- Post-1940 large buildings: concrete
        WHEN construction_year >= 1940 AND construction_year < 1965
             AND address_count >= 8
            THEN 'concrete'::report.foundation_type

        -- Post-1965, low/unknown height, sandy soil: no_pile
        WHEN construction_year >= 1965
             AND (height < 14 OR height IS NULL)
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'no_pile'::report.foundation_type

        -- Post-1965, low/unknown height, non-sandy/unknown soil: concrete
        WHEN construction_year >= 1965
             AND (height < 14 OR height IS NULL)
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'concrete'::report.foundation_type

        -- Post-1965, tall: concrete
        WHEN construction_year >= 1965
             AND height >= 14
            THEN 'concrete'::report.foundation_type

        -- 1700-1800, low/unknown, sandy: no_pile
        WHEN construction_year >= 1700 AND construction_year < 1800
             AND (height < 14 OR height IS NULL)
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'no_pile'::report.foundation_type

        -- 1700-1800, tall, sandy: wood
        WHEN construction_year >= 1700 AND construction_year < 1800
             AND height >= 14
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'wood'::report.foundation_type

        -- 1700-1800, short, non-sandy/unknown: no_pile
        WHEN construction_year >= 1700 AND construction_year < 1800
             AND height < 8.5
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'no_pile'::report.foundation_type

        -- 1700-1800, not-short/unknown, non-sandy/unknown: wood
        WHEN construction_year >= 1700 AND construction_year < 1800
             AND (height >= 8.5 OR height IS NULL)
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'wood'::report.foundation_type

        -- 1800-1965, low/unknown, sandy: no_pile
        WHEN construction_year >= 1800 AND construction_year < 1965
             AND (height < 14 OR height IS NULL)
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'no_pile'::report.foundation_type

        -- 1800-1965, tall, sandy: wood
        WHEN construction_year >= 1800 AND construction_year < 1965
             AND height >= 14
             AND soil_code IN ('hz', 'ni-hz', 'ni-du')
            THEN 'wood'::report.foundation_type

        -- 1800-1965, short, non-sandy/unknown: no_pile
        WHEN construction_year >= 1800 AND construction_year < 1965
             AND height < 8.5
             AND soil_code NOT IN ('hz', 'ni-hz', 'ni-du')
             AND (soil_code <> 'ni-du' OR soil_code IS NULL)
            THEN 'no_pile'::report.foundation_type

        -- 1800-1920, not-short/unknown, non-sandy/unknown: wood
        WHEN construction_year >= 1800 AND construction_year < 1920
             AND (height >= 8.5 OR height IS NULL)
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'wood'::report.foundation_type

        -- 1920-1965, not-short/unknown, non-sandy/unknown: wood_charger
        WHEN construction_year >= 1920 AND construction_year < 1965
             AND (height >= 8.5 OR height IS NULL)
             AND (soil_code NOT IN ('hz', 'ni-hz', 'ni-du') OR soil_code IS NULL)
            THEN 'wood_charger'::report.foundation_type

        -- Pre-1700: no_pile
        WHEN construction_year < 1700
            THEN 'no_pile'::report.foundation_type

        -- Fallback by height
        WHEN height >= 10.5
            THEN 'wood'::report.foundation_type
        WHEN height < 10.5
            THEN 'no_pile'::report.foundation_type

        ELSE 'other'::report.foundation_type
    END;
$$;


--
-- Name: is_concrete_family(report.foundation_type); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.is_concrete_family(ft report.foundation_type) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT ft IN ('concrete', 'steel_pile');
$$;


--
-- Name: FUNCTION is_concrete_family(ft report.foundation_type); Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON FUNCTION data.is_concrete_family(ft report.foundation_type) IS 'Scoring only. A grouted steel tube pile is a concrete foundation (Don, 2026-08-22). Never call this from a model function: model-2024.1 is frozen.';


--
-- Name: is_no_pile_family(report.foundation_type); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.is_no_pile_family(ft report.foundation_type) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT ft IN (
        'no_pile', 'no_pile_masonry', 'no_pile_strips',
        'no_pile_concrete_floor', 'no_pile_slit', 'no_pile_bearing_floor'
    );
$$;


--
-- Name: is_safe_foundation(report.foundation_type); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.is_safe_foundation(ft report.foundation_type) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT ft IN ('concrete', 'weighted_pile');
$$;


--
-- Name: is_wood_family(report.foundation_type); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.is_wood_family(ft report.foundation_type) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT ft IN (
        'wood', 'wood_charger', 'wood_amsterdam', 'wood_rotterdam',
        'wood_rotterdam_amsterdam', 'wood_amsterdam_arch', 'wood_rotterdam_arch'
    );
$$;


--
-- Name: is_wood_pile(report.foundation_type); Type: FUNCTION; Schema: data; Owner: -
--

CREATE FUNCTION data.is_wood_pile(ft report.foundation_type) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT ft IN (
        'wood', 'wood_amsterdam', 'wood_rotterdam',
        'wood_rotterdam_amsterdam', 'wood_amsterdam_arch', 'wood_rotterdam_arch'
    );
$$;


--
-- Name: refresh_building_precomputed(); Type: PROCEDURE; Schema: data; Owner: -
--

CREATE PROCEDURE data.refresh_building_precomputed()
    LANGUAGE sql
    AS $$
    TRUNCATE data.building_precomputed;

    INSERT INTO data.building_precomputed (
        building_id,
        neighborhood_id,
        surface_area,
        address_count,
        construction_year_bag,
        height,
        ground_level
    )
    SELECT
        ba.external_id,
        ba.neighborhood_id,
        round(ST_Area(ba.geom::geography, true)::numeric, 2),
        COALESCE(addr.cnt, 0),
        date_part('year', ba.built_year::date)::integer,
        GREATEST(bh.height, 0)::double precision,
        round(be.ground::numeric, 2)
    FROM geocoder.building_active ba
    LEFT JOIN data.building_elevation be ON be.building_id = ba.external_id
    LEFT JOIN data.building_height bh ON bh.building_id = ba.external_id
    LEFT JOIN (
        SELECT building_id, count(*)::integer AS cnt
        FROM geocoder.address
        GROUP BY building_id
    ) addr ON addr.building_id::text = ba.external_id
    WHERE ba.building_type = 'house';
$$;


--
-- Name: generate_reference(); Type: FUNCTION; Schema: dataops; Owner: -
--

CREATE FUNCTION dataops.generate_reference() RETURNS text
    LANGUAGE sql
    AS $$
      SELECT 'FM' || date_part('year', CURRENT_DATE)::int || '-' ||
             lpad(nextval('dataops.dossier_reference_seq')::text, 6, '0');
    $$;


--
-- Name: FUNCTION generate_reference(); Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON FUNCTION dataops.generate_reference() IS 'Melder-facing dossier reference, e.g. FM2026-000042. Not a secret: sequential by design, so anything reading by reference must also check the submitter.';


--
-- Name: geocoder_generate_id(); Type: FUNCTION; Schema: geocoder; Owner: -
--

CREATE FUNCTION geocoder.geocoder_generate_id() RETURNS text
    LANGUAGE sql PARALLEL SAFE
    AS $$SELECT 'gfm-' || REPLACE(gen_random_uuid()::text, '-', '')$$;


--
-- Name: FUNCTION geocoder_generate_id(); Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON FUNCTION geocoder.geocoder_generate_id() IS 'Generates a new geocoder id.';


--
-- Name: boundaries(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.boundaries(z integer, x integer, y integer) RETURNS bytea
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    AS $$
DECLARE
    env geometry;
    env4326 geometry;
    -- one MVT pixel at this zoom, for simplification
    tol double precision;
    mvt bytea := ''::bytea;
    part bytea;
BEGIN
    -- Below municipality minzoom, or nonsense coordinates
    -- (ST_TileEnvelope would error → 500): empty tile, no table hit.
    IF z < 7 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);
    env4326 := ST_Transform(env, 4326);
    tol := (40075016.686 / (1 << z)) / 4096;

    SELECT ST_AsMVT(tile, 'municipality', 4096, 'geom') INTO part
    FROM (
        SELECT external_id AS id, name,
               ST_AsMVTGeom(
                   ST_SimplifyPreserveTopology(ST_Transform(geom, 3857), tol),
                   env, 4096, 64, true) AS geom
        FROM geocoder.municipality
        WHERE geom && env4326 AND NOT water
    ) tile
    WHERE tile.geom IS NOT NULL;
    mvt := mvt || coalesce(part, ''::bytea);

    IF z >= 10 THEN
        SELECT ST_AsMVT(tile, 'district', 4096, 'geom') INTO part
        FROM (
            SELECT external_id AS id, name,
                   ST_AsMVTGeom(
                       ST_SimplifyPreserveTopology(ST_Transform(geom, 3857), tol),
                       env, 4096, 64, true) AS geom
            FROM geocoder.district
            WHERE geom && env4326 AND NOT water
        ) tile
        WHERE tile.geom IS NOT NULL;
        mvt := mvt || coalesce(part, ''::bytea);

        SELECT ST_AsMVT(tile, 'neighborhood', 4096, 'geom') INTO part
        FROM (
            SELECT external_id AS id, name,
                   ST_AsMVTGeom(
                       ST_SimplifyPreserveTopology(ST_Transform(geom, 3857), tol),
                       env, 4096, 64, true) AS geom
            FROM geocoder.neighborhood
            WHERE geom && env4326 AND NOT water
        ) tile
        WHERE tile.geom IS NOT NULL;
        mvt := mvt || coalesce(part, ''::bytea);
    END IF;

    RETURN mvt;
END;
$$;


--
-- Name: FUNCTION boundaries(z integer, x integer, y integer); Type: COMMENT; Schema: maplayer; Owner: -
--

COMMENT ON FUNCTION maplayer.boundaries(z integer, x integer, y integer) IS '{"description": "FunderMaps admin boundaries (municipality/district/neighborhood)", "minzoom": 7, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "municipality", "minzoom": 7, "maxzoom": 16, "fields": {"id": "String", "name": "String"}}, {"id": "district", "minzoom": 10, "maxzoom": 16, "fields": {"id": "String", "name": "String"}}, {"id": "neighborhood", "minzoom": 10, "maxzoom": 16, "fields": {"id": "String", "name": "String"}}]}';


--
-- Name: building_cluster(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.building_cluster(z integer, x integer, y integer) RETURNS bytea
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    -- Below the tileset's minzoom, or nonsense coordinates
    -- (ST_TileEnvelope would error → 500): empty tile, no table hit.
    IF z < 12 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    IF z >= 14 THEN
        SELECT ST_AsMVT(tile, 'building_cluster', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                cluster_id::text AS cluster_id,
                building_count,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.building_cluster_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        -- z12–13: overview zooms. Simplified geometry, no ids (near-unique
        -- uuid strings dominate tile size), sub-pixel clusters dropped —
        -- same thresholds as building_tiles (a cluster smaller than a
        -- single big building is invisible here anyway).
        SELECT ST_AsMVT(tile, 'building_cluster', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                ST_AsMVTGeom(geom_simple, env, 4096, 8, true) AS geom
            FROM maplayer.building_cluster_tiles
            WHERE geom_simple && env
              AND surface_area >= CASE WHEN z = 12 THEN 150 ELSE 60 END
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;


--
-- Name: FUNCTION building_cluster(z integer, x integer, y integer); Type: COMMENT; Schema: maplayer; Owner: -
--

COMMENT ON FUNCTION maplayer.building_cluster(z integer, x integer, y integer) IS '{"description": "FunderMaps building cluster (bouwkundige eenheid) outlines (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "building_cluster", "minzoom": 12, "maxzoom": 16, "fields": {"cluster_id": "String", "building_count": "Number"}}]}';


--
-- Name: buildings(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.buildings(z integer, x integer, y integer) RETURNS bytea
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    -- Below the building tilesets' minzoom, or nonsense coordinates
    -- (ST_TileEnvelope would error → 500): empty tile, no table hit.
    IF z < 12 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    IF z >= 14 THEN
        SELECT ST_AsMVT(tile, 'buildings', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                building_id, neighborhood_id, district_id, municipality_id,
                address_count, construction_year, construction_year_reliability,
                foundation_type, foundation_type_reliability, restoration_costs,
                drystand, drystand_risk, drystand_risk_reliability,
                bio_infection_risk, bio_infection_risk_reliability,
                dewatering_depth, dewatering_depth_risk,
                dewatering_depth_risk_reliability, unclassified_risk,
                height, velocity, owner, inquiry_type, damage_cause,
                enforcement_term, overall_quality, recovery_type, contractor,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.building_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        -- z12–13: overview zooms. Slim tiles three ways (measured on the
        -- densest tile in the country, Amsterdam z12/2103/1346):
        --   * simplified geometry            (7.4 MB → 4.6 MB)
        --   * style attributes only, no ids  (unique building_id strings
        --     alone double a tile)           (4.6 MB → ~1.3 MB)
        --   * sub-pixel buildings dropped    (~1.3 MB → ~0.3 MB,
        --     ≈ today's static tippecanoe tile which drop-densest'd
        --     to ~0.15 MB)
        -- Click-to-select needs building_id → works from z14 up.
        SELECT ST_AsMVT(tile, 'buildings', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                -- Geofence ids are load-bearing at EVERY zoom: WebFront's
                -- geography filter shows any feature missing them (the
                -- '!has' fallback), so dropping them here exposed the whole
                -- country to fenced orgs at z12–13. They dictionary-encode
                -- well; building_id stays z14+ (near-unique = the size cost).
                neighborhood_id, district_id, municipality_id,
                construction_year, foundation_type, foundation_type_reliability,
                drystand_risk, bio_infection_risk, dewatering_depth_risk,
                unclassified_risk, recovery_type, velocity, damage_cause,
                -- contractor is set on ~5% of buildings and has ~55
                -- distinct values → dictionary-encodes to near-nothing
                inquiry_type, contractor,
                -- WebFront paints with these even at z12–13: every layer
                -- extrudes on height; owner/restoration-cost/enforcement-term/
                -- overall-quality layers and address_count filters break
                -- without them. All low-cardinality → MVT dictionary-encodes
                -- them cheaply (building_id stays z14+, it's the size killer).
                address_count, height, owner, restoration_costs,
                enforcement_term, overall_quality,
                ST_AsMVTGeom(geom_simple, env, 4096, 8, true) AS geom
            FROM maplayer.building_tiles
            WHERE geom_simple && env
              AND surface_area >= CASE WHEN z = 12 THEN 150 ELSE 60 END
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;


--
-- Name: FUNCTION buildings(z integer, x integer, y integer); Type: COMMENT; Schema: maplayer; Owner: -
--

COMMENT ON FUNCTION maplayer.buildings(z integer, x integer, y integer) IS '{"description": "FunderMaps building foundation tiles (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "buildings", "minzoom": 12, "maxzoom": 16, "fields": {"building_id": "String", "neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "address_count": "Number", "construction_year": "Number", "construction_year_reliability": "String", "foundation_type": "String", "foundation_type_reliability": "String", "restoration_costs": "Number", "drystand": "Number", "drystand_risk": "String", "drystand_risk_reliability": "String", "bio_infection_risk": "String", "bio_infection_risk_reliability": "String", "dewatering_depth": "Number", "dewatering_depth_risk": "String", "dewatering_depth_risk_reliability": "String", "unclassified_risk": "String", "height": "Number", "velocity": "Number", "owner": "String", "inquiry_type": "String", "damage_cause": "String", "enforcement_term": "Number", "overall_quality": "String", "recovery_type": "String", "contractor": "String"}}]}';


--
-- Name: facade_scan(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.facade_scan(z integer, x integer, y integer) RETURNS bytea
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    -- Below the tileset's minzoom, or nonsense coordinates
    -- (ST_TileEnvelope would error → 500): empty tile, no table hit.
    IF z < 12 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'facade_scan', 4096, 'geom') INTO mvt
    FROM (
        SELECT
            external_id,
            neighborhood_id,
            district_id,
            municipality_id,
            height,
            owner,
            skewed_parallel_facade,
            skewed_perpendicular_facade,
            facade_type,
            settlement_speed,
            facade_scan_risk,
            risk,
            priority,
            ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
        FROM maplayer.facade_scan_tiles
        WHERE geom && env
    ) tile
    WHERE tile.geom IS NOT NULL;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;


--
-- Name: FUNCTION facade_scan(z integer, x integer, y integer); Type: COMMENT; Schema: maplayer; Owner: -
--

COMMENT ON FUNCTION maplayer.facade_scan(z integer, x integer, y integer) IS '{"description": "FunderMaps QuickScan facade observations (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "facade_scan", "minzoom": 12, "maxzoom": 16, "fields": {"external_id": "String", "neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "height": "Number", "owner": "String", "skewed_parallel_facade": "String", "skewed_perpendicular_facade": "String", "facade_type": "String", "settlement_speed": "String", "facade_scan_risk": "String", "risk": "String", "priority": "String"}}]}';


--
-- Name: incident(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.incident(z integer, x integer, y integer) RETURNS bytea
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    IF z < 12 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'incident', 4096, 'geom') INTO mvt
    FROM (
        SELECT
            id,
            neighborhood_id,
            district_id,
            municipality_id,
            foundation_damage_cause,
            height,
            ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
        FROM maplayer.incident_tiles
        WHERE geom && env
    ) tile
    WHERE tile.geom IS NOT NULL;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;


--
-- Name: FUNCTION incident(z integer, x integer, y integer); Type: COMMENT; Schema: maplayer; Owner: -
--

COMMENT ON FUNCTION maplayer.incident(z integer, x integer, y integer) IS '{"description": "FunderMaps foundation incident reports (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "incident", "minzoom": 12, "maxzoom": 16, "fields": {"id": "String", "neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "foundation_damage_cause": "String", "height": "Number"}}]}';


--
-- Name: incident_district(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.incident_district(z integer, x integer, y integer) RETURNS bytea
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    IF z < 10 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    -- Indexable branches, see maplayer.incident_neighborhood().
    IF z >= 12 THEN
        SELECT ST_AsMVT(tile, 'incident_district', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                district_id,
                municipality_id,
                incident_count,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.incident_district_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        SELECT ST_AsMVT(tile, 'incident_district', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                district_id,
                municipality_id,
                incident_count,
                ST_AsMVTGeom(geom_simple, env, 4096, 64, true) AS geom
            FROM maplayer.incident_district_tiles
            WHERE geom_simple && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;


--
-- Name: FUNCTION incident_district(z integer, x integer, y integer); Type: COMMENT; Schema: maplayer; Owner: -
--

COMMENT ON FUNCTION maplayer.incident_district(z integer, x integer, y integer) IS '{"description": "FunderMaps incident counts per CBS district (dynamic)", "minzoom": 10, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "incident_district", "minzoom": 10, "maxzoom": 16, "fields": {"district_id": "String", "municipality_id": "String", "incident_count": "Number"}}]}';


--
-- Name: incident_municipality(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.incident_municipality(z integer, x integer, y integer) RETURNS bytea
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    -- This tileset is z7–11 only; geom_simple is therefore used at every
    -- zoom it serves, and the full geometry column is kept for parity with
    -- the archived GPKG and any future zoom extension.
    IF z < 7 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    SELECT ST_AsMVT(tile, 'incident_municipality', 4096, 'geom') INTO mvt
    FROM (
        SELECT
            municipality_id,
            incident_count,
            ST_AsMVTGeom(geom_simple, env, 4096, 64, true) AS geom
        FROM maplayer.incident_municipality_tiles
        WHERE geom_simple && env
    ) tile
    WHERE tile.geom IS NOT NULL;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;


--
-- Name: FUNCTION incident_municipality(z integer, x integer, y integer); Type: COMMENT; Schema: maplayer; Owner: -
--

COMMENT ON FUNCTION maplayer.incident_municipality(z integer, x integer, y integer) IS '{"description": "FunderMaps incident counts per municipality (dynamic)", "minzoom": 7, "maxzoom": 11, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "incident_municipality", "minzoom": 7, "maxzoom": 11, "fields": {"municipality_id": "String", "incident_count": "Number"}}]}';


--
-- Name: incident_neighborhood(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.incident_neighborhood(z integer, x integer, y integer) RETURNS bytea
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    AS $$
DECLARE
    env geometry;
    mvt bytea;
BEGIN
    IF z < 10 OR x < 0 OR y < 0 OR x >= (1 << z) OR y >= (1 << z) THEN
        RETURN ''::bytea;
    END IF;

    env := ST_TileEnvelope(z, x, y);

    -- Two branches rather than a CASE inside WHERE: a CASE expression over
    -- two geometry columns is not indexable, so the planner would seq-scan
    -- and evaluate && against every polygon in the table.
    IF z >= 12 THEN
        SELECT ST_AsMVT(tile, 'incident_neighborhood', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                neighborhood_id,
                district_id,
                municipality_id,
                incident_count,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.incident_neighborhood_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        SELECT ST_AsMVT(tile, 'incident_neighborhood', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                neighborhood_id,
                district_id,
                municipality_id,
                incident_count,
                ST_AsMVTGeom(geom_simple, env, 4096, 64, true) AS geom
            FROM maplayer.incident_neighborhood_tiles
            WHERE geom_simple && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    END IF;

    RETURN coalesce(mvt, ''::bytea);
END;
$$;


--
-- Name: FUNCTION incident_neighborhood(z integer, x integer, y integer); Type: COMMENT; Schema: maplayer; Owner: -
--

COMMENT ON FUNCTION maplayer.incident_neighborhood(z integer, x integer, y integer) IS '{"description": "FunderMaps incident counts per CBS neighborhood (dynamic)", "minzoom": 10, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "incident_neighborhood", "minzoom": 10, "maxzoom": 16, "fields": {"neighborhood_id": "String", "district_id": "String", "municipality_id": "String", "incident_count": "Number"}}]}';


--
-- Name: refresh_building_cluster_tiles(); Type: PROCEDURE; Schema: maplayer; Owner: -
--

CREATE PROCEDURE maplayer.refresh_building_cluster_tiles()
    LANGUAGE sql
    AS $$
    TRUNCATE maplayer.building_cluster_tiles;

    INSERT INTO maplayer.building_cluster_tiles (
        cluster_id, building_count, surface_area, geom, geom_simple
    )
    SELECT
        u.cluster_id,
        u.building_count,
        ST_Area(u.geom::geography, true),
        ST_Multi(ST_Transform(u.geom, 3857)),
        -- 5.0 Mercator units ≈ 3 m at NL latitude, matching building_tiles:
        -- invisible at z12–13, collapses dense outlines to a few points.
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(u.geom, 3857), 5.0))
    FROM (
        SELECT
            bc.cluster_id,
            count(*) AS building_count,
            ST_Union(ba.geom) AS geom
        FROM data.building_cluster bc
        JOIN geocoder.building_active ba ON ba.external_id = bc.building_id
        GROUP BY bc.cluster_id
    ) u;

    ANALYZE maplayer.building_cluster_tiles;
$$;


--
-- Name: refresh_building_tiles(); Type: PROCEDURE; Schema: maplayer; Owner: -
--

CREATE PROCEDURE maplayer.refresh_building_tiles()
    LANGUAGE sql
    AS $$
    TRUNCATE maplayer.building_tiles;

    INSERT INTO maplayer.building_tiles (
        building_id, neighborhood_id, district_id, municipality_id,
        address_count, construction_year, construction_year_reliability,
        foundation_type, foundation_type_reliability, restoration_costs,
        drystand, drystand_risk, drystand_risk_reliability,
        bio_infection_risk, bio_infection_risk_reliability,
        dewatering_depth, dewatering_depth_risk,
        dewatering_depth_risk_reliability, unclassified_risk,
        height, velocity, owner, inquiry_type, damage_cause,
        enforcement_term, overall_quality, recovery_type, contractor,
        surface_area, geom, geom_simple
    )
    SELECT
        bgh.building_id,
        bgh.ext_neighborhood_id,
        bgh.ext_district_id,
        bgh.ext_municipality_id,
        bgh.address_count,
        bgh.construction_year,
        bgh.construction_year_reliability::text,
        bgh.foundation_type::text,
        bgh.foundation_type_reliability::text,
        bgh.restoration_costs,
        bgh.drystand,
        bgh.drystand_risk::text,
        bgh.drystand_risk_reliability::text,
        bgh.bio_infection_risk::text,
        bgh.bio_infection_risk_reliability::text,
        bgh.dewatering_depth,
        bgh.dewatering_depth_risk::text,
        bgh.dewatering_depth_risk_reliability::text,
        bgh.unclassified_risk::text,
        bgh.height::double precision,
        bgh.velocity::double precision,
        bgh.owner,
        bgh.inquiry_type::text,
        bgh.damage_cause::text,
        bgh.enforcement_term,
        bgh.overall_quality::text,
        bgh.recovery_type::text,
        con.name,
        bgh.surface_area::double precision,
        ST_Transform(bgh.geom, 3857),
        -- 5.0 Mercator units ≈ 3 m at NL latitude: invisible at z12–13,
        -- collapses a 40-vertex floor plan to a handful of points.
        ST_SimplifyPreserveTopology(ST_Transform(bgh.geom, 3857), 5.0)
    FROM data.building_geo_hierarchy bgh
    -- bgh.inquiry_id is the inquiry the model picked; its attribution
    -- names the contractor that performed the research.
    LEFT JOIN report.inquiry i ON i.id = bgh.inquiry_id
    LEFT JOIN application.attribution attr ON attr.id = i.attribution_id
    LEFT JOIN application.contractor con ON con.id = attr.contractor_id
    WHERE bgh.geom IS NOT NULL;

    ANALYZE maplayer.building_tiles;
$$;


--
-- Name: refresh_facade_scan_tiles(); Type: PROCEDURE; Schema: maplayer; Owner: -
--

CREATE PROCEDURE maplayer.refresh_facade_scan_tiles()
    LANGUAGE sql
    AS $$
    TRUNCATE maplayer.facade_scan_tiles;

    INSERT INTO maplayer.facade_scan_tiles (
        external_id, neighborhood_id, district_id, municipality_id,
        height, owner, skewed_parallel_facade, skewed_perpendicular_facade,
        facade_type, settlement_speed, facade_scan_risk, risk, priority, geom
    )
    SELECT
        f.external_id,
        f.neighborhood_id,
        f.district_id,
        f.municipality_id,
        f.height::double precision,
        f.owner,
        f.skewed_parallel_facade::text,
        f.skewed_perpendicular_facade::text,
        f.facade_type::text,
        f.settlement_speed::text,
        f.facade_scan_risk::text,
        f.risk::text,
        f.priority::text,
        ST_Multi(ST_Transform(f.geom, 3857))
    FROM maplayer.facade_scan f;

    ANALYZE maplayer.facade_scan_tiles;
$$;


--
-- Name: refresh_incident_tiles(); Type: PROCEDURE; Schema: maplayer; Owner: -
--

CREATE PROCEDURE maplayer.refresh_incident_tiles()
    LANGUAGE sql
    AS $$
    TRUNCATE maplayer.incident_tiles;

    INSERT INTO maplayer.incident_tiles (
        id, neighborhood_id, district_id, municipality_id,
        foundation_damage_cause, height, geom
    )
    SELECT
        i.id,
        n.external_id,
        d.external_id,
        m.external_id,
        i.foundation_damage_cause::text,
        round(GREATEST(bh.height, 0::real)::numeric, 2)::double precision,
        ST_Multi(ST_Transform(ba.geom, 3857))
    FROM report.incident i
    JOIN geocoder.building_active ba ON ba.external_id = i.building_id::text
    JOIN data.building_height bh ON bh.building_id = ba.external_id
    -- LEFT so a building with no CBS geography keeps its tile feature, matching
    -- the view's row count exactly. All 2,728 rows resolve today; a future null
    -- degrades to "shown when fenced", never to a dropped incident.
    LEFT JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    LEFT JOIN geocoder.district d ON d.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text;

    TRUNCATE maplayer.incident_neighborhood_tiles;

    INSERT INTO maplayer.incident_neighborhood_tiles (
        neighborhood_id, district_id, municipality_id, incident_count,
        geom, geom_simple
    )
    SELECT
        n.external_id,
        d.external_id,
        m.external_id,
        count(*),
        ST_Multi(ST_Transform(n.geom, 3857)),
        -- 20 Mercator units ≈ 12 m at NL latitude: sub-pixel at z11 (76 m/px)
        -- and every zoom below it, where geom_simple is used.
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(n.geom, 3857), 20.0))
    FROM report.incident i
    JOIN geocoder.building_active ba ON ba.external_id = i.building_id::text
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    LEFT JOIN geocoder.district d ON d.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text
    GROUP BY n.external_id, d.external_id, m.external_id, n.geom;

    TRUNCATE maplayer.incident_district_tiles;

    INSERT INTO maplayer.incident_district_tiles (
        district_id, municipality_id, incident_count, geom, geom_simple
    )
    SELECT
        d.external_id,
        m.external_id,
        count(*),
        ST_Multi(ST_Transform(d.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(d.geom, 3857), 20.0))
    FROM report.incident i
    JOIN geocoder.building_active ba ON ba.external_id = i.building_id::text
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    JOIN geocoder.district d ON d.id::text = n.district_id::text
    LEFT JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text
    GROUP BY d.external_id, m.external_id, d.geom;

    TRUNCATE maplayer.incident_municipality_tiles;

    INSERT INTO maplayer.incident_municipality_tiles (
        municipality_id, incident_count, geom, geom_simple
    )
    SELECT
        m.external_id,
        count(*),
        ST_Multi(ST_Transform(m.geom, 3857)),
        ST_Multi(ST_SimplifyPreserveTopology(ST_Transform(m.geom, 3857), 20.0))
    FROM report.incident i
    JOIN geocoder.building_active ba ON ba.external_id = i.building_id::text
    JOIN geocoder.neighborhood n ON n.id::text = ba.neighborhood_id::text
    JOIN geocoder.district d ON d.id::text = n.district_id::text
    JOIN geocoder.municipality m ON m.id::text = d.municipality_id::text
    GROUP BY m.external_id, m.geom;

    ANALYZE maplayer.incident_tiles;
    ANALYZE maplayer.incident_neighborhood_tiles;
    ANALYZE maplayer.incident_district_tiles;
    ANALYZE maplayer.incident_municipality_tiles;
$$;


--
-- Name: last_record_update(); Type: FUNCTION; Schema: report; Owner: -
--

CREATE FUNCTION report.last_record_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	NEW.update_date = CURRENT_TIMESTAMP;
	RETURN NEW;
END;
$$;


--
-- Name: FUNCTION last_record_update(); Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON FUNCTION report.last_record_update() IS 'Trigger function that sets the update date when a record is updated.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: product_tracker; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.product_tracker (
    organization_id application.organization_id NOT NULL,
    product text NOT NULL,
    building_id geocoder.geocoder_id NOT NULL,
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    identifier text NOT NULL
);


--
-- Name: account; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.account (
    id text NOT NULL,
    user_id uuid NOT NULL,
    account_id text NOT NULL,
    provider_id text NOT NULL,
    access_token text,
    refresh_token text,
    access_token_expires_at timestamp without time zone,
    refresh_token_expires_at timestamp without time zone,
    scope text,
    id_token text,
    password text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    issuer text DEFAULT 'local:credential'::text NOT NULL
);


--
-- Name: api_key_rate_limit; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.api_key_rate_limit (
    api_key_id text NOT NULL,
    source text NOT NULL,
    product text NOT NULL,
    period text NOT NULL,
    limit_count integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT api_key_rate_limit_limit_count_check CHECK ((limit_count >= 0)),
    CONSTRAINT api_key_rate_limit_period_check CHECK ((period = ANY (ARRAY['day'::text, 'month'::text]))),
    CONSTRAINT api_key_rate_limit_source_check CHECK ((source = ANY (ARRAY['ba'::text, 'legacy'::text])))
);


--
-- Name: TABLE api_key_rate_limit; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.api_key_rate_limit IS 'Per-(API key, product) billing-event rate limits enforced by FunderMapsWebservice.';


--
-- Name: COLUMN api_key_rate_limit.source; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON COLUMN application.api_key_rate_limit.source IS '''ba'' = application.apikey, ''legacy'' = application.auth_key (key id is unique within a source, not across).';


--
-- Name: COLUMN api_key_rate_limit.product; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON COLUMN application.api_key_rate_limit.product IS 'Tracker product name, e.g. analysis3, risk3, light3, statistics3.';


--
-- Name: COLUMN api_key_rate_limit.period; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON COLUMN application.api_key_rate_limit.period IS 'Calendar window: ''day'' resets at UTC midnight; ''month'' resets at first-of-month UTC.';


--
-- Name: COLUMN api_key_rate_limit.limit_count; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON COLUMN application.api_key_rate_limit.limit_count IS 'Max billable events allowed within one period. Absent row = unlimited.';


--
-- Name: apikey; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.apikey (
    id text NOT NULL,
    config_id text DEFAULT 'default'::text NOT NULL,
    name text,
    start text,
    reference_id uuid NOT NULL,
    prefix text,
    key text NOT NULL,
    refill_interval integer,
    refill_amount integer,
    last_refill_at timestamp with time zone,
    enabled boolean DEFAULT true,
    rate_limit_enabled boolean DEFAULT true,
    rate_limit_time_window integer,
    rate_limit_max integer,
    request_count integer DEFAULT 0,
    remaining integer,
    last_request timestamp with time zone,
    expires_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    permissions text,
    metadata text
);


--
-- Name: application; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.application (
    application_id text DEFAULT concat('app-', application.random_string(8)) NOT NULL,
    name text NOT NULL,
    data jsonb,
    secret text DEFAULT concat('app-sk-', application.random_string(32)) NOT NULL,
    redirect_url text,
    public boolean DEFAULT false NOT NULL,
    user_id application.user_id
);


--
-- Name: TABLE application; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.application IS 'Contains all applications.';


--
-- Name: application_user; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.application_user (
    user_id application.user_id NOT NULL,
    application_id text NOT NULL,
    metadata jsonb,
    update_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE application_user; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.application_user IS 'Linking table between application and user.';


--
-- Name: attribution; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.attribution (
    id integer NOT NULL,
    reviewer_id application.user_id NOT NULL,
    creator_id application.user_id NOT NULL,
    owner_id application.organization_id NOT NULL,
    contractor_id integer NOT NULL,
    CONSTRAINT creator_reviewer_chk CHECK (((creator_id)::uuid <> (reviewer_id)::uuid))
);


--
-- Name: TABLE attribution; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.attribution IS 'Intermediate object between an uploaded sample or report and the assigned user reviewer or owner. In case of user deletion a reference still exists, only the reference to said user or owner will be set to NULL.';


--
-- Name: attribution_id_seq; Type: SEQUENCE; Schema: application; Owner: -
--

CREATE SEQUENCE application.attribution_id_seq
    START WITH 50000
    INCREMENT BY 1
    MINVALUE 50000
    NO MAXVALUE
    CACHE 1;


--
-- Name: attribution_id_seq; Type: SEQUENCE OWNED BY; Schema: application; Owner: -
--

ALTER SEQUENCE application.attribution_id_seq OWNED BY application.attribution.id;


--
-- Name: auth_key; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.auth_key (
    user_id uuid NOT NULL,
    name text,
    last_used timestamp with time zone,
    key_hash text NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: contractor; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.contractor (
    id integer NOT NULL,
    name text
);


--
-- Name: contractor_id_seq; Type: SEQUENCE; Schema: application; Owner: -
--

CREATE SEQUENCE application.contractor_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contractor_id_seq; Type: SEQUENCE OWNED BY; Schema: application; Owner: -
--

ALTER SEQUENCE application.contractor_id_seq OWNED BY application.contractor.id;


--
-- Name: file_resources; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.file_resources (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    original_filename text NOT NULL,
    status text DEFAULT 'uploaded'::public.resource_status NOT NULL,
    size_bytes bigint,
    mime_type text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE file_resources; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.file_resources IS 'Stores metadata about file resources stored in an S3-compatible object storage.';


--
-- Name: file_resources_orphaned; Type: VIEW; Schema: application; Owner: -
--

CREATE VIEW application.file_resources_orphaned AS
 SELECT id,
    key,
    original_filename,
    status,
    size_bytes,
    mime_type,
    metadata,
    created_at,
    updated_at
   FROM application.file_resources
  WHERE ((status = ANY (ARRAY['uploaded'::text, 'processing'::text])) AND (updated_at < (now() - '1 day'::interval)));


--
-- Name: invitation; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.invitation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id application.organization_id NOT NULL,
    email text NOT NULL,
    role text DEFAULT 'reader'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    team_id uuid,
    inviter_id application.user_id NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invitation_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'rejected'::text, 'canceled'::text])))
);


--
-- Name: TABLE invitation; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.invitation IS 'Better Auth organization-plugin invitations (Phase 2).';


--
-- Name: jwks; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.jwks (
    id text NOT NULL,
    public_key text NOT NULL,
    private_key text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    expires_at timestamp without time zone,
    alg text,
    crv text
);


--
-- Name: mapset; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.mapset (
    id text NOT NULL,
    name text,
    style text NOT NULL,
    layers text[],
    public boolean DEFAULT false NOT NULL,
    consent text,
    note text,
    icon text,
    metadata jsonb,
    "order" integer DEFAULT 0 NOT NULL
);


--
-- Name: mapset_layer; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.mapset_layer (
    id text NOT NULL,
    name text NOT NULL,
    fields jsonb NOT NULL,
    "order" integer DEFAULT 0 NOT NULL
);


--
-- Name: mapset_collection; Type: VIEW; Schema: application; Owner: -
--

CREATE VIEW application.mapset_collection AS
 SELECT id,
    name,
    lower(regexp_replace(name, '\s+'::text, '-'::text, 'g'::text)) AS slug,
    style,
    metadata,
    public,
    consent,
    note,
    icon,
    "order",
    ( SELECT jsonb_agg(maplayers.layer) AS jsonb_agg
           FROM ( SELECT l.*::application.mapset_layer AS layer
                   FROM application.mapset_layer l
                  WHERE (l.id IN ( SELECT unnest(m2.layers) AS unnest
                           FROM application.mapset m2
                          WHERE (m2.id = m.id)))
                  ORDER BY l."order") maplayers) AS layerset
   FROM application.mapset m;


--
-- Name: oauth_access_token; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.oauth_access_token (
    id text NOT NULL,
    token text NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    client_id text NOT NULL,
    user_id uuid,
    scopes text[] NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    session_id text,
    reference_id text,
    refresh_id text,
    authorization_code_id text,
    resources text[],
    requested_user_info_claims text[],
    revoked timestamp without time zone,
    confirmation jsonb
);


--
-- Name: oauth_application; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.oauth_application (
    id text NOT NULL,
    name text NOT NULL,
    icon text,
    metadata jsonb,
    client_id text NOT NULL,
    client_secret text,
    disabled boolean DEFAULT false,
    user_id uuid,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    skip_consent boolean DEFAULT false NOT NULL,
    redirect_uris text[] NOT NULL,
    post_logout_redirect_uris text[],
    scopes text[],
    grant_types text[],
    response_types text[],
    contacts text[],
    require_pkce boolean,
    enable_end_session boolean,
    subject_type text,
    uri text,
    tos text,
    policy text,
    software_id text,
    software_version text,
    software_statement text,
    token_endpoint_auth_method text,
    reference_id text,
    application_type text,
    client_credentials_scopes text[] DEFAULT '{}'::text[] NOT NULL,
    client_discovery_id text,
    backchannel_logout_uri text,
    backchannel_logout_session_required boolean,
    jwks text,
    jwks_uri text,
    dpop_bound_access_tokens boolean DEFAULT false
);


--
-- Name: oauth_client_assertion; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.oauth_client_assertion (
    id text NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: oauth_client_resource; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.oauth_client_resource (
    id text NOT NULL,
    client_id text NOT NULL,
    resource_id text NOT NULL,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: oauth_consent; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.oauth_consent (
    id text NOT NULL,
    client_id text NOT NULL,
    user_id uuid,
    scopes text[] NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    reference_id text,
    resources text[],
    requested_user_info_claims text[]
);


--
-- Name: oauth_refresh_token; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.oauth_refresh_token (
    id text NOT NULL,
    token text NOT NULL,
    client_id text NOT NULL,
    session_id text,
    user_id uuid NOT NULL,
    reference_id text,
    expires_at timestamp without time zone NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    revoked timestamp without time zone,
    auth_time timestamp without time zone,
    scopes text[] NOT NULL,
    authorization_code_id text,
    resources text[],
    requested_user_info_claims text[],
    rotated_at timestamp without time zone,
    rotation_replay_response text,
    rotation_replay_expires_at timestamp without time zone,
    confirmation jsonb
);


--
-- Name: oauth_resource; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.oauth_resource (
    id text NOT NULL,
    identifier text NOT NULL,
    name text NOT NULL,
    access_token_ttl integer,
    refresh_token_ttl integer,
    signing_algorithm text,
    signing_key_id text,
    allowed_scopes text[],
    custom_claims jsonb,
    dpop_bound_access_tokens_required boolean DEFAULT false NOT NULL,
    disabled boolean DEFAULT false NOT NULL,
    policy_version integer DEFAULT 1 NOT NULL,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: organization; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.organization (
    id application.organization_id DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    logo text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE organization; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.organization IS 'Contains all organizations that are using FunderMaps.';


--
-- Name: organization_custom_role; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.organization_custom_role (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id application.organization_id NOT NULL,
    role text NOT NULL,
    permission jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


--
-- Name: TABLE organization_custom_role; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.organization_custom_role IS 'Better Auth dynamic access control: admin-defined per-organization roles with a JSON permission map (resource -> actions). Named *_custom_role because application.organization_role is the role enum type.';


--
-- Name: organization_geolock_district; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.organization_geolock_district (
    organization_id application.organization_id NOT NULL,
    district_id text NOT NULL
);


--
-- Name: TABLE organization_geolock_district; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.organization_geolock_district IS 'Linking table between organizations and their geolock objects.';


--
-- Name: organization_geolock_municipality; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.organization_geolock_municipality (
    organization_id application.organization_id NOT NULL,
    municipality_id text NOT NULL
);


--
-- Name: TABLE organization_geolock_municipality; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.organization_geolock_municipality IS 'Linking table between organizations and their geolock objects.';


--
-- Name: organization_geolock_neighborhood; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.organization_geolock_neighborhood (
    organization_id application.organization_id NOT NULL,
    neighborhood_id text NOT NULL
);


--
-- Name: TABLE organization_geolock_neighborhood; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.organization_geolock_neighborhood IS 'Linking table between organizations and their geolock objects.';


--
-- Name: organization_mapset; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.organization_mapset (
    organization_id application.organization_id NOT NULL,
    mapset_id text NOT NULL,
    metadata jsonb
);


--
-- Name: organization_user; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.organization_user (
    user_id application.user_id NOT NULL,
    organization_id application.organization_id NOT NULL,
    role application.organization_role DEFAULT 'reader'::application.organization_role NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE organization_user; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.organization_user IS 'Linking table between organizations and their users.';


--
-- Name: session; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.session (
    id text NOT NULL,
    user_id uuid NOT NULL,
    token text NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    ip_address text,
    user_agent text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    impersonated_by uuid,
    active_organization_id application.organization_id
);


--
-- Name: user; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application."user" (
    id application.user_id DEFAULT gen_random_uuid() NOT NULL,
    given_name text,
    last_name text,
    email application.email NOT NULL,
    avatar text,
    job_title text,
    phone_number application.phone,
    role application.role DEFAULT 'user'::application.role NOT NULL,
    name text,
    email_verified boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    banned boolean,
    ban_reason text,
    ban_expires timestamp without time zone
);


--
-- Name: TABLE "user"; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application."user" IS 'Contains all FunderMaps users.';


--
-- Name: verification; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.verification (
    id text NOT NULL,
    identifier text NOT NULL,
    value text NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: worker_jobs; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.worker_jobs (
    id bigint NOT NULL,
    job_type text NOT NULL,
    payload jsonb,
    status application.job_status DEFAULT 'pending'::application.job_status NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    retry_count integer DEFAULT 0 NOT NULL,
    max_retries integer DEFAULT 3 NOT NULL,
    last_error text,
    process_after timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: worker_jobs_id_seq; Type: SEQUENCE; Schema: application; Owner: -
--

CREATE SEQUENCE application.worker_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: worker_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: application; Owner: -
--

ALTER SEQUENCE application.worker_jobs_id_seq OWNED BY application.worker_jobs.id;


--
-- Name: building_cluster; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_cluster (
    building_id text NOT NULL,
    cluster_id uuid NOT NULL
);


--
-- Name: building_elevation; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_elevation (
    building_id text NOT NULL,
    ground real,
    roof real,
    height real GENERATED ALWAYS AS ((roof - ground)) STORED
);


--
-- Name: building_geographic_region; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_geographic_region (
    building_id text NOT NULL,
    geographic_region_id integer NOT NULL,
    code text NOT NULL
);


--
-- Name: building_groundwater_level; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_groundwater_level (
    building_id text NOT NULL,
    level double precision NOT NULL
);


--
-- Name: building_ownership; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_ownership (
    building_id text NOT NULL,
    owner text NOT NULL
);


--
-- Name: building_pleistocene; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_pleistocene (
    building_id text NOT NULL,
    depth double precision
);


--
-- Name: building_precomputed; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_precomputed (
    building_id text NOT NULL,
    neighborhood_id text,
    surface_area numeric(10,2),
    address_count integer DEFAULT 0 NOT NULL,
    construction_year_bag integer,
    height double precision,
    ground_level numeric(5,2)
);


--
-- Name: building; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.building (
    id geocoder.geocoder_id DEFAULT geocoder.geocoder_generate_id() NOT NULL,
    built_year geocoder.year,
    active boolean NOT NULL,
    geom public.geometry(MultiPolygon,4326) NOT NULL,
    external_id text NOT NULL,
    building_type geocoder.building_type,
    neighborhood_id geocoder.geocoder_id,
    zone_function geocoder.zone_function[]
);


--
-- Name: TABLE building; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON TABLE geocoder.building IS 'Contains all buildings in our own format.';


--
-- Name: inquiry; Type: TABLE; Schema: report; Owner: -
--

CREATE TABLE report.inquiry (
    id integer NOT NULL,
    document_name text NOT NULL,
    inspection boolean DEFAULT false NOT NULL,
    joint_measurement boolean DEFAULT false NOT NULL,
    floor_measurement boolean DEFAULT false NOT NULL,
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_date timestamp with time zone,
    delete_date timestamp with time zone,
    note text,
    document_date date NOT NULL,
    document_file text NOT NULL,
    attribution_id integer NOT NULL,
    access_policy application.access_policy DEFAULT 'private'::application.access_policy NOT NULL,
    type report.inquiry_type NOT NULL,
    standard_f3o boolean DEFAULT false NOT NULL,
    audit_status report.audit_status DEFAULT 'todo'::report.audit_status NOT NULL,
    data_owner_organization_id application.organization_id
);


--
-- Name: TABLE inquiry; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON TABLE report.inquiry IS 'Contains inquiries.';


--
-- Name: COLUMN inquiry.document_name; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.inquiry.document_name IS 'User provided document name';


--
-- Name: COLUMN inquiry.create_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.inquiry.create_date IS 'Timestamp of record creation, set by insert';


--
-- Name: COLUMN inquiry.update_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.inquiry.update_date IS 'Timestamp of last record update, automatically updated on record modification';


--
-- Name: COLUMN inquiry.delete_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.inquiry.delete_date IS 'Timestamp of soft delete';


--
-- Name: COLUMN inquiry.data_owner_organization_id; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.inquiry.data_owner_organization_id IS 'Organization that owns this inquiry''s data (#973). Durable owner, independent of the processing/attribution account; nullable until backfilled (Phase 2), then falls back to attribution.owner_id in the API.';


--
-- Name: inquiry_sample; Type: TABLE; Schema: report; Owner: -
--

CREATE TABLE report.inquiry_sample (
    id integer NOT NULL,
    inquiry_id integer NOT NULL,
    address geocoder.geocoder_id DEFAULT NULL::text,
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_date timestamp with time zone,
    delete_date timestamp with time zone,
    note text,
    built_year report.year,
    substructure report.substructure,
    overall_quality report.foundation_quality,
    wood_quality report.wood_quality,
    construction_quality report.quality,
    wood_capacity_horizontal_quality report.quality,
    pile_wood_capacity_vertical_quality report.quality,
    carrying_capacity_quality report.quality,
    mason_quality report.quality,
    wood_quality_necessity boolean,
    construction_level report.height,
    wood_level report.height,
    pile_diameter_top report.diameter,
    pile_diameter_bottom report.diameter,
    pile_head_level report.height,
    pile_tip_level report.height,
    foundation_depth report.height,
    mason_level report.height,
    concrete_charger_length report.length,
    pile_distance_length report.length,
    wood_penetration_depth report.length,
    cpt text,
    monitoring_well text,
    groundwater_level_temp report.height,
    groundlevel report.height,
    groundwater_level_net report.height,
    foundation_type report.foundation_type,
    enforcement_term report.enforcement_term,
    recovery_advised boolean,
    damage_cause report.foundation_damage_cause,
    damage_characteristics report.foundation_damage_characteristics,
    construction_pile report.construction_pile,
    wood_type report.wood_type,
    wood_encroachment report.wood_encroachment,
    crack_indoor_restored boolean,
    crack_indoor_type report.crack_type,
    crack_indoor_size report.crack_size,
    crack_facade_front_restored boolean,
    crack_facade_front_type report.crack_type,
    crack_facade_front_size report.crack_size,
    crack_facade_back_restored boolean,
    crack_facade_back_type report.crack_type,
    crack_facade_back_size report.crack_size,
    crack_facade_left_restored boolean,
    crack_facade_left_type report.crack_type,
    crack_facade_left_size report.crack_size,
    crack_facade_right_restored boolean,
    crack_facade_right_type report.crack_type,
    crack_facade_right_size report.crack_size,
    deformed_facade boolean,
    threshold_updown_skewed boolean,
    threshold_front_level report.height,
    threshold_back_level report.height,
    skewed_parallel report.length,
    skewed_perpendicular report.length,
    skewed_parallel_facade report.rotation_type,
    settlement_speed double precision,
    skewed_window_frame boolean,
    skewed_perpendicular_facade report.rotation_type,
    building_id geocoder.geocoder_id NOT NULL,
    facade_scan_risk report.facade_scan_risk,
    metadata jsonb,
    CONSTRAINT inquiry_sample_built_year_not_future CHECK (((built_year IS NULL) OR ((built_year)::date <= CURRENT_DATE))),
    CONSTRAINT inquiry_sample_settlement_speed_nonpositive CHECK (((settlement_speed IS NULL) OR (settlement_speed <= (0)::double precision)))
);


--
-- Name: TABLE inquiry_sample; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON TABLE report.inquiry_sample IS 'Contains sample data for inquiries.';


--
-- Name: COLUMN inquiry_sample.create_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.inquiry_sample.create_date IS 'Timestamp of record creation, set by insert';


--
-- Name: COLUMN inquiry_sample.update_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.inquiry_sample.update_date IS 'Timestamp of last record update, automatically updated on record modification';


--
-- Name: COLUMN inquiry_sample.delete_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.inquiry_sample.delete_date IS 'Timestamp of soft delete';


--
-- Name: building_sample; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.building_sample AS
 WITH ranked AS (
         SELECT DISTINCT ON (b.external_id) b.external_id AS building_id,
            is2.foundation_type,
            is2.enforcement_term,
            is2.damage_cause,
            is2.overall_quality,
            is2.recovery_advised,
            (date_part('year'::text, (is2.built_year)::date))::integer AS built_year,
            is2.groundwater_level_temp AS groundwater_level,
            is2.wood_level,
            is2.foundation_depth,
            i.type AS inquiry_type,
            i.document_date,
            i.id
           FROM ((report.inquiry_sample is2
             JOIN report.inquiry i ON ((is2.inquiry_id = i.id)))
             JOIN geocoder.building b ON ((b.external_id = (is2.building_id)::text)))
          WHERE (i.document_date >= ((b.built_year)::date - '5 years'::interval))
          ORDER BY b.external_id,
                CASE i.type
                    WHEN 'foundation_research'::report.inquiry_type THEN 0
                    WHEN 'inspectionpit'::report.inquiry_type THEN 1
                    WHEN 'second_opinion'::report.inquiry_type THEN 2
                    WHEN 'note'::report.inquiry_type THEN 3
                    WHEN 'additional_research'::report.inquiry_type THEN 4
                    WHEN 'demolition_research'::report.inquiry_type THEN 5
                    WHEN 'architectural_research'::report.inquiry_type THEN 6
                    WHEN 'archive_research'::report.inquiry_type THEN 7
                    WHEN 'quickscan'::report.inquiry_type THEN 8
                    ELSE 100
                END, i.document_date DESC
        ), facade AS (
         SELECT DISTINCT ON ((is2.building_id)::text) (is2.building_id)::text AS building_id,
            is2.facade_scan_risk
           FROM (report.inquiry_sample is2
             JOIN report.inquiry i ON ((i.id = is2.inquiry_id)))
          WHERE (is2.facade_scan_risk IS NOT NULL)
          ORDER BY (is2.building_id)::text, i.document_date DESC
        )
 SELECT r.building_id,
    r.foundation_type,
    r.enforcement_term,
    r.damage_cause,
    r.overall_quality,
    r.recovery_advised,
    r.built_year,
    r.groundwater_level,
    r.wood_level,
    r.foundation_depth,
    f.facade_scan_risk,
    r.inquiry_type,
    r.document_date,
    r.id
   FROM (ranked r
     LEFT JOIN facade f ON ((f.building_id = r.building_id)))
  WITH NO DATA;


--
-- Name: building_subsidence; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_subsidence (
    building_id text NOT NULL,
    velocity double precision NOT NULL
);


--
-- Name: cluster_recovery_sample; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.cluster_recovery_sample (
    cluster_id uuid NOT NULL,
    type report.recovery_type
);


--
-- Name: cluster_sample; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.cluster_sample AS
 SELECT DISTINCT ON (bc.cluster_id) bc.cluster_id,
    is2.foundation_type,
    is2.enforcement_term,
    is2.damage_cause,
    is2.overall_quality,
    is2.recovery_advised,
    (date_part('year'::text, (is2.built_year)::date))::integer AS built_year,
    is2.groundwater_level_temp AS groundwater_level,
    is2.wood_level,
    is2.foundation_depth,
    i.type AS inquiry_type,
    i.document_date,
    i.id
   FROM (((data.building_cluster bc
     JOIN geocoder.building b ON ((b.external_id = bc.building_id)))
     JOIN report.inquiry_sample is2 ON (((is2.building_id)::text = b.external_id)))
     JOIN report.inquiry i ON ((is2.inquiry_id = i.id)))
  WHERE (i.document_date >= ((b.built_year)::date - '5 years'::interval))
  ORDER BY bc.cluster_id,
        CASE i.type
            WHEN 'foundation_research'::report.inquiry_type THEN 0
            WHEN 'inspectionpit'::report.inquiry_type THEN 1
            WHEN 'second_opinion'::report.inquiry_type THEN 2
            WHEN 'note'::report.inquiry_type THEN 3
            WHEN 'additional_research'::report.inquiry_type THEN 4
            WHEN 'demolition_research'::report.inquiry_type THEN 5
            WHEN 'architectural_research'::report.inquiry_type THEN 6
            WHEN 'archive_research'::report.inquiry_type THEN 7
            WHEN 'quickscan'::report.inquiry_type THEN 8
            ELSE 100
        END, i.document_date DESC
  WITH NO DATA;


--
-- Name: supercluster; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.supercluster (
    cluster_id uuid NOT NULL,
    supercluster_id uuid NOT NULL
);


--
-- Name: supercluster_sample; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.supercluster_sample AS
 SELECT DISTINCT ON (s.supercluster_id) s.supercluster_id,
    is2.foundation_type,
    is2.enforcement_term,
    is2.damage_cause,
    is2.overall_quality,
    is2.recovery_advised,
    (date_part('year'::text, (is2.built_year)::date))::integer AS built_year,
    is2.groundwater_level_temp AS groundwater_level,
    is2.wood_level,
    is2.foundation_depth,
    i.type AS inquiry_type,
    i.document_date,
    i.id
   FROM ((((data.supercluster s
     JOIN data.building_cluster bc ON ((bc.cluster_id = s.cluster_id)))
     JOIN geocoder.building b ON ((b.external_id = bc.building_id)))
     JOIN report.inquiry_sample is2 ON (((is2.building_id)::text = b.external_id)))
     JOIN report.inquiry i ON ((is2.inquiry_id = i.id)))
  WHERE (i.document_date >= ((b.built_year)::date - '5 years'::interval))
  ORDER BY s.supercluster_id,
        CASE i.type
            WHEN 'foundation_research'::report.inquiry_type THEN 0
            WHEN 'inspectionpit'::report.inquiry_type THEN 1
            WHEN 'second_opinion'::report.inquiry_type THEN 2
            WHEN 'note'::report.inquiry_type THEN 3
            WHEN 'additional_research'::report.inquiry_type THEN 4
            WHEN 'demolition_research'::report.inquiry_type THEN 5
            WHEN 'architectural_research'::report.inquiry_type THEN 6
            WHEN 'archive_research'::report.inquiry_type THEN 7
            WHEN 'quickscan'::report.inquiry_type THEN 8
            ELSE 100
        END, i.document_date DESC
  WITH NO DATA;


--
-- Name: recovery_sample; Type: TABLE; Schema: report; Owner: -
--

CREATE TABLE report.recovery_sample (
    id integer NOT NULL,
    recovery_id integer NOT NULL,
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_date timestamp with time zone,
    delete_date timestamp with time zone,
    note text,
    status report.recovery_status,
    type report.recovery_type DEFAULT 'unknown'::report.recovery_type NOT NULL,
    pile_type report.pile_type,
    facade report.facade[],
    permit text,
    permit_date date,
    recovery_date date,
    contractor_id integer,
    building_id text NOT NULL,
    metadata jsonb
);


--
-- Name: TABLE recovery_sample; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON TABLE report.recovery_sample IS 'Contains sample data for recovery operations.';


--
-- Name: COLUMN recovery_sample.create_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.recovery_sample.create_date IS 'Timestamp of record creation, set by insert';


--
-- Name: COLUMN recovery_sample.update_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.recovery_sample.update_date IS 'Timestamp of last record update, automatically updated on record modification';


--
-- Name: COLUMN recovery_sample.delete_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.recovery_sample.delete_date IS 'Timestamp of soft delete';


--
-- Name: model_risk_dynamic_all; Type: VIEW; Schema: data; Owner: -
--

CREATE VIEW data.model_risk_dynamic_all AS
 SELECT building_id,
    address_count,
    neighborhood_id,
    construction_year,
    construction_year_reliability,
    foundation_type,
    foundation_type_reliability,
    restoration_costs,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    COALESCE(unclassified_risk,
        CASE
            WHEN ((drystand_risk IS NULL) AND (bio_infection_risk IS NULL) AND (dewatering_depth_risk IS NULL)) THEN
            CASE
                WHEN (construction_year < 1970) THEN 'd'::data.foundation_risk_indication
                WHEN (construction_year >= 1970) THEN 'b'::data.foundation_risk_indication
                ELSE NULL::data.foundation_risk_indication
            END
            ELSE NULL::data.foundation_risk_indication
        END) AS unclassified_risk,
    height,
    velocity,
    ground_water_level,
    ground_level,
    soil,
    surface_area,
    owner,
    inquiry_id,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    recovery_type
   FROM ( SELECT bp.building_id,
            bp.address_count,
            bp.neighborhood_id,
            COALESCE(established.built_year, bp.construction_year_bag) AS construction_year,
                CASE
                    WHEN (established.built_year IS NOT NULL) THEN 'established'::data.reliability
                    ELSE 'indicative'::data.reliability
                END AS construction_year_reliability,
            foundation_type.ft AS foundation_type,
                CASE
                    WHEN (established.foundation_type IS NOT NULL) THEN 'established'::data.reliability
                    WHEN (cluster.foundation_type IS NOT NULL) THEN 'cluster'::data.reliability
                    WHEN (supercluster.foundation_type IS NOT NULL) THEN 'supercluster'::data.reliability
                    ELSE 'indicative'::data.reliability
                END AS foundation_type_reliability,
            data.compute_restoration_costs(foundation_type.ft, bp.surface_area) AS restoration_costs,
                CASE
                    WHEN ((established.wood_level IS NOT NULL) AND (established.groundwater_level IS NOT NULL)) THEN (((established.wood_level)::numeric - (established.groundwater_level)::numeric))::double precision
                    WHEN ((cluster.wood_level IS NOT NULL) AND (cluster.groundwater_level IS NOT NULL)) THEN (((cluster.wood_level)::numeric - (cluster.groundwater_level)::numeric))::double precision
                    WHEN (foundation_type.ft = 'wood_charger'::report.foundation_type) THEN (gwl.level - (2.5)::double precision)
                    WHEN data.is_wood_pile(foundation_type.ft) THEN (gwl.level - (1.5)::double precision)
                    ELSE NULL::double precision
                END AS drystand,
            COALESCE(((established.facade_scan_risk)::text)::data.foundation_risk_indication, data.compute_damage_risk((recovery.type IS NOT NULL), established.damage_cause, ARRAY['drystand'::report.foundation_damage_cause, 'fungus_infection'::report.foundation_damage_cause, 'bio_fungus_infection'::report.foundation_damage_cause], established.enforcement_term, established.overall_quality, established.recovery_advised), data.compute_damage_risk(false, cluster.damage_cause, ARRAY['drystand'::report.foundation_damage_cause, 'fungus_infection'::report.foundation_damage_cause, 'bio_fungus_infection'::report.foundation_damage_cause], cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised), data.compute_indicative_drystand_risk(foundation_type.ft, bs.velocity, gwl.level, (recovery.type IS NOT NULL))) AS drystand_risk,
                CASE
                    WHEN (established.facade_scan_risk IS NOT NULL) THEN 'established'::data.reliability
                    WHEN (established.id IS NOT NULL) THEN 'established'::data.reliability
                    WHEN (cluster.id IS NOT NULL) THEN 'cluster'::data.reliability
                    ELSE 'indicative'::data.reliability
                END AS drystand_risk_reliability,
            COALESCE(((established.facade_scan_risk)::text)::data.foundation_risk_indication, data.compute_damage_risk((recovery.type IS NOT NULL), established.damage_cause, ARRAY['bio_infection'::report.foundation_damage_cause], established.enforcement_term, established.overall_quality, established.recovery_advised), data.compute_damage_risk(false, cluster.damage_cause, ARRAY['bio_infection'::report.foundation_damage_cause], cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised), data.compute_indicative_bio_risk(foundation_type.ft, pile_length.pile_length, bs.velocity, (recovery.type IS NOT NULL))) AS bio_infection_risk,
                CASE
                    WHEN (established.facade_scan_risk IS NOT NULL) THEN 'established'::data.reliability
                    WHEN (established.id IS NOT NULL) THEN 'established'::data.reliability
                    WHEN (cluster.id IS NOT NULL) THEN 'cluster'::data.reliability
                    ELSE 'indicative'::data.reliability
                END AS bio_infection_risk_reliability,
                CASE
                    WHEN ((established.foundation_depth IS NOT NULL) AND (established.groundwater_level IS NOT NULL)) THEN ((((established.foundation_depth)::numeric - (established.groundwater_level)::numeric) - 0.6))::double precision
                    WHEN ((cluster.foundation_depth IS NOT NULL) AND (cluster.groundwater_level IS NOT NULL)) THEN ((((cluster.foundation_depth)::numeric - (cluster.groundwater_level)::numeric) - 0.6))::double precision
                    WHEN data.is_no_pile_family(foundation_type.ft) THEN (gwl.level - (0.6)::double precision)
                    ELSE NULL::double precision
                END AS dewatering_depth,
            COALESCE(((established.facade_scan_risk)::text)::data.foundation_risk_indication, data.compute_damage_risk((recovery.type IS NOT NULL), established.damage_cause, ARRAY['drainage'::report.foundation_damage_cause], established.enforcement_term, established.overall_quality, established.recovery_advised), data.compute_damage_risk(false, cluster.damage_cause, ARRAY['drainage'::report.foundation_damage_cause], cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised), data.compute_indicative_dewatering_risk(foundation_type.ft, bs.velocity, gwl.level, (recovery.type IS NOT NULL))) AS dewatering_depth_risk,
                CASE
                    WHEN (established.facade_scan_risk IS NOT NULL) THEN 'established'::data.reliability
                    WHEN (established.id IS NOT NULL) THEN 'established'::data.reliability
                    WHEN (cluster.id IS NOT NULL) THEN 'cluster'::data.reliability
                    ELSE 'indicative'::data.reliability
                END AS dewatering_depth_risk_reliability,
            COALESCE(data.compute_unclassified_risk((recovery.type IS NOT NULL), 'a'::data.foundation_risk_indication, 'e'::data.foundation_risk_indication, established.enforcement_term, established.overall_quality, established.recovery_advised, established.damage_cause), data.compute_unclassified_risk((cluster_recovery_sample.type IS NOT NULL), 'e'::data.foundation_risk_indication, 'd'::data.foundation_risk_indication, cluster.enforcement_term, cluster.overall_quality, cluster.recovery_advised, cluster.damage_cause)) AS unclassified_risk,
            (bp.height)::numeric(10,2) AS height,
            round((bs.velocity)::numeric, 2) AS velocity,
            round((gwl.level)::numeric, 2) AS ground_water_level,
            bp.ground_level,
            gr.code AS soil,
            bp.surface_area,
            bo.owner,
            established.id AS inquiry_id,
            established.inquiry_type,
            COALESCE(established.damage_cause, cluster.damage_cause) AS damage_cause,
            date_part('years'::text, age(((COALESCE(established.document_date, cluster.document_date) + data.enforcement_term_years(COALESCE(established.enforcement_term, cluster.enforcement_term))))::timestamp with time zone, CURRENT_TIMESTAMP)) AS enforcement_term,
            COALESCE(established.overall_quality, cluster.overall_quality) AS overall_quality,
            recovery.type AS recovery_type
           FROM ((((((((((((data.building_precomputed bp
             LEFT JOIN data.building_geographic_region gr ON ((gr.building_id = bp.building_id)))
             LEFT JOIN data.building_groundwater_level gwl ON ((gwl.building_id = bp.building_id)))
             LEFT JOIN data.building_subsidence bs ON ((bs.building_id = bp.building_id)))
             LEFT JOIN data.building_ownership bo ON ((bo.building_id = bp.building_id)))
             LEFT JOIN data.building_pleistocene bpl ON ((bpl.building_id = bp.building_id)))
             LEFT JOIN data.building_cluster bc ON ((bc.building_id = bp.building_id)))
             LEFT JOIN data.supercluster bsc ON ((bsc.cluster_id = bc.cluster_id)))
             LEFT JOIN data.building_sample established ON ((established.building_id = bp.building_id)))
             LEFT JOIN data.cluster_sample cluster ON ((cluster.cluster_id = bc.cluster_id)))
             LEFT JOIN data.supercluster_sample supercluster ON ((supercluster.supercluster_id = bsc.supercluster_id)))
             LEFT JOIN LATERAL ( SELECT DISTINCT ON (rs.building_id) rs.building_id,
                    rs.type
                   FROM report.recovery_sample rs
                  WHERE (rs.building_id = bp.building_id)
                  ORDER BY rs.building_id, rs.create_date DESC) recovery ON (true))
             LEFT JOIN data.cluster_recovery_sample ON ((cluster_recovery_sample.cluster_id = bc.cluster_id))),
            LATERAL ( SELECT round((((bp.ground_level)::double precision - bpl.depth))::numeric, 2) AS round) pile_length(pile_length),
            LATERAL ( SELECT COALESCE(established.foundation_type, cluster.foundation_type, supercluster.foundation_type, data.indicative_foundation_type(COALESCE(established.built_year, bp.construction_year_bag), bp.height, gr.code, bp.address_count)) AS "coalesce") foundation_type(ft)) base;


--
-- Name: model_risk_static_2024_1; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.model_risk_static_2024_1 AS
 SELECT building_id,
    address_count,
    neighborhood_id,
    construction_year,
    construction_year_reliability,
    foundation_type,
    foundation_type_reliability,
    restoration_costs,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    unclassified_risk,
    height,
    velocity,
    ground_water_level,
    ground_level,
    soil,
    surface_area,
    owner,
    inquiry_id,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    recovery_type
   FROM data.model_risk_dynamic_all
  WITH NO DATA;


--
-- Name: building_active; Type: VIEW; Schema: geocoder; Owner: -
--

CREATE VIEW geocoder.building_active AS
 SELECT id,
    built_year,
    geom,
    external_id,
    building_type,
    neighborhood_id
   FROM geocoder.building
  WHERE ((active = true) AND (geom IS NOT NULL));


--
-- Name: VIEW building_active; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON VIEW geocoder.building_active IS 'Contains all entries from geocoder.building which have their status set to active.';


--
-- Name: district; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.district (
    id geocoder.geocoder_id DEFAULT geocoder.geocoder_generate_id() NOT NULL,
    external_id text NOT NULL,
    municipality_id geocoder.geocoder_id NOT NULL,
    name text NOT NULL,
    water boolean NOT NULL,
    geom public.geometry(MultiPolygon,4326) NOT NULL
);


--
-- Name: TABLE district; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON TABLE geocoder.district IS 'Contains all districts in our own format.';


--
-- Name: municipality; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.municipality (
    id geocoder.geocoder_id DEFAULT geocoder.geocoder_generate_id() NOT NULL,
    external_id text NOT NULL,
    name text NOT NULL,
    water boolean NOT NULL,
    geom public.geometry(MultiPolygon,4326) NOT NULL,
    state_id geocoder.geocoder_id NOT NULL
);


--
-- Name: TABLE municipality; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON TABLE geocoder.municipality IS 'Contains all municipalities in our own format.';


--
-- Name: neighborhood; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.neighborhood (
    id geocoder.geocoder_id DEFAULT geocoder.geocoder_generate_id() NOT NULL,
    external_id text NOT NULL,
    district_id geocoder.geocoder_id NOT NULL,
    name text NOT NULL,
    water boolean NOT NULL,
    geom public.geometry(MultiPolygon,4326) NOT NULL
);


--
-- Name: TABLE neighborhood; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON TABLE geocoder.neighborhood IS 'Contains all neighborhoods in our own format.';


--
-- Name: building_geo_hierarchy; Type: VIEW; Schema: data; Owner: -
--

CREATE VIEW data.building_geo_hierarchy AS
 SELECT mrs.building_id,
    mrs.address_count,
    mrs.neighborhood_id,
    mrs.construction_year,
    mrs.construction_year_reliability,
    mrs.foundation_type,
    mrs.foundation_type_reliability,
    mrs.restoration_costs,
    mrs.drystand,
    mrs.drystand_risk,
    mrs.drystand_risk_reliability,
    mrs.bio_infection_risk,
    mrs.bio_infection_risk_reliability,
    mrs.dewatering_depth,
    mrs.dewatering_depth_risk,
    mrs.dewatering_depth_risk_reliability,
    mrs.unclassified_risk,
    mrs.height,
    mrs.velocity,
    mrs.ground_water_level,
    mrs.ground_level,
    mrs.soil,
    mrs.surface_area,
    mrs.owner,
    mrs.inquiry_id,
    mrs.inquiry_type,
    mrs.damage_cause,
    mrs.enforcement_term,
    mrs.overall_quality,
    mrs.recovery_type,
    ba.geom,
    n.external_id AS ext_neighborhood_id,
    d.external_id AS ext_district_id,
    m.external_id AS ext_municipality_id
   FROM ((((data.model_risk_static_2024_1 mrs
     JOIN geocoder.building_active ba ON ((ba.external_id = mrs.building_id)))
     JOIN geocoder.neighborhood n ON (((n.id)::text = (ba.neighborhood_id)::text)))
     JOIN geocoder.district d ON (((d.id)::text = (n.district_id)::text)))
     JOIN geocoder.municipality m ON (((m.id)::text = (d.municipality_id)::text)))
  WHERE (mrs.address_count > 0);


--
-- Name: building_height; Type: VIEW; Schema: data; Owner: -
--

CREATE VIEW data.building_height AS
 SELECT building_id,
    (roof - ground) AS height
   FROM data.building_elevation be
  WHERE ((roof IS NOT NULL) AND (ground IS NOT NULL));


--
-- Name: VIEW building_height; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON VIEW data.building_height IS 'Absolute building height';


--
-- Name: building_sample_2026_1; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.building_sample_2026_1 AS
 WITH ranked AS (
         SELECT DISTINCT ON (b.external_id) b.external_id AS building_id,
            is2.foundation_type,
            is2.enforcement_term,
            is2.damage_cause,
            is2.overall_quality,
            is2.recovery_advised,
            (date_part('year'::text, (is2.built_year)::date))::integer AS built_year,
            is2.groundwater_level_temp AS groundwater_level,
            is2.wood_level,
            is2.foundation_depth,
            i.type AS inquiry_type,
            i.document_date,
            i.id
           FROM ((report.inquiry_sample is2
             JOIN report.inquiry i ON ((is2.inquiry_id = i.id)))
             JOIN geocoder.building b ON ((b.external_id = (is2.building_id)::text)))
          WHERE ((i.document_date >= ((b.built_year)::date - '5 years'::interval)) AND (is2.delete_date IS NULL) AND (i.document_date <= CURRENT_DATE))
          ORDER BY b.external_id,
                CASE i.type
                    WHEN 'foundation_research'::report.inquiry_type THEN 0
                    WHEN 'inspectionpit'::report.inquiry_type THEN 1
                    WHEN 'second_opinion'::report.inquiry_type THEN 2
                    WHEN 'additional_research'::report.inquiry_type THEN 3
                    WHEN 'demolition_research'::report.inquiry_type THEN 4
                    WHEN 'architectural_research'::report.inquiry_type THEN 5
                    WHEN 'archive_research'::report.inquiry_type THEN 6
                    WHEN 'quickscan'::report.inquiry_type THEN 7
                    WHEN 'note'::report.inquiry_type THEN 9
                    ELSE 100
                END, (date_part('year'::text, i.document_date)) DESC, ((((((((((is2.foundation_type IS NOT NULL))::integer + ((is2.enforcement_term IS NOT NULL))::integer) + ((is2.damage_cause IS NOT NULL))::integer) + ((is2.overall_quality IS NOT NULL))::integer) + ((is2.recovery_advised IS NOT NULL))::integer) + ((is2.built_year IS NOT NULL))::integer) + ((is2.groundwater_level_temp IS NOT NULL))::integer) + ((is2.wood_level IS NOT NULL))::integer) + ((is2.foundation_depth IS NOT NULL))::integer) DESC, i.document_date DESC, i.id DESC
        ), facade AS (
         SELECT DISTINCT ON ((is2.building_id)::text) (is2.building_id)::text AS building_id,
            is2.facade_scan_risk
           FROM (report.inquiry_sample is2
             JOIN report.inquiry i ON ((i.id = is2.inquiry_id)))
          WHERE ((is2.facade_scan_risk IS NOT NULL) AND (is2.delete_date IS NULL) AND (i.document_date <= CURRENT_DATE))
          ORDER BY (is2.building_id)::text, i.document_date DESC
        )
 SELECT r.building_id,
    r.foundation_type,
    r.enforcement_term,
    r.damage_cause,
    r.overall_quality,
    r.recovery_advised,
    r.built_year,
    r.groundwater_level,
    r.wood_level,
    r.foundation_depth,
    f.facade_scan_risk,
    r.inquiry_type,
    r.document_date,
    r.id
   FROM (ranked r
     LEFT JOIN facade f ON ((f.building_id = r.building_id)))
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW building_sample_2026_1; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON MATERIALIZED VIEW data.building_sample_2026_1 IS 'Candidate model 2026.1 -- observation selection only. Served to nobody. Drop with one DROP MATERIALIZED VIEW.';


--
-- Name: building_subsidence_history; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_subsidence_history (
    building_id text NOT NULL,
    velocity double precision NOT NULL,
    mark_at date NOT NULL
);


--
-- Name: foundation_type_lookup_2026_1; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.foundation_type_lookup_2026_1 (
    cell text NOT NULL,
    n integer NOT NULL,
    p_wood numeric NOT NULL,
    p_no_pile numeric NOT NULL,
    p_concrete numeric NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE foundation_type_lookup_2026_1; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON TABLE data.foundation_type_lookup_2026_1 IS 'Fitted foundation-type probabilities per feature cell for candidate model-2026.1. Fitted on evaluation-sample TRAIN rows only. Uses ground_level and surface_area, which the deployed decision tree ignores.';


--
-- Name: foundation_type_lookup_2026_2; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.foundation_type_lookup_2026_2 (
    cell text NOT NULL,
    n integer NOT NULL,
    p_wood numeric NOT NULL,
    p_no_pile numeric NOT NULL,
    p_concrete numeric NOT NULL
);


--
-- Name: TABLE foundation_type_lookup_2026_2; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON TABLE data.foundation_type_lookup_2026_2 IS 'Refit of the 2026.1 lookup on evidence-backed truth only (sample_version 2, grades physical+documented). Excludes quickscan-sourced answers, which are our own output.';


--
-- Name: model_compare_2026_1; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.model_compare_2026_1 (
    building_id text NOT NULL,
    neighborhood_id text,
    tier text,
    frozen_ft text,
    cand_ft text,
    frozen_rot text,
    cand_rot text,
    change_kind text
);


--
-- Name: TABLE model_compare_2026_1; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON TABLE data.model_compare_2026_1 IS 'One-off frozen-vs-candidate comparison for decision support. Not served, not refreshed. Drop freely.';


--
-- Name: model_evaluation_sample; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.model_evaluation_sample (
    purpose text NOT NULL,
    building_id text NOT NULL,
    stratum text NOT NULL,
    observed_family text,
    split text,
    sample_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    truth_source text,
    evidence_grade text,
    CONSTRAINT model_evaluation_sample_purpose CHECK ((purpose = ANY (ARRAY['truth'::text, 'population'::text]))),
    CONSTRAINT model_evaluation_sample_shape CHECK ((((purpose = 'truth'::text) AND (observed_family IS NOT NULL) AND (split IS NOT NULL)) OR ((purpose = 'population'::text) AND (observed_family IS NULL) AND (split IS NULL)))),
    CONSTRAINT model_evaluation_sample_split CHECK (((split IS NULL) OR (split = ANY (ARRAY['train'::text, 'test'::text]))))
);


--
-- Name: TABLE model_evaluation_sample; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON TABLE data.model_evaluation_sample IS 'Frozen benchmark for scoring candidate models. Deliberately a table, not a view: a growing truth set would make two candidates scored on different days incomparable. See docs/model-versioning.md.';


--
-- Name: COLUMN model_evaluation_sample.evidence_grade; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON COLUMN data.model_evaluation_sample.evidence_grade IS 'physical (dug) > documented (drawing) > opinion (assertion). quickscan is never present: its foundation type is our own output.';


--
-- Name: model_evaluation_stratum_weight; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.model_evaluation_stratum_weight (
    sample_version integer NOT NULL,
    stratum text NOT NULL,
    national_buildings bigint NOT NULL,
    sampled bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE model_evaluation_stratum_weight; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON TABLE data.model_evaluation_stratum_weight IS 'True national size of each evaluation stratum. The population sample is floored at 2,000 per stratum and is therefore NOT proportional -- weight by national_buildings before quoting any national figure.';


--
-- Name: model_gevelscan; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.model_gevelscan (
    skewed_parallel report.rotation_type,
    facade_type report.crack_type,
    skewed_perpendicular report.rotation_type,
    risk data.foundation_risk_indication
);


--
-- Name: model_risk_static; Type: VIEW; Schema: data; Owner: -
--

CREATE VIEW data.model_risk_static AS
 SELECT building_id,
    address_count,
    neighborhood_id,
    construction_year,
    construction_year_reliability,
    foundation_type,
    foundation_type_reliability,
    restoration_costs,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    unclassified_risk,
    height,
    velocity,
    ground_water_level,
    ground_level,
    soil,
    surface_area,
    owner,
    inquiry_id,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    recovery_type
   FROM data.model_risk_static_2024_1;


--
-- Name: VIEW model_risk_static; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON VIEW data.model_risk_static IS 'Pointer at the default model version. Consumers should name this, not a versioned matview. Switch the default with CREATE OR REPLACE VIEW. See docs/model-versioning.md.';


--
-- Name: model_version; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.model_version (
    id integer NOT NULL,
    slug text NOT NULL,
    title text NOT NULL,
    status data.model_status NOT NULL,
    inputs jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    activated_at timestamp with time zone,
    frozen_at timestamp with time zone,
    retire_after date,
    CONSTRAINT model_version_inputs_is_object CHECK ((jsonb_typeof(inputs) = 'object'::text)),
    CONSTRAINT model_version_slug_format CHECK ((slug ~ '^model-[0-9]{4}\.[0-9]+(-rc[0-9]+)?$'::text))
);


--
-- Name: TABLE model_version; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON TABLE data.model_version IS 'Registry of risk model versions: what each was built from, and where it is in its lifecycle. See docs/model-versioning.md.';


--
-- Name: COLUMN model_version.inputs; Type: COMMENT; Schema: data; Owner: -
--

COMMENT ON COLUMN data.model_version.inputs IS 'Vintage and row-count fingerprint of each input dataset, so a diff between versions can attribute itself to logic or to data.';


--
-- Name: model_version_id_seq; Type: SEQUENCE; Schema: data; Owner: -
--

ALTER TABLE data.model_version ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME data.model_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: risk_table_priority; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.risk_table_priority (
    risk data.foundation_risk_indication,
    settlement_speed report.rotation_type,
    priority character varying(50)
);


--
-- Name: statistics_product_buildings_restored; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_buildings_restored AS
 SELECT ba.neighborhood_id,
    COALESCE(rs_count.count, (0)::bigint) AS count
   FROM (( SELECT DISTINCT building_active.neighborhood_id
           FROM geocoder.building_active) ba
     LEFT JOIN ( SELECT ba2.neighborhood_id,
            count(*) AS count
           FROM (report.recovery_sample rs
             JOIN geocoder.building_active ba2 ON ((ba2.external_id = rs.building_id)))
          GROUP BY ba2.neighborhood_id) rs_count ON (((rs_count.neighborhood_id)::text = (ba.neighborhood_id)::text)))
  WITH NO DATA;


--
-- Name: statistics_product_construction_years; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_construction_years AS
 SELECT ba.neighborhood_id,
    (date_part('year'::text, decade.decade))::integer AS year_from,
    count(decade.decade) AS count
   FROM geocoder.building_active ba,
    LATERAL date_trunc('decade'::text, (ba.built_year)::timestamp with time zone) decade(decade)
  WHERE (ba.built_year IS NOT NULL)
  GROUP BY ba.neighborhood_id, decade.decade
  WITH NO DATA;


--
-- Name: address; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.address (
    id geocoder.geocoder_id DEFAULT geocoder.geocoder_generate_id() NOT NULL,
    building_number text NOT NULL,
    postal_code text,
    street text NOT NULL,
    external_id text NOT NULL,
    city text NOT NULL,
    building_id geocoder.geocoder_id
);


--
-- Name: TABLE address; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON TABLE geocoder.address IS 'Contains all addresses in our own format, including a tsvector column to enable full text search.';


--
-- Name: statistics_product_data_collected; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_data_collected AS
 SELECT ba.neighborhood_id,
    (((count(a.id) FILTER (WHERE (i.id IS NOT NULL)))::double precision / (count(a.id))::double precision) * (100)::double precision) AS percentage
   FROM ((geocoder.address a
     JOIN geocoder.building_active ba ON (((a.building_id)::text = ba.external_id)))
     LEFT JOIN report.inquiry_sample i ON (((i.building_id)::text = (a.building_id)::text)))
  GROUP BY ba.neighborhood_id
  WITH NO DATA;


--
-- Name: statistics_product_foundation_risk; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_foundation_risk AS
 SELECT neighborhood_id,
    risk AS foundation_risk,
    (((count(risk))::numeric / sum(count(risk)) OVER (PARTITION BY neighborhood_id)) * (100)::numeric) AS percentage
   FROM ( SELECT mrs.neighborhood_id,
            ( SELECT unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]) AS risk
                  ORDER BY (unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]))
                 LIMIT 1) AS risk
           FROM data.model_risk_static_2024_1 mrs) acr
  WHERE (risk IS NOT NULL)
  GROUP BY neighborhood_id, risk
  WITH NO DATA;


--
-- Name: statistics_product_foundation_type; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_foundation_type AS
 SELECT neighborhood_id,
    foundation_type,
    (((count(foundation_type))::numeric / sum(count(foundation_type)) OVER (PARTITION BY neighborhood_id)) * (100)::numeric) AS percentage
   FROM data.model_risk_static_2024_1 mrs
  GROUP BY neighborhood_id, foundation_type
  WITH NO DATA;


--
-- Name: incident; Type: TABLE; Schema: report; Owner: -
--

CREATE TABLE report.incident (
    id text NOT NULL,
    foundation_type report.foundation_type,
    chained_building boolean NOT NULL,
    owner boolean NOT NULL,
    foundation_recovery boolean NOT NULL,
    neighbor_recovery boolean NOT NULL,
    foundation_damage_cause report.foundation_damage_cause,
    document_file text[],
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_date timestamp with time zone,
    delete_date timestamp with time zone,
    foundation_damage_characteristics report.foundation_damage_characteristics[],
    environment_damage_characteristics report.environment_damage_characteristics[],
    metadata jsonb,
    audit_status report.audit_status DEFAULT 'todo'::report.audit_status NOT NULL,
    internal_note text,
    question_type report.incident_question_type DEFAULT 'other'::report.incident_question_type NOT NULL,
    building_id geocoder.geocoder_id NOT NULL,
    file_resource_key text
);


--
-- Name: TABLE incident; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON TABLE report.incident IS 'Contains reported incidents.';


--
-- Name: COLUMN incident.create_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.incident.create_date IS 'Timestamp of record creation, set by insert';


--
-- Name: COLUMN incident.update_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.incident.update_date IS 'Timestamp of last record update, automatically updated on record modification';


--
-- Name: COLUMN incident.delete_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.incident.delete_date IS 'Timestamp of soft delete';


--
-- Name: statistics_product_incident_municipality; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_incident_municipality AS
 SELECT m.id AS municipality_id,
    (date_part('year'::text, i.create_date))::integer AS year,
    count(i.id) AS count
   FROM ((((report.incident i
     JOIN geocoder.building_active ba ON ((ba.external_id = (i.building_id)::text)))
     JOIN geocoder.neighborhood n ON (((n.id)::text = (ba.neighborhood_id)::text)))
     JOIN geocoder.district d ON (((d.id)::text = (n.district_id)::text)))
     JOIN geocoder.municipality m ON (((m.id)::text = (d.municipality_id)::text)))
  GROUP BY m.id, ((date_part('year'::text, i.create_date))::integer)
  WITH NO DATA;


--
-- Name: statistics_product_incidents; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_incidents AS
 SELECT ba.neighborhood_id,
    year.year,
    count(i.id) AS count
   FROM (report.incident i
     JOIN geocoder.building_active ba ON ((ba.external_id = (i.building_id)::text))),
    LATERAL CAST((date_part('year'::text, i.create_date))::integer AS integer) year(year)
  GROUP BY ba.neighborhood_id, year.year
  WITH NO DATA;


--
-- Name: statistics_product_inquiries; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_inquiries AS
 SELECT ba.neighborhood_id,
    year.year,
    count(i.id) AS count
   FROM ((report.inquiry i
     JOIN report.inquiry_sample is2 ON ((is2.inquiry_id = i.id)))
     JOIN geocoder.building_active ba ON ((ba.external_id = (is2.building_id)::text))),
    LATERAL CAST((date_part('year'::text, i.document_date))::integer AS integer) year(year)
  GROUP BY ba.neighborhood_id, year.year
  WITH NO DATA;


--
-- Name: statistics_product_inquiry_municipality; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_product_inquiry_municipality AS
 SELECT m.id AS municipality_id,
    (date_part('year'::text, i.document_date))::integer AS year,
    count(is2.id) AS count
   FROM (((((report.inquiry_sample is2
     JOIN report.inquiry i ON ((i.id = is2.inquiry_id)))
     JOIN geocoder.building_active ba ON ((ba.external_id = (is2.building_id)::text)))
     JOIN geocoder.neighborhood n ON (((n.id)::text = (ba.neighborhood_id)::text)))
     JOIN geocoder.district d ON (((d.id)::text = (n.district_id)::text)))
     JOIN geocoder.municipality m ON (((m.id)::text = (d.municipality_id)::text)))
  GROUP BY m.id, ((date_part('year'::text, i.document_date))::integer)
  WITH NO DATA;


--
-- Name: artifact; Type: TABLE; Schema: dataops; Owner: -
--

CREATE TABLE dataops.artifact (
    id bigint NOT NULL,
    dossier_id bigint NOT NULL,
    parent_artifact_id bigint,
    storage_key text NOT NULL,
    original_filename text,
    mime_type text,
    size_bytes bigint,
    page_count integer,
    lane dataops.read_lane DEFAULT 'none'::dataops.read_lane NOT NULL,
    annotation_text text,
    annotation_pages integer[],
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    declared_category text
);


--
-- Name: COLUMN artifact.annotation_text; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.artifact.annotation_text IS 'The preparer''s own summary, lifted off the document. Withheld from every model; kept because on historical files it is the training label.';


--
-- Name: COLUMN artifact.declared_category; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.artifact.declared_category IS 'What the sender said this document is (form vocabulary: archieveresearch, foundationresearch, quickscan, herstelbewijs, foto, overig). A claim, not a finding: it bounds what the pipeline may conclude, never what the document says.';


--
-- Name: artifact_id_seq; Type: SEQUENCE; Schema: dataops; Owner: -
--

ALTER TABLE dataops.artifact ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dataops.artifact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: artifact_page; Type: TABLE; Schema: dataops; Owner: -
--

CREATE TABLE dataops.artifact_page (
    artifact_id bigint NOT NULL,
    page_no integer NOT NULL,
    material dataops.material,
    material_conf numeric(4,3),
    is_clean boolean DEFAULT false NOT NULL,
    redacted_boxes integer DEFAULT 0 NOT NULL,
    text_chars integer
);


--
-- Name: TABLE artifact_page; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON TABLE dataops.artifact_page IS 'Page-level triage. Routing photographs and blanks to a human before extraction is the cheapest accuracy this pipeline has: 2% vs 73-89% on the same field.';


--
-- Name: dossier; Type: TABLE; Schema: dataops; Owner: -
--

CREATE TABLE dataops.dossier (
    id bigint NOT NULL,
    channel dataops.intake_channel NOT NULL,
    subject text,
    external_ref text,
    duplicate_of bigint,
    inquiry_id integer,
    received_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    reference text,
    bag_id text,
    building_id text,
    resolution_status dataops.resolution_status,
    submitter jsonb,
    payload jsonb,
    outcome dataops.dossier_outcome,
    outcome_note text,
    outcome_at timestamp with time zone
);


--
-- Name: COLUMN dossier.duplicate_of; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier.duplicate_of IS 'Same submission arriving twice through different senders. Structural, not an error -- see docs/dataops-pipeline.md.';


--
-- Name: COLUMN dossier.reference; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier.reference IS 'Melder-facing code (FM2026-000042). Sequential, not a credential.';


--
-- Name: COLUMN dossier.bag_id; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier.bag_id IS 'BAG nummeraanduiding exactly as the melder supplied it, before resolution.';


--
-- Name: COLUMN dossier.building_id; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier.building_id IS 'NL.IMBAG.PAND.* resolved from bag_id.';


--
-- Name: COLUMN dossier.submitter; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier.submitter IS 'Contact details. Personal data — isolated so erasure can find it.';


--
-- Name: COLUMN dossier.payload; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier.payload IS 'What the melder claimed: topic, answers, form version, request provenance.';


--
-- Name: COLUMN dossier.outcome; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier.outcome IS 'Dossier-level decision. Per-value decisions live in dataops.verdict.';


--
-- Name: dossier_id_seq; Type: SEQUENCE; Schema: dataops; Owner: -
--

ALTER TABLE dataops.dossier ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dataops.dossier_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: dossier_mail; Type: TABLE; Schema: dataops; Owner: -
--

CREATE TABLE dataops.dossier_mail (
    id bigint NOT NULL,
    dossier_id bigint NOT NULL,
    kind text NOT NULL,
    recipient text NOT NULL,
    subject text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    provider_id text,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    CONSTRAINT dossier_mail_kind_check CHECK ((kind = ANY (ARRAY['received'::text, 'closed'::text]))),
    CONSTRAINT dossier_mail_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text])))
);


--
-- Name: TABLE dossier_mail; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON TABLE dataops.dossier_mail IS 'Send log for melder-facing mail (#1020). One row per (dossier, kind), claimed before the send; the unique key is the idempotency guard.';


--
-- Name: COLUMN dossier_mail.kind; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier_mail.kind IS 'received (ontvangstbevestiging) | closed (afronding).';


--
-- Name: COLUMN dossier_mail.recipient; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier_mail.recipient IS 'Address the mail went to. Personal data, like dossier.submitter.';


--
-- Name: COLUMN dossier_mail.status; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier_mail.status IS 'pending | sent | failed. A failed row is re-claimed on the next attempt.';


--
-- Name: COLUMN dossier_mail.provider_id; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.dossier_mail.provider_id IS 'Resend message id, when sent.';


--
-- Name: dossier_mail_id_seq; Type: SEQUENCE; Schema: dataops; Owner: -
--

ALTER TABLE dataops.dossier_mail ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dataops.dossier_mail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: dossier_reference_seq; Type: SEQUENCE; Schema: dataops; Owner: -
--

CREATE SEQUENCE dataops.dossier_reference_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extraction; Type: TABLE; Schema: dataops; Owner: -
--

CREATE TABLE dataops.extraction (
    id bigint NOT NULL,
    artifact_id bigint NOT NULL,
    model text NOT NULL,
    prompt_version text NOT NULL,
    lane dataops.read_lane NOT NULL,
    pages_sent integer,
    input_tokens integer,
    output_tokens integer,
    cost_usd numeric(10,6),
    started_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    finished_at timestamp with time zone,
    error text
);


--
-- Name: extraction_field; Type: TABLE; Schema: dataops; Owner: -
--

CREATE TABLE dataops.extraction_field (
    id bigint NOT NULL,
    extraction_id bigint NOT NULL,
    field text NOT NULL,
    value text,
    confidence numeric(4,3),
    evidence text,
    evidence_page integer,
    state dataops.review_state DEFAULT 'pending'::dataops.review_state NOT NULL,
    address_text text,
    address_id geocoder.geocoder_id
);


--
-- Name: COLUMN extraction_field.evidence; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON COLUMN dataops.extraction_field.evidence IS 'The passage the value was read from. Required for auto-accept: fabrications are rare, silent, and otherwise indistinguishable from correct answers.';


--
-- Name: extraction_field_id_seq; Type: SEQUENCE; Schema: dataops; Owner: -
--

ALTER TABLE dataops.extraction_field ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dataops.extraction_field_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extraction_id_seq; Type: SEQUENCE; Schema: dataops; Owner: -
--

ALTER TABLE dataops.extraction ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dataops.extraction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: verdict; Type: TABLE; Schema: dataops; Owner: -
--

CREATE TABLE dataops.verdict (
    id bigint NOT NULL,
    extraction_field_id bigint NOT NULL,
    decided_by uuid,
    decided_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    outcome dataops.review_state NOT NULL,
    final_value text,
    note text,
    review_seconds integer,
    CONSTRAINT verdict_outcome_check CHECK ((outcome <> 'pending'::dataops.review_state))
);


--
-- Name: TABLE verdict; Type: COMMENT; Schema: dataops; Owner: -
--

COMMENT ON TABLE dataops.verdict IS 'Every human confirmation and correction, kept as a labelled example. Today''s labels come from cover sheets an invoerder writes before uploading; once this pipeline reads documents instead, nobody writes those any more and this table becomes the only source of new training data.';


--
-- Name: verdict_id_seq; Type: SEQUENCE; Schema: dataops; Owner: -
--

ALTER TABLE dataops.verdict ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME dataops.verdict_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: residence; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.residence (
    id text NOT NULL,
    address_id text NOT NULL,
    building_id text NOT NULL,
    geom public.geometry(Point,4326) NOT NULL
);


--
-- Name: TABLE residence; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON TABLE geocoder.residence IS 'Link between building and address';


--
-- Name: state; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.state (
    id geocoder.geocoder_id DEFAULT geocoder.geocoder_generate_id() NOT NULL,
    external_id text NOT NULL,
    country_id geocoder.geocoder_id NOT NULL,
    name text NOT NULL,
    water boolean NOT NULL,
    geom public.geometry(MultiPolygon,4326) NOT NULL
);


--
-- Name: TABLE state; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON TABLE geocoder.state IS 'Contains all states in our own format.';


--
-- Name: building_geocoder; Type: VIEW; Schema: geocoder; Owner: -
--

CREATE VIEW geocoder.building_geocoder AS
 SELECT b.built_year AS building_built_year,
    b.external_id AS building_id,
    b.building_type,
    b.zone_function AS building_zone_function,
    r.id AS residence_id,
    public.st_y(r.geom) AS residence_lat,
    public.st_x(r.geom) AS residence_lon,
    n.external_id AS neighborhood_id,
    n.name AS neighborhood_name,
    d.external_id AS district_id,
    d.name AS district_name,
    m.external_id AS municipality_id,
    m.name AS municipality_name,
    s.external_id AS state_id,
    s.name AS state_name
   FROM (((((geocoder.building b
     LEFT JOIN geocoder.neighborhood n ON (((n.id)::text = (b.neighborhood_id)::text)))
     LEFT JOIN geocoder.residence r ON ((r.building_id = b.external_id)))
     LEFT JOIN geocoder.district d ON (((d.id)::text = (n.district_id)::text)))
     LEFT JOIN geocoder.municipality m ON (((m.id)::text = (d.municipality_id)::text)))
     LEFT JOIN geocoder.state s ON (((s.id)::text = (m.state_id)::text)));


--
-- Name: analysis_full; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.analysis_full AS
 SELECT building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    address_count,
    foundation_type,
    foundation_type_reliability,
    construction_year,
    construction_year_reliability,
    restoration_costs,
    bio_infection_risk,
    bio_infection_risk_reliability,
    dewatering_depth,
    dewatering_depth_risk,
    dewatering_depth_risk_reliability,
    drystand,
    drystand_risk,
    drystand_risk_reliability,
    unclassified_risk,
    overall_quality,
    ground_water_level,
    ground_level,
    soil,
    surface_area,
    recovery_type,
    inquiry_type,
    enforcement_term,
    damage_cause,
    velocity,
    height,
    owner,
    inquiry_id,
    geom
   FROM data.building_geo_hierarchy;


--
-- Name: building_cluster_tiles; Type: TABLE; Schema: maplayer; Owner: -
--

CREATE TABLE maplayer.building_cluster_tiles (
    cluster_id uuid NOT NULL,
    building_count integer NOT NULL,
    surface_area double precision,
    geom public.geometry(MultiPolygon,3857),
    geom_simple public.geometry(MultiPolygon,3857)
);


--
-- Name: building_tiles; Type: TABLE; Schema: maplayer; Owner: -
--

CREATE TABLE maplayer.building_tiles (
    building_id text NOT NULL,
    neighborhood_id text,
    district_id text,
    municipality_id text,
    address_count integer,
    construction_year integer,
    construction_year_reliability text,
    foundation_type text,
    foundation_type_reliability text,
    restoration_costs integer,
    drystand double precision,
    drystand_risk text,
    drystand_risk_reliability text,
    bio_infection_risk text,
    bio_infection_risk_reliability text,
    dewatering_depth double precision,
    dewatering_depth_risk text,
    dewatering_depth_risk_reliability text,
    unclassified_risk text,
    height double precision,
    velocity double precision,
    owner text,
    inquiry_type text,
    damage_cause text,
    enforcement_term double precision,
    overall_quality text,
    recovery_type text,
    geom public.geometry(MultiPolygon,3857),
    geom_simple public.geometry(MultiPolygon,3857),
    surface_area double precision,
    contractor text
);


--
-- Name: bundle; Type: TABLE; Schema: maplayer; Owner: -
--

CREATE TABLE maplayer.bundle (
    tileset text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    name text NOT NULL,
    zoom_min_level integer NOT NULL,
    zoom_max_level integer NOT NULL,
    generate_tileset boolean DEFAULT true,
    upload_dataset boolean
);


--
-- Name: facade_scan; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.facade_scan AS
 SELECT inputz.external_id,
    inputz.neighborhood_id,
    inputz.district_id,
    inputz.municipality_id,
    inputz.height,
    inputz.owner,
    inputz.skewed_parallel_facade,
    inputz.skewed_perpendicular_facade,
    inputz.facade_type,
    inputz.settlement_speed,
    inputz.facade_scan_risk,
    mg.risk,
    rtp.priority,
    inputz.geom
   FROM ((( SELECT DISTINCT ON (ba.external_id) ba.external_id,
            n.external_id AS neighborhood_id,
            d.external_id AS district_id,
            m.external_id AS municipality_id,
            round((GREATEST(bh.height, (0)::real))::numeric, 2) AS height,
            bo.owner,
            COALESCE(is2.skewed_parallel_facade,
                CASE
                    WHEN ((is2.skewed_parallel)::numeric < (75)::numeric) THEN 'very_big'::report.rotation_type
                    WHEN (((is2.skewed_parallel)::numeric >= (75)::numeric) AND ((is2.skewed_parallel)::numeric < (100)::numeric)) THEN 'big'::report.rotation_type
                    WHEN (((is2.skewed_parallel)::numeric >= (100)::numeric) AND ((is2.skewed_parallel)::numeric < (200)::numeric)) THEN 'mediocre'::report.rotation_type
                    WHEN (((is2.skewed_parallel)::numeric >= (200)::numeric) AND ((is2.skewed_parallel)::numeric < (300)::numeric)) THEN 'small'::report.rotation_type
                    WHEN ((is2.skewed_parallel)::numeric >= (300)::numeric) THEN 'nil'::report.rotation_type
                    ELSE NULL::report.rotation_type
                END) AS skewed_parallel_facade,
            COALESCE(is2.skewed_perpendicular_facade,
                CASE
                    WHEN ((is2.skewed_perpendicular)::numeric < (75)::numeric) THEN 'very_big'::report.rotation_type
                    WHEN (((is2.skewed_perpendicular)::numeric >= (75)::numeric) AND ((is2.skewed_perpendicular)::numeric < (100)::numeric)) THEN 'big'::report.rotation_type
                    WHEN (((is2.skewed_perpendicular)::numeric >= (100)::numeric) AND ((is2.skewed_perpendicular)::numeric < (200)::numeric)) THEN 'mediocre'::report.rotation_type
                    WHEN (((is2.skewed_perpendicular)::numeric >= (200)::numeric) AND ((is2.skewed_perpendicular)::numeric < (300)::numeric)) THEN 'small'::report.rotation_type
                    WHEN ((is2.skewed_perpendicular)::numeric >= (300)::numeric) THEN 'nil'::report.rotation_type
                    ELSE NULL::report.rotation_type
                END) AS skewed_perpendicular_facade,
            GREATEST(COALESCE(is2.crack_facade_front_type,
                CASE
                    WHEN ((is2.crack_facade_front_size)::integer = 0) THEN 'nil'::report.crack_type
                    WHEN ((is2.crack_facade_front_size)::integer = 1) THEN 'small'::report.crack_type
                    WHEN (((is2.crack_facade_front_size)::integer > 1) AND ((is2.crack_facade_front_size)::integer < 3)) THEN 'mediocre'::report.crack_type
                    WHEN ((is2.crack_facade_front_size)::integer >= 3) THEN 'big'::report.crack_type
                    ELSE NULL::report.crack_type
                END), COALESCE(is2.crack_facade_back_type,
                CASE
                    WHEN ((is2.crack_facade_back_size)::integer = 0) THEN 'nil'::report.crack_type
                    WHEN ((is2.crack_facade_back_size)::integer = 1) THEN 'small'::report.crack_type
                    WHEN (((is2.crack_facade_back_size)::integer > 1) AND ((is2.crack_facade_back_size)::integer < 3)) THEN 'mediocre'::report.crack_type
                    WHEN ((is2.crack_facade_back_size)::integer >= 3) THEN 'big'::report.crack_type
                    ELSE NULL::report.crack_type
                END), COALESCE(is2.crack_facade_left_type,
                CASE
                    WHEN ((is2.crack_facade_left_size)::integer = 0) THEN 'nil'::report.crack_type
                    WHEN ((is2.crack_facade_left_size)::integer = 1) THEN 'small'::report.crack_type
                    WHEN (((is2.crack_facade_left_size)::integer > 1) AND ((is2.crack_facade_left_size)::integer < 3)) THEN 'mediocre'::report.crack_type
                    WHEN ((is2.crack_facade_left_size)::integer >= 3) THEN 'big'::report.crack_type
                    ELSE NULL::report.crack_type
                END), COALESCE(is2.crack_facade_right_type,
                CASE
                    WHEN ((is2.crack_facade_right_size)::integer = 0) THEN 'nil'::report.crack_type
                    WHEN ((is2.crack_facade_right_size)::integer = 1) THEN 'small'::report.crack_type
                    WHEN (((is2.crack_facade_right_size)::integer > 1) AND ((is2.crack_facade_right_size)::integer < 3)) THEN 'mediocre'::report.crack_type
                    WHEN ((is2.crack_facade_right_size)::integer >= 3) THEN 'big'::report.crack_type
                    ELSE NULL::report.crack_type
                END)) AS facade_type,
                CASE
                    WHEN (abs(is2.settlement_speed) < (0.5)::double precision) THEN 'nil'::report.rotation_type
                    WHEN ((abs(is2.settlement_speed) >= (0.5)::double precision) AND (abs(is2.settlement_speed) < (2)::double precision)) THEN 'small'::report.rotation_type
                    WHEN ((abs(is2.settlement_speed) >= (2)::double precision) AND (abs(is2.settlement_speed) < (3)::double precision)) THEN 'mediocre'::report.rotation_type
                    WHEN ((abs(is2.settlement_speed) >= (3)::double precision) AND (abs(is2.settlement_speed) < (4)::double precision)) THEN 'big'::report.rotation_type
                    WHEN (abs(is2.settlement_speed) >= (4)::double precision) THEN 'very_big'::report.rotation_type
                    ELSE NULL::report.rotation_type
                END AS settlement_speed,
            is2.facade_scan_risk,
            ba.geom
           FROM ((((((report.inquiry_sample is2
             JOIN geocoder.building_active ba ON ((ba.external_id = (is2.building_id)::text)))
             JOIN data.building_height bh ON ((bh.building_id = ba.external_id)))
             LEFT JOIN data.building_ownership bo ON ((bo.building_id = ba.external_id)))
             JOIN geocoder.neighborhood n ON (((n.id)::text = (ba.neighborhood_id)::text)))
             JOIN geocoder.district d ON (((d.id)::text = (n.district_id)::text)))
             JOIN geocoder.municipality m ON (((m.id)::text = (d.municipality_id)::text)))
          WHERE ((is2.skewed_parallel IS NOT NULL) AND (is2.skewed_perpendicular IS NOT NULL) AND ((is2.crack_facade_front_type IS NOT NULL) OR (is2.crack_facade_front_size IS NOT NULL) OR (is2.crack_facade_back_type IS NOT NULL) OR (is2.crack_facade_back_size IS NOT NULL) OR (is2.crack_facade_left_type IS NOT NULL) OR (is2.crack_facade_left_size IS NOT NULL) OR (is2.crack_facade_right_type IS NOT NULL) OR (is2.crack_facade_right_size IS NOT NULL)))
          ORDER BY ba.external_id, is2.create_date DESC) inputz
     JOIN data.model_gevelscan mg ON (((mg.skewed_parallel = inputz.skewed_parallel_facade) AND (mg.skewed_perpendicular = inputz.skewed_perpendicular_facade) AND (mg.facade_type = inputz.facade_type))))
     LEFT JOIN data.risk_table_priority rtp ON (((rtp.risk = mg.risk) AND (rtp.settlement_speed = inputz.settlement_speed))));


--
-- Name: facade_scan_tiles; Type: TABLE; Schema: maplayer; Owner: -
--

CREATE TABLE maplayer.facade_scan_tiles (
    external_id text NOT NULL,
    neighborhood_id text,
    district_id text,
    municipality_id text,
    height double precision,
    owner text,
    skewed_parallel_facade text,
    skewed_perpendicular_facade text,
    facade_type text,
    settlement_speed text,
    facade_scan_risk text,
    risk text,
    priority text,
    geom public.geometry(MultiPolygon,3857)
);


--
-- Name: incident; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.incident AS
 SELECT i.id,
    i.foundation_damage_cause,
    round((GREATEST(bh.height, (0)::real))::numeric, 2) AS height,
    ba.geom
   FROM ((report.incident i
     JOIN geocoder.building_active ba ON ((ba.external_id = (i.building_id)::text)))
     JOIN data.building_height bh ON ((bh.building_id = ba.external_id)));


--
-- Name: incident_district; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.incident_district AS
 SELECT d.geom,
    count(d.id) AS incident_count
   FROM (((report.incident i
     JOIN geocoder.building_active ba ON ((ba.external_id = (i.building_id)::text)))
     JOIN geocoder.neighborhood n ON (((n.id)::text = (ba.neighborhood_id)::text)))
     JOIN geocoder.district d ON (((d.id)::text = (n.district_id)::text)))
  GROUP BY d.id, d.geom;


--
-- Name: incident_district_tiles; Type: TABLE; Schema: maplayer; Owner: -
--

CREATE TABLE maplayer.incident_district_tiles (
    district_id text NOT NULL,
    municipality_id text,
    incident_count integer NOT NULL,
    geom public.geometry(MultiPolygon,3857),
    geom_simple public.geometry(MultiPolygon,3857)
);


--
-- Name: incident_municipality; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.incident_municipality AS
 SELECT m.geom,
    count(m.id) AS incident_count
   FROM ((((report.incident i
     JOIN geocoder.building_active ba ON ((ba.external_id = (i.building_id)::text)))
     JOIN geocoder.neighborhood n ON (((n.id)::text = (ba.neighborhood_id)::text)))
     JOIN geocoder.district d ON (((d.id)::text = (n.district_id)::text)))
     JOIN geocoder.municipality m ON (((m.id)::text = (d.municipality_id)::text)))
  GROUP BY m.id, m.geom;


--
-- Name: incident_municipality_tiles; Type: TABLE; Schema: maplayer; Owner: -
--

CREATE TABLE maplayer.incident_municipality_tiles (
    municipality_id text NOT NULL,
    incident_count integer NOT NULL,
    geom public.geometry(MultiPolygon,3857),
    geom_simple public.geometry(MultiPolygon,3857)
);


--
-- Name: incident_neighborhood; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.incident_neighborhood AS
 SELECT n.geom,
    count(n.id) AS incident_count
   FROM ((report.incident i
     JOIN geocoder.building_active ba ON ((ba.external_id = (i.building_id)::text)))
     JOIN geocoder.neighborhood n ON (((n.id)::text = (ba.neighborhood_id)::text)))
  GROUP BY n.id, n.geom;


--
-- Name: incident_neighborhood_tiles; Type: TABLE; Schema: maplayer; Owner: -
--

CREATE TABLE maplayer.incident_neighborhood_tiles (
    neighborhood_id text NOT NULL,
    district_id text,
    municipality_id text,
    incident_count integer NOT NULL,
    geom public.geometry(MultiPolygon,3857),
    geom_simple public.geometry(MultiPolygon,3857)
);


--
-- Name: incident_tiles; Type: TABLE; Schema: maplayer; Owner: -
--

CREATE TABLE maplayer.incident_tiles (
    id text NOT NULL,
    neighborhood_id text,
    district_id text,
    municipality_id text,
    foundation_damage_cause text,
    height double precision,
    geom public.geometry(MultiPolygon,3857)
);


--
-- Name: dossier_event; Type: TABLE; Schema: report; Owner: -
--

CREATE TABLE report.dossier_event (
    id bigint NOT NULL,
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    kind report.dossier_event_kind NOT NULL,
    inquiry_id integer,
    recovery_id integer,
    incident_id text,
    actor application.user_id,
    note text,
    metadata jsonb,
    CONSTRAINT dossier_event_one_subject CHECK ((((((inquiry_id IS NOT NULL))::integer + ((recovery_id IS NOT NULL))::integer) + ((incident_id IS NOT NULL))::integer) = 1))
);


--
-- Name: TABLE dossier_event; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON TABLE report.dossier_event IS 'Append-only trail of dossier lifecycle events. Exactly one of inquiry_id / recovery_id / incident_id is set.';


--
-- Name: dossier_event_id_seq; Type: SEQUENCE; Schema: report; Owner: -
--

ALTER TABLE report.dossier_event ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME report.dossier_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inquiry_id_seq; Type: SEQUENCE; Schema: report; Owner: -
--

CREATE SEQUENCE report.inquiry_id_seq
    START WITH 120000
    INCREMENT BY 1
    MINVALUE 120000
    NO MAXVALUE
    CACHE 1;


--
-- Name: inquiry_id_seq; Type: SEQUENCE OWNED BY; Schema: report; Owner: -
--

ALTER SEQUENCE report.inquiry_id_seq OWNED BY report.inquiry.id;


--
-- Name: inquiry_sample_id_seq; Type: SEQUENCE; Schema: report; Owner: -
--

CREATE SEQUENCE report.inquiry_sample_id_seq
    START WITH 300000
    INCREMENT BY 1
    MINVALUE 300000
    NO MAXVALUE
    CACHE 1;


--
-- Name: inquiry_sample_id_seq; Type: SEQUENCE OWNED BY; Schema: report; Owner: -
--

ALTER SEQUENCE report.inquiry_sample_id_seq OWNED BY report.inquiry_sample.id;


--
-- Name: recovery; Type: TABLE; Schema: report; Owner: -
--

CREATE TABLE report.recovery (
    id integer NOT NULL,
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_date timestamp with time zone,
    delete_date timestamp with time zone,
    note text,
    attribution_id integer NOT NULL,
    access_policy application.access_policy DEFAULT 'private'::application.access_policy NOT NULL,
    type report.recovery_document_type DEFAULT 'unknown'::report.recovery_document_type NOT NULL,
    document_date date NOT NULL,
    document_file text NOT NULL,
    audit_status report.audit_status DEFAULT 'todo'::report.audit_status NOT NULL,
    document_name text NOT NULL,
    data_owner_organization_id application.organization_id
);


--
-- Name: TABLE recovery; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON TABLE report.recovery IS 'Contains recovery operations.';


--
-- Name: COLUMN recovery.create_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.recovery.create_date IS 'Timestamp of record creation, set by insert';


--
-- Name: COLUMN recovery.update_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.recovery.update_date IS 'Timestamp of last record update, automatically updated on record modification';


--
-- Name: COLUMN recovery.delete_date; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.recovery.delete_date IS 'Timestamp of soft delete';


--
-- Name: COLUMN recovery.document_name; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.recovery.document_name IS 'User provided document name';


--
-- Name: COLUMN recovery.data_owner_organization_id; Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON COLUMN report.recovery.data_owner_organization_id IS 'Organization that owns this recovery''s data (#973). Durable owner, independent of the processing/attribution account; nullable until backfilled, then falls back to attribution.owner_id in the API.';


--
-- Name: recovery_id_seq; Type: SEQUENCE; Schema: report; Owner: -
--

CREATE SEQUENCE report.recovery_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recovery_id_seq; Type: SEQUENCE OWNED BY; Schema: report; Owner: -
--

ALTER SEQUENCE report.recovery_id_seq OWNED BY report.recovery.id;


--
-- Name: recovery_sample_id_seq; Type: SEQUENCE; Schema: report; Owner: -
--

CREATE SEQUENCE report.recovery_sample_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recovery_sample_id_seq; Type: SEQUENCE OWNED BY; Schema: report; Owner: -
--

ALTER SEQUENCE report.recovery_sample_id_seq OWNED BY report.recovery_sample.id;


--
-- Name: attribution id; Type: DEFAULT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.attribution ALTER COLUMN id SET DEFAULT nextval('application.attribution_id_seq'::regclass);


--
-- Name: contractor id; Type: DEFAULT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.contractor ALTER COLUMN id SET DEFAULT nextval('application.contractor_id_seq'::regclass);


--
-- Name: worker_jobs id; Type: DEFAULT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.worker_jobs ALTER COLUMN id SET DEFAULT nextval('application.worker_jobs_id_seq'::regclass);


--
-- Name: inquiry id; Type: DEFAULT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.inquiry ALTER COLUMN id SET DEFAULT nextval('report.inquiry_id_seq'::regclass);


--
-- Name: inquiry_sample id; Type: DEFAULT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.inquiry_sample ALTER COLUMN id SET DEFAULT nextval('report.inquiry_sample_id_seq'::regclass);


--
-- Name: recovery id; Type: DEFAULT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery ALTER COLUMN id SET DEFAULT nextval('report.recovery_id_seq'::regclass);


--
-- Name: recovery_sample id; Type: DEFAULT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery_sample ALTER COLUMN id SET DEFAULT nextval('report.recovery_sample_id_seq'::regclass);


--
-- Name: account account_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.account
    ADD CONSTRAINT account_pkey PRIMARY KEY (id);


--
-- Name: api_key_rate_limit api_key_rate_limit_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.api_key_rate_limit
    ADD CONSTRAINT api_key_rate_limit_pkey PRIMARY KEY (api_key_id, source, product);


--
-- Name: apikey apikey_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.apikey
    ADD CONSTRAINT apikey_pkey PRIMARY KEY (id);


--
-- Name: application application_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.application
    ADD CONSTRAINT application_pkey PRIMARY KEY (application_id);


--
-- Name: application_user application_user_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.application_user
    ADD CONSTRAINT application_user_pkey PRIMARY KEY (user_id, application_id);


--
-- Name: attribution attribution_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.attribution
    ADD CONSTRAINT attribution_pkey PRIMARY KEY (id);


--
-- Name: auth_key auth_key_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_key
    ADD CONSTRAINT auth_key_pkey PRIMARY KEY (id);


--
-- Name: contractor contractor_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.contractor
    ADD CONSTRAINT contractor_pkey PRIMARY KEY (id);


--
-- Name: file_resources file_resources_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.file_resources
    ADD CONSTRAINT file_resources_pkey PRIMARY KEY (id);


--
-- Name: invitation invitation_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.invitation
    ADD CONSTRAINT invitation_pkey PRIMARY KEY (id);


--
-- Name: jwks jwks_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.jwks
    ADD CONSTRAINT jwks_pkey PRIMARY KEY (id);


--
-- Name: mapset_layer mapset_layer_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.mapset_layer
    ADD CONSTRAINT mapset_layer_pkey PRIMARY KEY (id);


--
-- Name: mapset mapset_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.mapset
    ADD CONSTRAINT mapset_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_token oauth_access_token_access_token_key; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_access_token
    ADD CONSTRAINT oauth_access_token_access_token_key UNIQUE (token);


--
-- Name: oauth_access_token oauth_access_token_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_access_token
    ADD CONSTRAINT oauth_access_token_pkey PRIMARY KEY (id);


--
-- Name: oauth_application oauth_application_client_id_key; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_application
    ADD CONSTRAINT oauth_application_client_id_key UNIQUE (client_id);


--
-- Name: oauth_application oauth_application_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_application
    ADD CONSTRAINT oauth_application_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_assertion oauth_client_assertion_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_client_assertion
    ADD CONSTRAINT oauth_client_assertion_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_resource oauth_client_resource_client_id_resource_id_key; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_client_resource
    ADD CONSTRAINT oauth_client_resource_client_id_resource_id_key UNIQUE (client_id, resource_id);


--
-- Name: oauth_client_resource oauth_client_resource_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_client_resource
    ADD CONSTRAINT oauth_client_resource_pkey PRIMARY KEY (id);


--
-- Name: oauth_consent oauth_consent_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_consent
    ADD CONSTRAINT oauth_consent_pkey PRIMARY KEY (id);


--
-- Name: oauth_refresh_token oauth_refresh_token_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_refresh_token
    ADD CONSTRAINT oauth_refresh_token_pkey PRIMARY KEY (id);


--
-- Name: oauth_refresh_token oauth_refresh_token_token_key; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_refresh_token
    ADD CONSTRAINT oauth_refresh_token_token_key UNIQUE (token);


--
-- Name: oauth_resource oauth_resource_identifier_key; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_resource
    ADD CONSTRAINT oauth_resource_identifier_key UNIQUE (identifier);


--
-- Name: oauth_resource oauth_resource_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_resource
    ADD CONSTRAINT oauth_resource_pkey PRIMARY KEY (id);


--
-- Name: organization_custom_role organization_custom_role_organization_id_role_key; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_custom_role
    ADD CONSTRAINT organization_custom_role_organization_id_role_key UNIQUE (organization_id, role);


--
-- Name: organization_custom_role organization_custom_role_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_custom_role
    ADD CONSTRAINT organization_custom_role_pkey PRIMARY KEY (id);


--
-- Name: organization_geolock_district organization_geolock_district_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_district
    ADD CONSTRAINT organization_geolock_district_pkey PRIMARY KEY (organization_id, district_id);


--
-- Name: organization_geolock_municipality organization_geolock_municipality_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_municipality
    ADD CONSTRAINT organization_geolock_municipality_pkey PRIMARY KEY (organization_id, municipality_id);


--
-- Name: organization_geolock_neighborhood organization_geolock_neighborhood_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_neighborhood
    ADD CONSTRAINT organization_geolock_neighborhood_pkey PRIMARY KEY (organization_id, neighborhood_id);


--
-- Name: organization_mapset organization_mapset_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_mapset
    ADD CONSTRAINT organization_mapset_pkey PRIMARY KEY (organization_id, mapset_id);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: organization_user organization_user_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_user
    ADD CONSTRAINT organization_user_pkey PRIMARY KEY (user_id, organization_id);


--
-- Name: session session_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (id);


--
-- Name: session session_token_key; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.session
    ADD CONSTRAINT session_token_key UNIQUE (token);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: verification verification_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.verification
    ADD CONSTRAINT verification_pkey PRIMARY KEY (id);


--
-- Name: worker_jobs worker_jobs_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.worker_jobs
    ADD CONSTRAINT worker_jobs_pkey PRIMARY KEY (id);


--
-- Name: building_cluster building_cluster_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_cluster
    ADD CONSTRAINT building_cluster_pkey PRIMARY KEY (building_id);


--
-- Name: building_elevation building_elevation_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_elevation
    ADD CONSTRAINT building_elevation_pkey PRIMARY KEY (building_id);


--
-- Name: building_geographic_region building_geographic_region_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_geographic_region
    ADD CONSTRAINT building_geographic_region_pkey PRIMARY KEY (building_id);


--
-- Name: building_groundwater_level building_groundwater_level_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_groundwater_level
    ADD CONSTRAINT building_groundwater_level_pkey PRIMARY KEY (building_id);


--
-- Name: building_ownership building_ownership_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_ownership
    ADD CONSTRAINT building_ownership_pkey PRIMARY KEY (building_id);


--
-- Name: building_pleistocene building_pleistocene_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_pleistocene
    ADD CONSTRAINT building_pleistocene_pkey PRIMARY KEY (building_id);


--
-- Name: building_precomputed building_precomputed_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_precomputed
    ADD CONSTRAINT building_precomputed_pkey PRIMARY KEY (building_id);


--
-- Name: building_subsidence_history building_subsidence_history_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_subsidence_history
    ADD CONSTRAINT building_subsidence_history_pkey PRIMARY KEY (building_id, mark_at);


--
-- Name: building_subsidence building_subsidence_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_subsidence
    ADD CONSTRAINT building_subsidence_pkey PRIMARY KEY (building_id);


--
-- Name: cluster_recovery_sample cluster_recovery_sample_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.cluster_recovery_sample
    ADD CONSTRAINT cluster_recovery_sample_pkey PRIMARY KEY (cluster_id);


--
-- Name: foundation_type_lookup_2026_1 foundation_type_lookup_2026_1_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.foundation_type_lookup_2026_1
    ADD CONSTRAINT foundation_type_lookup_2026_1_pkey PRIMARY KEY (cell);


--
-- Name: foundation_type_lookup_2026_2 foundation_type_lookup_2026_2_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.foundation_type_lookup_2026_2
    ADD CONSTRAINT foundation_type_lookup_2026_2_pkey PRIMARY KEY (cell);


--
-- Name: model_compare_2026_1 model_compare_2026_1_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.model_compare_2026_1
    ADD CONSTRAINT model_compare_2026_1_pkey PRIMARY KEY (building_id);


--
-- Name: model_evaluation_sample model_evaluation_sample_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.model_evaluation_sample
    ADD CONSTRAINT model_evaluation_sample_pkey PRIMARY KEY (sample_version, purpose, building_id);


--
-- Name: model_evaluation_stratum_weight model_evaluation_stratum_weight_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.model_evaluation_stratum_weight
    ADD CONSTRAINT model_evaluation_stratum_weight_pkey PRIMARY KEY (sample_version, stratum);


--
-- Name: model_version model_version_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.model_version
    ADD CONSTRAINT model_version_pkey PRIMARY KEY (id);


--
-- Name: model_version model_version_slug_key; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.model_version
    ADD CONSTRAINT model_version_slug_key UNIQUE (slug);


--
-- Name: supercluster supercluster_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.supercluster
    ADD CONSTRAINT supercluster_pkey PRIMARY KEY (cluster_id);


--
-- Name: artifact_page artifact_page_pkey; Type: CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.artifact_page
    ADD CONSTRAINT artifact_page_pkey PRIMARY KEY (artifact_id, page_no);


--
-- Name: artifact artifact_pkey; Type: CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.artifact
    ADD CONSTRAINT artifact_pkey PRIMARY KEY (id);


--
-- Name: dossier_mail dossier_mail_once; Type: CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.dossier_mail
    ADD CONSTRAINT dossier_mail_once UNIQUE (dossier_id, kind);


--
-- Name: dossier_mail dossier_mail_pkey; Type: CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.dossier_mail
    ADD CONSTRAINT dossier_mail_pkey PRIMARY KEY (id);


--
-- Name: dossier dossier_pkey; Type: CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.dossier
    ADD CONSTRAINT dossier_pkey PRIMARY KEY (id);


--
-- Name: extraction_field extraction_field_pkey; Type: CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.extraction_field
    ADD CONSTRAINT extraction_field_pkey PRIMARY KEY (id);


--
-- Name: extraction extraction_pkey; Type: CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.extraction
    ADD CONSTRAINT extraction_pkey PRIMARY KEY (id);


--
-- Name: verdict verdict_pkey; Type: CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.verdict
    ADD CONSTRAINT verdict_pkey PRIMARY KEY (id);


--
-- Name: address address_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (id);


--
-- Name: building building_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.building
    ADD CONSTRAINT building_pkey PRIMARY KEY (id);


--
-- Name: district district_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.district
    ADD CONSTRAINT district_pkey PRIMARY KEY (id);


--
-- Name: municipality municipality_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.municipality
    ADD CONSTRAINT municipality_pkey PRIMARY KEY (id);


--
-- Name: neighborhood neighborhood_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.neighborhood
    ADD CONSTRAINT neighborhood_pkey PRIMARY KEY (id);


--
-- Name: residence residence_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.residence
    ADD CONSTRAINT residence_pkey PRIMARY KEY (id, address_id, building_id);


--
-- Name: state state_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.state
    ADD CONSTRAINT state_pkey PRIMARY KEY (id);


--
-- Name: building_cluster_tiles building_cluster_tiles_pkey; Type: CONSTRAINT; Schema: maplayer; Owner: -
--

ALTER TABLE ONLY maplayer.building_cluster_tiles
    ADD CONSTRAINT building_cluster_tiles_pkey PRIMARY KEY (cluster_id);


--
-- Name: building_tiles building_tiles_pkey; Type: CONSTRAINT; Schema: maplayer; Owner: -
--

ALTER TABLE ONLY maplayer.building_tiles
    ADD CONSTRAINT building_tiles_pkey PRIMARY KEY (building_id);


--
-- Name: bundle bundle_pkey; Type: CONSTRAINT; Schema: maplayer; Owner: -
--

ALTER TABLE ONLY maplayer.bundle
    ADD CONSTRAINT bundle_pkey PRIMARY KEY (tileset);


--
-- Name: facade_scan_tiles facade_scan_tiles_pkey; Type: CONSTRAINT; Schema: maplayer; Owner: -
--

ALTER TABLE ONLY maplayer.facade_scan_tiles
    ADD CONSTRAINT facade_scan_tiles_pkey PRIMARY KEY (external_id);


--
-- Name: incident_district_tiles incident_district_tiles_pkey; Type: CONSTRAINT; Schema: maplayer; Owner: -
--

ALTER TABLE ONLY maplayer.incident_district_tiles
    ADD CONSTRAINT incident_district_tiles_pkey PRIMARY KEY (district_id);


--
-- Name: incident_municipality_tiles incident_municipality_tiles_pkey; Type: CONSTRAINT; Schema: maplayer; Owner: -
--

ALTER TABLE ONLY maplayer.incident_municipality_tiles
    ADD CONSTRAINT incident_municipality_tiles_pkey PRIMARY KEY (municipality_id);


--
-- Name: incident_neighborhood_tiles incident_neighborhood_tiles_pkey; Type: CONSTRAINT; Schema: maplayer; Owner: -
--

ALTER TABLE ONLY maplayer.incident_neighborhood_tiles
    ADD CONSTRAINT incident_neighborhood_tiles_pkey PRIMARY KEY (neighborhood_id);


--
-- Name: incident_tiles incident_tiles_pkey; Type: CONSTRAINT; Schema: maplayer; Owner: -
--

ALTER TABLE ONLY maplayer.incident_tiles
    ADD CONSTRAINT incident_tiles_pkey PRIMARY KEY (id);


--
-- Name: dossier_event dossier_event_pkey; Type: CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.dossier_event
    ADD CONSTRAINT dossier_event_pkey PRIMARY KEY (id);


--
-- Name: incident incident_pkey; Type: CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.incident
    ADD CONSTRAINT incident_pkey PRIMARY KEY (id);


--
-- Name: inquiry inquiry_pkey; Type: CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.inquiry
    ADD CONSTRAINT inquiry_pkey PRIMARY KEY (id);


--
-- Name: inquiry_sample inquiry_sample_pkey; Type: CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.inquiry_sample
    ADD CONSTRAINT inquiry_sample_pkey PRIMARY KEY (id);


--
-- Name: recovery recovery_pkey; Type: CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery
    ADD CONSTRAINT recovery_pkey PRIMARY KEY (id);


--
-- Name: recovery_sample recovery_sample_pkey; Type: CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery_sample
    ADD CONSTRAINT recovery_sample_pkey PRIMARY KEY (id);


--
-- Name: account_issuer_account_id_key; Type: INDEX; Schema: application; Owner: -
--

CREATE UNIQUE INDEX account_issuer_account_id_key ON application.account USING btree (issuer, account_id);


--
-- Name: apikey_config_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX apikey_config_id_idx ON application.apikey USING btree (config_id);


--
-- Name: apikey_key_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX apikey_key_idx ON application.apikey USING btree (key);


--
-- Name: apikey_reference_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX apikey_reference_id_idx ON application.apikey USING btree (reference_id);


--
-- Name: application_user_application_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX application_user_application_id_idx ON application.application_user USING btree (application_id);


--
-- Name: attribution_contractor_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX attribution_contractor_id_idx ON application.attribution USING btree (contractor_id);


--
-- Name: attribution_creator_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX attribution_creator_id_idx ON application.attribution USING btree (creator_id);


--
-- Name: attribution_owner_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX attribution_owner_id_idx ON application.attribution USING btree (owner_id);


--
-- Name: attribution_reviewer_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX attribution_reviewer_id_idx ON application.attribution USING btree (reviewer_id);


--
-- Name: auth_key_expires_at_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_key_expires_at_idx ON application.auth_key USING btree (expires_at) WHERE (expires_at IS NOT NULL);


--
-- Name: auth_key_key_hash_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE UNIQUE INDEX auth_key_key_hash_idx ON application.auth_key USING btree (key_hash);


--
-- Name: auth_key_user_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_key_user_id_idx ON application.auth_key USING btree (user_id);


--
-- Name: file_resources_created_at_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX file_resources_created_at_idx ON application.file_resources USING btree (created_at);


--
-- Name: file_resources_key_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX file_resources_key_idx ON application.file_resources USING btree (key);


--
-- Name: file_resources_status_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX file_resources_status_idx ON application.file_resources USING btree (status);


--
-- Name: idx_account_user_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_account_user_id ON application.account USING btree (user_id);


--
-- Name: idx_oauth_access_token_client_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_access_token_client_id ON application.oauth_access_token USING btree (client_id);


--
-- Name: idx_oauth_access_token_expires_at; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_access_token_expires_at ON application.oauth_access_token USING btree (expires_at);


--
-- Name: idx_oauth_access_token_refresh_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_access_token_refresh_id ON application.oauth_access_token USING btree (refresh_id);


--
-- Name: idx_oauth_access_token_session_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_access_token_session_id ON application.oauth_access_token USING btree (session_id);


--
-- Name: idx_oauth_access_token_user_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_access_token_user_id ON application.oauth_access_token USING btree (user_id);


--
-- Name: idx_oauth_application_user_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_application_user_id ON application.oauth_application USING btree (user_id);


--
-- Name: idx_oauth_client_assertion_expires_at; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_client_assertion_expires_at ON application.oauth_client_assertion USING btree (expires_at);


--
-- Name: idx_oauth_consent_client_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_consent_client_id ON application.oauth_consent USING btree (client_id);


--
-- Name: idx_oauth_consent_user_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_consent_user_id ON application.oauth_consent USING btree (user_id);


--
-- Name: idx_oauth_refresh_token_client_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_refresh_token_client_id ON application.oauth_refresh_token USING btree (client_id);


--
-- Name: idx_oauth_refresh_token_session_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_refresh_token_session_id ON application.oauth_refresh_token USING btree (session_id);


--
-- Name: idx_oauth_refresh_token_user_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_oauth_refresh_token_user_id ON application.oauth_refresh_token USING btree (user_id);


--
-- Name: idx_session_token; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_session_token ON application.session USING btree (token);


--
-- Name: idx_session_user_id; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX idx_session_user_id ON application.session USING btree (user_id);


--
-- Name: invitation_organization_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX invitation_organization_id_idx ON application.invitation USING btree (organization_id);


--
-- Name: organization_geolock_district_district_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX organization_geolock_district_district_id_idx ON application.organization_geolock_district USING btree (district_id);


--
-- Name: organization_geolock_municipality_municipality_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX organization_geolock_municipality_municipality_id_idx ON application.organization_geolock_municipality USING btree (municipality_id);


--
-- Name: organization_geolock_neighborhood_neighborhood_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX organization_geolock_neighborhood_neighborhood_id_idx ON application.organization_geolock_neighborhood USING btree (neighborhood_id);


--
-- Name: organization_mapset_mapset_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX organization_mapset_mapset_id_idx ON application.organization_mapset USING btree (mapset_id);


--
-- Name: organization_slug_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE UNIQUE INDEX organization_slug_idx ON application.organization USING btree (slug);


--
-- Name: organization_user_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE UNIQUE INDEX organization_user_id_idx ON application.organization_user USING btree (id);


--
-- Name: organization_user_organization_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX organization_user_organization_id_idx ON application.organization_user USING btree (organization_id);


--
-- Name: product_tracker_building_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX product_tracker_building_id_idx ON application.product_tracker USING btree (building_id);


--
-- Name: product_tracker_create_date_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX product_tracker_create_date_idx ON application.product_tracker USING btree (create_date DESC);


--
-- Name: product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX product_tracker_org_prod_id_date_idx ON application.product_tracker USING btree (organization_id, product, identifier, create_date);


--
-- Name: user_email_unique_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE UNIQUE INDEX user_email_unique_idx ON application."user" USING btree (lower((email)::text));


--
-- Name: worker_jobs_created_at_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX worker_jobs_created_at_idx ON application.worker_jobs USING btree (created_at);


--
-- Name: worker_jobs_job_type_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX worker_jobs_job_type_idx ON application.worker_jobs USING btree (job_type);


--
-- Name: worker_jobs_priority_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX worker_jobs_priority_idx ON application.worker_jobs USING btree (priority DESC);


--
-- Name: worker_jobs_status_process_after_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX worker_jobs_status_process_after_idx ON application.worker_jobs USING btree (status, process_after) WHERE (status = ANY (ARRAY['pending'::application.job_status, 'retry'::application.job_status]));


--
-- Name: building_cluster_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX building_cluster_idx ON data.building_cluster USING btree (cluster_id, building_id);


--
-- Name: building_precomputed_neighborhood_id_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE INDEX building_precomputed_neighborhood_id_idx ON data.building_precomputed USING btree (neighborhood_id);


--
-- Name: building_sample_2026_1_pkey; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX building_sample_2026_1_pkey ON data.building_sample_2026_1 USING btree (building_id);


--
-- Name: building_sample_building_id_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX building_sample_building_id_idx ON data.building_sample USING btree (building_id);


--
-- Name: cluster_sample_v2_cluster_id_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX cluster_sample_v2_cluster_id_idx ON data.cluster_sample USING btree (cluster_id);


--
-- Name: model_compare_2026_1_change_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE INDEX model_compare_2026_1_change_idx ON data.model_compare_2026_1 USING btree (change_kind) WHERE (change_kind <> 'unchanged'::text);


--
-- Name: model_compare_2026_1_nb_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE INDEX model_compare_2026_1_nb_idx ON data.model_compare_2026_1 USING btree (neighborhood_id);


--
-- Name: model_evaluation_sample_building_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE INDEX model_evaluation_sample_building_idx ON data.model_evaluation_sample USING btree (building_id);


--
-- Name: model_risk_static_2024_1_neighborhood_id_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE INDEX model_risk_static_2024_1_neighborhood_id_idx ON data.model_risk_static_2024_1 USING btree (neighborhood_id);


--
-- Name: model_risk_static_2024_1_pkey; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX model_risk_static_2024_1_pkey ON data.model_risk_static_2024_1 USING btree (building_id);


--
-- Name: model_version_one_default_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX model_version_one_default_idx ON data.model_version USING btree (is_default) WHERE is_default;


--
-- Name: statistics_product_buildings_restored_neighborhood_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_buildings_restored_neighborhood_idx ON data.statistics_product_buildings_restored USING btree (neighborhood_id);


--
-- Name: statistics_product_construction_years_neighborhood_year_from_id; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_construction_years_neighborhood_year_from_id ON data.statistics_product_construction_years USING btree (neighborhood_id, year_from);


--
-- Name: statistics_product_data_collected_neighborhood_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_data_collected_neighborhood_idx ON data.statistics_product_data_collected USING btree (neighborhood_id);


--
-- Name: statistics_product_foundation_risk_neighborhood_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_foundation_risk_neighborhood_idx ON data.statistics_product_foundation_risk USING btree (neighborhood_id, foundation_risk);


--
-- Name: statistics_product_foundation_type_neighborhood_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_foundation_type_neighborhood_idx ON data.statistics_product_foundation_type USING btree (neighborhood_id, foundation_type);


--
-- Name: statistics_product_incident_municipality_municipality_year_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_incident_municipality_municipality_year_idx ON data.statistics_product_incident_municipality USING btree (municipality_id, year);


--
-- Name: statistics_product_incidents_neighborhood_year_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_incidents_neighborhood_year_idx ON data.statistics_product_incidents USING btree (neighborhood_id, year);


--
-- Name: statistics_product_inquiries_neighborhood_year_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_inquiries_neighborhood_year_idx ON data.statistics_product_inquiries USING btree (neighborhood_id, year);


--
-- Name: statistics_product_inquiry_municipality_municipality_year_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_product_inquiry_municipality_municipality_year_idx ON data.statistics_product_inquiry_municipality USING btree (municipality_id, year);


--
-- Name: supercluster_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX supercluster_idx ON data.supercluster USING btree (cluster_id, supercluster_id);


--
-- Name: supercluster_sample_v2_supercluster_id_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX supercluster_sample_v2_supercluster_id_idx ON data.supercluster_sample USING btree (supercluster_id);


--
-- Name: artifact_dossier_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX artifact_dossier_idx ON dataops.artifact USING btree (dossier_id);


--
-- Name: artifact_parent_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX artifact_parent_idx ON dataops.artifact USING btree (parent_artifact_id) WHERE (parent_artifact_id IS NOT NULL);


--
-- Name: dossier_building_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX dossier_building_idx ON dataops.dossier USING btree (building_id) WHERE (building_id IS NOT NULL);


--
-- Name: dossier_reference_key; Type: INDEX; Schema: dataops; Owner: -
--

CREATE UNIQUE INDEX dossier_reference_key ON dataops.dossier USING btree (reference) WHERE (reference IS NOT NULL);


--
-- Name: dossier_submitter_email_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX dossier_submitter_email_idx ON dataops.dossier USING btree (lower((submitter ->> 'email'::text))) WHERE (submitter IS NOT NULL);


--
-- Name: extraction_artifact_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX extraction_artifact_idx ON dataops.extraction USING btree (artifact_id);


--
-- Name: extraction_field_address_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX extraction_field_address_idx ON dataops.extraction_field USING btree (address_id) WHERE (address_id IS NOT NULL);


--
-- Name: extraction_field_reading_field_value_addr_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE UNIQUE INDEX extraction_field_reading_field_value_addr_idx ON dataops.extraction_field USING btree (extraction_id, field, value, COALESCE(address_text, ''::text));


--
-- Name: extraction_field_state_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX extraction_field_state_idx ON dataops.extraction_field USING btree (state) WHERE (state = 'pending'::dataops.review_state);


--
-- Name: verdict_decided_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX verdict_decided_idx ON dataops.verdict USING btree (decided_at DESC);


--
-- Name: verdict_field_idx; Type: INDEX; Schema: dataops; Owner: -
--

CREATE INDEX verdict_field_idx ON dataops.verdict USING btree (extraction_field_id);


--
-- Name: address_building_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX address_building_id_idx ON geocoder.address USING btree (building_id);


--
-- Name: address_external_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE UNIQUE INDEX address_external_id_idx ON geocoder.address USING btree (external_id);


--
-- Name: address_postal_code_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX address_postal_code_idx ON geocoder.address USING btree (postal_code);


--
-- Name: address_streetname_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX address_streetname_idx ON geocoder.address USING btree (lower(street));


--
-- Name: building_external_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE UNIQUE INDEX building_external_id_idx ON geocoder.building USING btree (external_id);


--
-- Name: building_geom_gist; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX building_geom_gist ON geocoder.building USING gist (geom);


--
-- Name: building_neighborhood_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX building_neighborhood_idx ON geocoder.building USING btree (neighborhood_id);


--
-- Name: district_external_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE UNIQUE INDEX district_external_id_idx ON geocoder.district USING btree (external_id);


--
-- Name: district_geom_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX district_geom_idx ON geocoder.district USING gist (geom);


--
-- Name: district_municipality_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX district_municipality_idx ON geocoder.district USING btree (municipality_id);


--
-- Name: district_name_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX district_name_idx ON geocoder.district USING btree (name);


--
-- Name: municipality_external_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE UNIQUE INDEX municipality_external_id_idx ON geocoder.municipality USING btree (external_id);


--
-- Name: municipality_geom_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX municipality_geom_idx ON geocoder.municipality USING gist (geom);


--
-- Name: municipality_name_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX municipality_name_idx ON geocoder.municipality USING btree (name);


--
-- Name: neighborhood_district_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX neighborhood_district_idx ON geocoder.neighborhood USING btree (district_id);


--
-- Name: neighborhood_external_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE UNIQUE INDEX neighborhood_external_id_idx ON geocoder.neighborhood USING btree (external_id);


--
-- Name: neighborhood_geom_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX neighborhood_geom_idx ON geocoder.neighborhood USING gist (geom);


--
-- Name: neighborhood_name_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX neighborhood_name_idx ON geocoder.neighborhood USING btree (name);


--
-- Name: residence_address_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX residence_address_id_idx ON geocoder.residence USING btree (address_id);


--
-- Name: residence_building_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX residence_building_id_idx ON geocoder.residence USING btree (building_id);


--
-- Name: state_country_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX state_country_idx ON geocoder.state USING btree (country_id);


--
-- Name: state_external_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE UNIQUE INDEX state_external_id_idx ON geocoder.state USING btree (external_id);


--
-- Name: state_geom_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX state_geom_idx ON geocoder.state USING gist (geom);


--
-- Name: state_name_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX state_name_idx ON geocoder.state USING btree (name);


--
-- Name: building_cluster_tiles_geom_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX building_cluster_tiles_geom_idx ON maplayer.building_cluster_tiles USING gist (geom);


--
-- Name: building_cluster_tiles_geom_simple_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX building_cluster_tiles_geom_simple_idx ON maplayer.building_cluster_tiles USING gist (geom_simple);


--
-- Name: building_tiles_geom_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX building_tiles_geom_idx ON maplayer.building_tiles USING gist (geom);


--
-- Name: building_tiles_geom_simple_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX building_tiles_geom_simple_idx ON maplayer.building_tiles USING gist (geom_simple);


--
-- Name: facade_scan_tiles_geom_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX facade_scan_tiles_geom_idx ON maplayer.facade_scan_tiles USING gist (geom);


--
-- Name: incident_district_tiles_geom_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX incident_district_tiles_geom_idx ON maplayer.incident_district_tiles USING gist (geom);


--
-- Name: incident_district_tiles_geom_simple_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX incident_district_tiles_geom_simple_idx ON maplayer.incident_district_tiles USING gist (geom_simple);


--
-- Name: incident_municipality_tiles_geom_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX incident_municipality_tiles_geom_idx ON maplayer.incident_municipality_tiles USING gist (geom);


--
-- Name: incident_municipality_tiles_geom_simple_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX incident_municipality_tiles_geom_simple_idx ON maplayer.incident_municipality_tiles USING gist (geom_simple);


--
-- Name: incident_neighborhood_tiles_geom_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX incident_neighborhood_tiles_geom_idx ON maplayer.incident_neighborhood_tiles USING gist (geom);


--
-- Name: incident_neighborhood_tiles_geom_simple_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX incident_neighborhood_tiles_geom_simple_idx ON maplayer.incident_neighborhood_tiles USING gist (geom_simple);


--
-- Name: incident_tiles_geom_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX incident_tiles_geom_idx ON maplayer.incident_tiles USING gist (geom);


--
-- Name: dossier_event_incident_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX dossier_event_incident_idx ON report.dossier_event USING btree (incident_id, create_date) WHERE (incident_id IS NOT NULL);


--
-- Name: dossier_event_inquiry_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX dossier_event_inquiry_idx ON report.dossier_event USING btree (inquiry_id, create_date) WHERE (inquiry_id IS NOT NULL);


--
-- Name: dossier_event_recovery_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX dossier_event_recovery_idx ON report.dossier_event USING btree (recovery_id, create_date) WHERE (recovery_id IS NOT NULL);


--
-- Name: incident_building_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX incident_building_id_idx ON report.incident USING btree (building_id);


--
-- Name: inquiry_access_policy_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX inquiry_access_policy_idx ON report.inquiry USING btree (access_policy);


--
-- Name: inquiry_attribution_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX inquiry_attribution_id_idx ON report.inquiry USING btree (attribution_id);


--
-- Name: inquiry_data_owner_organization_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX inquiry_data_owner_organization_id_idx ON report.inquiry USING btree (data_owner_organization_id);


--
-- Name: inquiry_document_date_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX inquiry_document_date_idx ON report.inquiry USING btree (document_date);


--
-- Name: inquiry_sample_address_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX inquiry_sample_address_idx ON report.inquiry_sample USING btree (address);


--
-- Name: inquiry_sample_building_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX inquiry_sample_building_id_idx ON report.inquiry_sample USING btree (building_id);


--
-- Name: inquiry_sample_inquiry_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX inquiry_sample_inquiry_id_idx ON report.inquiry_sample USING btree (inquiry_id);


--
-- Name: inquiry_type_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX inquiry_type_idx ON report.inquiry USING btree (type);


--
-- Name: recovery_access_policy_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_access_policy_idx ON report.recovery USING btree (access_policy);


--
-- Name: recovery_attribution_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_attribution_id_idx ON report.recovery USING btree (attribution_id);


--
-- Name: recovery_data_owner_organization_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_data_owner_organization_id_idx ON report.recovery USING btree (data_owner_organization_id);


--
-- Name: recovery_sample_building_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_sample_building_id_idx ON report.recovery_sample USING btree (building_id);


--
-- Name: recovery_sample_contractor_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_sample_contractor_id_idx ON report.recovery_sample USING btree (contractor_id);


--
-- Name: recovery_sample_pile_type_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_sample_pile_type_idx ON report.recovery_sample USING btree (pile_type);


--
-- Name: recovery_sample_recovery_id_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_sample_recovery_id_idx ON report.recovery_sample USING btree (recovery_id);


--
-- Name: recovery_sample_status_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_sample_status_idx ON report.recovery_sample USING btree (status);


--
-- Name: recovery_sample_type_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_sample_type_idx ON report.recovery_sample USING btree (type);


--
-- Name: recovery_type_idx; Type: INDEX; Schema: report; Owner: -
--

CREATE INDEX recovery_type_idx ON report.recovery USING btree (type);


--
-- Name: incident update_date_record; Type: TRIGGER; Schema: report; Owner: -
--

CREATE TRIGGER update_date_record BEFORE UPDATE ON report.incident FOR EACH ROW EXECUTE FUNCTION report.last_record_update();


--
-- Name: inquiry update_date_record; Type: TRIGGER; Schema: report; Owner: -
--

CREATE TRIGGER update_date_record BEFORE UPDATE ON report.inquiry FOR EACH ROW EXECUTE FUNCTION report.last_record_update();


--
-- Name: inquiry_sample update_date_record; Type: TRIGGER; Schema: report; Owner: -
--

CREATE TRIGGER update_date_record BEFORE UPDATE ON report.inquiry_sample FOR EACH ROW EXECUTE FUNCTION report.last_record_update();


--
-- Name: recovery update_date_record; Type: TRIGGER; Schema: report; Owner: -
--

CREATE TRIGGER update_date_record BEFORE UPDATE ON report.recovery FOR EACH ROW EXECUTE FUNCTION report.last_record_update();


--
-- Name: recovery_sample update_date_record; Type: TRIGGER; Schema: report; Owner: -
--

CREATE TRIGGER update_date_record BEFORE UPDATE ON report.recovery_sample FOR EACH ROW EXECUTE FUNCTION report.last_record_update();


--
-- Name: account account_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.account
    ADD CONSTRAINT account_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON DELETE CASCADE;


--
-- Name: apikey apikey_reference_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.apikey
    ADD CONSTRAINT apikey_reference_id_fkey FOREIGN KEY (reference_id) REFERENCES application."user"(id) ON DELETE CASCADE;


--
-- Name: application_user application_user_application_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.application_user
    ADD CONSTRAINT application_user_application_id_fkey FOREIGN KEY (application_id) REFERENCES application.application(application_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: application_user application_user_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.application_user
    ADD CONSTRAINT application_user_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: attribution attribution_contractor_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.attribution
    ADD CONSTRAINT attribution_contractor_id_fkey FOREIGN KEY (contractor_id) REFERENCES application.contractor(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: attribution attribution_creator_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.attribution
    ADD CONSTRAINT attribution_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: attribution attribution_owner_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.attribution
    ADD CONSTRAINT attribution_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: attribution attribution_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.attribution
    ADD CONSTRAINT attribution_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: auth_key auth_key_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_key
    ADD CONSTRAINT auth_key_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: invitation invitation_inviter_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.invitation
    ADD CONSTRAINT invitation_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES application."user"(id);


--
-- Name: invitation invitation_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.invitation
    ADD CONSTRAINT invitation_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON DELETE CASCADE;


--
-- Name: oauth_access_token oauth_access_token_client_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_access_token
    ADD CONSTRAINT oauth_access_token_client_id_fkey FOREIGN KEY (client_id) REFERENCES application.oauth_application(client_id) ON DELETE CASCADE;


--
-- Name: oauth_access_token oauth_access_token_refresh_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_access_token
    ADD CONSTRAINT oauth_access_token_refresh_id_fkey FOREIGN KEY (refresh_id) REFERENCES application.oauth_refresh_token(id) ON DELETE CASCADE;


--
-- Name: oauth_access_token oauth_access_token_session_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_access_token
    ADD CONSTRAINT oauth_access_token_session_id_fkey FOREIGN KEY (session_id) REFERENCES application.session(id) ON DELETE SET NULL;


--
-- Name: oauth_access_token oauth_access_token_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_access_token
    ADD CONSTRAINT oauth_access_token_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON DELETE CASCADE;


--
-- Name: oauth_application oauth_application_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_application
    ADD CONSTRAINT oauth_application_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON DELETE CASCADE;


--
-- Name: oauth_client_resource oauth_client_resource_client_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_client_resource
    ADD CONSTRAINT oauth_client_resource_client_id_fkey FOREIGN KEY (client_id) REFERENCES application.oauth_application(client_id) ON DELETE CASCADE;


--
-- Name: oauth_client_resource oauth_client_resource_resource_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_client_resource
    ADD CONSTRAINT oauth_client_resource_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES application.oauth_resource(identifier) ON DELETE CASCADE;


--
-- Name: oauth_consent oauth_consent_client_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_consent
    ADD CONSTRAINT oauth_consent_client_id_fkey FOREIGN KEY (client_id) REFERENCES application.oauth_application(client_id) ON DELETE CASCADE;


--
-- Name: oauth_consent oauth_consent_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_consent
    ADD CONSTRAINT oauth_consent_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON DELETE CASCADE;


--
-- Name: oauth_refresh_token oauth_refresh_token_client_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_refresh_token
    ADD CONSTRAINT oauth_refresh_token_client_id_fkey FOREIGN KEY (client_id) REFERENCES application.oauth_application(client_id) ON DELETE CASCADE;


--
-- Name: oauth_refresh_token oauth_refresh_token_session_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_refresh_token
    ADD CONSTRAINT oauth_refresh_token_session_id_fkey FOREIGN KEY (session_id) REFERENCES application.session(id) ON DELETE SET NULL;


--
-- Name: oauth_refresh_token oauth_refresh_token_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.oauth_refresh_token
    ADD CONSTRAINT oauth_refresh_token_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON DELETE CASCADE;


--
-- Name: organization_custom_role organization_custom_role_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_custom_role
    ADD CONSTRAINT organization_custom_role_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON DELETE CASCADE;


--
-- Name: organization_geolock_district organization_geolock_district_district_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_district
    ADD CONSTRAINT organization_geolock_district_district_id_fkey FOREIGN KEY (district_id) REFERENCES geocoder.district(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_geolock_district organization_geolock_district_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_district
    ADD CONSTRAINT organization_geolock_district_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_geolock_municipality organization_geolock_municipality_municipality_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_municipality
    ADD CONSTRAINT organization_geolock_municipality_municipality_id_fkey FOREIGN KEY (municipality_id) REFERENCES geocoder.municipality(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_geolock_municipality organization_geolock_municipality_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_municipality
    ADD CONSTRAINT organization_geolock_municipality_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_geolock_neighborhood organization_geolock_neighborhood_neighborhood_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_neighborhood
    ADD CONSTRAINT organization_geolock_neighborhood_neighborhood_id_fkey FOREIGN KEY (neighborhood_id) REFERENCES geocoder.neighborhood(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_geolock_neighborhood organization_geolock_neighborhood_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_geolock_neighborhood
    ADD CONSTRAINT organization_geolock_neighborhood_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_mapset organization_mapset_mapset_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_mapset
    ADD CONSTRAINT organization_mapset_mapset_id_fkey FOREIGN KEY (mapset_id) REFERENCES application.mapset(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_mapset organization_mapset_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_mapset
    ADD CONSTRAINT organization_mapset_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_user organization_user_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_user
    ADD CONSTRAINT organization_user_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: organization_user organization_user_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.organization_user
    ADD CONSTRAINT organization_user_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: product_tracker product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.product_tracker
    ADD CONSTRAINT product_tracker_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: product_tracker product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.product_tracker
    ADD CONSTRAINT product_tracker_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: session session_active_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.session
    ADD CONSTRAINT session_active_organization_id_fkey FOREIGN KEY (active_organization_id) REFERENCES application.organization(id) ON DELETE SET NULL;


--
-- Name: session session_impersonated_by_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.session
    ADD CONSTRAINT session_impersonated_by_fkey FOREIGN KEY (impersonated_by) REFERENCES application."user"(id) ON DELETE SET NULL;


--
-- Name: session session_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.session
    ADD CONSTRAINT session_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON DELETE CASCADE;


--
-- Name: building_cluster building_cluster_building_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_cluster
    ADD CONSTRAINT building_cluster_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: building_elevation building_elevation_building_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_elevation
    ADD CONSTRAINT building_elevation_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: building_geographic_region building_geographic_region_building_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_geographic_region
    ADD CONSTRAINT building_geographic_region_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: building_groundwater_level building_groundwater_level_building_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_groundwater_level
    ADD CONSTRAINT building_groundwater_level_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: building_ownership building_ownership_building_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_ownership
    ADD CONSTRAINT building_ownership_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: building_pleistocene building_pleistocene_building_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_pleistocene
    ADD CONSTRAINT building_pleistocene_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: building_subsidence building_subsidence_building_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_subsidence
    ADD CONSTRAINT building_subsidence_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: building_subsidence_history building_subsidence_history_building_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.building_subsidence_history
    ADD CONSTRAINT building_subsidence_history_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: artifact artifact_dossier_id_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.artifact
    ADD CONSTRAINT artifact_dossier_id_fkey FOREIGN KEY (dossier_id) REFERENCES dataops.dossier(id) ON DELETE CASCADE;


--
-- Name: artifact_page artifact_page_artifact_id_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.artifact_page
    ADD CONSTRAINT artifact_page_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES dataops.artifact(id) ON DELETE CASCADE;


--
-- Name: artifact artifact_parent_artifact_id_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.artifact
    ADD CONSTRAINT artifact_parent_artifact_id_fkey FOREIGN KEY (parent_artifact_id) REFERENCES dataops.artifact(id) ON DELETE CASCADE;


--
-- Name: dossier dossier_duplicate_of_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.dossier
    ADD CONSTRAINT dossier_duplicate_of_fkey FOREIGN KEY (duplicate_of) REFERENCES dataops.dossier(id);


--
-- Name: dossier_mail dossier_mail_dossier_id_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.dossier_mail
    ADD CONSTRAINT dossier_mail_dossier_id_fkey FOREIGN KEY (dossier_id) REFERENCES dataops.dossier(id) ON DELETE CASCADE;


--
-- Name: extraction extraction_artifact_id_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.extraction
    ADD CONSTRAINT extraction_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES dataops.artifact(id) ON DELETE CASCADE;


--
-- Name: extraction_field extraction_field_address_id_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.extraction_field
    ADD CONSTRAINT extraction_field_address_id_fkey FOREIGN KEY (address_id) REFERENCES geocoder.address(id) ON DELETE SET NULL;


--
-- Name: extraction_field extraction_field_extraction_id_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.extraction_field
    ADD CONSTRAINT extraction_field_extraction_id_fkey FOREIGN KEY (extraction_id) REFERENCES dataops.extraction(id) ON DELETE CASCADE;


--
-- Name: verdict verdict_extraction_field_id_fkey; Type: FK CONSTRAINT; Schema: dataops; Owner: -
--

ALTER TABLE ONLY dataops.verdict
    ADD CONSTRAINT verdict_extraction_field_id_fkey FOREIGN KEY (extraction_field_id) REFERENCES dataops.extraction_field(id) ON DELETE CASCADE;


--
-- Name: address address_building_id_fkey; Type: FK CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.address
    ADD CONSTRAINT address_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: building building_neighborhood_id_fkey; Type: FK CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.building
    ADD CONSTRAINT building_neighborhood_id_fkey FOREIGN KEY (neighborhood_id) REFERENCES geocoder.neighborhood(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: district district_municipality_id_fkey; Type: FK CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.district
    ADD CONSTRAINT district_municipality_id_fkey FOREIGN KEY (municipality_id) REFERENCES geocoder.municipality(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: neighborhood neighborhood_district_id_fkey; Type: FK CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.neighborhood
    ADD CONSTRAINT neighborhood_district_id_fkey FOREIGN KEY (district_id) REFERENCES geocoder.district(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: residence residence_address_id_fkey; Type: FK CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.residence
    ADD CONSTRAINT residence_address_id_fkey FOREIGN KEY (address_id) REFERENCES geocoder.address(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: residence residence_building_id_fkey; Type: FK CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.residence
    ADD CONSTRAINT residence_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: dossier_event dossier_event_actor_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.dossier_event
    ADD CONSTRAINT dossier_event_actor_fkey FOREIGN KEY (actor) REFERENCES application."user"(id) ON DELETE SET NULL;


--
-- Name: dossier_event dossier_event_incident_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.dossier_event
    ADD CONSTRAINT dossier_event_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES report.incident(id) ON DELETE CASCADE;


--
-- Name: dossier_event dossier_event_inquiry_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.dossier_event
    ADD CONSTRAINT dossier_event_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES report.inquiry(id) ON DELETE CASCADE;


--
-- Name: dossier_event dossier_event_recovery_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.dossier_event
    ADD CONSTRAINT dossier_event_recovery_id_fkey FOREIGN KEY (recovery_id) REFERENCES report.recovery(id) ON DELETE CASCADE;


--
-- Name: incident incident_building_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.incident
    ADD CONSTRAINT incident_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: inquiry inquiry_attribution_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.inquiry
    ADD CONSTRAINT inquiry_attribution_id_fkey FOREIGN KEY (attribution_id) REFERENCES application.attribution(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: inquiry inquiry_data_owner_organization_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.inquiry
    ADD CONSTRAINT inquiry_data_owner_organization_id_fkey FOREIGN KEY (data_owner_organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: inquiry_sample inquiry_sample_building_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.inquiry_sample
    ADD CONSTRAINT inquiry_sample_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: inquiry_sample inquiry_sample_inquiry_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.inquiry_sample
    ADD CONSTRAINT inquiry_sample_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES report.inquiry(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: recovery recovery_attribution_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery
    ADD CONSTRAINT recovery_attribution_id_fkey FOREIGN KEY (attribution_id) REFERENCES application.attribution(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: recovery recovery_data_owner_organization_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery
    ADD CONSTRAINT recovery_data_owner_organization_id_fkey FOREIGN KEY (data_owner_organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: recovery_sample recovery_sample_building_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery_sample
    ADD CONSTRAINT recovery_sample_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: recovery_sample recovery_sample_contractor_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery_sample
    ADD CONSTRAINT recovery_sample_contractor_id_fkey FOREIGN KEY (contractor_id) REFERENCES application.contractor(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: recovery_sample recovery_sample_recovery_id_fkey; Type: FK CONSTRAINT; Schema: report; Owner: -
--

ALTER TABLE ONLY report.recovery_sample
    ADD CONSTRAINT recovery_sample_recovery_id_fkey FOREIGN KEY (recovery_id) REFERENCES report.recovery(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict 78jk05M09uaP5i49W6qAj48tXlBg5K8V3GPpE2ciCL3To7NlcwdyPykBiY6WVHm

