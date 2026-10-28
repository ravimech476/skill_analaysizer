-- Aptitude and coding test scores on student profiles
ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS aptitude_score numeric(5,2);
ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS coding_score numeric(5,2);
ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS communication_score numeric(5,2);
ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS psychometric_score numeric(5,2);

-- Interview question bank
CREATE TABLE IF NOT EXISTS interview_questions (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id  BIGINT REFERENCES companies(id),
    category    VARCHAR(50) NOT NULL DEFAULT 'technical',
    question    TEXT NOT NULL,
    answer      TEXT,
    difficulty  VARCHAR(20) DEFAULT 'medium',
    tags        TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  BIGINT REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  BIGINT REFERENCES users(id)
);

CREATE TRIGGER trg_interview_questions_updated_at BEFORE UPDATE ON interview_questions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Study materials per subject
CREATE TABLE IF NOT EXISTS study_materials (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_id  BIGINT NOT NULL REFERENCES subjects(id),
    title       VARCHAR(200) NOT NULL,
    material_type VARCHAR(50) NOT NULL DEFAULT 'notes',
    description TEXT,
    file_id     BIGINT REFERENCES files(id),
    url         TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  BIGINT REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  BIGINT REFERENCES users(id)
);

CREATE TRIGGER trg_study_materials_updated_at BEFORE UPDATE ON study_materials
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Permissions
INSERT INTO permissions (module, action, slug, description) VALUES
    ('interview', 'view', 'interview.view', 'View interview questions'),
    ('interview', 'create', 'interview.create', 'Create interview questions'),
    ('interview', 'update', 'interview.update', 'Update interview questions'),
    ('interview', 'delete', 'interview.delete', 'Delete interview questions'),
    ('study_material', 'view', 'study_material.view', 'View study materials'),
    ('study_material', 'create', 'study_material.create', 'Upload study materials'),
    ('study_material', 'update', 'study_material.update', 'Update study materials'),
    ('study_material', 'delete', 'study_material.delete', 'Delete study materials')
ON CONFLICT DO NOTHING;

-- Assign view permissions to all roles
INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
SELECT r.id, p.id, 1, 1
FROM roles r, permissions p
WHERE p.module IN ('interview', 'study_material') AND p.action = 'view'
AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id AND rp.is_active)
ON CONFLICT DO NOTHING;

-- Assign create/update/delete to admin and staff
INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
SELECT r.id, p.id, 1, 1
FROM roles r, permissions p
WHERE r.slug IN ('admin', 'staff', 'hod')
AND p.module IN ('interview', 'study_material') AND p.action IN ('create', 'update', 'delete')
AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id AND rp.is_active)
ON CONFLICT DO NOTHING;
