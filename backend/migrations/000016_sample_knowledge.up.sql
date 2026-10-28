-- Sample knowledge base for the AI chat assistant: interview questions (company-wise and general),
-- resume tips, career roadmaps, study materials and extra courses. Everything is guarded so it is
-- safe to re-run and never duplicates rows an admin has already entered.

-- Interview questions: company-wise (matched by company name) and general (company_id NULL).
INSERT INTO interview_questions (company_id, category, question, answer, difficulty, tags)
SELECT c.id, v.category, v.question, v.answer, v.difficulty, v.tags
FROM (VALUES
  ('TCS', 'technical', 'What is the difference between an array and a linked list?',
   'Arrays store elements contiguously with O(1) index access but costly insertion/deletion; linked lists use nodes with pointers, giving O(1) insertion at a known node but O(n) access.', 'easy', 'dsa,array,linked-list'),
  ('TCS', 'technical', 'Explain the four pillars of object-oriented programming.',
   'Encapsulation, abstraction, inheritance and polymorphism. Give one short example of each in Java or C++.', 'easy', 'oop,java'),
  ('TCS', 'aptitude', 'A train 150 m long passes a pole in 15 seconds. What is its speed in km/h?',
   'Speed = 150/15 = 10 m/s = 36 km/h.', 'easy', 'aptitude,speed-distance'),
  ('TCS', 'hr', 'Why do you want to join TCS?',
   'Mention the company''s scale, training programme (ILP), learning culture and projects across domains, and link them to your own goals.', 'easy', 'hr'),
  ('Zoho', 'technical', 'Write a program to reverse a string without using built-in reverse functions.',
   'Swap characters from both ends with two pointers until they meet. Time O(n), space O(1) if done in place.', 'easy', 'strings,logic'),
  ('Zoho', 'technical', 'Find the second largest element in an array in one pass.',
   'Keep two variables, largest and second; update them while scanning. Handle duplicates and arrays with fewer than two distinct values.', 'medium', 'arrays,logic'),
  ('Zoho', 'technical', 'Explain how a hash map works and how collisions are handled.',
   'A hash function maps keys to buckets. Collisions are handled by chaining (linked lists/trees per bucket) or open addressing (probing). Average O(1) lookup.', 'medium', 'dsa,hashing'),
  ('Zoho', 'technical', 'Design a parking lot system. What classes would you create?',
   'ParkingLot, Level, Spot (with types), Vehicle (Car, Bike), Ticket and a payment component. Discuss spot allocation and extensibility.', 'hard', 'design,oop'),
  ('Infosys', 'technical', 'What is the difference between SQL joins: INNER, LEFT, RIGHT and FULL?',
   'INNER returns matching rows only; LEFT keeps all left rows; RIGHT keeps all right rows; FULL keeps all rows from both with NULLs where no match.', 'easy', 'sql,joins'),
  ('Infosys', 'technical', 'What is normalization? Explain 1NF, 2NF and 3NF.',
   '1NF: atomic values; 2NF: no partial dependency on a composite key; 3NF: no transitive dependency. It reduces redundancy and update anomalies.', 'medium', 'dbms,normalization'),
  ('Infosys', 'aptitude', 'If the ratio of boys to girls in a class is 3:2 and there are 40 students, how many girls are there?',
   'Girls = 2/5 x 40 = 16.', 'easy', 'aptitude,ratio'),
  ('Infosys', 'hr', 'Tell me about a time you worked in a team and faced a disagreement.',
   'Use the STAR method: Situation, Task, Action, Result. Stress listening, finding common ground and the outcome.', 'medium', 'hr,star')
) AS v(company, category, question, answer, difficulty, tags)
JOIN companies c ON c.name = v.company
WHERE NOT EXISTS (SELECT 1 FROM interview_questions q WHERE q.question = v.question);

INSERT INTO interview_questions (company_id, category, question, answer, difficulty, tags)
SELECT NULL, v.category, v.question, v.answer, v.difficulty, v.tags
FROM (VALUES
  ('technical', 'What is the time complexity of binary search and what must be true of the input?',
   'O(log n). The input must be sorted (or otherwise monotonic) and support random access.', 'easy', 'dsa,searching'),
  ('technical', 'Explain the difference between a process and a thread.',
   'A process has its own memory space; threads of one process share memory and are lighter to create and switch between.', 'medium', 'os,threads'),
  ('technical', 'What is a deadlock and what are the four conditions for it?',
   'Processes wait on each other forever. Conditions: mutual exclusion, hold and wait, no preemption, circular wait. Break any one to prevent it.', 'medium', 'os,deadlock'),
  ('technical', 'What is the difference between stack and heap memory?',
   'The stack holds call frames and local variables with automatic, fast allocation; the heap holds dynamically allocated objects managed manually or by a garbage collector.', 'easy', 'memory'),
  ('technical', 'What are ACID properties in databases?',
   'Atomicity, Consistency, Isolation, Durability: guarantees that make transactions reliable.', 'medium', 'dbms,transactions'),
  ('aptitude', 'A can finish a job in 12 days and B in 18 days. How long will they take together?',
   'Combined rate = 1/12 + 1/18 = 5/36 per day, so 36/5 = 7.2 days.', 'medium', 'aptitude,time-work'),
  ('aptitude', 'What is the next number in the series 2, 6, 12, 20, 30, ?',
   'Differences grow by 2 (4, 6, 8, 10), so the next is 42.', 'easy', 'aptitude,series'),
  ('hr', 'Tell me about yourself.',
   'Keep it to about a minute: education, one or two projects or skills, and what you are looking for. Avoid reading your resume aloud.', 'easy', 'hr'),
  ('hr', 'What are your strengths and weaknesses?',
   'Pick real strengths backed by an example. For a weakness, name something genuine and say what you are doing to improve it.', 'easy', 'hr'),
  ('hr', 'Where do you see yourself in five years?',
   'Show ambition tied to the role: growing technical depth, taking ownership of larger modules, and mentoring others.', 'easy', 'hr'),
  ('resume', 'Resume tip: how long should a fresher''s resume be and what should it include?',
   'One page. Include contact details, a two-line objective, education with CGPA, skills grouped by type, 2 to 3 projects with your role and tools, internships, certifications and achievements. Use a clean single-column layout.', 'easy', 'resume,tips'),
  ('resume', 'Resume tip: how do I describe a project well?',
   'Use one line on what it does, then bullets that start with action verbs and show impact, for example "Built a REST API in Go that handles 500 requests per second". Mention the tech stack and a link to the code.', 'easy', 'resume,projects'),
  ('resume', 'Resume tip: what mistakes should I avoid?',
   'Typos, long paragraphs, unexplained skill lists, fake or inflated claims, unprofessional email addresses, and including projects you cannot explain in an interview.', 'easy', 'resume,mistakes'),
  ('career', 'Career roadmap: how do I become a software developer?',
   'Learn one language well (Java, Python or JavaScript), then data structures and algorithms, Git, SQL and one framework. Build 2 to 3 projects, solve problems regularly, and practise mock interviews. Aim for an internship in your pre-final year.', 'medium', 'roadmap,sde'),
  ('career', 'Career roadmap: how do I become a data analyst or ML engineer?',
   'Start with Python, SQL and statistics. Learn pandas, visualisation and then machine-learning basics (scikit-learn). Build projects on real datasets, publish them on GitHub, and add one cloud or deployment skill.', 'medium', 'roadmap,data,ml'),
  ('career', 'Career roadmap: how do I prepare for placements in the final year?',
   'Months 1 to 2: aptitude and core subjects. Months 3 to 4: DSA and coding practice. Month 5: projects and resume. Month 6 onward: mock interviews, company-wise questions and applying to every drive you are eligible for.', 'medium', 'roadmap,placement')
) AS v(category, question, answer, difficulty, tags)
WHERE NOT EXISTS (SELECT 1 FROM interview_questions q WHERE q.question = v.question);

-- Study materials (notes and question papers), linked to existing subjects by code.
INSERT INTO study_materials (subject_id, title, material_type, description, url)
SELECT s.id, v.title, v.material_type, v.description, v.url
FROM (VALUES
  ('CS3301', 'Data Structures: arrays, stacks and queues notes', 'notes', 'Unit-wise notes covering arrays, linked lists, stacks and queues with worked examples.', NULL),
  ('CS3301', 'Data Structures: trees and graphs notes', 'notes', 'Binary trees, BST, heaps, graph traversals (BFS, DFS) and shortest paths.', NULL),
  ('CS3301', 'Data Structures previous year question paper', 'question_paper', 'Last three end-semester papers with a unit-wise question list.', NULL),
  ('CS3311', 'Data Structures Lab manual', 'notes', 'Lab programs and expected outputs for every experiment.', NULL),
  ('MA3301', 'Discrete Mathematics: logic and sets notes', 'notes', 'Propositional logic, sets, relations and functions with solved problems.', NULL),
  ('CS3401', 'Operating Systems: process scheduling notes', 'notes', 'CPU scheduling algorithms, synchronisation and deadlocks with examples.', NULL),
  ('CS3401', 'Operating Systems previous year question paper', 'question_paper', 'Recent end-semester papers with model answers.', NULL),
  ('CS3402', 'DBMS: SQL and normalization notes', 'notes', 'SQL queries, joins, keys, functional dependencies and normal forms.', NULL),
  ('CS3402', 'DBMS previous year question paper', 'question_paper', 'Recent end-semester papers with model answers.', NULL),
  ('CS3411', 'DBMS Lab practice queries', 'notes', 'Practice SQL queries from basic SELECT to nested queries and views.', NULL),
  ('EC3301', 'Signals and Systems formula sheet', 'notes', 'Fourier, Laplace and Z-transform formulas and properties in one place.', NULL),
  ('EC3302', 'Electronic Circuits notes', 'notes', 'Amplifier configurations, biasing and frequency response.', NULL)
) AS v(code, title, material_type, description, url)
JOIN subjects s ON s.code = v.code
WHERE NOT EXISTS (SELECT 1 FROM study_materials m WHERE m.subject_id = s.id AND m.title = v.title);

-- More courses: SWAYAM and Coursera alongside the existing NPTEL and freeCodeCamp ones.
INSERT INTO courses (skill_id, title, provider, url, level, duration_hours, is_certification, is_free)
SELECT sk.id, v.title, v.provider, v.url, v.level, v.hours, v.cert, v.free
FROM (VALUES
  ('Data Structures & Algorithms', 'Data Structures and Algorithms', 'SWAYAM', 'https://swayam.gov.in', 3, 40, true, true),
  ('Data Structures & Algorithms', 'Algorithms Specialization', 'Coursera', 'https://www.coursera.org', 4, 80, true, false),
  ('Python', 'Python for Everybody', 'Coursera', 'https://www.coursera.org', 1, 30, true, false),
  ('SQL', 'Introduction to Databases and SQL', 'SWAYAM', 'https://swayam.gov.in', 2, 30, true, true),
  ('SQL', 'SQL for Data Science', 'Coursera', 'https://www.coursera.org', 2, 20, true, false),
  ('Machine Learning', 'Machine Learning', 'Coursera', 'https://www.coursera.org', 3, 60, true, false),
  ('Machine Learning', 'Introduction to Machine Learning', 'NPTEL', 'https://nptel.ac.in', 3, 40, true, true),
  ('Aptitude', 'Quantitative Aptitude for Placements', 'SWAYAM', 'https://swayam.gov.in', 2, 25, false, true),
  ('Communication', 'English Communication Skills', 'SWAYAM', 'https://swayam.gov.in', 1, 30, false, true),
  ('Communication', 'Business English Communication Skills', 'Coursera', 'https://www.coursera.org', 2, 25, true, false),
  ('Problem Solving', 'Problem Solving Techniques', 'NPTEL', 'https://nptel.ac.in', 2, 30, false, true),
  ('Teamwork', 'Teamwork and Collaboration', 'Coursera', 'https://www.coursera.org', 1, 10, false, false),
  ('Git', 'Version Control with Git', 'Coursera', 'https://www.coursera.org', 1, 10, false, false),
  ('Cloud (AWS/Azure)', 'Cloud Computing', 'NPTEL', 'https://nptel.ac.in', 3, 40, true, true)
) AS v(skill, title, provider, url, level, hours, cert, free)
JOIN skills sk ON sk.name = v.skill
WHERE NOT EXISTS (SELECT 1 FROM courses c WHERE c.skill_id = sk.id AND c.title = v.title AND c.provider = v.provider);
