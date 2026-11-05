-- The wiki (M8, §6, D36). `md` is what was written and `html` what it renders to, once, so a view never
-- parses; `plain` is what search reads. A revision keeps the text a save replaced. Search is FTS5 over
-- title and plain as external content, as chat's is (D16, §11.8). Never edit it once a database has
-- applied it.
CREATE TABLE wiki_pages (
  id         INTEGER PRIMARY KEY,
  slug       TEXT NOT NULL UNIQUE,
  title      TEXT NOT NULL,
  visibility INTEGER NOT NULL,
  manual     INTEGER NOT NULL DEFAULT 0,      -- from the binary, read-only
  md         TEXT NOT NULL,
  html       TEXT NOT NULL,
  plain      TEXT NOT NULL,
  rev        INTEGER NOT NULL DEFAULT 1,
  at         INTEGER NOT NULL,
  by_name    TEXT NOT NULL
);
CREATE TABLE wiki_revisions (
  page    INTEGER NOT NULL,
  rev     INTEGER NOT NULL,
  title   TEXT NOT NULL,
  md      TEXT NOT NULL,
  at      INTEGER NOT NULL,
  by_name TEXT NOT NULL,
  PRIMARY KEY (page, rev)
) WITHOUT ROWID;
CREATE VIRTUAL TABLE wiki_fts USING fts5(
  title, plain, content = 'wiki_pages', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
);
CREATE TRIGGER wiki_fts_add AFTER INSERT ON wiki_pages BEGIN
  INSERT INTO wiki_fts(rowid, title, plain) VALUES (new.id, new.title, new.plain);
END;
CREATE TRIGGER wiki_fts_drop AFTER DELETE ON wiki_pages BEGIN
  INSERT INTO wiki_fts(wiki_fts, rowid, title, plain) VALUES ('delete', old.id, old.title, old.plain);
END;
CREATE TRIGGER wiki_fts_change AFTER UPDATE OF title, plain ON wiki_pages BEGIN
  INSERT INTO wiki_fts(wiki_fts, rowid, title, plain) VALUES ('delete', old.id, old.title, old.plain);
  INSERT INTO wiki_fts(rowid, title, plain) VALUES (new.id, new.title, new.plain);
END;
