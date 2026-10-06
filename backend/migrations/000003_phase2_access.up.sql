-- Phase 2: data-scoped student access + bulk upload history.

-- Students may view their own profile (the students service scopes them to themselves;
-- parents are scoped to linked children, staff/HOD to their department).
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug IN ('student.view', 'class.view')
WHERE r.slug = 'student'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug IN ('class.view', 'staff.view')
WHERE r.slug IN ('parent', 'staff', 'placement_officer')
ON CONFLICT DO NOTHING;

-- Masters are needed read-only by everyone who works with students.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r
JOIN permissions p ON p.slug IN ('department.view', 'academic_year.view', 'subject.view', 'exam_type.view')
WHERE r.slug IN ('staff', 'hod', 'placement_officer', 'student', 'parent')
ON CONFLICT DO NOTHING;

CREATE INDEX IF NOT EXISTS ix_student_profiles_batch ON student_profiles (batch);
CREATE INDEX IF NOT EXISTS ix_bulk_upload_jobs_created ON bulk_upload_jobs (created_at DESC);

ALTER TABLE bulk_upload_jobs ADD COLUMN IF NOT EXISTS dry_run BOOLEAN NOT NULL DEFAULT false;
