-- What a member muted (M6 slice 7): a kind ("chat.mention") or a scope a producer names
-- ("chat.room:12"). Here and not in accounts_prefs: `send` asks for any member, and notify runs on
-- builds with no accounts. Never edit it once a database has applied it.
CREATE TABLE notify_mutes (
  user_id INTEGER NOT NULL,
  key     TEXT NOT NULL,
  PRIMARY KEY (user_id, key)
) WITHOUT ROWID;
