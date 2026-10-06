-- Phase 6: student lifecycle (semester change, year promotion, detention, pass-out, discontinuation).

-- Where a student is in their course. Detention is recorded per semester in student_enrollments.
ALTER TABLE student_profiles
    ADD COLUMN lifecycle_status VARCHAR(20) NOT NULL DEFAULT 'studying'
        CHECK (lifecycle_status IN ('studying', 'passed_out', 'discontinued')),
    ADD COLUMN passed_out_year SMALLINT,
    ADD COLUMN status_remarks TEXT;
CREATE INDEX ix_student_profiles_lifecycle ON student_profiles (lifecycle_status) WHERE is_active;

-- One row per executed year promotion (audit + guard against running the same promotion twice).
CREATE TABLE promotion_runs (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_year_id      BIGINT      NOT NULL REFERENCES academic_years(id),
    to_year_id        BIGINT      NOT NULL REFERENCES academic_years(id),
    promoted_count    INT         NOT NULL DEFAULT 0,
    detained_count    INT         NOT NULL DEFAULT 0,
    passed_out_count  INT         NOT NULL DEFAULT 0,
    classes_created   INT         NOT NULL DEFAULT 0,
    summary           JSONB       NOT NULL DEFAULT '[]',
    is_active         BOOLEAN     NOT NULL DEFAULT true,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT      REFERENCES users(id),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT      REFERENCES users(id),
    CHECK (from_year_id <> to_year_id)
);
CREATE UNIQUE INDEX ux_promotion_runs ON promotion_runs (from_year_id, to_year_id) WHERE is_active;
CREATE TRIGGER trg_promotion_runs_updated_at BEFORE UPDATE ON promotion_runs FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO permissions (module, action, slug, description) VALUES
    ('promotion', 'view',   'promotion.view',   'View semester change, promotion history and alumni'),
    ('promotion', 'create', 'promotion.create', 'Change semesters, promote years, discontinue and re-admit students');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.module = 'promotion' WHERE r.slug = 'admin'
ON CONFLICT DO NOTHING;
-- HODs can see the year-end screens and change their own department's semesters.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'promotion.view' WHERE r.slug = 'hod'
ON CONFLICT DO NOTHING;

-- Backfill student history: every current student is enrolled in their class's current semester.
INSERT INTO student_enrollments (student_id, class_id, academic_year_id, semester_id, status)
SELECT sp.user_id, c.id, c.academic_year_id, c.current_semester_id, 'studying'
FROM student_profiles sp
JOIN classes c ON c.id = sp.current_class_id AND c.is_active AND c.current_semester_id IS NOT NULL
WHERE sp.is_active
ON CONFLICT DO NOTHING;
