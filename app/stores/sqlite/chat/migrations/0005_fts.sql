-- Search (M6 slice 6, D16, §11.8): FTS5 over message bodies as external content, kept in sync by
-- triggers, so an edit, a tombstone and retention's deletes all reach it. Never edit it once a
-- database has applied it.
CREATE VIRTUAL TABLE chat_fts USING fts5(
  body, content = 'chat_messages', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2'
);
CREATE TRIGGER chat_fts_add AFTER INSERT ON chat_messages BEGIN
  INSERT INTO chat_fts(rowid, body) VALUES (new.id, new.body);
END;
CREATE TRIGGER chat_fts_drop AFTER DELETE ON chat_messages BEGIN
  INSERT INTO chat_fts(chat_fts, rowid, body) VALUES ('delete', old.id, old.body);
END;
CREATE TRIGGER chat_fts_change AFTER UPDATE OF body ON chat_messages BEGIN
  INSERT INTO chat_fts(chat_fts, rowid, body) VALUES ('delete', old.id, old.body);
  INSERT INTO chat_fts(rowid, body) VALUES (new.id, new.body);
END;
INSERT INTO chat_fts(chat_fts) VALUES ('rebuild');
