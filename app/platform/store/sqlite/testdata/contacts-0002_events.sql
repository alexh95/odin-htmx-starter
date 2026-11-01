CREATE TABLE IF NOT EXISTS events (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id  INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  target_id INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  kind      INTEGER NOT NULL,   -- mirrors models.Event_Kind
  at        INTEGER NOT NULL,   -- unix seconds
  note      TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_events_actor  ON events(actor_id);
CREATE INDEX IF NOT EXISTS idx_events_target ON events(target_id);
