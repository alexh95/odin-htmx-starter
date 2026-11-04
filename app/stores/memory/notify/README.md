# stores/memory/notify

Notifications in memory: a ring of the newest 200 per member behind the store's lock, gone with the process. An
item's strings are copied to the heap when added and freed when its ring pushes it out or the hourly sweep takes a
read one past 30 days; a reader gets copies in its request arena. A feature store.

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md; 771e5ef 2026-11-04 docs/audit/M6.md
