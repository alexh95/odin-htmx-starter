-- What a message's image needs to be found by (the holder check, a moderator's removal), a report's
-- own copy of it, and who a member blocked (M6). A DM can't be left, so a block is how one ends.
CREATE INDEX chat_messages_blob ON chat_messages(blob) WHERE blob <> '';
ALTER TABLE chat_reports ADD COLUMN blob TEXT NOT NULL DEFAULT '';
CREATE INDEX chat_reports_blob ON chat_reports(blob) WHERE blob <> '' AND resolved = 0;
CREATE TABLE chat_blocks (
  who   INTEGER NOT NULL,
  other INTEGER NOT NULL,
  name  TEXT NOT NULL,                 -- the other member's, as it was: for the list
  at    INTEGER NOT NULL,
  PRIMARY KEY (who, other)
) WITHOUT ROWID;
