CREATE TABLE IF NOT EXISTS contacts (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  name   TEXT    NOT NULL,
  email  TEXT    NOT NULL,
  role   INTEGER NOT NULL,   -- mirrors models.Role  (stores int(role))
  status INTEGER NOT NULL,   -- mirrors models.Status
  score  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON contacts(status);
