-- Checklists (M8, §6, D36). An item has a column; one column of a list closes, and done means being in
-- it, so there's no second truth to fall out of step. Positions keep gaps of 1024 within a column.
-- `list_people` is who has worked on a list: who an item can be given to. Search is FTS5 over item text,
-- as chat's is. Never edit it once a database has applied it.
CREATE TABLE lists (
  id      INTEGER PRIMARY KEY,
  title   TEXT NOT NULL,
  by_name TEXT NOT NULL,
  at      INTEGER NOT NULL
);
CREATE TABLE list_columns (
  id     INTEGER PRIMARY KEY,
  list   INTEGER NOT NULL,
  name   TEXT NOT NULL,
  pos    INTEGER NOT NULL,
  closes INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX list_columns_list ON list_columns(list, pos);
CREATE TABLE list_items (
  id       INTEGER PRIMARY KEY,
  list     INTEGER NOT NULL,
  col      INTEGER NOT NULL,
  body     TEXT NOT NULL,
  assignee INTEGER NOT NULL DEFAULT 0,
  pos      INTEGER NOT NULL
);
CREATE INDEX list_items_col ON list_items(col, pos);
CREATE INDEX list_items_list ON list_items(list);
CREATE TABLE list_people (
  list INTEGER NOT NULL,
  who  INTEGER NOT NULL,
  name TEXT NOT NULL,
  PRIMARY KEY (list, who)
) WITHOUT ROWID;
CREATE VIRTUAL TABLE lists_fts USING fts5(
  body, content = 'list_items', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
);
CREATE TRIGGER lists_fts_add AFTER INSERT ON list_items BEGIN
  INSERT INTO lists_fts(rowid, body) VALUES (new.id, new.body);
END;
CREATE TRIGGER lists_fts_drop AFTER DELETE ON list_items BEGIN
  INSERT INTO lists_fts(lists_fts, rowid, body) VALUES ('delete', old.id, old.body);
END;
