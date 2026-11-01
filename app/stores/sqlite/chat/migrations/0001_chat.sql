-- The chat feature's first migration. Never edit it once a database has applied
-- it (the boot refuses a changed hash): add 0002_*.sql and list it in MIGRATIONS.
CREATE TABLE chat_rooms (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  slug        TEXT NOT NULL UNIQUE,   -- [a-z0-9-], 1 to 40: /chat/r/<slug> (X12)
  name        TEXT NOT NULL,
  at          INTEGER NOT NULL,       -- unix seconds
  ver         INTEGER NOT NULL DEFAULT 0,  -- bumped by every change in the room: the poll's tag
  dropped     INTEGER NOT NULL DEFAULT 0,  -- the newest message id retention let go
  dropped_ver INTEGER NOT NULL DEFAULT 0   -- and the newest version among those
);
CREATE TABLE chat_messages (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  room   INTEGER NOT NULL REFERENCES chat_rooms(id),
  author INTEGER NOT NULL,            -- the member's id, as the identity gives it
  name   TEXT NOT NULL,               -- their name when they posted (no join into accounts, D6)
  body   TEXT NOT NULL,               -- '' once deleted: a tombstone keeps its row and id
  at     INTEGER NOT NULL,
  edited INTEGER NOT NULL DEFAULT 0,
  gone   INTEGER NOT NULL DEFAULT 0,
  ver    INTEGER NOT NULL
);
CREATE INDEX chat_messages_room ON chat_messages(room, id);
CREATE INDEX chat_messages_ver ON chat_messages(room, ver);
