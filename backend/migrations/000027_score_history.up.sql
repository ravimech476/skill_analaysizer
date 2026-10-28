-- One row per student per day: the scores that make up placement readiness, so faculty can see movement
-- over time and a drop is noticed. risk_level is kept to tell when a student has newly become high risk.
CREATE TABLE student_score_history (
    student_id    bigint       NOT NULL REFERENCES users (id),
    snapshot_date date         NOT NULL,
    readiness     numeric(5, 2) NOT NULL,
    cgpa          numeric(4, 2) NOT NULL DEFAULT 0,
    aptitude      numeric(5, 2),
    coding        numeric(5, 2),
    communication numeric(5, 2),
    attendance    numeric(5, 2),
    skill_count   integer      NOT NULL DEFAULT 0,
    risk_level    varchar(10)  NOT NULL DEFAULT 'none' CHECK (risk_level IN ('none', 'medium', 'high')),
    PRIMARY KEY (student_id, snapshot_date)
);
