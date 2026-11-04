-- Moderation (M6 slice 4): a room's lock and slow mode, a member's mute or kick in a room, and
-- reports, each carrying a copy of the message it is about (a moderator doesn't read a private
-- room or a DM, so the copy is what they see). Never edit it once a database has applied it.
ALTER TABLE chat_rooms ADD COLUMN locked INTEGER NOT NULL DEFAULT 0; -- only moderators post
ALTER TABLE chat_rooms ADD COLUMN slow INTEGER NOT NULL DEFAULT 0;   -- seconds between a member's posts; 0: off
CREATE TABLE chat_bans (
  room   INTEGER NOT NULL REFERENCES chat_rooms(id),
  who    INTEGER NOT NULL,
  kind   INTEGER NOT NULL,           -- 0 a mute (no posting), 1 a kick (not in the room at all)
  until  INTEGER NOT NULL,           -- unix seconds
  made_by INTEGER NOT NULL,
  PRIMARY KEY (room, who, kind)
) WITHOUT ROWID;
CREATE TABLE chat_reports (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  room        INTEGER NOT NULL,
  msg         INTEGER NOT NULL,
  author      INTEGER NOT NULL,
  author_name TEXT NOT NULL,
  body        TEXT NOT NULL,         -- the message as it was reported: the moderator's copy
  made_by     INTEGER NOT NULL,
  by_name     TEXT NOT NULL,
  reason      TEXT NOT NULL,
  at          INTEGER NOT NULL,
  resolved    INTEGER NOT NULL DEFAULT 0, -- when; 0: open
  outcome     TEXT NOT NULL DEFAULT ''    -- 'removed' or 'dismissed'
);
CREATE INDEX chat_reports_open ON chat_reports(resolved, id);
