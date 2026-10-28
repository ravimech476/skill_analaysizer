-- Project ideas a student can build to show the skills a career asks for. Shown in the placement prep plan.
CREATE TABLE career_project_ideas (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    career_id   bigint      NOT NULL REFERENCES careers (id),
    title       varchar(150) NOT NULL,
    description text,
    level       smallint    NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 3),
    is_active   boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_career_project_ideas_career ON career_project_ideas (career_id) WHERE is_active;

INSERT INTO career_project_ideas (career_id, title, description, level)
SELECT c.id, v.title, v.description, v.level
FROM (VALUES
    ('SDE',       'Task manager with a REST API and tests',        'Build create, update and delete for tasks, add unit tests and publish the code.', 2),
    ('SDE',       'Algorithm visualiser',                          'Show how sorting and searching algorithms work step by step.', 2),
    ('FULLSTACK', 'Expense tracker with login',                    'A web app with sign-up, a database and a simple chart of spending.', 2),
    ('FULLSTACK', 'Mini online store',                             'Product list, cart and order history with a real database.', 3),
    ('BACKEND',   'URL shortener with caching',                    'An API that shortens links, counts visits and caches popular ones.', 2),
    ('BACKEND',   'Library API with authentication',               'Books, members and loans behind a secured API with a documented schema.', 2),
    ('DATA_AN',   'Sales dashboard from a public dataset',         'Clean a dataset, answer five questions with charts and write down what you found.', 1),
    ('DATA_AN',   'Student marks analysis report',                 'Analyse a class marks sheet for trends and write a one-page summary.', 2),
    ('ML_ENG',    'House price predictor',                         'Train and compare two models and explain which features matter.', 2),
    ('ML_ENG',    'Spam message classifier',                       'Turn text into features, train a classifier and measure its mistakes.', 2),
    ('DEVOPS',    'Deploy a web app with Docker and CI',           'Containerise an app and run tests automatically on every push.', 2),
    ('DEVOPS',    'Monitor a service with alerts',                 'Collect basic metrics from a running service and raise an alert when it fails.', 3),
    ('EMBEDDED',  'Sensor data logger',                            'Read a sensor with a microcontroller and store readings with timestamps.', 2),
    ('EMBEDDED',  'Home automation relay controller',              'Switch a load on a schedule or from a phone and handle failures safely.', 3),
    ('DESIGN_E',  'CAD model of a small mechanism',                'Model the parts of a simple mechanism and check that they assemble.', 1),
    ('DESIGN_E',  'Stress analysis of a simple part',              'Run a basic analysis and compare the result with a hand calculation.', 3),
    ('QA',        'Test plan and bug report for a mobile app',     'Write test cases, run them and report defects clearly.', 1),
    ('QA',        'Automated tests for a sample web app',          'Write repeatable tests for key screens and run them in a pipeline.', 2),
    ('DBA',       'Normalised database for a college',             'Design tables for students, courses and marks with keys and constraints.', 1),
    ('DBA',       'Backup and query tuning exercise',              'Plan backups and speed up three slow queries with indexes.', 3),
    ('SUPPORT',   'Troubleshooting guide',                         'Write a guide for ten common computer and network problems.', 1),
    ('SUPPORT',   'Small office network in a simulator',           'Set up addressing, a shared printer and a basic firewall rule.', 2),
    ('BIZ_AN',    'Requirements document for a campus app',        'Interview users and write clear requirements and user stories.', 1),
    ('BIZ_AN',    'Process flow and gap analysis',                 'Map how a college service works today and propose improvements.', 2)
) AS v(code, title, description, level)
JOIN careers c ON c.code = v.code;
