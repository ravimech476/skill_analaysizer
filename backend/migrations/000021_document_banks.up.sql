-- Interview Bank and Question Bank as document libraries: one row per document (a company's interview
-- questions and answers, a question paper) with an uploaded file, the same way Study Materials work.
-- The earlier per-question tables (interview_questions, question_bank) stay as they are.

CREATE TABLE IF NOT EXISTS interview_documents (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id  bigint NOT NULL REFERENCES companies(id),
    title       varchar(200) NOT NULL,
    doc_type    varchar(30) NOT NULL DEFAULT 'mixed'
                CHECK (doc_type IN ('technical', 'aptitude', 'hr', 'coding', 'group_discussion', 'case_study', 'mixed')),
    role        varchar(150),
    year        integer CHECK (year BETWEEN 2000 AND 2100),
    description text,
    tags        varchar(500),
    file_id     bigint REFERENCES files(id),
    is_active   boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    created_by  bigint REFERENCES users(id),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    updated_by  bigint REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS ix_interview_documents_company ON interview_documents (company_id) WHERE is_active;
CREATE TRIGGER trg_interview_documents_updated_at BEFORE UPDATE ON interview_documents
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS question_papers (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_id   bigint NOT NULL REFERENCES subjects(id),
    title        varchar(200) NOT NULL,
    doc_type     varchar(30) NOT NULL DEFAULT 'question_paper'
                 CHECK (doc_type IN ('question_paper', 'model_paper', 'important_questions', 'answer_key')),
    exam_type_id bigint REFERENCES exam_types(id),
    year         integer CHECK (year BETWEEN 2000 AND 2100),
    semester     varchar(30),
    unit         varchar(50),
    max_marks    integer CHECK (max_marks BETWEEN 0 AND 1000),
    description  text,
    file_id      bigint REFERENCES files(id),
    is_active    boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    created_by   bigint REFERENCES users(id),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    updated_by   bigint REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS ix_question_papers_subject ON question_papers (subject_id) WHERE is_active;
CREATE TRIGGER trg_question_papers_updated_at BEFORE UPDATE ON question_papers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Their files.
ALTER TABLE files DROP CONSTRAINT IF EXISTS files_category_check;
ALTER TABLE files ADD CONSTRAINT files_category_check CHECK (category IN (
    'profile_photo', 'resume', 'certificate', 'offer_letter', 'student_document', 'company_logo',
    'job_description', 'notification_attachment', 'study_material', 'interview_document', 'question_paper'));
