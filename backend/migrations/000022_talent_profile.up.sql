-- Psychometric and coding data about a student (the "psychometric" and "coding skills" inputs of the
-- EduSkill pipeline): questionnaire results, coding-platform profiles and projects.

-- Every time a student (or staff on their behalf) completes a questionnaire a row is added; the latest
-- row per kind is the current result, older rows keep the history.
CREATE TABLE IF NOT EXISTS student_assessments (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id bigint NOT NULL REFERENCES users(id),
    kind       varchar(20) NOT NULL CHECK (kind IN ('personality', 'interests', 'learning')),
    answers    jsonb NOT NULL,
    scores     jsonb NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by bigint REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS ix_student_assessments_latest ON student_assessments (student_id, kind, id DESC) WHERE is_active;

CREATE TABLE IF NOT EXISTS coding_profiles (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id      bigint NOT NULL REFERENCES users(id),
    platform        varchar(30) NOT NULL
                    CHECK (platform IN ('leetcode', 'hackerrank', 'codechef', 'codeforces', 'geeksforgeeks', 'hackerearth', 'other')),
    username        varchar(100) NOT NULL,
    profile_url     text,
    problems_solved integer NOT NULL DEFAULT 0 CHECK (problems_solved >= 0),
    rating          integer CHECK (rating >= 0),
    -- only verified entries count towards the programming skill index
    verified        boolean NOT NULL DEFAULT false,
    verified_by     bigint REFERENCES users(id),
    verified_at     timestamptz,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      bigint REFERENCES users(id),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    updated_by      bigint REFERENCES users(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_coding_profiles_platform ON coding_profiles (student_id, platform) WHERE is_active;
CREATE TRIGGER trg_coding_profiles_updated_at BEFORE UPDATE ON coding_profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS student_projects (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id    bigint NOT NULL REFERENCES users(id),
    title         varchar(150) NOT NULL,
    description   text,
    tech_stack    varchar(300),
    repo_url      text,
    live_url      text,
    status        varchar(15) NOT NULL DEFAULT 'completed' CHECK (status IN ('ongoing', 'completed')),
    verified      boolean NOT NULL DEFAULT false,
    verified_by   bigint REFERENCES users(id),
    verified_at   timestamptz,
    -- staff rubric for code quality: {"readability":1-5,"structure":1-5,"testing":1-5,"documentation":1-5}
    rubric        jsonb,
    quality_score numeric(5,2),
    review_notes  text,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    created_by    bigint REFERENCES users(id),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    updated_by    bigint REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS ix_student_projects_student ON student_projects (student_id) WHERE is_active;
CREATE TRIGGER trg_student_projects_updated_at BEFORE UPDATE ON student_projects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
