# notify

The Inbox (PLAN §14.2, D36): a member's notifications from every producer, live on every page of theirs. Packages:
`notify` (the domain: what a producer may send, the newest 200 per member, read ones gone after 30 days), `models`
(the item and the store contract), `views` (the page's live log, the push, the home card), `web` (`/notify`,
`/notify/list`, `POST /notify/read`, `send`, the `notify.user` member topic, the hourly `notify.prune` job). Its stores:
memory (`app/stores/memory/notify/`, M2) and SQLite (`app/stores/sqlite/notify/`, M6, kept across restarts);
`storetest` holds both to one contract.

**Producers** import `notify_web` (the one web-to-web import, §6.2) and call `notify_web.send(user, kind, ref, html)`:
`kind` is their namespaced name (`chat.mention`), `ref` a path on this site, `html` their escaped line. notify never
names a producer's kinds.

**Live**: `notify.user:<id>` is a member row (`member = true`): the layout's `#live` carries it on every page of the
member's, and `/events` refuses it to anyone else. A push is out-of-band HTML: the item into the top of
`#notify-list`, and the count into every `.notify-count` on the page (core htmx swaps an OOB class selector into each
match, and into none when there is none). So notify's `EXTS` is hx-sse, which `#live` needs on every page of a
profile that mounts it.

It owns `/notify`, its own prefix.

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md; 771e5ef 2026-11-04 docs/audit/M6.md
