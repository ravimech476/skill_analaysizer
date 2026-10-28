-- Knowledge base for the AI assistant: uploaded documents (syllabus, notes, question papers…) cut into
-- passages, each stored with an embedding vector so questions can be matched by meaning.
-- Vectors are plain real[] and compared in the application, so no pgvector extension is needed.

CREATE TABLE IF NOT EXISTS kb_documents (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title         varchar(200) NOT NULL,
    doc_type      varchar(30) NOT NULL DEFAULT 'notes'
                  CHECK (doc_type IN ('syllabus', 'notes', 'question_paper', 'placement', 'resume', 'roadmap', 'other')),
    -- limit who can retrieve it: NULL means everyone
    department_id bigint REFERENCES departments(id),
    subject_id    bigint REFERENCES subjects(id),
    source_name   varchar(255) NOT NULL,
    chunk_count   integer NOT NULL DEFAULT 0,
    embed_model   varchar(100) NOT NULL,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    created_by    bigint REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS ix_kb_documents_active ON kb_documents (department_id) WHERE is_active;

CREATE TABLE IF NOT EXISTS kb_chunks (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    document_id bigint NOT NULL REFERENCES kb_documents(id) ON DELETE CASCADE,
    position    integer NOT NULL,
    content     text NOT NULL,
    embedding   real[] NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_kb_chunks_document ON kb_chunks (document_id, position);

INSERT INTO permissions (module, action, slug, description)
VALUES ('kb', 'manage', 'kb.manage', 'Upload and manage knowledge-base documents for the AI assistant')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'kb.manage'
WHERE r.slug IN ('admin', 'staff', 'hod', 'placement_officer')
ON CONFLICT DO NOTHING;
