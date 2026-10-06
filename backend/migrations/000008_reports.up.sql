-- Phase 7: bulk tools and reports.

-- Dashboard access. Exports reuse the view permission of what they export
-- (marks.view, student.view, placement.view, skill_analyzer.view).
INSERT INTO permissions (module, action, slug, description) VALUES
    ('report', 'view', 'report.view', 'View the analytics dashboard (pass %, CGPA spread, skill gaps, placement trend)');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'report.view'
WHERE r.slug IN ('admin', 'hod', 'placement_officer', 'staff')
ON CONFLICT DO NOTHING;

-- Staff and skill imports are run by staff who may not see the whole upload history.
CREATE INDEX IF NOT EXISTS ix_bulk_upload_jobs_type ON bulk_upload_jobs (upload_type, created_at DESC) WHERE is_active;
