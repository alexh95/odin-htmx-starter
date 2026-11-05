-- A prefix index (M8, docs/perf/FIND-BUDGETS.md): a search's last word is also a prefix, and with no index for
-- it FTS5 merges every matching term's list, 33 ms at 100k messages against 0.08 ms with one. The triggers
-- name the table and stay as they are. Never edit it once a database has applied it.
DROP TABLE chat_fts;
CREATE VIRTUAL TABLE chat_fts USING fts5(
  body, content = 'chat_messages', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
);
INSERT INTO chat_fts(chat_fts) VALUES ('rebuild');
