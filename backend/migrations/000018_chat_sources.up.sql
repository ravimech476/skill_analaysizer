-- Knowledge-base documents an assistant answer drew on, kept with the answer so history can show them.
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS sources jsonb;
