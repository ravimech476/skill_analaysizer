-- Career fit: what a role asks of a person (interest code, personality traits, how much it relies
-- on programming) and an indicative outlook, so matching can use more than skills and marks.
ALTER TABLE careers
    ADD COLUMN holland_code     varchar(3),
    ADD COLUMN key_traits       text[]        NOT NULL DEFAULT '{}',
    ADD COLUMN coding_relevance numeric(3, 2) NOT NULL DEFAULT 0 CHECK (coding_relevance BETWEEN 0 AND 1),
    ADD COLUMN growth_outlook   smallint CHECK (growth_outlook BETWEEN 1 AND 5),
    ADD COLUMN growth_note      text;

ALTER TABLE career_matches ADD COLUMN fit jsonb;

UPDATE careers c SET holland_code = v.holland, key_traits = v.traits, coding_relevance = v.coding,
                     growth_outlook = v.outlook, growth_note = v.note
FROM (VALUES
    ('SDE',       'IRC', ARRAY['conscientiousness','openness'],                          1.00, 5, 'Steady demand across product and service companies.'),
    ('FULLSTACK', 'IAC', ARRAY['openness','conscientiousness'],                          1.00, 5, 'Small teams and start-ups prefer people who can work across the stack.'),
    ('BACKEND',   'ICR', ARRAY['conscientiousness','stability'],                         1.00, 5, 'Core to every product; growing with cloud and API work.'),
    ('DATA_AN',   'ICE', ARRAY['conscientiousness','openness'],                          0.60, 5, 'Growing as companies rely more on data for decisions.'),
    ('ML_ENG',    'IRA', ARRAY['openness','conscientiousness'],                          0.90, 5, 'Fast-growing but competitive; usually expects strong maths and projects.'),
    ('DEVOPS',    'RIC', ARRAY['conscientiousness','stability'],                         0.70, 4, 'Demand follows cloud adoption.'),
    ('EMBEDDED',  'RIC', ARRAY['conscientiousness','openness'],                          0.60, 4, 'Growing with devices, automotive and IoT.'),
    ('DESIGN_E',  'RIA', ARRAY['openness','conscientiousness'],                          0.20, 3, 'Stable demand in core engineering firms.'),
    ('QA',        'CIR', ARRAY['conscientiousness','agreeableness'],                     0.50, 3, 'Stable; moving towards test automation.'),
    ('DBA',       'CIR', ARRAY['conscientiousness','stability'],                         0.40, 3, 'Stable; cloud-managed databases are changing the work.'),
    ('SUPPORT',   'SRC', ARRAY['agreeableness','stability','extraversion'],              0.20, 3, 'Many openings; a common first step into other roles.'),
    ('BIZ_AN',    'ESC', ARRAY['extraversion','agreeableness','conscientiousness'],      0.10, 4, 'Steady demand where technology meets business.')
) AS v(code, holland, traits, coding, outlook, note)
WHERE c.code = v.code;
