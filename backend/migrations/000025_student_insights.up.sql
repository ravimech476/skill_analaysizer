-- One stored insight per student. It is reused until the student's facts change (facts_hash).
CREATE TABLE student_insights (
    student_id   bigint PRIMARY KEY REFERENCES users (id),
    facts_hash   text        NOT NULL,
    body         jsonb       NOT NULL,
    generated_at timestamptz NOT NULL DEFAULT now()
);
