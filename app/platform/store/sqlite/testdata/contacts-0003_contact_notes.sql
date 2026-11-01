-- The /forms page posts a notes field and an email-updates switch; keep them
-- rather than dropping them. notes is the optional text column empty strings are
-- stored in (as '', never NULL: see bind_text in db.odin).
ALTER TABLE contacts ADD COLUMN notes  TEXT    NOT NULL DEFAULT '';
ALTER TABLE contacts ADD COLUMN notify INTEGER NOT NULL DEFAULT 0;  -- 0 / 1
