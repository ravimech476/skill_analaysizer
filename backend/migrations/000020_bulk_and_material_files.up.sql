-- 1. Bulk imports of departments, subjects, companies, exam types, academic years, the skill list and
--    placement drives were rejected by the database (it only knew students, staff, marks and skills),
--    so they failed with an internal error. Allow every import type, including the three new ones.
ALTER TABLE bulk_upload_jobs DROP CONSTRAINT IF EXISTS bulk_upload_jobs_upload_type_check;
ALTER TABLE bulk_upload_jobs ADD CONSTRAINT bulk_upload_jobs_upload_type_check CHECK (upload_type IN (
    'students', 'staff', 'marks', 'skills',
    'departments', 'subjects', 'companies', 'exam_types', 'academic_years', 'skill_master', 'placement_drives',
    'interview_questions', 'study_materials', 'question_bank'));

-- 2. Study materials can carry an uploaded file (PDF, Word or PowerPoint).
ALTER TABLE files DROP CONSTRAINT IF EXISTS files_category_check;
ALTER TABLE files ADD CONSTRAINT files_category_check CHECK (category IN (
    'profile_photo', 'resume', 'certificate', 'offer_letter', 'student_document', 'company_logo',
    'job_description', 'notification_attachment', 'study_material'));
