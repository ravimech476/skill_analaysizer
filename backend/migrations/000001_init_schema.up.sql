-- =====================================================================
-- Skills Analyzer — initial schema
-- Every table carries: id, is_active, created_at/by, updated_at/by.
-- "Delete" = is_active=false; uniqueness is enforced only among active rows.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS citext;

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- A. Auth & RBAC
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reference_number VARCHAR(50),
    name             VARCHAR(150) NOT NULL,
    mobile           VARCHAR(15),
    email            CITEXT,
    username         CITEXT       NOT NULL,
    password_hash    TEXT,
    department_id    BIGINT,
    profile_photo    TEXT,
    gender           VARCHAR(10)  CHECK (gender IN ('male', 'female', 'other')),
    dob              DATE,
    last_login_at    TIMESTAMPTZ,
    is_active        BOOLEAN      NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by       BIGINT       REFERENCES users(id),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by       BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_users_username ON users (username) WHERE is_active;
CREATE UNIQUE INDEX ux_users_email ON users (email) WHERE is_active AND email IS NOT NULL;
CREATE UNIQUE INDEX ux_users_reference_number ON users (reference_number) WHERE is_active AND reference_number IS NOT NULL;
-- mobile is NOT unique: a student and parent often share one number.
CREATE INDEX ix_users_mobile ON users (mobile);
CREATE INDEX ix_users_department ON users (department_id);

CREATE TABLE roles (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    slug        VARCHAR(100) NOT NULL,
    description TEXT,
    is_system   BOOLEAN      NOT NULL DEFAULT false,
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by  BIGINT       REFERENCES users(id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by  BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_roles_slug ON roles (slug) WHERE is_active;

CREATE TABLE permissions (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    module      VARCHAR(50)  NOT NULL,
    action      VARCHAR(50)  NOT NULL,
    slug        VARCHAR(120) NOT NULL,
    description TEXT,
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by  BIGINT       REFERENCES users(id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by  BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_permissions_slug ON permissions (slug) WHERE is_active;

CREATE TABLE role_permissions (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id       BIGINT      NOT NULL REFERENCES roles(id),
    permission_id BIGINT      NOT NULL REFERENCES permissions(id),
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    BIGINT      REFERENCES users(id),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_role_permissions ON role_permissions (role_id, permission_id) WHERE is_active;

-- A user can hold several roles (e.g. staff + placement_officer).
CREATE TABLE user_roles (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT      NOT NULL REFERENCES users(id),
    role_id    BIGINT      NOT NULL REFERENCES roles(id),
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by BIGINT      REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_user_roles ON user_roles (user_id, role_id) WHERE is_active;
CREATE INDEX ix_user_roles_role ON user_roles (role_id);

CREATE TABLE user_sessions (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id            BIGINT      NOT NULL REFERENCES users(id),
    refresh_token_hash TEXT        NOT NULL,
    device_info        TEXT,
    ip_address         VARCHAR(64),
    login_method       VARCHAR(20) NOT NULL DEFAULT 'password' CHECK (login_method IN ('password', 'otp')),
    expires_at         TIMESTAMPTZ NOT NULL,
    revoked_at         TIMESTAMPTZ,
    is_active          BOOLEAN     NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by         BIGINT      REFERENCES users(id),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by         BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_user_sessions_token ON user_sessions (refresh_token_hash);
CREATE INDEX ix_user_sessions_user ON user_sessions (user_id);

CREATE TABLE user_otps (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT      NOT NULL REFERENCES users(id),
    mobile      VARCHAR(15) NOT NULL,
    otp_hash    TEXT        NOT NULL,
    purpose     VARCHAR(30) NOT NULL CHECK (purpose IN ('login', 'reset_password')),
    attempts    INT         NOT NULL DEFAULT 0,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    is_active   BOOLEAN     NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  BIGINT      REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  BIGINT      REFERENCES users(id)
);
CREATE INDEX ix_user_otps_user_purpose ON user_otps (user_id, purpose, created_at DESC);

-- ---------------------------------------------------------------------
-- B. Academic masters
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       VARCHAR(150) NOT NULL,
    code       VARCHAR(20)  NOT NULL,
    hod_id     BIGINT       REFERENCES users(id),
    is_active  BOOLEAN      NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by BIGINT       REFERENCES users(id),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_departments_code ON departments (code) WHERE is_active;

ALTER TABLE users ADD CONSTRAINT fk_users_department FOREIGN KEY (department_id) REFERENCES departments(id);

CREATE TABLE academic_years (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       VARCHAR(20) NOT NULL,           -- '2025-26'
    start_date DATE        NOT NULL,
    end_date   DATE        NOT NULL,
    is_current BOOLEAN     NOT NULL DEFAULT false,
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by BIGINT      REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by BIGINT      REFERENCES users(id),
    CHECK (end_date > start_date)
);
CREATE UNIQUE INDEX ux_academic_years_name ON academic_years (name) WHERE is_active;
CREATE UNIQUE INDEX ux_academic_years_current ON academic_years (is_current) WHERE is_current AND is_active;

-- Year of study: I Year .. IV Year
CREATE TABLE year_levels (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       VARCHAR(30) NOT NULL,
    level_no   SMALLINT    NOT NULL,
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by BIGINT      REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_year_levels_no ON year_levels (level_no) WHERE is_active;

CREATE TABLE semesters (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(30) NOT NULL,
    sem_no        SMALLINT    NOT NULL,
    year_level_id BIGINT      NOT NULL REFERENCES year_levels(id),
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    BIGINT      REFERENCES users(id),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_semesters_no ON semesters (sem_no) WHERE is_active;

CREATE TABLE subjects (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code         VARCHAR(30)  NOT NULL,
    name         VARCHAR(200) NOT NULL,
    credits      NUMERIC(3,1) NOT NULL DEFAULT 0,
    subject_type VARCHAR(20)  NOT NULL DEFAULT 'theory' CHECK (subject_type IN ('theory', 'lab', 'elective', 'project')),
    is_active    BOOLEAN      NOT NULL DEFAULT true,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by   BIGINT       REFERENCES users(id),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by   BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_subjects_code ON subjects (code) WHERE is_active;

-- Which subjects a department teaches in which semester (per regulation).
CREATE TABLE curriculum (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id BIGINT      NOT NULL REFERENCES departments(id),
    semester_id   BIGINT      NOT NULL REFERENCES semesters(id),
    subject_id    BIGINT      NOT NULL REFERENCES subjects(id),
    regulation    VARCHAR(20) NOT NULL DEFAULT 'R2021',
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    BIGINT      REFERENCES users(id),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_curriculum ON curriculum (department_id, semester_id, subject_id, regulation) WHERE is_active;

-- The "marks" master from the requirement: Internal 1, Internal 2, Model, End Semester.
CREATE TABLE exam_types (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       VARCHAR(60)  NOT NULL,
    code       VARCHAR(20)  NOT NULL,
    max_marks  NUMERIC(6,2) NOT NULL DEFAULT 100,
    is_final   BOOLEAN      NOT NULL DEFAULT false,   -- end-semester result used for CGPA
    sort_order SMALLINT     NOT NULL DEFAULT 0,
    is_active  BOOLEAN      NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by BIGINT       REFERENCES users(id),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_exam_types_code ON exam_types (code) WHERE is_active;

-- ---------------------------------------------------------------------
-- D. Classes (one row per department/year/section per academic year)
--    class_incharge_id lives HERE, so incharge history is kept per year.
-- ---------------------------------------------------------------------
CREATE TABLE classes (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id     BIGINT      NOT NULL REFERENCES departments(id),
    academic_year_id  BIGINT      NOT NULL REFERENCES academic_years(id),
    year_level_id     BIGINT      NOT NULL REFERENCES year_levels(id),
    section           VARCHAR(5)  NOT NULL DEFAULT 'A',
    class_incharge_id BIGINT      REFERENCES users(id),
    is_active         BOOLEAN     NOT NULL DEFAULT true,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT      REFERENCES users(id),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_classes ON classes (department_id, academic_year_id, year_level_id, section) WHERE is_active;
CREATE INDEX ix_classes_incharge ON classes (class_incharge_id);

-- ---------------------------------------------------------------------
-- C. People profiles & relations
-- ---------------------------------------------------------------------
CREATE TABLE student_profiles (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT       NOT NULL REFERENCES users(id),
    register_no      VARCHAR(50)  NOT NULL,
    admission_year   SMALLINT     NOT NULL,
    batch            VARCHAR(20)  NOT NULL,          -- '2023-2027'
    current_class_id BIGINT       REFERENCES classes(id),
    cgpa             NUMERIC(4,2) NOT NULL DEFAULT 0, -- cached, recomputed from student_marks
    backlog_count    INT          NOT NULL DEFAULT 0, -- cached
    blood_group      VARCHAR(5),
    address          TEXT,
    resume_url       TEXT,
    is_active        BOOLEAN      NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by       BIGINT       REFERENCES users(id),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by       BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_student_profiles_user ON student_profiles (user_id) WHERE is_active;
CREATE UNIQUE INDEX ux_student_profiles_register ON student_profiles (register_no) WHERE is_active;
CREATE INDEX ix_student_profiles_class ON student_profiles (current_class_id);

CREATE TABLE staff_profiles (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT       NOT NULL REFERENCES users(id),
    employee_code VARCHAR(50)  NOT NULL,
    designation   VARCHAR(100),
    qualification VARCHAR(200),
    joined_on     DATE,
    is_active     BOOLEAN      NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by    BIGINT       REFERENCES users(id),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by    BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_staff_profiles_user ON staff_profiles (user_id) WHERE is_active;
CREATE UNIQUE INDEX ux_staff_profiles_code ON staff_profiles (employee_code) WHERE is_active;

CREATE TABLE student_parents (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id BIGINT      NOT NULL REFERENCES users(id),
    parent_id  BIGINT      NOT NULL REFERENCES users(id),
    relation   VARCHAR(20) NOT NULL DEFAULT 'guardian' CHECK (relation IN ('father', 'mother', 'guardian')),
    is_primary BOOLEAN     NOT NULL DEFAULT false,
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by BIGINT      REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by BIGINT      REFERENCES users(id),
    CHECK (student_id <> parent_id)
);
CREATE UNIQUE INDEX ux_student_parents ON student_parents (student_id, parent_id) WHERE is_active;
CREATE INDEX ix_student_parents_parent ON student_parents (parent_id);

-- ---------------------------------------------------------------------
-- E. History
-- ---------------------------------------------------------------------
-- Which class/semester a student was in (the "student_history" placement part).
CREATE TABLE student_enrollments (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id       BIGINT      NOT NULL REFERENCES users(id),
    class_id         BIGINT      NOT NULL REFERENCES classes(id),
    academic_year_id BIGINT      NOT NULL REFERENCES academic_years(id),
    semester_id      BIGINT      NOT NULL REFERENCES semesters(id),
    status           VARCHAR(20) NOT NULL DEFAULT 'studying'
                     CHECK (status IN ('studying', 'promoted', 'detained', 'passed_out', 'discontinued')),
    is_active        BOOLEAN     NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by       BIGINT      REFERENCES users(id),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by       BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_student_enrollments ON student_enrollments (student_id, academic_year_id, semester_id) WHERE is_active;
CREATE INDEX ix_student_enrollments_class ON student_enrollments (class_id);

-- One row per student x subject x exam (x attempt, for arrear re-exams).
CREATE TABLE student_marks (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id       BIGINT       NOT NULL REFERENCES users(id),
    academic_year_id BIGINT       NOT NULL REFERENCES academic_years(id),
    semester_id      BIGINT       NOT NULL REFERENCES semesters(id),
    subject_id       BIGINT       NOT NULL REFERENCES subjects(id),
    exam_type_id     BIGINT       NOT NULL REFERENCES exam_types(id),
    attempt_no       SMALLINT     NOT NULL DEFAULT 1,
    marks_obtained   NUMERIC(6,2),
    max_marks        NUMERIC(6,2) NOT NULL,
    grade            VARCHAR(5),
    result           VARCHAR(10)  CHECK (result IN ('pass', 'fail', 'absent', 'withheld')),
    is_active        BOOLEAN      NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by       BIGINT       REFERENCES users(id),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by       BIGINT       REFERENCES users(id),
    CHECK (marks_obtained IS NULL OR (marks_obtained >= 0 AND marks_obtained <= max_marks))
);
CREATE UNIQUE INDEX ux_student_marks ON student_marks (student_id, semester_id, subject_id, exam_type_id, attempt_no) WHERE is_active;
CREATE INDEX ix_student_marks_student ON student_marks (student_id, semester_id);

-- Which staff taught which subject to which class (the "staff_history").
CREATE TABLE staff_assignments (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    staff_id         BIGINT      NOT NULL REFERENCES users(id),
    academic_year_id BIGINT      NOT NULL REFERENCES academic_years(id),
    semester_id      BIGINT      NOT NULL REFERENCES semesters(id),
    department_id    BIGINT      NOT NULL REFERENCES departments(id),
    class_id         BIGINT      REFERENCES classes(id),
    subject_id       BIGINT      REFERENCES subjects(id),
    is_active        BOOLEAN     NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by       BIGINT      REFERENCES users(id),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by       BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_staff_assignments ON staff_assignments (staff_id, academic_year_id, semester_id, class_id, subject_id) WHERE is_active;

-- ---------------------------------------------------------------------
-- F. Skills (one master list shared by students and companies)
-- ---------------------------------------------------------------------
CREATE TABLE skills (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       CITEXT      NOT NULL,
    category   VARCHAR(30) NOT NULL DEFAULT 'technical'
               CHECK (category IN ('programming', 'framework', 'database', 'tool', 'technical', 'soft_skill', 'domain')),
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by BIGINT      REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_skills_name ON skills (name) WHERE is_active;

-- Entered by staff/admin only (created_by / updated_by records who).
CREATE TABLE student_skills (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id      BIGINT      NOT NULL REFERENCES users(id),
    skill_id        BIGINT      NOT NULL REFERENCES skills(id),
    proficiency     SMALLINT    NOT NULL CHECK (proficiency BETWEEN 1 AND 5),
    source          VARCHAR(20) NOT NULL DEFAULT 'assessment'
                    CHECK (source IN ('assessment', 'certification', 'project', 'internship', 'course')),
    certificate_url TEXT,
    remarks         TEXT,
    is_active       BOOLEAN     NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      BIGINT      REFERENCES users(id),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_student_skills ON student_skills (student_id, skill_id) WHERE is_active;
CREATE INDEX ix_student_skills_skill ON student_skills (skill_id);

-- ---------------------------------------------------------------------
-- G. Placement
-- ---------------------------------------------------------------------
CREATE TABLE companies (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           CITEXT       NOT NULL,
    industry       VARCHAR(100),
    website        TEXT,
    location       VARCHAR(150),
    contact_person VARCHAR(150),
    contact_email  CITEXT,
    contact_mobile VARCHAR(15),
    description    TEXT,
    is_active      BOOLEAN      NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by     BIGINT       REFERENCES users(id),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by     BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_companies_name ON companies (name) WHERE is_active;

-- A job opening / placement drive of a company.
CREATE TABLE company_job_roles (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id      BIGINT       NOT NULL REFERENCES companies(id),
    title           VARCHAR(150) NOT NULL,
    description     TEXT,
    package_lpa     NUMERIC(6,2) NOT NULL,
    drive_date      DATE,
    last_apply_date DATE,
    min_cgpa        NUMERIC(4,2) NOT NULL DEFAULT 0,
    max_backlogs    INT          NOT NULL DEFAULT 0,
    eligible_batch  VARCHAR(20),
    openings        INT,
    status          VARCHAR(20)  NOT NULL DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'open', 'closed', 'completed')),
    is_active       BOOLEAN      NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by      BIGINT       REFERENCES users(id),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by      BIGINT       REFERENCES users(id)
);
CREATE INDEX ix_company_job_roles_company ON company_job_roles (company_id);
CREATE INDEX ix_company_job_roles_status ON company_job_roles (status, drive_date);

-- Replaces "company_skills": skills a job role needs, with level and weight.
CREATE TABLE job_role_skills (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_role_id    BIGINT       NOT NULL REFERENCES company_job_roles(id),
    skill_id       BIGINT       NOT NULL REFERENCES skills(id),
    required_level SMALLINT     NOT NULL DEFAULT 3 CHECK (required_level BETWEEN 1 AND 5),
    is_mandatory   BOOLEAN      NOT NULL DEFAULT false,
    weight         NUMERIC(4,2) NOT NULL DEFAULT 1 CHECK (weight > 0),
    is_active      BOOLEAN      NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by     BIGINT       REFERENCES users(id),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by     BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_job_role_skills ON job_role_skills (job_role_id, skill_id) WHERE is_active;

CREATE TABLE job_role_departments (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_role_id   BIGINT      NOT NULL REFERENCES company_job_roles(id),
    department_id BIGINT      NOT NULL REFERENCES departments(id),
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    BIGINT      REFERENCES users(id),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_job_role_departments ON job_role_departments (job_role_id, department_id) WHERE is_active;

CREATE TABLE placement_applications (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_role_id BIGINT       NOT NULL REFERENCES company_job_roles(id),
    student_id  BIGINT       NOT NULL REFERENCES users(id),
    match_score NUMERIC(5,2),
    status      VARCHAR(20)  NOT NULL DEFAULT 'shortlisted'
                CHECK (status IN ('shortlisted', 'applied', 'in_process', 'selected', 'rejected', 'withdrawn')),
    remarks     TEXT,
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by  BIGINT       REFERENCES users(id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by  BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_placement_applications ON placement_applications (job_role_id, student_id) WHERE is_active;
CREATE INDEX ix_placement_applications_student ON placement_applications (student_id);

-- Final offers. A placed student may still apply to roles paying MORE than their best offer.
CREATE TABLE placement_records (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id       BIGINT       NOT NULL REFERENCES users(id),
    company_id       BIGINT       NOT NULL REFERENCES companies(id),
    job_role_id      BIGINT       NOT NULL REFERENCES company_job_roles(id),
    application_id   BIGINT       REFERENCES placement_applications(id),
    package_lpa      NUMERIC(6,2) NOT NULL,
    offer_date       DATE,
    joining_date     DATE,
    offer_letter_url TEXT,
    is_active        BOOLEAN      NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by       BIGINT       REFERENCES users(id),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by       BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_placement_records ON placement_records (student_id, job_role_id) WHERE is_active;
CREATE INDEX ix_placement_records_company ON placement_records (company_id);

-- ---------------------------------------------------------------------
-- H. Skill analyzer results (cached ranking per job role)
-- ---------------------------------------------------------------------
CREATE TABLE skill_match_results (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_role_id       BIGINT       NOT NULL REFERENCES company_job_roles(id),
    student_id        BIGINT       NOT NULL REFERENCES users(id),
    skill_score       NUMERIC(5,2) NOT NULL DEFAULT 0,
    academic_score    NUMERIC(5,2) NOT NULL DEFAULT 0,
    final_score       NUMERIC(5,2) NOT NULL DEFAULT 0,
    matched_skills    JSONB        NOT NULL DEFAULT '[]',
    missing_skills    JSONB        NOT NULL DEFAULT '[]',
    is_eligible       BOOLEAN      NOT NULL DEFAULT false,
    ineligible_reason TEXT,
    computed_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    is_active         BOOLEAN      NOT NULL DEFAULT true,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by        BIGINT       REFERENCES users(id),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by        BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_skill_match_results ON skill_match_results (job_role_id, student_id) WHERE is_active;
CREATE INDEX ix_skill_match_results_rank ON skill_match_results (job_role_id, final_score DESC);

-- ---------------------------------------------------------------------
-- I. Notifications & bulk upload
-- ---------------------------------------------------------------------
CREATE TABLE notifications (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title          VARCHAR(200) NOT NULL,
    body           TEXT         NOT NULL,
    type           VARCHAR(20)  NOT NULL DEFAULT 'general' CHECK (type IN ('general', 'placement', 'marks', 'skill', 'system')),
    target_type    VARCHAR(20)  NOT NULL CHECK (target_type IN ('all', 'role', 'department', 'class', 'user')),
    target_id      BIGINT,
    reference_type VARCHAR(50),
    reference_id   BIGINT,
    is_active      BOOLEAN      NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by     BIGINT       REFERENCES users(id),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by     BIGINT       REFERENCES users(id)
);

CREATE TABLE notification_recipients (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    notification_id BIGINT      NOT NULL REFERENCES notifications(id),
    user_id         BIGINT      NOT NULL REFERENCES users(id),
    is_read         BOOLEAN     NOT NULL DEFAULT false,
    read_at         TIMESTAMPTZ,
    push_status     VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (push_status IN ('pending', 'sent', 'failed', 'skipped')),
    is_active       BOOLEAN     NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      BIGINT      REFERENCES users(id),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_notification_recipients ON notification_recipients (notification_id, user_id) WHERE is_active;
CREATE INDEX ix_notification_recipients_inbox ON notification_recipients (user_id, is_read, created_at DESC);

CREATE TABLE device_tokens (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT      NOT NULL REFERENCES users(id),
    token      TEXT        NOT NULL,
    platform   VARCHAR(10) NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by BIGINT      REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_device_tokens ON device_tokens (token) WHERE is_active;
CREATE INDEX ix_device_tokens_user ON device_tokens (user_id);

CREATE TABLE bulk_upload_jobs (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    upload_type   VARCHAR(20) NOT NULL CHECK (upload_type IN ('students', 'staff', 'marks', 'skills')),
    file_name     TEXT        NOT NULL,
    file_url      TEXT,
    total_rows    INT         NOT NULL DEFAULT 0,
    success_rows  INT         NOT NULL DEFAULT 0,
    failed_rows   INT         NOT NULL DEFAULT 0,
    errors        JSONB       NOT NULL DEFAULT '[]',
    status        VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    BIGINT      REFERENCES users(id),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    BIGINT      REFERENCES users(id)
);

-- ---------------------------------------------------------------------
-- updated_at trigger on every table that has the column
-- ---------------------------------------------------------------------
DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN
        SELECT c.table_name FROM information_schema.columns c
        JOIN information_schema.tables tb ON tb.table_name = c.table_name AND tb.table_schema = c.table_schema
        WHERE c.table_schema = 'public' AND c.column_name = 'updated_at' AND tb.table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t, t);
    END LOOP;
END $$;
