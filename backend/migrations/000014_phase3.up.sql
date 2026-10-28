-- Phase 3: Attendance tracking, CO/PO mapping, Question bank

-- 1. Attendance tracking
CREATE TABLE IF NOT EXISTS attendance (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id      BIGINT NOT NULL REFERENCES users(id),
    class_id        BIGINT NOT NULL REFERENCES classes(id),
    subject_id      BIGINT NOT NULL REFERENCES subjects(id),
    semester_id     BIGINT NOT NULL REFERENCES semesters(id),
    academic_year_id BIGINT NOT NULL REFERENCES academic_years(id),
    total_classes    INT NOT NULL DEFAULT 0,
    classes_attended INT NOT NULL DEFAULT 0,
    percentage       NUMERIC(5,2) NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      BIGINT REFERENCES users(id),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      BIGINT REFERENCES users(id),
    CONSTRAINT attendance_check CHECK (classes_attended >= 0 AND classes_attended <= total_classes),
    CONSTRAINT ux_attendance UNIQUE (student_id, class_id, subject_id, semester_id, academic_year_id)
);

CREATE TRIGGER trg_attendance_updated_at BEFORE UPDATE ON attendance
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 2. CO/PO Mapping
CREATE TABLE IF NOT EXISTS program_outcomes (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id BIGINT NOT NULL REFERENCES departments(id),
    code        VARCHAR(10) NOT NULL,
    description TEXT NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  BIGINT REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  BIGINT REFERENCES users(id)
);

CREATE TRIGGER trg_program_outcomes_updated_at BEFORE UPDATE ON program_outcomes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS course_outcomes (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_id  BIGINT NOT NULL REFERENCES subjects(id),
    code        VARCHAR(10) NOT NULL,
    description TEXT NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  BIGINT REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  BIGINT REFERENCES users(id)
);

CREATE TRIGGER trg_course_outcomes_updated_at BEFORE UPDATE ON course_outcomes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS co_po_mapping (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    co_id       BIGINT NOT NULL REFERENCES course_outcomes(id),
    po_id       BIGINT NOT NULL REFERENCES program_outcomes(id),
    strength    SMALLINT NOT NULL DEFAULT 2,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  BIGINT REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  BIGINT REFERENCES users(id),
    CONSTRAINT co_po_strength_check CHECK (strength >= 1 AND strength <= 3),
    CONSTRAINT ux_co_po UNIQUE (co_id, po_id)
);

CREATE TRIGGER trg_co_po_mapping_updated_at BEFORE UPDATE ON co_po_mapping
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 3. Question Bank
CREATE TABLE IF NOT EXISTS question_bank (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_id  BIGINT NOT NULL REFERENCES subjects(id),
    exam_type_id BIGINT REFERENCES exam_types(id),
    year        INT,
    question    TEXT NOT NULL,
    marks       INT DEFAULT 0,
    blooms_level VARCHAR(20) DEFAULT 'understand',
    unit        VARCHAR(50),
    co_id       BIGINT REFERENCES course_outcomes(id),
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  BIGINT REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  BIGINT REFERENCES users(id)
);

CREATE TRIGGER trg_question_bank_updated_at BEFORE UPDATE ON question_bank
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Permissions
INSERT INTO permissions (module, action, slug, description) VALUES
    ('attendance', 'view', 'attendance.view', 'View attendance records'),
    ('attendance', 'create', 'attendance.create', 'Record attendance'),
    ('attendance', 'update', 'attendance.update', 'Update attendance'),
    ('program_outcome', 'view', 'program_outcome.view', 'View program outcomes'),
    ('program_outcome', 'create', 'program_outcome.create', 'Create program outcomes'),
    ('program_outcome', 'update', 'program_outcome.update', 'Update program outcomes'),
    ('program_outcome', 'delete', 'program_outcome.delete', 'Delete program outcomes'),
    ('course_outcome', 'view', 'course_outcome.view', 'View course outcomes'),
    ('course_outcome', 'create', 'course_outcome.create', 'Create course outcomes'),
    ('course_outcome', 'update', 'course_outcome.update', 'Update course outcomes'),
    ('course_outcome', 'delete', 'course_outcome.delete', 'Delete course outcomes'),
    ('question_bank', 'view', 'question_bank.view', 'View question bank'),
    ('question_bank', 'create', 'question_bank.create', 'Create questions'),
    ('question_bank', 'update', 'question_bank.update', 'Update questions'),
    ('question_bank', 'delete', 'question_bank.delete', 'Delete questions')
ON CONFLICT DO NOTHING;

-- Assign view to all roles
INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
SELECT r.id, p.id, 1, 1
FROM roles r, permissions p
WHERE p.module IN ('attendance', 'program_outcome', 'course_outcome', 'question_bank') AND p.action = 'view'
AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id AND rp.is_active)
ON CONFLICT DO NOTHING;

-- Assign create/update/delete to admin, staff, hod
INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
SELECT r.id, p.id, 1, 1
FROM roles r, permissions p
WHERE r.slug IN ('admin', 'staff', 'hod')
AND p.module IN ('attendance', 'program_outcome', 'course_outcome', 'question_bank')
AND p.action IN ('create', 'update', 'delete')
AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id AND rp.is_active)
ON CONFLICT DO NOTHING;
