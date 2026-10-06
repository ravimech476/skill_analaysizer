-- =====================================================================
-- Seed: roles, permissions, default role→permission grants, academic masters.
-- The admin USER is created by `go run ./cmd/migrate seed-admin` (needs bcrypt).
-- =====================================================================

INSERT INTO roles (name, slug, description, is_system) VALUES
    ('Admin',             'admin',             'Full access to everything',                          true),
    ('Staff',             'staff',             'Teaching staff: own classes, marks, student skills', true),
    ('HOD',               'hod',               'Head of department: department-wide view',           true),
    ('Placement Officer', 'placement_officer', 'Companies, drives, skill analyzer, shortlisting',    true),
    ('Student',           'student',           'Own profile, marks, skills and eligible drives',     true),
    ('Parent',            'parent',            'Linked children''s marks, placement and notices',    true);

-- Permissions = module x action. Middleware checks slugs like 'user.create'.
INSERT INTO permissions (module, action, slug, description)
SELECT m.module, a.action, m.module || '.' || a.action, initcap(a.action) || ' ' || replace(m.module, '_', ' ')
FROM (VALUES
    ('user'), ('role'), ('permission'), ('department'), ('academic_year'), ('subject'), ('exam_type'),
    ('class'), ('student'), ('staff'), ('parent'), ('marks'), ('skill'), ('student_skill'),
    ('company'), ('job_role'), ('placement'), ('skill_analyzer'), ('notification'), ('bulk_upload')
) AS m(module)
CROSS JOIN (VALUES ('view'), ('create'), ('update'), ('delete')) AS a(action);

-- helper: grant a list of permission slugs to a role
CREATE OR REPLACE FUNCTION pg_temp.grant_perms(p_role TEXT, p_slugs TEXT[]) RETURNS void AS $$
    INSERT INTO role_permissions (role_id, permission_id)
    SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = ANY (p_slugs)
    WHERE r.slug = p_role
    ON CONFLICT DO NOTHING;
$$ LANGUAGE sql;

-- admin: everything
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.slug = 'admin';

SELECT pg_temp.grant_perms('staff', ARRAY[
    'student.view', 'parent.view', 'class.view', 'subject.view', 'exam_type.view', 'department.view', 'academic_year.view',
    'marks.view', 'marks.create', 'marks.update',
    'skill.view', 'student_skill.view', 'student_skill.create', 'student_skill.update', 'student_skill.delete',
    'placement.view', 'job_role.view', 'company.view',
    'notification.view', 'notification.create']);

SELECT pg_temp.grant_perms('hod', ARRAY[
    'student.view', 'staff.view', 'parent.view', 'class.view', 'class.update', 'subject.view', 'exam_type.view',
    'department.view', 'academic_year.view',
    'marks.view', 'marks.create', 'marks.update',
    'skill.view', 'skill.create', 'student_skill.view', 'student_skill.create', 'student_skill.update', 'student_skill.delete',
    'company.view', 'job_role.view', 'placement.view', 'skill_analyzer.view',
    'notification.view', 'notification.create']);

SELECT pg_temp.grant_perms('placement_officer', ARRAY[
    'student.view', 'department.view', 'academic_year.view', 'marks.view',
    'skill.view', 'skill.create', 'skill.update', 'student_skill.view',
    'company.view', 'company.create', 'company.update', 'company.delete',
    'job_role.view', 'job_role.create', 'job_role.update', 'job_role.delete',
    'placement.view', 'placement.create', 'placement.update', 'placement.delete',
    'skill_analyzer.view', 'skill_analyzer.create',
    'notification.view', 'notification.create']);

-- student/parent: data is additionally scoped to "self" / "linked children" in the services.
SELECT pg_temp.grant_perms('student', ARRAY[
    'marks.view', 'student_skill.view', 'skill.view', 'company.view', 'job_role.view', 'placement.view',
    'skill_analyzer.view', 'notification.view']);

SELECT pg_temp.grant_perms('parent', ARRAY[
    'student.view', 'marks.view', 'student_skill.view', 'placement.view', 'notification.view']);

-- Academic masters
INSERT INTO year_levels (name, level_no) VALUES
    ('I Year', 1), ('II Year', 2), ('III Year', 3), ('IV Year', 4);

INSERT INTO semesters (name, sem_no, year_level_id)
SELECT 'Semester ' || s.n, s.n, y.id
FROM generate_series(1, 8) AS s(n)
JOIN year_levels y ON y.level_no = (s.n + 1) / 2;

INSERT INTO exam_types (name, code, max_marks, is_final, sort_order) VALUES
    ('Internal Assessment 1', 'IA1',   50,  false, 1),
    ('Internal Assessment 2', 'IA2',   50,  false, 2),
    ('Model Exam',            'MODEL', 100, false, 3),
    ('End Semester',          'SEM',   100, true,  4);

INSERT INTO academic_years (name, start_date, end_date, is_current) VALUES
    ('2025-26', '2025-06-01', '2026-05-31', false),
    ('2026-27', '2026-06-01', '2027-05-31', true);
