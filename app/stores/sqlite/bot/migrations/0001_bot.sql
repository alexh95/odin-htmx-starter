-- The bot feature's first migration. Never edit it once a database has applied
-- it (the boot refuses a changed hash): add 0002_*.sql and list it in MIGRATIONS.
CREATE TABLE bot_conversations (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  owner INTEGER NOT NULL,  -- the member's id, as the identity gives it
  title TEXT NOT NULL,
  at    INTEGER NOT NULL,  -- unix seconds
  turns INTEGER NOT NULL DEFAULT 0  -- every turn it has had: older ones may be gone
);
CREATE INDEX bot_conversations_owner ON bot_conversations(owner, id);
CREATE TABLE bot_turns (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  conv     INTEGER NOT NULL REFERENCES bot_conversations(id),
  role     INTEGER NOT NULL,  -- Bot_Role
  text     TEXT NOT NULL,
  at       INTEGER NOT NULL,
  stop     INTEGER NOT NULL DEFAULT 0,  -- an answer's Bot_Done
  tokens   INTEGER NOT NULL DEFAULT 0,
  ms_first INTEGER NOT NULL DEFAULT 0,
  ms_total INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX bot_turns_conv ON bot_turns(conv, id);
