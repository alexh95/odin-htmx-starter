# stores/memory/bot

The bot's conversations in memory (PLAN §14.3): each member's newest 50, each with its last 200 turns, behind the
store's lock, gone with the process. A conversation is its owner's alone: every read and write names the owner, and
another member's id answers Not_Found. Past 4,096 members a new member's first conversation pushes out another
member's. Strings live on the heap from their write until their conversation or turn is pushed out; a reader gets
copies in its request arena, a writer's op in its own. A feature store.

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md; 88f9222 2026-11-05 docs/audit/M7.md
