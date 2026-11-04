-- One open report per message per member (M6-02). Never edit it once a database has applied it.
CREATE UNIQUE INDEX chat_reports_once ON chat_reports(msg, made_by) WHERE resolved = 0;
CREATE INDEX chat_reports_by ON chat_reports(made_by) WHERE resolved = 0;
CREATE INDEX chat_rooms_owner ON chat_rooms(owner) WHERE kind <> 3;
