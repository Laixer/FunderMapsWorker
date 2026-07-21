--
-- PostgreSQL database dump
--

\restrict ZjD8I2nYbXGWRKPYx409fdZOGvf4BQzdbaz5tncwtqkG7JaKKb14HsxTISXRtUL

-- Dumped from database version 17.10
-- Dumped by pg_dump version 18.4 (Ubuntu 18.4-0ubuntu0.26.04.1)

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
-- Name: reliability; Type: TYPE; Schema: data; Owner: -
--

CREATE TYPE data.reliability AS ENUM (
    'indicative',
    'established',
    'cluster',
    'supercluster'
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

    -- Legacy C# WebApi tables --------------------------------------------------

    DELETE FROM application.auth_access_token
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired access tokens (legacy).', FOUND::TEXT;

    DELETE FROM application.auth_code
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired auth codes (legacy).', FOUND::TEXT;

    DELETE FROM application.auth_refresh_token
    WHERE expired_at < NOW();
    RAISE NOTICE 'Deleted % expired refresh tokens (legacy).', FOUND::TEXT;

    -- Better Auth tables -------------------------------------------------------

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
-- Name: refresh_clusters(); Type: PROCEDURE; Schema: data; Owner: -
--

CREATE PROCEDURE data.refresh_clusters()
    LANGUAGE plpgsql
    AS $$
DECLARE
    local_cluster text[];
    neighbors text[];
    counter integer := 0;
    cluster_id uuid;
BEGIN
    DROP TABLE IF EXISTS building_all;
    CREATE TEMP TABLE building_all (
        building_id text NOT NULL,
        CONSTRAINT building_all_pkey PRIMARY KEY (building_id)
    );

    INSERT INTO building_all
    SELECT ba.external_id FROM geocoder.building_active AS ba
    EXCEPT
    SELECT c.building_id FROM data.building_cluster AS c;

    TRUNCATE data.building_cluster;

    LOOP
        SELECT INTO cluster_id uuid_generate_v4();
        SELECT INTO local_cluster ARRAY[building_id] FROM building_all LIMIT 1;

        EXIT WHEN local_cluster IS NULL;

        neighbors := local_cluster;

        LOOP
            SELECT array_agg(b2.external_id) INTO neighbors
            FROM geocoder.building_active b
            JOIN geocoder.building_active b2
                ON st_intersects(b.geom, b2.geom)
                AND b.built_year = b2.built_year
                AND b2.external_id <> all(local_cluster)
            WHERE b.built_year IS NOT NULL
            AND b.external_id = any(neighbors);

            EXIT WHEN neighbors IS NULL;

            local_cluster := local_cluster || neighbors;
        END LOOP;

        IF array_length(local_cluster, 1) > 1 THEN
            INSERT INTO data.building_cluster
            SELECT unnest(local_cluster), cluster_id
            ON CONFLICT DO NOTHING;
        END IF;

        DELETE FROM building_all
        WHERE building_id = any(local_cluster);

        IF counter % 1000 = 0 THEN
            RAISE NOTICE 'Counter %', counter;
            COMMIT;
        END IF;

        IF counter % 50000 = 0 AND counter > 0 THEN
            RAISE NOTICE 'Reindex %', counter;
            REINDEX INDEX data.building_all_pk;
        END IF;

        counter := counter + 1;
    END LOOP;

    DROP TABLE building_all;
END;
$$;


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
-- Name: buildings(integer, integer, integer); Type: FUNCTION; Schema: maplayer; Owner: -
--

CREATE FUNCTION maplayer.buildings(z integer, x integer, y integer) RETURNS bytea
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
                enforcement_term, overall_quality, recovery_type,
                ST_AsMVTGeom(geom, env, 4096, 64, true) AS geom
            FROM maplayer.building_tiles
            WHERE geom && env
        ) tile
        WHERE tile.geom IS NOT NULL;
    ELSE
        SELECT ST_AsMVT(tile, 'buildings', 4096, 'geom') INTO mvt
        FROM (
            SELECT
                construction_year, foundation_type, foundation_type_reliability,
                drystand_risk, bio_infection_risk, dewatering_depth_risk,
                unclassified_risk, recovery_type, velocity, damage_cause,
                inquiry_type,
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

COMMENT ON FUNCTION maplayer.buildings(z integer, x integer, y integer) IS '{"description": "FunderMaps building foundation tiles (dynamic)", "minzoom": 12, "maxzoom": 16, "bounds": [3.2, 50.7, 7.3, 53.6], "vector_layers": [{"id": "buildings", "minzoom": 12, "maxzoom": 16}]}';


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
        enforcement_term, overall_quality, recovery_type,
        surface_area, geom, geom_simple
    )
    SELECT
        building_id,
        ext_neighborhood_id,
        ext_district_id,
        ext_municipality_id,
        address_count,
        construction_year,
        construction_year_reliability::text,
        foundation_type::text,
        foundation_type_reliability::text,
        restoration_costs,
        drystand,
        drystand_risk::text,
        drystand_risk_reliability::text,
        bio_infection_risk::text,
        bio_infection_risk_reliability::text,
        dewatering_depth,
        dewatering_depth_risk::text,
        dewatering_depth_risk_reliability::text,
        unclassified_risk::text,
        height::double precision,
        velocity::double precision,
        owner,
        inquiry_type::text,
        damage_cause::text,
        enforcement_term,
        overall_quality::text,
        recovery_type::text,
        surface_area::double precision,
        ST_Transform(geom, 3857),
        ST_SimplifyPreserveTopology(ST_Transform(geom, 3857), 5.0)
    FROM data.building_geo_hierarchy
    WHERE geom IS NOT NULL;

    ANALYZE maplayer.building_tiles;
$$;


--
-- Name: fir_generate_id(integer); Type: FUNCTION; Schema: report; Owner: -
--

CREATE FUNCTION report.fir_generate_id(client_id integer) RETURNS text
    LANGUAGE sql
    AS $_$select 'FIR' || lpad($1::text, 2, '0') || date_part('year', CURRENT_DATE) || '-' || nextval('report.incident_id_seq');
$_$;


--
-- Name: FUNCTION fir_generate_id(client_id integer); Type: COMMENT; Schema: report; Owner: -
--

COMMENT ON FUNCTION report.fir_generate_id(client_id integer) IS 'Generate a new FIR identifier.';


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
-- Name: product_tracker_mismatch; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.product_tracker_mismatch (
    organization_id application.organization_id NOT NULL,
    identifier text NOT NULL,
    create_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: COLUMN product_tracker_mismatch.create_date; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON COLUMN application.product_tracker_mismatch.create_date IS 'Timestamp of record creation, set by insert';


--
-- Name: _hyper_1_10_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_10_chunk (
    CONSTRAINT constraint_10 CHECK (((create_date >= '2023-01-23 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-02-22 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_11_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_11_chunk (
    CONSTRAINT constraint_11 CHECK (((create_date >= '2024-08-15 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-09-14 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_12_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_12_chunk (
    CONSTRAINT constraint_12 CHECK (((create_date >= '2024-12-13 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-01-12 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_132_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_132_chunk (
    CONSTRAINT constraint_132 CHECK (((create_date >= '2026-04-07 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-05-07 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_134_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_134_chunk (
    CONSTRAINT constraint_134 CHECK (((create_date >= '2026-05-07 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-06-06 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_136_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_136_chunk (
    CONSTRAINT constraint_136 CHECK (((create_date >= '2026-06-06 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-07-06 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_13_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_13_chunk (
    CONSTRAINT constraint_13 CHECK (((create_date >= '2025-01-12 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-02-11 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_14_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_14_chunk (
    CONSTRAINT constraint_14 CHECK (((create_date >= '2023-02-22 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-03-24 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_15_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_15_chunk (
    CONSTRAINT constraint_15 CHECK (((create_date >= '2023-03-24 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-04-23 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_16_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_16_chunk (
    CONSTRAINT constraint_16 CHECK (((create_date >= '2023-04-23 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-05-23 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_17_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_17_chunk (
    CONSTRAINT constraint_17 CHECK (((create_date >= '2025-03-13 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-04-12 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_18_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_18_chunk (
    CONSTRAINT constraint_18 CHECK (((create_date >= '2023-05-23 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-06-22 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_19_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_19_chunk (
    CONSTRAINT constraint_19 CHECK (((create_date >= '2023-06-22 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-07-22 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_1_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_1_chunk (
    CONSTRAINT constraint_1 CHECK (((create_date >= '2022-08-26 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-09-25 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_20_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_20_chunk (
    CONSTRAINT constraint_20 CHECK (((create_date >= '2023-07-22 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-08-21 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_21_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_21_chunk (
    CONSTRAINT constraint_21 CHECK (((create_date >= '2023-08-21 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-09-20 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_22_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_22_chunk (
    CONSTRAINT constraint_22 CHECK (((create_date >= '2023-09-20 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-10-20 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_23_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_23_chunk (
    CONSTRAINT constraint_23 CHECK (((create_date >= '2023-10-20 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-11-19 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_24_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_24_chunk (
    CONSTRAINT constraint_24 CHECK (((create_date >= '2024-01-18 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-02-17 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_25_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_25_chunk (
    CONSTRAINT constraint_25 CHECK (((create_date >= '2024-02-17 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-03-18 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_26_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_26_chunk (
    CONSTRAINT constraint_26 CHECK (((create_date >= '2024-03-18 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-04-17 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_27_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_27_chunk (
    CONSTRAINT constraint_27 CHECK (((create_date >= '2024-05-17 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-06-16 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_28_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_28_chunk (
    CONSTRAINT constraint_28 CHECK (((create_date >= '2024-06-16 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-07-16 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_29_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_29_chunk (
    CONSTRAINT constraint_29 CHECK (((create_date >= '2024-07-16 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-08-15 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_2_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_2_chunk (
    CONSTRAINT constraint_2 CHECK (((create_date >= '2025-02-11 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-03-13 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_30_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_30_chunk (
    CONSTRAINT constraint_30 CHECK (((create_date >= '2024-09-14 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-10-14 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_31_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_31_chunk (
    CONSTRAINT constraint_31 CHECK (((create_date >= '2024-10-14 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-11-13 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_32_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_32_chunk (
    CONSTRAINT constraint_32 CHECK (((create_date >= '2024-11-13 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-12-13 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_33_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_33_chunk (
    CONSTRAINT constraint_33 CHECK (((create_date >= '2025-04-12 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-05-12 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_34_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_34_chunk (
    CONSTRAINT constraint_34 CHECK (((create_date >= '2025-05-12 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-06-11 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_35_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_35_chunk (
    CONSTRAINT constraint_35 CHECK (((create_date >= '2025-06-11 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-07-11 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_36_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_36_chunk (
    CONSTRAINT constraint_36 CHECK (((create_date >= '2025-07-11 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-08-10 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_37_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_37_chunk (
    CONSTRAINT constraint_37 CHECK (((create_date >= '2025-08-10 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-09-09 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_38_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_38_chunk (
    CONSTRAINT constraint_38 CHECK (((create_date >= '2025-09-09 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-10-09 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_39_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_39_chunk (
    CONSTRAINT constraint_39 CHECK (((create_date >= '2025-10-09 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-11-08 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_3_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_3_chunk (
    CONSTRAINT constraint_3 CHECK (((create_date >= '2022-09-25 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-10-25 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_40_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_40_chunk (
    CONSTRAINT constraint_40 CHECK (((create_date >= '2025-11-08 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-12-08 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_41_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_41_chunk (
    CONSTRAINT constraint_41 CHECK (((create_date >= '2025-12-08 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-01-07 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_42_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_42_chunk (
    CONSTRAINT constraint_42 CHECK (((create_date >= '2026-01-07 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-02-06 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_43_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_43_chunk (
    CONSTRAINT constraint_43 CHECK (((create_date >= '2026-02-06 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-03-08 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_4_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_4_chunk (
    CONSTRAINT constraint_4 CHECK (((create_date >= '2022-10-25 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-11-24 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_5_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_5_chunk (
    CONSTRAINT constraint_5 CHECK (((create_date >= '2022-11-24 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-12-24 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_6_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_6_chunk (
    CONSTRAINT constraint_6 CHECK (((create_date >= '2022-12-24 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-01-23 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_7_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_7_chunk (
    CONSTRAINT constraint_7 CHECK (((create_date >= '2023-11-19 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-12-19 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_8_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_8_chunk (
    CONSTRAINT constraint_8 CHECK (((create_date >= '2023-12-19 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-01-18 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_98_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_98_chunk (
    CONSTRAINT constraint_98 CHECK (((create_date >= '2026-03-08 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-04-07 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


--
-- Name: _hyper_1_9_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_1_9_chunk (
    CONSTRAINT constraint_9 CHECK (((create_date >= '2024-04-17 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-05-17 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker_mismatch);


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
-- Name: _hyper_2_131_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_131_chunk (
    CONSTRAINT constraint_131 CHECK (((create_date >= '2026-04-07 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-05-07 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_133_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_133_chunk (
    CONSTRAINT constraint_133 CHECK (((create_date >= '2026-05-07 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-06-06 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_135_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_135_chunk (
    CONSTRAINT constraint_135 CHECK (((create_date >= '2026-06-06 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-07-06 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_44_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_44_chunk (
    CONSTRAINT constraint_44 CHECK (((create_date >= '2021-10-30 00:00:00+00'::timestamp with time zone) AND (create_date < '2021-11-29 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_45_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_45_chunk (
    CONSTRAINT constraint_45 CHECK (((create_date >= '2021-11-29 00:00:00+00'::timestamp with time zone) AND (create_date < '2021-12-29 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_46_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_46_chunk (
    CONSTRAINT constraint_46 CHECK (((create_date >= '2021-12-29 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-01-28 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_47_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_47_chunk (
    CONSTRAINT constraint_47 CHECK (((create_date >= '2022-11-24 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-12-24 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_48_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_48_chunk (
    CONSTRAINT constraint_48 CHECK (((create_date >= '2022-12-24 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-01-23 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_49_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_49_chunk (
    CONSTRAINT constraint_49 CHECK (((create_date >= '2022-04-28 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-05-28 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_50_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_50_chunk (
    CONSTRAINT constraint_50 CHECK (((create_date >= '2022-05-28 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-06-27 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_51_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_51_chunk (
    CONSTRAINT constraint_51 CHECK (((create_date >= '2022-06-27 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-07-27 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_52_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_52_chunk (
    CONSTRAINT constraint_52 CHECK (((create_date >= '2022-07-27 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-08-26 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_53_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_53_chunk (
    CONSTRAINT constraint_53 CHECK (((create_date >= '2022-08-26 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-09-25 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_54_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_54_chunk (
    CONSTRAINT constraint_54 CHECK (((create_date >= '2022-09-25 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-10-25 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_55_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_55_chunk (
    CONSTRAINT constraint_55 CHECK (((create_date >= '2022-10-25 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-11-24 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_56_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_56_chunk (
    CONSTRAINT constraint_56 CHECK (((create_date >= '2022-01-28 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-02-27 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_57_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_57_chunk (
    CONSTRAINT constraint_57 CHECK (((create_date >= '2022-02-27 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-03-29 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_58_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_58_chunk (
    CONSTRAINT constraint_58 CHECK (((create_date >= '2022-03-29 00:00:00+00'::timestamp with time zone) AND (create_date < '2022-04-28 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_59_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_59_chunk (
    CONSTRAINT constraint_59 CHECK (((create_date >= '2023-07-22 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-08-21 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_60_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_60_chunk (
    CONSTRAINT constraint_60 CHECK (((create_date >= '2023-10-20 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-11-19 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_61_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_61_chunk (
    CONSTRAINT constraint_61 CHECK (((create_date >= '2023-01-23 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-02-22 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_62_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_62_chunk (
    CONSTRAINT constraint_62 CHECK (((create_date >= '2023-02-22 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-03-24 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_63_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_63_chunk (
    CONSTRAINT constraint_63 CHECK (((create_date >= '2023-03-24 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-04-23 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_64_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_64_chunk (
    CONSTRAINT constraint_64 CHECK (((create_date >= '2023-04-23 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-05-23 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_65_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_65_chunk (
    CONSTRAINT constraint_65 CHECK (((create_date >= '2023-05-23 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-06-22 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_66_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_66_chunk (
    CONSTRAINT constraint_66 CHECK (((create_date >= '2023-06-22 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-07-22 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_67_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_67_chunk (
    CONSTRAINT constraint_67 CHECK (((create_date >= '2023-08-21 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-09-20 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_68_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_68_chunk (
    CONSTRAINT constraint_68 CHECK (((create_date >= '2023-09-20 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-10-20 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_69_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_69_chunk (
    CONSTRAINT constraint_69 CHECK (((create_date >= '2023-11-19 00:00:00+00'::timestamp with time zone) AND (create_date < '2023-12-19 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_70_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_70_chunk (
    CONSTRAINT constraint_70 CHECK (((create_date >= '2023-12-19 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-01-18 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_71_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_71_chunk (
    CONSTRAINT constraint_71 CHECK (((create_date >= '2024-03-18 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-04-17 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_72_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_72_chunk (
    CONSTRAINT constraint_72 CHECK (((create_date >= '2024-04-17 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-05-17 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_73_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_73_chunk (
    CONSTRAINT constraint_73 CHECK (((create_date >= '2024-05-17 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-06-16 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_74_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_74_chunk (
    CONSTRAINT constraint_74 CHECK (((create_date >= '2024-06-16 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-07-16 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_75_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_75_chunk (
    CONSTRAINT constraint_75 CHECK (((create_date >= '2024-07-16 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-08-15 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_76_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_76_chunk (
    CONSTRAINT constraint_76 CHECK (((create_date >= '2024-08-15 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-09-14 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_77_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_77_chunk (
    CONSTRAINT constraint_77 CHECK (((create_date >= '2024-09-14 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-10-14 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_78_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_78_chunk (
    CONSTRAINT constraint_78 CHECK (((create_date >= '2024-10-14 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-11-13 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_79_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_79_chunk (
    CONSTRAINT constraint_79 CHECK (((create_date >= '2024-11-13 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-12-13 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_80_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_80_chunk (
    CONSTRAINT constraint_80 CHECK (((create_date >= '2024-12-13 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-01-12 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_81_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_81_chunk (
    CONSTRAINT constraint_81 CHECK (((create_date >= '2024-02-17 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-03-18 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_82_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_82_chunk (
    CONSTRAINT constraint_82 CHECK (((create_date >= '2024-01-18 00:00:00+00'::timestamp with time zone) AND (create_date < '2024-02-17 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_83_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_83_chunk (
    CONSTRAINT constraint_83 CHECK (((create_date >= '2025-01-12 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-02-11 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_84_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_84_chunk (
    CONSTRAINT constraint_84 CHECK (((create_date >= '2025-02-11 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-03-13 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_85_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_85_chunk (
    CONSTRAINT constraint_85 CHECK (((create_date >= '2025-03-13 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-04-12 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_86_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_86_chunk (
    CONSTRAINT constraint_86 CHECK (((create_date >= '2025-04-12 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-05-12 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_87_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_87_chunk (
    CONSTRAINT constraint_87 CHECK (((create_date >= '2025-05-12 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-06-11 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_88_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_88_chunk (
    CONSTRAINT constraint_88 CHECK (((create_date >= '2025-06-11 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-07-11 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_89_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_89_chunk (
    CONSTRAINT constraint_89 CHECK (((create_date >= '2025-10-09 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-11-08 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_90_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_90_chunk (
    CONSTRAINT constraint_90 CHECK (((create_date >= '2025-08-10 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-09-09 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_91_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_91_chunk (
    CONSTRAINT constraint_91 CHECK (((create_date >= '2025-09-09 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-10-09 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_92_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_92_chunk (
    CONSTRAINT constraint_92 CHECK (((create_date >= '2025-07-11 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-08-10 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_93_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_93_chunk (
    CONSTRAINT constraint_93 CHECK (((create_date >= '2025-11-08 00:00:00+00'::timestamp with time zone) AND (create_date < '2025-12-08 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_94_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_94_chunk (
    CONSTRAINT constraint_94 CHECK (((create_date >= '2025-12-08 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-01-07 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_95_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_95_chunk (
    CONSTRAINT constraint_95 CHECK (((create_date >= '2026-02-06 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-03-08 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_96_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_96_chunk (
    CONSTRAINT constraint_96 CHECK (((create_date >= '2026-01-07 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-02-06 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


--
-- Name: _hyper_2_97_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._hyper_2_97_chunk (
    CONSTRAINT constraint_97 CHECK (((create_date >= '2026-03-08 00:00:00+00'::timestamp with time zone) AND (create_date < '2026-04-07 00:00:00+00'::timestamp with time zone)))
)
INHERITS (application.product_tracker);


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
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


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
-- Name: auth_access_token; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.auth_access_token (
    access_token text NOT NULL,
    ip_address inet NOT NULL,
    application_id text NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    expired_at timestamp with time zone NOT NULL
);


--
-- Name: auth_code; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.auth_code (
    code text NOT NULL,
    application_id text NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expired_at timestamp with time zone NOT NULL,
    code_challenge text,
    code_challenge_method text
);


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
-- Name: auth_refresh_token; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.auth_refresh_token (
    token text NOT NULL,
    application_id text NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expired_at timestamp with time zone
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
-- Name: jwks; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.jwks (
    id text NOT NULL,
    public_key text NOT NULL,
    private_key text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    expires_at timestamp without time zone
);


--
-- Name: key_store; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.key_store (
    name text NOT NULL,
    value text NOT NULL
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
    refresh_id text
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
    type text NOT NULL,
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
    public boolean,
    enable_end_session boolean,
    subject_type text,
    uri text,
    tos text,
    policy text,
    software_id text,
    software_version text,
    software_statement text,
    token_endpoint_auth_method text,
    reference_id text
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
    reference_id text
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
    scopes text[] NOT NULL
);


--
-- Name: organization; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.organization (
    id application.organization_id DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL
);


--
-- Name: TABLE organization; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.organization IS 'Contains all organizations that are using FunderMaps.';


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
    role application.organization_role DEFAULT 'reader'::application.organization_role NOT NULL
);


--
-- Name: TABLE organization_user; Type: COMMENT; Schema: application; Owner: -
--

COMMENT ON TABLE application.organization_user IS 'Linking table between organizations and their users.';


--
-- Name: portal; Type: TABLE; Schema: application; Owner: -
--

CREATE TABLE application.portal (
    id integer NOT NULL,
    name text
);


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
    impersonated_by uuid
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
    last_login timestamp with time zone,
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
    audit_status report.audit_status DEFAULT 'todo'::report.audit_status NOT NULL
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
    metadata jsonb
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
-- Name: model_risk_static; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.model_risk_static AS
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
   FROM ((((data.model_risk_static mrs
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
-- Name: building_subsidence_history; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.building_subsidence_history (
    building_id text NOT NULL,
    velocity double precision NOT NULL,
    mark_at date NOT NULL
);


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
-- Name: risk_table_priority; Type: TABLE; Schema: data; Owner: -
--

CREATE TABLE data.risk_table_priority (
    risk data.foundation_risk_indication,
    settlement_speed report.rotation_type,
    priority character varying(50)
);


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
-- Name: statistics_postal_code_data_collected; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_postal_code_data_collected AS
 SELECT a.postal_code,
    (((count(a.id) FILTER (WHERE (i.id IS NOT NULL)))::double precision / (count(a.id))::double precision) * (100)::double precision) AS percentage
   FROM (geocoder.address a
     LEFT JOIN report.inquiry_sample i ON (((i.building_id)::text = (a.building_id)::text)))
  GROUP BY a.postal_code
  WITH NO DATA;


--
-- Name: address_building; Type: VIEW; Schema: geocoder; Owner: -
--

CREATE VIEW geocoder.address_building AS
 SELECT addr.id AS address_id,
    ba.external_id AS building_id,
    ba.geom
   FROM (geocoder.address addr
     JOIN geocoder.building_active ba ON (((addr.building_id)::text = ba.external_id)));


--
-- Name: statistics_postal_code_foundation_risk; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_postal_code_foundation_risk AS
 SELECT postal_code,
    risk AS foundation_risk,
    (((count(risk))::numeric / sum(count(risk)) OVER (PARTITION BY postal_code)) * (100)::numeric) AS percentage
   FROM ( SELECT a.postal_code,
            ( SELECT unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]) AS risk
                  ORDER BY (unnest(ARRAY[mrs.drystand_risk, mrs.bio_infection_risk, mrs.dewatering_depth_risk, mrs.unclassified_risk]))
                 LIMIT 1) AS risk
           FROM ((data.model_risk_static mrs
             JOIN geocoder.address_building ab ON ((ab.building_id = mrs.building_id)))
             JOIN geocoder.address a ON (((a.id)::text = (ab.address_id)::text)))) acr
  WHERE (risk IS NOT NULL)
  GROUP BY postal_code, risk
  WITH NO DATA;


--
-- Name: statistics_postal_code_foundation_type; Type: MATERIALIZED VIEW; Schema: data; Owner: -
--

CREATE MATERIALIZED VIEW data.statistics_postal_code_foundation_type AS
 SELECT a.postal_code,
    mrs.foundation_type,
    (((count(mrs.foundation_type))::numeric / sum(count(mrs.foundation_type)) OVER (PARTITION BY a.postal_code)) * (100)::numeric) AS percentage
   FROM ((data.model_risk_static mrs
     JOIN geocoder.address_building ab ON ((ab.building_id = mrs.building_id)))
     JOIN geocoder.address a ON (((a.id)::text = (ab.address_id)::text)))
  GROUP BY a.postal_code, mrs.foundation_type
  WITH NO DATA;


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
           FROM data.model_risk_static mrs) acr
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
   FROM data.model_risk_static mrs
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
-- Name: country; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.country (
    id geocoder.geocoder_id DEFAULT geocoder.geocoder_generate_id() NOT NULL,
    external_id text NOT NULL,
    name text NOT NULL,
    geom public.geometry(MultiPolygon,4326) NOT NULL
);


--
-- Name: TABLE country; Type: COMMENT; Schema: geocoder; Owner: -
--

COMMENT ON TABLE geocoder.country IS 'Contains all countries in our own format.';


--
-- Name: postal_code; Type: TABLE; Schema: geocoder; Owner: -
--

CREATE TABLE geocoder.postal_code (
    postal_code character varying(6) NOT NULL,
    geom public.geometry(MultiPolygon,4326) NOT NULL
);


--
-- Name: analysis_building; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.analysis_building AS
 SELECT building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    address_count,
    construction_year,
    construction_year_reliability,
    height,
    owner,
    geom
   FROM data.building_geo_hierarchy;


--
-- Name: analysis_foundation; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.analysis_foundation AS
 SELECT building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    foundation_type,
    foundation_type_reliability,
    height,
    owner,
    recovery_type,
    velocity,
    geom
   FROM data.building_geo_hierarchy;


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
-- Name: analysis_monitoring; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.analysis_monitoring AS
 SELECT DISTINCT ON (ba.external_id) ba.external_id AS building_id,
    round((GREATEST(bh.height, (0)::real))::numeric, 2) AS height,
    n.external_id AS neighborhood_id,
    d.external_id AS district_id,
    m.external_id AS municipality_id,
    ba.geom
   FROM ((((((report.inquiry_sample is2
     JOIN report.inquiry i ON ((i.id = is2.inquiry_id)))
     JOIN geocoder.building_active ba ON ((ba.external_id = (is2.building_id)::text)))
     JOIN data.building_height bh ON ((bh.building_id = ba.external_id)))
     JOIN geocoder.neighborhood n ON (((n.id)::text = (ba.neighborhood_id)::text)))
     JOIN geocoder.district d ON (((d.id)::text = (n.district_id)::text)))
     JOIN geocoder.municipality m ON (((m.id)::text = (d.municipality_id)::text)))
  WHERE (i.type = 'monitoring'::report.inquiry_type)
  ORDER BY ba.external_id, i.document_date DESC;


--
-- Name: analysis_report; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.analysis_report AS
 SELECT building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
    height,
    owner,
    inquiry_type,
    damage_cause,
    enforcement_term,
    overall_quality,
    geom
   FROM data.building_geo_hierarchy;


--
-- Name: analysis_risk; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.analysis_risk AS
 SELECT building_id,
    ext_neighborhood_id AS neighborhood_id,
    ext_district_id AS district_id,
    ext_municipality_id AS municipality_id,
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
    height,
    owner,
    geom
   FROM data.building_geo_hierarchy;


--
-- Name: boundary_district; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.boundary_district AS
 SELECT geom
   FROM geocoder.district d;


--
-- Name: boundary_municipality; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.boundary_municipality AS
 SELECT geom
   FROM geocoder.municipality m;


--
-- Name: boundary_neighborhood; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.boundary_neighborhood AS
 SELECT geom
   FROM geocoder.neighborhood n;


--
-- Name: building_cluster; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.building_cluster AS
 SELECT bc.cluster_id,
    public.st_union(ba.geom) AS geom
   FROM (data.building_cluster bc
     JOIN geocoder.building_active ba ON ((ba.external_id = bc.building_id)))
  GROUP BY bc.cluster_id;


--
-- Name: building_supercluster; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.building_supercluster AS
 SELECT s.supercluster_id,
    public.st_union(ba.geom) AS geom
   FROM ((data.supercluster s
     JOIN data.building_cluster bc ON ((bc.cluster_id = s.cluster_id)))
     JOIN geocoder.building_active ba ON ((ba.external_id = bc.building_id)))
  GROUP BY s.supercluster_id;


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
    surface_area double precision,
    geom public.geometry(MultiPolygon,3857),
    geom_simple public.geometry(MultiPolygon,3857)
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
                    WHEN (is2.settlement_speed < (0.5)::double precision) THEN 'nil'::report.rotation_type
                    WHEN ((is2.settlement_speed >= (0.5)::double precision) AND (is2.settlement_speed < (2)::double precision)) THEN 'small'::report.rotation_type
                    WHEN ((is2.settlement_speed >= (2)::double precision) AND (is2.settlement_speed < (3)::double precision)) THEN 'mediocre'::report.rotation_type
                    WHEN ((is2.settlement_speed >= (3)::double precision) AND (is2.settlement_speed < (4)::double precision)) THEN 'big'::report.rotation_type
                    WHEN (is2.settlement_speed >= (4)::double precision) THEN 'very_big'::report.rotation_type
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
-- Name: statistics_foundation_risk; Type: VIEW; Schema: maplayer; Owner: -
--

CREATE VIEW maplayer.statistics_foundation_risk AS
 SELECT spfr.neighborhood_id,
    spfr.foundation_risk,
    spfr.percentage,
    n.geom
   FROM (data.statistics_product_foundation_risk spfr
     JOIN geocoder.neighborhood n ON (((n.id)::text = spfr.neighborhood_id)));


--
-- Name: model_supply; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_supply (
    building_id text NOT NULL
);


--
-- Name: incident_id_seq; Type: SEQUENCE; Schema: report; Owner: -
--

CREATE SEQUENCE report.incident_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


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
    document_name text NOT NULL
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
-- Name: _hyper_1_10_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_10_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_11_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_11_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_12_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_12_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_132_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_132_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_134_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_134_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_136_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_136_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_13_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_13_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_14_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_14_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_15_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_15_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_16_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_16_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_17_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_17_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_18_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_18_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_19_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_19_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_1_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_1_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_20_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_20_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_21_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_21_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_22_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_22_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_23_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_23_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_24_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_24_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_25_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_25_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_26_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_26_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_27_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_27_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_28_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_28_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_29_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_29_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_2_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_2_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_30_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_30_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_31_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_31_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_32_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_32_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_33_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_33_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_34_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_34_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_35_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_35_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_36_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_36_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_37_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_37_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_38_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_38_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_39_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_39_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_3_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_3_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_40_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_40_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_41_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_41_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_42_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_42_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_43_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_43_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_4_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_4_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_5_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_5_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_6_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_6_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_7_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_7_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_8_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_8_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_98_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_98_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_1_9_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_9_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_131_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_131_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_133_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_133_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_135_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_135_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_44_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_44_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_45_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_45_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_46_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_46_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_47_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_47_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_48_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_48_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_49_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_49_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_50_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_50_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_51_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_51_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_52_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_52_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_53_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_53_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_54_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_54_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_55_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_55_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_56_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_56_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_57_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_57_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_58_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_58_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_59_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_59_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_60_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_60_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_61_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_61_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_62_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_62_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_63_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_63_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_64_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_64_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_65_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_65_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_66_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_66_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_67_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_67_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_68_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_68_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_69_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_69_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_70_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_70_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_71_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_71_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_72_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_72_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_73_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_73_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_74_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_74_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_75_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_75_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_76_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_76_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_77_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_77_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_78_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_78_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_79_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_79_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_80_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_80_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_81_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_81_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_82_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_82_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_83_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_83_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_84_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_84_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_85_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_85_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_86_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_86_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_87_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_87_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_88_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_88_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_89_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_89_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_90_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_90_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_91_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_91_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_92_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_92_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_93_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_93_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_94_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_94_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_95_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_95_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_96_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_96_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


--
-- Name: _hyper_2_97_chunk create_date; Type: DEFAULT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_97_chunk ALTER COLUMN create_date SET DEFAULT CURRENT_TIMESTAMP;


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
-- Name: auth_access_token auth_access_token_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_access_token
    ADD CONSTRAINT auth_access_token_pkey PRIMARY KEY (access_token);


--
-- Name: auth_code auth_code_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_code
    ADD CONSTRAINT auth_code_pkey PRIMARY KEY (code);


--
-- Name: auth_key auth_key_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_key
    ADD CONSTRAINT auth_key_pkey PRIMARY KEY (id);


--
-- Name: auth_refresh_token auth_refresh_token_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_refresh_token
    ADD CONSTRAINT auth_refresh_token_pkey PRIMARY KEY (token);


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
-- Name: jwks jwks_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.jwks
    ADD CONSTRAINT jwks_pkey PRIMARY KEY (id);


--
-- Name: key_store key_store_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.key_store
    ADD CONSTRAINT key_store_pkey PRIMARY KEY (name);


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
-- Name: portal portal_pkey; Type: CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.portal
    ADD CONSTRAINT portal_pkey PRIMARY KEY (id);


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
-- Name: supercluster supercluster_pkey; Type: CONSTRAINT; Schema: data; Owner: -
--

ALTER TABLE ONLY data.supercluster
    ADD CONSTRAINT supercluster_pkey PRIMARY KEY (cluster_id);


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
-- Name: country country_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.country
    ADD CONSTRAINT country_pkey PRIMARY KEY (id);


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
-- Name: postal_code postal_code_pkey; Type: CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.postal_code
    ADD CONSTRAINT postal_code_pkey PRIMARY KEY (postal_code);


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
-- Name: model_supply model_supply_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_supply
    ADD CONSTRAINT model_supply_pkey PRIMARY KEY (building_id);


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
-- Name: _hyper_1_10_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_10_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_10_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_10_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_10_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_10_chunk USING btree (organization_id);


--
-- Name: _hyper_1_11_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_11_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_11_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_11_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_11_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_11_chunk USING btree (organization_id);


--
-- Name: _hyper_1_12_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_12_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_12_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_12_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_12_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_12_chunk USING btree (organization_id);


--
-- Name: _hyper_1_132_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_132_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_132_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_132_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_132_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_132_chunk USING btree (organization_id);


--
-- Name: _hyper_1_134_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_134_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_134_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_134_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_134_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_134_chunk USING btree (organization_id);


--
-- Name: _hyper_1_136_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_136_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_136_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_136_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_136_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_136_chunk USING btree (organization_id);


--
-- Name: _hyper_1_13_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_13_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_13_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_13_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_13_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_13_chunk USING btree (organization_id);


--
-- Name: _hyper_1_14_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_14_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_14_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_14_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_14_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_14_chunk USING btree (organization_id);


--
-- Name: _hyper_1_15_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_15_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_15_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_15_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_15_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_15_chunk USING btree (organization_id);


--
-- Name: _hyper_1_16_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_16_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_16_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_16_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_16_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_16_chunk USING btree (organization_id);


--
-- Name: _hyper_1_17_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_17_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_17_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_17_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_17_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_17_chunk USING btree (organization_id);


--
-- Name: _hyper_1_18_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_18_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_18_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_18_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_18_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_18_chunk USING btree (organization_id);


--
-- Name: _hyper_1_19_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_19_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_19_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_19_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_19_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_19_chunk USING btree (organization_id);


--
-- Name: _hyper_1_1_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_1_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_1_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_1_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_1_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_1_chunk USING btree (organization_id);


--
-- Name: _hyper_1_20_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_20_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_20_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_20_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_20_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_20_chunk USING btree (organization_id);


--
-- Name: _hyper_1_21_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_21_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_21_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_21_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_21_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_21_chunk USING btree (organization_id);


--
-- Name: _hyper_1_22_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_22_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_22_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_22_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_22_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_22_chunk USING btree (organization_id);


--
-- Name: _hyper_1_23_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_23_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_23_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_23_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_23_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_23_chunk USING btree (organization_id);


--
-- Name: _hyper_1_24_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_24_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_24_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_24_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_24_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_24_chunk USING btree (organization_id);


--
-- Name: _hyper_1_25_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_25_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_25_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_25_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_25_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_25_chunk USING btree (organization_id);


--
-- Name: _hyper_1_26_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_26_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_26_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_26_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_26_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_26_chunk USING btree (organization_id);


--
-- Name: _hyper_1_27_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_27_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_27_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_27_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_27_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_27_chunk USING btree (organization_id);


--
-- Name: _hyper_1_28_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_28_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_28_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_28_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_28_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_28_chunk USING btree (organization_id);


--
-- Name: _hyper_1_29_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_29_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_29_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_29_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_29_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_29_chunk USING btree (organization_id);


--
-- Name: _hyper_1_2_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_2_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_2_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_2_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_2_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_2_chunk USING btree (organization_id);


--
-- Name: _hyper_1_30_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_30_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_30_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_30_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_30_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_30_chunk USING btree (organization_id);


--
-- Name: _hyper_1_31_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_31_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_31_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_31_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_31_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_31_chunk USING btree (organization_id);


--
-- Name: _hyper_1_32_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_32_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_32_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_32_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_32_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_32_chunk USING btree (organization_id);


--
-- Name: _hyper_1_33_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_33_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_33_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_33_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_33_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_33_chunk USING btree (organization_id);


--
-- Name: _hyper_1_34_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_34_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_34_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_34_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_34_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_34_chunk USING btree (organization_id);


--
-- Name: _hyper_1_35_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_35_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_35_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_35_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_35_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_35_chunk USING btree (organization_id);


--
-- Name: _hyper_1_36_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_36_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_36_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_36_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_36_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_36_chunk USING btree (organization_id);


--
-- Name: _hyper_1_37_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_37_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_37_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_37_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_37_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_37_chunk USING btree (organization_id);


--
-- Name: _hyper_1_38_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_38_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_38_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_38_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_38_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_38_chunk USING btree (organization_id);


--
-- Name: _hyper_1_39_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_39_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_39_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_39_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_39_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_39_chunk USING btree (organization_id);


--
-- Name: _hyper_1_3_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_3_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_3_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_3_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_3_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_3_chunk USING btree (organization_id);


--
-- Name: _hyper_1_40_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_40_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_40_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_40_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_40_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_40_chunk USING btree (organization_id);


--
-- Name: _hyper_1_41_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_41_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_41_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_41_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_41_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_41_chunk USING btree (organization_id);


--
-- Name: _hyper_1_42_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_42_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_42_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_42_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_42_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_42_chunk USING btree (organization_id);


--
-- Name: _hyper_1_43_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_43_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_43_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_43_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_43_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_43_chunk USING btree (organization_id);


--
-- Name: _hyper_1_4_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_4_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_4_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_4_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_4_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_4_chunk USING btree (organization_id);


--
-- Name: _hyper_1_5_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_5_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_5_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_5_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_5_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_5_chunk USING btree (organization_id);


--
-- Name: _hyper_1_6_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_6_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_6_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_6_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_6_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_6_chunk USING btree (organization_id);


--
-- Name: _hyper_1_7_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_7_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_7_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_7_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_7_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_7_chunk USING btree (organization_id);


--
-- Name: _hyper_1_8_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_8_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_8_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_8_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_8_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_8_chunk USING btree (organization_id);


--
-- Name: _hyper_1_98_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_98_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_98_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_98_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_98_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_98_chunk USING btree (organization_id);


--
-- Name: _hyper_1_9_chunk_product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_9_chunk_product_tracker_mismatch_create_date_idx ON _timescaledb_internal._hyper_1_9_chunk USING btree (create_date DESC);


--
-- Name: _hyper_1_9_chunk_product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_1_9_chunk_product_tracker_mismatch_organization_id_idx ON _timescaledb_internal._hyper_1_9_chunk USING btree (organization_id);


--
-- Name: _hyper_2_131_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_131_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_131_chunk USING btree (building_id);


--
-- Name: _hyper_2_131_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_131_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_131_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_131_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_131_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_131_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_133_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_133_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_133_chunk USING btree (building_id);


--
-- Name: _hyper_2_133_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_133_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_133_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_133_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_133_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_133_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_135_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_135_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_135_chunk USING btree (building_id);


--
-- Name: _hyper_2_135_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_135_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_135_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_135_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_135_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_135_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_44_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_44_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_44_chunk USING btree (building_id);


--
-- Name: _hyper_2_44_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_44_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_44_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_44_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_44_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_44_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_45_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_45_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_45_chunk USING btree (building_id);


--
-- Name: _hyper_2_45_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_45_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_45_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_45_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_45_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_45_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_46_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_46_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_46_chunk USING btree (building_id);


--
-- Name: _hyper_2_46_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_46_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_46_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_46_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_46_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_46_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_47_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_47_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_47_chunk USING btree (building_id);


--
-- Name: _hyper_2_47_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_47_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_47_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_47_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_47_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_47_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_48_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_48_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_48_chunk USING btree (building_id);


--
-- Name: _hyper_2_48_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_48_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_48_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_48_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_48_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_48_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_49_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_49_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_49_chunk USING btree (building_id);


--
-- Name: _hyper_2_49_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_49_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_49_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_49_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_49_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_49_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_50_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_50_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_50_chunk USING btree (building_id);


--
-- Name: _hyper_2_50_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_50_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_50_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_50_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_50_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_50_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_51_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_51_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_51_chunk USING btree (building_id);


--
-- Name: _hyper_2_51_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_51_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_51_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_51_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_51_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_51_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_52_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_52_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_52_chunk USING btree (building_id);


--
-- Name: _hyper_2_52_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_52_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_52_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_52_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_52_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_52_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_53_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_53_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_53_chunk USING btree (building_id);


--
-- Name: _hyper_2_53_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_53_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_53_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_53_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_53_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_53_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_54_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_54_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_54_chunk USING btree (building_id);


--
-- Name: _hyper_2_54_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_54_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_54_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_54_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_54_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_54_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_55_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_55_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_55_chunk USING btree (building_id);


--
-- Name: _hyper_2_55_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_55_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_55_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_55_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_55_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_55_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_56_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_56_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_56_chunk USING btree (building_id);


--
-- Name: _hyper_2_56_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_56_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_56_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_56_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_56_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_56_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_57_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_57_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_57_chunk USING btree (building_id);


--
-- Name: _hyper_2_57_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_57_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_57_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_57_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_57_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_57_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_58_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_58_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_58_chunk USING btree (building_id);


--
-- Name: _hyper_2_58_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_58_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_58_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_58_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_58_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_58_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_59_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_59_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_59_chunk USING btree (building_id);


--
-- Name: _hyper_2_59_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_59_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_59_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_59_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_59_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_59_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_60_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_60_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_60_chunk USING btree (building_id);


--
-- Name: _hyper_2_60_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_60_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_60_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_60_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_60_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_60_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_61_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_61_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_61_chunk USING btree (building_id);


--
-- Name: _hyper_2_61_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_61_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_61_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_61_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_61_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_61_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_62_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_62_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_62_chunk USING btree (building_id);


--
-- Name: _hyper_2_62_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_62_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_62_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_62_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_62_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_62_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_63_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_63_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_63_chunk USING btree (building_id);


--
-- Name: _hyper_2_63_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_63_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_63_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_63_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_63_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_63_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_64_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_64_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_64_chunk USING btree (building_id);


--
-- Name: _hyper_2_64_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_64_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_64_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_64_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_64_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_64_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_65_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_65_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_65_chunk USING btree (building_id);


--
-- Name: _hyper_2_65_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_65_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_65_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_65_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_65_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_65_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_66_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_66_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_66_chunk USING btree (building_id);


--
-- Name: _hyper_2_66_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_66_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_66_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_66_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_66_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_66_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_67_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_67_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_67_chunk USING btree (building_id);


--
-- Name: _hyper_2_67_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_67_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_67_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_67_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_67_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_67_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_68_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_68_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_68_chunk USING btree (building_id);


--
-- Name: _hyper_2_68_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_68_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_68_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_68_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_68_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_68_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_69_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_69_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_69_chunk USING btree (building_id);


--
-- Name: _hyper_2_69_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_69_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_69_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_69_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_69_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_69_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_70_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_70_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_70_chunk USING btree (building_id);


--
-- Name: _hyper_2_70_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_70_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_70_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_70_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_70_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_70_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_71_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_71_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_71_chunk USING btree (building_id);


--
-- Name: _hyper_2_71_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_71_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_71_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_71_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_71_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_71_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_72_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_72_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_72_chunk USING btree (building_id);


--
-- Name: _hyper_2_72_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_72_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_72_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_72_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_72_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_72_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_73_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_73_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_73_chunk USING btree (building_id);


--
-- Name: _hyper_2_73_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_73_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_73_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_73_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_73_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_73_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_74_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_74_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_74_chunk USING btree (building_id);


--
-- Name: _hyper_2_74_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_74_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_74_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_74_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_74_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_74_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_75_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_75_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_75_chunk USING btree (building_id);


--
-- Name: _hyper_2_75_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_75_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_75_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_75_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_75_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_75_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_76_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_76_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_76_chunk USING btree (building_id);


--
-- Name: _hyper_2_76_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_76_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_76_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_76_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_76_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_76_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_77_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_77_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_77_chunk USING btree (building_id);


--
-- Name: _hyper_2_77_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_77_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_77_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_77_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_77_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_77_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_78_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_78_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_78_chunk USING btree (building_id);


--
-- Name: _hyper_2_78_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_78_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_78_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_78_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_78_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_78_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_79_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_79_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_79_chunk USING btree (building_id);


--
-- Name: _hyper_2_79_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_79_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_79_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_79_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_79_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_79_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_80_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_80_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_80_chunk USING btree (building_id);


--
-- Name: _hyper_2_80_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_80_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_80_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_80_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_80_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_80_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_81_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_81_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_81_chunk USING btree (building_id);


--
-- Name: _hyper_2_81_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_81_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_81_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_81_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_81_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_81_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_82_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_82_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_82_chunk USING btree (building_id);


--
-- Name: _hyper_2_82_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_82_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_82_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_82_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_82_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_82_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_83_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_83_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_83_chunk USING btree (building_id);


--
-- Name: _hyper_2_83_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_83_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_83_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_83_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_83_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_83_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_84_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_84_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_84_chunk USING btree (building_id);


--
-- Name: _hyper_2_84_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_84_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_84_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_84_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_84_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_84_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_85_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_85_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_85_chunk USING btree (building_id);


--
-- Name: _hyper_2_85_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_85_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_85_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_85_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_85_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_85_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_86_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_86_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_86_chunk USING btree (building_id);


--
-- Name: _hyper_2_86_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_86_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_86_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_86_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_86_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_86_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_87_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_87_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_87_chunk USING btree (building_id);


--
-- Name: _hyper_2_87_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_87_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_87_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_87_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_87_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_87_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_88_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_88_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_88_chunk USING btree (building_id);


--
-- Name: _hyper_2_88_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_88_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_88_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_88_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_88_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_88_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_89_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_89_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_89_chunk USING btree (building_id);


--
-- Name: _hyper_2_89_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_89_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_89_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_89_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_89_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_89_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_90_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_90_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_90_chunk USING btree (building_id);


--
-- Name: _hyper_2_90_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_90_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_90_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_90_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_90_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_90_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_91_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_91_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_91_chunk USING btree (building_id);


--
-- Name: _hyper_2_91_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_91_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_91_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_91_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_91_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_91_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_92_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_92_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_92_chunk USING btree (building_id);


--
-- Name: _hyper_2_92_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_92_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_92_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_92_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_92_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_92_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_93_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_93_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_93_chunk USING btree (building_id);


--
-- Name: _hyper_2_93_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_93_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_93_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_93_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_93_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_93_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_94_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_94_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_94_chunk USING btree (building_id);


--
-- Name: _hyper_2_94_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_94_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_94_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_94_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_94_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_94_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_95_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_95_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_95_chunk USING btree (building_id);


--
-- Name: _hyper_2_95_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_95_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_95_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_95_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_95_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_95_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_96_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_96_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_96_chunk USING btree (building_id);


--
-- Name: _hyper_2_96_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_96_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_96_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_96_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_96_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_96_chunk USING btree (organization_id, product, identifier, create_date);


--
-- Name: _hyper_2_97_chunk_product_tracker_building_id_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_97_chunk_product_tracker_building_id_idx ON _timescaledb_internal._hyper_2_97_chunk USING btree (building_id);


--
-- Name: _hyper_2_97_chunk_product_tracker_create_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_97_chunk_product_tracker_create_date_idx ON _timescaledb_internal._hyper_2_97_chunk USING btree (create_date DESC);


--
-- Name: _hyper_2_97_chunk_product_tracker_org_prod_id_date_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _hyper_2_97_chunk_product_tracker_org_prod_id_date_idx ON _timescaledb_internal._hyper_2_97_chunk USING btree (organization_id, product, identifier, create_date);


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
-- Name: auth_access_token_application_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_access_token_application_id_idx ON application.auth_access_token USING btree (application_id);


--
-- Name: auth_access_token_expired_at_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_access_token_expired_at_idx ON application.auth_access_token USING btree (expired_at);


--
-- Name: auth_access_token_user_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_access_token_user_id_idx ON application.auth_access_token USING btree (user_id);


--
-- Name: auth_code_application_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_code_application_id_idx ON application.auth_code USING btree (application_id);


--
-- Name: auth_code_expired_at_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_code_expired_at_idx ON application.auth_code USING btree (expired_at);


--
-- Name: auth_code_user_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_code_user_id_idx ON application.auth_code USING btree (user_id);


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
-- Name: auth_refresh_token_application_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_refresh_token_application_id_idx ON application.auth_refresh_token USING btree (application_id);


--
-- Name: auth_refresh_token_expired_at_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_refresh_token_expired_at_idx ON application.auth_refresh_token USING btree (expired_at);


--
-- Name: auth_refresh_token_user_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX auth_refresh_token_user_id_idx ON application.auth_refresh_token USING btree (user_id);


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
-- Name: product_tracker_mismatch_create_date_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX product_tracker_mismatch_create_date_idx ON application.product_tracker_mismatch USING btree (create_date DESC);


--
-- Name: product_tracker_mismatch_organization_id_idx; Type: INDEX; Schema: application; Owner: -
--

CREATE INDEX product_tracker_mismatch_organization_id_idx ON application.product_tracker_mismatch USING btree (organization_id);


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
-- Name: building_sample_building_id_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX building_sample_building_id_idx ON data.building_sample USING btree (building_id);


--
-- Name: cluster_sample_v2_cluster_id_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX cluster_sample_v2_cluster_id_idx ON data.cluster_sample USING btree (cluster_id);


--
-- Name: model_risk_static_neighborhood_id_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE INDEX model_risk_static_neighborhood_id_idx ON data.model_risk_static USING btree (neighborhood_id);


--
-- Name: model_risk_static_pkey; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX model_risk_static_pkey ON data.model_risk_static USING btree (building_id);


--
-- Name: statistics_postal_code_data_collected_postal_code_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_postal_code_data_collected_postal_code_idx ON data.statistics_postal_code_data_collected USING btree (postal_code);


--
-- Name: statistics_postal_code_foundation_risk_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_postal_code_foundation_risk_idx ON data.statistics_postal_code_foundation_risk USING btree (postal_code, foundation_risk);


--
-- Name: statistics_postal_code_foundation_type_idx; Type: INDEX; Schema: data; Owner: -
--

CREATE UNIQUE INDEX statistics_postal_code_foundation_type_idx ON data.statistics_postal_code_foundation_type USING btree (postal_code, foundation_type);


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
-- Name: country_external_id_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE UNIQUE INDEX country_external_id_idx ON geocoder.country USING btree (external_id);


--
-- Name: country_geom_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX country_geom_idx ON geocoder.country USING gist (geom);


--
-- Name: country_name_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX country_name_idx ON geocoder.country USING btree (name);


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
-- Name: postal_code_geom_idx; Type: INDEX; Schema: geocoder; Owner: -
--

CREATE INDEX postal_code_geom_idx ON geocoder.postal_code USING gist (geom);


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
-- Name: building_tiles_geom_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX building_tiles_geom_idx ON maplayer.building_tiles USING gist (geom);


--
-- Name: building_tiles_geom_simple_idx; Type: INDEX; Schema: maplayer; Owner: -
--

CREATE INDEX building_tiles_geom_simple_idx ON maplayer.building_tiles USING gist (geom_simple);


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
-- Name: _hyper_1_10_chunk 10_10_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_10_chunk
    ADD CONSTRAINT "10_10_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_11_chunk 11_11_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_11_chunk
    ADD CONSTRAINT "11_11_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_12_chunk 12_12_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_12_chunk
    ADD CONSTRAINT "12_12_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_131_chunk 131_291_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_131_chunk
    ADD CONSTRAINT "131_291_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_131_chunk 131_292_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_131_chunk
    ADD CONSTRAINT "131_292_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_132_chunk 132_293_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_132_chunk
    ADD CONSTRAINT "132_293_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_133_chunk 133_294_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_133_chunk
    ADD CONSTRAINT "133_294_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_133_chunk 133_295_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_133_chunk
    ADD CONSTRAINT "133_295_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_134_chunk 134_296_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_134_chunk
    ADD CONSTRAINT "134_296_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_135_chunk 135_297_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_135_chunk
    ADD CONSTRAINT "135_297_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_135_chunk 135_298_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_135_chunk
    ADD CONSTRAINT "135_298_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_136_chunk 136_299_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_136_chunk
    ADD CONSTRAINT "136_299_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_13_chunk 13_13_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_13_chunk
    ADD CONSTRAINT "13_13_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_14_chunk 14_14_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_14_chunk
    ADD CONSTRAINT "14_14_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_15_chunk 15_15_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_15_chunk
    ADD CONSTRAINT "15_15_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_16_chunk 16_16_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_16_chunk
    ADD CONSTRAINT "16_16_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_17_chunk 17_17_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_17_chunk
    ADD CONSTRAINT "17_17_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_18_chunk 18_18_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_18_chunk
    ADD CONSTRAINT "18_18_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_19_chunk 19_19_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_19_chunk
    ADD CONSTRAINT "19_19_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_1_chunk 1_1_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_1_chunk
    ADD CONSTRAINT "1_1_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_20_chunk 20_20_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_20_chunk
    ADD CONSTRAINT "20_20_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_21_chunk 21_21_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_21_chunk
    ADD CONSTRAINT "21_21_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_22_chunk 22_22_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_22_chunk
    ADD CONSTRAINT "22_22_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_23_chunk 23_23_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_23_chunk
    ADD CONSTRAINT "23_23_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_24_chunk 24_24_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_24_chunk
    ADD CONSTRAINT "24_24_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_25_chunk 25_25_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_25_chunk
    ADD CONSTRAINT "25_25_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_26_chunk 26_26_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_26_chunk
    ADD CONSTRAINT "26_26_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_27_chunk 27_27_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_27_chunk
    ADD CONSTRAINT "27_27_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_28_chunk 28_28_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_28_chunk
    ADD CONSTRAINT "28_28_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_29_chunk 29_29_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_29_chunk
    ADD CONSTRAINT "29_29_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_2_chunk 2_2_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_2_chunk
    ADD CONSTRAINT "2_2_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_30_chunk 30_30_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_30_chunk
    ADD CONSTRAINT "30_30_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_31_chunk 31_31_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_31_chunk
    ADD CONSTRAINT "31_31_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_32_chunk 32_32_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_32_chunk
    ADD CONSTRAINT "32_32_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_33_chunk 33_33_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_33_chunk
    ADD CONSTRAINT "33_33_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_34_chunk 34_34_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_34_chunk
    ADD CONSTRAINT "34_34_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_35_chunk 35_35_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_35_chunk
    ADD CONSTRAINT "35_35_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_36_chunk 36_36_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_36_chunk
    ADD CONSTRAINT "36_36_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_37_chunk 37_37_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_37_chunk
    ADD CONSTRAINT "37_37_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_38_chunk 38_38_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_38_chunk
    ADD CONSTRAINT "38_38_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_39_chunk 39_39_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_39_chunk
    ADD CONSTRAINT "39_39_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_3_chunk 3_3_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_3_chunk
    ADD CONSTRAINT "3_3_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_40_chunk 40_40_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_40_chunk
    ADD CONSTRAINT "40_40_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_41_chunk 41_41_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_41_chunk
    ADD CONSTRAINT "41_41_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_42_chunk 42_42_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_42_chunk
    ADD CONSTRAINT "42_42_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_43_chunk 43_43_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_43_chunk
    ADD CONSTRAINT "43_43_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_44_chunk 44_150_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_44_chunk
    ADD CONSTRAINT "44_150_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_44_chunk 44_203_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_44_chunk
    ADD CONSTRAINT "44_203_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_45_chunk 45_151_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_45_chunk
    ADD CONSTRAINT "45_151_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_45_chunk 45_204_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_45_chunk
    ADD CONSTRAINT "45_204_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_46_chunk 46_152_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_46_chunk
    ADD CONSTRAINT "46_152_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_46_chunk 46_205_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_46_chunk
    ADD CONSTRAINT "46_205_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_47_chunk 47_153_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_47_chunk
    ADD CONSTRAINT "47_153_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_47_chunk 47_206_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_47_chunk
    ADD CONSTRAINT "47_206_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_48_chunk 48_154_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_48_chunk
    ADD CONSTRAINT "48_154_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_48_chunk 48_207_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_48_chunk
    ADD CONSTRAINT "48_207_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_49_chunk 49_155_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_49_chunk
    ADD CONSTRAINT "49_155_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_49_chunk 49_208_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_49_chunk
    ADD CONSTRAINT "49_208_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_4_chunk 4_4_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_4_chunk
    ADD CONSTRAINT "4_4_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_50_chunk 50_156_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_50_chunk
    ADD CONSTRAINT "50_156_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_50_chunk 50_209_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_50_chunk
    ADD CONSTRAINT "50_209_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_51_chunk 51_157_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_51_chunk
    ADD CONSTRAINT "51_157_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_51_chunk 51_210_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_51_chunk
    ADD CONSTRAINT "51_210_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_52_chunk 52_158_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_52_chunk
    ADD CONSTRAINT "52_158_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_52_chunk 52_211_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_52_chunk
    ADD CONSTRAINT "52_211_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_53_chunk 53_159_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_53_chunk
    ADD CONSTRAINT "53_159_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_53_chunk 53_212_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_53_chunk
    ADD CONSTRAINT "53_212_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_54_chunk 54_160_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_54_chunk
    ADD CONSTRAINT "54_160_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_54_chunk 54_213_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_54_chunk
    ADD CONSTRAINT "54_213_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_55_chunk 55_161_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_55_chunk
    ADD CONSTRAINT "55_161_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_55_chunk 55_214_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_55_chunk
    ADD CONSTRAINT "55_214_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_56_chunk 56_162_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_56_chunk
    ADD CONSTRAINT "56_162_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_56_chunk 56_215_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_56_chunk
    ADD CONSTRAINT "56_215_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_57_chunk 57_163_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_57_chunk
    ADD CONSTRAINT "57_163_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_57_chunk 57_216_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_57_chunk
    ADD CONSTRAINT "57_216_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_58_chunk 58_164_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_58_chunk
    ADD CONSTRAINT "58_164_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_58_chunk 58_217_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_58_chunk
    ADD CONSTRAINT "58_217_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_59_chunk 59_165_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_59_chunk
    ADD CONSTRAINT "59_165_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_59_chunk 59_218_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_59_chunk
    ADD CONSTRAINT "59_218_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_5_chunk 5_5_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_5_chunk
    ADD CONSTRAINT "5_5_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_60_chunk 60_166_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_60_chunk
    ADD CONSTRAINT "60_166_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_60_chunk 60_219_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_60_chunk
    ADD CONSTRAINT "60_219_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_61_chunk 61_167_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_61_chunk
    ADD CONSTRAINT "61_167_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_61_chunk 61_220_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_61_chunk
    ADD CONSTRAINT "61_220_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_62_chunk 62_168_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_62_chunk
    ADD CONSTRAINT "62_168_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_62_chunk 62_221_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_62_chunk
    ADD CONSTRAINT "62_221_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_63_chunk 63_169_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_63_chunk
    ADD CONSTRAINT "63_169_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_63_chunk 63_222_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_63_chunk
    ADD CONSTRAINT "63_222_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_64_chunk 64_170_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_64_chunk
    ADD CONSTRAINT "64_170_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_64_chunk 64_223_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_64_chunk
    ADD CONSTRAINT "64_223_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_65_chunk 65_171_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_65_chunk
    ADD CONSTRAINT "65_171_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_65_chunk 65_224_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_65_chunk
    ADD CONSTRAINT "65_224_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_66_chunk 66_172_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_66_chunk
    ADD CONSTRAINT "66_172_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_66_chunk 66_225_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_66_chunk
    ADD CONSTRAINT "66_225_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_67_chunk 67_173_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_67_chunk
    ADD CONSTRAINT "67_173_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_67_chunk 67_226_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_67_chunk
    ADD CONSTRAINT "67_226_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_68_chunk 68_174_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_68_chunk
    ADD CONSTRAINT "68_174_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_68_chunk 68_227_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_68_chunk
    ADD CONSTRAINT "68_227_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_69_chunk 69_175_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_69_chunk
    ADD CONSTRAINT "69_175_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_69_chunk 69_228_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_69_chunk
    ADD CONSTRAINT "69_228_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_6_chunk 6_6_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_6_chunk
    ADD CONSTRAINT "6_6_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_70_chunk 70_176_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_70_chunk
    ADD CONSTRAINT "70_176_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_70_chunk 70_229_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_70_chunk
    ADD CONSTRAINT "70_229_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_71_chunk 71_177_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_71_chunk
    ADD CONSTRAINT "71_177_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_71_chunk 71_230_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_71_chunk
    ADD CONSTRAINT "71_230_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_72_chunk 72_178_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_72_chunk
    ADD CONSTRAINT "72_178_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_72_chunk 72_231_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_72_chunk
    ADD CONSTRAINT "72_231_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_73_chunk 73_179_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_73_chunk
    ADD CONSTRAINT "73_179_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_73_chunk 73_232_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_73_chunk
    ADD CONSTRAINT "73_232_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_74_chunk 74_180_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_74_chunk
    ADD CONSTRAINT "74_180_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_74_chunk 74_233_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_74_chunk
    ADD CONSTRAINT "74_233_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_75_chunk 75_181_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_75_chunk
    ADD CONSTRAINT "75_181_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_75_chunk 75_234_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_75_chunk
    ADD CONSTRAINT "75_234_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_76_chunk 76_182_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_76_chunk
    ADD CONSTRAINT "76_182_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_76_chunk 76_235_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_76_chunk
    ADD CONSTRAINT "76_235_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_77_chunk 77_183_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_77_chunk
    ADD CONSTRAINT "77_183_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_77_chunk 77_236_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_77_chunk
    ADD CONSTRAINT "77_236_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_78_chunk 78_184_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_78_chunk
    ADD CONSTRAINT "78_184_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_78_chunk 78_237_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_78_chunk
    ADD CONSTRAINT "78_237_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_79_chunk 79_185_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_79_chunk
    ADD CONSTRAINT "79_185_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_79_chunk 79_238_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_79_chunk
    ADD CONSTRAINT "79_238_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_7_chunk 7_7_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_7_chunk
    ADD CONSTRAINT "7_7_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_80_chunk 80_186_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_80_chunk
    ADD CONSTRAINT "80_186_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_80_chunk 80_239_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_80_chunk
    ADD CONSTRAINT "80_239_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_81_chunk 81_187_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_81_chunk
    ADD CONSTRAINT "81_187_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_81_chunk 81_240_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_81_chunk
    ADD CONSTRAINT "81_240_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_82_chunk 82_188_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_82_chunk
    ADD CONSTRAINT "82_188_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_82_chunk 82_241_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_82_chunk
    ADD CONSTRAINT "82_241_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_83_chunk 83_189_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_83_chunk
    ADD CONSTRAINT "83_189_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_83_chunk 83_242_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_83_chunk
    ADD CONSTRAINT "83_242_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_84_chunk 84_190_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_84_chunk
    ADD CONSTRAINT "84_190_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_84_chunk 84_243_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_84_chunk
    ADD CONSTRAINT "84_243_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_85_chunk 85_191_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_85_chunk
    ADD CONSTRAINT "85_191_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_85_chunk 85_244_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_85_chunk
    ADD CONSTRAINT "85_244_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_86_chunk 86_192_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_86_chunk
    ADD CONSTRAINT "86_192_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_86_chunk 86_245_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_86_chunk
    ADD CONSTRAINT "86_245_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_87_chunk 87_193_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_87_chunk
    ADD CONSTRAINT "87_193_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_87_chunk 87_246_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_87_chunk
    ADD CONSTRAINT "87_246_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_88_chunk 88_194_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_88_chunk
    ADD CONSTRAINT "88_194_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_88_chunk 88_247_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_88_chunk
    ADD CONSTRAINT "88_247_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_89_chunk 89_195_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_89_chunk
    ADD CONSTRAINT "89_195_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_89_chunk 89_248_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_89_chunk
    ADD CONSTRAINT "89_248_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_8_chunk 8_8_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_8_chunk
    ADD CONSTRAINT "8_8_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_90_chunk 90_196_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_90_chunk
    ADD CONSTRAINT "90_196_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_90_chunk 90_249_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_90_chunk
    ADD CONSTRAINT "90_249_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_91_chunk 91_197_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_91_chunk
    ADD CONSTRAINT "91_197_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_91_chunk 91_250_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_91_chunk
    ADD CONSTRAINT "91_250_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_92_chunk 92_198_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_92_chunk
    ADD CONSTRAINT "92_198_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_92_chunk 92_251_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_92_chunk
    ADD CONSTRAINT "92_251_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_93_chunk 93_199_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_93_chunk
    ADD CONSTRAINT "93_199_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_93_chunk 93_252_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_93_chunk
    ADD CONSTRAINT "93_252_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_94_chunk 94_200_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_94_chunk
    ADD CONSTRAINT "94_200_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_94_chunk 94_253_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_94_chunk
    ADD CONSTRAINT "94_253_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_95_chunk 95_201_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_95_chunk
    ADD CONSTRAINT "95_201_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_95_chunk 95_254_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_95_chunk
    ADD CONSTRAINT "95_254_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_96_chunk 96_202_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_96_chunk
    ADD CONSTRAINT "96_202_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_96_chunk 96_255_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_96_chunk
    ADD CONSTRAINT "96_255_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_2_97_chunk 97_256_product_tracker_building_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_97_chunk
    ADD CONSTRAINT "97_256_product_tracker_building_id_fkey" FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;


--
-- Name: _hyper_2_97_chunk 97_257_product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_2_97_chunk
    ADD CONSTRAINT "97_257_product_tracker_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_98_chunk 98_258_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_98_chunk
    ADD CONSTRAINT "98_258_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: _hyper_1_9_chunk 9_9_product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: -
--

ALTER TABLE ONLY _timescaledb_internal._hyper_1_9_chunk
    ADD CONSTRAINT "9_9_product_tracker_mismatch_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
-- Name: auth_access_token auth_access_token_application_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_access_token
    ADD CONSTRAINT auth_access_token_application_id_fkey FOREIGN KEY (application_id) REFERENCES application.application(application_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: auth_access_token auth_access_token_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_access_token
    ADD CONSTRAINT auth_access_token_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: auth_code auth_code_application_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_code
    ADD CONSTRAINT auth_code_application_id_fkey FOREIGN KEY (application_id) REFERENCES application.application(application_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: auth_code auth_code_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_code
    ADD CONSTRAINT auth_code_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: auth_key auth_key_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_key
    ADD CONSTRAINT auth_key_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: auth_refresh_token auth_refresh_token_application_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_refresh_token
    ADD CONSTRAINT auth_refresh_token_application_id_fkey FOREIGN KEY (application_id) REFERENCES application.application(application_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: auth_refresh_token auth_refresh_token_user_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.auth_refresh_token
    ADD CONSTRAINT auth_refresh_token_user_id_fkey FOREIGN KEY (user_id) REFERENCES application."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
-- Name: product_tracker_mismatch product_tracker_mismatch_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.product_tracker_mismatch
    ADD CONSTRAINT product_tracker_mismatch_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: product_tracker product_tracker_organization_id_fkey; Type: FK CONSTRAINT; Schema: application; Owner: -
--

ALTER TABLE ONLY application.product_tracker
    ADD CONSTRAINT product_tracker_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
-- Name: state state_country_id_fkey; Type: FK CONSTRAINT; Schema: geocoder; Owner: -
--

ALTER TABLE ONLY geocoder.state
    ADD CONSTRAINT state_country_id_fkey FOREIGN KEY (country_id) REFERENCES geocoder.country(id) ON UPDATE CASCADE ON DELETE CASCADE;


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

\unrestrict ZjD8I2nYbXGWRKPYx409fdZOGvf4BQzdbaz5tncwtqkG7JaKKb14HsxTISXRtUL

