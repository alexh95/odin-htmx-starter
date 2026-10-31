-- The notify feature's first migration. Never edit it once a database has applied
-- it (the boot refuses a changed hash): add 0002_*.sql and list it in MIGRATIONS.
CREATE TABLE notify_items (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,  -- the member's id, as the identity gives it
  kind    TEXT NOT NULL,     -- the producer's namespaced name: "chat.mention"
  ref     TEXT NOT NULL,
  html    TEXT NOT NULL,     -- the producer's line, escaped by it
  at      INTEGER NOT NULL,  -- unix seconds
  read    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX notify_items_user ON notify_items(user_id, id);
