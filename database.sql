--
-- PostgreSQL database dump
--

\restrict T0zH5tbJpbY8hCF77Obhl0aDRdAdFIiL3zungE4AnNUEcxAKzvwAbddo7uZl1aO

-- Dumped from database version 17.4
-- Dumped by pg_dump version 18.4

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
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: file_json(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.file_json(fid bigint) RETURNS json
    LANGUAGE sql STABLE
    AS $$
    SELECT json_build_object('uuid', f.uuid, 'name', f.original_name, 'type', f.content_type, 'size', f.size_bytes)
    FROM files f WHERE f.id = fid AND f.is_active
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: academic_years; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.academic_years (
    id bigint NOT NULL,
    name character varying(20) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    is_current boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT academic_years_check CHECK ((end_date > start_date))
);


--
-- Name: academic_years_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.academic_years ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.academic_years_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_config (
    key character varying(60) NOT NULL,
    value jsonb NOT NULL,
    description text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: bulk_upload_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bulk_upload_jobs (
    id bigint NOT NULL,
    upload_type character varying(20) NOT NULL,
    file_name text NOT NULL,
    file_url text,
    total_rows integer DEFAULT 0 NOT NULL,
    success_rows integer DEFAULT 0 NOT NULL,
    failed_rows integer DEFAULT 0 NOT NULL,
    errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    dry_run boolean DEFAULT false NOT NULL,
    CONSTRAINT bulk_upload_jobs_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying])::text[]))),
    CONSTRAINT bulk_upload_jobs_upload_type_check CHECK (((upload_type)::text = ANY ((ARRAY['students'::character varying, 'staff'::character varying, 'marks'::character varying, 'skills'::character varying])::text[])))
);


--
-- Name: bulk_upload_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.bulk_upload_jobs ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.bulk_upload_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: career_feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.career_feedback (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    career_id bigint NOT NULL,
    rating smallint NOT NULL,
    is_useful boolean DEFAULT true NOT NULL,
    comment text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT career_feedback_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


--
-- Name: career_feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.career_feedback ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.career_feedback_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: career_matches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.career_matches (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    career_id bigint NOT NULL,
    rank smallint NOT NULL,
    skill_score numeric(5,2) DEFAULT 0 NOT NULL,
    academic_score numeric(5,2) DEFAULT 0 NOT NULL,
    final_score numeric(5,2) DEFAULT 0 NOT NULL,
    readiness character varying(10) DEFAULT 'explore'::character varying NOT NULL,
    gaps jsonb DEFAULT '[]'::jsonb NOT NULL,
    strengths jsonb DEFAULT '[]'::jsonb NOT NULL,
    explanation text,
    computed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT career_matches_readiness_check CHECK (((readiness)::text = ANY ((ARRAY['ready'::character varying, 'close'::character varying, 'explore'::character varying])::text[])))
);


--
-- Name: career_matches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.career_matches ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.career_matches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: career_skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.career_skills (
    id bigint NOT NULL,
    career_id bigint NOT NULL,
    skill_id bigint NOT NULL,
    required_level smallint DEFAULT 3 NOT NULL,
    weight numeric(3,2) DEFAULT 1 NOT NULL,
    is_core boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT career_skills_required_level_check CHECK (((required_level >= 1) AND (required_level <= 5))),
    CONSTRAINT career_skills_weight_check CHECK ((weight > (0)::numeric))
);


--
-- Name: career_skills_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.career_skills ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.career_skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: careers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.careers (
    id bigint NOT NULL,
    code character varying(30) NOT NULL,
    name character varying(150) NOT NULL,
    domain character varying(80),
    description text,
    avg_package numeric(6,2),
    min_cgpa numeric(4,2) DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: careers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.careers ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.careers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: classes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.classes (
    id bigint NOT NULL,
    department_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    year_level_id bigint NOT NULL,
    section character varying(5) DEFAULT 'A'::character varying NOT NULL,
    class_incharge_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    current_semester_id bigint
);


--
-- Name: classes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.classes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.classes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id bigint NOT NULL,
    name public.citext NOT NULL,
    industry character varying(100),
    website text,
    location character varying(150),
    contact_person character varying(150),
    contact_email public.citext,
    contact_mobile character varying(15),
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    logo_file_id bigint
);


--
-- Name: companies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.companies ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.companies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: company_job_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_job_roles (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    title character varying(150) NOT NULL,
    description text,
    package_lpa numeric(6,2) NOT NULL,
    drive_date date,
    last_apply_date date,
    min_cgpa numeric(4,2) DEFAULT 0 NOT NULL,
    max_backlogs integer DEFAULT 0 NOT NULL,
    eligible_batch character varying(20),
    openings integer,
    status character varying(20) DEFAULT 'upcoming'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    jd_file_id bigint,
    CONSTRAINT company_job_roles_status_check CHECK (((status)::text = ANY ((ARRAY['upcoming'::character varying, 'open'::character varying, 'closed'::character varying, 'completed'::character varying])::text[])))
);


--
-- Name: company_job_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.company_job_roles ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.company_job_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.courses (
    id bigint NOT NULL,
    skill_id bigint NOT NULL,
    title character varying(200) NOT NULL,
    provider character varying(100),
    url text,
    level smallint DEFAULT 1 NOT NULL,
    duration_hours smallint,
    is_certification boolean DEFAULT false NOT NULL,
    is_free boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT courses_level_check CHECK (((level >= 1) AND (level <= 5)))
);


--
-- Name: courses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.courses ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.courses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: curriculum; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.curriculum (
    id bigint NOT NULL,
    department_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    subject_id bigint NOT NULL,
    regulation character varying(20) DEFAULT 'R2021'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: curriculum_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.curriculum ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.curriculum_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id bigint NOT NULL,
    name character varying(150) NOT NULL,
    code character varying(20) NOT NULL,
    hod_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: departments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.departments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.departments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: device_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_tokens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token text NOT NULL,
    platform character varying(10) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT device_tokens_platform_check CHECK (((platform)::text = ANY ((ARRAY['android'::character varying, 'ios'::character varying, 'web'::character varying])::text[])))
);


--
-- Name: device_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.device_tokens ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.device_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: exam_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_types (
    id bigint NOT NULL,
    name character varying(60) NOT NULL,
    code character varying(20) NOT NULL,
    max_marks numeric(6,2) DEFAULT 100 NOT NULL,
    is_final boolean DEFAULT false NOT NULL,
    sort_order smallint DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    pass_percent numeric(5,2) DEFAULT 50 NOT NULL,
    CONSTRAINT exam_types_pass_percent_check CHECK (((pass_percent >= (0)::numeric) AND (pass_percent <= (100)::numeric)))
);


--
-- Name: exam_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.exam_types ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.exam_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.files (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    category character varying(30) NOT NULL,
    original_name character varying(255) NOT NULL,
    content_type character varying(100) NOT NULL,
    size_bytes bigint NOT NULL,
    sha256 character(64) NOT NULL,
    storage_key text NOT NULL,
    ref_type character varying(40),
    ref_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT files_category_check CHECK (((category)::text = ANY ((ARRAY['profile_photo'::character varying, 'resume'::character varying, 'certificate'::character varying, 'offer_letter'::character varying, 'student_document'::character varying, 'company_logo'::character varying, 'job_description'::character varying, 'notification_attachment'::character varying])::text[]))),
    CONSTRAINT files_size_bytes_check CHECK ((size_bytes > 0))
);


--
-- Name: files_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.files ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: grade_scales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grade_scales (
    id bigint NOT NULL,
    grade character varying(5) NOT NULL,
    min_percent numeric(5,2) NOT NULL,
    grade_point numeric(4,2) NOT NULL,
    is_pass boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT grade_scales_grade_point_check CHECK ((grade_point >= (0)::numeric)),
    CONSTRAINT grade_scales_min_percent_check CHECK (((min_percent >= (0)::numeric) AND (min_percent <= (100)::numeric)))
);


--
-- Name: grade_scales_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.grade_scales ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.grade_scales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: job_role_departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_role_departments (
    id bigint NOT NULL,
    job_role_id bigint NOT NULL,
    department_id bigint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: job_role_departments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.job_role_departments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.job_role_departments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: job_role_skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_role_skills (
    id bigint NOT NULL,
    job_role_id bigint NOT NULL,
    skill_id bigint NOT NULL,
    required_level smallint DEFAULT 3 NOT NULL,
    is_mandatory boolean DEFAULT false NOT NULL,
    weight numeric(4,2) DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT job_role_skills_required_level_check CHECK (((required_level >= 1) AND (required_level <= 5))),
    CONSTRAINT job_role_skills_weight_check CHECK ((weight > (0)::numeric))
);


--
-- Name: job_role_skills_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.job_role_skills ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.job_role_skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notification_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_recipients (
    id bigint NOT NULL,
    notification_id bigint NOT NULL,
    user_id bigint NOT NULL,
    is_read boolean DEFAULT false NOT NULL,
    read_at timestamp with time zone,
    push_status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT notification_recipients_push_status_check CHECK (((push_status)::text = ANY ((ARRAY['pending'::character varying, 'sent'::character varying, 'failed'::character varying, 'skipped'::character varying])::text[])))
);


--
-- Name: notification_recipients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notification_recipients ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.notification_recipients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    title character varying(200) NOT NULL,
    body text NOT NULL,
    type character varying(20) DEFAULT 'general'::character varying NOT NULL,
    target_type character varying(20) NOT NULL,
    target_id bigint,
    reference_type character varying(50),
    reference_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    attachment_file_id bigint,
    CONSTRAINT notifications_target_type_check CHECK (((target_type)::text = ANY ((ARRAY['all'::character varying, 'role'::character varying, 'department'::character varying, 'class'::character varying, 'user'::character varying])::text[]))),
    CONSTRAINT notifications_type_check CHECK (((type)::text = ANY ((ARRAY['general'::character varying, 'placement'::character varying, 'marks'::character varying, 'skill'::character varying, 'system'::character varying])::text[])))
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notifications ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    id bigint NOT NULL,
    module character varying(50) NOT NULL,
    action character varying(50) NOT NULL,
    slug character varying(120) NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.permissions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: placement_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.placement_applications (
    id bigint NOT NULL,
    job_role_id bigint NOT NULL,
    student_id bigint NOT NULL,
    match_score numeric(5,2),
    status character varying(20) DEFAULT 'shortlisted'::character varying NOT NULL,
    remarks text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT placement_applications_status_check CHECK (((status)::text = ANY ((ARRAY['shortlisted'::character varying, 'applied'::character varying, 'in_process'::character varying, 'selected'::character varying, 'rejected'::character varying, 'withdrawn'::character varying])::text[])))
);


--
-- Name: placement_applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.placement_applications ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.placement_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: placement_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.placement_records (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    company_id bigint NOT NULL,
    job_role_id bigint NOT NULL,
    application_id bigint,
    package_lpa numeric(6,2) NOT NULL,
    offer_date date,
    joining_date date,
    offer_letter_url text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    offer_letter_file_id bigint
);


--
-- Name: placement_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.placement_records ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.placement_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: promotion_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promotion_runs (
    id bigint NOT NULL,
    from_year_id bigint NOT NULL,
    to_year_id bigint NOT NULL,
    promoted_count integer DEFAULT 0 NOT NULL,
    detained_count integer DEFAULT 0 NOT NULL,
    passed_out_count integer DEFAULT 0 NOT NULL,
    classes_created integer DEFAULT 0 NOT NULL,
    summary jsonb DEFAULT '[]'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT promotion_runs_check CHECK ((from_year_id <> to_year_id))
);


--
-- Name: promotion_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.promotion_runs ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.promotion_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    id bigint NOT NULL,
    role_id bigint NOT NULL,
    permission_id bigint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: role_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.role_permissions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.role_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    slug character varying(100) NOT NULL,
    description text,
    is_system boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.roles ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying(255) NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: semesters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semesters (
    id bigint NOT NULL,
    name character varying(30) NOT NULL,
    sem_no smallint NOT NULL,
    year_level_id bigint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: semesters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.semesters ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.semesters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: skill_match_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill_match_results (
    id bigint NOT NULL,
    job_role_id bigint NOT NULL,
    student_id bigint NOT NULL,
    skill_score numeric(5,2) DEFAULT 0 NOT NULL,
    academic_score numeric(5,2) DEFAULT 0 NOT NULL,
    final_score numeric(5,2) DEFAULT 0 NOT NULL,
    matched_skills jsonb DEFAULT '[]'::jsonb NOT NULL,
    missing_skills jsonb DEFAULT '[]'::jsonb NOT NULL,
    is_eligible boolean DEFAULT false NOT NULL,
    ineligible_reason text,
    computed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: skill_match_results_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.skill_match_results ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.skill_match_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: skill_scores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill_scores (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    skill_id bigint NOT NULL,
    source character varying(10) NOT NULL,
    score numeric(5,2) NOT NULL,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    computed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT skill_scores_score_check CHECK (((score >= (0)::numeric) AND (score <= (100)::numeric))),
    CONSTRAINT skill_scores_source_check CHECK (((source)::text = ANY ((ARRAY['declared'::character varying, 'test'::character varying, 'cert'::character varying, 'academic'::character varying, 'blended'::character varying])::text[])))
);


--
-- Name: skill_scores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.skill_scores ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.skill_scores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skills (
    id bigint NOT NULL,
    name public.citext NOT NULL,
    category character varying(30) DEFAULT 'technical'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT skills_category_check CHECK (((category)::text = ANY ((ARRAY['programming'::character varying, 'framework'::character varying, 'database'::character varying, 'tool'::character varying, 'technical'::character varying, 'soft_skill'::character varying, 'domain'::character varying])::text[])))
);


--
-- Name: skills_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.skills ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: staff_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_assignments (
    id bigint NOT NULL,
    staff_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    department_id bigint NOT NULL,
    class_id bigint,
    subject_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: staff_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.staff_assignments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.staff_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: staff_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_profiles (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    employee_code character varying(50) NOT NULL,
    designation character varying(100),
    qualification character varying(200),
    joined_on date,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: staff_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.staff_profiles ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.staff_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: student_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_documents (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    doc_type character varying(30) NOT NULL,
    title character varying(150) NOT NULL,
    file_id bigint NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    remarks text,
    verified_by bigint,
    verified_at timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT student_documents_doc_type_check CHECK (((doc_type)::text = ANY ((ARRAY['id_proof'::character varying, 'photo_id'::character varying, 'marksheet_10'::character varying, 'marksheet_12'::character varying, 'diploma'::character varying, 'transfer_certificate'::character varying, 'community_certificate'::character varying, 'income_certificate'::character varying, 'course_certificate'::character varying, 'internship_certificate'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT student_documents_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'verified'::character varying, 'rejected'::character varying])::text[])))
);


--
-- Name: student_documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.student_documents ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.student_documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: student_enrollments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_enrollments (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    class_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    status character varying(20) DEFAULT 'studying'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT student_enrollments_status_check CHECK (((status)::text = ANY ((ARRAY['studying'::character varying, 'promoted'::character varying, 'detained'::character varying, 'passed_out'::character varying, 'discontinued'::character varying])::text[])))
);


--
-- Name: student_enrollments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.student_enrollments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.student_enrollments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: student_marks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_marks (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    academic_year_id bigint NOT NULL,
    semester_id bigint NOT NULL,
    subject_id bigint NOT NULL,
    exam_type_id bigint NOT NULL,
    attempt_no smallint DEFAULT 1 NOT NULL,
    marks_obtained numeric(6,2),
    max_marks numeric(6,2) NOT NULL,
    grade character varying(5),
    result character varying(10),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    grade_point numeric(4,2),
    class_id bigint,
    CONSTRAINT student_marks_check CHECK (((marks_obtained IS NULL) OR ((marks_obtained >= (0)::numeric) AND (marks_obtained <= max_marks)))),
    CONSTRAINT student_marks_result_check CHECK (((result)::text = ANY ((ARRAY['pass'::character varying, 'fail'::character varying, 'absent'::character varying, 'withheld'::character varying])::text[])))
);


--
-- Name: student_marks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.student_marks ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.student_marks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: student_parents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_parents (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    parent_id bigint NOT NULL,
    relation character varying(20) DEFAULT 'guardian'::character varying NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT student_parents_check CHECK ((student_id <> parent_id)),
    CONSTRAINT student_parents_relation_check CHECK (((relation)::text = ANY ((ARRAY['father'::character varying, 'mother'::character varying, 'guardian'::character varying])::text[])))
);


--
-- Name: student_parents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.student_parents ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.student_parents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: student_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_profiles (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    register_no character varying(50) NOT NULL,
    admission_year smallint NOT NULL,
    batch character varying(20) NOT NULL,
    current_class_id bigint,
    cgpa numeric(4,2) DEFAULT 0 NOT NULL,
    backlog_count integer DEFAULT 0 NOT NULL,
    blood_group character varying(5),
    address text,
    resume_url text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    lifecycle_status character varying(20) DEFAULT 'studying'::character varying NOT NULL,
    passed_out_year smallint,
    status_remarks text,
    resume_file_id bigint,
    CONSTRAINT student_profiles_lifecycle_status_check CHECK (((lifecycle_status)::text = ANY ((ARRAY['studying'::character varying, 'passed_out'::character varying, 'discontinued'::character varying])::text[])))
);


--
-- Name: student_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.student_profiles ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.student_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: student_skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_skills (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    skill_id bigint NOT NULL,
    proficiency smallint NOT NULL,
    source character varying(20) DEFAULT 'assessment'::character varying NOT NULL,
    certificate_url text,
    remarks text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    certificate_file_id bigint,
    certificate_verified boolean DEFAULT false NOT NULL,
    certificate_verified_by bigint,
    certificate_verified_at timestamp with time zone,
    CONSTRAINT student_skills_proficiency_check CHECK (((proficiency >= 1) AND (proficiency <= 5))),
    CONSTRAINT student_skills_source_check CHECK (((source)::text = ANY ((ARRAY['assessment'::character varying, 'certification'::character varying, 'project'::character varying, 'internship'::character varying, 'course'::character varying])::text[])))
);


--
-- Name: student_skills_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.student_skills ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.student_skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subject_skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subject_skills (
    id bigint NOT NULL,
    subject_id bigint NOT NULL,
    skill_id bigint NOT NULL,
    weight numeric(3,2) DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT subject_skills_weight_check CHECK ((weight > (0)::numeric))
);


--
-- Name: subject_skills_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.subject_skills ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.subject_skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subjects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subjects (
    id bigint NOT NULL,
    code character varying(30) NOT NULL,
    name character varying(200) NOT NULL,
    credits numeric(3,1) DEFAULT 0 NOT NULL,
    subject_type character varying(20) DEFAULT 'theory'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT subjects_subject_type_check CHECK (((subject_type)::text = ANY ((ARRAY['theory'::character varying, 'lab'::character varying, 'elective'::character varying, 'project'::character varying])::text[])))
);


--
-- Name: subjects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.subjects ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.subjects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_otps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_otps (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    mobile character varying(15) NOT NULL,
    otp_hash text NOT NULL,
    purpose character varying(30) NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    consumed_at timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT user_otps_purpose_check CHECK (((purpose)::text = ANY ((ARRAY['login'::character varying, 'reset_password'::character varying])::text[])))
);


--
-- Name: user_otps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.user_otps ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.user_otps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    role_id bigint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: user_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.user_roles ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.user_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    refresh_token_hash text NOT NULL,
    device_info text,
    ip_address character varying(64),
    login_method character varying(20) DEFAULT 'password'::character varying NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    CONSTRAINT user_sessions_login_method_check CHECK (((login_method)::text = ANY ((ARRAY['password'::character varying, 'otp'::character varying])::text[])))
);


--
-- Name: user_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.user_sessions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.user_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    reference_number character varying(50),
    name character varying(150) NOT NULL,
    mobile character varying(15),
    email public.citext,
    username public.citext NOT NULL,
    password_hash text,
    department_id bigint,
    profile_photo text,
    gender character varying(10),
    dob date,
    last_login_at timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint,
    photo_file_id bigint,
    CONSTRAINT users_gender_check CHECK (((gender)::text = ANY ((ARRAY['male'::character varying, 'female'::character varying, 'other'::character varying])::text[])))
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.users ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: year_levels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.year_levels (
    id bigint NOT NULL,
    name character varying(30) NOT NULL,
    level_no smallint NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: year_levels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.year_levels ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.year_levels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Data for Name: academic_years; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.academic_years (id, name, start_date, end_date, is_current, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	2025-26	2025-06-01	2026-05-31	f	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
2	2026-27	2026-06-01	2027-05-31	t	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
3	2027-28	2027-06-01	2028-05-31	f	t	2026-09-21 15:00:10.800791+05:30	1	2026-09-21 15:00:10.800791+05:30	1
\.


--
-- Data for Name: app_config; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_config (key, value, description, updated_at, updated_by) FROM stdin;
skill_score_weights	{"cert": 0.25, "test": 0.45, "academic": 0.20, "declared": 0.10}	How much each source counts towards a blended skill score. A source with no data is dropped and the rest are renormalised.	2026-10-03 15:19:29.317019+05:30	\N
match_weights	{"skill": 0.70, "academic": 0.30}	Split between skill match and academic record in a job-role or career match score.	2026-10-03 15:19:29.317019+05:30	\N
\.


--
-- Data for Name: bulk_upload_jobs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.bulk_upload_jobs (id, upload_type, file_name, file_url, total_rows, success_rows, failed_rows, errors, status, is_active, created_at, created_by, updated_at, updated_by, dry_run) FROM stdin;
1	students	demo_students.xlsx	\N	12	12	0	[]	completed	t	2026-09-21 13:49:54.297197+05:30	1	2026-09-21 13:49:54.339248+05:30	1	f
2	marks	ia1.xlsx	\N	4	4	0	[]	completed	t	2026-09-21 16:02:10.16709+05:30	4	2026-09-21 16:02:10.171263+05:30	4	t
3	skills	student_skills_template.xlsx	\N	2	2	0	[]	completed	t	2026-09-22 10:10:08.053804+05:30	2	2026-09-22 10:10:08.136332+05:30	2	t
\.


--
-- Data for Name: career_feedback; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.career_feedback (id, student_id, career_id, rating, is_useful, comment, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
\.


--
-- Data for Name: career_matches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.career_matches (id, student_id, career_id, rank, skill_score, academic_score, final_score, readiness, gaps, strengths, explanation, computed_at, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	19	3	1	0.00	0.00	0.00	explore	[{"gap": 80, "name": "Java", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 2, "url": "https://nptel.ac.in", "level": 3, "title": "Programming in Java", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "programming", "skill_id": 3, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "SQL", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": true, "category": "database", "skill_id": 7, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Spring Boot", "level": 0, "score": 0, "weight": 1.5, "is_core": false, "category": "framework", "skill_id": 11, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Git", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 12, "url": "https://roadmap.sh", "level": 2, "title": "Git and GitHub Basics", "is_free": true, "provider": "roadmap.sh", "duration_hours": 8}], "is_core": false, "category": "tool", "skill_id": 17, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "Docker", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 13, "url": "https://roadmap.sh", "level": 3, "title": "Docker Roadmap", "is_free": true, "provider": "roadmap.sh", "duration_hours": 15}], "is_core": false, "category": "tool", "skill_id": 18, "required_level": 2, "required_score": 40}]	[]	Backend Developer is a stretch right now at a 0% skill match; the biggest gap is Java, which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
2	19	12	2	0.00	0.00	0.00	explore	[{"gap": 80, "name": "Communication", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 16, "url": null, "level": 2, "title": "Soft Skills and Interview Preparation", "is_free": true, "provider": "In-house", "duration_hours": 15}], "is_core": true, "category": "soft_skill", "skill_id": 23, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "Aptitude", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 15, "url": null, "level": 2, "title": "Quantitative Aptitude Practice", "is_free": true, "provider": "In-house", "duration_hours": 20}], "is_core": true, "category": "soft_skill", "skill_id": 22, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "SQL", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Teamwork", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 25, "required_level": 3, "required_score": 60}]	[]	Business Analyst is a stretch right now at a 0% skill match; the biggest gap is Communication, which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.50 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
3	19	6	3	0.00	0.00	0.00	explore	[{"gap": 80, "name": "Cloud (AWS/Azure)", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 11, "url": "https://nptel.ac.in", "level": 3, "title": "Cloud Computing", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "tool", "skill_id": 16, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "Docker", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 13, "url": "https://roadmap.sh", "level": 3, "title": "Docker Roadmap", "is_free": true, "provider": "roadmap.sh", "duration_hours": 15}], "is_core": true, "category": "tool", "skill_id": 18, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Git", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 12, "url": "https://roadmap.sh", "level": 2, "title": "Git and GitHub Basics", "is_free": true, "provider": "roadmap.sh", "duration_hours": 8}], "is_core": false, "category": "tool", "skill_id": 17, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "Python", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 3, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Scientific Computing with Python", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": false, "category": "programming", "skill_id": 4, "required_level": 2, "required_score": 40}]	[]	Cloud / DevOps Engineer is a stretch right now at a 0% skill match; the biggest gap is Cloud (AWS/Azure), which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
4	19	4	4	0.00	0.00	0.00	explore	[{"gap": 80, "name": "SQL", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": true, "category": "database", "skill_id": 7, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Python", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 3, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Scientific Computing with Python", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": true, "category": "programming", "skill_id": 4, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Communication", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 16, "url": null, "level": 2, "title": "Soft Skills and Interview Preparation", "is_free": true, "provider": "In-house", "duration_hours": 15}], "is_core": false, "category": "soft_skill", "skill_id": 23, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 24, "required_level": 3, "required_score": 60}]	[]	Data Analyst is a stretch right now at a 0% skill match; the biggest gap is SQL, which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
5	19	10	5	0.00	0.00	0.00	explore	[{"gap": 80, "name": "SQL", "level": 0, "score": 0, "weight": 2.5, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": true, "category": "database", "skill_id": 7, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "MongoDB", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "database", "skill_id": 8, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "Docker", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 13, "url": "https://roadmap.sh", "level": 3, "title": "Docker Roadmap", "is_free": true, "provider": "roadmap.sh", "duration_hours": 15}], "is_core": false, "category": "tool", "skill_id": 18, "required_level": 2, "required_score": 40}]	[]	Database Administrator is a stretch right now at a 0% skill match; the biggest gap is SQL, which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
6	19	8	6	0.00	0.00	0.00	explore	[{"gap": 80, "name": "AutoCAD", "level": 0, "score": 0, "weight": 2, "is_core": true, "category": "tool", "skill_id": 21, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Communication", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 16, "url": null, "level": 2, "title": "Soft Skills and Interview Preparation", "is_free": true, "provider": "In-house", "duration_hours": 15}], "is_core": false, "category": "soft_skill", "skill_id": 23, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Teamwork", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 25, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "MATLAB", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "tool", "skill_id": 20, "required_level": 2, "required_score": 40}]	[]	Design Engineer is a stretch right now at a 0% skill match; the biggest gap is AutoCAD, which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
7	19	7	7	0.00	0.00	0.00	explore	[{"gap": 80, "name": "Embedded C", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 14, "url": "https://nptel.ac.in", "level": 3, "title": "Embedded Systems Design", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "programming", "skill_id": 19, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "C", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 1, "url": "https://nptel.ac.in", "level": 2, "title": "Problem Solving through Programming in C", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "programming", "skill_id": 1, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 24, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "MATLAB", "level": 0, "score": 0, "weight": 0.5, "is_core": false, "category": "tool", "skill_id": 20, "required_level": 2, "required_score": 40}]	[]	Embedded Systems Engineer is a stretch right now at a 0% skill match; the biggest gap is Embedded C, which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
8	19	2	8	0.00	0.00	0.00	explore	[{"gap": 80, "name": "JavaScript", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 4, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "JavaScript Algorithms and Data Structures", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 35}], "is_core": true, "category": "programming", "skill_id": 5, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "React", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 6, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Front End Development Libraries", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": true, "category": "framework", "skill_id": 9, "required_level": 3, "required_score": 60}, {"gap": 80, "name": "HTML/CSS", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 8, "url": "https://www.freecodecamp.org/learn", "level": 2, "title": "Responsive Web Design", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 25}], "is_core": false, "category": "technical", "skill_id": 13, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Node.js", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 7, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Back End Development and APIs", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": false, "category": "framework", "skill_id": 10, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "SQL", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Git", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 12, "url": "https://roadmap.sh", "level": 2, "title": "Git and GitHub Basics", "is_free": true, "provider": "roadmap.sh", "duration_hours": 8}], "is_core": false, "category": "tool", "skill_id": 17, "required_level": 3, "required_score": 60}]	[]	Full Stack Developer is a stretch right now at a 0% skill match; the biggest gap is JavaScript, which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
9	19	5	9	0.00	0.00	0.00	explore	[{"gap": 80, "name": "Machine Learning", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 10, "url": "https://nptel.ac.in", "level": 4, "title": "Introduction to Machine Learning", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "technical", "skill_id": 15, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "Python", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 3, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Scientific Computing with Python", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": true, "category": "programming", "skill_id": 4, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Data Structures & Algorithms", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 9, "url": "https://nptel.ac.in", "level": 3, "title": "Data Structures and Algorithms", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": false, "category": "technical", "skill_id": 14, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "SQL", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}]	[]	Machine Learning Engineer is a stretch right now at a 0% skill match; the biggest gap is Machine Learning, which is not recorded yet (needs level 4); CGPA 0.00 is below the 7.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
10	19	1	10	0.00	0.00	0.00	explore	[{"gap": 80, "name": "Data Structures & Algorithms", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 9, "url": "https://nptel.ac.in", "level": 3, "title": "Data Structures and Algorithms", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "technical", "skill_id": 14, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1.5, "is_core": true, "category": "soft_skill", "skill_id": 24, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Python", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 3, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Scientific Computing with Python", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": false, "category": "programming", "skill_id": 4, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "SQL", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Git", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 12, "url": "https://roadmap.sh", "level": 2, "title": "Git and GitHub Basics", "is_free": true, "provider": "roadmap.sh", "duration_hours": 8}], "is_core": false, "category": "tool", "skill_id": 17, "required_level": 3, "required_score": 60}]	[]	Software Development Engineer is a stretch right now at a 0% skill match; the biggest gap is Data Structures & Algorithms, which is not recorded yet (needs level 4); CGPA 0.00 is below the 6.50 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
16	6	3	4	52.08	96.00	65.26	close	[{"gap": 20, "name": "SQL", "level": 3, "score": 60, "weight": 1.5, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": true, "category": "database", "skill_id": 7, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Spring Boot", "level": 0, "score": 0, "weight": 1.5, "is_core": false, "category": "framework", "skill_id": 11, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Git", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 12, "url": "https://roadmap.sh", "level": 2, "title": "Git and GitHub Basics", "is_free": true, "provider": "roadmap.sh", "duration_hours": 8}], "is_core": false, "category": "tool", "skill_id": 17, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "Docker", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 13, "url": "https://roadmap.sh", "level": 3, "title": "Docker Roadmap", "is_free": true, "provider": "roadmap.sh", "duration_hours": 15}], "is_core": false, "category": "tool", "skill_id": 18, "required_level": 2, "required_score": 40}]	[{"gap": 0, "name": "Java", "level": 4, "score": 80, "weight": 2, "is_core": true, "category": "programming", "skill_id": 3, "required_level": 4, "required_score": 80}]	You are close to Backend Developer at a 52% skill match; your strongest fit here is Java; the biggest gap is SQL at level 3 of the 4 needed.	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
11	19	11	11	0.00	0.00	0.00	explore	[{"gap": 80, "name": "Communication", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 16, "url": null, "level": 2, "title": "Soft Skills and Interview Preparation", "is_free": true, "provider": "In-house", "duration_hours": 15}], "is_core": true, "category": "soft_skill", "skill_id": 23, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1.5, "is_core": true, "category": "soft_skill", "skill_id": 24, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Aptitude", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 15, "url": null, "level": 2, "title": "Quantitative Aptitude Practice", "is_free": true, "provider": "In-house", "duration_hours": 20}], "is_core": false, "category": "soft_skill", "skill_id": 22, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "SQL", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": false, "category": "database", "skill_id": 7, "required_level": 2, "required_score": 40}]	[]	Technical Support Engineer is a stretch right now at a 0% skill match; the biggest gap is Communication, which is not recorded yet (needs level 4); CGPA 0.00 is below the 5.50 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
12	19	9	12	0.00	0.00	0.00	explore	[{"gap": 60, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1.5, "is_core": true, "category": "soft_skill", "skill_id": 24, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Communication", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 16, "url": null, "level": 2, "title": "Soft Skills and Interview Preparation", "is_free": true, "provider": "In-house", "duration_hours": 15}], "is_core": false, "category": "soft_skill", "skill_id": 23, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Java", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 2, "url": "https://nptel.ac.in", "level": 3, "title": "Programming in Java", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": false, "category": "programming", "skill_id": 3, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "SQL", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}]	[]	Testing / QA Engineer is a stretch right now at a 0% skill match; the biggest gap is Problem Solving, which is not recorded yet (needs level 3); CGPA 0.00 is below the 6.00 usually expected.	2026-10-03 15:20:59.450151+05:30	t	2026-10-03 15:20:59.452801+05:30	1	2026-10-03 15:20:59.452801+05:30	1
13	6	12	1	81.82	96.00	86.07	ready	[{"gap": 60, "name": "Teamwork", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 25, "required_level": 3, "required_score": 60}]	[{"gap": 0, "name": "Communication", "level": 4, "score": 80, "weight": 2, "is_core": true, "category": "soft_skill", "skill_id": 23, "required_level": 4, "required_score": 80}, {"gap": 0, "name": "Aptitude", "level": 4, "score": 80, "weight": 1.5, "is_core": true, "category": "soft_skill", "skill_id": 22, "required_level": 4, "required_score": 80}, {"gap": 0, "name": "SQL", "level": 3, "score": 60, "weight": 1, "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}]	You meet every core requirement for Business Analyst; your strongest fit here is Communication and Aptitude; the biggest gap is Teamwork, which is not recorded yet (needs level 3).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
14	6	11	2	70.00	96.00	77.80	close	[{"gap": 60, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1.5, "is_core": true, "category": "soft_skill", "skill_id": 24, "required_level": 3, "required_score": 60}]	[{"gap": 0, "name": "Communication", "level": 4, "score": 80, "weight": 2, "is_core": true, "category": "soft_skill", "skill_id": 23, "required_level": 4, "required_score": 80}, {"gap": 0, "name": "Aptitude", "level": 4, "score": 80, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 22, "required_level": 3, "required_score": 60}, {"gap": 0, "name": "SQL", "level": 3, "score": 60, "weight": 0.5, "is_core": false, "category": "database", "skill_id": 7, "required_level": 2, "required_score": 40}]	You are close to Technical Support Engineer at a 70% skill match; your strongest fit here is Communication and Aptitude; the biggest gap is Problem Solving, which is not recorded yet (needs level 3).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
15	6	9	3	66.67	96.00	75.47	close	[{"gap": 60, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1.5, "is_core": true, "category": "soft_skill", "skill_id": 24, "required_level": 3, "required_score": 60}]	[{"gap": 0, "name": "Communication", "level": 4, "score": 80, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 23, "required_level": 3, "required_score": 60}, {"gap": 0, "name": "Java", "level": 4, "score": 80, "weight": 1, "is_core": false, "category": "programming", "skill_id": 3, "required_level": 3, "required_score": 60}, {"gap": 0, "name": "SQL", "level": 3, "score": 60, "weight": 1, "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}]	You are close to Testing / QA Engineer at a 67% skill match; your strongest fit here is Communication and Java; the biggest gap is Problem Solving, which is not recorded yet (needs level 3).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
17	6	1	5	50.00	96.00	63.80	close	[{"gap": 80, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1.5, "is_core": true, "category": "soft_skill", "skill_id": 24, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Python", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 3, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Scientific Computing with Python", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": false, "category": "programming", "skill_id": 4, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Git", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 12, "url": "https://roadmap.sh", "level": 2, "title": "Git and GitHub Basics", "is_free": true, "provider": "roadmap.sh", "duration_hours": 8}], "is_core": false, "category": "tool", "skill_id": 17, "required_level": 3, "required_score": 60}]	[{"gap": 0, "name": "Data Structures & Algorithms", "level": 4, "score": 80, "weight": 2, "is_core": true, "category": "technical", "skill_id": 14, "required_level": 4, "required_score": 80}, {"gap": 0, "name": "SQL", "level": 3, "score": 60, "weight": 1, "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}]	You are close to Software Development Engineer at a 50% skill match; your strongest fit here is Data Structures & Algorithms and SQL; the biggest gap is Problem Solving, which is not recorded yet (needs level 4).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
18	6	10	6	46.88	96.00	61.62	explore	[{"gap": 20, "name": "SQL", "level": 3, "score": 60, "weight": 2.5, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": true, "category": "database", "skill_id": 7, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "MongoDB", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "database", "skill_id": 8, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "Docker", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 13, "url": "https://roadmap.sh", "level": 3, "title": "Docker Roadmap", "is_free": true, "provider": "roadmap.sh", "duration_hours": 15}], "is_core": false, "category": "tool", "skill_id": 18, "required_level": 2, "required_score": 40}]	[]	Database Administrator is a stretch right now at a 47% skill match; the biggest gap is SQL at level 3 of the 4 needed.	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
19	6	4	7	45.45	96.00	60.61	explore	[{"gap": 60, "name": "Python", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 3, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Scientific Computing with Python", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": true, "category": "programming", "skill_id": 4, "required_level": 3, "required_score": 60}, {"gap": 20, "name": "SQL", "level": 3, "score": 60, "weight": 2, "courses": [{"id": 5, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Relational Database Course", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 20}], "is_core": true, "category": "database", "skill_id": 7, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 24, "required_level": 3, "required_score": 60}]	[{"gap": 0, "name": "Communication", "level": 4, "score": 80, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 23, "required_level": 3, "required_score": 60}]	Data Analyst is a stretch right now at a 45% skill match; your strongest fit here is Communication; the biggest gap is Python, which is not recorded yet (needs level 3).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
20	6	5	8	33.33	96.00	52.13	explore	[{"gap": 80, "name": "Machine Learning", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 10, "url": "https://nptel.ac.in", "level": 4, "title": "Introduction to Machine Learning", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "technical", "skill_id": 15, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "Python", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 3, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Scientific Computing with Python", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": true, "category": "programming", "skill_id": 4, "required_level": 4, "required_score": 80}]	[{"gap": 0, "name": "Data Structures & Algorithms", "level": 4, "score": 80, "weight": 1, "is_core": false, "category": "technical", "skill_id": 14, "required_level": 3, "required_score": 60}, {"gap": 0, "name": "SQL", "level": 3, "score": 60, "weight": 1, "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}]	Machine Learning Engineer is a stretch right now at a 33% skill match; your strongest fit here is Data Structures & Algorithms and SQL; the biggest gap is Machine Learning, which is not recorded yet (needs level 4).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
21	6	8	9	20.00	96.00	42.80	explore	[{"gap": 80, "name": "AutoCAD", "level": 0, "score": 0, "weight": 2, "is_core": true, "category": "tool", "skill_id": 21, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Teamwork", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 25, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "MATLAB", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "tool", "skill_id": 20, "required_level": 2, "required_score": 40}]	[{"gap": 0, "name": "Communication", "level": 4, "score": 80, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 23, "required_level": 3, "required_score": 60}]	Design Engineer is a stretch right now at a 20% skill match; your strongest fit here is Communication; the biggest gap is AutoCAD, which is not recorded yet (needs level 4).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
22	6	2	10	13.33	96.00	38.13	explore	[{"gap": 80, "name": "JavaScript", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 4, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "JavaScript Algorithms and Data Structures", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 35}], "is_core": true, "category": "programming", "skill_id": 5, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "React", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 6, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Front End Development Libraries", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": true, "category": "framework", "skill_id": 9, "required_level": 3, "required_score": 60}, {"gap": 80, "name": "HTML/CSS", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 8, "url": "https://www.freecodecamp.org/learn", "level": 2, "title": "Responsive Web Design", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 25}], "is_core": false, "category": "technical", "skill_id": 13, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Node.js", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 7, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Back End Development and APIs", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": false, "category": "framework", "skill_id": 10, "required_level": 3, "required_score": 60}, {"gap": 60, "name": "Git", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 12, "url": "https://roadmap.sh", "level": 2, "title": "Git and GitHub Basics", "is_free": true, "provider": "roadmap.sh", "duration_hours": 8}], "is_core": false, "category": "tool", "skill_id": 17, "required_level": 3, "required_score": 60}]	[{"gap": 0, "name": "SQL", "level": 3, "score": 60, "weight": 1, "is_core": false, "category": "database", "skill_id": 7, "required_level": 3, "required_score": 60}]	Full Stack Developer is a stretch right now at a 13% skill match; your strongest fit here is SQL; the biggest gap is JavaScript, which is not recorded yet (needs level 4).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
23	6	6	11	0.00	96.00	28.80	explore	[{"gap": 80, "name": "Cloud (AWS/Azure)", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 11, "url": "https://nptel.ac.in", "level": 3, "title": "Cloud Computing", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "tool", "skill_id": 16, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "Docker", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 13, "url": "https://roadmap.sh", "level": 3, "title": "Docker Roadmap", "is_free": true, "provider": "roadmap.sh", "duration_hours": 15}], "is_core": true, "category": "tool", "skill_id": 18, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Git", "level": 0, "score": 0, "weight": 1, "courses": [{"id": 12, "url": "https://roadmap.sh", "level": 2, "title": "Git and GitHub Basics", "is_free": true, "provider": "roadmap.sh", "duration_hours": 8}], "is_core": false, "category": "tool", "skill_id": 17, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "Python", "level": 0, "score": 0, "weight": 0.5, "courses": [{"id": 3, "url": "https://www.freecodecamp.org/learn", "level": 3, "title": "Scientific Computing with Python", "is_free": true, "provider": "freeCodeCamp", "duration_hours": 30}], "is_core": false, "category": "programming", "skill_id": 4, "required_level": 2, "required_score": 40}]	[]	Cloud / DevOps Engineer is a stretch right now at a 0% skill match; the biggest gap is Cloud (AWS/Azure), which is not recorded yet (needs level 4).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
24	6	7	12	0.00	96.00	28.80	explore	[{"gap": 80, "name": "Embedded C", "level": 0, "score": 0, "weight": 2, "courses": [{"id": 14, "url": "https://nptel.ac.in", "level": 3, "title": "Embedded Systems Design", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "programming", "skill_id": 19, "required_level": 4, "required_score": 80}, {"gap": 80, "name": "C", "level": 0, "score": 0, "weight": 1.5, "courses": [{"id": 1, "url": "https://nptel.ac.in", "level": 2, "title": "Problem Solving through Programming in C", "is_free": true, "provider": "NPTEL", "duration_hours": 40}], "is_core": true, "category": "programming", "skill_id": 1, "required_level": 4, "required_score": 80}, {"gap": 60, "name": "Problem Solving", "level": 0, "score": 0, "weight": 1, "is_core": false, "category": "soft_skill", "skill_id": 24, "required_level": 3, "required_score": 60}, {"gap": 40, "name": "MATLAB", "level": 0, "score": 0, "weight": 0.5, "is_core": false, "category": "tool", "skill_id": 20, "required_level": 2, "required_score": 40}]	[]	Embedded Systems Engineer is a stretch right now at a 0% skill match; the biggest gap is Embedded C, which is not recorded yet (needs level 4).	2026-10-03 15:33:40.180946+05:30	t	2026-10-03 15:33:40.184835+05:30	1	2026-10-03 15:33:40.184835+05:30	1
\.


--
-- Data for Name: career_skills; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.career_skills (id, career_id, skill_id, required_level, weight, is_core, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	24	4	1.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
2	1	17	3	0.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
3	1	14	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
4	1	7	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
5	1	4	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
6	2	17	3	0.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
7	2	13	4	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
8	2	10	3	1.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
9	2	9	3	1.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
10	2	7	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
11	2	5	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
12	3	18	2	0.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
13	3	17	3	0.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
14	3	11	3	1.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
15	3	7	4	1.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
16	3	3	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
17	4	24	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
18	4	23	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
19	4	7	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
20	4	4	3	1.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
21	5	15	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
22	5	14	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
23	5	7	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
24	5	4	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
25	6	18	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
26	6	17	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
27	6	16	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
28	6	4	2	0.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
29	7	24	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
30	7	20	2	0.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
31	7	19	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
32	7	1	4	1.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
33	8	25	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
34	8	23	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
35	8	21	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
36	8	20	2	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
37	9	24	3	1.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
38	9	23	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
39	9	7	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
40	9	3	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
41	10	18	2	0.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
42	10	8	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
43	10	7	4	2.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
44	11	24	3	1.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
45	11	23	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
46	11	22	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
47	11	7	2	0.50	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
48	12	25	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
49	12	23	4	2.00	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
50	12	22	4	1.50	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
51	12	7	3	1.00	f	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
\.


--
-- Data for Name: careers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.careers (id, code, name, domain, description, avg_package, min_cgpa, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	SDE	Software Development Engineer	IT / Software	Builds and ships application software. Interviews centre on data structures, problem solving and one strong language.	6.50	6.50	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
2	FULLSTACK	Full Stack Developer	IT / Software	Works across the browser and the server, from screens to APIs and databases.	5.50	6.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
3	BACKEND	Backend Developer	IT / Software	Owns APIs, business logic and data stores behind a product.	6.00	6.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
4	DATA_AN	Data Analyst	Data	Turns raw data into reports and decisions with SQL, spreadsheets and visualisation.	4.50	6.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
5	ML_ENG	Machine Learning Engineer	Data	Trains and deploys models. Expects strong Python, statistics and ML fundamentals.	8.00	7.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
6	DEVOPS	Cloud / DevOps Engineer	Infrastructure	Runs build pipelines, containers and cloud infrastructure.	6.50	6.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
7	EMBEDDED	Embedded Systems Engineer	Core / Hardware	Programs microcontrollers and hardware-facing firmware.	4.50	6.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
8	DESIGN_E	Design Engineer	Core	Produces and validates engineering designs and drawings.	4.00	6.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
9	QA	Testing / QA Engineer	IT / Software	Finds defects before customers do, by hand and with automation.	4.00	6.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
10	DBA	Database Administrator	Infrastructure	Keeps databases fast, backed up and secure.	5.00	6.00	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
11	SUPPORT	Technical Support Engineer	IT Services	Resolves customer issues; the most common entry route into an IT services company.	3.50	5.50	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
12	BIZ_AN	Business Analyst	IT Services	Sits between the customer and the engineers, writing down what must be built.	5.00	6.50	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
\.


--
-- Data for Name: classes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.classes (id, department_id, academic_year_id, year_level_id, section, class_incharge_id, is_active, created_at, created_by, updated_at, updated_by, current_semester_id) FROM stdin;
2	1	2	2	B	2	t	2026-09-21 13:49:54.204995+05:30	1	2026-09-21 13:49:54.204995+05:30	1	4
3	1	2	3	A	3	t	2026-09-21 13:49:54.209175+05:30	1	2026-09-21 13:49:54.209175+05:30	1	6
4	2	2	2	A	5	t	2026-09-21 13:49:54.215473+05:30	1	2026-09-21 13:49:54.215473+05:30	1	4
1	1	2	2	A	4	t	2026-09-21 13:49:54.198242+05:30	1	2026-10-01 17:35:17.353117+05:30	1	3
\.


--
-- Data for Name: companies; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.companies (id, name, industry, website, location, contact_person, contact_email, contact_mobile, description, is_active, created_at, created_by, updated_at, updated_by, logo_file_id) FROM stdin;
1	Zoho	Product / SaaS	\N	Chennai	\N	\N	\N	\N	t	2026-09-21 13:49:55.199123+05:30	2	2026-09-21 13:49:55.199123+05:30	2	\N
2	TCS	IT Services	\N	Chennai	\N	\N	\N	\N	t	2026-09-21 13:49:55.214061+05:30	2	2026-09-21 13:49:55.214061+05:30	2	\N
3	Infosys	IT Services	\N	Bengaluru	\N	\N	\N	\N	t	2026-09-21 13:49:55.217827+05:30	2	2026-09-21 13:49:55.217827+05:30	2	\N
\.


--
-- Data for Name: company_job_roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.company_job_roles (id, company_id, title, description, package_lpa, drive_date, last_apply_date, min_cgpa, max_backlogs, eligible_batch, openings, status, is_active, created_at, created_by, updated_at, updated_by, jd_file_id) FROM stdin;
1	1	Software Developer	\N	8.40	2026-11-15	2026-11-05	7.00	0	\N	\N	open	t	2026-09-21 13:49:55.222826+05:30	2	2026-09-21 13:49:55.222826+05:30	2	\N
2	2	Ninja - Assistant System Engineer	\N	3.60	2026-10-20	2026-10-10	6.00	1	\N	\N	open	t	2026-09-21 13:49:55.259347+05:30	2	2026-09-21 13:49:55.259347+05:30	2	\N
3	3	Systems Engineer	\N	4.50	2026-12-10	\N	6.50	0	\N	\N	upcoming	t	2026-09-21 13:49:55.279016+05:30	2	2026-09-21 13:49:55.279016+05:30	2	\N
\.


--
-- Data for Name: courses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.courses (id, skill_id, title, provider, url, level, duration_hours, is_certification, is_free, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	Problem Solving through Programming in C	NPTEL	https://nptel.ac.in	2	40	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
2	3	Programming in Java	NPTEL	https://nptel.ac.in	3	40	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
3	4	Scientific Computing with Python	freeCodeCamp	https://www.freecodecamp.org/learn	3	30	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
4	5	JavaScript Algorithms and Data Structures	freeCodeCamp	https://www.freecodecamp.org/learn	3	35	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
5	7	Relational Database Course	freeCodeCamp	https://www.freecodecamp.org/learn	3	20	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
6	9	Front End Development Libraries	freeCodeCamp	https://www.freecodecamp.org/learn	3	30	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
7	10	Back End Development and APIs	freeCodeCamp	https://www.freecodecamp.org/learn	3	30	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
8	13	Responsive Web Design	freeCodeCamp	https://www.freecodecamp.org/learn	2	25	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
9	14	Data Structures and Algorithms	NPTEL	https://nptel.ac.in	3	40	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
10	15	Introduction to Machine Learning	NPTEL	https://nptel.ac.in	4	40	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
11	16	Cloud Computing	NPTEL	https://nptel.ac.in	3	40	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
12	17	Git and GitHub Basics	roadmap.sh	https://roadmap.sh	2	8	f	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
13	18	Docker Roadmap	roadmap.sh	https://roadmap.sh	3	15	f	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
14	19	Embedded Systems Design	NPTEL	https://nptel.ac.in	3	40	t	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
15	22	Quantitative Aptitude Practice	In-house	\N	2	20	f	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
16	23	Soft Skills and Interview Preparation	In-house	\N	2	15	f	t	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
\.


--
-- Data for Name: curriculum; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.curriculum (id, department_id, semester_id, subject_id, regulation, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	4	1	R2021	t	2026-09-21 13:49:54.178291+05:30	1	2026-09-21 13:49:54.178291+05:30	1
2	1	4	2	R2021	t	2026-09-21 13:49:54.178291+05:30	1	2026-09-21 13:49:54.178291+05:30	1
3	1	4	3	R2021	t	2026-09-21 13:49:54.178291+05:30	1	2026-09-21 13:49:54.178291+05:30	1
4	1	3	4	R2021	t	2026-09-21 13:49:54.183288+05:30	1	2026-09-21 13:49:54.183288+05:30	1
5	1	3	5	R2021	t	2026-09-21 13:49:54.183288+05:30	1	2026-09-21 13:49:54.183288+05:30	1
6	1	3	6	R2021	t	2026-09-21 13:49:54.183288+05:30	1	2026-09-21 13:49:54.183288+05:30	1
7	2	4	7	R2021	t	2026-09-21 13:49:54.187201+05:30	1	2026-09-21 13:49:54.187201+05:30	1
8	2	4	8	R2021	t	2026-09-21 13:49:54.187201+05:30	1	2026-09-21 13:49:54.187201+05:30	1
9	2	4	3	R2021	t	2026-09-21 13:49:54.187201+05:30	1	2026-09-21 13:49:54.187201+05:30	1
\.


--
-- Data for Name: departments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.departments (id, name, code, hod_id, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
3	Mechanical Engineering	MECH	\N	t	2026-09-21 13:49:53.878272+05:30	1	2026-09-21 13:49:53.878272+05:30	1
1	Computer Science and Engineering	CSE	3	t	2026-09-21 13:49:53.865437+05:30	1	2026-09-21 13:49:54.129524+05:30	1
2	Electronics and Communication Engineering	ECE	5	t	2026-09-21 13:49:53.873961+05:30	1	2026-09-21 13:49:54.134507+05:30	1
\.


--
-- Data for Name: device_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.device_tokens (id, user_id, token, platform, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
\.


--
-- Data for Name: exam_types; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exam_types (id, name, code, max_marks, is_final, sort_order, is_active, created_at, created_by, updated_at, updated_by, pass_percent) FROM stdin;
1	Internal Assessment 1	IA1	50.00	f	1	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N	50.00
2	Internal Assessment 2	IA2	50.00	f	2	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N	50.00
3	Model Exam	MODEL	100.00	f	3	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N	50.00
4	End Semester	SEM	100.00	t	4	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N	50.00
\.


--
-- Data for Name: files; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.files (id, uuid, category, original_name, content_type, size_bytes, sha256, storage_key, ref_type, ref_id, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
7	c98c72d0-0151-402a-a93c-17c43419b8a5	resume	cv.pdf	application/pdf	45	5a838678058f6de375e8635b5f2fea47a4e5f07cb1a882a44b10f39abc6f34ff		\N	\N	f	2026-09-21 17:52:15.508686+05:30	7	2026-09-22 20:19:47.989814+05:30	7
1	81d5d369-f349-4a6e-b133-dfd498236668	profile_photo	me.png	image/png	69	b1ff9c8ea3a780bad09b346c423d2d0e46815926879b18e841d928376a946640		users	6	f	2026-09-21 17:52:11.362969+05:30	6	2026-10-01 17:23:30.117399+05:30	6
2	a962e0b8-c7e6-48b2-aa8e-45889140c876	profile_photo	a.png	image/png	69	b1ff9c8ea3a780bad09b346c423d2d0e46815926879b18e841d928376a946640		users	6	f	2026-09-21 17:52:14.260295+05:30	4	2026-10-01 17:23:30.157431+05:30	4
3	07b03f00-91be-401f-9358-853df6ccf29d	profile_photo	s.png	image/png	69	b1ff9c8ea3a780bad09b346c423d2d0e46815926879b18e841d928376a946640		users	4	f	2026-09-21 17:52:14.394777+05:30	4	2026-10-01 17:23:30.160103+05:30	4
4	3f43cc0b-eab9-484f-8811-9faddff14f22	profile_photo	p.png	image/png	69	b1ff9c8ea3a780bad09b346c423d2d0e46815926879b18e841d928376a946640		users	7	f	2026-09-21 17:52:15.045643+05:30	7	2026-10-01 17:23:30.16188+05:30	7
5	30670560-26a5-47fd-b150-bae492302a60	profile_photo	p.png	image/png	69	b1ff9c8ea3a780bad09b346c423d2d0e46815926879b18e841d928376a946640		users	1	f	2026-09-21 17:52:15.160189+05:30	1	2026-10-01 17:23:30.164692+05:30	1
6	22f96a70-f42d-442b-bd56-162c8cc3ba5e	resume	cv.pdf	application/pdf	45	5a838678058f6de375e8635b5f2fea47a4e5f07cb1a882a44b10f39abc6f34ff		student_profiles	6	f	2026-09-21 17:52:15.311856+05:30	6	2026-10-01 17:23:30.166452+05:30	4
8	929dc6e1-4bdc-442b-9bb3-a7190c7aaaaf	student_document	tc.pdf	application/pdf	45	5a838678058f6de375e8635b5f2fea47a4e5f07cb1a882a44b10f39abc6f34ff		student_documents	1	f	2026-09-21 17:52:16.027143+05:30	6	2026-10-01 17:23:30.168753+05:30	4
9	4d4e1290-c319-44e8-94fe-ece47e6d8588	student_document	id.png	image/png	69	b1ff9c8ea3a780bad09b346c423d2d0e46815926879b18e841d928376a946640		student_documents	2	f	2026-09-21 17:52:17.528118+05:30	4	2026-10-01 17:23:30.1704+05:30	4
10	d08f51ff-8e5e-47e4-b931-382033e07aac	student_document	m.pdf	application/pdf	45	5a838678058f6de375e8635b5f2fea47a4e5f07cb1a882a44b10f39abc6f34ff		student_documents	3	f	2026-09-21 17:52:18.042764+05:30	6	2026-10-01 17:23:30.172315+05:30	6
11	b5b071a5-e214-4126-bb8e-2bf4582cfa00	profile_photo	arun.png	image/png	1547	e70b76fa91e6227e672453a567d9d0b9fbc34e597d92902b45584c2f65c7157a		users	6	f	2026-09-21 17:56:46.926474+05:30	6	2026-10-01 17:23:30.174844+05:30	1
12	bfa4093c-d886-44e9-bce0-14b6ee1b52ff	student_document	tenth.pdf	application/pdf	69	cfa3181c1ee36e8bce5e39f84959f4558ea7ba32c0e4539a8ab3c8ce8c716ec6		student_documents	4	f	2026-09-21 17:57:02.398609+05:30	6	2026-10-01 17:23:30.177563+05:30	1
\.


--
-- Data for Name: grade_scales; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.grade_scales (id, grade, min_percent, grade_point, is_pass, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	O	91.00	10.00	t	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
2	A+	81.00	9.00	t	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
3	A	71.00	8.00	t	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
4	B+	61.00	7.00	t	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
5	B	56.00	6.00	t	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
6	C	50.00	5.00	t	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
7	U	0.00	0.00	f	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
\.


--
-- Data for Name: job_role_departments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.job_role_departments (id, job_role_id, department_id, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	1	t	2026-09-21 13:49:55.222826+05:30	2	2026-09-21 13:49:55.222826+05:30	2
\.


--
-- Data for Name: job_role_skills; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.job_role_skills (id, job_role_id, skill_id, required_level, is_mandatory, weight, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	3	4	t	2.00	t	2026-09-21 13:49:55.222826+05:30	2	2026-09-21 13:49:55.222826+05:30	2
2	1	14	3	t	2.00	t	2026-09-21 13:49:55.222826+05:30	2	2026-09-21 13:49:55.222826+05:30	2
3	1	7	3	f	1.00	t	2026-09-21 13:49:55.222826+05:30	2	2026-09-21 13:49:55.222826+05:30	2
4	1	23	3	f	1.00	t	2026-09-21 13:49:55.222826+05:30	2	2026-09-21 13:49:55.222826+05:30	2
5	2	22	3	t	2.00	t	2026-09-21 13:49:55.259347+05:30	2	2026-09-21 13:49:55.259347+05:30	2
6	2	23	3	f	1.00	t	2026-09-21 13:49:55.259347+05:30	2	2026-09-21 13:49:55.259347+05:30	2
7	2	3	2	f	1.00	t	2026-09-21 13:49:55.259347+05:30	2	2026-09-21 13:49:55.259347+05:30	2
8	3	4	3	f	1.00	t	2026-09-21 13:49:55.279016+05:30	2	2026-09-21 13:49:55.279016+05:30	2
9	3	7	3	t	1.00	t	2026-09-21 13:49:55.279016+05:30	2	2026-09-21 13:49:55.279016+05:30	2
10	3	22	3	t	1.00	t	2026-09-21 13:49:55.279016+05:30	2	2026-09-21 13:49:55.279016+05:30	2
11	3	23	4	f	1.00	t	2026-09-21 13:49:55.279016+05:30	2	2026-09-21 13:49:55.279016+05:30	2
\.


--
-- Data for Name: notification_recipients; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notification_recipients (id, notification_id, user_id, is_read, read_at, push_status, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	6	f	\N	skipped	t	2026-09-21 13:49:54.604178+05:30	4	2026-09-21 13:49:54.604178+05:30	4
2	1	8	f	\N	skipped	t	2026-09-21 13:49:54.604178+05:30	4	2026-09-21 13:49:54.604178+05:30	4
3	1	9	f	\N	skipped	t	2026-09-21 13:49:54.604178+05:30	4	2026-09-21 13:49:54.604178+05:30	4
4	1	10	f	\N	skipped	t	2026-09-21 13:49:54.604178+05:30	4	2026-09-21 13:49:54.604178+05:30	4
5	1	11	f	\N	skipped	t	2026-09-21 13:49:54.604178+05:30	4	2026-09-21 13:49:54.604178+05:30	4
6	1	12	f	\N	skipped	t	2026-09-21 13:49:54.604178+05:30	4	2026-09-21 13:49:54.604178+05:30	4
8	2	6	f	\N	skipped	t	2026-09-21 13:49:54.625047+05:30	4	2026-09-21 13:49:54.625047+05:30	4
9	2	8	f	\N	skipped	t	2026-09-21 13:49:54.625047+05:30	4	2026-09-21 13:49:54.625047+05:30	4
10	2	9	f	\N	skipped	t	2026-09-21 13:49:54.625047+05:30	4	2026-09-21 13:49:54.625047+05:30	4
11	2	10	f	\N	skipped	t	2026-09-21 13:49:54.625047+05:30	4	2026-09-21 13:49:54.625047+05:30	4
12	2	11	f	\N	skipped	t	2026-09-21 13:49:54.625047+05:30	4	2026-09-21 13:49:54.625047+05:30	4
13	2	12	f	\N	skipped	t	2026-09-21 13:49:54.625047+05:30	4	2026-09-21 13:49:54.625047+05:30	4
15	3	6	f	\N	skipped	t	2026-09-21 13:49:54.645052+05:30	4	2026-09-21 13:49:54.645052+05:30	4
16	3	8	f	\N	skipped	t	2026-09-21 13:49:54.645052+05:30	4	2026-09-21 13:49:54.645052+05:30	4
17	3	9	f	\N	skipped	t	2026-09-21 13:49:54.645052+05:30	4	2026-09-21 13:49:54.645052+05:30	4
18	3	10	f	\N	skipped	t	2026-09-21 13:49:54.645052+05:30	4	2026-09-21 13:49:54.645052+05:30	4
19	3	11	f	\N	skipped	t	2026-09-21 13:49:54.645052+05:30	4	2026-09-21 13:49:54.645052+05:30	4
20	3	12	f	\N	skipped	t	2026-09-21 13:49:54.645052+05:30	4	2026-09-21 13:49:54.645052+05:30	4
22	4	6	f	\N	skipped	t	2026-09-21 13:49:54.659476+05:30	4	2026-09-21 13:49:54.659476+05:30	4
23	4	8	f	\N	skipped	t	2026-09-21 13:49:54.659476+05:30	4	2026-09-21 13:49:54.659476+05:30	4
24	4	9	f	\N	skipped	t	2026-09-21 13:49:54.659476+05:30	4	2026-09-21 13:49:54.659476+05:30	4
25	4	10	f	\N	skipped	t	2026-09-21 13:49:54.659476+05:30	4	2026-09-21 13:49:54.659476+05:30	4
26	4	11	f	\N	skipped	t	2026-09-21 13:49:54.659476+05:30	4	2026-09-21 13:49:54.659476+05:30	4
27	4	12	f	\N	skipped	t	2026-09-21 13:49:54.659476+05:30	4	2026-09-21 13:49:54.659476+05:30	4
29	5	6	f	\N	skipped	t	2026-09-21 13:49:54.672698+05:30	4	2026-09-21 13:49:54.672698+05:30	4
30	5	8	f	\N	skipped	t	2026-09-21 13:49:54.672698+05:30	4	2026-09-21 13:49:54.672698+05:30	4
31	5	9	f	\N	skipped	t	2026-09-21 13:49:54.672698+05:30	4	2026-09-21 13:49:54.672698+05:30	4
32	5	10	f	\N	skipped	t	2026-09-21 13:49:54.672698+05:30	4	2026-09-21 13:49:54.672698+05:30	4
33	5	11	f	\N	skipped	t	2026-09-21 13:49:54.672698+05:30	4	2026-09-21 13:49:54.672698+05:30	4
34	5	12	f	\N	skipped	t	2026-09-21 13:49:54.672698+05:30	4	2026-09-21 13:49:54.672698+05:30	4
36	6	6	f	\N	skipped	t	2026-09-21 13:49:54.688264+05:30	4	2026-09-21 13:49:54.688264+05:30	4
37	6	8	f	\N	skipped	t	2026-09-21 13:49:54.688264+05:30	4	2026-09-21 13:49:54.688264+05:30	4
38	6	9	f	\N	skipped	t	2026-09-21 13:49:54.688264+05:30	4	2026-09-21 13:49:54.688264+05:30	4
39	6	10	f	\N	skipped	t	2026-09-21 13:49:54.688264+05:30	4	2026-09-21 13:49:54.688264+05:30	4
40	6	11	f	\N	skipped	t	2026-09-21 13:49:54.688264+05:30	4	2026-09-21 13:49:54.688264+05:30	4
41	6	12	f	\N	skipped	t	2026-09-21 13:49:54.688264+05:30	4	2026-09-21 13:49:54.688264+05:30	4
43	7	6	f	\N	skipped	t	2026-09-21 13:49:54.699321+05:30	4	2026-09-21 13:49:54.699321+05:30	4
44	7	8	f	\N	skipped	t	2026-09-21 13:49:54.699321+05:30	4	2026-09-21 13:49:54.699321+05:30	4
45	7	9	f	\N	skipped	t	2026-09-21 13:49:54.699321+05:30	4	2026-09-21 13:49:54.699321+05:30	4
46	7	10	f	\N	skipped	t	2026-09-21 13:49:54.699321+05:30	4	2026-09-21 13:49:54.699321+05:30	4
47	7	11	f	\N	skipped	t	2026-09-21 13:49:54.699321+05:30	4	2026-09-21 13:49:54.699321+05:30	4
48	7	12	f	\N	skipped	t	2026-09-21 13:49:54.699321+05:30	4	2026-09-21 13:49:54.699321+05:30	4
50	8	6	f	\N	skipped	t	2026-09-21 13:49:54.708396+05:30	4	2026-09-21 13:49:54.708396+05:30	4
51	8	8	f	\N	skipped	t	2026-09-21 13:49:54.708396+05:30	4	2026-09-21 13:49:54.708396+05:30	4
52	8	9	f	\N	skipped	t	2026-09-21 13:49:54.708396+05:30	4	2026-09-21 13:49:54.708396+05:30	4
53	8	10	f	\N	skipped	t	2026-09-21 13:49:54.708396+05:30	4	2026-09-21 13:49:54.708396+05:30	4
54	8	11	f	\N	skipped	t	2026-09-21 13:49:54.708396+05:30	4	2026-09-21 13:49:54.708396+05:30	4
55	8	12	f	\N	skipped	t	2026-09-21 13:49:54.708396+05:30	4	2026-09-21 13:49:54.708396+05:30	4
57	9	6	f	\N	skipped	t	2026-09-21 13:49:54.715977+05:30	4	2026-09-21 13:49:54.715977+05:30	4
58	9	8	f	\N	skipped	t	2026-09-21 13:49:54.715977+05:30	4	2026-09-21 13:49:54.715977+05:30	4
59	9	9	f	\N	skipped	t	2026-09-21 13:49:54.715977+05:30	4	2026-09-21 13:49:54.715977+05:30	4
60	9	10	f	\N	skipped	t	2026-09-21 13:49:54.715977+05:30	4	2026-09-21 13:49:54.715977+05:30	4
61	9	11	f	\N	skipped	t	2026-09-21 13:49:54.715977+05:30	4	2026-09-21 13:49:54.715977+05:30	4
62	9	12	f	\N	skipped	t	2026-09-21 13:49:54.715977+05:30	4	2026-09-21 13:49:54.715977+05:30	4
64	10	6	f	\N	skipped	t	2026-09-21 13:49:55.007154+05:30	4	2026-09-21 13:49:55.007154+05:30	4
65	11	6	f	\N	skipped	t	2026-09-21 13:49:55.013857+05:30	4	2026-09-21 13:49:55.013857+05:30	4
66	12	6	f	\N	skipped	t	2026-09-21 13:49:55.019942+05:30	4	2026-09-21 13:49:55.019942+05:30	4
67	13	6	f	\N	skipped	t	2026-09-21 13:49:55.026971+05:30	4	2026-09-21 13:49:55.026971+05:30	4
68	14	6	f	\N	skipped	t	2026-09-21 13:49:55.03497+05:30	4	2026-09-21 13:49:55.03497+05:30	4
69	15	8	f	\N	skipped	t	2026-09-21 13:49:55.042563+05:30	4	2026-09-21 13:49:55.042563+05:30	4
70	16	8	f	\N	skipped	t	2026-09-21 13:49:55.051016+05:30	4	2026-09-21 13:49:55.051016+05:30	4
71	17	8	f	\N	skipped	t	2026-09-21 13:49:55.056801+05:30	4	2026-09-21 13:49:55.056801+05:30	4
72	18	8	f	\N	skipped	t	2026-09-21 13:49:55.060198+05:30	4	2026-09-21 13:49:55.060198+05:30	4
73	19	8	f	\N	skipped	t	2026-09-21 13:49:55.064743+05:30	4	2026-09-21 13:49:55.064743+05:30	4
74	20	9	f	\N	skipped	t	2026-09-21 13:49:55.071813+05:30	4	2026-09-21 13:49:55.071813+05:30	4
75	21	9	f	\N	skipped	t	2026-09-21 13:49:55.075897+05:30	4	2026-09-21 13:49:55.075897+05:30	4
76	22	9	f	\N	skipped	t	2026-09-21 13:49:55.080868+05:30	4	2026-09-21 13:49:55.080868+05:30	4
77	23	9	f	\N	skipped	t	2026-09-21 13:49:55.088072+05:30	4	2026-09-21 13:49:55.088072+05:30	4
78	24	9	f	\N	skipped	t	2026-09-21 13:49:55.093354+05:30	4	2026-09-21 13:49:55.093354+05:30	4
79	25	11	f	\N	skipped	t	2026-09-21 13:49:55.099726+05:30	4	2026-09-21 13:49:55.099726+05:30	4
80	26	11	f	\N	skipped	t	2026-09-21 13:49:55.105129+05:30	4	2026-09-21 13:49:55.105129+05:30	4
81	27	11	f	\N	skipped	t	2026-09-21 13:49:55.109216+05:30	4	2026-09-21 13:49:55.109216+05:30	4
82	28	11	f	\N	skipped	t	2026-09-21 13:49:55.114313+05:30	4	2026-09-21 13:49:55.114313+05:30	4
83	29	13	f	\N	skipped	t	2026-09-21 13:49:55.11981+05:30	4	2026-09-21 13:49:55.11981+05:30	4
84	30	13	f	\N	skipped	t	2026-09-21 13:49:55.125211+05:30	4	2026-09-21 13:49:55.125211+05:30	4
85	31	13	f	\N	skipped	t	2026-09-21 13:49:55.131326+05:30	4	2026-09-21 13:49:55.131326+05:30	4
86	32	13	f	\N	skipped	t	2026-09-21 13:49:55.136599+05:30	4	2026-09-21 13:49:55.136599+05:30	4
87	33	15	f	\N	skipped	t	2026-09-21 13:49:55.140473+05:30	4	2026-09-21 13:49:55.140473+05:30	4
88	34	15	f	\N	skipped	t	2026-09-21 13:49:55.146664+05:30	4	2026-09-21 13:49:55.146664+05:30	4
89	35	15	f	\N	skipped	t	2026-09-21 13:49:55.152099+05:30	4	2026-09-21 13:49:55.152099+05:30	4
90	36	15	f	\N	skipped	t	2026-09-21 13:49:55.15634+05:30	4	2026-09-21 13:49:55.15634+05:30	4
91	37	23	f	\N	skipped	t	2026-09-21 13:49:55.161657+05:30	5	2026-09-21 13:49:55.161657+05:30	5
92	38	23	f	\N	skipped	t	2026-09-21 13:49:55.166322+05:30	5	2026-09-21 13:49:55.166322+05:30	5
93	39	23	f	\N	skipped	t	2026-09-21 13:49:55.171016+05:30	5	2026-09-21 13:49:55.171016+05:30	5
94	40	23	f	\N	skipped	t	2026-09-21 13:49:55.17541+05:30	5	2026-09-21 13:49:55.17541+05:30	5
95	41	23	f	\N	skipped	t	2026-09-21 13:49:55.181203+05:30	5	2026-09-21 13:49:55.181203+05:30	5
96	42	25	f	\N	skipped	t	2026-09-21 13:49:55.185518+05:30	5	2026-09-21 13:49:55.185518+05:30	5
97	43	25	f	\N	skipped	t	2026-09-21 13:49:55.190973+05:30	5	2026-09-21 13:49:55.190973+05:30	5
98	44	25	f	\N	skipped	t	2026-09-21 13:49:55.196428+05:30	5	2026-09-21 13:49:55.196428+05:30	5
99	45	6	f	\N	skipped	t	2026-09-21 13:49:55.254121+05:30	2	2026-09-21 13:49:55.254121+05:30	2
100	46	6	f	\N	skipped	t	2026-09-21 13:49:55.271926+05:30	2	2026-09-21 13:49:55.271926+05:30	2
101	46	8	f	\N	skipped	t	2026-09-21 13:49:55.271926+05:30	2	2026-09-21 13:49:55.271926+05:30	2
102	46	9	f	\N	skipped	t	2026-09-21 13:49:55.271926+05:30	2	2026-09-21 13:49:55.271926+05:30	2
103	47	6	f	\N	skipped	t	2026-09-21 13:49:55.327831+05:30	2	2026-09-21 13:49:55.327831+05:30	2
105	48	6	f	\N	skipped	t	2026-09-21 13:49:55.339625+05:30	2	2026-09-21 13:49:55.339625+05:30	2
106	48	8	f	\N	skipped	t	2026-09-21 13:49:55.339625+05:30	2	2026-09-21 13:49:55.339625+05:30	2
107	48	9	f	\N	skipped	t	2026-09-21 13:49:55.339625+05:30	2	2026-09-21 13:49:55.339625+05:30	2
108	48	10	f	\N	skipped	t	2026-09-21 13:49:55.339625+05:30	2	2026-09-21 13:49:55.339625+05:30	2
110	49	6	f	\N	skipped	t	2026-09-21 13:49:55.360288+05:30	2	2026-09-21 13:49:55.360288+05:30	2
114	51	3	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
116	51	8	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
117	51	9	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
118	51	10	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
119	51	11	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
120	51	12	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
121	51	13	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
122	51	14	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
123	51	15	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
124	51	16	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
125	51	17	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
126	51	18	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
127	51	19	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
128	51	20	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
129	51	21	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
130	51	22	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
131	51	23	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
132	51	24	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
133	51	25	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
134	51	26	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
135	51	27	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
136	51	28	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
138	51	4	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
139	51	5	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
140	51	2	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
141	51	1	f	\N	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1
115	51	6	t	2026-09-21 13:54:02.621424+05:30	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:54:02.621424+05:30	1
112	50	6	t	2026-09-21 13:54:05.084164+05:30	skipped	t	2026-09-21 13:49:55.371635+05:30	2	2026-09-21 13:54:05.084164+05:30	2
142	52	8	f	\N	skipped	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 13:55:00.701839+05:30	3
143	52	9	f	\N	skipped	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 13:55:00.701839+05:30	3
144	52	10	f	\N	skipped	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 13:55:00.701839+05:30	3
145	52	11	f	\N	skipped	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 13:55:00.701839+05:30	3
146	52	12	f	\N	skipped	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 13:55:00.701839+05:30	3
148	52	4	f	\N	skipped	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 13:55:00.701839+05:30	3
149	52	6	f	\N	skipped	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 13:55:00.701839+05:30	3
7	1	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.604178+05:30	4	2026-09-21 14:39:47.470141+05:30	4
14	2	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.625047+05:30	4	2026-09-21 14:39:47.470141+05:30	4
21	3	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.645052+05:30	4	2026-09-21 14:39:47.470141+05:30	4
28	4	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.659476+05:30	4	2026-09-21 14:39:47.470141+05:30	4
35	5	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.672698+05:30	4	2026-09-21 14:39:47.470141+05:30	4
42	6	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.688264+05:30	4	2026-09-21 14:39:47.470141+05:30	4
49	7	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.699321+05:30	4	2026-09-21 14:39:47.470141+05:30	4
56	8	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.708396+05:30	4	2026-09-21 14:39:47.470141+05:30	4
63	9	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:54.715977+05:30	4	2026-09-21 14:39:47.470141+05:30	4
104	47	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:55.327831+05:30	2	2026-09-21 14:39:47.470141+05:30	2
109	48	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:55.339625+05:30	2	2026-09-21 14:39:47.470141+05:30	2
111	49	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:55.360288+05:30	2	2026-09-21 14:39:47.470141+05:30	2
113	50	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:55.371635+05:30	2	2026-09-21 14:39:47.470141+05:30	2
137	51	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 14:39:47.470141+05:30	1
147	52	7	t	2026-09-21 14:39:47.470141+05:30	skipped	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 14:39:47.470141+05:30	3
153	54	6	f	\N	skipped	f	2026-09-21 17:52:17.374632+05:30	4	2026-09-21 17:52:18.108293+05:30	4
151	53	6	f	\N	skipped	f	2026-09-21 17:52:17.144989+05:30	4	2026-09-21 17:52:18.114962+05:30	4
152	54	7	f	\N	skipped	f	2026-09-21 17:52:17.374632+05:30	4	2026-09-21 17:52:18.133648+05:30	4
150	53	7	f	\N	skipped	f	2026-09-21 17:52:17.144989+05:30	4	2026-09-21 17:52:18.14607+05:30	4
155	55	6	f	\N	skipped	f	2026-09-21 17:57:15.067533+05:30	4	2026-09-21 17:57:32.651382+05:30	4
154	55	7	f	\N	skipped	f	2026-09-21 17:57:15.067533+05:30	4	2026-09-21 17:57:32.855943+05:30	4
156	56	13	f	\N	skipped	t	2026-09-23 11:16:24.209619+05:30	2	2026-09-23 11:16:24.209619+05:30	2
157	56	14	f	\N	skipped	t	2026-09-23 11:16:24.209619+05:30	2	2026-09-23 11:16:24.209619+05:30	2
158	56	15	f	\N	skipped	t	2026-09-23 11:16:24.209619+05:30	2	2026-09-23 11:16:24.209619+05:30	2
159	56	16	f	\N	skipped	t	2026-09-23 11:16:24.209619+05:30	2	2026-09-23 11:16:24.209619+05:30	2
160	56	17	f	\N	skipped	t	2026-09-23 11:16:24.209619+05:30	2	2026-09-23 11:16:24.209619+05:30	2
161	56	18	f	\N	skipped	t	2026-09-23 11:16:24.209619+05:30	2	2026-09-23 11:16:24.209619+05:30	2
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notifications (id, title, body, type, target_type, target_id, reference_type, reference_id, is_active, created_at, created_by, updated_at, updated_by, attachment_file_id) FROM stdin;
1	Internal Assessment 1 marks: CS3301	Internal Assessment 1 marks for CS3301 Data Structures (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	1	t	2026-09-21 13:49:54.604178+05:30	4	2026-09-21 13:49:54.604178+05:30	4	\N
2	Internal Assessment 2 marks: CS3301	Internal Assessment 2 marks for CS3301 Data Structures (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	1	t	2026-09-21 13:49:54.625047+05:30	4	2026-09-21 13:49:54.625047+05:30	4	\N
3	End Semester marks: CS3301	End Semester marks for CS3301 Data Structures (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	1	t	2026-09-21 13:49:54.645052+05:30	4	2026-09-21 13:49:54.645052+05:30	4	\N
4	Internal Assessment 1 marks: CS3311	Internal Assessment 1 marks for CS3311 Data Structures Lab (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	2	t	2026-09-21 13:49:54.659476+05:30	4	2026-09-21 13:49:54.659476+05:30	4	\N
5	Internal Assessment 2 marks: CS3311	Internal Assessment 2 marks for CS3311 Data Structures Lab (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	2	t	2026-09-21 13:49:54.672698+05:30	4	2026-09-21 13:49:54.672698+05:30	4	\N
6	End Semester marks: CS3311	End Semester marks for CS3311 Data Structures Lab (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	2	t	2026-09-21 13:49:54.688264+05:30	4	2026-09-21 13:49:54.688264+05:30	4	\N
7	Internal Assessment 1 marks: MA3301	Internal Assessment 1 marks for MA3301 Discrete Mathematics (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	3	t	2026-09-21 13:49:54.699321+05:30	4	2026-09-21 13:49:54.699321+05:30	4	\N
8	Internal Assessment 2 marks: MA3301	Internal Assessment 2 marks for MA3301 Discrete Mathematics (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	3	t	2026-09-21 13:49:54.708396+05:30	4	2026-09-21 13:49:54.708396+05:30	4	\N
9	End Semester marks: MA3301	End Semester marks for MA3301 Discrete Mathematics (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	3	t	2026-09-21 13:49:54.715977+05:30	4	2026-09-21 13:49:54.715977+05:30	4	\N
10	Skill recorded: Java	Java is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	3	t	2026-09-21 13:49:55.007154+05:30	4	2026-09-21 13:49:55.007154+05:30	4	\N
11	Skill recorded: Data Structures & Algorithms	Data Structures & Algorithms is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	14	t	2026-09-21 13:49:55.013857+05:30	4	2026-09-21 13:49:55.013857+05:30	4	\N
12	Skill recorded: SQL	SQL is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	7	t	2026-09-21 13:49:55.019942+05:30	4	2026-09-21 13:49:55.019942+05:30	4	\N
13	Skill recorded: Communication	Communication is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	23	t	2026-09-21 13:49:55.026971+05:30	4	2026-09-21 13:49:55.026971+05:30	4	\N
14	Skill recorded: Aptitude	Aptitude is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	22	t	2026-09-21 13:49:55.03497+05:30	4	2026-09-21 13:49:55.03497+05:30	4	\N
15	Skill recorded: Python	Python is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	4	t	2026-09-21 13:49:55.042563+05:30	4	2026-09-21 13:49:55.042563+05:30	4	\N
16	Skill recorded: SQL	SQL is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	7	t	2026-09-21 13:49:55.051016+05:30	4	2026-09-21 13:49:55.051016+05:30	4	\N
17	Skill recorded: Data Structures & Algorithms	Data Structures & Algorithms is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	14	t	2026-09-21 13:49:55.056801+05:30	4	2026-09-21 13:49:55.056801+05:30	4	\N
18	Skill recorded: Communication	Communication is now recorded at level 5 of 5 (Expert). Higher levels improve your placement match.	skill	user	\N	skill	23	t	2026-09-21 13:49:55.060198+05:30	4	2026-09-21 13:49:55.060198+05:30	4	\N
19	Skill recorded: Aptitude	Aptitude is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	22	t	2026-09-21 13:49:55.064743+05:30	4	2026-09-21 13:49:55.064743+05:30	4	\N
20	Skill recorded: Java	Java is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	3	t	2026-09-21 13:49:55.071813+05:30	4	2026-09-21 13:49:55.071813+05:30	4	\N
21	Skill recorded: HTML/CSS	HTML/CSS is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	13	t	2026-09-21 13:49:55.075897+05:30	4	2026-09-21 13:49:55.075897+05:30	4	\N
22	Skill recorded: JavaScript	JavaScript is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	5	t	2026-09-21 13:49:55.080868+05:30	4	2026-09-21 13:49:55.080868+05:30	4	\N
23	Skill recorded: Communication	Communication is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	23	t	2026-09-21 13:49:55.088072+05:30	4	2026-09-21 13:49:55.088072+05:30	4	\N
24	Skill recorded: Aptitude	Aptitude is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	22	t	2026-09-21 13:49:55.093354+05:30	4	2026-09-21 13:49:55.093354+05:30	4	\N
25	Skill recorded: Java	Java is now recorded at level 2 of 5 (Basic). Higher levels improve your placement match.	skill	user	\N	skill	3	t	2026-09-21 13:49:55.099726+05:30	4	2026-09-21 13:49:55.099726+05:30	4	\N
26	Skill recorded: SQL	SQL is now recorded at level 2 of 5 (Basic). Higher levels improve your placement match.	skill	user	\N	skill	7	t	2026-09-21 13:49:55.105129+05:30	4	2026-09-21 13:49:55.105129+05:30	4	\N
27	Skill recorded: Communication	Communication is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	23	t	2026-09-21 13:49:55.109216+05:30	4	2026-09-21 13:49:55.109216+05:30	4	\N
28	Skill recorded: Aptitude	Aptitude is now recorded at level 2 of 5 (Basic). Higher levels improve your placement match.	skill	user	\N	skill	22	t	2026-09-21 13:49:55.114313+05:30	4	2026-09-21 13:49:55.114313+05:30	4	\N
29	Skill recorded: Java	Java is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	3	t	2026-09-21 13:49:55.11981+05:30	4	2026-09-21 13:49:55.11981+05:30	4	\N
30	Skill recorded: Spring Boot	Spring Boot is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	11	t	2026-09-21 13:49:55.125211+05:30	4	2026-09-21 13:49:55.125211+05:30	4	\N
31	Skill recorded: SQL	SQL is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	7	t	2026-09-21 13:49:55.131326+05:30	4	2026-09-21 13:49:55.131326+05:30	4	\N
32	Skill recorded: Aptitude	Aptitude is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	22	t	2026-09-21 13:49:55.136599+05:30	4	2026-09-21 13:49:55.136599+05:30	4	\N
33	Skill recorded: Python	Python is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	4	t	2026-09-21 13:49:55.140473+05:30	4	2026-09-21 13:49:55.140473+05:30	4	\N
34	Skill recorded: Machine Learning	Machine Learning is now recorded at level 2 of 5 (Basic). Higher levels improve your placement match.	skill	user	\N	skill	15	t	2026-09-21 13:49:55.146664+05:30	4	2026-09-21 13:49:55.146664+05:30	4	\N
35	Skill recorded: Communication	Communication is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	23	t	2026-09-21 13:49:55.152099+05:30	4	2026-09-21 13:49:55.152099+05:30	4	\N
36	Skill recorded: Aptitude	Aptitude is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	22	t	2026-09-21 13:49:55.15634+05:30	4	2026-09-21 13:49:55.15634+05:30	4	\N
37	Skill recorded: Embedded C	Embedded C is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	19	t	2026-09-21 13:49:55.161657+05:30	5	2026-09-21 13:49:55.161657+05:30	5	\N
38	Skill recorded: C	C is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	1	t	2026-09-21 13:49:55.166322+05:30	5	2026-09-21 13:49:55.166322+05:30	5	\N
39	Skill recorded: MATLAB	MATLAB is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	20	t	2026-09-21 13:49:55.171016+05:30	5	2026-09-21 13:49:55.171016+05:30	5	\N
40	Skill recorded: Communication	Communication is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	23	t	2026-09-21 13:49:55.17541+05:30	5	2026-09-21 13:49:55.17541+05:30	5	\N
41	Skill recorded: Aptitude	Aptitude is now recorded at level 4 of 5 (Advanced). Higher levels improve your placement match.	skill	user	\N	skill	22	t	2026-09-21 13:49:55.181203+05:30	5	2026-09-21 13:49:55.181203+05:30	5	\N
42	Skill recorded: C	C is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	1	t	2026-09-21 13:49:55.185518+05:30	5	2026-09-21 13:49:55.185518+05:30	5	\N
43	Skill recorded: Embedded C	Embedded C is now recorded at level 2 of 5 (Basic). Higher levels improve your placement match.	skill	user	\N	skill	19	t	2026-09-21 13:49:55.190973+05:30	5	2026-09-21 13:49:55.190973+05:30	5	\N
44	Skill recorded: Aptitude	Aptitude is now recorded at level 3 of 5 (Intermediate). Higher levels improve your placement match.	skill	user	\N	skill	22	t	2026-09-21 13:49:55.196428+05:30	5	2026-09-21 13:49:55.196428+05:30	5	\N
45	New drive: Zoho - Software Developer	Zoho is hiring for Software Developer at 8.40 LPA. Apply by 05 Nov 2026. You are eligible. Open Placement Drives for details.	placement	user	\N	job_role_open	1	t	2026-09-21 13:49:55.254121+05:30	2	2026-09-21 13:49:55.254121+05:30	2	\N
46	New drive: TCS - Ninja - Assistant System Engineer	TCS is hiring for Ninja - Assistant System Engineer at 3.60 LPA. Apply by 10 Oct 2026. You are eligible. Open Placement Drives for details.	placement	user	\N	job_role_open	2	t	2026-09-21 13:49:55.271926+05:30	2	2026-09-21 13:49:55.271926+05:30	2	\N
47	Shortlisted: Zoho - Software Developer	Shortlisted for Software Developer at Zoho (8.40 LPA). Watch for the next round details from the placement cell.	placement	user	\N	job_role	1	t	2026-09-21 13:49:55.327831+05:30	2	2026-09-21 13:49:55.327831+05:30	2	\N
48	Shortlisted: TCS - Ninja - Assistant System Engineer	Shortlisted for Ninja - Assistant System Engineer at TCS (3.60 LPA). Watch for the next round details from the placement cell.	placement	user	\N	job_role	2	t	2026-09-21 13:49:55.339625+05:30	2	2026-09-21 13:49:55.339625+05:30	2	\N
49	Zoho: moved to the next round	Arun Kumar has moved to the next round for Software Developer at Zoho.	placement	user	\N	job_role	1	t	2026-09-21 13:49:55.360288+05:30	2	2026-09-21 13:49:55.360288+05:30	2	\N
50	Selected: Zoho - Software Developer	Congratulations! Arun Kumar has been selected for Software Developer at Zoho with a package of 8.40 LPA.	placement	user	\N	job_role	1	t	2026-09-21 13:49:55.371635+05:30	2	2026-09-21 13:49:55.371635+05:30	2	\N
51	Welcome to Skills Analyzer	Marks, skills and placement updates will appear here. Keep your mobile number up to date for OTP login.	general	all	\N	\N	\N	t	2026-09-21 13:49:55.881893+05:30	1	2026-09-21 13:49:55.881893+05:30	1	\N
52	IA2 timetable	Internal Assessment 2 starts on 6 Oct. Timetable is on the notice board.	general	class	1	\N	\N	t	2026-09-21 13:55:00.701839+05:30	3	2026-09-21 13:55:00.701839+05:30	3	\N
53	Document rejected	Your Transfer certificate (Transfer certificate) was rejected: Blurry. Please upload it again.	system	user	\N	student_document	1	t	2026-09-21 17:52:17.144989+05:30	4	2026-09-21 17:52:17.144989+05:30	4	\N
54	Document verified	Your Transfer certificate (Transfer certificate) was verified.	system	user	\N	student_document	1	t	2026-09-21 17:52:17.374632+05:30	4	2026-09-21 17:52:17.374632+05:30	4	\N
55	Document verified	Your 10th mark sheet (10th mark sheet) was verified.	system	user	\N	student_document	4	t	2026-09-21 17:57:15.067533+05:30	4	2026-09-21 17:57:15.067533+05:30	4	\N
56	Internal Assessment 1 marks: CS3301	Internal Assessment 1 marks for CS3301 Data Structures (Semester 3) are available. Open Marks to view them.	marks	user	\N	marks	1	t	2026-09-23 11:16:24.209619+05:30	2	2026-09-23 11:16:24.209619+05:30	2	\N
\.


--
-- Data for Name: permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.permissions (id, module, action, slug, description, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	user	view	user.view	View user	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
2	user	create	user.create	Create user	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
3	user	update	user.update	Update user	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
4	user	delete	user.delete	Delete user	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
5	role	view	role.view	View role	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
6	role	create	role.create	Create role	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
7	role	update	role.update	Update role	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
8	role	delete	role.delete	Delete role	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
9	permission	view	permission.view	View permission	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
10	permission	create	permission.create	Create permission	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
11	permission	update	permission.update	Update permission	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
12	permission	delete	permission.delete	Delete permission	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
13	department	view	department.view	View department	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
14	department	create	department.create	Create department	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
15	department	update	department.update	Update department	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
16	department	delete	department.delete	Delete department	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
17	academic_year	view	academic_year.view	View academic year	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
18	academic_year	create	academic_year.create	Create academic year	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
19	academic_year	update	academic_year.update	Update academic year	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
20	academic_year	delete	academic_year.delete	Delete academic year	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
21	subject	view	subject.view	View subject	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
22	subject	create	subject.create	Create subject	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
23	subject	update	subject.update	Update subject	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
24	subject	delete	subject.delete	Delete subject	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
25	exam_type	view	exam_type.view	View exam type	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
26	exam_type	create	exam_type.create	Create exam type	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
27	exam_type	update	exam_type.update	Update exam type	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
28	exam_type	delete	exam_type.delete	Delete exam type	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
29	class	view	class.view	View class	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
30	class	create	class.create	Create class	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
31	class	update	class.update	Update class	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
32	class	delete	class.delete	Delete class	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
33	student	view	student.view	View student	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
34	student	create	student.create	Create student	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
35	student	update	student.update	Update student	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
36	student	delete	student.delete	Delete student	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
37	staff	view	staff.view	View staff	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
38	staff	create	staff.create	Create staff	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
39	staff	update	staff.update	Update staff	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
40	staff	delete	staff.delete	Delete staff	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
41	parent	view	parent.view	View parent	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
42	parent	create	parent.create	Create parent	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
43	parent	update	parent.update	Update parent	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
44	parent	delete	parent.delete	Delete parent	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
45	marks	view	marks.view	View marks	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
46	marks	create	marks.create	Create marks	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
47	marks	update	marks.update	Update marks	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
48	marks	delete	marks.delete	Delete marks	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
49	skill	view	skill.view	View skill	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
50	skill	create	skill.create	Create skill	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
51	skill	update	skill.update	Update skill	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
52	skill	delete	skill.delete	Delete skill	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
53	student_skill	view	student_skill.view	View student skill	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
54	student_skill	create	student_skill.create	Create student skill	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
55	student_skill	update	student_skill.update	Update student skill	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
56	student_skill	delete	student_skill.delete	Delete student skill	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
57	company	view	company.view	View company	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
58	company	create	company.create	Create company	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
59	company	update	company.update	Update company	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
60	company	delete	company.delete	Delete company	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
61	job_role	view	job_role.view	View job role	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
62	job_role	create	job_role.create	Create job role	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
63	job_role	update	job_role.update	Update job role	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
64	job_role	delete	job_role.delete	Delete job role	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
65	placement	view	placement.view	View placement	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
66	placement	create	placement.create	Create placement	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
67	placement	update	placement.update	Update placement	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
68	placement	delete	placement.delete	Delete placement	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
69	skill_analyzer	view	skill_analyzer.view	View skill analyzer	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
70	skill_analyzer	create	skill_analyzer.create	Create skill analyzer	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
71	skill_analyzer	update	skill_analyzer.update	Update skill analyzer	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
72	skill_analyzer	delete	skill_analyzer.delete	Delete skill analyzer	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
73	notification	view	notification.view	View notification	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
74	notification	create	notification.create	Create notification	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
75	notification	update	notification.update	Update notification	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
76	notification	delete	notification.delete	Delete notification	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
77	bulk_upload	view	bulk_upload.view	View bulk upload	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
78	bulk_upload	create	bulk_upload.create	Create bulk upload	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
79	bulk_upload	update	bulk_upload.update	Update bulk upload	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
80	bulk_upload	delete	bulk_upload.delete	Delete bulk upload	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
81	subject_allocation	view	subject_allocation.view	View subject allocation	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
82	subject_allocation	create	subject_allocation.create	Create subject allocation	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
83	subject_allocation	delete	subject_allocation.delete	Delete subject allocation	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
84	promotion	view	promotion.view	View semester change, promotion history and alumni	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
85	promotion	create	promotion.create	Change semesters, promote years, discontinue and re-admit students	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
86	report	view	report.view	View the analytics dashboard (pass %, CGPA spread, skill gaps, placement trend)	t	2026-09-21 15:33:25.074512+05:30	\N	2026-09-21 15:33:25.074512+05:30	\N
87	document	view	document.view	View student documents	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
88	document	create	document.create	Upload student documents	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
89	document	verify	document.verify	Verify or reject student documents	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
90	document	delete	document.delete	Delete student documents	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
91	career	view	career.view	View the career catalogue and career matches	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
92	career	create	career.create	Add careers and their required skills	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
93	career	update	career.update	Edit careers, required skills and courses	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
94	career	delete	career.delete	Remove careers and courses	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
95	career	run	career.run	Recompute career matches for students	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
96	config	view	config.view	View scoring weights and settings	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
97	config	update	config.update	Change scoring weights and settings	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
\.


--
-- Data for Name: placement_applications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.placement_applications (id, job_role_id, student_id, match_score, status, remarks, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
4	2	8	77.10	shortlisted	\N	t	2026-09-21 13:49:55.336971+05:30	2	2026-09-21 13:49:55.336971+05:30	2
1	1	6	98.80	selected	Cleared technical round	t	2026-09-21 13:49:55.32449+05:30	2	2026-09-21 13:49:55.364244+05:30	2
2	2	6	98.80	applied	\N	t	2026-09-21 13:49:55.336971+05:30	2	2026-09-21 13:49:55.381783+05:30	2
3	2	9	90.40	applied	\N	t	2026-09-21 13:49:55.336971+05:30	2	2026-09-21 13:49:55.389798+05:30	2
\.


--
-- Data for Name: placement_records; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.placement_records (id, student_id, company_id, job_role_id, application_id, package_lpa, offer_date, joining_date, offer_letter_url, is_active, created_at, created_by, updated_at, updated_by, offer_letter_file_id) FROM stdin;
1	6	1	1	1	8.40	2026-09-21	\N	\N	t	2026-09-21 13:49:55.364244+05:30	2	2026-09-21 13:49:55.364244+05:30	2	\N
\.


--
-- Data for Name: promotion_runs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.promotion_runs (id, from_year_id, to_year_id, promoted_count, detained_count, passed_out_count, classes_created, summary, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
\.


--
-- Data for Name: role_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.role_permissions (id, role_id, permission_id, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	1	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
2	1	2	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
3	1	3	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
4	1	4	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
5	1	5	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
6	1	6	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
7	1	7	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
8	1	8	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
9	1	9	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
10	1	10	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
11	1	11	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
12	1	12	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
13	1	13	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
14	1	14	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
15	1	15	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
16	1	16	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
17	1	17	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
18	1	18	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
19	1	19	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
20	1	20	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
21	1	21	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
22	1	22	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
23	1	23	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
24	1	24	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
25	1	25	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
26	1	26	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
27	1	27	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
28	1	28	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
29	1	29	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
30	1	30	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
31	1	31	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
32	1	32	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
33	1	33	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
34	1	34	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
35	1	35	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
36	1	36	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
37	1	37	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
38	1	38	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
39	1	39	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
40	1	40	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
41	1	41	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
42	1	42	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
43	1	43	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
44	1	44	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
45	1	45	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
46	1	46	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
47	1	47	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
48	1	48	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
49	1	49	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
50	1	50	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
51	1	51	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
52	1	52	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
53	1	53	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
54	1	54	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
55	1	55	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
56	1	56	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
57	1	57	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
58	1	58	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
59	1	59	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
60	1	60	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
61	1	61	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
62	1	62	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
63	1	63	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
64	1	64	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
65	1	65	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
66	1	66	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
67	1	67	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
68	1	68	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
69	1	69	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
70	1	70	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
71	1	71	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
72	1	72	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
73	1	73	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
74	1	74	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
75	1	75	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
76	1	76	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
77	1	77	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
78	1	78	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
79	1	79	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
80	1	80	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
81	2	13	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
82	2	17	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
83	2	21	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
84	2	25	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
85	2	29	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
86	2	33	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
87	2	41	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
88	2	45	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
89	2	46	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
90	2	47	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
91	2	49	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
92	2	53	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
93	2	54	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
94	2	55	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
95	2	56	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
96	2	57	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
97	2	61	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
98	2	65	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
99	2	73	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
100	2	74	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
101	3	13	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
102	3	17	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
103	3	21	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
104	3	25	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
105	3	29	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
106	3	31	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
107	3	33	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
108	3	37	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
109	3	41	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
110	3	45	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
111	3	46	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
112	3	47	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
113	3	49	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
114	3	50	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
115	3	53	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
116	3	54	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
117	3	55	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
118	3	56	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
119	3	57	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
120	3	61	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
121	3	65	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
122	3	69	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
123	3	73	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
124	3	74	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
125	4	13	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
126	4	17	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
127	4	33	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
128	4	45	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
129	4	49	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
130	4	50	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
131	4	51	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
132	4	53	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
133	4	57	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
134	4	58	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
135	4	59	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
136	4	60	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
137	4	61	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
138	4	62	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
139	4	63	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
140	4	64	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
141	4	65	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
142	4	66	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
143	4	67	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
144	4	68	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
145	4	69	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
146	4	70	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
147	4	73	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
148	4	74	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
149	5	45	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
150	5	49	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
151	5	53	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
152	5	57	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
153	5	61	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
154	5	65	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
155	5	69	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
156	5	73	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
157	6	33	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
158	6	45	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
159	6	53	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
160	6	65	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
161	6	73	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
162	5	29	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
163	5	33	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
165	2	37	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
166	4	29	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
167	4	37	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
168	6	29	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
169	6	37	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
180	4	21	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
181	4	25	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
182	5	13	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
183	5	17	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
184	5	21	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
185	5	25	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
186	6	13	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
187	6	17	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
188	6	21	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
189	6	25	t	2026-09-21 13:49:27.262585+05:30	\N	2026-09-21 13:49:27.262585+05:30	\N
190	1	81	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
191	3	81	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
192	1	82	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
193	3	82	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
194	1	83	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
195	3	83	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
196	2	81	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
197	4	81	t	2026-09-21 13:49:27.275837+05:30	\N	2026-09-21 13:49:27.275837+05:30	\N
199	6	49	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
200	6	57	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
201	6	61	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
202	3	70	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
211	1	84	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
212	1	85	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
213	3	84	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
214	1	86	t	2026-09-21 15:33:25.074512+05:30	\N	2026-09-21 15:33:25.074512+05:30	\N
215	2	86	t	2026-09-21 15:33:25.074512+05:30	\N	2026-09-21 15:33:25.074512+05:30	\N
216	3	86	t	2026-09-21 15:33:25.074512+05:30	\N	2026-09-21 15:33:25.074512+05:30	\N
217	4	86	t	2026-09-21 15:33:25.074512+05:30	\N	2026-09-21 15:33:25.074512+05:30	\N
218	7	1	f	2026-09-21 15:52:56.779689+05:30	1	2026-09-21 15:52:57.563527+05:30	1
219	7	2	f	2026-09-21 15:52:56.779689+05:30	1	2026-09-21 15:52:57.563527+05:30	1
220	8	1	f	2026-09-21 15:53:49.632527+05:30	1	2026-09-21 15:53:50.688591+05:30	1
221	8	2	f	2026-09-21 15:53:49.632527+05:30	1	2026-09-21 15:53:50.688591+05:30	1
222	1	87	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
223	2	87	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
224	3	87	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
225	4	87	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
226	5	87	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
227	6	87	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
228	1	88	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
229	2	88	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
230	3	88	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
231	5	88	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
232	1	89	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
233	2	89	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
234	3	89	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
235	1	90	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
236	2	90	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
237	3	90	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
238	5	90	t	2026-09-21 17:23:16.860772+05:30	\N	2026-09-21 17:23:16.860772+05:30	\N
239	1	91	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
240	1	92	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
241	1	93	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
242	1	94	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
243	1	95	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
244	1	96	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
245	1	97	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
246	3	91	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
247	4	91	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
248	3	92	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
249	4	92	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
250	3	93	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
251	4	93	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
252	3	95	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
253	4	95	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
254	3	96	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
255	4	96	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
256	2	91	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
257	2	95	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
258	5	91	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
259	6	91	t	2026-10-03 15:19:29.317019+05:30	\N	2026-10-03 15:19:29.317019+05:30	\N
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.roles (id, name, slug, description, is_system, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	Admin	admin	Full access to everything	t	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
2	Staff	staff	Teaching staff: own classes, marks, student skills	t	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
3	HOD	hod	Head of department: department-wide view	t	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
4	Placement Officer	placement_officer	Companies, drives, skill analyzer, shortlisting	t	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
5	Student	student	Own profile, marks, skills and eligible drives	t	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
6	Parent	parent	Linked children's marks, placement and notices	t	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
7	Lab Assistant	lab_assistant	\N	f	f	2026-09-21 15:52:56.775669+05:30	1	2026-09-21 15:52:58.55869+05:30	1
8	Lab Assistant	lab_assistant	\N	f	f	2026-09-21 15:53:49.61076+05:30	1	2026-09-21 15:53:51.686134+05:30	1
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.schema_migrations (version, applied_at) FROM stdin;
000001_init_schema	2026-09-21 13:49:26.940788+05:30
000002_seed_masters_rbac	2026-09-21 13:49:27.230198+05:30
000003_phase2_access	2026-09-21 13:49:27.262585+05:30
000004_marks	2026-09-21 13:49:27.275837+05:30
000005_placement	2026-09-21 13:49:27.304502+05:30
000006_notifications	2026-09-21 13:49:27.31175+05:30
000007_lifecycle	2026-09-21 14:52:13.912825+05:30
000008_reports	2026-09-21 15:33:25.074512+05:30
000009_files	2026-09-21 17:23:16.860772+05:30
000010_skill_model	2026-10-03 15:19:29.317019+05:30
\.


--
-- Data for Name: semesters; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.semesters (id, name, sem_no, year_level_id, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	Semester 2	2	1	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
2	Semester 1	1	1	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
3	Semester 4	4	2	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
4	Semester 3	3	2	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
5	Semester 6	6	3	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
6	Semester 5	5	3	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
7	Semester 8	8	4	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
8	Semester 7	7	4	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
\.


--
-- Data for Name: skill_match_results; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.skill_match_results (id, job_role_id, student_id, skill_score, academic_score, final_score, matched_skills, missing_skills, is_eligible, ineligible_reason, computed_at, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
91	1	6	100.00	96.00	98.80	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 4, "required_score": 80}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[]	t	\N	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
92	1	8	66.67	82.00	71.27	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 5, "student_score": 100, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}]	[{"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}]	f	Needs Java at level 4 (has 0)	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
93	1	9	41.67	68.00	49.57	[{"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 4, "required_score": 80}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 6.80 is below 7.00\nNeeds Data Structures & Algorithms at level 3 (has 0)\nNeeds Java at level 4 (has 3)	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
94	1	11	44.44	60.00	49.11	[{"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 2, "student_score": 40, "required_level": 4, "required_score": 80}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 2, "student_score": 40, "required_level": 3, "required_score": 60}]	f	CGPA 6.00 is below 7.00\n1 backlog(s), at most 0 allowed\nNeeds Data Structures & Algorithms at level 3 (has 0)\nNeeds Java at level 4 (has 2)	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
95	1	13	50.00	0.00	35.00	[{"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 4, "required_score": 80}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 7.00\nNeeds Data Structures & Algorithms at level 3 (has 0)	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
96	1	15	16.67	0.00	11.67	[{"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}]	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 7.00\nNeeds Data Structures & Algorithms at level 3 (has 0)\nNeeds Java at level 4 (has 0)	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
97	1	17	0.00	0.00	0.00	[]	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 7.00\nNeeds Data Structures & Algorithms at level 3 (has 0)\nNeeds Java at level 4 (has 0)	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
98	1	19	0.00	0.00	0.00	[]	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 7.00\nNeeds Data Structures & Algorithms at level 3 (has 0)\nNeeds Java at level 4 (has 0)	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
99	1	21	0.00	0.00	0.00	[]	[{"name": "Data Structures & Algorithms", "weight": 2, "skill_id": 14, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 2, "skill_id": 3, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 7.00\nNeeds Data Structures & Algorithms at level 3 (has 0)\nNeeds Java at level 4 (has 0)	2026-10-03 15:34:47.522623+05:30	t	2026-10-03 15:34:47.522853+05:30	1	2026-10-03 15:34:47.522853+05:30	1
100	3	8	100.00	82.00	94.60	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 5, "student_score": 100, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}]	[]	t	\N	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
101	3	6	75.00	96.00	81.30	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 4, "required_score": 80}]	[{"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	Already placed at 8.40 LPA (Zoho), only higher packages allowed	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
102	3	11	52.08	60.00	54.46	[]	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 2, "student_score": 40, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 2, "student_score": 40, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 6.00 is below 6.50\n1 backlog(s), at most 0 allowed\nNeeds Aptitude at level 3 (has 2)\nNeeds SQL at level 3 (has 2)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
103	3	15	75.00	0.00	52.50	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.50\nNeeds SQL at level 3 (has 0)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
104	3	9	43.75	68.00	51.02	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	Needs SQL at level 3 (has 0)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
105	3	13	50.00	0.00	35.00	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.50	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
106	3	23	43.75	0.00	30.62	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}]	[{"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.50\nNeeds SQL at level 3 (has 0)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
107	3	25	25.00	0.00	17.50	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.50\nNeeds SQL at level 3 (has 0)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
108	3	17	0.00	0.00	0.00	[]	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.50\nNeeds Aptitude at level 3 (has 0)\nNeeds SQL at level 3 (has 0)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
109	3	19	0.00	0.00	0.00	[]	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.50\nNeeds Aptitude at level 3 (has 0)\nNeeds SQL at level 3 (has 0)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
110	3	21	0.00	0.00	0.00	[]	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.50\nNeeds Aptitude at level 3 (has 0)\nNeeds SQL at level 3 (has 0)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
111	3	27	0.00	0.00	0.00	[]	[{"name": "Aptitude", "weight": 1, "skill_id": 22, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "SQL", "weight": 1, "skill_id": 7, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 4, "required_score": 80}, {"name": "Python", "weight": 1, "skill_id": 4, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.50\nNeeds Aptitude at level 3 (has 0)\nNeeds SQL at level 3 (has 0)	2026-10-03 15:34:56.358839+05:30	t	2026-10-03 15:34:56.359358+05:30	1	2026-10-03 15:34:56.359358+05:30	1
124	2	9	100.00	68.00	90.40	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 2, "required_score": 40}]	[]	t	\N	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
125	2	8	75.00	82.00	77.10	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 5, "student_score": 100, "required_level": 3, "required_score": 60}]	[{"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 2, "required_score": 40}]	t	\N	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
126	2	6	100.00	96.00	98.80	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 2, "required_score": 40}]	[]	f	Already placed at 8.40 LPA (Zoho), only higher packages allowed	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
127	2	11	83.33	60.00	76.33	[{"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 2, "student_score": 40, "required_level": 2, "required_score": 40}]	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 2, "student_score": 40, "required_level": 3, "required_score": 60}]	f	Needs Aptitude at level 3 (has 2)	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
128	2	13	75.00	0.00	52.50	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 2, "required_score": 40}]	[{"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}]	f	CGPA 0.00 is below 6.00	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
129	2	15	75.00	0.00	52.50	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}]	[{"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 2, "required_score": 40}]	f	CGPA 0.00 is below 6.00	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
130	2	23	75.00	0.00	52.50	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 4, "student_score": 80, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 2, "required_score": 40}]	f	CGPA 0.00 is below 6.00	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
131	2	25	50.00	0.00	35.00	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 3, "student_score": 60, "required_level": 3, "required_score": 60}]	[{"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 2, "required_score": 40}]	f	CGPA 0.00 is below 6.00	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
132	2	17	0.00	0.00	0.00	[]	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 2, "required_score": 40}]	f	CGPA 0.00 is below 6.00\nNeeds Aptitude at level 3 (has 0)	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
133	2	19	0.00	0.00	0.00	[]	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 2, "required_score": 40}]	f	CGPA 0.00 is below 6.00\nNeeds Aptitude at level 3 (has 0)	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
134	2	21	0.00	0.00	0.00	[]	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 2, "required_score": 40}]	f	CGPA 0.00 is below 6.00\nNeeds Aptitude at level 3 (has 0)	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
135	2	27	0.00	0.00	0.00	[]	[{"name": "Aptitude", "weight": 2, "skill_id": 22, "is_mandatory": true, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Communication", "weight": 1, "skill_id": 23, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 3, "required_score": 60}, {"name": "Java", "weight": 1, "skill_id": 3, "is_mandatory": false, "student_level": 0, "student_score": 0, "required_level": 2, "required_score": 40}]	f	CGPA 0.00 is below 6.00\nNeeds Aptitude at level 3 (has 0)	2026-10-05 11:14:38.576309+05:30	t	2026-10-05 11:14:38.576785+05:30	1	2026-10-05 11:14:38.576785+05:30	1
\.


--
-- Data for Name: skill_scores; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.skill_scores (id, student_id, skill_id, source, score, detail, computed_at, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
187	6	3	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
188	6	14	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
189	6	7	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
190	6	23	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
191	6	22	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
192	8	4	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
193	8	7	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
194	8	14	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
195	8	23	declared	100.00	{"entered_as": "assessment", "proficiency": 5}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
196	8	22	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
197	9	3	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
198	9	13	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
199	9	5	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
200	9	23	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
201	9	22	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
202	11	3	declared	40.00	{"entered_as": "assessment", "proficiency": 2}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
203	11	7	declared	40.00	{"entered_as": "assessment", "proficiency": 2}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
204	11	23	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
205	11	22	declared	40.00	{"entered_as": "assessment", "proficiency": 2}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
206	13	3	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
207	13	11	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
208	13	7	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
209	13	22	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
210	15	4	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
211	15	15	declared	40.00	{"entered_as": "assessment", "proficiency": 2}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
212	15	23	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
213	15	22	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
28	23	19	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
29	23	1	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
30	23	20	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
31	23	23	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
32	23	22	declared	80.00	{"entered_as": "assessment", "proficiency": 4}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
33	25	1	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
34	25	19	declared	40.00	{"entered_as": "assessment", "proficiency": 2}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
35	25	22	declared	60.00	{"entered_as": "assessment", "proficiency": 3}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
214	6	14	academic	94.00	{"subjects": [{"weight": 1.00, "percent": 94.00, "subject_id": 1}]}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
215	8	14	academic	76.00	{"subjects": [{"weight": 1.00, "percent": 76.00, "subject_id": 1}]}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
216	9	14	academic	63.00	{"subjects": [{"weight": 1.00, "percent": 63.00, "subject_id": 1}]}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
217	11	14	academic	55.00	{"subjects": [{"weight": 1.00, "percent": 55.00, "subject_id": 1}]}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
218	13	14	academic	96.00	{"subjects": [{"weight": 1.00, "percent": 96.00, "subject_id": 1}]}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
219	15	14	academic	84.00	{"subjects": [{"weight": 1.00, "percent": 84.00, "subject_id": 1}]}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
220	6	3	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
221	6	7	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
222	6	14	blended	89.33	{"scores": {"academic": 94.00, "declared": 80.00}, "weights": {"academic": 0.20, "declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
223	6	22	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
224	6	23	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
225	8	4	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
226	8	7	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
227	8	14	blended	70.67	{"scores": {"academic": 76.00, "declared": 60.00}, "weights": {"academic": 0.20, "declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
228	8	22	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
229	8	23	blended	100.00	{"scores": {"declared": 100.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
230	9	3	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
231	9	5	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
232	9	13	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
233	9	14	blended	63.00	{"scores": {"academic": 63.00}, "weights": {"academic": 0.20}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
234	9	22	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
235	9	23	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
236	11	3	blended	40.00	{"scores": {"declared": 40.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
237	11	7	blended	40.00	{"scores": {"declared": 40.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
238	11	14	blended	55.00	{"scores": {"academic": 55.00}, "weights": {"academic": 0.20}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
239	11	22	blended	40.00	{"scores": {"declared": 40.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
240	11	23	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
63	23	1	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
64	23	19	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
65	23	20	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
66	23	22	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
67	23	23	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
68	25	1	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
69	25	19	blended	40.00	{"scores": {"declared": 40.00}, "weights": {"declared": 0.10}}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
70	25	22	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:19:29.317019+05:30	t	2026-10-03 15:19:29.317019+05:30	5	2026-10-03 15:19:29.317019+05:30	5
241	13	3	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
242	13	7	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
243	13	11	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
244	13	14	blended	96.00	{"scores": {"academic": 96.00}, "weights": {"academic": 0.20}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
245	13	22	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
246	15	4	blended	60.00	{"scores": {"declared": 60.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
247	15	14	blended	84.00	{"scores": {"academic": 84.00}, "weights": {"academic": 0.20}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
248	15	15	blended	40.00	{"scores": {"declared": 40.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
249	15	22	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
250	15	23	blended	80.00	{"scores": {"declared": 80.00}, "weights": {"declared": 0.10}}	2026-10-03 15:39:03.343344+05:30	t	2026-10-03 15:39:03.343344+05:30	1	2026-10-03 15:39:03.343344+05:30	1
\.


--
-- Data for Name: skills; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.skills (id, name, category, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	C	programming	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
2	C++	programming	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
3	Java	programming	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
4	Python	programming	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
5	JavaScript	programming	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
6	Go	programming	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
7	SQL	database	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
8	MongoDB	database	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
9	React	framework	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
10	Node.js	framework	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
11	Spring Boot	framework	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
12	Django	framework	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
13	HTML/CSS	technical	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
14	Data Structures & Algorithms	technical	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
15	Machine Learning	technical	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
16	Cloud (AWS/Azure)	tool	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
17	Git	tool	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
18	Docker	tool	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
19	Embedded C	programming	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
20	MATLAB	tool	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
21	AutoCAD	tool	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
22	Aptitude	soft_skill	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
23	Communication	soft_skill	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
24	Problem Solving	soft_skill	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
25	Teamwork	soft_skill	t	2026-09-21 13:49:27.304502+05:30	\N	2026-09-21 13:49:27.304502+05:30	\N
\.


--
-- Data for Name: staff_assignments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.staff_assignments (id, staff_id, academic_year_id, semester_id, department_id, class_id, subject_id, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	2	2	4	1	1	1	t	2026-09-21 13:49:54.565065+05:30	1	2026-09-21 13:49:54.565065+05:30	1
2	3	2	4	1	1	3	t	2026-09-21 13:49:54.574919+05:30	1	2026-09-21 13:49:54.574919+05:30	1
3	4	2	4	1	1	2	t	2026-09-21 13:49:54.580332+05:30	1	2026-09-21 13:49:54.580332+05:30	1
\.


--
-- Data for Name: staff_profiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.staff_profiles (id, user_id, employee_code, designation, qualification, joined_on, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	2	EMP001	Assistant Professor	M.E., Ph.D.	2015-06-01	t	2026-09-21 13:49:53.934507+05:30	1	2026-09-21 13:49:53.934507+05:30	1
2	3	EMP002	Professor & Head	M.E., Ph.D.	2015-06-01	t	2026-09-21 13:49:53.999828+05:30	1	2026-09-21 13:49:53.999828+05:30	1
3	4	EMP003	Assistant Professor	M.E., Ph.D.	2015-06-01	t	2026-09-21 13:49:54.059889+05:30	1	2026-09-21 13:49:54.059889+05:30	1
4	5	EMP004	Professor & Head	M.E., Ph.D.	2015-06-01	t	2026-09-21 13:49:54.120822+05:30	1	2026-09-21 13:49:54.120822+05:30	1
\.


--
-- Data for Name: student_documents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.student_documents (id, student_id, doc_type, title, file_id, status, remarks, verified_by, verified_at, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	6	transfer_certificate	Transfer certificate	8	verified	\N	4	2026-09-21 17:52:17.310422+05:30	f	2026-09-21 17:52:16.493503+05:30	6	2026-09-21 17:52:17.487689+05:30	4
2	6	id_proof	Aadhaar	9	verified	\N	4	2026-09-21 17:52:17.93736+05:30	f	2026-09-21 17:52:17.924653+05:30	4	2026-09-21 17:52:18.022794+05:30	4
3	6	marksheet_10	10th mark sheet	10	pending	\N	\N	\N	f	2026-09-21 17:52:18.063277+05:30	6	2026-09-21 17:52:18.08185+05:30	6
4	6	marksheet_10	10th mark sheet	12	verified	\N	4	2026-09-21 17:57:15.055133+05:30	f	2026-09-21 17:57:02.437408+05:30	6	2026-09-21 17:57:32.446303+05:30	1
\.


--
-- Data for Name: student_enrollments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.student_enrollments (id, student_id, class_id, academic_year_id, semester_id, status, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	6	1	2	4	studying	t	2026-09-21 13:49:54.593321+05:30	4	2026-09-21 13:49:54.593321+05:30	4
2	8	1	2	4	studying	t	2026-09-21 13:49:54.593321+05:30	4	2026-09-21 13:49:54.593321+05:30	4
3	9	1	2	4	studying	t	2026-09-21 13:49:54.593321+05:30	4	2026-09-21 13:49:54.593321+05:30	4
4	11	1	2	4	studying	t	2026-09-21 13:49:54.593321+05:30	4	2026-09-21 13:49:54.593321+05:30	4
41	17	2	2	4	studying	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
42	15	2	2	4	studying	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
43	13	2	2	4	studying	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
44	21	3	2	6	studying	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
45	19	3	2	6	studying	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
46	27	4	2	4	studying	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
47	25	4	2	4	studying	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
48	23	4	2	4	studying	t	2026-09-21 14:52:13.912825+05:30	\N	2026-09-21 14:52:13.912825+05:30	\N
52	8	1	2	3	studying	t	2026-10-01 17:35:17.353117+05:30	1	2026-10-01 17:35:17.353117+05:30	1
53	9	1	2	3	studying	t	2026-10-01 17:35:17.353117+05:30	1	2026-10-01 17:35:17.353117+05:30	1
54	11	1	2	3	studying	t	2026-10-01 17:35:17.353117+05:30	1	2026-10-01 17:35:17.353117+05:30	1
55	6	1	2	3	studying	t	2026-10-01 17:35:17.353117+05:30	1	2026-10-01 17:35:17.353117+05:30	1
\.


--
-- Data for Name: student_marks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.student_marks (id, student_id, academic_year_id, semester_id, subject_id, exam_type_id, attempt_no, marks_obtained, max_marks, grade, result, is_active, created_at, created_by, updated_at, updated_by, grade_point, class_id) FROM stdin;
1	6	2	4	1	1	1	46.00	50.00	\N	pass	t	2026-09-21 13:49:54.593321+05:30	4	2026-09-21 13:49:54.593321+05:30	4	\N	1
2	8	2	4	1	1	1	38.00	50.00	\N	pass	t	2026-09-21 13:49:54.593321+05:30	4	2026-09-21 13:49:54.593321+05:30	4	\N	1
3	9	2	4	1	1	1	30.00	50.00	\N	pass	t	2026-09-21 13:49:54.593321+05:30	4	2026-09-21 13:49:54.593321+05:30	4	\N	1
4	11	2	4	1	1	1	26.00	50.00	\N	pass	t	2026-09-21 13:49:54.593321+05:30	4	2026-09-21 13:49:54.593321+05:30	4	\N	1
5	6	2	4	1	2	1	44.00	50.00	\N	pass	t	2026-09-21 13:49:54.62211+05:30	4	2026-09-21 13:49:54.62211+05:30	4	\N	1
6	8	2	4	1	2	1	40.00	50.00	\N	pass	t	2026-09-21 13:49:54.62211+05:30	4	2026-09-21 13:49:54.62211+05:30	4	\N	1
7	9	2	4	1	2	1	33.00	50.00	\N	pass	t	2026-09-21 13:49:54.62211+05:30	4	2026-09-21 13:49:54.62211+05:30	4	\N	1
8	11	2	4	1	2	1	29.00	50.00	\N	pass	t	2026-09-21 13:49:54.62211+05:30	4	2026-09-21 13:49:54.62211+05:30	4	\N	1
9	6	2	4	1	4	1	94.00	100.00	O	pass	t	2026-09-21 13:49:54.637983+05:30	4	2026-09-21 13:49:54.637983+05:30	4	10.00	1
10	8	2	4	1	4	1	76.00	100.00	A	pass	t	2026-09-21 13:49:54.637983+05:30	4	2026-09-21 13:49:54.637983+05:30	4	8.00	1
11	9	2	4	1	4	1	63.00	100.00	B+	pass	t	2026-09-21 13:49:54.637983+05:30	4	2026-09-21 13:49:54.637983+05:30	4	7.00	1
12	11	2	4	1	4	1	55.00	100.00	C	pass	t	2026-09-21 13:49:54.637983+05:30	4	2026-09-21 13:49:54.637983+05:30	4	5.00	1
13	6	2	4	2	1	1	48.00	50.00	\N	pass	t	2026-09-21 13:49:54.656555+05:30	4	2026-09-21 13:49:54.656555+05:30	4	\N	1
14	8	2	4	2	1	1	45.00	50.00	\N	pass	t	2026-09-21 13:49:54.656555+05:30	4	2026-09-21 13:49:54.656555+05:30	4	\N	1
15	9	2	4	2	1	1	40.00	50.00	\N	pass	t	2026-09-21 13:49:54.656555+05:30	4	2026-09-21 13:49:54.656555+05:30	4	\N	1
16	11	2	4	2	1	1	38.00	50.00	\N	pass	t	2026-09-21 13:49:54.656555+05:30	4	2026-09-21 13:49:54.656555+05:30	4	\N	1
17	6	2	4	2	2	1	47.00	50.00	\N	pass	t	2026-09-21 13:49:54.667962+05:30	4	2026-09-21 13:49:54.667962+05:30	4	\N	1
18	8	2	4	2	2	1	46.00	50.00	\N	pass	t	2026-09-21 13:49:54.667962+05:30	4	2026-09-21 13:49:54.667962+05:30	4	\N	1
19	9	2	4	2	2	1	42.00	50.00	\N	pass	t	2026-09-21 13:49:54.667962+05:30	4	2026-09-21 13:49:54.667962+05:30	4	\N	1
20	11	2	4	2	2	1	41.00	50.00	\N	pass	t	2026-09-21 13:49:54.667962+05:30	4	2026-09-21 13:49:54.667962+05:30	4	\N	1
21	6	2	4	2	4	1	92.00	100.00	O	pass	t	2026-09-21 13:49:54.682179+05:30	4	2026-09-21 13:49:54.682179+05:30	4	10.00	1
22	8	2	4	2	4	1	85.00	100.00	A+	pass	t	2026-09-21 13:49:54.682179+05:30	4	2026-09-21 13:49:54.682179+05:30	4	9.00	1
23	9	2	4	2	4	1	80.00	100.00	A	pass	t	2026-09-21 13:49:54.682179+05:30	4	2026-09-21 13:49:54.682179+05:30	4	8.00	1
24	11	2	4	2	4	1	74.00	100.00	A	pass	t	2026-09-21 13:49:54.682179+05:30	4	2026-09-21 13:49:54.682179+05:30	4	8.00	1
25	6	2	4	3	1	1	41.00	50.00	\N	pass	t	2026-09-21 13:49:54.696384+05:30	4	2026-09-21 13:49:54.696384+05:30	4	\N	1
26	8	2	4	3	1	1	35.00	50.00	\N	pass	t	2026-09-21 13:49:54.696384+05:30	4	2026-09-21 13:49:54.696384+05:30	4	\N	1
27	9	2	4	3	1	1	28.00	50.00	\N	pass	t	2026-09-21 13:49:54.696384+05:30	4	2026-09-21 13:49:54.696384+05:30	4	\N	1
28	11	2	4	3	1	1	18.00	50.00	\N	fail	t	2026-09-21 13:49:54.696384+05:30	4	2026-09-21 13:49:54.696384+05:30	4	\N	1
29	6	2	4	3	2	1	45.00	50.00	\N	pass	t	2026-09-21 13:49:54.705997+05:30	4	2026-09-21 13:49:54.705997+05:30	4	\N	1
30	8	2	4	3	2	1	39.00	50.00	\N	pass	t	2026-09-21 13:49:54.705997+05:30	4	2026-09-21 13:49:54.705997+05:30	4	\N	1
31	9	2	4	3	2	1	\N	50.00	\N	absent	t	2026-09-21 13:49:54.705997+05:30	4	2026-09-21 13:49:54.705997+05:30	4	\N	1
32	11	2	4	3	2	1	21.00	50.00	\N	fail	t	2026-09-21 13:49:54.705997+05:30	4	2026-09-21 13:49:54.705997+05:30	4	\N	1
33	6	2	4	3	4	1	88.00	100.00	A+	pass	t	2026-09-21 13:49:54.71296+05:30	4	2026-09-21 13:49:54.71296+05:30	4	9.00	1
34	8	2	4	3	4	1	71.00	100.00	A	pass	t	2026-09-21 13:49:54.71296+05:30	4	2026-09-21 13:49:54.71296+05:30	4	8.00	1
35	9	2	4	3	4	1	58.00	100.00	B	pass	t	2026-09-21 13:49:54.71296+05:30	4	2026-09-21 13:49:54.71296+05:30	4	6.00	1
36	11	2	4	3	4	1	38.00	100.00	U	fail	t	2026-09-21 13:49:54.71296+05:30	4	2026-09-21 13:49:54.71296+05:30	4	0.00	1
37	13	2	4	1	1	1	48.00	50.00	\N	pass	t	2026-09-23 11:16:24.164021+05:30	2	2026-09-23 11:16:24.164021+05:30	2	\N	2
38	15	2	4	1	1	1	42.00	50.00	\N	pass	t	2026-09-23 11:16:24.164021+05:30	2	2026-09-23 11:16:24.164021+05:30	2	\N	2
39	17	2	4	1	1	1	\N	50.00	\N	absent	t	2026-09-23 11:16:24.164021+05:30	2	2026-09-23 11:16:24.164021+05:30	2	\N	2
\.


--
-- Data for Name: student_parents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.student_parents (id, student_id, parent_id, relation, is_primary, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	6	7	father	t	t	2026-09-21 13:49:54.303554+05:30	1	2026-09-21 13:49:54.303554+05:30	1
2	8	7	father	t	t	2026-09-21 13:49:54.313543+05:30	1	2026-09-21 13:49:54.313543+05:30	1
3	9	10	father	t	t	2026-09-21 13:49:54.315696+05:30	1	2026-09-21 13:49:54.315696+05:30	1
4	11	12	mother	t	t	2026-09-21 13:49:54.318052+05:30	1	2026-09-21 13:49:54.318052+05:30	1
5	13	14	father	t	t	2026-09-21 13:49:54.322194+05:30	1	2026-09-21 13:49:54.322194+05:30	1
6	15	16	father	t	t	2026-09-21 13:49:54.324726+05:30	1	2026-09-21 13:49:54.324726+05:30	1
7	17	18	mother	t	t	2026-09-21 13:49:54.32847+05:30	1	2026-09-21 13:49:54.32847+05:30	1
8	19	20	father	t	t	2026-09-21 13:49:54.330474+05:30	1	2026-09-21 13:49:54.330474+05:30	1
9	21	22	mother	t	t	2026-09-21 13:49:54.332019+05:30	1	2026-09-21 13:49:54.332019+05:30	1
10	23	24	father	t	t	2026-09-21 13:49:54.333405+05:30	1	2026-09-21 13:49:54.333405+05:30	1
11	25	26	father	t	t	2026-09-21 13:49:54.335619+05:30	1	2026-09-21 13:49:54.335619+05:30	1
12	27	28	mother	t	t	2026-09-21 13:49:54.337633+05:30	1	2026-09-21 13:49:54.337633+05:30	1
\.


--
-- Data for Name: student_profiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.student_profiles (id, user_id, register_no, admission_year, batch, current_class_id, cgpa, backlog_count, blood_group, address, resume_url, is_active, created_at, created_by, updated_at, updated_by, lifecycle_status, passed_out_year, status_remarks, resume_file_id) FROM stdin;
5	13	25CS005	2025	2025-2029	2	0.00	0	O+	\N	\N	t	2026-09-21 13:49:54.322194+05:30	1	2026-09-21 13:49:54.322194+05:30	1	studying	\N	\N	\N
6	15	25CS006	2025	2025-2029	2	0.00	0	O+	\N	\N	t	2026-09-21 13:49:54.324726+05:30	1	2026-09-21 13:49:54.324726+05:30	1	studying	\N	\N	\N
7	17	25CS007	2025	2025-2029	2	0.00	0	O+	\N	\N	t	2026-09-21 13:49:54.32847+05:30	1	2026-09-21 13:49:54.32847+05:30	1	studying	\N	\N	\N
8	19	24CS001	2024	2024-2028	3	0.00	0	O+	\N	\N	t	2026-09-21 13:49:54.330474+05:30	1	2026-09-21 13:49:54.330474+05:30	1	studying	\N	\N	\N
9	21	24CS002	2024	2024-2028	3	0.00	0	O+	\N	\N	t	2026-09-21 13:49:54.332019+05:30	1	2026-09-21 13:49:54.332019+05:30	1	studying	\N	\N	\N
10	23	25EC001	2025	2025-2029	4	0.00	0	O+	\N	\N	t	2026-09-21 13:49:54.333405+05:30	1	2026-09-21 13:49:54.333405+05:30	1	studying	\N	\N	\N
11	25	25EC002	2025	2025-2029	4	0.00	0	O+	\N	\N	t	2026-09-21 13:49:54.335619+05:30	1	2026-09-21 13:49:54.335619+05:30	1	studying	\N	\N	\N
12	27	25EC003	2025	2025-2029	4	0.00	0	O+	\N	\N	t	2026-09-21 13:49:54.337633+05:30	1	2026-09-21 13:49:54.337633+05:30	1	studying	\N	\N	\N
2	8	25CS002	2025	2025-2029	1	8.20	0	O+	\N	\N	t	2026-09-21 13:49:54.313543+05:30	1	2026-09-21 13:49:54.71296+05:30	1	studying	\N	\N	\N
3	9	25CS003	2025	2025-2029	1	6.80	0	O+	\N	\N	t	2026-09-21 13:49:54.315696+05:30	1	2026-09-21 13:49:54.71296+05:30	1	studying	\N	\N	\N
4	11	25CS004	2025	2025-2029	1	6.00	1	O+	\N	\N	t	2026-09-21 13:49:54.318052+05:30	1	2026-09-21 13:49:54.71296+05:30	1	studying	\N	\N	\N
1	6	25CS001	2025	2025-2029	1	9.60	0	O+	\N	\N	t	2026-09-21 13:49:54.303554+05:30	1	2026-09-21 17:52:15.995614+05:30	4	studying	\N	\N	\N
\.


--
-- Data for Name: student_skills; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.student_skills (id, student_id, skill_id, proficiency, source, certificate_url, remarks, is_active, created_at, created_by, updated_at, updated_by, certificate_file_id, certificate_verified, certificate_verified_by, certificate_verified_at) FROM stdin;
1	6	3	4	assessment	\N	\N	t	2026-09-21 13:49:55.005271+05:30	4	2026-09-21 13:49:55.005271+05:30	4	\N	f	\N	\N
2	6	14	4	assessment	\N	\N	t	2026-09-21 13:49:55.013378+05:30	4	2026-09-21 13:49:55.013378+05:30	4	\N	f	\N	\N
3	6	7	3	assessment	\N	\N	t	2026-09-21 13:49:55.01866+05:30	4	2026-09-21 13:49:55.01866+05:30	4	\N	f	\N	\N
4	6	23	4	assessment	\N	\N	t	2026-09-21 13:49:55.025694+05:30	4	2026-09-21 13:49:55.025694+05:30	4	\N	f	\N	\N
5	6	22	4	assessment	\N	\N	t	2026-09-21 13:49:55.033733+05:30	4	2026-09-21 13:49:55.033733+05:30	4	\N	f	\N	\N
6	8	4	4	assessment	\N	\N	t	2026-09-21 13:49:55.042032+05:30	4	2026-09-21 13:49:55.042032+05:30	4	\N	f	\N	\N
7	8	7	4	assessment	\N	\N	t	2026-09-21 13:49:55.047979+05:30	4	2026-09-21 13:49:55.047979+05:30	4	\N	f	\N	\N
8	8	14	3	assessment	\N	\N	t	2026-09-21 13:49:55.056405+05:30	4	2026-09-21 13:49:55.056405+05:30	4	\N	f	\N	\N
9	8	23	5	assessment	\N	\N	t	2026-09-21 13:49:55.059609+05:30	4	2026-09-21 13:49:55.059609+05:30	4	\N	f	\N	\N
10	8	22	4	assessment	\N	\N	t	2026-09-21 13:49:55.064072+05:30	4	2026-09-21 13:49:55.064072+05:30	4	\N	f	\N	\N
11	9	3	3	assessment	\N	\N	t	2026-09-21 13:49:55.071425+05:30	4	2026-09-21 13:49:55.071425+05:30	4	\N	f	\N	\N
12	9	13	4	assessment	\N	\N	t	2026-09-21 13:49:55.075596+05:30	4	2026-09-21 13:49:55.075596+05:30	4	\N	f	\N	\N
13	9	5	3	assessment	\N	\N	t	2026-09-21 13:49:55.080476+05:30	4	2026-09-21 13:49:55.080476+05:30	4	\N	f	\N	\N
14	9	23	3	assessment	\N	\N	t	2026-09-21 13:49:55.086943+05:30	4	2026-09-21 13:49:55.086943+05:30	4	\N	f	\N	\N
15	9	22	3	assessment	\N	\N	t	2026-09-21 13:49:55.092857+05:30	4	2026-09-21 13:49:55.092857+05:30	4	\N	f	\N	\N
16	11	3	2	assessment	\N	\N	t	2026-09-21 13:49:55.098738+05:30	4	2026-09-21 13:49:55.098738+05:30	4	\N	f	\N	\N
17	11	7	2	assessment	\N	\N	t	2026-09-21 13:49:55.104763+05:30	4	2026-09-21 13:49:55.104763+05:30	4	\N	f	\N	\N
18	11	23	3	assessment	\N	\N	t	2026-09-21 13:49:55.108811+05:30	4	2026-09-21 13:49:55.108811+05:30	4	\N	f	\N	\N
19	11	22	2	assessment	\N	\N	t	2026-09-21 13:49:55.113684+05:30	4	2026-09-21 13:49:55.113684+05:30	4	\N	f	\N	\N
20	13	3	4	assessment	\N	\N	t	2026-09-21 13:49:55.119112+05:30	4	2026-09-21 13:49:55.119112+05:30	4	\N	f	\N	\N
21	13	11	3	assessment	\N	\N	t	2026-09-21 13:49:55.124136+05:30	4	2026-09-21 13:49:55.124136+05:30	4	\N	f	\N	\N
22	13	7	3	assessment	\N	\N	t	2026-09-21 13:49:55.130971+05:30	4	2026-09-21 13:49:55.130971+05:30	4	\N	f	\N	\N
23	13	22	3	assessment	\N	\N	t	2026-09-21 13:49:55.135391+05:30	4	2026-09-21 13:49:55.135391+05:30	4	\N	f	\N	\N
24	15	4	3	assessment	\N	\N	t	2026-09-21 13:49:55.139976+05:30	4	2026-09-21 13:49:55.139976+05:30	4	\N	f	\N	\N
25	15	15	2	assessment	\N	\N	t	2026-09-21 13:49:55.146015+05:30	4	2026-09-21 13:49:55.146015+05:30	4	\N	f	\N	\N
26	15	23	4	assessment	\N	\N	t	2026-09-21 13:49:55.151355+05:30	4	2026-09-21 13:49:55.151355+05:30	4	\N	f	\N	\N
27	15	22	4	assessment	\N	\N	t	2026-09-21 13:49:55.156027+05:30	4	2026-09-21 13:49:55.156027+05:30	4	\N	f	\N	\N
28	23	19	4	assessment	\N	\N	t	2026-09-21 13:49:55.160793+05:30	5	2026-09-21 13:49:55.160793+05:30	5	\N	f	\N	\N
29	23	1	4	assessment	\N	\N	t	2026-09-21 13:49:55.165486+05:30	5	2026-09-21 13:49:55.165486+05:30	5	\N	f	\N	\N
30	23	20	3	assessment	\N	\N	t	2026-09-21 13:49:55.170646+05:30	5	2026-09-21 13:49:55.170646+05:30	5	\N	f	\N	\N
31	23	23	3	assessment	\N	\N	t	2026-09-21 13:49:55.174556+05:30	5	2026-09-21 13:49:55.174556+05:30	5	\N	f	\N	\N
32	23	22	4	assessment	\N	\N	t	2026-09-21 13:49:55.180845+05:30	5	2026-09-21 13:49:55.180845+05:30	5	\N	f	\N	\N
33	25	1	3	assessment	\N	\N	t	2026-09-21 13:49:55.184689+05:30	5	2026-09-21 13:49:55.184689+05:30	5	\N	f	\N	\N
34	25	19	2	assessment	\N	\N	t	2026-09-21 13:49:55.190647+05:30	5	2026-09-21 13:49:55.190647+05:30	5	\N	f	\N	\N
35	25	22	3	assessment	\N	\N	t	2026-09-21 13:49:55.196006+05:30	5	2026-09-21 13:49:55.196006+05:30	5	\N	f	\N	\N
\.


--
-- Data for Name: subject_skills; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.subject_skills (id, subject_id, skill_id, weight, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	7	1.00	f	2026-10-03 15:37:01.32871+05:30	1	2026-10-03 15:39:03.336811+05:30	1
2	1	14	1.00	t	2026-10-03 15:39:03.336811+05:30	1	2026-10-03 15:39:03.336811+05:30	1
\.


--
-- Data for Name: subjects; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.subjects (id, code, name, credits, subject_type, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	CS3301	Data Structures	4.0	theory	t	2026-09-21 13:49:54.138903+05:30	1	2026-09-21 13:49:54.138903+05:30	1
2	CS3311	Data Structures Lab	2.0	lab	t	2026-09-21 13:49:54.147412+05:30	1	2026-09-21 13:49:54.147412+05:30	1
3	MA3301	Discrete Mathematics	4.0	theory	t	2026-09-21 13:49:54.151444+05:30	1	2026-09-21 13:49:54.151444+05:30	1
4	CS3401	Operating Systems	4.0	theory	t	2026-09-21 13:49:54.156004+05:30	1	2026-09-21 13:49:54.156004+05:30	1
5	CS3402	Database Management Systems	4.0	theory	t	2026-09-21 13:49:54.159297+05:30	1	2026-09-21 13:49:54.159297+05:30	1
6	CS3411	DBMS Lab	2.0	lab	t	2026-09-21 13:49:54.163237+05:30	1	2026-09-21 13:49:54.163237+05:30	1
7	EC3301	Signals and Systems	4.0	theory	t	2026-09-21 13:49:54.166316+05:30	1	2026-09-21 13:49:54.166316+05:30	1
8	EC3302	Electronic Circuits	4.0	theory	t	2026-09-21 13:49:54.169489+05:30	1	2026-09-21 13:49:54.169489+05:30	1
\.


--
-- Data for Name: user_otps; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_otps (id, user_id, mobile, otp_hash, purpose, attempts, expires_at, consumed_at, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	32	9000000002	19b90ca5c478fb77ae3dfb43d91aae29edb426cbd89e45598b5e4fc417eed720	login	1	2026-09-21 15:58:03.869415+05:30	2026-09-21 15:53:04.927176+05:30	f	2026-09-21 15:53:03.873638+05:30	32	2026-09-21 15:53:04.927176+05:30	\N
2	2	9000000001	fb16d6f5c35cfeab9a92c0d5de07a9f04c6c3abe9ade0bcdb8f0ccd0b3de63d2	login	5	2026-09-21 15:58:05.758045+05:30	\N	t	2026-09-21 15:53:05.758486+05:30	2	2026-09-21 15:53:06.953745+05:30	\N
3	31	9000000002	d80896eebc760dcd25302fd1e40ae3824d76397fa1ec8552ce489b47aa520623	reset_password	0	2026-09-21 15:58:08.376439+05:30	2026-09-21 15:53:09.192476+05:30	f	2026-09-21 15:53:08.37731+05:30	31	2026-09-21 15:53:09.192476+05:30	\N
\.


--
-- Data for Name: user_roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_roles (id, user_id, role_id, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	1	1	t	2026-09-21 13:49:27.377026+05:30	1	2026-09-21 13:49:27.377026+05:30	\N
2	2	4	t	2026-09-21 13:49:53.934507+05:30	1	2026-09-21 13:49:53.934507+05:30	1
3	2	2	t	2026-09-21 13:49:53.934507+05:30	1	2026-09-21 13:49:53.934507+05:30	1
4	3	3	t	2026-09-21 13:49:53.999828+05:30	1	2026-09-21 13:49:53.999828+05:30	1
5	3	2	t	2026-09-21 13:49:53.999828+05:30	1	2026-09-21 13:49:53.999828+05:30	1
6	4	2	t	2026-09-21 13:49:54.059889+05:30	1	2026-09-21 13:49:54.059889+05:30	1
7	5	3	t	2026-09-21 13:49:54.120822+05:30	1	2026-09-21 13:49:54.120822+05:30	1
8	5	2	t	2026-09-21 13:49:54.120822+05:30	1	2026-09-21 13:49:54.120822+05:30	1
9	6	5	t	2026-09-21 13:49:54.303554+05:30	1	2026-09-21 13:49:54.303554+05:30	1
10	7	6	t	2026-09-21 13:49:54.303554+05:30	1	2026-09-21 13:49:54.303554+05:30	1
11	8	5	t	2026-09-21 13:49:54.313543+05:30	1	2026-09-21 13:49:54.313543+05:30	1
12	9	5	t	2026-09-21 13:49:54.315696+05:30	1	2026-09-21 13:49:54.315696+05:30	1
13	10	6	t	2026-09-21 13:49:54.315696+05:30	1	2026-09-21 13:49:54.315696+05:30	1
14	11	5	t	2026-09-21 13:49:54.318052+05:30	1	2026-09-21 13:49:54.318052+05:30	1
15	12	6	t	2026-09-21 13:49:54.318052+05:30	1	2026-09-21 13:49:54.318052+05:30	1
16	13	5	t	2026-09-21 13:49:54.322194+05:30	1	2026-09-21 13:49:54.322194+05:30	1
17	14	6	t	2026-09-21 13:49:54.322194+05:30	1	2026-09-21 13:49:54.322194+05:30	1
18	15	5	t	2026-09-21 13:49:54.324726+05:30	1	2026-09-21 13:49:54.324726+05:30	1
19	16	6	t	2026-09-21 13:49:54.324726+05:30	1	2026-09-21 13:49:54.324726+05:30	1
20	17	5	t	2026-09-21 13:49:54.32847+05:30	1	2026-09-21 13:49:54.32847+05:30	1
21	18	6	t	2026-09-21 13:49:54.32847+05:30	1	2026-09-21 13:49:54.32847+05:30	1
22	19	5	t	2026-09-21 13:49:54.330474+05:30	1	2026-09-21 13:49:54.330474+05:30	1
23	20	6	t	2026-09-21 13:49:54.330474+05:30	1	2026-09-21 13:49:54.330474+05:30	1
24	21	5	t	2026-09-21 13:49:54.332019+05:30	1	2026-09-21 13:49:54.332019+05:30	1
25	22	6	t	2026-09-21 13:49:54.332019+05:30	1	2026-09-21 13:49:54.332019+05:30	1
26	23	5	t	2026-09-21 13:49:54.333405+05:30	1	2026-09-21 13:49:54.333405+05:30	1
27	24	6	t	2026-09-21 13:49:54.333405+05:30	1	2026-09-21 13:49:54.333405+05:30	1
28	25	5	t	2026-09-21 13:49:54.335619+05:30	1	2026-09-21 13:49:54.335619+05:30	1
29	26	6	t	2026-09-21 13:49:54.335619+05:30	1	2026-09-21 13:49:54.335619+05:30	1
30	27	5	t	2026-09-21 13:49:54.337633+05:30	1	2026-09-21 13:49:54.337633+05:30	1
31	28	6	t	2026-09-21 13:49:54.337633+05:30	1	2026-09-21 13:49:54.337633+05:30	1
32	31	5	t	2026-09-21 15:53:00.60808+05:30	1	2026-09-21 15:53:00.60808+05:30	1
33	32	6	t	2026-09-21 15:53:01.009119+05:30	1	2026-09-21 15:53:01.009119+05:30	1
\.


--
-- Data for Name: user_sessions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_sessions (id, user_id, refresh_token_hash, device_info, ip_address, login_method, expires_at, revoked_at, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
3	4	5cacb95d832e741bd739b27f5429a138dd06645264889478d8b807c77ceec873	python-requests/2.32.3	::1	password	2026-10-21 13:49:54.535448+05:30	\N	t	2026-09-21 13:49:54.535937+05:30	4	2026-09-21 13:49:54.535937+05:30	\N
5	4	e20539fb20cf792deadda50e992b8d1498c7706057e7a0fdd359523d36ff6dcd	python-requests/2.32.3	::1	password	2026-10-21 13:49:54.864864+05:30	\N	t	2026-09-21 13:49:54.865884+05:30	4	2026-09-21 13:49:54.865884+05:30	\N
6	5	4a38b7b6cdf1631d9d94534ea516f755a93815e7aace861e6212f1afa58b2d75	python-requests/2.32.3	::1	password	2026-10-21 13:49:54.914541+05:30	\N	t	2026-09-21 13:49:54.923315+05:30	5	2026-09-21 13:49:54.923315+05:30	\N
7	2	2f9d86cc0ae0c786de511689065ef463431e4dd78a14bce72d205c62dddb703d	python-requests/2.32.3	::1	password	2026-10-21 13:49:54.977525+05:30	\N	t	2026-09-21 13:49:54.979862+05:30	2	2026-09-21 13:49:54.979862+05:30	\N
9	6	41489c5d6c022f522a4534d2000076b7ab70a9be60a7c281cfa8c1d03c32632e	curl/8.11.0	::1	password	2026-10-21 13:52:42.678811+05:30	\N	t	2026-09-21 13:52:42.679506+05:30	6	2026-09-21 13:52:42.679506+05:30	\N
10	3	aa19902b0a5a57db3b2be2cfa40c932da53351a45b2b4864693518c561e4c171	curl/8.11.0	::1	password	2026-10-21 13:52:43.002494+05:30	\N	t	2026-09-21 13:52:43.003052+05:30	3	2026-09-21 13:52:43.003052+05:30	\N
11	7	79a1b45a2f82e63cbfa024dd043774e90749cb3af61831b996f2f437fba86d4a	curl/8.11.0	::1	password	2026-10-21 14:38:57.707218+05:30	\N	t	2026-09-21 14:38:57.708501+05:30	7	2026-09-21 14:38:57.708501+05:30	\N
15	2	ed1a9bc398cbd8db84d30b8b1084430ef11b70bb7003ef7e3ae726f4d1a0c4e4	curl/8.11.0	::1	password	2026-10-21 15:53:02.408734+05:30	\N	t	2026-09-21 15:53:02.409191+05:30	2	2026-09-21 15:53:02.409191+05:30	\N
16	32	d4774089fc61778a9a402f16b3101391b97a4c4dade7c401b44a26b77c429b8b	curl/8.11.0	::1	otp	2026-10-21 15:53:04.928682+05:30	2026-09-21 15:53:07.43859+05:30	f	2026-09-21 15:53:04.929053+05:30	32	2026-09-21 15:53:07.43859+05:30	\N
17	32	ce3bcc417266024d286ed3b56e54ed0aaff77dc13c34199dab6a30904ba96639	curl/8.11.0	::1	otp	2026-10-21 15:53:07.43953+05:30	2026-09-21 15:53:07.849156+05:30	f	2026-09-21 15:53:07.44023+05:30	32	2026-09-21 15:53:07.849156+05:30	\N
18	31	81ad6e8aa532de6b22d6c78ac2e461f0e2276ef6daa7151dc96032481923d89b	curl/8.11.0	::1	password	2026-10-21 15:53:09.806913+05:30	2026-09-21 15:53:10.524655+05:30	f	2026-09-21 15:53:09.807442+05:30	31	2026-09-21 15:53:10.524655+05:30	\N
20	2	4a73a4f0073ae545249458599fc44d8d57d557c5f305f2b7edee4b7c5d8246a2	curl/8.11.0	::1	password	2026-10-21 15:53:56.038924+05:30	\N	t	2026-09-21 15:53:56.039827+05:30	2	2026-09-21 15:53:56.039827+05:30	\N
21	31	58cc8ba2ebae46f2b3d862a3190a3853ed5f649112fc49ab7de5e0c340bc4015	curl/8.11.0	::1	password	2026-10-21 15:54:03.917752+05:30	\N	t	2026-09-21 15:54:03.918857+05:30	31	2026-09-21 15:54:03.918857+05:30	\N
22	31	70baa901dff1664a3c5159d8befa690cc9de87e75cd68bef748347077d6256a4	curl/8.11.0	::1	password	2026-10-21 15:54:05.079312+05:30	\N	t	2026-09-21 15:54:05.082148+05:30	31	2026-09-21 15:54:05.082148+05:30	\N
12	1	2275786aae532d27c713a691854b78bf4fb7ee14dd47618d7b4b73ce33b07ee7	curl/8.11.0	::1	password	2026-10-21 15:00:10.444024+05:30	2026-09-21 16:01:23.384609+05:30	f	2026-09-21 15:00:10.449336+05:30	1	2026-09-21 16:01:23.384609+05:30	\N
25	2	7bd376045de48e4126e723cda1da9ee5d40e6e0e96e7388943caa59746620750	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 16:01:27.595883+05:30	\N	t	2026-09-21 16:01:27.597932+05:30	2	2026-09-21 16:01:27.597932+05:30	\N
26	4	8e8d1eb877be69cb988663acf50bcc75a3ec018ad3b4ccc5635b6db5e6ac8ab8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 16:01:39.645748+05:30	\N	t	2026-09-21 16:01:39.650276+05:30	4	2026-09-21 16:01:39.650276+05:30	\N
28	6	ec57823516098b511d32daa3e0d400703dc2fadc249cec7a6cef7853d987a8b0	curl/8.11.0	::1	password	2026-10-21 16:03:05.956561+05:30	\N	t	2026-09-21 16:03:05.959186+05:30	6	2026-09-21 16:03:05.959186+05:30	\N
29	6	a67c4d64a17003aed15dbbc5f439facb89dd31924c34556071a2fcfed6652374	curl/8.11.0	::1	password	2026-10-21 16:15:16.557767+05:30	\N	t	2026-09-21 16:15:16.558743+05:30	6	2026-09-21 16:15:16.558743+05:30	\N
30	4	2ea5488667b089c685206f2c8e2d8158cf746c1dd8a6258baeea0c21394a3072	curl/8.11.0	::1	password	2026-10-21 16:16:08.813842+05:30	\N	t	2026-09-21 16:16:08.815837+05:30	4	2026-09-21 16:16:08.815837+05:30	\N
32	6	48b49dce353b8ec934a58266aec4c0e32408222be78682f26afeef5f55c0262b	curl/8.11.0	::1	password	2026-10-21 16:16:09.274641+05:30	\N	t	2026-09-21 16:16:09.277712+05:30	6	2026-09-21 16:16:09.277712+05:30	\N
27	6	51c6eb8648c4ca7b745738ca7f00bbc43ed5f7577bc73e5c999b6059ce59ea67	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 16:02:45.679104+05:30	2026-09-21 16:17:52.845175+05:30	f	2026-09-21 16:02:45.682772+05:30	6	2026-09-21 16:17:52.845175+05:30	\N
33	6	1e7296e65bc5ce3c5680991173509661520772662f82b49448bb018d02c4e66f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 16:17:52.847436+05:30	2026-09-21 17:56:37.619821+05:30	f	2026-09-21 16:17:52.847667+05:30	6	2026-09-21 17:56:37.619821+05:30	\N
1	1	fc76fdde4f76709d10ebf8faad9dcb0b77ae556a4670f1a3de6c983a22943b65	python-requests/2.32.3	::1	password	2026-10-21 13:49:53.857464+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 13:49:53.857897+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
2	1	b6dfc2c99bb84a848a54f1f27d9b405a12a4d389cea75243ca57b39e62d51efb	python-requests/2.32.3	::1	password	2026-10-21 13:49:54.47111+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 13:49:54.472529+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
4	1	de95dd31bcdb1b732cb0e5c5142a6626c3301cdf01d6487b4dcc8c0552de2d8b	python-requests/2.32.3	::1	password	2026-10-21 13:49:54.804083+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 13:49:54.805539+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
8	1	ac17e35eee77ead2c4ec7fc222e9319f273c87cb7c7ff2e335fd1caf3a9e6160	curl/8.11.0	::1	password	2026-10-21 13:49:55.782623+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 13:49:55.782925+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
34	4	dc6b5522ffb89466a1bcd35c7a494ed254a7ac43478f7e00e3f50f33cad57d31	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 16:21:25.201301+05:30	\N	t	2026-09-21 16:21:25.20375+05:30	4	2026-09-21 16:21:25.20375+05:30	\N
35	6	9bf6d0948b9171665d057235a1ed0fda4f48f16e93a2c11170cfae64b7252075	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 16:22:09.714105+05:30	\N	t	2026-09-21 16:22:09.714521+05:30	6	2026-09-21 16:22:09.714521+05:30	\N
37	4	73df01f2dd65e886d7314dff2cdb175b79956edd29837df164ace0dcb74dab13	Python-urllib/3.12	::1	password	2026-10-21 17:39:02.767316+05:30	\N	t	2026-09-21 17:39:02.770783+05:30	4	2026-09-21 17:39:02.770783+05:30	\N
38	6	bd0de7a9102e6b5fe99de549b150147195c1d02762d98a594a1267e50123a30d	Python-urllib/3.12	::1	password	2026-10-21 17:39:02.88205+05:30	\N	t	2026-09-21 17:39:02.883652+05:30	6	2026-09-21 17:39:02.883652+05:30	\N
39	7	0fef7ad2edb7e111bd57607f36f79e4062dea08b2d06a3af6429e99eac55463f	Python-urllib/3.12	::1	password	2026-10-21 17:39:02.998532+05:30	\N	t	2026-09-21 17:39:03.000172+05:30	7	2026-09-21 17:39:03.000172+05:30	\N
41	4	d32725735960a09d2ea7a4b761cc417d75061e1f3851eec0ab71a2f572a480bc	Python-urllib/3.12	::1	password	2026-10-21 17:52:09.882407+05:30	\N	t	2026-09-21 17:52:09.882727+05:30	4	2026-09-21 17:52:09.882727+05:30	\N
42	6	2278b7a276aa41beb34108c394d42abbd4d05c9f47cbf897926f891232efa778	Python-urllib/3.12	::1	password	2026-10-21 17:52:10.702233+05:30	\N	t	2026-09-21 17:52:10.702757+05:30	6	2026-09-21 17:52:10.702757+05:30	\N
43	7	0f663dd8ddfbccc48f004e0b3019888ad59c90f0a9243f9406fedf0f6d5824c1	Python-urllib/3.12	::1	password	2026-10-21 17:52:11.099441+05:30	\N	t	2026-09-21 17:52:11.099937+05:30	7	2026-09-21 17:52:11.099937+05:30	\N
44	6	03510cbf357ec2e0e0aa9026bf24362cad5ee227fe0ff866ca39219b20cd7ec3	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 17:56:37.62419+05:30	\N	t	2026-09-21 17:56:37.624887+05:30	6	2026-09-21 17:56:37.624887+05:30	\N
45	6	f67bc927d983a95e566398c1aeb872fcdf644e3f4c5f145a843a597f58ae08fe	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 17:56:39.005868+05:30	\N	t	2026-09-21 17:56:39.007151+05:30	6	2026-09-21 17:56:39.007151+05:30	\N
46	4	1c71a3338d6326b6050a6864dd4692c4720a11b369ced30ac1c2170493301fa0	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 17:57:10.411071+05:30	\N	t	2026-09-21 17:57:10.411784+05:30	4	2026-09-21 17:57:10.411784+05:30	\N
48	6	1d9586909c6ec66ca46a76c706585161d09d59daa99294680935862dc79184df	python-requests/2.32.3	::1	password	2026-10-21 17:57:32.618611+05:30	\N	t	2026-09-21 17:57:32.627055+05:30	6	2026-09-21 17:57:32.627055+05:30	\N
49	7	72b0a39d111af996b9fb0e9bc314fd03700b78db3ceccd4fe4506542771839e2	python-requests/2.32.3	::1	password	2026-10-21 17:57:32.840629+05:30	\N	t	2026-09-21 17:57:32.841563+05:30	7	2026-09-21 17:57:32.841563+05:30	\N
50	4	7b089e90a78da61dcdec290adca4185d0044942a4fb38757760ed9257a736d33	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 18:00:41.158345+05:30	\N	t	2026-09-21 18:00:41.159117+05:30	4	2026-09-21 18:00:41.159117+05:30	\N
51	1	d8d73309fdd7b05663fb75ec1451b82c968cefdc9cad5d75e8f798c451f5c99e	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36	::1	password	2026-10-21 18:22:02.60549+05:30	2026-09-21 18:24:01.833413+05:30	f	2026-09-21 18:22:02.610824+05:30	1	2026-09-21 18:24:01.833413+05:30	\N
52	2	41eddac588a9e98401a443ab4888fa3327e784e89a40a34b552e033ff365f0e2	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36	::1	password	2026-10-21 18:24:27.256205+05:30	2026-09-22 10:09:16.747575+05:30	f	2026-09-21 18:24:27.259049+05:30	2	2026-09-22 10:09:16.747575+05:30	\N
53	2	9d73437fc80bd7cf48155643985f22d5f9aabaad32a3432e147bcc853d824be1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36	::1	password	2026-10-22 10:09:16.810141+05:30	2026-09-23 11:15:05.317232+05:30	f	2026-09-22 10:09:16.813722+05:30	2	2026-09-23 11:15:05.317232+05:30	\N
54	2	d7260744167c05245e2f05509c2b0336b6cc410ac125b73a23404019113044a8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36	::1	password	2026-10-23 11:15:05.468774+05:30	2026-10-01 17:24:57.543+05:30	f	2026-09-23 11:15:05.474049+05:30	2	2026-10-01 17:24:57.543+05:30	\N
56	2	d04e1161198757c4d44adcda34fdb378a534408bc2f921579ed80f18afa6637f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-10-31 17:24:57.564062+05:30	2026-10-01 17:25:02.170064+05:30	f	2026-10-01 17:24:57.564499+05:30	2	2026-10-01 17:25:02.170064+05:30	\N
57	1	142154aa550f2915101bf45860b302efc8d732ed040bf90e8fb78097d99031e6	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-10-31 17:25:13.578197+05:30	2026-10-01 17:49:40.014656+05:30	f	2026-10-01 17:25:13.578517+05:30	1	2026-10-01 17:49:40.014656+05:30	\N
58	1	40901093a867fd48f0c4b96c752d2a5ae9115c488ed7168d1fa3c2e7a0e09dec	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-10-31 17:49:40.051625+05:30	2026-10-01 18:08:56.165323+05:30	f	2026-10-01 17:49:40.053706+05:30	1	2026-10-01 18:08:56.165323+05:30	\N
62	6	261c3cb07124e81737de1a0ffb6cdd21e5f7bf13e487423e87c21175ced29dcb	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.16120.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 10:50:39.134309+05:30	\N	t	2026-10-03 10:50:39.138147+05:30	6	2026-10-03 10:50:39.138147+05:30	\N
61	1	b570a59b5377a18de5fcb22f3408bdfb1ac181fbf4ad644fa82e81448a7226e9	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-02 10:37:00.195098+05:30	2026-10-03 10:52:02.157379+05:30	f	2026-10-03 10:37:00.201439+05:30	1	2026-10-03 10:52:02.157379+05:30	\N
64	1	22c37b1e1c33cabdbdd0fc08c1cb2a1238bcf2e7ce934e121177066d954c7686	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-02 10:52:02.16244+05:30	2026-10-03 11:04:48.220662+05:30	f	2026-10-03 10:52:02.163245+05:30	1	2026-10-03 11:04:48.220662+05:30	\N
36	1	999d79898e714c854292df525573ed410b33976328cc425525c4e75a23a60bd7	Python-urllib/3.12	::1	password	2026-10-21 17:39:02.622252+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 17:39:02.625282+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
63	1	91261d3fac0614ae11732f57a3c5a6d7dbe4d0fc18b7b0dd3b72260df37d80d5	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.16120.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 10:51:24.848436+05:30	2026-10-03 11:06:29.459897+05:30	f	2026-10-03 10:51:24.849614+05:30	1	2026-10-03 11:06:29.459897+05:30	\N
67	6	69445c131b882e52453d7fcfe1d7c35add050096725385d80e066c61ac7a944f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.16120.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 11:17:39.674439+05:30	\N	t	2026-10-03 11:17:39.675474+05:30	6	2026-10-03 11:17:39.675474+05:30	\N
65	1	13f347116aa750327bf8acc5c7703f87e2d26f5fb20771f828f63e010ff76687	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-02 11:04:50.274985+05:30	2026-10-03 11:22:41.720925+05:30	f	2026-10-03 11:04:50.275624+05:30	1	2026-10-03 11:22:41.720925+05:30	\N
68	1	cc5f4493f20a74cab561ba55cefba31de98a922ecf6c83f7bdc55c31800f4abb	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-02 11:22:41.737099+05:30	2026-10-03 11:48:45.447242+05:30	f	2026-10-03 11:22:41.738945+05:30	1	2026-10-03 11:48:45.447242+05:30	\N
69	1	11778cc6eb341fabdb79cfc7872764cb21a2c7fc85b0a9208154be9759253b30	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.16120.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 11:26:23.498058+05:30	2026-10-03 11:48:46.34892+05:30	f	2026-10-03 11:26:23.499709+05:30	1	2026-10-03 11:48:46.34892+05:30	\N
71	1	48ad985a2c78a35dd871752cba360d32bbd3c7f0c5dd2a6f58558ccf37e3f07a	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.16120.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 11:48:46.35349+05:30	2026-10-03 13:38:50.496193+05:30	f	2026-10-03 11:48:46.353796+05:30	1	2026-10-03 13:38:50.496193+05:30	\N
70	1	b4fff43bcb4a1dce43b04d67d31ffb81a99cffd60ad2ae681bf7c25c4419ed7e	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-02 11:48:45.544253+05:30	2026-10-03 13:38:51.290094+05:30	f	2026-10-03 11:48:45.552276+05:30	1	2026-10-03 13:38:51.290094+05:30	\N
13	1	6eb31b1b953df9d1744f5d525c45fdd5524722757c82ee41efc6b12ebd60169e	curl/8.11.0	::1	password	2026-10-21 15:03:36.631292+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 15:03:36.631417+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
14	1	f9108a65bb48b6d4d9e2078f9c10e358998f55ac9f0d642aa1f2b342449d58c3	curl/8.11.0	::1	password	2026-10-21 15:52:53.705987+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 15:52:53.708941+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
19	1	8ecf8643c09a8bac0cfb7b0c3fca1db1d6bdd9d797f17e3edffe8ec9c311b0f1	curl/8.11.0	::1	password	2026-10-21 15:53:46.511317+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 15:53:46.513505+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
23	1	145a0bf656a2d0393cd98efc3e1df179a3f53b33c757134b8b0c990082387572	curl/8.11.0	::1	password	2026-10-21 16:01:16.27342+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 16:01:16.274533+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
24	1	eaf11999dfedb3826189ef882ea6823977b4444fd6d0e4b70ef186098d52c08b	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.2553.1 Chrome/152.0.7977.76 Safari/537.36	::1	password	2026-10-21 16:01:23.38595+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 16:01:23.386271+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
31	1	925905ad50f35fcd836b12855bcb2f01f9e55686ea8d634e42fd9550f586a421	curl/8.11.0	::1	password	2026-10-21 16:16:09.030958+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 16:16:09.038601+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
40	1	f910698c89dbcd0afce9e21cc613680d42016522be0c71cbab91a43870269571	Python-urllib/3.12	::1	password	2026-10-21 17:52:08.293932+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 17:52:08.337357+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
47	1	f9b2d098ebe8f9dab41070b7f3f9f7d8121a9bdd0b6d97e44ef461dd025ba30c	python-requests/2.32.3	::1	password	2026-10-21 17:57:32.40461+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-09-21 17:57:32.405294+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
55	1	814a433dced32da1879826f6778d4fcb740957e15f5940c3db1ab0ca244ff536	curl/8.11.0	::1	password	2026-10-31 17:23:50.256292+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-10-01 17:23:50.265058+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
59	1	32ee8192191fe4aaca35be25d7a7b2b9579e71b9ea9269441116a8c422edea87	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-10-31 18:08:56.218783+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-10-01 18:08:56.220491+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
60	1	6fbe547131fb41dcfa51548e16554b2b6436e91f64205f660448d5230ef1d135	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.16120.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 10:36:37.594801+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-10-03 10:36:37.603316+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
66	1	c0b80a484b181665fd8fc70d68cc72d80bb14bfb0d8e4d99259c78fd87fa6752	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.16120.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 11:06:29.468726+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-10-03 11:06:29.47016+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
72	1	c35e225b0fd9dfccfd46819835f9ff87d3e065235485df2d404864f2141903f9	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-02 13:38:51.411553+05:30	2026-10-03 13:38:51.480509+05:30	f	2026-10-03 13:38:51.4135+05:30	1	2026-10-03 13:38:51.480509+05:30	\N
74	6	350382fbc70e333583e79e3ac1f01ebb47f5fa3baafb6981d367716da492037c	python-requests/2.32.3	::1	password	2026-11-02 14:33:19.60265+05:30	\N	t	2026-10-03 14:33:19.604308+05:30	6	2026-10-03 14:33:19.604308+05:30	\N
73	1	b62f8b4e42ad29535e5ff3f6d65b56caedcf809b061cacedd4db2afdf1ccdd5e	python-requests/2.32.3	::1	password	2026-11-02 14:33:19.149351+05:30	2026-10-03 15:34:34.679242+05:30	f	2026-10-03 14:33:19.160059+05:30	1	2026-10-03 15:34:34.679242+05:30	\N
75	1	f4c1cc82b257ce0a8df96044ab27476b84c9a671689338e0691b4570b3c8ec87	python-requests/2.32.3	::1	password	2026-11-02 15:20:59.252361+05:30	2026-10-03 15:34:34.679242+05:30	f	2026-10-03 15:20:59.253716+05:30	1	2026-10-03 15:34:34.679242+05:30	\N
76	1	f9083514c617b94efa95c74e1e8aaf9c134a8fab9242dbd9a732e561cdbf6eb5	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.19675.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 15:33:16.500463+05:30	2026-10-03 15:34:34.679242+05:30	f	2026-10-03 15:33:16.503443+05:30	1	2026-10-03 15:34:34.679242+05:30	\N
77	1	0abb1f0033623596367510723156144b7264d43fa0cc20da06763828452dd315	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-02 15:34:37.552669+05:30	2026-10-03 16:04:14.004808+05:30	f	2026-10-03 15:34:37.553295+05:30	1	2026-10-03 16:04:14.004808+05:30	\N
79	1	a612bfc7615d2923fb00607373509db5c5b8d3e573dc13f6f36665198bad7e35	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.19675.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-02 17:22:07.075206+05:30	\N	t	2026-10-03 17:22:07.083407+05:30	1	2026-10-03 17:22:07.083407+05:30	\N
78	1	5d65c5b31c85570fca99764bf30d70f9318a8ad49fde14f799651131ab5a7d24	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-02 16:04:14.147045+05:30	2026-10-05 11:03:30.49735+05:30	f	2026-10-03 16:04:14.155066+05:30	1	2026-10-05 11:03:30.49735+05:30	\N
81	6	041f5e9fe139a8f9c7998cf544549649351adb46439415428db229160f2f3c66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.19675.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-04 11:03:56.368071+05:30	\N	t	2026-10-05 11:03:56.375974+05:30	6	2026-10-05 11:03:56.375974+05:30	\N
80	1	585f32d9a441ce3fc0f082b1ba1d33cbdb283c307f6b0491c1d9df06c3b2f589	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-04 11:03:30.557858+05:30	2026-10-05 11:21:30.810657+05:30	f	2026-10-05 11:03:30.561159+05:30	1	2026-10-05 11:21:30.810657+05:30	\N
82	1	ef5ed13a73f3ff831465d7b9c1c4de1c077a4899492c6535ea0fdd46e75f22bd	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.19675.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-04 11:10:25.352362+05:30	2026-10-05 11:25:53.157849+05:30	f	2026-10-05 11:10:25.360819+05:30	1	2026-10-05 11:25:53.157849+05:30	\N
83	1	7b1d1179095f6e8c74e3bc61a190855261d743ec7569356e5a64042760840bc9	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-04 11:21:30.828087+05:30	2026-10-05 11:36:33.026164+05:30	f	2026-10-05 11:21:30.828343+05:30	1	2026-10-05 11:36:33.026164+05:30	\N
85	1	33ae1e8e6eec824173da039c9ce83b4c3e486c53fc61bba57aa52c1d508f41a7	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36	::1	password	2026-11-04 11:36:33.03368+05:30	\N	t	2026-10-05 11:36:33.033976+05:30	1	2026-10-05 11:36:33.033976+05:30	\N
84	1	3f5444e47f018e391cd0e0af1e86ac6dfd628b78006b27b2f5e8ad4478ebfee5	Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Mobile Safari/537.36	::1	password	2026-11-04 11:25:53.168696+05:30	2026-10-05 11:40:56.030982+05:30	f	2026-10-05 11:25:53.169621+05:30	1	2026-10-05 11:40:56.030982+05:30	\N
86	1	89531ae42d69ba0994d8d159007ff15b68f1892c8c6baaaaa0ba4c6dc6b061e4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.19675.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-04 11:40:56.052158+05:30	2026-10-05 11:56:22.940239+05:30	f	2026-10-05 11:40:56.056125+05:30	1	2026-10-05 11:56:22.940239+05:30	\N
87	1	d35b548a127925a02af497a95891f99a9177c7a35f8233128648ae301d8e9632	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.19675.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-04 11:56:22.967091+05:30	2026-10-05 12:11:23.321474+05:30	f	2026-10-05 11:56:22.968207+05:30	1	2026-10-05 12:11:23.321474+05:30	\N
88	1	59c855f8073accc71e106c12c2f33dc3b35bd21df99964325bad41e662c1d79f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.19675.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-04 12:11:23.350133+05:30	2026-10-05 12:26:23.710493+05:30	f	2026-10-05 12:11:23.351052+05:30	1	2026-10-05 12:26:23.710493+05:30	\N
89	1	288c0f452c04b446107e03ed1ba5db444ab4d1945ea43dd1d42c8edd52521785	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Claude/2.19675.0 Chrome/152.0.7977.130 Safari/537.36	::1	password	2026-11-04 12:26:23.720616+05:30	\N	t	2026-10-05 12:26:23.720957+05:30	1	2026-10-05 12:26:23.720957+05:30	\N
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, reference_number, name, mobile, email, username, password_hash, department_id, profile_photo, gender, dob, last_login_at, is_active, created_at, created_by, updated_at, updated_by, photo_file_id) FROM stdin;
8	25CS002	Anjali Kumar	9100000002	25cs002@college.edu	25cs002	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	female	2007-08-21	\N	t	2026-09-21 13:49:54.313543+05:30	1	2026-09-21 13:49:54.313543+05:30	1	\N
9	25CS003	Bharath S	9100000003	25cs003@college.edu	25cs003	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	male	2007-01-05	\N	t	2026-09-21 13:49:54.315696+05:30	1	2026-09-21 13:49:54.315696+05:30	1	\N
10	\N	Sankar V	9200000003	\N	p9200000003	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.315696+05:30	1	2026-09-21 13:49:54.315696+05:30	1	\N
11	25CS004	Divya R	9100000004	25cs004@college.edu	25cs004	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	female	2007-11-30	\N	t	2026-09-21 13:49:54.318052+05:30	1	2026-09-21 13:49:54.318052+05:30	1	\N
12	\N	Revathi R	9200000004	\N	p9200000004	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.318052+05:30	1	2026-09-21 13:49:54.318052+05:30	1	\N
13	25CS005	Farhan Ali	9100000005	25cs005@college.edu	25cs005	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	male	2007-05-17	\N	t	2026-09-21 13:49:54.322194+05:30	1	2026-09-21 13:49:54.322194+05:30	1	\N
14	\N	Imran Ali	9200000005	\N	p9200000005	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.322194+05:30	1	2026-09-21 13:49:54.322194+05:30	1	\N
15	25CS006	Gayathri M	9100000006	25cs006@college.edu	25cs006	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	female	2007-07-09	\N	t	2026-09-21 13:49:54.324726+05:30	1	2026-09-21 13:49:54.324726+05:30	1	\N
16	\N	Murugan K	9200000006	\N	p9200000006	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.324726+05:30	1	2026-09-21 13:49:54.324726+05:30	1	\N
17	25CS007	Harish P	9100000007	25cs007@college.edu	25cs007	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	male	2007-02-14	\N	t	2026-09-21 13:49:54.32847+05:30	1	2026-09-21 13:49:54.32847+05:30	1	\N
18	\N	Padma P	9200000007	\N	p9200000007	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.32847+05:30	1	2026-09-21 13:49:54.32847+05:30	1	\N
19	24CS001	Ishwarya N	9100000008	24cs001@college.edu	24cs001	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	female	2006-04-02	\N	t	2026-09-21 13:49:54.330474+05:30	1	2026-09-21 13:49:54.330474+05:30	1	\N
20	\N	Natarajan S	9200000008	\N	p9200000008	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.330474+05:30	1	2026-09-21 13:49:54.330474+05:30	1	\N
21	24CS002	Karthik V	9100000009	24cs002@college.edu	24cs002	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	male	2006-09-25	\N	t	2026-09-21 13:49:54.332019+05:30	1	2026-09-21 13:49:54.332019+05:30	1	\N
22	\N	Vijaya L	9200000009	\N	p9200000009	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.332019+05:30	1	2026-09-21 13:49:54.332019+05:30	1	\N
23	25EC001	Lakshmi T	9100000010	25ec001@college.edu	25ec001	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	2	\N	female	2007-06-18	\N	t	2026-09-21 13:49:54.333405+05:30	1	2026-09-21 13:49:54.333405+05:30	1	\N
24	\N	Thangaraj M	9200000010	\N	p9200000010	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.333405+05:30	1	2026-09-21 13:49:54.333405+05:30	1	\N
25	25EC002	Mohan Raj	9100000011	25ec002@college.edu	25ec002	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	2	\N	male	2007-12-01	\N	t	2026-09-21 13:49:54.335619+05:30	1	2026-09-21 13:49:54.335619+05:30	1	\N
26	\N	Raj Kumar	9200000011	\N	p9200000011	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.335619+05:30	1	2026-09-21 13:49:54.335619+05:30	1	\N
27	25EC003	Nandhini S	9100000012	25ec003@college.edu	25ec003	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	2	\N	female	2007-10-10	\N	t	2026-09-21 13:49:54.337633+05:30	1	2026-09-21 13:49:54.337633+05:30	1	\N
28	\N	Sundari S	9200000012	\N	p9200000012	\N	\N	\N	\N	\N	\N	t	2026-09-21 13:49:54.337633+05:30	1	2026-09-21 13:49:54.337633+05:30	1	\N
7	\N	Kumar Ramasamy	9200000001	\N	p9200000001	$2a$10$V/8YaqlsfI6mwKZShoHowuh7.eRr936/4u4q40eGfXOHAtlaiPjuO	\N	\N	\N	\N	2026-09-21 17:57:32.844045+05:30	t	2026-09-21 13:49:54.303554+05:30	1	2026-09-21 17:57:32.844045+05:30	7	\N
5	EMP004	Suresh Babu	9000000004	\N	suresh	$2a$10$hPEkaUaZqRNmIyY3V7aH9O8Q0F89zUmhkgaOdKfcaPxkLMO9fBP2K	2	\N	\N	\N	2026-09-21 13:49:54.9247+05:30	t	2026-09-21 13:49:54.120822+05:30	1	2026-09-21 13:49:54.9247+05:30	1	\N
4	EMP003	Meena Devi	9000000003	\N	meena	$2a$10$m0wMszevT1TfYEXdgjERlOmQu9h60Axe4bQVkZVjR0zPAgJ8z.wlm	1	\N	\N	\N	2026-09-21 18:00:41.205145+05:30	t	2026-09-21 13:49:54.059889+05:30	1	2026-09-21 18:00:41.205145+05:30	4	\N
3	EMP002	Kavya Srinivasan	9000000002	\N	kavya	$2a$10$HnK9lAmKMrovLhr4NDGl4OFaBL9VnPnSnjk8xlgOrM5.gYiRyUQk6	1	\N	\N	\N	2026-09-21 13:52:43.012277+05:30	t	2026-09-21 13:49:53.999828+05:30	1	2026-09-21 13:52:43.012277+05:30	1	\N
2	EMP001	Priya Raman	9000000001	\N	priya	$2a$10$maUOQE3Sz0pqE3gRlZ5/e.JftCVnY1s4ZgD/VWSXAyYfnAvUFfX/y	1	\N	\N	\N	2026-09-21 18:24:27.262432+05:30	t	2026-09-21 13:49:53.934507+05:30	1	2026-09-21 18:24:27.262432+05:30	1	\N
32	\N	Ravi Parent	9000000002	\N	ravi	\N	\N	\N	\N	\N	2026-09-21 15:53:04.929517+05:30	t	2026-09-21 15:53:01.009119+05:30	1	2026-09-21 15:53:04.929517+05:30	1	\N
31	21CS001	Arun Student	9000000002	\N	arun	$2a$10$M7GuNXTX7k7IHgNISnnSSe5gnHdPqQVwhuhrnHOeI.6S57.swK9je	\N	\N	\N	\N	2026-09-21 15:54:05.093173+05:30	t	2026-09-21 15:53:00.60808+05:30	1	2026-09-21 15:54:05.093173+05:30	1	\N
6	25CS001	Arun Kumar	9100000001	25cs001@college.edu	25cs001	$2a$10$qZO5dpewkBedd2DBohKLRuLhVJ61x3BzkRJmPaBAvIgSJcRjiLI5O	1	\N	male	2007-03-12	2026-10-05 11:03:56.379388+05:30	t	2026-09-21 13:49:54.303554+05:30	1	2026-10-05 11:03:56.379388+05:30	1	\N
1	\N	Administrator	9876543210	\N	admin	$2a$10$0co2EvIdby63vv2FAZkaju615YbImMJHpYUx3z1ktzq07.oziOWIC	\N	\N	\N	\N	2026-10-05 11:10:25.366329+05:30	t	2026-09-21 13:49:27.377026+05:30	\N	2026-10-05 11:10:25.366329+05:30	1	\N
\.


--
-- Data for Name: year_levels; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.year_levels (id, name, level_no, is_active, created_at, created_by, updated_at, updated_by) FROM stdin;
1	I Year	1	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
2	II Year	2	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
3	III Year	3	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
4	IV Year	4	t	2026-09-21 13:49:27.230198+05:30	\N	2026-09-21 13:49:27.230198+05:30	\N
\.


--
-- Name: academic_years_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.academic_years_id_seq', 3, true);


--
-- Name: bulk_upload_jobs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bulk_upload_jobs_id_seq', 3, true);


--
-- Name: career_feedback_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.career_feedback_id_seq', 1, false);


--
-- Name: career_matches_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.career_matches_id_seq', 24, true);


--
-- Name: career_skills_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.career_skills_id_seq', 51, true);


--
-- Name: careers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.careers_id_seq', 12, true);


--
-- Name: classes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.classes_id_seq', 4, true);


--
-- Name: companies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.companies_id_seq', 3, true);


--
-- Name: company_job_roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.company_job_roles_id_seq', 3, true);


--
-- Name: courses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.courses_id_seq', 16, true);


--
-- Name: curriculum_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.curriculum_id_seq', 9, true);


--
-- Name: departments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.departments_id_seq', 3, true);


--
-- Name: device_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.device_tokens_id_seq', 1, false);


--
-- Name: exam_types_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.exam_types_id_seq', 4, true);


--
-- Name: files_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.files_id_seq', 12, true);


--
-- Name: grade_scales_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.grade_scales_id_seq', 7, true);


--
-- Name: job_role_departments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.job_role_departments_id_seq', 1, true);


--
-- Name: job_role_skills_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.job_role_skills_id_seq', 11, true);


--
-- Name: notification_recipients_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.notification_recipients_id_seq', 161, true);


--
-- Name: notifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.notifications_id_seq', 56, true);


--
-- Name: permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.permissions_id_seq', 97, true);


--
-- Name: placement_applications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.placement_applications_id_seq', 4, true);


--
-- Name: placement_records_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.placement_records_id_seq', 1, true);


--
-- Name: promotion_runs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.promotion_runs_id_seq', 1, false);


--
-- Name: role_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.role_permissions_id_seq', 259, true);


--
-- Name: roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.roles_id_seq', 8, true);


--
-- Name: semesters_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.semesters_id_seq', 8, true);


--
-- Name: skill_match_results_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.skill_match_results_id_seq', 135, true);


--
-- Name: skill_scores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.skill_scores_id_seq', 250, true);


--
-- Name: skills_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.skills_id_seq', 25, true);


--
-- Name: staff_assignments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.staff_assignments_id_seq', 3, true);


--
-- Name: staff_profiles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.staff_profiles_id_seq', 4, true);


--
-- Name: student_documents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.student_documents_id_seq', 4, true);


--
-- Name: student_enrollments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.student_enrollments_id_seq', 55, true);


--
-- Name: student_marks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.student_marks_id_seq', 39, true);


--
-- Name: student_parents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.student_parents_id_seq', 12, true);


--
-- Name: student_profiles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.student_profiles_id_seq', 12, true);


--
-- Name: student_skills_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.student_skills_id_seq', 37, true);


--
-- Name: subject_skills_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.subject_skills_id_seq', 2, true);


--
-- Name: subjects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.subjects_id_seq', 8, true);


--
-- Name: user_otps_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_otps_id_seq', 3, true);


--
-- Name: user_roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_roles_id_seq', 33, true);


--
-- Name: user_sessions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_sessions_id_seq', 89, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.users_id_seq', 36, true);


--
-- Name: year_levels_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.year_levels_id_seq', 4, true);


--
-- Name: academic_years academic_years_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_years
    ADD CONSTRAINT academic_years_pkey PRIMARY KEY (id);


--
-- Name: app_config app_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_pkey PRIMARY KEY (key);


--
-- Name: bulk_upload_jobs bulk_upload_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_upload_jobs
    ADD CONSTRAINT bulk_upload_jobs_pkey PRIMARY KEY (id);


--
-- Name: career_feedback career_feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_feedback
    ADD CONSTRAINT career_feedback_pkey PRIMARY KEY (id);


--
-- Name: career_matches career_matches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_matches
    ADD CONSTRAINT career_matches_pkey PRIMARY KEY (id);


--
-- Name: career_skills career_skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_skills
    ADD CONSTRAINT career_skills_pkey PRIMARY KEY (id);


--
-- Name: careers careers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.careers
    ADD CONSTRAINT careers_pkey PRIMARY KEY (id);


--
-- Name: classes classes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classes
    ADD CONSTRAINT classes_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: company_job_roles company_job_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_job_roles
    ADD CONSTRAINT company_job_roles_pkey PRIMARY KEY (id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);


--
-- Name: curriculum curriculum_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum
    ADD CONSTRAINT curriculum_pkey PRIMARY KEY (id);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: device_tokens device_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (id);


--
-- Name: exam_types exam_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_types
    ADD CONSTRAINT exam_types_pkey PRIMARY KEY (id);


--
-- Name: files files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_pkey PRIMARY KEY (id);


--
-- Name: grade_scales grade_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_scales
    ADD CONSTRAINT grade_scales_pkey PRIMARY KEY (id);


--
-- Name: job_role_departments job_role_departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_departments
    ADD CONSTRAINT job_role_departments_pkey PRIMARY KEY (id);


--
-- Name: job_role_skills job_role_skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_skills
    ADD CONSTRAINT job_role_skills_pkey PRIMARY KEY (id);


--
-- Name: notification_recipients notification_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_recipients
    ADD CONSTRAINT notification_recipients_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: placement_applications placement_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_applications
    ADD CONSTRAINT placement_applications_pkey PRIMARY KEY (id);


--
-- Name: placement_records placement_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_records
    ADD CONSTRAINT placement_records_pkey PRIMARY KEY (id);


--
-- Name: promotion_runs promotion_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotion_runs
    ADD CONSTRAINT promotion_runs_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: semesters semesters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semesters
    ADD CONSTRAINT semesters_pkey PRIMARY KEY (id);


--
-- Name: skill_match_results skill_match_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_match_results
    ADD CONSTRAINT skill_match_results_pkey PRIMARY KEY (id);


--
-- Name: skill_scores skill_scores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_scores
    ADD CONSTRAINT skill_scores_pkey PRIMARY KEY (id);


--
-- Name: skills skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skills
    ADD CONSTRAINT skills_pkey PRIMARY KEY (id);


--
-- Name: staff_assignments staff_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_pkey PRIMARY KEY (id);


--
-- Name: staff_profiles staff_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_profiles
    ADD CONSTRAINT staff_profiles_pkey PRIMARY KEY (id);


--
-- Name: student_documents student_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_pkey PRIMARY KEY (id);


--
-- Name: student_enrollments student_enrollments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_enrollments
    ADD CONSTRAINT student_enrollments_pkey PRIMARY KEY (id);


--
-- Name: student_marks student_marks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_pkey PRIMARY KEY (id);


--
-- Name: student_parents student_parents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents
    ADD CONSTRAINT student_parents_pkey PRIMARY KEY (id);


--
-- Name: student_profiles student_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_profiles
    ADD CONSTRAINT student_profiles_pkey PRIMARY KEY (id);


--
-- Name: student_skills student_skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_skills
    ADD CONSTRAINT student_skills_pkey PRIMARY KEY (id);


--
-- Name: subject_skills subject_skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_skills
    ADD CONSTRAINT subject_skills_pkey PRIMARY KEY (id);


--
-- Name: subjects subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subjects
    ADD CONSTRAINT subjects_pkey PRIMARY KEY (id);


--
-- Name: user_otps user_otps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_otps
    ADD CONSTRAINT user_otps_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);


--
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: year_levels year_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.year_levels
    ADD CONSTRAINT year_levels_pkey PRIMARY KEY (id);


--
-- Name: ix_bulk_upload_jobs_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bulk_upload_jobs_created ON public.bulk_upload_jobs USING btree (created_at DESC);


--
-- Name: ix_bulk_upload_jobs_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bulk_upload_jobs_type ON public.bulk_upload_jobs USING btree (upload_type, created_at DESC) WHERE is_active;


--
-- Name: ix_career_matches_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_career_matches_student ON public.career_matches USING btree (student_id, rank) WHERE is_active;


--
-- Name: ix_classes_incharge; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_classes_incharge ON public.classes USING btree (class_incharge_id);


--
-- Name: ix_company_job_roles_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_company_job_roles_company ON public.company_job_roles USING btree (company_id);


--
-- Name: ix_company_job_roles_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_company_job_roles_status ON public.company_job_roles USING btree (status, drive_date);


--
-- Name: ix_courses_skill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_courses_skill ON public.courses USING btree (skill_id) WHERE is_active;


--
-- Name: ix_device_tokens_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_device_tokens_user ON public.device_tokens USING btree (user_id);


--
-- Name: ix_files_inactive; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_files_inactive ON public.files USING btree (updated_at) WHERE (NOT is_active);


--
-- Name: ix_files_unattached; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_files_unattached ON public.files USING btree (created_at) WHERE ((ref_type IS NULL) AND is_active);


--
-- Name: ix_notification_recipients_inbox; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notification_recipients_inbox ON public.notification_recipients USING btree (user_id, is_read, created_at DESC);


--
-- Name: ix_notifications_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notifications_reference ON public.notifications USING btree (reference_type, reference_id) WHERE is_active;


--
-- Name: ix_notifications_sender; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notifications_sender ON public.notifications USING btree (created_by, created_at DESC) WHERE is_active;


--
-- Name: ix_placement_applications_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_placement_applications_role ON public.placement_applications USING btree (job_role_id, status) WHERE is_active;


--
-- Name: ix_placement_applications_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_placement_applications_student ON public.placement_applications USING btree (student_id);


--
-- Name: ix_placement_records_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_placement_records_company ON public.placement_records USING btree (company_id);


--
-- Name: ix_placement_records_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_placement_records_student ON public.placement_records USING btree (student_id) WHERE is_active;


--
-- Name: ix_skill_match_results_rank; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_skill_match_results_rank ON public.skill_match_results USING btree (job_role_id, final_score DESC);


--
-- Name: ix_skill_scores_blended; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_skill_scores_blended ON public.skill_scores USING btree (student_id) WHERE (is_active AND ((source)::text = 'blended'::text));


--
-- Name: ix_skill_scores_skill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_skill_scores_skill ON public.skill_scores USING btree (skill_id) WHERE (is_active AND ((source)::text = 'blended'::text));


--
-- Name: ix_staff_assignments_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_staff_assignments_class ON public.staff_assignments USING btree (class_id, semester_id) WHERE is_active;


--
-- Name: ix_student_documents_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_documents_pending ON public.student_documents USING btree (created_at) WHERE (is_active AND ((status)::text = 'pending'::text));


--
-- Name: ix_student_documents_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_documents_student ON public.student_documents USING btree (student_id) WHERE is_active;


--
-- Name: ix_student_enrollments_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_enrollments_class ON public.student_enrollments USING btree (class_id);


--
-- Name: ix_student_marks_entry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_marks_entry ON public.student_marks USING btree (semester_id, subject_id, exam_type_id) WHERE is_active;


--
-- Name: ix_student_marks_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_marks_student ON public.student_marks USING btree (student_id, semester_id);


--
-- Name: ix_student_parents_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_parents_parent ON public.student_parents USING btree (parent_id);


--
-- Name: ix_student_profiles_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_profiles_batch ON public.student_profiles USING btree (batch);


--
-- Name: ix_student_profiles_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_profiles_class ON public.student_profiles USING btree (current_class_id);


--
-- Name: ix_student_profiles_lifecycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_profiles_lifecycle ON public.student_profiles USING btree (lifecycle_status) WHERE is_active;


--
-- Name: ix_student_skills_skill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_student_skills_skill ON public.student_skills USING btree (skill_id);


--
-- Name: ix_subject_skills_skill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subject_skills_skill ON public.subject_skills USING btree (skill_id);


--
-- Name: ix_user_otps_user_purpose; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_user_otps_user_purpose ON public.user_otps USING btree (user_id, purpose, created_at DESC);


--
-- Name: ix_user_roles_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_user_roles_role ON public.user_roles USING btree (role_id);


--
-- Name: ix_user_sessions_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_user_sessions_user ON public.user_sessions USING btree (user_id);


--
-- Name: ix_users_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_users_department ON public.users USING btree (department_id);


--
-- Name: ix_users_mobile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_users_mobile ON public.users USING btree (mobile);


--
-- Name: ux_academic_years_current; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_academic_years_current ON public.academic_years USING btree (is_current) WHERE (is_current AND is_active);


--
-- Name: ux_academic_years_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_academic_years_name ON public.academic_years USING btree (name) WHERE is_active;


--
-- Name: ux_career_feedback; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_career_feedback ON public.career_feedback USING btree (student_id, career_id) WHERE is_active;


--
-- Name: ux_career_matches; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_career_matches ON public.career_matches USING btree (student_id, career_id) WHERE is_active;


--
-- Name: ux_career_skills; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_career_skills ON public.career_skills USING btree (career_id, skill_id) WHERE is_active;


--
-- Name: ux_careers_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_careers_code ON public.careers USING btree (code) WHERE is_active;


--
-- Name: ux_classes; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_classes ON public.classes USING btree (department_id, academic_year_id, year_level_id, section) WHERE is_active;


--
-- Name: ux_companies_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_companies_name ON public.companies USING btree (name) WHERE is_active;


--
-- Name: ux_curriculum; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_curriculum ON public.curriculum USING btree (department_id, semester_id, subject_id, regulation) WHERE is_active;


--
-- Name: ux_departments_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_departments_code ON public.departments USING btree (code) WHERE is_active;


--
-- Name: ux_device_tokens; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_device_tokens ON public.device_tokens USING btree (token) WHERE is_active;


--
-- Name: ux_exam_types_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_exam_types_code ON public.exam_types USING btree (code) WHERE is_active;


--
-- Name: ux_files_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_files_uuid ON public.files USING btree (uuid);


--
-- Name: ux_grade_scales_grade; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_grade_scales_grade ON public.grade_scales USING btree (grade) WHERE is_active;


--
-- Name: ux_grade_scales_min; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_grade_scales_min ON public.grade_scales USING btree (min_percent) WHERE is_active;


--
-- Name: ux_job_role_departments; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_job_role_departments ON public.job_role_departments USING btree (job_role_id, department_id) WHERE is_active;


--
-- Name: ux_job_role_skills; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_job_role_skills ON public.job_role_skills USING btree (job_role_id, skill_id) WHERE is_active;


--
-- Name: ux_notification_recipients; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_notification_recipients ON public.notification_recipients USING btree (notification_id, user_id) WHERE is_active;


--
-- Name: ux_permissions_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_permissions_slug ON public.permissions USING btree (slug) WHERE is_active;


--
-- Name: ux_placement_applications; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_placement_applications ON public.placement_applications USING btree (job_role_id, student_id) WHERE is_active;


--
-- Name: ux_placement_records; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_placement_records ON public.placement_records USING btree (student_id, job_role_id) WHERE is_active;


--
-- Name: ux_promotion_runs; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_promotion_runs ON public.promotion_runs USING btree (from_year_id, to_year_id) WHERE is_active;


--
-- Name: ux_role_permissions; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_role_permissions ON public.role_permissions USING btree (role_id, permission_id) WHERE is_active;


--
-- Name: ux_roles_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_roles_slug ON public.roles USING btree (slug) WHERE is_active;


--
-- Name: ux_semesters_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_semesters_no ON public.semesters USING btree (sem_no) WHERE is_active;


--
-- Name: ux_skill_match_results; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_skill_match_results ON public.skill_match_results USING btree (job_role_id, student_id) WHERE is_active;


--
-- Name: ux_skill_scores; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_skill_scores ON public.skill_scores USING btree (student_id, skill_id, source) WHERE is_active;


--
-- Name: ux_skills_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_skills_name ON public.skills USING btree (name) WHERE is_active;


--
-- Name: ux_staff_assignments; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_staff_assignments ON public.staff_assignments USING btree (staff_id, academic_year_id, semester_id, class_id, subject_id) WHERE is_active;


--
-- Name: ux_staff_profiles_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_staff_profiles_code ON public.staff_profiles USING btree (employee_code) WHERE is_active;


--
-- Name: ux_staff_profiles_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_staff_profiles_user ON public.staff_profiles USING btree (user_id) WHERE is_active;


--
-- Name: ux_student_enrollments; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_student_enrollments ON public.student_enrollments USING btree (student_id, academic_year_id, semester_id) WHERE is_active;


--
-- Name: ux_student_marks; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_student_marks ON public.student_marks USING btree (student_id, semester_id, subject_id, exam_type_id, attempt_no) WHERE is_active;


--
-- Name: ux_student_parents; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_student_parents ON public.student_parents USING btree (student_id, parent_id) WHERE is_active;


--
-- Name: ux_student_profiles_register; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_student_profiles_register ON public.student_profiles USING btree (register_no) WHERE is_active;


--
-- Name: ux_student_profiles_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_student_profiles_user ON public.student_profiles USING btree (user_id) WHERE is_active;


--
-- Name: ux_student_skills; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_student_skills ON public.student_skills USING btree (student_id, skill_id) WHERE is_active;


--
-- Name: ux_subject_skills; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_subject_skills ON public.subject_skills USING btree (subject_id, skill_id) WHERE is_active;


--
-- Name: ux_subjects_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_subjects_code ON public.subjects USING btree (code) WHERE is_active;


--
-- Name: ux_user_roles; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_user_roles ON public.user_roles USING btree (user_id, role_id) WHERE is_active;


--
-- Name: ux_user_sessions_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_user_sessions_token ON public.user_sessions USING btree (refresh_token_hash);


--
-- Name: ux_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_users_email ON public.users USING btree (email) WHERE (is_active AND (email IS NOT NULL));


--
-- Name: ux_users_reference_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_users_reference_number ON public.users USING btree (reference_number) WHERE (is_active AND (reference_number IS NOT NULL));


--
-- Name: ux_users_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_users_username ON public.users USING btree (username) WHERE is_active;


--
-- Name: ux_year_levels_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_year_levels_no ON public.year_levels USING btree (level_no) WHERE is_active;


--
-- Name: academic_years trg_academic_years_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_academic_years_updated_at BEFORE UPDATE ON public.academic_years FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: bulk_upload_jobs trg_bulk_upload_jobs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_bulk_upload_jobs_updated_at BEFORE UPDATE ON public.bulk_upload_jobs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: career_feedback trg_career_feedback_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_career_feedback_updated_at BEFORE UPDATE ON public.career_feedback FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: career_matches trg_career_matches_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_career_matches_updated_at BEFORE UPDATE ON public.career_matches FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: career_skills trg_career_skills_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_career_skills_updated_at BEFORE UPDATE ON public.career_skills FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: careers trg_careers_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_careers_updated_at BEFORE UPDATE ON public.careers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: classes trg_classes_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_classes_updated_at BEFORE UPDATE ON public.classes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: companies trg_companies_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_companies_updated_at BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: company_job_roles trg_company_job_roles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_company_job_roles_updated_at BEFORE UPDATE ON public.company_job_roles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: courses trg_courses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_courses_updated_at BEFORE UPDATE ON public.courses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: curriculum trg_curriculum_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_curriculum_updated_at BEFORE UPDATE ON public.curriculum FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: departments trg_departments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_departments_updated_at BEFORE UPDATE ON public.departments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: device_tokens trg_device_tokens_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_device_tokens_updated_at BEFORE UPDATE ON public.device_tokens FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: exam_types trg_exam_types_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_exam_types_updated_at BEFORE UPDATE ON public.exam_types FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: files trg_files_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_files_updated_at BEFORE UPDATE ON public.files FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: grade_scales trg_grade_scales_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_grade_scales_updated_at BEFORE UPDATE ON public.grade_scales FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: job_role_departments trg_job_role_departments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_job_role_departments_updated_at BEFORE UPDATE ON public.job_role_departments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: job_role_skills trg_job_role_skills_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_job_role_skills_updated_at BEFORE UPDATE ON public.job_role_skills FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: notification_recipients trg_notification_recipients_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notification_recipients_updated_at BEFORE UPDATE ON public.notification_recipients FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: notifications trg_notifications_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notifications_updated_at BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: permissions trg_permissions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_permissions_updated_at BEFORE UPDATE ON public.permissions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: placement_applications trg_placement_applications_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_placement_applications_updated_at BEFORE UPDATE ON public.placement_applications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: placement_records trg_placement_records_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_placement_records_updated_at BEFORE UPDATE ON public.placement_records FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: promotion_runs trg_promotion_runs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_promotion_runs_updated_at BEFORE UPDATE ON public.promotion_runs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: role_permissions trg_role_permissions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_role_permissions_updated_at BEFORE UPDATE ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: roles trg_roles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_roles_updated_at BEFORE UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: semesters trg_semesters_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_semesters_updated_at BEFORE UPDATE ON public.semesters FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: skill_match_results trg_skill_match_results_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_skill_match_results_updated_at BEFORE UPDATE ON public.skill_match_results FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: skill_scores trg_skill_scores_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_skill_scores_updated_at BEFORE UPDATE ON public.skill_scores FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: skills trg_skills_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_skills_updated_at BEFORE UPDATE ON public.skills FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: staff_assignments trg_staff_assignments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_staff_assignments_updated_at BEFORE UPDATE ON public.staff_assignments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: staff_profiles trg_staff_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_staff_profiles_updated_at BEFORE UPDATE ON public.staff_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_documents trg_student_documents_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_student_documents_updated_at BEFORE UPDATE ON public.student_documents FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_enrollments trg_student_enrollments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_student_enrollments_updated_at BEFORE UPDATE ON public.student_enrollments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_marks trg_student_marks_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_student_marks_updated_at BEFORE UPDATE ON public.student_marks FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_parents trg_student_parents_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_student_parents_updated_at BEFORE UPDATE ON public.student_parents FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_profiles trg_student_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_student_profiles_updated_at BEFORE UPDATE ON public.student_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_skills trg_student_skills_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_student_skills_updated_at BEFORE UPDATE ON public.student_skills FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: subject_skills trg_subject_skills_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_subject_skills_updated_at BEFORE UPDATE ON public.subject_skills FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: subjects trg_subjects_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_subjects_updated_at BEFORE UPDATE ON public.subjects FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: user_otps trg_user_otps_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_user_otps_updated_at BEFORE UPDATE ON public.user_otps FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: user_roles trg_user_roles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_user_roles_updated_at BEFORE UPDATE ON public.user_roles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: user_sessions trg_user_sessions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_user_sessions_updated_at BEFORE UPDATE ON public.user_sessions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: users trg_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: year_levels trg_year_levels_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_year_levels_updated_at BEFORE UPDATE ON public.year_levels FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: academic_years academic_years_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_years
    ADD CONSTRAINT academic_years_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: academic_years academic_years_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_years
    ADD CONSTRAINT academic_years_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: app_config app_config_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: bulk_upload_jobs bulk_upload_jobs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_upload_jobs
    ADD CONSTRAINT bulk_upload_jobs_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: bulk_upload_jobs bulk_upload_jobs_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_upload_jobs
    ADD CONSTRAINT bulk_upload_jobs_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: career_feedback career_feedback_career_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_feedback
    ADD CONSTRAINT career_feedback_career_id_fkey FOREIGN KEY (career_id) REFERENCES public.careers(id);


--
-- Name: career_feedback career_feedback_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_feedback
    ADD CONSTRAINT career_feedback_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: career_feedback career_feedback_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_feedback
    ADD CONSTRAINT career_feedback_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: career_feedback career_feedback_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_feedback
    ADD CONSTRAINT career_feedback_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: career_matches career_matches_career_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_matches
    ADD CONSTRAINT career_matches_career_id_fkey FOREIGN KEY (career_id) REFERENCES public.careers(id);


--
-- Name: career_matches career_matches_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_matches
    ADD CONSTRAINT career_matches_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: career_matches career_matches_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_matches
    ADD CONSTRAINT career_matches_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: career_matches career_matches_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_matches
    ADD CONSTRAINT career_matches_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: career_skills career_skills_career_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_skills
    ADD CONSTRAINT career_skills_career_id_fkey FOREIGN KEY (career_id) REFERENCES public.careers(id);


--
-- Name: career_skills career_skills_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_skills
    ADD CONSTRAINT career_skills_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: career_skills career_skills_skill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_skills
    ADD CONSTRAINT career_skills_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES public.skills(id);


--
-- Name: career_skills career_skills_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.career_skills
    ADD CONSTRAINT career_skills_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: careers careers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.careers
    ADD CONSTRAINT careers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: careers careers_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.careers
    ADD CONSTRAINT careers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: classes classes_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classes
    ADD CONSTRAINT classes_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(id);


--
-- Name: classes classes_class_incharge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classes
    ADD CONSTRAINT classes_class_incharge_id_fkey FOREIGN KEY (class_incharge_id) REFERENCES public.users(id);


--
-- Name: classes classes_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classes
    ADD CONSTRAINT classes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: classes classes_current_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classes
    ADD CONSTRAINT classes_current_semester_id_fkey FOREIGN KEY (current_semester_id) REFERENCES public.semesters(id);


--
-- Name: classes classes_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classes
    ADD CONSTRAINT classes_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: classes classes_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classes
    ADD CONSTRAINT classes_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: classes classes_year_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classes
    ADD CONSTRAINT classes_year_level_id_fkey FOREIGN KEY (year_level_id) REFERENCES public.year_levels(id);


--
-- Name: companies companies_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: companies companies_logo_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_logo_file_id_fkey FOREIGN KEY (logo_file_id) REFERENCES public.files(id);


--
-- Name: companies companies_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: company_job_roles company_job_roles_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_job_roles
    ADD CONSTRAINT company_job_roles_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_job_roles company_job_roles_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_job_roles
    ADD CONSTRAINT company_job_roles_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: company_job_roles company_job_roles_jd_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_job_roles
    ADD CONSTRAINT company_job_roles_jd_file_id_fkey FOREIGN KEY (jd_file_id) REFERENCES public.files(id);


--
-- Name: company_job_roles company_job_roles_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_job_roles
    ADD CONSTRAINT company_job_roles_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: courses courses_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: courses courses_skill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES public.skills(id);


--
-- Name: courses courses_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: curriculum curriculum_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum
    ADD CONSTRAINT curriculum_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: curriculum curriculum_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum
    ADD CONSTRAINT curriculum_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: curriculum curriculum_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum
    ADD CONSTRAINT curriculum_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(id);


--
-- Name: curriculum curriculum_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum
    ADD CONSTRAINT curriculum_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: curriculum curriculum_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum
    ADD CONSTRAINT curriculum_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: departments departments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: departments departments_hod_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_hod_id_fkey FOREIGN KEY (hod_id) REFERENCES public.users(id);


--
-- Name: departments departments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: device_tokens device_tokens_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: device_tokens device_tokens_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: device_tokens device_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: exam_types exam_types_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_types
    ADD CONSTRAINT exam_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: exam_types exam_types_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_types
    ADD CONSTRAINT exam_types_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: files files_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: files files_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: users fk_users_department; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_users_department FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: grade_scales grade_scales_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_scales
    ADD CONSTRAINT grade_scales_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: grade_scales grade_scales_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_scales
    ADD CONSTRAINT grade_scales_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: job_role_departments job_role_departments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_departments
    ADD CONSTRAINT job_role_departments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: job_role_departments job_role_departments_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_departments
    ADD CONSTRAINT job_role_departments_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: job_role_departments job_role_departments_job_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_departments
    ADD CONSTRAINT job_role_departments_job_role_id_fkey FOREIGN KEY (job_role_id) REFERENCES public.company_job_roles(id);


--
-- Name: job_role_departments job_role_departments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_departments
    ADD CONSTRAINT job_role_departments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: job_role_skills job_role_skills_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_skills
    ADD CONSTRAINT job_role_skills_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: job_role_skills job_role_skills_job_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_skills
    ADD CONSTRAINT job_role_skills_job_role_id_fkey FOREIGN KEY (job_role_id) REFERENCES public.company_job_roles(id);


--
-- Name: job_role_skills job_role_skills_skill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_skills
    ADD CONSTRAINT job_role_skills_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES public.skills(id);


--
-- Name: job_role_skills job_role_skills_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_role_skills
    ADD CONSTRAINT job_role_skills_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: notification_recipients notification_recipients_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_recipients
    ADD CONSTRAINT notification_recipients_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: notification_recipients notification_recipients_notification_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_recipients
    ADD CONSTRAINT notification_recipients_notification_id_fkey FOREIGN KEY (notification_id) REFERENCES public.notifications(id);


--
-- Name: notification_recipients notification_recipients_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_recipients
    ADD CONSTRAINT notification_recipients_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: notification_recipients notification_recipients_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_recipients
    ADD CONSTRAINT notification_recipients_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: notifications notifications_attachment_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_attachment_file_id_fkey FOREIGN KEY (attachment_file_id) REFERENCES public.files(id);


--
-- Name: notifications notifications_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: notifications notifications_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: permissions permissions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: permissions permissions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: placement_applications placement_applications_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_applications
    ADD CONSTRAINT placement_applications_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: placement_applications placement_applications_job_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_applications
    ADD CONSTRAINT placement_applications_job_role_id_fkey FOREIGN KEY (job_role_id) REFERENCES public.company_job_roles(id);


--
-- Name: placement_applications placement_applications_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_applications
    ADD CONSTRAINT placement_applications_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: placement_applications placement_applications_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_applications
    ADD CONSTRAINT placement_applications_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: placement_records placement_records_application_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_records
    ADD CONSTRAINT placement_records_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.placement_applications(id);


--
-- Name: placement_records placement_records_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_records
    ADD CONSTRAINT placement_records_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: placement_records placement_records_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_records
    ADD CONSTRAINT placement_records_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: placement_records placement_records_job_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_records
    ADD CONSTRAINT placement_records_job_role_id_fkey FOREIGN KEY (job_role_id) REFERENCES public.company_job_roles(id);


--
-- Name: placement_records placement_records_offer_letter_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_records
    ADD CONSTRAINT placement_records_offer_letter_file_id_fkey FOREIGN KEY (offer_letter_file_id) REFERENCES public.files(id);


--
-- Name: placement_records placement_records_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_records
    ADD CONSTRAINT placement_records_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: placement_records placement_records_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.placement_records
    ADD CONSTRAINT placement_records_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: promotion_runs promotion_runs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotion_runs
    ADD CONSTRAINT promotion_runs_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: promotion_runs promotion_runs_from_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotion_runs
    ADD CONSTRAINT promotion_runs_from_year_id_fkey FOREIGN KEY (from_year_id) REFERENCES public.academic_years(id);


--
-- Name: promotion_runs promotion_runs_to_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotion_runs
    ADD CONSTRAINT promotion_runs_to_year_id_fkey FOREIGN KEY (to_year_id) REFERENCES public.academic_years(id);


--
-- Name: promotion_runs promotion_runs_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotion_runs
    ADD CONSTRAINT promotion_runs_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: role_permissions role_permissions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id);


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: role_permissions role_permissions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: roles roles_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: roles roles_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: semesters semesters_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semesters
    ADD CONSTRAINT semesters_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: semesters semesters_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semesters
    ADD CONSTRAINT semesters_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: semesters semesters_year_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semesters
    ADD CONSTRAINT semesters_year_level_id_fkey FOREIGN KEY (year_level_id) REFERENCES public.year_levels(id);


--
-- Name: skill_match_results skill_match_results_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_match_results
    ADD CONSTRAINT skill_match_results_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: skill_match_results skill_match_results_job_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_match_results
    ADD CONSTRAINT skill_match_results_job_role_id_fkey FOREIGN KEY (job_role_id) REFERENCES public.company_job_roles(id);


--
-- Name: skill_match_results skill_match_results_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_match_results
    ADD CONSTRAINT skill_match_results_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: skill_match_results skill_match_results_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_match_results
    ADD CONSTRAINT skill_match_results_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: skill_scores skill_scores_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_scores
    ADD CONSTRAINT skill_scores_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: skill_scores skill_scores_skill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_scores
    ADD CONSTRAINT skill_scores_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES public.skills(id);


--
-- Name: skill_scores skill_scores_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_scores
    ADD CONSTRAINT skill_scores_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: skill_scores skill_scores_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_scores
    ADD CONSTRAINT skill_scores_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: skills skills_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skills
    ADD CONSTRAINT skills_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: skills skills_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skills
    ADD CONSTRAINT skills_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: staff_assignments staff_assignments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(id);


--
-- Name: staff_assignments staff_assignments_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_class_id_fkey FOREIGN KEY (class_id) REFERENCES public.classes(id);


--
-- Name: staff_assignments staff_assignments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: staff_assignments staff_assignments_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: staff_assignments staff_assignments_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(id);


--
-- Name: staff_assignments staff_assignments_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.users(id);


--
-- Name: staff_assignments staff_assignments_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: staff_assignments staff_assignments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_assignments
    ADD CONSTRAINT staff_assignments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: staff_profiles staff_profiles_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_profiles
    ADD CONSTRAINT staff_profiles_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: staff_profiles staff_profiles_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_profiles
    ADD CONSTRAINT staff_profiles_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: staff_profiles staff_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_profiles
    ADD CONSTRAINT staff_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: student_documents student_documents_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: student_documents student_documents_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(id);


--
-- Name: student_documents student_documents_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: student_documents student_documents_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: student_documents student_documents_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_documents
    ADD CONSTRAINT student_documents_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.users(id);


--
-- Name: student_enrollments student_enrollments_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_enrollments
    ADD CONSTRAINT student_enrollments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(id);


--
-- Name: student_enrollments student_enrollments_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_enrollments
    ADD CONSTRAINT student_enrollments_class_id_fkey FOREIGN KEY (class_id) REFERENCES public.classes(id);


--
-- Name: student_enrollments student_enrollments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_enrollments
    ADD CONSTRAINT student_enrollments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: student_enrollments student_enrollments_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_enrollments
    ADD CONSTRAINT student_enrollments_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(id);


--
-- Name: student_enrollments student_enrollments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_enrollments
    ADD CONSTRAINT student_enrollments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: student_enrollments student_enrollments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_enrollments
    ADD CONSTRAINT student_enrollments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: student_marks student_marks_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_years(id);


--
-- Name: student_marks student_marks_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_class_id_fkey FOREIGN KEY (class_id) REFERENCES public.classes(id);


--
-- Name: student_marks student_marks_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: student_marks student_marks_exam_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_exam_type_id_fkey FOREIGN KEY (exam_type_id) REFERENCES public.exam_types(id);


--
-- Name: student_marks student_marks_semester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_semester_id_fkey FOREIGN KEY (semester_id) REFERENCES public.semesters(id);


--
-- Name: student_marks student_marks_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: student_marks student_marks_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: student_marks student_marks_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_marks
    ADD CONSTRAINT student_marks_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: student_parents student_parents_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents
    ADD CONSTRAINT student_parents_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: student_parents student_parents_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents
    ADD CONSTRAINT student_parents_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.users(id);


--
-- Name: student_parents student_parents_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents
    ADD CONSTRAINT student_parents_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: student_parents student_parents_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_parents
    ADD CONSTRAINT student_parents_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: student_profiles student_profiles_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_profiles
    ADD CONSTRAINT student_profiles_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: student_profiles student_profiles_current_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_profiles
    ADD CONSTRAINT student_profiles_current_class_id_fkey FOREIGN KEY (current_class_id) REFERENCES public.classes(id);


--
-- Name: student_profiles student_profiles_resume_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_profiles
    ADD CONSTRAINT student_profiles_resume_file_id_fkey FOREIGN KEY (resume_file_id) REFERENCES public.files(id);


--
-- Name: student_profiles student_profiles_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_profiles
    ADD CONSTRAINT student_profiles_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: student_profiles student_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_profiles
    ADD CONSTRAINT student_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: student_skills student_skills_certificate_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_skills
    ADD CONSTRAINT student_skills_certificate_file_id_fkey FOREIGN KEY (certificate_file_id) REFERENCES public.files(id);


--
-- Name: student_skills student_skills_certificate_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_skills
    ADD CONSTRAINT student_skills_certificate_verified_by_fkey FOREIGN KEY (certificate_verified_by) REFERENCES public.users(id);


--
-- Name: student_skills student_skills_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_skills
    ADD CONSTRAINT student_skills_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: student_skills student_skills_skill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_skills
    ADD CONSTRAINT student_skills_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES public.skills(id);


--
-- Name: student_skills student_skills_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_skills
    ADD CONSTRAINT student_skills_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.users(id);


--
-- Name: student_skills student_skills_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_skills
    ADD CONSTRAINT student_skills_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: subject_skills subject_skills_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_skills
    ADD CONSTRAINT subject_skills_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: subject_skills subject_skills_skill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_skills
    ADD CONSTRAINT subject_skills_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES public.skills(id);


--
-- Name: subject_skills subject_skills_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_skills
    ADD CONSTRAINT subject_skills_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: subject_skills subject_skills_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_skills
    ADD CONSTRAINT subject_skills_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: subjects subjects_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subjects
    ADD CONSTRAINT subjects_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: subjects subjects_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subjects
    ADD CONSTRAINT subjects_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: user_otps user_otps_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_otps
    ADD CONSTRAINT user_otps_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: user_otps user_otps_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_otps
    ADD CONSTRAINT user_otps_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: user_otps user_otps_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_otps
    ADD CONSTRAINT user_otps_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_roles user_roles_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: user_roles user_roles_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_sessions user_sessions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: user_sessions user_sessions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: user_sessions user_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: users users_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: users users_photo_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_photo_file_id_fkey FOREIGN KEY (photo_file_id) REFERENCES public.files(id);


--
-- Name: users users_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: year_levels year_levels_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.year_levels
    ADD CONSTRAINT year_levels_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: year_levels year_levels_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.year_levels
    ADD CONSTRAINT year_levels_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

\unrestrict T0zH5tbJpbY8hCF77Obhl0aDRdAdFIiL3zungE4AnNUEcxAKzvwAbddo7uZl1aO

