-- Phase 8: file uploads (photos, resumes, certificates, offer letters, logos, job descriptions,
-- notification attachments) and student documents.

-- Every stored file. Bytes live in the file store (local disk for now) under storage_key.
-- A file is uploaded first (ref_type NULL) and then attached to exactly one record.
CREATE TABLE files (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid          UUID         NOT NULL DEFAULT gen_random_uuid(),
    category      VARCHAR(30)  NOT NULL CHECK (category IN ('profile_photo', 'resume', 'certificate', 'offer_letter',
                                  'student_document', 'company_logo', 'job_description', 'notification_attachment')),
    original_name VARCHAR(255) NOT NULL,
    content_type  VARCHAR(100) NOT NULL,
    size_bytes    BIGINT       NOT NULL CHECK (size_bytes > 0),
    sha256        CHAR(64)     NOT NULL,
    storage_key   TEXT         NOT NULL,
    ref_type      VARCHAR(40),          -- what it is attached to (users, student_documents, …); NULL = not attached yet
    ref_id        BIGINT,
    is_active     BOOLEAN      NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by    BIGINT       REFERENCES users(id),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by    BIGINT       REFERENCES users(id)
);
CREATE UNIQUE INDEX ux_files_uuid ON files (uuid);
CREATE INDEX ix_files_unattached ON files (created_at) WHERE ref_type IS NULL AND is_active;
CREATE INDEX ix_files_inactive ON files (updated_at) WHERE NOT is_active;
CREATE TRIGGER trg_files_updated_at BEFORE UPDATE ON files FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- File pointers on existing records (the old *_url text columns stay for external links).
ALTER TABLE users               ADD COLUMN photo_file_id        BIGINT REFERENCES files(id);
ALTER TABLE student_profiles    ADD COLUMN resume_file_id       BIGINT REFERENCES files(id);
ALTER TABLE student_skills      ADD COLUMN certificate_file_id  BIGINT REFERENCES files(id);
ALTER TABLE placement_records   ADD COLUMN offer_letter_file_id BIGINT REFERENCES files(id);
ALTER TABLE companies           ADD COLUMN logo_file_id         BIGINT REFERENCES files(id);
ALTER TABLE company_job_roles   ADD COLUMN jd_file_id           BIGINT REFERENCES files(id);
ALTER TABLE notifications       ADD COLUMN attachment_file_id   BIGINT REFERENCES files(id);

-- Documents a student keeps on file (ID proof, earlier mark sheets, certificates…), verified by staff.
CREATE TABLE student_documents (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id   BIGINT       NOT NULL REFERENCES users(id),
    doc_type     VARCHAR(30)  NOT NULL CHECK (doc_type IN ('id_proof', 'photo_id', 'marksheet_10', 'marksheet_12',
                                 'diploma', 'transfer_certificate', 'community_certificate', 'income_certificate',
                                 'course_certificate', 'internship_certificate', 'other')),
    title        VARCHAR(150) NOT NULL,
    file_id      BIGINT       NOT NULL REFERENCES files(id),
    status       VARCHAR(20)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'rejected')),
    remarks      TEXT,
    verified_by  BIGINT       REFERENCES users(id),
    verified_at  TIMESTAMPTZ,
    is_active    BOOLEAN      NOT NULL DEFAULT true,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_by   BIGINT       REFERENCES users(id),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by   BIGINT       REFERENCES users(id)
);
CREATE INDEX ix_student_documents_student ON student_documents (student_id) WHERE is_active;
CREATE INDEX ix_student_documents_pending ON student_documents (created_at) WHERE is_active AND status = 'pending';
CREATE TRIGGER trg_student_documents_updated_at BEFORE UPDATE ON student_documents FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- file_json(id): the JSON the API needs to render a file link ({uuid,name,type,size}); NULL when absent.
CREATE FUNCTION file_json(fid BIGINT) RETURNS JSON LANGUAGE sql STABLE AS $$
    SELECT json_build_object('uuid', f.uuid, 'name', f.original_name, 'type', f.content_type, 'size', f.size_bytes)
    FROM files f WHERE f.id = fid AND f.is_active
$$;

INSERT INTO permissions (module, action, slug, description) VALUES
    ('document', 'view',   'document.view',   'View student documents'),
    ('document', 'create', 'document.create', 'Upload student documents'),
    ('document', 'verify', 'document.verify', 'Verify or reject student documents'),
    ('document', 'delete', 'document.delete', 'Delete student documents');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.module = 'document'
WHERE (r.slug IN ('admin', 'hod', 'staff'))
   OR (r.slug = 'placement_officer' AND p.action = 'view')
   OR (r.slug = 'student' AND p.action IN ('view', 'create', 'delete'))
   OR (r.slug = 'parent' AND p.action = 'view')
ON CONFLICT DO NOTHING;
