-- The uploads feature's first migration (M6 slice 8, X13). Never edit it once a database has
-- applied it: add 0002_*.sql and list it in MIGRATIONS.
CREATE TABLE uploads_parts (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id  INTEGER NOT NULL,
  size     INTEGER NOT NULL,           -- what it said it would be
  received INTEGER NOT NULL DEFAULT 0,
  state    INTEGER NOT NULL DEFAULT 0, -- 0 open, 1 done, 2 given up
  at       INTEGER NOT NULL
);
CREATE INDEX uploads_parts_open ON uploads_parts(state, user_id, at);
CREATE TABLE uploads_blobs (
  sha256  TEXT PRIMARY KEY,            -- the content's: its file is <UPLOADS_DIR>/blobs/<sha256>
  mime    TEXT NOT NULL,
  bytes   INTEGER NOT NULL,
  width   INTEGER NOT NULL,
  height  INTEGER NOT NULL,
  user_id INTEGER NOT NULL,            -- who uploaded it first
  at      INTEGER NOT NULL
) WITHOUT ROWID;
