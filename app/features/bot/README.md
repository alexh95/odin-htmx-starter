# bot

The house assistant (PLAN §14.3, D31; Q20, Q32), on its mock at M2. Packages: `bot` (the domain: questions of at most
4,000 runes, titles, what a backend is asked, the answer's markdown render), `models` (D31's backend contract:
`Bot_Request`, `Bot_Event`, `Bot_Done` with llama's stats shape, `Bot_Health`, `Bot_Sink`; conversations, turns and the
store contract), `backend_mock` (the default), `backend_llama` (a llama.cpp server on the LAN), `views` and `web` (the
routes, the backend switch, both deliveries, Stop and the limits). Its stores: memory (`app/stores/memory/bot/`, `streams`) and
SQLite (`app/stores/sqlite/bot/`, Houston, from M7), held to one contract by `storetest`.

**An answer** is a stream on the asker's own connection, in four frames: the question and the answer's shell with Stop;
the answer's text into `#mb-<mid>` a piece at a time (an SSE answer adds `event: hx:release` after the first, so the
form is back while it streams); the answer rendered as markdown with its stats, in place of the shell (`outerMorph`);
the end. The form chooses the delivery: an SSE answer to its POST, or a multipart one, which also sends `#usage` and,
for a conversation's first question, `#conv-title`. `x-impl: bot.backend=<name>` says which backend answered.

**The mock** runs a timer chain on the stream's loop: canned "under construction" and "TODO" lines, word by word,
30–120 ms apart (`BOT_DELAY_MS` fixes it, 0 as fast as the loop goes), coalesced to at most 20 events a second, and the
same answer for the same question when `BOT_SEED` is set. `cancel`, from Stop on any loop or a browser that went away,
is posted to the generation's loop, which removes its timer and sends `Bot_Done{.Stopped}`.

**The llama binding** posts to `BOT_LLAMA_URL`'s `/v1/chat/completions` on `platform/stream/client`, on the loop of the
stream that asked, so it needs no pool. The server takes its slots' worth at once, counted across every loop; past that a
generation queues, first come first served, and the page says "Queued (#n)". Connect 2 s, first token 30 s, idle 15 s,
each answered in words; what was said before a fault stands, marked "Cut off". Stop closes the socket, which is what stops
llama.cpp. `tools/fakellama` is what it's tested against: no model ships.

**Which backend** is chosen per request among the healthy: a guest always gets the mock, a member the default
(`BOT_BACKEND`, or what an admin set on `/admin/bot`, which a restart forgets) or, while both can answer, what the form
picks; a llama that can't answer gives way to the mock. A thread reads `/health` and `/props` every `BOT_LLAMA_PROBE`,
and a change publishes the badge on `bot.health` and the status line on `obs`, degraded at worst.

**In a chat room**, `@bot` is the same answer told to the room (`web/room.odin`): chat publishes on `bot.ask:<room>`, whose
`deliver` row here starts the backend under the asker's limits, a bubble grows on `chat.typing:<room>` for everyone in
the room, and the finished text goes back on `chat.reply:<room>`, which chat stores, the same text as the bubble's last. The
model is given the question alone, so a private room's talk leaves it only when someone asks, and is asked to be brief, at
`ROOM_TOKENS`; an answer that still reaches a message's 2,000 runes stops the model there. A failed ask stores nothing and
tells its asker alone. Neither feature imports the other.

**Who may ask** (Q20, §17.5): members keep their conversations (the newest 50, each with its last 200 turns), ask one
at a time and `BOT_MEMBER_PER_HOUR` (30) an hour; guests get the mock, `BOT_GUEST_PER_HOUR` (5) an hour per client,
and nothing is kept. A conversation is its owner's alone: anyone else's id answers 404.

It owns `/bot` and `/admin/bot`, its own prefixes. `/admin/bot` is `ADMIN_ROUTES`, mounted where there is an admin.

Audited: c490e2a 2026-10-30 docs/audit/M3.md; 88f9222 2026-11-05 docs/audit/M7.md
