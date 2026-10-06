-- Phase 3: marks, grades, CGPA, subject allocation.

-- Pass threshold for internal exams (final exams use the grade scale's is_pass).
ALTER TABLE exam_types ADD COLUMN pass_percent NUMERIC(5,2) NOT NULL DEFAULT 50 CHECK (pass_percent BETWEEN 0 AND 100);

-- The semester a class is currently in; drives the default for mark entry.
ALTER TABLE classes ADD COLUMN current_semester_id BIGINT REFERENCES semesters(id);
UPDATE classes c SET current_semester_id = s.id
FROM year_levels yl, semesters s
WHERE yl.id = c.year_level_id AND s.sem_no = yl.level_no * 2 - 1 AND c.current_semester_id IS NULL;

-- Grade scale for final (end-semester) exams, percentage based (Anna University style by default).
CREATE TABLE grade_scales (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    grade       VARCHAR(5)   NOT NULL,
    min_percent NUMERIC(5,2) NOT NULL CHECK (min_percent BETWEEN 0 AND 100),
    grade_point NUMERIC(4,2) NOT NULL CHECK (grade_point >= 0),
    is_pass     BOOLEAN      NOT NULL DEFAULT true,
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by  BIGINT       REFERENCES users(id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by  BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_grade_scales_grade ON grade_scales (grade) WHERE is_active;
CREATE UNIQUE INDEX ux_grade_scales_min ON grade_scales (min_percent) WHERE is_active;
CREATE TRIGGER trg_grade_scales_updated_at BEFORE UPDATE ON grade_scales FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO grade_scales (grade, min_percent, grade_point, is_pass) VALUES
    ('O',  91, 10, true),
    ('A+', 81, 9,  true),
    ('A',  71, 8,  true),
    ('B+', 61, 7,  true),
    ('B',  56, 6,  true),
    ('C',  50, 5,  true),
    ('U',  0,  0,  false);

-- Grade point stored with the mark so CGPA never depends on a later scale change.
ALTER TABLE student_marks ADD COLUMN grade_point NUMERIC(4,2);
ALTER TABLE student_marks ADD COLUMN class_id BIGINT REFERENCES classes(id);
CREATE INDEX ix_student_marks_entry ON student_marks (semester_id, subject_id, exam_type_id) WHERE is_active;

-- One allocation per staff × class × subject × semester (staff_assignments already has academic_year + department).
CREATE INDEX IF NOT EXISTS ix_staff_assignments_class ON staff_assignments (class_id, semester_id) WHERE is_active;

-- Subject allocation permissions (who teaches what; drives who may enter marks).
INSERT INTO permissions (module, action, slug, description) VALUES
    ('subject_allocation', 'view',   'subject_allocation.view',   'View subject allocation'),
    ('subject_allocation', 'create', 'subject_allocation.create', 'Create subject allocation'),
    ('subject_allocation', 'delete', 'subject_allocation.delete', 'Delete subject allocation');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.module = 'subject_allocation'
WHERE r.slug IN ('admin', 'hod')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'subject_allocation.view'
WHERE r.slug IN ('staff', 'placement_officer')
ON CONFLICT DO NOTHING;

-- Placement officers need marks for eligibility; parents/students already have marks.view.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'marks.view'
WHERE r.slug = 'placement_officer'
ON CONFLICT DO NOTHING;
