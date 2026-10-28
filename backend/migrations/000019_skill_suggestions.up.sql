-- Skill levels suggested from a student's marks. Nothing here changes a student's skills until staff accept it.

CREATE TABLE IF NOT EXISTS skill_suggestions (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id      bigint NOT NULL REFERENCES users(id),
    skill_id        bigint NOT NULL REFERENCES skills(id),
    suggested_level smallint NOT NULL CHECK (suggested_level BETWEEN 1 AND 5),
    -- the level the student already has for this skill (NULL = none recorded)
    current_level   smallint CHECK (current_level BETWEEN 1 AND 5),
    percent         numeric(5,2) NOT NULL,
    -- the subjects and marks behind it: [{"subject_id":1,"subject":"Data Structures","percent":82,"weight":1}]
    evidence        jsonb NOT NULL,
    status          varchar(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'dismissed')),
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      bigint REFERENCES users(id),
    decided_at      timestamptz,
    decided_by      bigint REFERENCES users(id)
);
-- one open suggestion per student and skill
CREATE UNIQUE INDEX IF NOT EXISTS ux_skill_suggestions_pending ON skill_suggestions (student_id, skill_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS ix_skill_suggestions_student ON skill_suggestions (student_id, status);
