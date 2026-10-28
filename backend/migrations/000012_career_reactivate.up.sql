-- Re-add career permissions that were removed.
INSERT INTO permissions (module, action, slug, description) VALUES
    ('career', 'view',   'career.view',   'View career catalogue and matches'),
    ('career', 'create', 'career.create', 'Create careers'),
    ('career', 'update', 'career.update', 'Update careers'),
    ('career', 'delete', 'career.delete', 'Delete careers'),
    ('career', 'run',    'career.run',    'Run career matching for students')
ON CONFLICT DO NOTHING;

-- career.view → admin, staff, hod, placement_officer, student, parent
INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
SELECT r.id, p.id, 1, 1
FROM roles r, permissions p
WHERE r.slug IN ('admin', 'staff', 'hod', 'placement_officer', 'student', 'parent')
  AND p.module = 'career' AND p.action = 'view'
  AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id AND rp.is_active)
ON CONFLICT DO NOTHING;

-- all career permissions → admin
INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
SELECT r.id, p.id, 1, 1
FROM roles r, permissions p
WHERE r.slug = 'admin'
  AND p.module = 'career'
  AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id AND rp.is_active)
ON CONFLICT DO NOTHING;

-- career.view, career.create, career.update, career.run → placement_officer, hod
INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
SELECT r.id, p.id, 1, 1
FROM roles r, permissions p
WHERE r.slug IN ('placement_officer', 'hod')
  AND p.slug IN ('career.view', 'career.create', 'career.update', 'career.run')
  AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id AND rp.is_active)
ON CONFLICT DO NOTHING;

-- career.view, career.run → staff
INSERT INTO role_permissions (role_id, permission_id, created_by, updated_by)
SELECT r.id, p.id, 1, 1
FROM roles r, permissions p
WHERE r.slug = 'staff'
  AND p.slug IN ('career.view', 'career.run')
  AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id AND rp.is_active)
ON CONFLICT DO NOTHING;
