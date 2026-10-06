-- Phase 4: skills, placement, skill analyzer.

-- Common skills to start with (editable under Placement → Skills).
INSERT INTO skills (name, category) VALUES
    ('C', 'programming'), ('C++', 'programming'), ('Java', 'programming'), ('Python', 'programming'),
    ('JavaScript', 'programming'), ('Go', 'programming'), ('SQL', 'database'), ('MongoDB', 'database'),
    ('React', 'framework'), ('Node.js', 'framework'), ('Spring Boot', 'framework'), ('Django', 'framework'),
    ('HTML/CSS', 'technical'), ('Data Structures & Algorithms', 'technical'), ('Machine Learning', 'technical'),
    ('Cloud (AWS/Azure)', 'tool'), ('Git', 'tool'), ('Docker', 'tool'), ('Embedded C', 'programming'),
    ('MATLAB', 'tool'), ('AutoCAD', 'tool'), ('Aptitude', 'soft_skill'), ('Communication', 'soft_skill'),
    ('Problem Solving', 'soft_skill'), ('Teamwork', 'soft_skill');

CREATE INDEX IF NOT EXISTS ix_placement_records_student ON placement_records (student_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS ix_placement_applications_role ON placement_applications (job_role_id, status) WHERE is_active;

-- Students see their own opportunities/skill gaps; parents see their children's.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug IN ('skill.view', 'company.view', 'job_role.view')
WHERE r.slug = 'parent'
ON CONFLICT DO NOTHING;

-- HOD can run the analyzer for their department's students.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug IN ('skill_analyzer.create')
WHERE r.slug = 'hod'
ON CONFLICT DO NOTHING;
