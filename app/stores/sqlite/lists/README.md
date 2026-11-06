# stores/sqlite/lists

Lists, their columns and items, the people who've worked on each, and FTS5 over item text. SQLite only: there's no memory member, so a
memory build that reaches `lists` fails to compile. A change runs on the query pool under `write_now` and answers which columns changed.
Positions keep gaps of 1024 and a column renumbers itself when one runs out. A feature store.

Audited: 4f81819 2026-11-05 docs/audit/M8.md
