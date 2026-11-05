# platform/hub

Server events to every subscriber on every event loop (PLAN §9, D13). `hub.publish(topic, html, rowid, key)` from any
thread takes the hub sequence under a `guard.Mutex`, puts the message in the topic's ring and wakes each loop that has
subscribers at most once per burst; the loop's drain encodes once per transport and writes to its subscribers. Rings
follow the topic row's policy (`.Queue`, `.Latest` per publish key, `.Sample`). `/events` (`hub.ROUTES`) is the page's
one SSE stream: each topic's perm and `allow`, then D13's resume (`Last-Event-ID`, then `after`, then the row's keyset
replay, else `event: resync`). `hub.kick` ends a topic's streams (SSE `kicked`, a socket's close code). A profile that
streams calls `hub.init()` and `hub.mount("<host>", ..TOPICS[:])` in `main` and mounts `hub.ROUTES` on that host; one
that doesn't links none of it. Layer L3 (PLAN §5.1).

Audited: d136601 2026-10-30 docs/audit/M4.md (its M4 diff); c490e2a 2026-10-30 docs/audit/M3.md; 771e5ef 2026-11-04 docs/audit/M6.md; 88f9222 2026-11-05 docs/audit/M7.md
