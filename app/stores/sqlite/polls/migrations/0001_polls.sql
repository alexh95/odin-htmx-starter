-- Go/No-go (M8, §15.1, D36, Q36). `poll_tally` is what every poll's bars read, and `poll_voters` who has voted.
-- An anonymous poll stores nothing else about a vote, and within one copy of the file neither table can line up with the
-- other: the tally holds counters, no rows per vote; the voters have no rowid and no time, so no query gets an order but
-- their ids'. Two copies can: what changed between them is a voter and a counter (M8-01). A vote leaves the option in
-- `poll_votes` only on a named poll. Never edit it once a database has applied it.
CREATE TABLE polls (
  id        INTEGER PRIMARY KEY,
  question  TEXT NOT NULL,
  multiple  INTEGER NOT NULL,
  anonymous INTEGER NOT NULL,
  closes_at INTEGER NOT NULL,
  closed_at INTEGER NOT NULL DEFAULT 0,
  by_id     INTEGER NOT NULL,
  by_name   TEXT NOT NULL,
  at        INTEGER NOT NULL
);
CREATE INDEX polls_due ON polls(closes_at) WHERE closed_at = 0;
-- Set at creation for good: a named poll turned anonymous would still hold its rows.
CREATE TRIGGER polls_anonymous_stays BEFORE UPDATE OF anonymous ON polls WHEN new.anonymous <> old.anonymous BEGIN
  SELECT RAISE(ABORT, 'a poll stays as it was made');
END;
CREATE TABLE poll_options (
  id    INTEGER PRIMARY KEY,
  poll  INTEGER NOT NULL,
  label TEXT NOT NULL,
  pos   INTEGER NOT NULL
);
CREATE INDEX poll_options_poll ON poll_options(poll, pos);
CREATE TABLE poll_tally (
  poll   INTEGER NOT NULL,
  option INTEGER NOT NULL,
  n      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (poll, option)
) WITHOUT ROWID;
CREATE TABLE poll_voters (
  poll INTEGER NOT NULL,
  who  INTEGER NOT NULL,
  PRIMARY KEY (poll, who)
) WITHOUT ROWID;
CREATE TABLE poll_votes (
  poll   INTEGER NOT NULL,
  who    INTEGER NOT NULL,
  option INTEGER NOT NULL,
  name   TEXT NOT NULL,
  PRIMARY KEY (poll, who, option)
) WITHOUT ROWID;
