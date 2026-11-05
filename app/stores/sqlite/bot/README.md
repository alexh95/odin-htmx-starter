# stores/sqlite/bot

The bot's conversations in SQLite (PLAN §14.3, M7): a member's newest 50, each with its last 200 turns, kept across
restarts, as the memory store keeps them for as long as the process runs. Every read and write names the owner, and
another member's id answers `.Not_Found` (Q20). Reads on the loop's reader; a new conversation or a turn goes through the
writer task, which trims in the same batch. A feature store.

Audited: 88f9222 2026-11-05 docs/audit/M7.md
