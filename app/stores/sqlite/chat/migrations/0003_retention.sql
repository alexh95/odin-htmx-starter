-- Retention (M6 slice 3): a pinned message is exempt from a room's caps and ages, and the age
-- sweep reads a room's messages oldest first. Never edit it once a database has applied it.
ALTER TABLE chat_messages ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;
CREATE INDEX chat_messages_kept ON chat_messages(room, pinned, id);
