-- AI chat assistant: saved conversation history and the permission that gates it.

CREATE TABLE IF NOT EXISTS chat_messages (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint NOT NULL REFERENCES users(id),
    -- the student the answer was about (the user themselves, a child, or a student a staff member asked about)
    student_id bigint REFERENCES users(id),
    role       varchar(10) NOT NULL CHECK (role IN ('user', 'assistant')),
    content    text NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_chat_messages_user ON chat_messages (user_id, id DESC) WHERE is_active;

INSERT INTO permissions (module, action, slug, description)
VALUES ('chat', 'use', 'chat.use', 'Use the AI chat assistant')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.slug = 'chat.use'
WHERE r.slug IN ('admin', 'staff', 'hod', 'placement_officer', 'student', 'parent')
ON CONFLICT DO NOTHING;
