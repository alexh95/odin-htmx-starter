# stores/sqlite/notify

The Inbox in SQLite (PLAN §14.2, M6): `notify_items`, a member's newest 200 kept across restarts. Reads on the loop's
reader; an add goes through the writer task, which trims the member's oldest past 200 and counts the unread in the same
batch; marking read and the sweep of read items past 30 days are writes the caller waits on. A feature store.

Audited: 771e5ef 2026-11-04 docs/audit/M6.md
