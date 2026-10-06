-- Phase 10: the skill-score model and the career catalogue.
--
-- Until now a student's skill was one number typed by staff, and matching only worked
-- against live drives. This migration adds:
--   * skill_scores   one row per student, skill and source, plus a blended row
--   * subject_skills which skills a subject's marks contribute to
--   * careers        a catalogue students can aim at even when no drive is open
--   * career_matches the ranked careers for a student, with gaps and feedback
--   * app_config     the weights behind all of the above, tunable without a deploy

-- ---------- tunable settings ----------

CREATE TABLE app_config (
    key         VARCHAR(60) PRIMARY KEY,
    value       JSONB       NOT NULL,
    description TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  BIGINT      REFERENCES users(id)
);

INSERT INTO app_config (key, value, description) VALUES
    ('skill_score_weights',
     '{"declared": 0.10, "test": 0.45, "cert": 0.25, "academic": 0.20}',
     'How much each source counts towards a blended skill score. A source with no data is dropped and the rest are renormalised.'),
    ('match_weights',
     '{"skill": 0.70, "academic": 0.30}',
     'Split between skill match and academic record in a job-role or career match score.');

-- ---------- which skills a subject teaches ----------

CREATE TABLE subject_skills (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_id BIGINT       NOT NULL REFERENCES subjects(id),
    skill_id   BIGINT       NOT NULL REFERENCES skills(id),
    weight     NUMERIC(3,2) NOT NULL DEFAULT 1 CHECK (weight > 0),
    is_active  BOOLEAN      NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by BIGINT       REFERENCES users(id),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_subject_skills ON subject_skills (subject_id, skill_id) WHERE is_active;
CREATE INDEX ix_subject_skills_skill ON subject_skills (skill_id);
CREATE TRIGGER trg_subject_skills_updated_at BEFORE UPDATE ON subject_skills FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- A skill certificate only counts once someone has verified it.
ALTER TABLE student_skills
    ADD COLUMN certificate_verified    BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN certificate_verified_by BIGINT REFERENCES users(id),
    ADD COLUMN certificate_verified_at TIMESTAMPTZ;

-- ---------- blended skill scores ----------

CREATE TABLE skill_scores (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id  BIGINT       NOT NULL REFERENCES users(id),
    skill_id    BIGINT       NOT NULL REFERENCES skills(id),
    -- declared: the level staff recorded · test: assessments · cert: verified certificate
    -- academic: subject marks through subject_skills · blended: the weighted result
    source      VARCHAR(10)  NOT NULL CHECK (source IN ('declared', 'test', 'cert', 'academic', 'blended')),
    score       NUMERIC(5,2) NOT NULL CHECK (score BETWEEN 0 AND 100),
    detail      JSONB        NOT NULL DEFAULT '{}', -- what the number was built from
    computed_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by  BIGINT       REFERENCES users(id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by  BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_skill_scores ON skill_scores (student_id, skill_id, source) WHERE is_active;
-- The matcher reads only blended rows, one index scan per student.
CREATE INDEX ix_skill_scores_blended ON skill_scores (student_id) WHERE is_active AND source = 'blended';
CREATE INDEX ix_skill_scores_skill ON skill_scores (skill_id) WHERE is_active AND source = 'blended';
CREATE TRIGGER trg_skill_scores_updated_at BEFORE UPDATE ON skill_scores FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------- career catalogue ----------

CREATE TABLE careers (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(30)  NOT NULL,
    name        VARCHAR(150) NOT NULL,
    domain      VARCHAR(80),
    description TEXT,
    avg_package NUMERIC(6,2), -- LPA
    min_cgpa    NUMERIC(4,2) NOT NULL DEFAULT 0,
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by  BIGINT       REFERENCES users(id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by  BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_careers_code ON careers (code) WHERE is_active;
CREATE TRIGGER trg_careers_updated_at BEFORE UPDATE ON careers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE career_skills (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    career_id      BIGINT       NOT NULL REFERENCES careers(id),
    skill_id       BIGINT       NOT NULL REFERENCES skills(id),
    required_level SMALLINT     NOT NULL DEFAULT 3 CHECK (required_level BETWEEN 1 AND 5),
    weight         NUMERIC(3,2) NOT NULL DEFAULT 1 CHECK (weight > 0),
    is_core        BOOLEAN      NOT NULL DEFAULT false,
    is_active      BOOLEAN      NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by     BIGINT       REFERENCES users(id),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by     BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_career_skills ON career_skills (career_id, skill_id) WHERE is_active;
CREATE TRIGGER trg_career_skills_updated_at BEFORE UPDATE ON career_skills FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Courses that close a gap in a skill. Learning paths (next phase) draw from this.
CREATE TABLE courses (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    skill_id         BIGINT       NOT NULL REFERENCES skills(id),
    title            VARCHAR(200) NOT NULL,
    provider         VARCHAR(100),
    url              TEXT,
    level            SMALLINT     NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 5),
    duration_hours   SMALLINT,
    is_certification BOOLEAN      NOT NULL DEFAULT false,
    is_free          BOOLEAN      NOT NULL DEFAULT true,
    is_active        BOOLEAN      NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by       BIGINT       REFERENCES users(id),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by       BIGINT       REFERENCES users(id)
);
CREATE INDEX ix_courses_skill ON courses (skill_id) WHERE is_active;
CREATE TRIGGER trg_courses_updated_at BEFORE UPDATE ON courses FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------- career matches for a student ----------

CREATE TABLE career_matches (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id     BIGINT       NOT NULL REFERENCES users(id),
    career_id      BIGINT       NOT NULL REFERENCES careers(id),
    rank           SMALLINT     NOT NULL,
    skill_score    NUMERIC(5,2) NOT NULL DEFAULT 0,
    academic_score NUMERIC(5,2) NOT NULL DEFAULT 0,
    final_score    NUMERIC(5,2) NOT NULL DEFAULT 0,
    -- how ready the student is: ready (every core skill met) | close | explore
    readiness      VARCHAR(10)  NOT NULL DEFAULT 'explore' CHECK (readiness IN ('ready', 'close', 'explore')),
    gaps           JSONB        NOT NULL DEFAULT '[]', -- [{skill_id,name,score,required,gap,is_core}]
    strengths      JSONB        NOT NULL DEFAULT '[]',
    explanation    TEXT,
    computed_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    is_active      BOOLEAN      NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by     BIGINT       REFERENCES users(id),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by     BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_career_matches ON career_matches (student_id, career_id) WHERE is_active;
CREATE INDEX ix_career_matches_student ON career_matches (student_id, rank) WHERE is_active;
CREATE TRIGGER trg_career_matches_updated_at BEFORE UPDATE ON career_matches FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- What the student thought of a suggested career. Also the label set a model would learn from.
CREATE TABLE career_feedback (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id BIGINT      NOT NULL REFERENCES users(id),
    career_id  BIGINT      NOT NULL REFERENCES careers(id),
    rating     SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    is_useful  BOOLEAN     NOT NULL DEFAULT true,
    comment    TEXT,
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by BIGINT      REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by BIGINT      REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_career_feedback ON career_feedback (student_id, career_id) WHERE is_active;
CREATE TRIGGER trg_career_feedback_updated_at BEFORE UPDATE ON career_feedback FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------- a starting catalogue ----------
-- Editable under Careers. Required skills are matched by name, so a career simply
-- carries fewer requirements on a college that has removed one of the seeded skills.

INSERT INTO careers (code, name, domain, description, avg_package, min_cgpa) VALUES
    ('SDE',      'Software Development Engineer', 'IT / Software',   'Builds and ships application software. Interviews centre on data structures, problem solving and one strong language.', 6.50, 6.5),
    ('FULLSTACK','Full Stack Developer',          'IT / Software',   'Works across the browser and the server, from screens to APIs and databases.',                                      5.50, 6.0),
    ('BACKEND',  'Backend Developer',             'IT / Software',   'Owns APIs, business logic and data stores behind a product.',                                                      6.00, 6.0),
    ('DATA_AN',  'Data Analyst',                  'Data',            'Turns raw data into reports and decisions with SQL, spreadsheets and visualisation.',                              4.50, 6.0),
    ('ML_ENG',   'Machine Learning Engineer',     'Data',            'Trains and deploys models. Expects strong Python, statistics and ML fundamentals.',                                8.00, 7.0),
    ('DEVOPS',   'Cloud / DevOps Engineer',       'Infrastructure',  'Runs build pipelines, containers and cloud infrastructure.',                                                       6.50, 6.0),
    ('EMBEDDED', 'Embedded Systems Engineer',     'Core / Hardware', 'Programs microcontrollers and hardware-facing firmware.',                                                          4.50, 6.0),
    ('DESIGN_E', 'Design Engineer',               'Core',            'Produces and validates engineering designs and drawings.',                                                         4.00, 6.0),
    ('QA',       'Testing / QA Engineer',         'IT / Software',   'Finds defects before customers do, by hand and with automation.',                                                  4.00, 6.0),
    ('DBA',      'Database Administrator',        'Infrastructure',  'Keeps databases fast, backed up and secure.',                                                                      5.00, 6.0),
    ('SUPPORT',  'Technical Support Engineer',    'IT Services',     'Resolves customer issues; the most common entry route into an IT services company.',                               3.50, 5.5),
    ('BIZ_AN',   'Business Analyst',              'IT Services',     'Sits between the customer and the engineers, writing down what must be built.',                                    5.00, 6.5);

INSERT INTO career_skills (career_id, skill_id, required_level, weight, is_core)
SELECT c.id, s.id, v.lvl, v.wt, v.core
FROM (VALUES
    ('SDE',      'Data Structures & Algorithms', 4, 2.0, true),
    ('SDE',      'Problem Solving',              4, 1.5, true),
    ('SDE',      'Python',                       3, 1.0, false),
    ('SDE',      'SQL',                          3, 1.0, false),
    ('SDE',      'Git',                          3, 0.5, false),
    ('FULLSTACK','JavaScript',                   4, 2.0, true),
    ('FULLSTACK','React',                        3, 1.5, true),
    ('FULLSTACK','Node.js',                      3, 1.5, false),
    ('FULLSTACK','HTML/CSS',                     4, 1.0, false),
    ('FULLSTACK','SQL',                          3, 1.0, false),
    ('FULLSTACK','Git',                          3, 0.5, false),
    ('BACKEND',  'Java',                         4, 2.0, true),
    ('BACKEND',  'SQL',                          4, 1.5, true),
    ('BACKEND',  'Spring Boot',                  3, 1.5, false),
    ('BACKEND',  'Docker',                       2, 0.5, false),
    ('BACKEND',  'Git',                           3, 0.5, false),
    ('DATA_AN',  'SQL',                          4, 2.0, true),
    ('DATA_AN',  'Python',                       3, 1.5, true),
    ('DATA_AN',  'Communication',                3, 1.0, false),
    ('DATA_AN',  'Problem Solving',              3, 1.0, false),
    ('ML_ENG',   'Python',                       4, 2.0, true),
    ('ML_ENG',   'Machine Learning',             4, 2.0, true),
    ('ML_ENG',   'SQL',                          3, 1.0, false),
    ('ML_ENG',   'Data Structures & Algorithms', 3, 1.0, false),
    ('DEVOPS',   'Cloud (AWS/Azure)',            4, 2.0, true),
    ('DEVOPS',   'Docker',                       4, 2.0, true),
    ('DEVOPS',   'Git',                          3, 1.0, false),
    ('DEVOPS',   'Python',                       2, 0.5, false),
    ('EMBEDDED', 'Embedded C',                   4, 2.0, true),
    ('EMBEDDED', 'C',                            4, 1.5, true),
    ('EMBEDDED', 'MATLAB',                       2, 0.5, false),
    ('EMBEDDED', 'Problem Solving',              3, 1.0, false),
    ('DESIGN_E', 'AutoCAD',                      4, 2.0, true),
    ('DESIGN_E', 'MATLAB',                       2, 1.0, false),
    ('DESIGN_E', 'Communication',                3, 1.0, false),
    ('DESIGN_E', 'Teamwork',                     3, 1.0, false),
    ('QA',       'Problem Solving',              3, 1.5, true),
    ('QA',       'Java',                         3, 1.0, false),
    ('QA',       'SQL',                          3, 1.0, false),
    ('QA',       'Communication',                3, 1.0, false),
    ('DBA',      'SQL',                          4, 2.5, true),
    ('DBA',      'MongoDB',                      3, 1.0, false),
    ('DBA',      'Docker',                       2, 0.5, false),
    ('SUPPORT',  'Communication',                4, 2.0, true),
    ('SUPPORT',  'Problem Solving',              3, 1.5, true),
    ('SUPPORT',  'Aptitude',                     3, 1.0, false),
    ('SUPPORT',  'SQL',                          2, 0.5, false),
    ('BIZ_AN',   'Communication',                4, 2.0, true),
    ('BIZ_AN',   'Aptitude',                     4, 1.5, true),
    ('BIZ_AN',   'SQL',                          3, 1.0, false),
    ('BIZ_AN',   'Teamwork',                     3, 1.0, false)
) AS v(career_code, skill_name, lvl, wt, core)
JOIN careers c ON c.code = v.career_code
JOIN skills s ON s.name = v.skill_name AND s.is_active;

-- One free starting point per in-demand skill, so a gap always comes with a next step.
INSERT INTO courses (skill_id, title, provider, url, level, duration_hours, is_certification, is_free)
SELECT s.id, v.title, v.provider, v.url, v.lvl, v.hrs, v.cert, v.free
FROM (VALUES
    ('Data Structures & Algorithms', 'Data Structures and Algorithms', 'NPTEL',        'https://nptel.ac.in',                3, 40, true,  true),
    ('Python',                       'Scientific Computing with Python','freeCodeCamp','https://www.freecodecamp.org/learn', 3, 30, true,  true),
    ('JavaScript',                   'JavaScript Algorithms and Data Structures', 'freeCodeCamp', 'https://www.freecodecamp.org/learn', 3, 35, true, true),
    ('React',                        'Front End Development Libraries', 'freeCodeCamp','https://www.freecodecamp.org/learn', 3, 30, true,  true),
    ('Node.js',                      'Back End Development and APIs', 'freeCodeCamp',  'https://www.freecodecamp.org/learn', 3, 30, true,  true),
    ('HTML/CSS',                     'Responsive Web Design',         'freeCodeCamp',  'https://www.freecodecamp.org/learn', 2, 25, true,  true),
    ('SQL',                          'Relational Database Course',    'freeCodeCamp',  'https://www.freecodecamp.org/learn', 3, 20, true,  true),
    ('Java',                         'Programming in Java',           'NPTEL',         'https://nptel.ac.in',                3, 40, true,  true),
    ('C',                            'Problem Solving through Programming in C', 'NPTEL', 'https://nptel.ac.in',             2, 40, true,  true),
    ('Machine Learning',             'Introduction to Machine Learning', 'NPTEL',       'https://nptel.ac.in',               4, 40, true,  true),
    ('Git',                          'Git and GitHub Basics',         'roadmap.sh',    'https://roadmap.sh',                 2, 8,  false, true),
    ('Docker',                        'Docker Roadmap',               'roadmap.sh',    'https://roadmap.sh',                 3, 15, false, true),
    ('Cloud (AWS/Azure)',            'Cloud Computing',               'NPTEL',         'https://nptel.ac.in',                3, 40, true,  true),
    ('Embedded C',                   'Embedded Systems Design',       'NPTEL',         'https://nptel.ac.in',                3, 40, true,  true),
    ('Aptitude',                     'Quantitative Aptitude Practice','In-house',       NULL,                                2, 20, false, true),
    ('Communication',                'Soft Skills and Interview Preparation', 'In-house', NULL,                              2, 15, false, true)
) AS v(skill_name, title, provider, url, lvl, hrs, cert, free)
JOIN skills s ON s.name = v.skill_name AND s.is_active;

-- ---------- permissions ----------

INSERT INTO permissions (module, action, slug, description) VALUES
    ('career', 'view',   'career.view',   'View the career catalogue and career matches'),
    ('career', 'create', 'career.create', 'Add careers and their required skills'),
    ('career', 'update', 'career.update', 'Edit careers, required skills and courses'),
    ('career', 'delete', 'career.delete', 'Remove careers and courses'),
    ('career', 'run',    'career.run',    'Recompute career matches for students'),
    ('config', 'view',   'config.view',   'View scoring weights and settings'),
    ('config', 'update', 'config.update', 'Change scoring weights and settings');

-- Admin: everything. Placement officer and HOD: catalogue plus recompute. Staff: read.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.module IN ('career', 'config')
WHERE r.slug = 'admin'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug IN ('career.view', 'career.create', 'career.update', 'career.run', 'config.view')
WHERE r.slug IN ('placement_officer', 'hod')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug IN ('career.view', 'career.run')
WHERE r.slug = 'staff'
ON CONFLICT DO NOTHING;

-- Students and parents see the catalogue and the student's own matches.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'career.view'
WHERE r.slug IN ('student', 'parent')
ON CONFLICT DO NOTHING;

-- ---------- backfill ----------
-- The analyzer now reads blended scores, so every skill already on record needs one before
-- the upgraded build serves a ranking. These are the same statements the recompute service
-- runs (internal/modules/skillscore); there is no assessment or academic evidence yet, since
-- those tables arrive with this migration.

INSERT INTO skill_scores (student_id, skill_id, source, score, detail, created_by, updated_by)
SELECT x.student_id, x.skill_id, 'declared', (x.proficiency * 20)::numeric,
       jsonb_build_object('proficiency', x.proficiency, 'entered_as', x.source),
       x.created_by, x.updated_by
FROM student_skills x
WHERE x.is_active;

WITH cfg AS (
    SELECT value AS v FROM app_config WHERE key = 'skill_score_weights'
), parts AS (
    SELECT s.student_id, s.skill_id, s.source, s.score, s.created_by, s.updated_by,
           COALESCE((SELECT (v ->> s.source)::numeric FROM cfg), 0) AS wt
    FROM skill_scores s
    WHERE s.is_active AND s.source <> 'blended'
)
INSERT INTO skill_scores (student_id, skill_id, source, score, detail, created_by, updated_by)
SELECT student_id, skill_id, 'blended',
       LEAST(100, GREATEST(0, ROUND(SUM(score * wt) / SUM(wt), 2))),
       jsonb_build_object('scores', jsonb_object_agg(source, score), 'weights', jsonb_object_agg(source, wt)),
       min(created_by), min(updated_by)
FROM parts
GROUP BY student_id, skill_id
HAVING SUM(wt) > 0;
