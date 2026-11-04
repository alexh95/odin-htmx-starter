-- An owner's Remove (M6): a chat_bans row of kind 2 keeps a member out of a private room, whatever
-- invite they hold, until the owner lifts it; `name` is for the owner's list.
ALTER TABLE chat_bans ADD COLUMN name TEXT NOT NULL DEFAULT '';
