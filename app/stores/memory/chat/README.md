# stores/memory/chat

Chat in memory (PLAN §14.1, D16): rooms, and a ring of each room's last 100 messages under one byte budget for all of
them (`CHAT_RING_BYTES`, 16 MiB), which takes the oldest rooms' tails first. The ring is the history: a restart
empties it (the room page says "ephemeral"), and the lobby is seeded again. Message ids and room versions count from
the boot time × 10⁶, the `<epoch>-<seq>` of §14.1 as one number, so a page from before a restart keeps its messages
and never sees a new one take an old one's id; `PERSISTED` is false, so the room's topic resyncs rather than replays
by id. A message's strings live on the heap from its post until the ring or the budget lets it go; a reader gets
copies in its request arena, a writer's op in its own. A feature store.

Audited: c490e2a 2026-10-30 docs/audit/M3.md; 771e5ef 2026-11-04 docs/audit/M6.md
