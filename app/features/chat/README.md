# chat

Rooms on the LAN (PLAN §14.1, D30), live over four transports. Packages: `chat` (the domain: bodies of at most 2,000
runes, the 10-minute edit window, room names and slugs, and what lives only in the process whatever the store:
presence, read cursors, the names mentions match), `models` (rooms, messages, the post and change ops, the store
contract), `views` (the rooms, a room, a message, its menu and edit form, presence, typing, unread counts),
`transport_ws`, `transport_sse`, `transport_poll`, `transport_multipart` (each a room's wiring, its endpoint and its
extensions) and `web` (the routes, the topics, the switch, one post path for forms and sockets). Its store at M2:
memory (`app/stores/memory/chat/`); at M6 SQLite (`app/stores/sqlite/chat/`), rooms of every kind, then
moderation, uploads and search.

**One fragment for every transport.** A message is rendered once, `<article id="m-<id>">`, and travels as
`<hx-partial hx-target="#log-<room>" hx-swap="upsert sort">`: upsert replaces what the log already has (an edit, a
tombstone, a reconnect's snapshot, the author's own reply and the hub's copy of it) and sorts a new one in by id, so
nothing doubles. The menu's slot, `#mm-<id>`, is `hx-preserve` (but on a tombstone), so a message rendered again
keeps the menu or the half-typed edit open in it; a saved edit closes its form with its answer's empty main swap
(`swapEmpty`). What differs per viewer is asked for (the menu, `GET /chat/m/<id>/menu`) or marked on the client
(`AutoScroll` sets `.mine` where `data-author` is the log's `data-me`).

**The page's version.** Every fragment also sets `#ver-<room>`, a hidden field holding the newest room version the page
has seen. A reconnect sends it back (a socket's first frame, from the field's form on hx-ws's `after:connection`; SSE's
resync, by `hx-include`), and the answer is what changed since it, or, when the room has let go of something that
changed after it, the last 50 swapped in with `innerHTML`, so the log never runs on across a gap (M2-31, M2-35). After a
restart the version is reached (the new process's versions start above it, and its rooms have let nothing go), so the
page keeps what it had (D37).

| Transport | The pane | The composer | A reconnect |
|---|---|---|---|
| `ws` (default) | `hx-ws:connect` `/chat/r/<slug>/ws` | `hx-ws:send` (JSON `{body}`) | the page sends `{ver}`: what changed since |
| `sse` | the room's topic on the layout's `#live` | `hx-post`, `hx-pending` | the hub's ring, else `resync` → `/since?ver=` |
| `poll` | `hx-get` `/chat/r/<slug>/since` every 2 s, `hx-ptag` | `hx-post`, `hx-pending` | the tag: what changed since it |
| `multipart` | `hx-multipart:connect` `/chat/r/<slug>/parts` | `hx-post`, `hx-pending` | what came after `HX-Last-Part-ID` |

The choice is per request: `?transport=`, the member's Connection setting (the `chat_transport` cookie, from
`POST /chat/transport`), else `CHAT_TRANSPORT`; the response says which in `x-impl: chat.transport=<t>`.

**Every page of a room** also carries `chat.presence:<id>` and `chat.typing:<id>` on its `#live`: presence learns who is
there from those streams opening and closing (the hub's `watch` hook: online at once, away 10 s after the last closed,
gone after 5 minutes, published by the `chat.presence` job), and typing is `POST /chat/r/<slug>/typing` from the
composer (`throttle:2s`), upserted and faded by CSS (`Expire` removes it on the hyperscript client). The newest message
a page renders or receives posts a read receipt when it scrolls into view (`hx-trigger="intersect once"`, never a GET);
a new message moves every other reader's unread count on `.unread-<slug>`, through their `notify.user` topic, and a
mention (`@name`, the name a member last used here) lands in their Inbox through `notify_web.send`.

**Rooms of four kinds** (D30, M6). A public room and announcements are every member's to read; announcements are
posted by their owner and the moderators only (the rest see no composer, and a post is 403), and only a moderator
makes one. A private room and a DM are their members' alone: to anyone else every route of theirs, their topics and
their messages' menus answer as a room that doesn't exist (404), and the rooms list leaves them out; a mention there
reaches only members, and moderators read neither (moderation works from reports, slice 4). A private room's owner
(or a moderator among its members) hands out invite links (`POST /chat/r/<slug>/invite`, `once=1` for a single
use), lists the open ones on the room's page and revokes them (`POST /chat/r/<slug>/invites/<id>/revoke`). An invite
is a row (`chat_invites`): its link is `/chat/join/<id>.<secret>`, the store keeps the secret's SHA-256 only and the
domain compares it in constant time, and it lasts 7 days, through restarts, unless revoked or spent; a forged,
revoked, expired or spent one answers 404 alike. The link's page joins by a plain form and sends no Referer on, and
the access log names the route's pattern only, so the token stays in the link. A member leaves with
`POST /chat/r/<slug>/leave`; a DM isn't left (blocking is slice 4's). A DM
starts from a message's menu, "Message <name>" (`POST /chat/dm/<id>`, `Chat_Dm`): the two members' room with an
opaque slug (`dm-` and 16 hex digits), found again from either side, never made twice. The domain holds the rule
once (`room_for`, `may_read`, `may_post`, `reads`), and every handler, transport and topic asks it.

**Limits** (§17.5): posts 5 per 10 s per member (`web.Limit`, a 429 with `Retry-After` into the toasts; a socket gets
the toast down the socket), typing 1 per 2 s (the rest dropped), socket frames 20 a second (then 1008), bodies 2,000
runes, 100 rooms in a memory build (1,000 on SQLite), 64 members a private room in a memory build, at most 4,096
members' names per process, and 256 read cursors a room.

It owns `/chat`, its own prefix.

Audited: c490e2a 2026-10-30 docs/audit/M3.md
