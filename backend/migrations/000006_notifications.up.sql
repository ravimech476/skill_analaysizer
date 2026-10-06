-- Phase 5: notifications.

-- Automatic notices are tagged with what triggered them (e.g. 'job_role_open'); manual notices have none.
CREATE INDEX IF NOT EXISTS ix_notifications_reference ON notifications (reference_type, reference_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS ix_notifications_sender ON notifications (created_by, created_at DESC) WHERE is_active;

-- Parents and students must be able to read their inbox; staff roles can send.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'notification.view'
WHERE r.slug IN ('staff', 'hod', 'placement_officer', 'student', 'parent')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'notification.create'
WHERE r.slug IN ('staff', 'hod', 'placement_officer')
ON CONFLICT DO NOTHING;
