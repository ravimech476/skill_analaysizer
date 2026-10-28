-- Communication and soft skills (self-report questionnaire + staff rubric) and an aptitude test
-- (question bank, timed attempts, automatic scoring).

-- The communication questionnaire is one more assessment kind.
ALTER TABLE student_assessments DROP CONSTRAINT IF EXISTS student_assessments_kind_check;
ALTER TABLE student_assessments ADD CONSTRAINT student_assessments_kind_check
    CHECK (kind IN ('personality', 'interests', 'learning', 'communication'));

-- A staff member rates a student's communication on four criteria (1 to 5). The latest review counts.
CREATE TABLE IF NOT EXISTS communication_reviews (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id  bigint NOT NULL REFERENCES users(id),
    -- {"speaking":1-5,"writing":1-5,"listening":1-5,"teamwork":1-5}
    rubric      jsonb NOT NULL,
    score       numeric(5,2) NOT NULL,
    notes       text,
    is_active   boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    created_by  bigint REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS ix_communication_reviews_latest ON communication_reviews (student_id, id DESC) WHERE is_active;

CREATE TABLE IF NOT EXISTS aptitude_questions (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    section     varchar(20) NOT NULL CHECK (section IN ('quantitative', 'logical', 'verbal')),
    question    text NOT NULL,
    option_a    varchar(300) NOT NULL,
    option_b    varchar(300) NOT NULL,
    option_c    varchar(300) NOT NULL,
    option_d    varchar(300) NOT NULL,
    correct     char(1) NOT NULL CHECK (correct IN ('a', 'b', 'c', 'd')),
    explanation text,
    is_active   boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    created_by  bigint REFERENCES users(id),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    updated_by  bigint REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS ix_aptitude_questions_section ON aptitude_questions (section) WHERE is_active;
CREATE TRIGGER trg_aptitude_questions_updated_at BEFORE UPDATE ON aptitude_questions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- An attempt records which questions were asked, so the answers can be checked on the server and the time limit enforced.
CREATE TABLE IF NOT EXISTS aptitude_attempts (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id     bigint NOT NULL REFERENCES users(id),
    question_ids   jsonb NOT NULL,
    answers        jsonb,
    score          numeric(5,2),
    section_scores jsonb,
    time_limit_sec integer NOT NULL,
    started_at     timestamptz NOT NULL DEFAULT now(),
    submitted_at   timestamptz,
    status         varchar(12) NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'submitted', 'expired'))
);
CREATE INDEX IF NOT EXISTS ix_aptitude_attempts_student ON aptitude_attempts (student_id, id DESC);

-- Permissions: staff manage the question bank with the question-bank permissions (already granted).

INSERT INTO aptitude_questions (section, question, option_a, option_b, option_c, option_d, correct, explanation)
SELECT v.* FROM (VALUES
  -- quantitative
  ('quantitative', 'A train travels 120 km in 2 hours. What is its speed in km/h?', '40', '50', '60', '80', 'c', 'Speed = distance / time = 120 / 2 = 60.'),
  ('quantitative', 'What is 15% of 240?', '36', '24', '30', '40', 'a', '15/100 x 240 = 36.'),
  ('quantitative', 'If 3x + 5 = 20, what is x?', '4', '5', '3', '6', 'b', '3x = 15, so x = 5.'),
  ('quantitative', 'The ratio of boys to girls in a class is 3:2. If there are 30 boys, how many girls are there?', '25', '15', '18', '20', 'd', '30 / 3 = 10 per part, so girls = 2 x 10 = 20.'),
  ('quantitative', 'A shopkeeper buys an item for 200 and sells it for 250. What is the profit percentage?', '25%', '30%', '20%', '50%', 'a', 'Profit 50 on cost 200 = 25%.'),
  ('quantitative', 'What is the simple interest on 5000 at 8% per annum for 3 years?', '1000', '1200', '1500', '2000', 'b', 'SI = 5000 x 8 x 3 / 100 = 1200.'),
  ('quantitative', 'A can finish a job in 10 days and B in 15 days. Working together, how many days will they take?', '8', '5', '6', '7', 'c', 'Together they do 1/10 + 1/15 = 1/6 of the job a day, so 6 days.'),
  ('quantitative', 'What is the average of 4, 8, 12 and 16?', '12', '11', '10', '9', 'c', 'Sum 40 / 4 = 10.'),
  ('quantitative', 'What is the next number in the series 2, 6, 12, 20, 30, ?', '42', '40', '44', '36', 'a', 'Differences grow by 2: +4, +6, +8, +10, so next is +12 = 42.'),
  ('quantitative', 'A square has a perimeter of 36 cm. What is its area?', '100', '81', '72', '64', 'b', 'Side = 9 cm, area = 81 square cm.'),
  -- logical
  ('logical', 'Find the odd one out.', 'Python', 'Java', 'Linux', 'C++', 'c', 'Python, Java and C++ are programming languages; Linux is an operating system.'),
  ('logical', 'If MONDAY is written as NPOEBZ (each letter moved one place forward), how is FRIDAY written?', 'GSJEBZ', 'GSIEBZ', 'ESHCZX', 'GRJEBZ', 'a', 'F-G, R-S, I-J, D-E, A-B, Y-Z.'),
  ('logical', 'Ravi is taller than Sam. Sam is taller than Tara. Who is the shortest?', 'Ravi', 'Sam', 'Tara', 'Cannot be determined', 'c', 'Ravi > Sam > Tara.'),
  ('logical', 'A is the brother of B. B is the sister of C. How is C related to A?', 'Brother', 'Sister', 'Cousin', 'Brother or sister', 'd', 'C is a sibling of A, but C''s gender is not given.'),
  ('logical', 'Which number does not belong: 9, 16, 30, 36?', '9', '16', '30', '36', 'c', '9, 16 and 36 are perfect squares; 30 is not.'),
  ('logical', 'All roses are flowers, and some flowers fade quickly. Which statement is certainly true?', 'All flowers are roses', 'No rose fades quickly', 'All flowers fade quickly', 'Roses are flowers', 'd', 'Only the first premise is guaranteed.'),
  ('logical', 'Complete the pattern: 1, 4, 9, 16, ?', '20', '24', '36', '25', 'd', 'Square numbers: 1, 4, 9, 16, 25.'),
  ('logical', 'Today is Wednesday. What day will it be after 10 days?', 'Friday', 'Saturday', 'Sunday', 'Monday', 'b', '10 days = 1 week + 3 days; Wednesday + 3 = Saturday.'),
  ('logical', 'Which word is the odd one out?', 'Apple', 'Mango', 'Banana', 'Carrot', 'd', 'Apple, mango and banana are fruits; carrot is a vegetable.'),
  ('logical', 'Complete the series: 3, 6, 12, 24, ?', '36', '48', '42', '60', 'b', 'Each number doubles.'),
  -- verbal
  ('verbal', 'Choose the word closest in meaning to RAPID.', 'Slow', 'Late', 'Quick', 'Weak', 'c', 'Rapid means quick.'),
  ('verbal', 'Choose the word opposite in meaning to ANCIENT.', 'Old', 'Antique', 'Historic', 'Modern', 'd', 'Ancient means very old; modern is the opposite.'),
  ('verbal', 'Fill in the blank: She ____ to college every day.', 'go', 'goes', 'going', 'gone', 'b', 'A singular subject in the present tense takes "goes".'),
  ('verbal', 'Choose the correctly spelt word.', 'Recieve', 'Reciev', 'Receve', 'Receive', 'd', 'i before e, except after c.'),
  ('verbal', 'Fill in the blank: He is good ____ mathematics.', 'at', 'in', 'on', 'with', 'a', 'The phrase is "good at".'),
  ('verbal', 'Choose the correct sentence.', 'He doesn''t likes tea.', 'He not like tea.', 'He doesn''t like tea.', 'He don''t like tea.', 'c', 'After "doesn''t" the verb stays in its base form.'),
  ('verbal', 'What does the phrase "to beat around the bush" mean?', 'To avoid the main point', 'To search a garden', 'To hit someone', 'To plant a tree', 'a', 'It means to avoid getting to the point.'),
  ('verbal', 'Fill in the blank: The manager was ____ by the team''s excellent performance.', 'impress', 'impression', 'impressing', 'impressed', 'd', 'The passive form needs the past participle "impressed".'),
  ('verbal', 'Choose the synonym of BRIEF.', 'Long', 'Short', 'Heavy', 'Wide', 'b', 'Brief means short.'),
  ('verbal', 'Choose the correct plural of "child".', 'childs', 'childes', 'children', 'childrens', 'c', 'Child has an irregular plural.')
) AS v(section, question, option_a, option_b, option_c, option_d, correct, explanation)
WHERE NOT EXISTS (SELECT 1 FROM aptitude_questions);

-- Only staff can see or change aptitude questions: the list includes the correct answers.
INSERT INTO permissions (module, action, slug, description) VALUES
    ('aptitude', 'view', 'aptitude.view', 'View aptitude test questions and answers'),
    ('aptitude', 'create', 'aptitude.create', 'Add aptitude test questions'),
    ('aptitude', 'update', 'aptitude.update', 'Edit aptitude test questions'),
    ('aptitude', 'delete', 'aptitude.delete', 'Delete aptitude test questions')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.module = 'aptitude'
WHERE r.slug IN ('admin', 'staff', 'hod')
ON CONFLICT DO NOTHING;
