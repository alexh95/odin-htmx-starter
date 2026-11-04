# stores/sqlite/chat

Chat in SQLite (PLAN §14.1, D30; M6): `chat_rooms` and `chat_messages`, kept across restarts, ids the rowids, so a
page resumes a room from `@<rowid>` after a restart (`PERSISTED`). Reads on the loop's reader; a post or a change goes
through the writer task, which bumps the room's version and reads the row back in its batch; a room is made at once.
Retention (M6 slice 3) moves `dropped` and `dropped_ver`. A feature store.

Audited: 771e5ef 2026-11-04 docs/audit/M6.md
