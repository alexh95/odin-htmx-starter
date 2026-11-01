-- Rooms beyond public (M6 slice 2): a kind, an owner, a DM's pair, the members of the rooms
-- that have them (private rooms and DMs), and a private room's invites. Never edit it once a
-- database has applied it.
ALTER TABLE chat_rooms ADD COLUMN kind INTEGER NOT NULL DEFAULT 0;  -- 0 public, 1 private, 2 announcements, 3 DM
ALTER TABLE chat_rooms ADD COLUMN owner INTEGER NOT NULL DEFAULT 0; -- who made it; 0: the seeded lobby
ALTER TABLE chat_rooms ADD COLUMN dm TEXT;                          -- a DM's '<lower id>:<higher id>', else NULL
CREATE UNIQUE INDEX chat_rooms_dm ON chat_rooms(dm) WHERE dm IS NOT NULL;
CREATE TABLE chat_members (
  room INTEGER NOT NULL REFERENCES chat_rooms(id),
  who  INTEGER NOT NULL,            -- the member's id, as the identity gives it
  name TEXT NOT NULL,               -- their name when they joined (no join into accounts, D6)
  at   INTEGER NOT NULL,
  PRIMARY KEY (room, who)
) WITHOUT ROWID;
CREATE INDEX chat_members_who ON chat_members(who, room);
CREATE TABLE chat_invites (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  room     INTEGER NOT NULL REFERENCES chat_rooms(id),
  hash     TEXT NOT NULL,             -- hex SHA-256 of the token's secret: the secret itself is never kept
  made_by  INTEGER NOT NULL,          -- who made it
  by_name  TEXT NOT NULL,
  at       INTEGER NOT NULL,          -- unix seconds
  expires  INTEGER NOT NULL,
  max_uses INTEGER NOT NULL DEFAULT 0, -- 0: any number until it expires
  uses     INTEGER NOT NULL DEFAULT 0,
  revoked  INTEGER NOT NULL DEFAULT 0  -- when; 0: not revoked
);
CREATE INDEX chat_invites_room ON chat_invites(room, id);
