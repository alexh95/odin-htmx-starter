# TODO

Source of truth for outstanding work. Check items off as you finish them; add follow-ups you
discover. See `CLAUDE.md` for the standing policy. Keep this and `CHANGELOG.md` current.

## The project, in one line

This is a **starter skeleton** for a simple, server-rendered website on Odin + HTMX + SQLite —
clone it, rename it, strip the demo, build your thing. The bundled app (contacts/events admin
console + the theme library + the test/deploy harness) is the **worked example** that proves the
patterns, *not* the product. So "done" means *a great starting point*, not *a finished app*:
copy-and-start ergonomics and good defaults matter more than feature depth.

> Reframe: earlier docs ([`docs/USE_CASES.md`](docs/USE_CASES.md)) framed this as evolving into a
> "flagship admin console." That app is now explicitly the **example**, not the goal. Product-depth
> items (**bulk actions**, a **named console identity**) are **out of scope as goals** — they'd just
> be cruft a copier deletes — and survive only as "example extensions you might add."

## M6's audit: what stays open (docs/audit/M6.md)

- [ ] **Rooms can't be deleted** (M6-07), and nobody can remove a member from a private room (M6-16): with the room
      settings page (3a).
- [ ] **A post in flight isn't a holder** (M6-10): a delete or the sweep in the same milliseconds costs that message its
      image; a purge racing a post can leave a message naming a blob that a later upload brings back.
- [ ] **A session's expiry doesn't reach an open stream** (M6-12): revokes do. Give a stream its session's end.
- [ ] **Search on the query pool** (M6-13), when `find` comes (M8).
- [ ] **Small things** (M6-16): a private room's slug can be probed by name, a moderator can mute an admin, a renamed
      member's socket keeps the old name, `report_remove` closes before it removes.

## Known flakes (seen once, passed on a rerun: not fixed)

- `contacts/crud.spec:4` on Firefox (skeleton): "Invited" stayed where "Disabled" was due, both attempts of one run on
  69df7b9. Watch it.

- [x] **dbview's drill, Linux** (run 41251995318, job "Drills (full, Linux)", on `eea5cae`): a query running to its
      2 s budget left the writes' slowest at 63 ms (alone: 1.1 ms), against the drill's bar; it passed on the rerun.
      Found: the bar (the slowest ≤ max(50 ms, 3× alone)) caught one write on a four-core runner whose core the
      query was burning. What the drill holds is that dbview never takes the writer's lock, which would hold a write
      the query's whole 2 s: the floor is 250 ms now, far below that.
- [x] **contacts' search highlighting** (run 41251995318, jobs "E2E (full, firefox)" and "E2E (full-vanilla,
      chromium)", on `eea5cae`): "a query that shrinks when lowered marks the original span" found no match for
      `Turİng`; it passed on the rerun. Found: it searched the seed's Turing, which can be the first row, and
      crud.spec renames and deletes the first row on the same worker's server. The case adds its own row now.

## M6 — Comms, and the family beta (v2.5.0)

The starter's sixth milestone ([`docs/PLAN.md`](docs/PLAN.md) §22.3, M6's row; §14.1 chat, §14.2 notify and uploads;
§17.5 limits, §17.6 uploads' caps and headers; Q19 retention, Q23 the beta). Its exit gate: the slice gate; four
transports × resume specs, including across a restart; the retention spec (`CHAT_ROOM_CAP=5`, send 7 → 5 + the
marker); the WS chat budget at 1000 sockets; the writer task ≥ 3× autocommit at 1000 msgs/s; the XSS/UGC suite; an
upload decode-bomb fuzz; D22's core flows on the oldest-browser device with no client behaviours; and a focused
security audit of accounts, sessions, chat and uploads with 0 CRITICAL/HIGH **before the first invite**. Chat is
M2's (`streams`, the memory store, all four transports); M6 puts it in `full` on SQLite. Pushes are on the standing
go; Alex's step is the last: the 2–3 invites (Q23), only after the audit.

- [x] **1. Spike: htmx 4's `htmx:ws:error` detail** (§14.1's "Auto", UNVERIFIED (M6)): what the event carries on a
      refused and a dropped socket in chromium, webkit and firefox, so Auto can fall back to SSE after two failed
      connects. *Check:* a decision record in `docs/spikes/`, with the measured details.
      Done: `docs/spikes/M6.1.md`: the error's detail is a bare Event (no browser gives a reason), and chromium sends
      none for a socket that was open; Auto counts `htmx:ws:close` events with no connection between them.
      `e2e/tests/lab/ws-errors.spec.ts` keeps it measured (firefox in CI).
- [x] **2. Chat on SQLite** (§14.1, D30): `stores/sqlite/chat` with rooms (public, private, announcements; a DM as a
      two-member room with an opaque slug), members and messages (rowids), through M2's writer task; publish after
      commit with the rowid; `@rowid` keyset replay. `full` mounts chat on its main host, perms `Chat_*` (D35).
      *Check:* chat's storetest over both families; the chat specs on `full`.
      Progress (2026-11-01): the SQLite store (rooms, messages, versions, edits and tombstones; rowids, so
      `PERSISTED`) and `chat/storetest` over both families; `full` mounts chat and notify on its main host, and the
      chat and notify specs and scenarios run there (an account per member); the ring's and the memory restart's
      cases are `@chat-memory`. Rooms beyond public (2026-11-01): private rooms (invite links, leaving),
      announcements (a moderator's to make, their owner's to post) and DMs (from a message's menu), with members in
      both stores; `rooms.spec` (chromium and webkit on streams and full, locally) and `rooms.js`. Left: SQLite's own
      restart spec is slice 9's, its retention slice 3's; moderation (mute, kick, lock, slow mode) slice 4's.
      **Was open (2026-11-01): the mount in `full` failed in CI only, and was reverted (`51505e3`, of `d697760`).** Runs
      41257098422 (`7efa854`) and 41257794341 (`3738749`), jobs "E2E (full, chromium)" and "E2E (full, firefox)":
      in Firefox the members' pages log "NetworkError when attempting to fetch resource" (`chat.spec`'s "reaches the
      other member once" over ws and sse, "an open edit form outlives…" over every transport; `notify.spec`'s
      mention), and in chromium the rate case's `waitForResponse` never sees its POST. They pass on Windows and on
      Linux with CI's four workers, the whole suite included. Find the cause (what fetch fails, on what), then mount
      again; the specs' and scenarios' accounts members (`member()`, `lib/member.js`) are in `d697760`.
      Found (2026-11-01, in CI's image): chat had never run in Firefox in CI (streams is chromium and WebKit), and
      fails there on streams too. (a) Fixed in `0ba074e`: Firefox holds a second fetch of a URL behind an earlier
      one's open response, so a second tab's multipart pane got nothing; the pane (and ops') fetch with no-store.
      (b) Fixed in `c587a07`: the chromium rate case typed the next burst before the composer's reset cleared it.
      (c) Fixed in the commit before the mount: full is on the hyperscript client, whose bootstrap fetches its
      scripts with no catch, and Firefox rejects a fetch a navigation cuts; every NetworkError and AbortError the
      members' pages logged came from that one call (the starved box was a separate, local effect). Mounted again
      after (a)–(c). Still to watch: chromium's presence case failed once in CI and passed on retry (a join
      published between the page's render and its #live's subscribe is a candidate).
- [ ] **3. Retention** (§14.1, Q19, D16): the per-kind caps and ages (`CHAT_ROOM_CAP`, `CHAT_DM_CAP`,
      `CHAT_ANNOUNCE_CAP` and their `_MAX_AGE`; a room's own up to 5000 / 90 d), chunked deletes every 50 inserts per
      room, a 60 s age sweep as a job, pinned messages exempt, the in-memory ring (`CHAT_RING_BYTES`), the marker.
      *Check:* the retention spec (`CHAT_ROOM_CAP=5`, send 7 → 5 + the marker); a unit test of the chunking.
      Progress (2026-11-01): the caps and ages per kind, SQLite's trim in the post's batch (every tenth of the cap,
      1 to 50 inserts) and the 60 s `chat.retention` sweep, 1000 rows a transaction, `pinned` exempt
      (`0003_retention.sql`), the memory ring at the cap, the marker; `retention.spec` on both stores, the storetest's
      caps, sweep and a sweep across chunks, `trim_every`'s unit cases. Left: a room's own settings (up to 5000 / 90 d,
      by its owner or an admin), which need the room settings page.
- [ ] **3a. The room settings page** (slice 3's leftover; planning 2026-11-01): a room's owner (or an admin) sets its own
      caps (up to 5000 messages or 90 days), hands the room to another member, or deletes it. It is where an owner gets
      out of a private room, which they can't leave (they'd leave it to no one). *Check:* e2e for each: the caps (a
      room keeping more than its kind), a handover (the new owner's invite panel, the old one's Leave), a delete (its
      members' 404, its rows gone); k6 for the routes.
- [x] **4. Edits, deletes, moderation** (§14.1): own edits within 10 min and deletes; moderators delete to a
      tombstone, mute, kick, lock and slow mode, each with an hx-prompt reason, audited (in the change's transaction,
      as M4-04); the per-message menu `GET /chat/m/<id>/menu` by the viewer's perms. *Check:* e2e per action, the
      tombstone as an upsert, the audit rows.
      Done (2026-11-01): remove, mute, kick, lock and slow mode in public rooms and announcements; reports (with a
      copy) for every room, closed from `/chat/reports`; each audited in the change's transaction through the chat
      store's Audit_Writer; the menu by the viewer's perms (Report, Remove, Mute, Kick, Message <name>).
      `moderation.spec` (each act, the tombstone, the audit rows without the body; a private room's report),
      the storetest's moderation case, the `moderation` scenario. Open: chat.spec's "an open edit form outlives…"
      lost its typed text once over poll in streams webkit locally (1 of 4 suite runs, never in 60 runs alone).
- [x] **5. Presence, typing, receipts, unread** (§14.1, D14): presence debounced 10 s, typing ≤ 1 per 2 s expiring
      after 5 s (memory only), read receipts by `POST /chat/r/<slug>/read?upto=` on `intersect once`, unread counts
      on `notify.user:<uid>`. *Check:* e2e across two members; a receipt never from a GET.
      Done (2026-11-04): M2 built these; `chat.spec` now holds the rest of the check: a reload inside the debounce
      doesn't flap presence, leaving shows away, typing expires, a receipt is a POST alone (a GET is 405).
- [x] **6. FTS** (§14.1, D16): FTS5 over message bodies with triggers, search within the rooms a member may read;
      the budget of 6.4 ms per 1000 retention deletes kept. *Check:* a storetest of search and membership; the
      retention budget measured.
      Done (2026-11-04): `0005_fts.sql`, `/chat/search` over the rooms a member may read, the memory store's scan;
      the storetest's `searching` (membership, a kick, every word, the prefix, typed syntax, an edit and a tombstone),
      `rooms.spec`'s search case. 3.8 to 4.5 ms per 1000 rows (`docs/perf/CHAT-RETENTION.md`). It also found that
      `close` crashed on FTS5's internal statements; fixed.
- [x] **7. Notify on SQLite** (§14.2): `stores/sqlite/notify`, 200 per user, read ones gone after 30 days, mutes per
      room and kind in `accounts_prefs`; mentions and DMs from chat, job failures to admins. *Check:* notify's
      storetest over both families; e2e of a mention's bell and its count.
      Progress (2026-11-01): the SQLite store (the newest 200 trimmed in the add's batch, the sweep, marking read)
      and `notify/storetest` over both families, done first because chat imports notify and `full` is on SQLite.
      Done (2026-11-04): mutes per kind and per room, in notify's store rather than `accounts_prefs` (`send` asks for
      any member, on builds with no accounts: PLAN §14.2 updated); DMs to the other member's Inbox, a failed job to
      every admin's through `send_now` and `jobs_web.admin_ids`; `notify.spec` and `jobs.spec` hold each.
- [x] **8. Uploads** (§14.2, §17.6, X13, X14): create, `PUT /uploads/<id>?off=` chunks of ≤ 4 MiB, finish (sniff,
      decode, sha256, a content-addressed blob); the chunked-upload shim in app.js; progress on
      `uploads.upload:<id>`; caps, content checks and serving headers; 20 an hour and 2 at once per user; chat
      images through it (`Chat_Attach`). *Check:* e2e of a chunked upload, a resume, a refused type; the upload
      decode-bomb fuzz (platform/fuzz) in the unit job and the nightly.
      Done (2026-11-04): progress comes from each chunk's answer, not the topic (a page's `#live` topics are fixed at
      load); PNG and JPEG only, not progressive JPEG (`core:image`); a finish runs one at a time on its own pool. The
      fuzz found two faults in `core:image`, both held off in `uploads.check`, so a decode's arena has a 256 MiB cap,
      which on Houston's 512 MiB is the real limit, below 40 MP for a deep PNG (§17.6 updated).
- [x] **8a. Blob lifetime** (planning, 2026-11-04): holders, not counters; the sweep past 24 h, a member's delete at once,
      a moderator's removal everywhere, audited; a report's own `blob`; reads stay member-wide, written in §17.6 as a
      decision. *Check:* `uploads.spec`, storetests over both families, the domain's `sweep_and_mirror`.
- [x] **8b. Blobs in backups** (planning, 2026-11-04): the daily `uploads.mirror`, following removals by row; DATA.md.
      *Check:* a restore brings an image back (`uploads.spec`).
- [x] **8c. Blocking** (planning, 2026-11-04): the DM closed both ways, no new one, no DMs or mentions in the Inbox; public
      rooms and moderation unchanged, no audit row; Block and Unblock on the DM page and the message menu, the list at
      `/chat/blocks`. *Check:* `blocks.spec`, k6's `blocks`.
- [x] **9. The connection-mode setting** (§14.1): Auto / WebSocket / Streaming / Polling / Multipart in
      `accounts_prefs`, per request by `chat_web`'s switch, `x-impl` on every response; Auto as the spike says.
      *Check:* the four transports × resume specs on `full`, including across a restart (D37).
      Done (2026-11-04): `Auto` the default, falling back by `static/chat.js` for the browser's session; the setting on
      the account through `authz.keep_connection`, a cookie on builds with no accounts; the restart spec now runs on both
      stores.
- [ ] **10. Budgets** (§18, D38): the WS chat budget at 1000 sockets; the writer task ≥ 3× autocommit at 1000
      msgs/s; send → another member's DOM p95 ≤ 50 ms on the LAN through NPM. *Check:* the drills and k6
      scenarios, recorded in `docs/perf/`.
      Recorded in `docs/perf/CHAT-BUDGETS.md` (2026-11-04), with the worst decode against 512 MiB; §18.4's writer row
      restated against a real post (planning, 2026-11-04). It found the socket wait fixed in F-23. Closes after the
      promote, as M5's smoke did: the DOM number through NPM needs Houston on this code (5.3 ms direct), and the invites
      wait on it.
- [ ] **11. The XSS/UGC suite and the oldest browser** (§19.1.2, D22): every place chat, notify and uploads render a
      member's text or file, against the injection set; D22's core flows on the oldest-browser device with no client
      behaviours (htmx 4 there UNVERIFIED (M6)). *Check:* the suite in e2e; the device run recorded.
      The suite is in (`e2e/tests/chat/xss.spec.ts`, 2026-11-04): messages over the four transports, edits, search, room
      names, the Inbox, invites, reports, the audit log, upload names. It found nothing. Closes after the promote, as
      M5's smoke did: the phone is Alex's (v2.5.0's steps), and the invites wait on the walk.
- [ ] **12. Exit**: the slice gate for every new feature; the parity gate on both legs; `docs/audit/M6.md`, the
      focused security audit of accounts, sessions, chat and uploads, by an agent that didn't write the code, 0 open
      CRITICAL/HIGH, and a re-read of its fixes; `Audited:` stamps; CHANGELOG's 2.5.0 lead. Then, with Alex: the
      v2.5.0 tag, `starter-full` promoted, and Q23's 2–3 invites.

## M5 — Operate (v2.4.0)

The starter's fifth milestone ([`docs/PLAN.md`](docs/PLAN.md) §22.3, M5's row; §15.4 ops, status, jobs and dbview; §11.6
retention; §11.8 backups; §10 obs). Its exit gate: the slice gate; one ops render per second whatever the number of
viewers (CPU flat from 1 to 100 viewers); status parts swap independently (the parallel order asserted); a backup and
restore drill; dbview never takes the writer lock. Every page is `/admin/*` on Houston's main host: its `Admin_*`
perm (Admin only), LAN only, audited where it acts. The slices need nothing from Alex until the last (Q25: in-app
metrics only). Pushes are on the standing go; apollo, tags and anything on Alex's hands are asked in one batch.

- [x] **1. ops and status in `full`** (§15.4): mount M2's `ops` and `status` on Houston's main host under
      `Admin_Ops` (status's summary public, its details behind `Admin_Ops`), with the store's `sqlite3_db_status`
      numbers pushed to obs and shown (the store is never imported by ops). *Check:* the ops and status specs on `full`
      (each refresh mode, 403 for a member, 404 off the LAN, a guest sent to sign in); `rbac.spec` covers the rows.
      Done: `houston.spec` (each mode, the Store card, a guest to sign in), `status.spec` on the main host, rbac's
      rows; `ops/houston.js` and `status.js` reach every route on `full`.
- [x] **2. One ops render whatever the viewers** (§15.4): *Check:* a measurement of the server's CPU with 1, 10 and 100
      SSE viewers of `/admin/ops` (`tools/streamload` or a k6 scenario), flat within noise, recorded in `docs/perf/`;
      a unit or drill assertion that the publisher renders once a second.
      Done: the `opsviewers` drill (Windows 0.0 / 1.6 / 3.1 ms of CPU a second at 1 / 10 / 100 viewers, 11 refreshes
      each in 10 s; Linux in CI's `streams` drills), `docs/perf/OPS-VIEWERS.md`.
- [x] **3. status, full** (§15.4): `STATUS_PROBES` externals with a 2 s timeout (connect and the reads share it,
      M5-09; a name to resolve takes the resolver's own time on top), disk
      free and backup age as parts, one `multipart/parallel` response whose parts arrive as each answers. *Check:* a
      spec with a slow and a fast external asserting the fast part swaps first (the parallel order); the ptag variant.
      Done: a prober thread per external with waiters (single-flight), the 2.5 s cut-off on the page's loop, the disk
      part; `status.spec`'s parallel-order case (fast at ~0.1 s, slow at ~1.6 s in a browser) green in chromium and
      webkit on full, lab and streams. Backup age joins with slice 6.
- [x] **4. Runs as data in `platform/workers`** (§15.4, LC §9): each run of a `JOBS` row has an id, a state
      (queued, running, done, failed, cancelled), progress and a bounded log; `run_now(id)` returns the run, and
      `cancel(run)` asks a running job to stop at its next check. workers never calls a feature. *Check:* unit tests
      of the states, cancel and the log bound.
      Done: `Run` in a ring of 64 (`runs_since`, `run_of`), `cancel_run` (`cancel` is the pool's), `current`,
      `progress`, `log` (4 KiB, cut and said), `cancelled`; frequent jobs kept only by hand; a slot still queued or
      running is never overwritten. `workers_test` holds each state, both cancels and the ring's order.
- [x] **5. `jobs`** (`/admin/jobs`, §15.4): `jobs_runs` in SQLite with leases, so a run a restart interrupted resumes
      or fails on boot; the page lists every job, its schedule and last runs, progress upserting over `jobs.runs`
      (key = run id); run now and cancel with an hx-prompt reason, audited; a run's log as a download. Perm
      `Admin_Jobs`. *Check:* e2e (run now, live progress, cancel, the log, a run interrupted by a restart); k6.
      Done: the feature in both store families, mounted in `full`; `jobs.spec` (run now live, the log, the audit row,
      refusals, runs kept past a restart) in chromium, webkit and full-vanilla; the storetest holds the upsert, the
      lapsed lease (only another boot's) and the prune; `jobs.js` reaches every route. Left for slice 6: a cancel and
      live progress e2e on the backup job, which reports both (no job in `full` is long enough before it).
- [x] **6. Backups as jobs** (§11.6, §11.8): `store.backup`, a nightly `VACUUM INTO /data/backups/nightly-<date>.db`
      keeping 7, on the query pool; its age is a status part. *Check:* a backup and restore drill (write rows, back
      up, write more, restore the backup into a fresh server, read the first rows and not the later ones).
      Done: `store.backup` (VACUUM INTO on its own connection, cancellable through the progress handler, a
      quick_check, keep 7), `Job.due` for the nightly hour, `workers.fail`, the `backups` status part through obs; the
      `backup` drill passes on Windows (Linux in CI's full drills); `jobs.spec` runs it by hand (3 of 3, then /status).
      A running cancel is held by workers' unit test: no job here runs long enough for a browser to catch it.
- [x] **7. `dbview`** (`/admin/dbview`, §15.4): read-only SQL on a query-pool reader (`OPEN_READONLY`,
      `stmt_readonly`, `LIMIT_ATTACHED 0`), a 2 s `progress_handler` budget, results capped, step-up, audited. Perm
      `Admin_Db`; SQLite only. *Check:* e2e (a select, a write refused, an `ATTACH` refused, the 2 s budget); a drill
      that dbview never takes the writer lock (a long query beside writes leaves the writes' p99 alone).
      Done: the feature (SQLite only) in `full`; `dbview.spec` (a table, a write, two statements and an attach
      refused, the caps, the 2 s stop, the audit row, the 422s) in chromium, webkit and full-vanilla; the `dbview`
      drill (writes' slowest 2.4 ms alone and beside the query); `dbview/dbview.js` reaches both routes.
- [x] **8. Exit**: the slice gate for every new feature; the parity gate on both legs; `docs/audit/M5.md` by an agent
      that didn't write the code, 0 open CRITICAL/HIGH, and a re-read of the fixes; `Audited:` stamps; CHANGELOG's
      2.4.0 lead. Then, with Alex: the v2.4.0 tag and `starter-full` promoted.
      Progress (2026-10-31): `docs/audit/M5.md` (0 CRITICAL or HIGH, 4 MEDIUM, 6 LOW, 2 NIT; all fixed or said in
      `f42f032`, re-read; the re-read's M5-13 LOW fixed in `23244f2`, its two NIT said). Parity
      (`docs/perf/PARITY-M5.md`): Linux 20 of 20; Windows 19 of 20, `pages@mem`'s p99 1.11-1.12 of HEAD at 2.2 times its
      throughput, accepted as a pass by Alex (2026-10-31). Stamps and the 2.4.0 lead written. M5-09 (connect within the 2 s, reads within what is
      left) and M5-10 (status and the memory jobs store on guard locks, `tools/check locks`) closed 2026-10-31.
      **Done (2026-11-01): M5 is out as v2.4.0, and the whole stack runs it.** Alex tagged v2.4.0 on `7945dcc`
      (release/2.4; release run 41262396834, 18 of 18), put Houston's backups on the HDD (`FULL_BACKUPS`, PLAN §11),
      and promoted the four witnesses, then `starter-full`. Its first snapshot stopped because `/data/backups` didn't
      exist, and nothing was recreated; `3977bbd` makes the directory first (`promote-test.ps1 -Snapshot`), and the
      rerun went through: `pre-v2.4.0.db` taken, healthy, 0 restarts. The smoke through NPM: 21 of 21
      (`deploy/npm-smoke.mjs --houston --version v2.4.0`), a clean Chromium pass over 15 pages on both of Houston's
      hosts (200, CSP, DENY, nosniff, x-version v2.4.0, no console error), /readyz on both, houston `/status` 200,
      `-Status` all five on v2.4.0. The first nightly into `/backups` is due 2026-11-02 at 03:00 UTC.

## M4 — identity and the Houston shell (v2.3.0)

The starter's fourth milestone ([`docs/PLAN.md`](docs/PLAN.md) §22.3, M4's row; §17 the security model, §13 Houston,
§7.3 the two hosts, §15.4 `modules`, §15.5 the lab host). Slices in order, each done only when its check passes; from
here every exit also passes the slice gate (§22.1 (a)–(f)). The slices need nothing from Alex until the last: Q10
(invite-only), Q11 (TOTP for admins and terminal writers, no QR) and Q31 (the grants as tabled) stand as answered, and
Q34 sized the argon pool. Pushes are on the standing go; apollo, tags, Fly, DNS and anything on Alex's hands wait for
Alex, asked in one batch.

- [x] **1. Enforcement completeness** (§17.2): `front`'s perm check over every row is M1's; add `.Step_Up` (a stale
      session goes to the step-up page; the identity says how recent), `ROLE_PERMS` as §17.1's table (Q31's three
      grants as tabled), and `bin --routes --json` printing each row's perm, flags and host. *Check:* unit tests of
      the table and of each flag's answer (401 + `HX-Redirect`, 302, 403, 404 off the LAN, the step-up redirect).
      Done: `authz.refusal` decides, `front` answers (the step-up page itself is slice 5's); `--routes --json` already
      printed each row's host, perm and flags; `authz_test` holds the table and every answer.
- [x] **2. `accounts`' store and passwords** (§17.1; passwords in `platform/password`, L2, so `envadmin` shares them: done): the SQLite store (accounts, sessions, invites, recovery codes,
      `accounts_prefs`), argon2id on its own pool (`ACCOUNTS_ARGON_THREADS`, 1 with ≤ 2 CPUs, a queue of 32 then 503,
      one buffer per worker, 19 MiB, t = 2, p = 1), constant-time compares, the dummy hash for unknown names,
      passwords 10–256 bytes, `--hash-password` printing its derive time, the bootstrap admin from
      `ACCOUNTS_ADMIN_HASH`. *Check:* unit tests (vectors, the dummy path's time, the queue's 503); the pool's memory
      cap measured (threads × 19 MiB, nothing per login).
      Done: `platform/password` (argon2id, PHC, the dummy, the pool with one buffer per worker; its tests) and
      `stores/sqlite/accounts` with `accounts_models` (held by `features/accounts/storetest`). `--hash-password` and
      the bootstrap admin go with the identity, slice 3; the pool's memory cap is measured there under load.
- [ ] **3. Sessions and login, in `cmd/full`'s first host** (§17.1, §17.5, §7.3): `identity_accounts` and `cmd/full`
      with Houston's main host alone (SQLite, the hyperscript client; the lab host is slice 10), so the accounts specs
      have a home; the `sid` cookie (32 bytes, SHA-256 stored, `HttpOnly`,
      `SameSite=Lax`, host-only, `Secure` by `COOKIE_SECURE=auto`; `0` warns at boot and shows a banner), rotation on
      login and privilege change, 14 d idle / 30 d absolute, `/login` `/logout`, the sessions page with revoke; login
      limits (5 per 15 min per client id, 40 overall) and per-account exponential backoff, never a lockout.
      *Check:* e2e of login, logout, revoke and expiry; the login-storm budget (Q34: other routes' p99 ≤ base +
      0.5 ms under `cpus: 2.0`).
      Progress: `cmd/full` (home, about, accounts; SQLite, hyperscript, full theme) in every CI job but the release;
      `identity_accounts` with all of the above; `COOKIE_SECURE=0` warns at boot and the sign-in form says so (the
      site-wide banner waits for the layout's slot, slice 7's shell); `--hash-password` prints the derive time (98 ms
      on the dev PC, debug build); the pool's memory is declared to `--limits` (threads × 19 MiB); the generator gives
      an identity its domain's SQLite need. `accounts.spec` (9 cases) and `accounts/login.js` (100 sign-ins/s at 20
      VUs, the other pages' p99 under 100 ms) green; drills 27/27 on Windows. The Q34 budget holds: `full`'s image
      under `--cpus 2` with one argon thread in WSL, `/about` at 10 VUs, p99 1.02-1.03 ms alone and 1.35-1.43 ms beside
      a 20-VU sign-in storm (31 sign-ins/s), +0.32 to +0.40 ms over three rounds against the 0.5 ms budget. Left: rotation on a privilege change comes with role changes (slice 6). For slice 10: `starter-full` sets
      `ACCOUNTS_ARGON_THREADS=1` (and `THREADS`) in the stack, because the auto rule counts the host's cores, not the
      container's `cpus` quota.
- [x] **4. `audit`** (§17.7), mounted in `full`: `features/audit`, `store:audit`'s `append` in both families (SQLite: `audit_log`,
      append-only by triggers, deletes only past 400 days; memory: one `mod=audit` line), `/admin/audit`
      (`Admin_Audit`, SQLite profiles only) with filters, keyset infinite scroll and CSV through hx-download.
      *Check:* the triggers refuse an update and an early delete; e2e of the filters and the scroll; load.
      Done: `audit_log` with both triggers (`audit/storetest`: an update and an early delete refused, a 401-day-old
      entry deleted); `/admin/audit` (LAN only) with the actor and action-prefix filters as a plain GET, `intersect
      once` keyset pages of 50, and `/admin/audit/export` (up to 10,000 rows, formula-guarded CSV, `web.respond_csv`);
      accounts' sign-ins, wrong passwords and revokes audited; `audit.spec` (3 cases, 9/9 over three repeats) and
      `audit/audit.js`. The generator gives an identity its own feature deps (`identity_accounts` brings `audit`, so
      `streams`' nick doesn't). Later: the nightly prune past 400 days (with M5's `jobs`); the bootstrap admin's
      creation is an obs line, not an entry (boot has no loop for the append to answer on).
- [x] **5. TOTP, step-up and recovery** (§17.1, Q11): RFC 6238 with its vectors, manual secret entry and the
      `otpauth://` text, required for Admin (and `Term_Write` later); the step-up page (password or code within
      10 min) on `.Step_Up` rows (role changes, invites); 10 recovery codes and admin-issued one-time reset codes,
      hashed. *Check:* unit vectors; e2e of enrolment, step-up and a recovery.
      Done: `platform/totp` (L2; RFC 4226's and RFC 6238's vectors); `/accounts/totp` (the secret in base32 and as
      `otpauth://` text, on by a code, ten recovery codes shown once and stored hashed; new codes and off are
      `.Step_Up` rows); the code step after the password (a pending token signed with a boot key, five minutes; a
      code or a recovery code spent in the session's own write, migration `0002_totp.sql`'s `totp_last_step`, so
      none is taken twice); `/step-up` (the password, or a code), returning a write to the page it came from
      (`HX-Current-URL`); an Admin without TOTP is a Member (`ACCOUNTS_ADMIN_TOTP=required`, the default; the
      suites run `optional`); `ACCOUNTS_STEP_UP_WINDOW`. `totp.spec` (3 cases), `accounts/totp.js`. Found on the
      way: `load_viewer` cleared the cookie on any store error, not only on a session that ended (now a guest
      once, the cookie kept, a warn line); `audit/audit.js` had measured `/login` (k6 empties the cookie jar each
      iteration: `noCookiesReset`, and a checks threshold on both new scenarios). The admin-issued reset codes go
      with `/admin/accounts` (slice 6).
- [x] **6. Registration, invites, profile and `/admin/accounts`** (§17.1, Q10): `ACCOUNTS_REGISTRATION` (`invite` by
      default; `open`, `closed`), `/invite` redemption (limits), `/register`, display names through `clean_name`,
      `accounts_prefs` (theme, chat transport, mutes), `/admin/accounts` (roles, disable, invites, reset codes; the
      last admin can't be demoted or disabled), every action audited with its `HX-Prompt` reason. *Check:* e2e per
      mode; the last-admin rule; `escaping.spec` over the new fields.
      Done: `/register` in the three modes (an invite link is `/register?code=…`, 100 bits, its role and its uses
      spent in the one write that creates the member and signs them in); usernames 3-32 of `[A-Za-z0-9_.-]`, display
      names through `clean_name` (the profile edits it); `/reset` with an admin's one-time code (60 bits, 24 h,
      migration `0003_reset_codes.sql`; every session ends); `/admin/accounts` (LAN only, every write a step-up and an
      `HX-Prompt` reason, audited): roles and disable (the member's sessions end; the last enabled admin stays),
      reset codes and invites shown once; `password.submit_hash` for the pool. Limits: 3 registrations and 10 codes
      an hour per client. `members.spec` (4 cases, the hostile-name case standing in for `escaping.spec`, which runs
      on the profiles with UGC fields) and `accounts/members.js`. Moved: `accounts_prefs` goes with its first reader
      (the theme with the `houston` theme, slice 10; the chat transport and mutes with chat on `full`), rather than a store
      nothing reads.
- [x] **7. `envadmin`** (§17.1): the stateless signed-cookie identity, one admin from `ACCOUNTS_ADMIN_HASH`, for the
      SQLite-free profiles. *Check:* unit tests (sign, tamper, rotate signs everyone out); e2e of its login.
      Done: `identity_envadmin` (`admin=<issued>.<expires>.<mac>`, HMAC-SHA256 with `ACCOUNTS_ENVADMIN_KEY`, 7 days;
      the issue time is the step-up time, and `/step-up` issues a fresh one); `/login`, `/logout`, `/step-up` on the
      argon pool, limited, audited through `store:audit`; `--hash-password` moved into `platform/password` for both
      password identities. Its unit test (signed, ended, issued later, a new key, no MAC) and `envadmin.spec`, which
      the nightly runs on a generated `--identity envadmin --features notes` project (63 specs green locally).
- [x] **8. Revocation on streams** (§17.2.3, X19): a kick or role change publishes a revoke that closes the viewer's
      streams with 1008; SSE gets the named `kicked` event, which goes to `/login`. *Check:* `revoke.spec` (at most 3
      reconnects in 30 s), and whether hx-sse stops retrying after a 403 settled (UNVERIFIED (M4)).
      Done: `hub.revoke(user_id)` kicks every member topic of theirs with 1008; a member's `#live` carries
      `data-revoke="/login"`, and core.js goes there on its `kicked` (the lab's own kicks still reconnect);
      `identity_accounts` has a member topic, `accounts.user`, and `full` mounts the hub; a role change or a
      disable revokes. Answered: hx-sse does **not** stop after a 403 (5 reconnects in 30 s, backing off), so core.js
      settles a stream refused with 401, 403 or 404 (it cancels the next connection). `revoke.spec` (both cases, 1
      reconnect at most), `accounts/live.js`. A member revoking one of their own sessions doesn't end that device's
      open stream (the topic is the member's, not the session's): it ends at its next request.
- [x] **9. `modules`** (§15.4, Q28: no runtime disabling): `/admin/modules` (`Admin_Modules`): the profile, its
      family members, the switched implementations, the routes per host with perms and flags, bundle extensions, env
      (secrets masked), limits, health, migrations. *Check:* e2e; it imports no feature (`tools/check imports`).
      Done: `features/modules` (a web package alone, LAN only), mounted in `full`; `platform/app` records the build in
      `web.build` at `app.check` (profile, families, features, the main bundle's extensions, every route per host)
      and the SQLite store lists each `migrate` in `store.in_force`; a secret shows only as set or unset;
      `tools/check imports` refuses modules any feature or store. `modules.spec` (2 cases), `modules/modules.js`.
      The switched implementations aren't listed: they are chosen per request (`x-impl`), and the catalog's
      `switched` field already names them per feature.
- [ ] **10. `cmd/full` and its two hosts** (§7.3, §15.5, F2): Houston on `SITE_URL` (`home`'s Today with cards, nav
      from `brand.odin`, the `houston` theme, which a member keeps in `accounts_prefs`) and the lab host on `SITE_URL_LAB` (`landing` at `/`, `notes`,
      `dashboard` at `/dashboard`, `gallery`, `contacts`, `about`, `lab`, `scripting`, `compat`; `LAB_NAV`), the
      boot's lab rules (§6.1 check 4), no identity and no cookie on the lab host, `NOTES_CAP` 500 and
      `CONTACTS_CAP` 2000 with their 04:00 resets; `starter-full` in `deploy/compose.yaml` (512 MiB) and the release
      matrix. *Check:* every route × both hosts (a row answers on its host, 404 on the other; a `sid` on the lab host
      is a Guest); the demo resets run.
      Progress (part a): the two hosts. `full`'s lab host (`SITE_URL_LAB`, `LAB_BRAND`, `LAB_NAV`, `LAB_ROUTES`,
      `LAB_TOPICS`, `LAB_JOBS`) carries `landing` at `/`, `dashboard` at `/dashboard`, `gallery`, `contacts`, `lab`,
      `scripting`, `compat` and `about`, with no identity (`notes` waits: its card is `home`'s, Houston's, so it has
      no page on the lab host yet, and `NOTES_CAP` with it); boot refuses two hosts on one name; `app.serve`
      takes a brand per host. The suites: the lab host is `127.0.0.1` and the main host `localhost` on one port
      (`--features --json` now lists each host's features; a spec goes to its own feature's host, and one whose
      features sit on different hosts is skipped); `hosts.spec` walks every literal GET row on both hosts and checks
      a `sid` means nothing on the lab host. Fixed on the way: the dashboard's canonical and title follow the path
      it is served at; the layout's search box carries `hx-nonce` on a `.Nonce_Csp` page; a loopback origin counts
      as a placeholder. tools/init writes and edits one-host profiles only, and says so for `full`. Part b: `CONTACTS_CAP` (2000)
      refuses a create past it as a validation error, and `contacts.reset` (`DEMO_JOBS`, which `full` mounts and the
      skeleton doesn't) starts the rows over once a day at `CONTACTS_RESET_HOUR_UTC` (2: 04:00 in Romania's winter,
      05:00 in summer; a UTC hour because the image has no tz database). `contacts/storetest` holds the reset,
      `contacts/demo.spec` the cap; the suites lift the cap. Part c: `starter-full` in `deploy/compose.yaml` (512 MiB,
      two cores, two loops, one argon thread, `DB_PATH` on its own volume, the admin hash as a compose secret file
      because a PHC string is all `$`), behind a `houston` profile so a plain `up` and the stack test run without it;
      promote knows it (snapshotted, promoted only when named) and the release matrix lists it. Its first deploy is
      Alex's: a release with its image, the `admin-hash` file on apollo, and the NPM hosts. Part d: the `houston` scheme
      (modern style; the full theme is 6 × 24 now) is Houston's server-rendered default (`Brand.style`/`scheme`), and
      a member's pick is kept in `accounts_prefs` (`POST /accounts/theme`, 204; the viewer carries it): the layout
      renders it with `data-kept`, which the pre-paint leaves alone, so every device of theirs shows it.
      `accounts/storetest` and `members.spec` hold it. Left: the first deploy (Alex's, above).
- [x] **11. Behaviours and `full-vanilla`** (§12.4, D22): the hyperscript behaviours `full` needs and their vanilla
      twins; the `full-vanilla` build in both build scripts. *Check:* behaviour duality (the same specs on `full` and
      `full-vanilla`); injected `_` inert. *Done:* `full` needed no new behaviour: its core flows are forms and htmx,
      and every behaviour it renders is twinned or an enhancement. `full-vanilla` is a `build.sh`/`build.bat` row
      with `src=full` (`app/cmd/full`, no directory of its own); prepare bundles its assets, tools/check checks it
      (parity skips it: full's runs hold those routes) and tools/init leaves it out. CI checks it, builds it on
      ubuntu (tests and smoke) and runs the chromium specs on it: 143 passed locally, the hyperscript-only ones
      skipped. `escaping.spec` holds the injected `_` inert on both: the gate on hyperscript, no runtime at all on
      vanilla.
- [ ] **12. The M4 specs** (§17.2, §17.3, §19.1): `rbac.spec` generated from `bin --routes` (100 % of routes × roles ×
      both hosts, freezing Q31's grants), the CSRF and CSWSH specs (a cross-site POST and a foreign-Origin upgrade get
      403), `headers.spec` and `csp-clean.spec` on both hosts, `csp-enforced` and `streams-hxcsp` on the lab host,
      `e2e-proxy` for `full` × chromium. *Check:* all green in three engines. *So far:* `platform/rbac.spec` walks every
      row × Guest, Member, Moderator and Admin (an admin's invites make the two between) × both hosts against the grants
      it freezes, and off the LAN holds `.Lan_Only` rows 404 for an admin; it reaches no handler (a write carries a
      Content-Length past every cap and no body, so an admitted one stops at 413, and `Connection: close` spares a
      refusal the drain). `platform/cross-site.spec`: every write forged three ways on every host, signed in, is 403,
      and no foreign-Origin upgrade becomes a socket. Both api-only, green on all five profiles (a dropped grant fails
      rbac). headers and csp-clean walk both hosts (the lab host sets no cookie); csp-enforced and streams-hxcsp
      already run on `full`'s lab host (9 green). `e2e-proxy` gains `full` behind Caddy and NPM (`E2E_PROXY_LAB`; the
      proxied server counts the proxies' networks as its LAN): Houston's own specs, the platform's on both hosts and
      proxy.spec on the lab host's name (the lab legs take the lab pages through both proxies already; one shared
      server behind a proxy also holds every spec's state, which the demo specs don't expect). Their first run found
      the lab helpers naming 127.0.0.1 (the proxied main host there) and a revoke spec counting exactly two
      sessions; both fixed. Left: those two legs green. Fixed on the way:
      tools/init named the catalog's profiles in the scripts' usage lines, which full-vanilla broke (13199fa).
- [ ] **13. Nightly fuzzing** (§19.1, D44): pairwise and selection fuzzing of the generator's selections. *Check:*
      one nightly run green. *So far:* `tools/init --pairwise --seed <n>` (pairwise.odin) builds a strength-2
      covering array over feature presence by seeded greedy search (our own xorshift, so a seed is the same rows
      everywhere), each row a closed selection `select` accepts and never `dashboard` with `landing`; seed 1's
      15 rows cover every feasible pair, and the 33 pairs no valid selection holds are listed as infeasible.
      `.github/matrix/pairwise.json` is that output, which CI's generator job holds current. `--random --seed <n>`
      prints one random valid selection. nightly's `selections` job turns the array, three random selections
      (seeded by the run number) and every singleton into a matrix; each is generated, boot-tested and run
      through chromium and api. The first array found a generator bug: a selection with `scripting` or `compat`
      gets the anonymous identity, and `ops`, `audit` and other features with member-only rows can't boot
      without one; `select` now refuses that (the catalog marks a feature `gated` when a ROUTES row asks for a
      permission). Generated projects drop the two jobs and the array. Left: one nightly run green.
- [x] **14. Exit**: the slice gate (a)–(f) for every new feature; the parity gate on both legs; `docs/audit/M4.md`
      by an agent that didn't write the code, 0 open CRITICAL/HIGH; `Audited:` stamps; CHANGELOG's 2.3.0 entry.
      Then, with Alex: `--hash-password` for the bootstrap admin (Alex alone; it measures apollo's derive time), the
      v2.3.0 tag, `starter-full` promoted, and Houston and its lab host through NPM at stage 1b (no invites yet).
      Progress (2026-10-30): `docs/audit/M4.md` by an agent that didn't write the code (1 HIGH, 3 MEDIUM, 9 LOW,
      3 NIT), fixes in `30988ae` and after, then a re-read by another: 0 open CRITICAL or HIGH (M4-01 fixed and
      read; the re-read's M4-17 MEDIUM and two LOWs fixed). The parity gate's Windows leg at `d136601`: 18 of 20 at
      n = 3, `seo@file` passes at n = 5 (1.00); `static@file` reads 0.97 at n = 5 with `static@mem` at 1.00 on the
      same code path; again at n = 5 at `eb228d8`, `static@file` 0.98 and `static@mem` 0.95 (25 % background):
      the static cells alternate around the bar. Linux at `eb228d8`: 20 of 20 (`docs/perf/PARITY-M4.md`). The stamps
      and the 2.3.0 lead are done. Left: Alex's call on the Windows static cells, and Alex's part.
      **Done (2026-11-01): M4 is out as v2.3.0, and Houston is deployed at stage 1b, no invites.** Alex made the
      bootstrap hash on apollo (`derive: 33.3 ms`, Q34's cost there), tagged v2.3.0 on `64c674d` (release run
      41254342837, 19 of 19), and ran `promote.ps1 -Tag v2.3.0 -Service starter-full` (after `3738749`'s
      ValidateSet fix): healthy, 0 restarts, 3.2 MiB. The smoke through NPM: 21 of 21 (`deploy/npm-smoke.mjs
      --houston`) and a clean Chromium pass over both of Houston's hosts, /readyz on both.
- [x] **M4 audit** (`docs/audit/M4.md`): every finding closed. Fixed: M4-03, M4-04, M4-12's code (the key's and the
      backups' place on apollo is Alex's) and M4-13's rest (2026-11-01), M4-05 and M4-09
      (2026-10-31), M4-06, M4-07, M4-08, M4-10, M4-11, M4-14, M4-15, M4-16, M4-12's busybox pin (and M3-08's),
      M4-13's four parsers (and M3-09's `ws_field`).

## M3 — pipeline, apollo LAN, the landing page (v2.2.0)

The starter's third milestone ([`docs/PLAN.md`](docs/PLAN.md) §22.3, M3's row; §20 pipeline, hosting and deploys,
§15.5 the lab's pages, §18 the parity gate). Slices in order, each done only when its check passes. Slices 1–8 need
nothing from Alex; 9 and 10 start with Alex's steps (§20.7) and every promote to apollo waits for Alex's go, as does
every push and tag. apollo stays read-only until slice 9, and its other services are never touched. `FLY_DEPLOY` stays
off until Alex sets it before the v2.2.0 tag.

- [x] **1. The release image** (§20.2): the runtime stage on distroless `base-nossl-debian13`, `USER 10001:10001`,
      `STOPSIGNAL SIGTERM`, `HEALTHCHECK` through the binary's `--healthcheck`, the binary at `/app/bin`; the build
      stage picks Odin's amd64 or arm64 asset by `TARGETARCH` (the digests `setup-odin` and `check-pins.sh` hold);
      `SOURCES.md` naming the base's Debian source versions. *Check:* the `docker` job builds every hosted profile
      (minimal, streams, skeleton, lab), each turns healthy through `--healthcheck`, runs as 10001 on a read-only
      rootfs, stops on SIGTERM within 6 s, persists to a fresh `/data`; `readelf -d` lists only `libc.so.6` and
      `libm.so.6` with SQLite linked (skeleton); each image ≤ 25 MB compressed (D38). `fly.toml` and the Fly job keep
      working on the new image.
      Progress: the Dockerfile and the per-profile `docker` job, replayed in WSL: all four pass (6.5–7.4 MB
      compressed; glibc only; stop 0.6–1.2 s). Green on CI run 40772472633 on `681c283`, all four profiles.
- [x] **2. The release workflow** (§20.1's `release`, §20.2): on a `v*` tag, each hosted profile built natively on
      `ubuntu-latest` (amd64) and `ubuntu-24.04-arm` (arm64), pushed by digest and merged into one manifest list,
      `ghcr.io/alexh95/odin-htmx-starter-<profile>:vX.Y.Z` and `:sha-<7>` (never `latest`), a provenance attestation,
      and a GitHub Release whose notes are the tag's CHANGELOG section. `deploy-fly` moves onto the tag
      (`vars.FLY_DEPLOY == 'true'`). *Check:* a `workflow_dispatch` dry run builds every profile on both arches and
      turns each healthy without pushing; the real run is v2.2.0's (Alex's go).
      Progress: `release.yml` (the Fly job moved there from `ci.yml`), actionlint clean; the dry run's amd64 leg
      replayed in WSL for lab (healthy, `x-version`) and the notes' CHANGELOG cut checked on 2.1.0. The first dry run
      on GitHub (run 40785174422, on `681c283`) failed on arm64: the build stage's `ARG TARGETARCH=amd64` won over
      BuildKit's value, so the arm64 runner fetched (and checksummed) amd64's Odin, which couldn't run there
      ("Exec format error" in `prepare`); every other leg was cancelled with it. Fixed: the ARG is declared bare and
      the RUN falls back to amd64 only when it's empty. The dry run again (run 40790281475, on `a2488d5`): all eight
      images, four profiles on both arches, built and turned healthy; nothing pushed, the publish, release and Fly
      jobs skipped. Left for v2.2.0 (Alex's go): the real run, and the GHCR packages public. A pre-release tag (`v2.2.0-rc.1`,
      Alex's pick for slice 9's first images) makes a pre-release, not latest, with `[Unreleased]`'s notes; the cut
      checked by hand for the rc (88 lines, flagged), for 2.1.0, and refused for 2.2.0 until its section exists. At v2.2.0, check the four GHCR packages are public: a
      new package can start private, and apollo pulls without credentials (Q18), so Alex may have to flip each once.
- [x] **3. The apollo stack** (§20.4): `deploy/compose.yaml` (the stack Caddy on `8120:80` with a fixed
      `ipv4_address`, the four witnesses as witnesses, `starter-full` from M4; the pinned `172.31.120.0/24` subnet,
      `TRUST_PROXY` = Caddy's address as a /32; every service's hardening, healthcheck and log rotation),
      `deploy/.env.example` (the tags), and `docker/seccomp-io-uring.json` staged next to `compose.yaml` (X21).
      *Check:* the `docker` job brings the stack up from locally built images with the file staged as promote stages
      it: every service healthy, each host answers through the Caddy, a bare IP gets 421, the app sees the Caddy's
      `X-Real-IP` and refuses it from anyone else.
      Progress: `deploy/compose.yaml`, `deploy/.env.example` (a tag per service, which promote changes one at a
      time) and `deploy/stack-test.sh`, run by CI's new `stack` job; in WSL the four witnesses answer through the
      Caddy, a bare address gets 421, `X-Forwarded-For` from the gateway reaches the app as the client (the
      nickname form) and the gateway alone doesn't, every app is read-only as 10001 under the seccomp profile with
      no published port, and a witness recreated behind the Caddy loses no request. The stack test found F-24 (a
      HEAD sent the GET's body). Green on CI run 40772472633 on `681c283` (`The apollo stack (compose)`).
- [x] **4. proxy-config** (§20.1, X26): a CI job: `caddy validate` on `deploy/Caddyfile` and every Caddyfile snippet in
      the docs; `nginx -t` on §20.4's Advanced snippet inside NPM's template (`tests/proxy/npm.conf`); curl assertions
      for every redirect alias, bare and deep (D25), and the 301 from `htmx-odin-starter`; the `8120:80` publish and
      the catch-all's 421 (X23). *Check:* the job is green and fails on a broken alias.
      Progress: `deploy/proxy-config-test.sh` and the `proxy-config` job; in WSL it validates the Caddyfile and the
      docs' 3 snippets, `nginx -t` passes, the 8 aliases, the 301 and the 421 answer as written, and a broken alias
      fails it. Green on CI run 40772472633 on `681c283`.
- [x] **5. `deploy/promote.ps1`** (§20.5, D42): `-Target apollo-lan|apollo -Tag vX.Y.Z [-Service …]`: stage
      `compose.yaml`, the Caddyfile, `.env` and the seccomp file over the SSH alias; `docker compose pull`; the
      pre-deploy snapshot (`--backup`, keep 5) where a service has a volume; `up -d --no-deps` one service at a time,
      no Caddy reload; smoke (`/readyz`, `x-version == tag`, an SSE first event, a WS echo); `deployed.json`; on a
      failed smoke, the previous tag again, automatically. `-Status` is the read-only inventory (RAM, disk, kernel,
      Docker's fd default, NPM version, `:8111` reachable); `-WhatIf` prints the plan. *Check:* against a local
      Docker target in WSL: a good tag promotes, a deliberately broken one rolls back by itself, and `-Status` reads
      without writing.
      Done locally (`-Target local`, WSL's Docker): all four promoted and smoked; a `broken` tag on starter-lab
      (another profile's image, so its `x-version` is wrong) failed its smoke and went back to the previous tag by
      itself, exit 1; `-Status` printed the inventory. The site values are in the git-ignored
      `deploy/promote.local.psd1`. Its first run against apollo is slice 9's, with Alex's go.
- [x] **6. `landing`** (§15.5): the lab's `/`, the catalog explorer from `docs/catalog.json` (features,
      implementations, dependencies, sizes, SQLite needs), the init-command builder (the `odin run tools/init -- …`
      line and its `--explain`; cut-list item 11) and links to every witness. *Check:* e2e (3 engines) and a k6
      scenario; route coverage; `tools/check` all.
      Progress: `features/landing` (the catalog parsed at boot, `plan` mirroring the generator's rules, the page
      rendered once, `GET /landing/command`) mounted at the lab's `/`, the lab index at `/lab`; `landing.spec`
      (chromium, webkit, api) and `scenarios/landing` (20 VUs, 0 % failed); `tools/check all` and `odin test
      tools/init` pass; the catalog lists it. Route coverage and lab's Firefox e2e green on CI run 40772472633. A project that selects
      `landing` would lose its catalog to `new_project`, which deletes `docs/catalog.json`: keep it then.
- [x] **7. The witness board** (§15.4, D36): `status` in `cmd/lab` with `STATUS_PROBES` externals, each witness's
      `/healthz` and `x-version` over `platform/stream/client`, 2 s timeout each, its part swapping in as it answers.
      *Check:* e2e with one probe answering slowly and one down; k6; the board's parts arrive in answer order.
      Progress: `status` gained `STATUS_PROBES`, probed by its own thread every 10 s (the board shows the last
      answers, so it never waits on a probe: the answer-order check is M5's, for probes it runs per request); the lab
      mounts it, its nav names it, and the stack's lab probes the other three. `status.spec` (lab and streams) has a
      live witness ok with its version and a closed port down; the stack test sees all three witnesses up with their
      versions. k6's status scenario runs on lab too. Green on CI run 40772472633 on `681c283`.
- [x] **8. M2's carry-overs** (owner M3): the audit's M2-18, M2-21, M2-31's socket part, M2-33, M2-35, M2-36 (each
      below); `mixed@file` on Linux; `scale`'s budget re-measured and tightened (Left over); `tools/init`'s
      `new_project` removing `deploy/compose.yaml` and `deploy/promote.ps1` (Left over); lab's Firefox `page.goto`
      stalls (below). *Check:* each finding's test fails without its fix; `docs/audit/M2.md` resolution updated.
      Done: M2-18 (`panel.spec`), M2-21 (`body_test`'s `post_stream_gives_its_arena_back`), M2-31's socket part and
      M2-35 (`chat.spec`'s `a poll from before…` and the two `a reconnect past what the room let go` tests), M2-33 and
      M2-36 (`stream_test`, `chat.spec`'s brackets): each test fails with its fix taken out and passes with it, and
      `docs/audit/M2.md` closes every finding. `mixed@file`: no cost (below). `scale`'s budget, `new_project`'s M3
      files and the Firefox stalls: done earlier in M3.
- [x] **9. Stage 1a, apollo LAN direct** (§20.3). First, **Alex's steps** (§20.7): create
      `<APOLLO_DATA_DIR>/odin-htmx-starter` with sudo; the seven DNS-only `A` records pointing at `<APOLLO_LAN_IP>`
      (`houston`, `houston-lab`, `odin-htmx-starter`, `htmx-odin-starter`, `starter-minimal`, `starter-streams`,
      `starter-skeleton`); the permission rule for `deploy/promote.ps1`. Then, each promote with Alex's go: minimal,
      streams, skeleton and lab by `promote -Target apollo-lan -Tag v2.2.x` with smoke; the inventory (`-Status`)
      recorded in `docs/private/APOLLO.md`; the seccomp path, the publish and the 421 confirmed on apollo; a broken tag
      rolls back by itself; 0 5xx through Caddy during a promote under 50 VUs; two-host k6 (dev PC → apollo).
      Done 2026-10-29 at `v2.2.0-rc.1` (pre-release run 40968275138; the four GHCR packages pull anonymously): each
      promote's smoke green; seccomp on every app container, only Caddy publishes `8120:80`, a bare IP gets 421; the
      seven names answer through `:8120` (Houston's two 503 until `starter-full`, M4). The broken tag was `sha-70c427f`
      (the rc's image, so `x-version` is wrong): its smoke failed and the rc came back by itself. Under 50 VUs on
      minimal through that promote's two swaps: 838,878 requests, 0 5xx, max 5.8 s. Two-host k6, skeleton at 50 VUs
      over ten scenarios: 0.00 % failed, 0.9k (pages) to 10.2k (seo) rps, static at the 1 GbE wire. Numbers in
      `docs/private/APOLLO.md`.
- [x] **10. Stage 1b, apollo LAN via NPM**. **M3-03** is deferred to before stage 2 (Alex, 2026-10-30; a stage-2
      blocker, in M12's exit): the Caddy trusts the stack network's gateway, which
      every host-local and (suspected) IPv6 connection to `:8120` arrives from too, so any of them can name a LAN
      address. The fix: trust NPM by an address only NPM has (NPM on the stack's network, or a small shared one, at a pinned
      address; 8120 then off the host's other addresses), and put the apps on an `internal` network (M3-07's rest).
      That needs a further NPM change of Alex's. Slice 10's own steps, first **Alex's**: the four NPM proxy hosts (houston, houston-lab,
      starter, skeleton-lan) with §20.4's details and Advanced snippet, and the Access List "LAN only";
      `worker_connections 4096` in NPM's `events.conf`. Then: e2e smoke through NPM; 1000 SSE held 1 h through NPM
      with no idle cuts.
      Done (2026-10-31): Alex's NPM steps; `deploy/npm-smoke.mjs` 15 of 15 (HTTP/2, a clean render, the 301s, SSE's
      first frame unbuffered in 21 ms, the WebSocket upgrade); `deploy/npm-hold.mjs`: 1000 SSE held 60 min through NPM,
      none ended early, none quiet a minute, NPM flat at about 303 MiB and the lab at 7 MiB, with the lab's stream caps
      lifted for the window and put back by Alex after it (2026-10-31T23:34:59Z).
- [ ] **M3's open findings, later**: M3-04 (the status watcher's `guard.Mutex`, `guard.call` and a bounded dial: with
      M5's `jobs`); M3-11 (a socket version above the room's
      read as a restart's: with M6's SQLite chat); M3-06's smoke of the pushed digest; M3-13's Caddy recreate (done by Alex 2026-10-31: promote never recreates the Caddy, so its new capabilities and memory limit reach
      apollo only when it is recreated: do it with slice 10's Caddy change, by hand with Alex's go).
- [x] **11. Exit**: the parity gate on both legs (X25), with `starter-skeleton` passing it and the 01 (A) 40-item
      checklist on apollo's LAN; `docs/audit/M3.md` by an agent that didn't write the code, 0 open CRITICAL/HIGH;
      `Audited:` stamps; CHANGELOG's 2.2.0 entry. Then Alex sets `FLY_DEPLOY=true`, the v2.2.0 tag (Alex's go) runs
      the release and `deploy-fly` from `cmd/skeleton`, and the Fly cost is recorded (warn Alex above $10/month).
      Progress (2026-10-30): the parity gate passes on both legs, 20 of 20 each (`docs/perf/PARITY.md`; Windows at
      `c490e2a` with its busy blocks re-run in place and `static` at n = 5, Linux at `48666d6`); `docs/audit/M3.md`
      by an agent that didn't write the code, then a re-read of the fixes by another: 0 open CRITICAL or HIGH (M3-01
      fixed and read; M3-03, MEDIUM, deferred to before stage 2); the `Audited:` stamps at `c490e2a` (status at
      `6bad255`, the fork's F-17 amendment and F-24 in `UPSTREAM.md`); CHANGELOG's 2.2.0 lead drafted under
      `[Unreleased]`. v2.2.0-rc.2 (on `65c399d`, tagged by Alex) released and promoted to apollo's four witnesses; the
      40-item checklist at rc.2, read-only over HTTP from the LAN: every item observable from outside green, the rest
      held by CI at `65c399d`. Left: slice 10 (the stack Caddy's recreate, M3-13, done by Alex 2026-10-31; the NPM steps next) and Alex's part
      (`FLY_DEPLOY`, the v2.2.0 tag on `65c399d`).
      **Done (2026-11-01): M3 is out as v2.2.0.** Alex set `FLY_DEPLOY=true` and tagged v2.2.0 on `8b9999a`
      (release/2.2, the stage 1b result in its lead); release run 41253158208 green on every job (the gate, eight
      images, four publishes, the GitHub Release, Deploy (Fly.io)); v2.2.0 is "latest", every package pulls
      anonymously, and the Fly witness answers `x-version: v2.2.0`. The deploy updated the one machine in place
      (rolling, health checks passed, a 6.1 MB image): the machine count, size and cost are unchanged.
- [x] **A Firefox flake to watch** (found and fixed in M3): v2.1.0's release commit lost lab's Firefox e2e on CI's first try (run 40736711557):
      `page.goto` hit the 30 s timeout in `escaping.spec`'s hyperscript gate (both tries), `scripting.spec`'s password
      rules and `streams-hxcsp.spec`'s unnonced `hx-sse` (each passing its retry); the re-run passed with 3 flaky. The
      same commit's code had passed every job before, so a page load stalls in Firefox now and then, as it did in the
      local container. Find what the load waits on (a stream that never ends the load event?).
      Cause: every response's `Cross-Origin-Opener-Policy: same-origin`. A page's first navigation from `about:blank`
      swaps browsing-context groups, and Playwright's Firefox driver now and then loses it: the server answered
      (`/healthz` in 16 µs), the page reported `complete`, and `goto` never resolved. Python's file server stalled the
      same way with the header added (8 of 120) and never without (0 of 160); so did our `/healthz`, plain text. Fixed
      in the e2e config: Firefox's `browser.tabs.remote.useCrossOriginOpenerPolicy` off in the test browser (0 of 320
      after; lab's and skeleton's Firefox suites clean in CI's image). Worth an upstream Playwright report (ask Alex).

## M2 — stream substrate, `streams` and the lab pages, generator v1 (v2.1.0)

The starter's second milestone ([`docs/PLAN.md`](docs/PLAN.md) §22.3, M2's row; §8.2 streams, §9 the hub, §12 the
client stack, §14.1–14.3 chat, notify and bot, §15.4–15.5 ops, status and the lab pages, §7.4 the generator, §19.1
the tests). Slices in order, each done only when its check passes; a later slice builds only on earlier ones (§22.4).
The S0.3 prototype (`docs/spikes/S0.3/server/`) and its specs (`e2e/spikes/S0.3/`) are where slices 1, 2 and 5
start. Every exit re-runs the skeleton parity gate (§18.2); released as v2.1.0 on 2026-10-28 at Alex's go;
`FLY_DEPLOY` stays off.

- [x] **1. Stream protocols** (`platform/stream`, L3, over F-1 through `platform/web`, which stays the one importer of
      odin-http): the SSE encoder (CR, LF and CRLF each start a `data:` line; ids, named events; `: open` with the
      headers), the WS handshake (`Origin` = the host's origin, or none; version 13, else 426), the strict RFC 6455
      codec (RSV, masking, control frames, fragmentation, UTF-8 across fragments; 1002, 1007, 1009 at 64 KiB), ping
      and the 45 s pong deadline, 1013 before the queue passes its cap with F-1's 2 s deadline, 1012 on drain, 1011
      from `on_crash`; the multipart writer (boundary, CRLF framing, `Content-Length` per part, a preamble); the
      `.Stream` flag's headers; a `virtual.Arena` per stream. *Check:* unit tests from spark's RFC 6455 coverage
      table (03 §5.1, X24), the SSE encoder and a multipart round trip, leaks fatal; `tools/check imports` knows the
      package. Done: 10 unit tests, leak-free; the codec is exercised end to end by slice 5's lab specs. A
      stream's state is on the heap, not a per-stream arena (D12's as-built note: §18.4's 6 KiB a stream).
- [ ] **2. The hub** (`platform/hub`, §9.2–9.4): a shard per loop from F-4's thread hooks, one wakeup per loop per
      burst, the hub mutex a `guard.Mutex`, a ring per topic (`HUB_RING` 256), one refcounted message encoded once
      per transport, `.Queue`/`.Latest` (with the publish key)/`.Sample`, `TOPICS` rows mounted per host
      (`{family, policy, ring, persisted, subscribe, deliver}`), `<epoch ms>-<seq>` ids, the connect procedure
      (`Last-Event-ID`, then `after`, then the row's keyset replay, else `resync`), the caps (256 KiB per stream, 64
      MiB in all, 8/16/8192 streams, 64 KiB messages, 20 connects a minute per client → 429), a 20 s heartbeat per
      loop, kicks with close codes; `/events` in `platform/app`. *Check:* hub unit tests (publish, drain, replay,
      resync, each policy, each cap); a TSan build of hub and stream on Linux with only the nbio mpsc suppression.
      Progress: the hub, the caps (in `platform/stream`, since they cover every stream) and `/events` (`hub.ROUTES`,
      mounted by the profile, with `hub.mount` for its `TOPICS`: PLAN §7.2, D13 as built) are in, with unit tests of
      the rings, policies, cursors and topic names. End to end: the lab specs (slice 5) pass on Windows in Chromium,
      WebKit and the api project, replay, resync and the kick included, and drain and restart on a `TEST_ROUTES`
      build. Left: the Linux leg (CI's lab e2e, slice 16) and TSan (slice 13).
- [ ] **3. Page bundles and flags → CSP** (§12.1–12.2): `web.Bundle` and `BUNDLES` lines; `tools/bundle` builds
      Main plus every bundle a reached package names; the layout takes the bundle; the htmx-config meta from the
      union (strict JSON); `.Private` (no-store, noindex, `hx-history="false"`), `.Stream`, `.Nonce_Csp` (a nonce
      per response, the `hx-nonce` marker the writer replaces, no-store) and the `.Lab_Host` mount rule;
      `Reporting-Endpoints`, `report-to` and a rate-limited `/csp-report` in `streams` and `lab`; boot check 6 over
      every bundle. *Check:* CSP-builder unit tests; `headers.spec` (api) per flag class; `minimal`'s and
      `skeleton`'s headers unchanged. Progress: all of it in the platform (a boosted request for a fixed-bundle page
      gets `HX-Redirect`, PLAN §12.1 as built; `/csp-report` in `web.REPORT_ROUTES`, 10 a minute per client),
      `headers.spec` green on the three profiles, the CSP builder's unit test. Left: `.Private` exercised by a real
      page (chat, slice 8; `.Nonce_Csp` and the page bundles are, since slice 5), and `.Lab_Host`'s `noindex` with
      houston-lab (M4). `tools/check routes` refuses a bare `-` after a literal since slice 12 (`/csp-report` had
      matched nothing until it was `/csp%-report`).
- [x] **4. `client/hyperscript` and `html.behave`** (§12.4, D22): _hyperscript 0.9.94 core pinned (SHA, upstream
      `.br`) by prepare and in `pins`; the `client` family's second member; the `Behaviour` table and `html.behave`
      (`_="install X"` or `data-behave="x"`); the gate in app.js; the platform's core `._hs` set with its vanilla
      twins. *Check:* behave's output per client in a unit test; the gate refuses an injected `_` and an injected
      `text/hyperscript` script (a lab spec); `escaping.spec`'s `_` and `data-behave` rules. Done: both members, the
      table of twenty, `client/core.js` shared by both, lab on hyperscript; `behave_writes_installs` (lab) and
      `behave_writes_twins` (skeleton) under `CMD=test`; `escaping.spec` on every sitemap page and the gate test;
      lab 164, skeleton 195 (api, Chromium, WebKit) and minimal 61 passed, and the skeleton's specs on a hyperscript
      build of it. Changed from the plan: the skeleton's markup moved to `html.behave` as well (D22's M2 note: one
      dispatcher by name), and the notices gained hx-multipart's Shopify MIT notice, owed since slice 3.
- [ ] **5. The lab pages and `cmd/lab`** (§15.5): features `lab` (`/lab/streams`: the SSE, WS and multipart contract
      pages and the WS echo), `scripting` (`/scripting/*`: the nonce class, `live`, `streams`, `tt`) and `compat`
      (`/compat/htmx2`, `/compat/alpine`); `cmd/lab` on memory, anonymous, hyperscript and full, its root row the
      lab index until `landing` (M3), with `about`. *Check:* S0.3's 29 contract checks, plan checks and 20 extension
      checks as `e2e/tests/lab/` specs, green in chromium and webkit on both legs; `csp-clean`, `csp-enforced`,
      `harness-csp`, `streams-hxcsp` and `bundle-race`; load scenarios for every lab route; `lab` builds with no
      SQLite library. Progress: the `lab` feature and `cmd/lab` (on the hyperscript client since slice 4; its root is
      the lab index until `landing`) with S0.3's checks ported to `e2e/tests/lab/` and green on Windows (157 passed with
      the platform specs, Chromium, WebKit, api), load scenarios for every lab route, route parity clean. Two
      lessons in the port: a burst of five 60 KB frames passes the 256 KiB cap while the kernel still has room (the
      never-reads check now fills the kernel first, one message at a time), and a k6 iteration cut off mid-await
      stalls its VU's later awaits (the streams scenario lets the warmup's last iterations finish). Then `scripting`
      (`/scripting`, `/live`, `/streams`, `/tt`) and `compat` (`/compat`, `/htmx2`, `/alpine`) with `.Trusted_Types`,
      `PAGE_BUNDLES` in boot check 6 and feature `static/*.js`; `csp-clean`, `csp-enforced`, `harness-csp`,
      `bundle-race` and `streams-hxcsp` with `scripting.spec` and `compat.spec`: lab 226 passed (api, Chromium,
      WebKit); load scenarios for both. Found on the way: the fork's F-18 (a request right after a stream on its
      keep-alive connection lost its first bytes) and a robots.txt that hid `/lab/streams`. `lab` reaches no SQLite file
      (its dependency list; CI's no-SQLite build of it is slice 16's). Left: the Linux leg of the lab specs.
- [ ] **6. `platform/stream/client` and `tools/streamload`** (§8.2, §19.1.7): one non-blocking chunked, SSE and WS
      client on `core:net`; a multi-threaded fan-out generator with publisher-stamped `data-t` for delivery
      percentiles. *Check:* the client's parsers under table-driven random bytes; fan-out (1000 × 50, 3000), restart
      (4000 back ≤ 3 s), replay and resync, and back-pressure measured on Linux into `docs/perf/`, against §9.5 and
      §18.4. Done but the random-bytes tables: the parsers' tests split every input at every byte; streamload's
      fanout, restart and hold runs meet every §18.4 row on Linux (`docs/perf/STREAMS.md`), per-stream RSS once the
      fork's F-17 was in (16.2 KiB an idle stream before, 3.0 after). Follow-ups: random-bytes tables for the client's
      parsers (slice 13's fuzz tier 2); streamload into the nightly soak (slice 13).
- [ ] **A load sweep on Windows after the socket scenarios** fails a few dials (k6 1213: loopback pairs in
      TIME_WAIT; `load-tests/README.md` "Caveats"), so `--strict` can trip on a scenario that runs clean alone.
      Ways out, for slice 13 or 16: pause between scenarios until TIME_WAIT drains, run the socket scenarios last,
      or gate the parity sweep on Linux only.
- [x] **The skeleton's size budget**: F-17 put the skeleton 512 B past 2.75 MiB, and slices 3 and 4 11,264 B (the
      shared `client/core.js`, the twins' dispatcher, `html.behave`). Alex chose (a), 3 MiB (ANSWERS round 10), in CI,
      the drills, D38 and §18.4; no OMIT flags, no re-encode.
- [x] **6a. The `nick` identity** (`features/accounts/identity_nick`, §17.1, ANSWERS round 9): a signed nickname cookie,
      role User for clients in `LAN_CIDRS` (`ACCOUNTS_NICK_FROM=lan`), Admin for those in `ACCOUNTS_NICK_ADMIN_CIDRS`
      (none by default), Guest for the rest; `NAME`, `SETS_COOKIE`, `load_viewer`, `cli` and its `ROUTES` (the
      nickname form), checked against `authz.Load_Viewer` by `tools/check contracts`; the rest of `accounts` stays at
      M4. *Check:* unit tests (signing, tamper, each CIDR rule); e2e of the nickname form; load. Done: 3 unit tests,
      `nick.spec` (5, chromium and webkit, an off-LAN server of its own among them), k6's `accounts/nick.js`; the
      layout's one `#live` came with it (`web.render_page(…, live =)`, the hub's `member` rows).
- [x] **7. `notify` (memory)** (§14.2): models, domain, the memory store (200 per user), views, web (`/notify`, the
      bell, `notify_web.send`), `notify.user:<uid>` over `#live` with hx-targets on `.notify-count`. *Check:* e2e and
      load, both suites reaching every route. Done: the counts go out of band on the class selector (core htmx swaps
      into every match), so no hx-targets; the store's unit test, `notify.spec` (3), k6's `notify/notify.js`.
- [x] **8. `chat` (memory, four transports)** (§14.1): models, domain (2,000 runes, the 10-minute edit window, the
      caps), the memory store (100 per room, `CHAT_RING_BYTES`), `transport_{ws,sse,poll,multipart}` with their
      `EXTS`, `chat_web`'s switch (cookie, `?transport=`, `CHAT_TRANSPORT`; `x-impl`), topics `chat.room`,
      `chat.presence`, `chat.typing`, read receipts by POST, the post and frame limits, `Composer` and `AutoScroll`
      twinned. *Check:* the chat specs once per transport (`@chat-ws` …), resume without duplicates across
      `setOffline` and a server restart; a load scenario per transport. Progress: all of it, with presence through
      the hub's new `watch`, typing, edits and tombstones, the menu, unread counts and mentions; unit tests of the store
      and the domain; `chat.spec` once per transport by `?transport=` (tags name features and family members, so the
      transports are describe blocks: delivery once and escaped, edit and delete, and a server restart with nothing
      lost or doubled), plus presence and typing, the refusals and the 429, and the setting, 138 of 138 over three
      repeats in chromium and webkit; k6's `chat/chat.js` (every route, the transport rotating) and
      `chat/chat_streams.js` (the socket, the poll's 304, the held streams). Found on the way: memory ids restarted at
      1, so a page's upsert would have replaced old messages with new ones (now the boot epoch × 10⁶ plus the
      sequence), and ranging over `m[k]` of a nil map traps (CLAUDE.md's gotchas). The `setOffline` spec is in too,
      but Playwright's offline emulation cuts only new requests and Chromium's socket: an open SSE or multipart
      response, and WebKit's socket, keep delivering, so for those the restart spec is the resume check. Slice 8 done.
- [x] **9. `bot` (memory, mock)** (§14.3): models, the conversations' memory store, `backend_mock` (`BOT_SEED`,
      `BOT_DELAY_MS`), `bot_web`'s backend switch (`.Llama` joins at M7), SSE delivery (the four frames,
      `hx:release`) and multipart delivery, Stop, `bot.health`, the guest and member limits. *Check:* e2e per
      delivery (deterministic with `BOT_SEED`); Stop ≤ 100 ms; load with 1000 mock generations and a Stop storm.
      Done: `bot.spec` (14, chromium and webkit; 42 of 42 over three repeats), Stop timed in the page well under
      100 ms on both deliveries, the store's unit test; k6's `bot/bot.js` makes thousands of generations a quick run
      (about 23k requests a second at 20 VUs, p95 1.6 ms). Changed: the Stop storm is the e2e timing, since k6 reads a
      stream's body (and with it the generation's id) only at its end; `/admin/bot` waits for a second backend (M7).
- [x] **10. `ops` and `status` (basic)** (§15.4): ops's 1 Hz `.Sample` publisher rendering obs's registry once into
      OOB fragments and SVG sparklines on `ops.panel`, refreshed by SSE, `?mode=poll` (ptag 304s) or multipart;
      `last-crash.txt` after a restart. `status`: one `multipart/parallel` response of each module's health, a
      ptag poll variant. *Check:* e2e per refresh mode; load. Done: ops's `panel.spec` (each mode, the 304, the
      crash file, 403 and the guest's redirect; servers of its own with loopback admin) and `status.spec` (both modes,
      the 304), chromium and webkit; k6's `ops/panel.js` (the load driver makes loopback admin) and `status/status.js`.
- [x] **11. `cmd/streams`** (§7.1): home, notes, chat, notify, bot, ops, status, about on memory, vanilla and lite, with
      the `nick` identity (slice 6a); `build.*` and CI's matrix (tools/init reads the profiles from `build.sh`).
      *Check:* builds with no SQLite library; its e2e in chromium and webkit; its bundle's size recorded (§12.1's
      UNVERIFIED (M2)); route coverage with 0 unexplained waivers. Progress: the profile with home, notes, chat,
      notify, bot, ops, status, the nick identity and about, in `build.*` and every per-profile CI job; the generator composes it
      again; its e2e 151 passed (chromium, webkit, api), its k6 quick run clean, its drills 25/25 on Windows (binary
      1,714,176 B, idle 10.06 MB). The generator's identity handling too (nick by default unless scripting or
      compat, accounts with it, `identity.EXTS`, the host flag; a chat project made, tested, checked and built in a
      scratch copy). Its bundle measured into §12.1: Main 68,186 B raw, 19,967 B br, the four transports' extensions
      28,965 and 8,217 of it; it builds with no SQLite library present (WSL, prepare's SQLite step skipped). Slice 11
      done.
- [x] **12. `tools/check topics` and `exts`**: every `TOPICS` row mounted per host, families unique and in their
      feature's prefix; `BUNDLE_EXTS` names every mounted package with `EXTS` or `BUNDLES`. *Check:* a bad fixture
      trips each. Done: `topics` (families the feature's and declared once; every host's packages with `TOPICS`
      named by its `hub.mount`, and nothing it doesn't mount; `hub.init` called; a literal `hub.publish` names a
      declared family), `exts` (every mounted web package declares `EXTS`; `BUNDLE_EXTS` and `PAGE_BUNDLES` name
      exactly the mounted packages with `EXTS` or `BUNDLES`, an inline row's handler counting as mounted), and in
      `routes` the `-` rule; both in `all`, so CI's check job runs them. The bad fixture trips 13 more (43 in all).
- [x] **13. Stream drills** (§19.1.10): `wsdata` → 1011 with the server up; shutdown ≤ 6 s with 500 SSE + 500 WS
      (WS got 1012); the fd ceiling with 3000 streams; restart, 4000 back ≤ 3 s; TSan with 0 reports on hub, stream,
      workers and store/sqlite (S0.11, one nbio suppression, S0.9); the 1 h soak. *Check:* `tools/drills` on both
      legs and in CI's `linux-ops`; TSan and soak as nightly jobs. Progress: the drills `wsdata`, `streamdrain`
      (which found the drain sending SSE no `retry:`) and `streamfd` in `drills.mjs`, lab in `linux-ops`;
      `tools/drills/tsan.sh` at 0 reports (138 at first: the fork's F-21, a shutdown that woke released loops, and
      F-22, connection arenas TSan can't follow, plus a store test's loop released under the writer);
      `tools/drills/soak.sh`, whose first hour found the hub's idle-ring sweep freeing a ring twice (fixed) and whose
      hour after it passed (RSS 16.3 MB, +0.3 % and +1.0 % a half, 2000 of 2000 back in 1.5 s); both nightly. Slice 13
      done.
- [x] **14. M1's carried findings** (`docs/audit/M1.md`, owner M2): the MEDIUMs M1-02 (a send deadline), M1-03,
      M1-04 with M1-26 (a crash in a continuation or a stream's end), M1-05 and M1-07, now that streams rework the
      drain and the deferred paths; the profile's follow-ups (the connection arena's mutex and header reserves as a
      fork change, one read transaction per page, `tools/profile`). *Check:* each finding's own regression test or
      drill, and the parity gate. Progress: M1-04 (the guard's unwind and the fork's `response_crashed`; the
      `continuation` drill), M1-26 (with F-18; the `streamcrash` drill), M1-02 (`SEND_TIMEOUT_MS`, with F-19 for
      Windows; the `slowread` drill), M1-03 (the exits arm before they log; the `logstall` drill), M1-07 (a reader
      that can't open is a 500; the store's test; opening them at boot cost 1.65 MB idle, so they stay lazy) and M1-05 (the loop gate, the writer's intake,
      the clean path's bound; the `latewrite` drill) fixed. The profile's follow-ups: the header maps reserved
      (F-20), a handler's reads in one transaction (+2.1 % `pages`, Linux), the arena's mutex measured and left
      (95 ns a request), and `tools/profile` (perf samples, folded stacks, the top functions and a spall
      trace; its README), checked on the skeleton's `pages` and `write` in WSL. Slice 14 done.
      The Linux leg of the new drills, with slice 13's: every profile passes (minimal 24/24, skeleton 26/26, lab
      28/28, streams 24/24), once `streamfd`'s curl was taken from PATH on a native Linux run.
- [ ] **Report core:nbio's `SO_UPDATE_ACCEPT_CONTEXT` bug upstream** (found in slice 14; the fork's F-19 works around
      it): `impl_windows.odin` passes no value, so Windows rejects the call and `shutdown` fails on accepted sockets.
      And its Linux tick (the fork's F-23 works around it): `__tick` in `impl_linux.odin` runs the completed queue's
      length as it began, then `_flush_submissions` waits with the caller's timeout even when those callbacks queued
      more, where `impl_windows.odin`'s `compute_timeout` and `impl_posix.odin` use 0. Ask Alex before filing anything.
- [ ] **15. Generator v1** (`tools/init` compose mode, §7.4): `--list [--json]` (committed as `docs/catalog.json`,
      checked fresh in CI), `--explain`, `--profile`, `--features`, `--add`, `--without`, the family commands,
      `--dry-run`, `--verify` (scratch copy, `build.*`, `tools/check profile`, `--features --json` against the plan),
      `--yes`; edits planned against the parsed profile files, any miss aborting with nothing written. *Check:* the
      generator CI job with a rotating singleton per push; a plan that misses aborts cleanly. Progress: all of it in
      `tools/init` (tree, catalog, profiles, compose, explain, project, edit, verify), each feature's lines taken from
      a committed profile that mounts it (D26 as built); `odin test tools/init` composes the three profiles again;
      checked on scratch copies: a new project from `--features notes,about`, `--without about` there, `--add notes
      --profile lab`, `--store sqlite --profile lab`, a client swap that verify refused (lab's test pins hyperscript).
      The rename-only path, broken since M1 (a token the README no longer held), runs again. All nine singletons
      made and verified on Windows (`init ci-<f> --features <f> --yes`). Left: the CI job's first run (a push).
- [x] **16. CI**: `streams` (chromium, webkit) and `lab` (all three, Firefox included) e2e; `e2e-proxy` ({streams,
      lab} × chromium through `deploy/Caddyfile` and through nginx with the config apollo's NPM version generates;
      X26, X40); nightly Autobahn|Testsuite against the lab's WS echo (X24), TSan and soak; `pins` with hyperscript.
      *Check:* every job green on a pushed commit. Progress: lab in every per-profile job, three engines in e2e; the
      `generator` job; `e2e-proxy` for lab through `deploy/Caddyfile` and through `tests/proxy/npm.conf` (NPM's
      rendering at apollo's version, which the config models without naming: the version is a private value), with
      the suite's proxy mode, 84 passed through each in WSL; nightly TSan, soak and Autobahn (247 cases, none
      failed); `pins` already covers _hyperscript. Locally, the lab's chromium and api legs pass on Linux (148).
      `streams` is in check, build, e2e, coverage, linux-ops and `e2e-proxy` (79 passed through each proxy in WSL).
      The first run on a pushed commit (`d9e2e1c`): 41 jobs green, every `e2e-proxy` leg among them; the `generator`
      and lab's and streams' WebKit e2e failed (fixed since: the catalog, libsoup's 1006, the Stop spec's load), so
      `coverage` (the k6 quick runs) was skipped. Reproduced in Playwright's CI image in WSL: lab's extensions 20 of
      20 and streams' suite 84 of 84 on WebKit. The second run (`4b5d49b`): 42 green, and streams' WebKit lost chat
      over poll's edit form to the poll's re-render on both tries (fixed since: the slot is `hx-preserve`). The third
      (`c8e4007`): every e2e job green, and `coverage` ran its k6 quick runs for the first time: every scenario 0 %
      failed, but the bot's p95 was 10 s on Linux, core:nbio's tick stall (fixed since: the fork's F-23). The
      fourth (`118fc82`, run 40648389468): every job green, `coverage` included.
- [ ] **Ask Alex**: X40 says `e2e-proxy` pins apollo's NPM version, which `docs/private/SITE.md` keeps private. The job
      pins the config that version renders instead (`tests/proxy/npm.conf`); naming the image tag in CI would publish
      it. Confirm, or say the version may be public.
- [x] **17. Exit**: the parity gate on both legs; the budgets (bundle sizes, idle, no SQLite in `minimal`, `streams`
      and `lab`); `docs/audit/M2.md` by an agent that didn't write the code, 0 open CRITICAL/HIGH (M1-04 and M1-26
      are due here); `Audited:` stamps; CHANGELOG's 2.1.0 entry; then ask Alex about tagging v2.1.0.
      Progress: the audit at `db27254` (0 CRITICAL, 2 HIGH, 9 MEDIUM, 5 LOW, 5 NIT; M1-04 and M1-26 borne out) is
      resolved but for M2-18 and M2-21 (below); its Resolution section maps each fix to its test. The re-read of the
      fixes at `a6bc5de` found M2-22 (HIGH: JSON5 hid brackets from M2-01's scan) to M2-29, all fixed since; a second
      re-read at `5c5ebf2` found M2-30 (HIGH: a raw line feed did) to M2-32, fixed since but for M2-31's socket part;
      a third at `5395ae0` read them sound (no CRITICAL or HIGH open), and the stamps are on. The parity gate passes
      on both legs at `40f8716`, 20 of 20 cells each counting §18.2's n = 5 re-runs (`docs/perf/PARITY-M2.md`), after the
      TSan gate (0 reports), the 1 h soak (PASS, back 2000 of 2000 in 1.5 s) and every profile's drills and e2e on
      both OSes; 2.1.0's summary is in `CHANGELOG.md`. Pushed (Alex's go, 2026-10-27); tagged
      v2.1.0 once CI was green (Alex: "Tag it", 2026-10-28).
- [x] **M2's open audit findings** (`docs/audit/M2.md`, owner M3): M2-18, a topic has no `.Lan_Only`, so an Admin by
      `ACCOUNTS_NICK_ADMIN_CIDRS` outside `LAN_CIDRS` gets ops' panel stream but not its page (fixed in M3:
      `hub.Topic.lan_only`); M2-21, a POST stream keeps its request
      arena until it ends (fixed in M3: `_body_returned` gives it back where the body's callback returns);
      M2-31's socket part, a chat socket's reconnect upserts the room's last 50 with no cursor, so a page away for more
      than that sees no gap (the page should send its newest id as the socket's first frame, and a snapshot past it
      replace the log); and the third re-read's (`docs/audit/M2.md`): M2-33, core:encoding/json `alloca`s stack per
      key, which neither of `ws_json`'s bounds counts (count `:` outside strings, `#assert` the target's size,
      measure `{"":` nesting, report it upstream); M2-35, SSE's resync and the poll transport upsert across a gap the
      room let go (`changed` reports whether it reached the version; SSE's pane gets a tag); M2-36, a message past the
      socket's bracket bound is refused after the composer cleared it. M3: M2-33 and M2-36 fixed (`stream.ws_field`
      reads hx-ws's field by hand; core:encoding/json is gone from the socket path). M2-35's poll part fixed in M3
      (`changed` reports whether it reached the tag). SSE's resync and M2-31's socket part fixed later in M3: the page's
      version (`#ver-<room>`, kept current by every fragment) goes back on a reconnect (a socket's first frame; SSE's
      resync by `hx-include`), so a gap replaces the log and a restart keeps it (D37); `chat.spec`'s two `a reconnect
      past what the room let go` tests fail without it. M2-21's own test: the fork's `post_stream_gives_its_arena_back`.
      Every M2 finding is closed.
- [x] **`mixed@file` on Linux** (`docs/perf/PARITY-M2.md`, owner M3): M2's candidate read 0.95 of M1's in an A/B
      (rounds 0.93–1.05); A/B it with and without a handler's single read transaction before M3's gate.
      Done (2026-10-29, n = 5 through `parity.sh`'s measurement): with the transaction it reads 1.03 of without on
      `mixed@file` (0.95–1.06) and 1.01 on `api@file`, the control. No cost; nothing to change.
- [ ] **A WebKit flake to watch**: `ops: the panel refreshes every second` failed once by multipart and once by poll,
      each passing its retry, on WebKit in Playwright's image on four pinned cores: the page logged its `#live`
      stream's `/events?…&after=…` fetch as failing "due to access control checks" (WebKit's wording for a fetch that
      failed on the network). Find why that stream's request failed. Repeated there (2026-10-28) it failed 2 of 9:
      by sse the same `#live` error, and by multipart a panel whose count never moved in 10 s (its stream stalled?).
      A full streams run there also had `chat over sse: a message reaches the other member once` fail once, passing
      its retry (its details were lost). The multipart panel failed on Windows' WebKit too (2026-10-28, no retry).
      `chat: an edit and a delete reach the other member` takes 4–7 s alone on Linux WebKit but 14–29 s when four
      copies share four cores, against the 30 s test timeout: one poll run there timed out (with F-23 or without,
      the same). The Firefox flakes in that image were COOP's (above, fixed in M3). (`chat: an edit and a delete reach the other
      member` failed now and then over sse and poll: over poll it was a re-render wiping the edit form, fixed; the one
      sse failure on Windows was most likely the same, its echo landing late.)

**Answered by Alex (ANSWERS round 9, 2026-10-26), before slices 7–11:** nick is built in M2 (slice 6a);
`ACCOUNTS_NICK_ADMIN_CIDRS` (none by default, loopback in e2e) makes its clients there Admin, so `/admin/ops` opens in
`streams`; off-LAN visitors stay Guests under D35's table, and chat shows them a "chat is open on the LAN" notice.

## M1 — request-path substrate, `skeleton` at parity (v2.0.0)

The starter's first milestone of code ([`docs/PLAN.md`](docs/PLAN.md) §22.3, M1's row; M0's spikes are
in [`docs/spikes/`](docs/spikes/)). Slices in order, each done only when its check passes. `app/src`
(the 1.2.x app on the fork) keeps building and passing its tests until slice 7 retires it, so
every slice before that can be compared with it. Released as v2.0.0 on 2026-10-26 at Alex's go; `FLY_DEPLOY`
stays off and Fly keeps serving 6d37506.

- [x] **1. Build line.** `build.{sh,bat} <profile>` at the root (`minimal`, `skeleton`; `CMD=check|test|run`;
      the four collection flags; `-vet -strict-style -warnings-as-errors`; `-define:VERSION`), `ols.json`
      at the root on `skeleton`'s families until `full` exists, and `prepare.*` building SQLite with
      D16's `SQLITE_FLAGS`, recorded in `vendor/sqlite/.flags` so a flag change rebuilds the lib (S0.11).
      *Check:* an unknown profile is refused; `app/src` builds and passes its store and views tests on
      the tuned lib on Windows and Linux.
- [x] **2. Platform L1–L2**, each checking alone: `sys`, `ext`, `sqlite` (`in_sqlite` around every call),
      `escape` (the injection boundary, below `markdown`), `guard` (S0.6), `obs` (logfmt buffers,
      request ids, per-thread counters, health, limits), `env`
      (the typed table), `authz`, `authz/anonymous`, `store`, `markdown`, `workers` (pools, `next_tick`
      replies over F-13, the scheduler). *Check:* `odin check -no-entry-point` per package with the strict
      flags; `odin test` per package under a `Tracking_Allocator` (guard classification, logfmt, env
      parsing, markdown caps, worker replies on the submitting loop). Follow-ups: daily jobs at a local
      time (M4's nightly resets); the jobs page's run history (M5).
- [x] **3. Store families.** `store/sqlite` (v3, `MEMMODE` ephemeral/single, the boot sweep, tmpfs; the
      writer task with group commit and no timer; the query pool; the reader reset pulled from guard;
      `migrate` adopting 709bc94 and v1.1.1 databases; `--backup`, `--adopt-profile`) and `store/memory`.
      *Check:* the runner's 6 cases plus fixture databases written by the real 709bc94 and v1.1.1 binaries;
      a reader sees the writer's commits; 0 re-prepares in 1000 pages; a batch answers each write as a lone
      write would; the reader reset after a pure trap. Follow-ups: the dashboard and ops numbers
      (`sqlite3_db_status`, WAL bytes) pushed to obs at M5; keyset paging helpers with chat (M6).
- [x] **4. Platform L3–L4.** `web` (per-host prefix router, `Route` and flags, `respond_*`, body caps, the
      trusted client address, assets with crc32 names and br/gz/identity, robots, sitemap, Bing, IndexNow,
      `/licenses`, `/healthz /livez /readyz /metrics`), `html` (the escaping boundary, layout, NAV, the
      components, `behave`), `client/vanilla`, `theme/full`, `theme/lite`, `app` (`front`, `Host`,
      `boot check serve wait shutdown`, the CLI, the 8 boot checks, `TEST_ROUTES`). *Check:* router,
      escaping and boot-check unit tests, a deliberately bad table tripping checks 1, 3 and 5. Done:
      `platform/escape`'s tests; the router and the bad table in the skeleton's `routes_test.odin`
      (`platform/web` reaches the family collections, so it can't be tested alone), which trips checks
      1, 3 and 5 and nothing else; both profiles' boot checks under `CMD=test`, leak-free. Moved to M2:
      `html.behave` and the `Behaviour` table, with `client/hyperscript`, the family's second member
      (D22's as-built note; the skeleton's markup stays byte for byte until then).
- [x] **5. `minimal`.** Features `home`, `about`, `notes` (both store families, `storetest`); `cmd/minimal`'s
      four files. *Check:* builds with no SQLite library present; ≤ 1.0 MB; the skeleton's exact header
      set; its bundle is `htmx.min.js` byte for byte; the minimal starter's specs pass. Done: no SQLite
      file in its build, the exact header set, the bundle byte for byte, the storetest on both families,
      its boot checks under `CMD=test`. Moved on: the specs run in slice 7's ported suite; the size
      (1.31 MB at `-o:speed`, og.png alone 230 KB) is slice 10's budget work.
- [x] **6. `skeleton`.** Features `contacts` (SQLite store, migrations 0001–0003 with their hashes plus
      `0004_sort_indexes`, group-committed writes over F-13), `dashboard`, `gallery`, `about`;
      `cmd/skeleton`. *Check:* every skeleton URL answers byte for byte as `app/src` does (a route diff,
      intended differences listed: X35's three headers, `x-request-id`); `app/src`'s e2e and k6 smoke
      pass against it. Done: 32 of 33 GET URLs byte for byte (asset hashes and the ping token
      normalised); robots.txt is now derived from the `.Fragment` rows (the same Disallows, single
      routes kept exact); the access log is logfmt (ops.spec follows). The suite: 181 passed in
      chromium, webkit and api; the k6 quick smoke: 10 scenarios, 0 % failed. On Linux (WSL2):
      prepare, the build and both profiles' `CMD=test` boot checks pass; the smoke URLs answer, a
      create round-trips, SIGTERM exits 0 and `/dev/shm` is left clean.
- [x] **7. Retire `app/src`.** The 23 specs ported to `e2e/tests/<f>/` and tagged; global setup through
      `build.sh` and `--features --json`; `load-tests/scenarios/<f>/` and `run.sh --parity`; per-route
      counters and `tests/parity-waivers.txt` (S0.4's three documented exceptions); `run.*`, the
      Dockerfile and `tools/init` through `build.*`; `app/src` deleted. *Check:* 3 engines + `api` green
      on `skeleton`, chromium on `minimal`; route coverage with 0 unexplained waivers. Done: `skeleton`
      190 passed in chromium, webkit and api (10 skipped: the notes and home specs it doesn't mount;
      Firefox waits for CI), `minimal` 58 passed in chromium and api (every skip names a feature it
      lacks); both quick k6 runs `--strict` green; every route of both profiles reached by both suites
      (31/31 and 14/14), so no route waiver; the three `perf` lines are S0.4's. New: `ops.spec` covers
      `/livez`, `/readyz`, `/metrics`, `/licenses`, and load scenarios `ops`, `ping`, `gallery`, `home`,
      `about` cover the routes the skeleton never load-tested. `tools/init` renames every profile's
      brand (tried on a scratch copy: both renamed profiles build); `--minimal` and its overlay are gone,
      the `minimal` profile replaces them. The skeleton image builds through `build.sh` (WSL Docker).
      `run.sh` skips ports another process listens on (WSL's relay held 8192 and answered k6).
- [x] **8. `tools/check`**: `imports`, `profile`, `routes`, `contracts` (and `parity`). *Check:* clean on
      both profiles; a bad fixture trips each. Done: `odin run tools/check -- all parity` exits 0 on the
      repo; `odin test tools/check` runs every check on the repo (clean) and on `testdata/bad` (all 30
      expected problems, nothing else). Feature READMEs carry the D9 prefix tables; `platform/app`'s
      `store:.` import is in PLAN §5.1. Follow-ups: per-host route counters when a profile has two hosts
      (M2's `lab`), and `topics`/`exts` with M2. `parity` reads `bin --routes --json`, the counter files in
      `app/build/coverage/{e2e,load}/<profile>/` and the `route` lines of `tests/parity-waivers.txt`
      (e2e/README and load-tests/README already describe it).
- [x] **9. CI**: `pins`, `check`, `build` ({minimal, skeleton} × 4 OSes, the no-SQLite build), `e2e`,
      `docker`, `linux-ops`, nightly ASan, all through `build.*`. *Check:* a green run (needs the push,
      which waits for Alex's go and the token's `workflow` scope). Written: `pins`, `check`, `build`
      (minimal and skeleton × ubuntu, ubuntu-arm, macOS, Windows; minimal with `NO_SQLITE=1` on ubuntu
      and Windows; size budgets on Windows), `e2e` (`E2E_PROFILE`), `coverage` (k6 quick + `tools/check
      parity`), `docker`; the `setup-odin` action; `check-pins` covers the prepare scripts and the
      odin-http base. Checked locally: the pins, every `check` command, the smoke script on both
      profiles, `NO_SQLITE=1` on Linux; actionlint wasn't run (no local install; the Docker image was
      refused). `linux-ops` and the nightly ASan land with slice 10's drills, which they run. Open
      until the push: the green run itself. Done: run 40383619999 on `7fe60a5`, every job green.
- [x] **10. Drills and budgets.** Crash drills (panic, bounds, div, nil, stack, lock, async, sqlite, hang)
      on both OSes; the fuzz smoke; the shutdown bound with slowloris, half body and idle peers; restart;
      the fd ceiling; `skeleton` ≤ 2.75 MB, idle ≤ 10 MB, boot → `/readyz` ≤ 50 ms. Done: every drill
      passes for both profiles on Windows and on Linux (WSL): pure 500 with 20/20 bystanders, dirty exit
      70 in 0.5–1.2 s, burst, the watchdog's exit 70 in 9.8–10.1 s naming the route and request, 10k
      malformed requests with 0 deaths, the shutdown bound 5.6 s, restart at 0/50/100 ms, the fd ceiling
      (past the cap 503 in 1.4–1.9 ms, 200 after); boot → `/readyz` 26 ms (skeleton) and 11 ms (minimal)
      from the spawn on Windows, 3–5 ms boot_ms on Linux, after moving the ephemeral files to a directory
      of their own (it was 167–181 ms). The ASan build runs clean with `use_sigaltstack=0`. **Budgets,
      decided** (ANSWERS round 7, option (a)): binaries in MiB as CI reads them (skeleton ≤ 2.75 MiB holds
      at 2,881,536 B; minimal raised to ≤ 1.5 MiB) and idle ≤ 6 MB + 0.4 MB per loop; the drills read
      the same figures; the idle budget is measured at 16 loops and gated by the dev PC's drills, while
      CI's Linux runner (about 5 MB above this PC's Linux) reports it (ANSWERS round 8). What was
      measured before the decision (decimal MB as PLAN's 2.42 MB was):
      skeleton 2,876,416 B against 2,750,000 and minimal 1,313,792 B against 1,000,000 (Windows
      `-o:speed`); skeleton idle 11.3 MB working set (Windows) and 12.0 MB RSS (Linux) against 10 MB, at
      16 loops (about 0.37 MB per loop on Linux; 6.0 MB at one loop). Minimal idles at 9.6 MB on both.
      The levers measured: og.png is 230 KB of each binary (a lossless re-encode saves 31 KB; a palette
      one 168 KB but bands the gradients); SQLite's `OMIT_JSON`, `OMIT_DEPRECATED`, `OMIT_UTF16`,
      `OMIT_COMPLETE`, `OMIT_DECLTYPE`, `OMIT_GET_TABLE` and `OMIT_TCL_VARIABLE` save 69 KB of skeleton;
      the JSON CLI is 25 KB. Even with all three skeleton stays about 10 KB over, and minimal reaches
      1.0 MB only without the social card. Also seen: on Linux a client that half-closes right after
      its request often gets no response (the malformed run's "none": 5,560 of 10,000 against 1,250 on
      Windows); no crash, but worth the audit's look.
- [ ] **The M1 audit's open findings** (`docs/audit/M1.md`; M1-01 CRITICAL, M1-06 and M1-08 are
      fixed, and so are the re-read's M1-17 (CRITICAL once confirmed) to M1-23, by the fork's F-16,
      and F-16's re-read's M1-24, M1-25, M1-27, M1-28 and M1-29. M1-26 (a trap in a request a stream's
      end starts, latent until a profile streams) is open, owner M2, with M1-04). MEDIUM, owner M2 (the stream substrate reworks the drain and the deferred paths):
      M1-02 a response send has no deadline (a client that never reads holds the connection);
      M1-03 the watchdog's and the dirty crash's exits log before they arm the exit, so a stalled
      stderr hangs them; M1-04 a crash in a write continuation after `web.resume` leaves its
      connection open; M1-05 at shutdown the writer can post replies into a released loop, and the
      store close has no deadline; M1-07 a reader that can't be opened at runtime exits the process
      (open readers in the loop's init hook, answer 500 at runtime). LOW, owner M2 or later: M1-09
      request identity per thread where requests interleave; M1-10 the drain's log lines aren't
      flushed; M1-11 half-closed clients and resets (likely the Linux "none" count in the drills);
      M1-12 callbacks outside the guard; M1-13 `tools/check locks` and `entry-points`, plain
      `sync.Mutex` in four packages; M1-14 Markdown's quadratic worst case; M1-15 the watchdog's lock
      limit equals busy_timeout; M1-16 unchecked setup results. (`web.count_and_log` and
      `store_sqlite.query_drain`, which had no caller, are removed: the audit's vet triage.)
- [x] **`Audited:` stamps for the packages without a README**: the M1 audit stamps the features,
      `platform/web` and the fork (`UPSTREAM.md`); the other platform packages, the stores and the
      profiles need a README (or `tools/check audit-debt` another place to read stamps). F-14, M1-06's
      and M1-08's fixes are audit debt until an independent re-read. Done: a README with its purpose
      and the M1 stamp (`bf831da`) in each of the 19 platform packages, both store families, the three
      stores and both profiles; the changes since `bf831da` went to an independent re-read
      (`docs/audit/M1.md`, Re-read). `tools/check audit-debt` itself is still to write (PLAN §19.2.1).
- [ ] **The M1 profile's follow-ups** (`docs/audit/M1.md`, Profile; owner M2): the connection arena without its
      mutex (21 lock pairs a request on a one-thread arena) and the header maps reserved up front (3.7 regrowths a
      request), as fork change F-16; one read transaction per page request (`unixShmLock` is 13 % of `pages`); a
      `tools/profile` that makes the spall trace and the perf flame graph repeatable at each milestone exit.
- [x] **`--limits` misses the store's rows** (`DB_PATH`, `SEED`, `MEMMODE`): `store_sqlite.open`
      records them at step 5, after `app.check` answers the CLI at step 4. Record them in an init
      before `app.check` (PLAN §8.5: every row printed, secrets masked). Done: `store_sqlite.init()`
      in the skeleton's `main` before `app.check` (`open` records them itself if a profile skips it).
- [x] **11. The parity gate** on both legs (`skeleton` against 709bc94 and v1.1.1; §18.2 with Q6's and
      Q35's references), into `docs/perf/PARITY-M1.md`; the 01 (A) checklist. Done: PASS on both legs, 20 of
      20 cells each counting §18.2's n = 5 re-runs (Windows `8c4f1a9`, Linux `72590f6`, the box quiet);
      Linux `write@mem` at 0.99 of HEAD on its re-run, under the 0.93 floor Alex accepted (round 6). The
      checklist is 40 of 40. Both legs' drills
      pass at `72590f6`, budgets included (skeleton 2,883,584 B, exactly 2.75 MiB: no headroom left).
- [x] **12. Audit and release prep.** `docs/audit/M1.md` by an agent that didn't write the code, 0 open
      CRITICAL/HIGH; `Audited:` stamps; CLAUDE.md, README and app/README rewritten for the starter (and
      the docs still describing `app/src`: docs/DATA.md, DATA_IMPL.md, STRIP.md, USE_CASES.md's
      `init --minimal`, e2e/PLAN.md, load-tests/PLAN.md — rewritten or removed, PLAN §4);
      CHANGELOG's 2.0.0 entry; then ask Alex about tagging v2.0.0. Done: the audit and two independent
      re-reads (0 open CRITICAL or HIGH; M1-01 and M1-17 fixed), stamps in every package README, the docs
      rewritten, Alex's pass by hand (`docs/testing/M1.md`), and the CHANGELOG cut as 2.0.0; tagged
      v2.0.0 once CI was green on that commit (Alex: "(a) Confirmed. Release 2.0.0.").

## Roadmap to 1.0 — template-ize (Phase F) — ✅ shipped as v1.0.0 (2026-07-01)

Make it trivial to start a new project from. Bounded: mostly docs + one script. **All items below are
done** — the repo is a GitHub template with `tools/init` (+ `--minimal`), a centralized brand, and
the starter docs. Next up is **1.x** (below), headlined by auth.

- [x] **GitHub *template repository*.** Repo set as a Template Repository (the "Use this template"
      button is live); README has the use-template → `init` steps.
- [x] **An `init` / scaffold script** — `tools/init` (an Odin program: the skeleton's own tooling on
      the stack it teaches). Renames the app everywhere it's hardcoded in one pass — the binary
      (`demo`), the `fly.toml` app, the docker image, the apollo-11 service + volume, the `main.odin`
      banner, the test-package names, and the three `brand.odin` constants — across a fixed, audited
      file set. `--wordmark`/`--suffix`/`--repo` override the brand defaults; a confirm prompt +
      name validation guard it. Tested (run → build → revert).
  - [x] `--minimal`: strips the contacts/events demo to a one-page **Notes** starter (the full
        model→repo→service→view→controller stack over one entity), keeping the shell + theme +
        data-layer + harness. Deletes the demo domain/pages/specs/scenarios and drops in minimal
        templates (`tools/init/minimal/`, embedded via `#load`). Tested end-to-end: run → build
        (`-warnings-as-errors`) → curl smoke → **12/12 e2e** → revert.
- [x] **Parameterize the brand / app name** to one place — `app/src/views/brand.odin` holds
      `BRAND_WORDMARK` (the topbar wordmark, inline markup allowed) and `BRAND_SUFFIX` (the
      `<title>` / og:title suffix); `layout` is the only reader. The display name is now a
      two-constant edit instead of literals scattered through the views. The remaining name
      touch-points are outside the views (binary/app name in run/build scripts + `fly.toml` +
      `Dockerfile`, and the `main.odin` startup banner) — the `init` script will tie them together.
- [x] **README as a starter guide**, not a demo tour: use-template → run `init` → keep-vs-strip →
      the `CLAUDE.md` **Recipes** for adding a page / entity / endpoint. (Live in the README's
      "Using this as a starter".)
- [x] **`docs/STRIP.md` — "remove the demo."** Written: the demo-vs-scaffold map + the file-by-file
      seams to delete the contacts/events domain and demo pages, leaving the shell + data layer +
      theming + harness. Cross-links `init --minimal` (the automated version) and the CLAUDE recipes.
- [x] **Re-skin the docs to the skeleton framing** — `USE_CASES.md`'s "flagship (the app's
      direction)" section is now "the worked example" (built, past tense), the retired product-depth
      items (bulk actions, named console) are called out as out-of-scope, and the "read first" banner
      is tightened.

## 1.x — what *every new site* needs (so the skeleton should ship it)

- [ ] **Auth: sessions + CSRF.** The highest-leverage addition for a *starter* — every new site
      reinvents login/sessions/CSRF and it's easy to get wrong. A minimal, in-philosophy
      session-cookie pattern (login page, a protected-route guard, a CSRF token on POST/DELETE),
      held to the "few dependencies" line. Also closes the current CSRF gap on the mutating surface.
- [x] **Per-thread WAL connections** — already **load-justified** (reads scale ~3–4× not ~5× under
      the v1 single shared connection; the `detail` JOIN worst at 1.9×). Ship the right concurrency
      default and re-measure in `load-tests/RESULTS.md`. Done by store v3 in M1 (722cd3e): a read-only
      connection per loop and one writer task (D16), measured in `docs/perf/PARITY.md`.
- [ ] **A second entity as a worked "add your own resource" example** (e.g. teams/companies a
      contact belongs to) — doubles as the multi-resource nav pattern *and* the literal tutorial for
      extending the skeleton. App / e2e / load at par, as always.

## Discoverability — the half that isn't code

The crawler-facing plumbing shipped (canonical/og/JSON-LD, `robots.txt`, `sitemap.xml`, the
`*.fly.dev` → canonical 301). What's left needs an account, not a commit:

- [x] **GitHub repo description, topics and homepage set.** All three were empty, which meant
      nothing on the web linked to the site and the repo carried no keywords — the highest-impact
      item of the lot, since the homepage field is the inbound link that gets *either* property
      crawled in the first place.
- [x] **Google Search Console** — `alexh95.com` verified as a *Domain* property (DNS TXT via
      Cloudflare, which covers every subdomain at once); `/sitemap.xml` submitted and indexing
      requested for `/` and `/about`.
- [ ] **Bing Webmaster Tools** — DNS verification cost two wrong record values and a resolver-cache
      stall, so ownership moved to `/BingSiteAuth.xml`, served from the binary and deterministic on
      deploy. **IndexNow is wired too** (`/<key>.txt`), which covers Bing, Yandex, Seznam and Naver
      from one key. Bing reports the URL as *known but not indexed*; the delivery path is ruled out
      — a bingbot-UA fetch returns 200 with our own `robots.txt` (not a Cloudflare-managed one), TLS
      1.2 negotiates, and Cloudflare's Security Events log shows **no bingbot mitigations at all**
      (that log records only *mitigated* requests, so the absence is the edge clearing itself, not
      evidence of a crawl). Crawl Information reports **no data**, i.e. Bingbot has barely fetched.
      Left: submit `/sitemap.xml` in Bing's console, watch the IndexNow tab for rejected
      submissions, run Site Scan, and re-inspect once Bing has actually crawled.
- [x] **Cloudflare is not blocking the crawl** — SSL/TLS set to **Full (strict)** (`force_https` in
      `fly.toml` plus Flexible mode would be an infinite redirect loop), and Bot Fight Mode left
      **off**: the free tier lacks the verified-bot allowlist that Super Bot Fight Mode has, and a
      challenged crawler fails in a way that reads as "Google is just slow".
- [x] **Add a LICENSE** — **zlib**, chosen for being the most permissive of the common licences
      while still asking that altered versions say so: exactly the ask of a skeleton meant to be
      cloned and rewritten. Deliberately *not* mirrored into the JSON-LD `license` field: the
      minimal templates are shared with forks, and a hardcoded licence URL there would have every
      fork asserting a licence its author never chose.
- [ ] **Distribution beats meta tags.** `r/odinlang`, the Odin Discord, `awesome-odin`, htmx's
      "in the wild" page, a Show HN. Backlinks from those outweigh any on-page tuning for a new
      project; `odin htmx skeleton` itself has ~no search volume. Note the correction to the GitHub
      item above: GitHub applies `rel="nofollow"` to the repo homepage link, so it aids *discovery*
      (which is why Bing knows the URL) but passes no authority — a zero-authority subdomain with no
      followed inbound link is the likeliest reason Bing crawls it and declines to index.

## Stretch goals

- [x] **A `--minimal` scaffold variant** — delivered as `init --minimal` (see Phase F above): a
      fully-wired one-page **Notes** starter you generate on demand (blank-but-wired), instead of a
      second variant to maintain beside the showcase.
- [ ] **Common-need recipes** as documented patterns (file upload, an env/config story, a background
      task) — kept as *recipes*, not framework features, to stay true to the philosophy.
- [ ] **Reporting/export** (CSV of the filtered table) and a focused **a11y pass** (drawer/modal
      focus management, keyboard nav) — cheap reinforcement of the "exemplar" claim.

## Shipped — the foundation the skeleton provides

The patterns + harness a fork inherits. (Was "Now / next"; the initiative below is built.)

- [~] **Vision + flagship + style library** (this initiative). Anchored by
      [`PHILOSOPHY.md`](PHILOSOPHY.md), [`docs/USE_CASES.md`](docs/USE_CASES.md),
      [`docs/DATA.md`](docs/DATA.md). Keep app/e2e/load-tests **at par** at every phase.
  - [x] **Phase A — direction docs.** PHILOSOPHY (vision), USE_CASES (sweet spot + flagship
        direction), DATA (datasource future-proofing). Wired into README/CLAUDE.
  - [x] **Phase B — theming foundation.** `data-style` × `data-scheme` on `<html>` (SSR default
        `modern`/`midnight`, restored pre-paint from localStorage); token contract; stateless
        `<details>` picker in the topbar (vanilla JS apply/persist, no endpoint → load par).
        **Modern** is the reference style with four schemes (Midnight/Daylight/Nebula/Aurora).
        e2e: picker switch + persist. Build clean, 32/32 e2e.
  - [x] **Phase C — the styles.** All five shipped — Skeuomorphic, Terminal/CRT, Brutalist,
        Editorial/Paper, Arcade (video-game) — each a pure `[data-style]` block with multiple
        schemes, every style incl. a light option. Plus cache-busting (`?v=hash`) so style edits
        show without a hard refresh. Library: 6 styles, 23 schemes.
    - [x] Turned `/components` into a live style/scheme **showroom**: a catalog of all 6 styles ×
          23 schemes at the top of the page; click any swatch to jump to that exact style+scheme and
          the whole page (components below) re-skins live. e2e covers it; no new server surface.
  - [~] **Phase D — flagship app.** Evolve the sampler into one cohesive internal admin console.
        Each new endpoint gets e2e **and** load scenarios in the same change.
    - [x] **Contact detail drilldown** — click a row's name → `GET /contacts/:id` opens a drawer
          with the full record, a derived **activity trail**, and **related** contacts (same role,
          each a one-click jump). Read-only for now. e2e + `detail.js` load scenario added.
    - [x] Inline edit + actions in the detail drawer (edit fields, cycle, delete — all swapped in
          place; edits OOB-refresh the table row; `repo_update` persists score). e2e + load at par.
          Phase-D review fix: an invalid drawer edit now surfaces an OOB error toast instead of
          silently reverting.
      - Known limitation: an in-drawer edit/cycle OOB-refreshes the row *in place*, so a
        filtered/sorted table can briefly show a row that no longer matches until the next
        interaction. A deeper fix would thread the table's q/status/sort into the drawer and
        re-render the whole region; acceptable for the POC.
    - [~] Richer table.
      - [x] Saved/quick **status filters** (chips: All/Active/Invited/Disabled; compose with search +
            sort + paginate via a threaded `status` arg).
      - [-] Bulk actions (select rows → set status / delete) — **out of scope as a goal** (skeleton:
            app-specific; a copier would strip it). Keep only as an example extension if ever wanted.
    - [x] Coherent product frame — the dashboard stat cards drill into the filtered/sorted data view
          (overview → tool). A *named* console identity + deeper nav IA is **out of scope** for a
          skeleton: the fork names and structures its own console.
  - [x] **Phase E — parity + polish sweep.** Parity closed: Phase D endpoints all have e2e + load
        (detail.js, the create→edit→delete write path, the new **list.js** for `GET /contacts`
        filter/sort); CHANGELOG/docs current; the Phase D review fix landed. Also wrote the
        **Odin data-layer implementation plan** ([`docs/DATA_IMPL.md`](docs/DATA_IMPL.md)).
        Phase E review pass swept the whole Phase D+E surface and caught a reflected
        HTML-injection via the `sort` query param (unescaped reflection into the table's `hx-get`
        attributes) — fixed by `url_encode`ing `sort` everywhere, pinned by an e2e regression test.
- [x] **Data layer — persistent SQLite** (replaces the in-memory POC).
  - [x] Implemented per [`docs/DATA_IMPL.md`](docs/DATA_IMPL.md): amalgamation binding
        (`src/sqlite/`), the seven `repo_*` over SQLite, `prepare.*` fetch+compile (pinned + SHA-256),
        `DB_PATH` (`:memory:` default / file persists), WAL + migrations + `schema_version`. Contract
        unchanged; e2e + load pass untouched. apollo-11 persists to a named volume; Fly stays
        `:memory:` pending a volume (documented in `fly.toml`).
  - [x] **Repository cleanup + split.** Split into a **common** part (`repo.odin` — connection
        lifecycle incl. `repo_close`, the migration runner, the shared `exec`/`prep`/`bind`/`clone`/
        `scalar` helpers + the lock) and **per-entity** files (`contacts.odin`, `events.odin`), each
        owning its statements + procs. Helpers grouped, error handling documented (fatal at boot,
        best-effort per request), `repo_close` wired via `defer` in main.
  - [x] **Multi-table case — events between contacts.** `events(actor_id, target_id → contacts,
        ON DELETE CASCADE, kind, at, note)` (`migrations/0002_events.sql`). The detail drawer's
        activity feed is now **real**: `event_timeline` JOINs back to contacts to resolve the other
        party, each a one-click jump (replaces the faked `service_activity`). Deleting a contact
        cascades its interactions. End-to-end at par: model + repo + service + view + e2e (incl. a
        cascade test; **42 e2e**) + load (`detail.js` now exercises the JOIN). Load re-measured:
        reads scale ~3–4× under the single-connection exclusive lock (`detail` JOIN worst at 1.9×) —
        see `load-tests/RESULTS.md`.
  - [x] **Per-thread WAL connections** — moved to the **1.x roadmap** above (load-justified); done by store v3.
- [~] **Set up infrastructure** per [`infra/PLAN.md`](infra/PLAN.md). Code + config landed;
      what's left are operator actions on Fly/GitHub/Cloudflare (no repo changes).
  - [x] Prereq code change: `app/main.odin` reads `PORT` and binds `0.0.0.0` on `BIND_ALL`
        (loopback stays the local default).
  - [x] Pin odin-http as a submodule (`app/odin-http` @ `112c49b`) for reproducible builds.
  - [x] `Dockerfile` + `.dockerignore` + `fly.toml`; `.github/workflows/ci.yml` (build,
        smoke, deploy-on-`master`).
  - [x] Operator: created the Fly app + `FLY_API_TOKEN` secret; CI deploys on green push and the app
        is live (Fly `fra`, Cloudflare-fronted at `odin-htmx.alexh95.com`).
  - [x] Operator: front the Fly app with a **proxied Cloudflare record** (`fly certs add` + the
        `_fly-ownership` TXT and `_acme-challenge` CNAME for DNS-01 validation, CF SSL Full-strict).
        This was also a latency fix: Fly's IPv6 anycast mis-routed an EU ISP to the `jnb`
        (Johannesburg) edge (~785 ms TTFB) while IPv4 hit `ams` (~160 ms); routing through
        Cloudflare's edge bypasses Fly's anycast and serves both v4/v6 in **~105 ms** with
        `/static` edge-cached. The Fly region was also moved `iad`→`fra` so the origin is nearby.
  - [ ] Stand up the dedicated load-test environment when load-tests are implemented.
- [x] Implement the e2e suite per [`e2e/PLAN.md`](e2e/PLAN.md) — Playwright, 31 tests incl. the
      three regressions; wired into CI as a gating job. It surfaced (and we fixed) the `fmt`
      brace bug in the page `<head>` and the OOB-toast wrapper.
- [x] Implement the load-tests per [`load-tests/PLAN.md`](load-tests/PLAN.md) — k6 scenarios
      (static/pages/search/api/write/mixed), a `run.sh`/`run.bat` sweep driver, and
      `RESULTS.md`. Single-thread baseline captured.
  - [x] Headline follow-up: guarded the store with an `sync.RW_Mutex` and set `thread_count`
        to the core count (`THREADS` env overrides). Before/after in `RESULTS.md`: reads scale
        **~5×** (1→8 threads), writes ~1.8× (exclusive-lock-bound, as predicted), and the
        500-VU overload failures (13–34%) drop to **0%**. Also ran it against prod (Fly).
  - [x] Two-host absolute numbers: deployed to the apollo-11 home server
        (then `deploy/apollo-11`, now the generic [`deploy/docker-host`](deploy/docker-host)), k6 on
        the workstation over a 1 GbE LAN. Found the
        wire ceiling (static/pages saturate ~912 Mbit vs 2.4 GB/s loopback) and the reverse-proxy
        cost (~12× for NPM+TLS on the shared box). Surfaced the io_uring-vs-Docker-seccomp gotcha.
        Results in `RESULTS.md`. (Further: a generator *outside* the LAN for the true external path.)
- [~] **Sync gate:** every endpoint now has both an e2e and a load scenario for its *class*
      (static, page, search, api, write). `/healthz` is hit by the run driver's readiness
      probe rather than a dedicated scenario; add one if it ever does real work.

## Backlog

- [x] Data table: the actions column overflowed into horizontal scroll on narrow viewports. Fixed
      in the mobile pass — below 560px the table folds email/role/engagement into the detail drawer
      (name · status · actions remain); the topbar was the larger culprit (page-wide scroll), also
      fixed. No horizontal overflow 320–1280px, pinned by e2e.
- [x] Pin htmx to an exact version in `prepare.*` (was the floating `@2`) for reproducible builds —
      pinned to **4.0.0-beta5** with a SHA-256 check (same discipline as ODIN_VERSION / SQLite), and
      migrated htmx 2 → 4 (renamed config keys `defaultSwap`/`transitions`, `htmx:after:process`
      re-init, the form auto-reset moved to `app.js` over `ctx.sourceElement`).
- [ ] Optional: a build-flag-gated `/__reset` endpoint to reseed the store (useful for load
      tests; must never ship in a normal build). Tie to `load-tests/PLAN.md`.
- [ ] Optional: `-o:speed` build path for benchmarking vs. the default showcase build.
- [x] CI guard for `init --minimal` rot — a `minimal` CI job strips a fresh checkout to the Notes
      starter and runs its e2e (global-setup builds it `-warnings-as-errors`, so one job catches
      compile- **and** runtime-rot, and exercises the rename path too). Chromium only; gates deploy.
      Keeps the `tools/init/minimal/` templates honest as the skeleton evolves.
- [ ] `/forms` email validates one value twice: `keyup changed delay:400ms` checks it as you type,
      then `change` re-sends it on blur — a redundant request, and the `.msg` fade-up replays. Since
      #8's fix it no longer costs a click, only the round-trip. htmx 4's `changed` modifier keeps its
      last value *per trigger*, so `change changed` can't dedupe against the keyup; a lone
      `input changed delay:400ms` would (it also covers a mouse paste, which keyup misses). Keep the
      e2e's click-during-a-swap case exercising a real swap if you change it.
- [ ] Optional: crossfade back/forward too. Since #8, only the boosted links opt into a view
      transition, and htmx 4 takes a history restore's from the global `transitions` flag alone — so
      it would take one `htmx:config:request` listener in `app.js` setting `ctx.transition` on
      `HX-History-Restore-Request` requests. It reopens a (brief) dead-click window each time.
- [ ] Move the CI `e2e` + `minimal` containers off `mcr.microsoft.com/playwright:v*-jammy` before
      Ubuntu 22.04 leaves standard support (2027). `noble` is the conservative step. It changes the
      jobs' apt `clang` (14 → 18), which compiles SQLite and links Odin, so land it alone and not
      inside a dependency sweep. Same rule as the Debian base in the `Dockerfile`. (The apt
      mirror outages of 2026-10-07 are another reason; `apt-install.sh`'s HTTPS failover covers them
      meanwhile.)

### Left over from the 2026-10-07 review (tracker #12)
What the fixes for #13–#44 didn't finish, by area. Each names its issue where one exists. The last open issues
(#12, #14, #23, #29, #35, #40, #42, #43, #44) were swept against v2.1.0 and closed on 2026-10-28, each with a note;
what still applies lives here.
- [x] **`scale`'s budget predates store v3** (#14). Done in M3: 70/97 ms on the dev PC, 198/300 ms on CI, bound 1 s / 2 s. `load-tests/scenarios/contacts/scale.js` still allows p95
      3 s / p99 6 s and says every request queues on one exclusive lock; reads have had a connection per loop
      since M1. Re-measure at 20 VUs over 20k rows, tighten `SCALE_P95`/`SCALE_P99`, fix the comment. (Search's
      `contains_ci` scan and the dashboard's `GROUP BY` stay: PLAN §11.8.)
- [ ] **`minimal` still carries the skeleton's CSS and JS** (#29). The lite bundle is about 45 KB against the
      skeleton's 72 KB, but `app/platform/static/app.css` still holds the skeleton's component styles (about 110
      of 187 classes unused by `minimal`, by a rough grep), and minimal's `app.js` is the skeleton's file.
- [ ] **Test-suite gaps** (#42): order-dependent "first row" tests; the toast
      test races a 3.6 s timer; occasional Firefox-only flakes in `search.spec` and the
      `components.spec` drawer under local parallel load. The concurrent-cycle test documents the
      single-UPDATE contract but doesn't reproduce the old race.
- [ ] **Supply chain** (#44): pin `debian:trixie-slim`, the Playwright image and the actions by
      digest (the proxy and Autobahn images and the flyctl action already are); add Dependabot or Renovate.
      Required checks: the only ruleset requires linear history and auto-merge is off, so nothing merges early
      today; a required-checks rule would also block the direct pushes to `master` this repo takes, so decide
      it together with how pushes land.
- [ ] **CI cost** (#43): document the per-run minutes for private forks in the README. The green master run
      40648389468 was 45 jobs, about 82 job-minutes and 13 minutes of wall time (about 159 billed if private).
- [ ] **CI apt time** (#43): `setup-odin` apt-installs clang, binutils, unzip and brotli in every Linux job,
      15–79 s each in run 40648389468 with Odin cached. Cache the packages or bake them into an image; settle
      it with the `noble` move (Backlog).
- [ ] **Dev loop**: optionally run e2e against the `-o:speed` binary (#37); a watch loop for local dev (#35),
      now slower since a CSS or JS edit needs `prepare` and a build. PLAN §2.5 names `tools/watch`, but no
      milestone builds it. (Origin gzip, #23, is superseded: assets are precompressed and HTML compression is
      the proxy's, PLAN §20.4, D41; request ids, #20, are in the access log.)
- [ ] **Auth will need**: a session CSRF token and `SameSite=Lax` cookies on top of today's
      `Sec-Fetch-Site`/`Origin` guard (#18).
- [ ] **A new project inherits the template's docs** (#29). Compose-mode init keeps `CLAUDE.md`, `app/README.md`,
      `docs/` (PLAN, BRIEF, USE_CASES, design, spikes, perf, audit), `e2e/PLAN.md`, `load-tests/RESULTS.md` and
      `lib/config.js`'s `TERMS`; it drops only `docs/catalog.json` (`tools/init/project.odin:49`), and PLAN §7.4
      has no step for them. Decide per file: delete, a starter stub, or keep.
- [x] **init and M3's apollo files** (#44, done in M3's slice 5): when M3 adds `deploy/compose.yaml` and `deploy/promote.ps1`, add them
      to what `new_project` removes beside `deploy/Caddyfile` (`tools/init/project.odin:47-49`), so a project
      doesn't inherit the starter's own hosting again.
- [ ] **Upstream (odin-http)**: its shared `Date`-header buffer is rewritten every second while
      other threads read it. k6 saw 2 malformed `Date:` headers with NUL bytes in about 800k
      requests. Fixed in the vendored fork (F-11, `app/vendor/odin-http/UPSTREAM.md`); still to
      report upstream.
- [ ] **Upstream (odin-http): a negative `Content-Length` aborts the process.** `_body_length`
      (`body.odin`) checks only the upper bound, so `-5` reaches `assert(n >= 0)` in
      `scan_num_bytes`. `front` refuses it for every request it sees, but odin-http answers
      `OPTIONS *` itself and then drains the body, so `OPTIONS * HTTP/1.1` with `Content-Length: -5`
      still kills the server. Report it upstream with the chunked path's `size < 0` guard (#117) as
      the fix. Fixed in the vendored fork (F-6, `app/vendor/odin-http/UPSTREAM.md`); the issue is
      drafted, still to post upstream.
- [ ] **Upstream (Odin `core:image`, `core:nbio`, Alex's go to file).** The JPEG reader: a Huffman table's counts wrap a
      `u8`, a frame's sampling factors and a missing Y reach an unchecked scan, and JFXX walks past its segment
      (`platform/jpeg`'s README lists each; drop that copy once fixed). PNG's inflate doesn't stop at the declared size
      (`app/features/uploads/testdata/endless.png`). core:nbio's Linux tick waits while work is queued (F-23).
- [ ] **Upstream (_hyperscript 0.9.94): its bootstrap's fetch has no catch.** At load it fetches every
      `<script type="text/hyperscript" src>` (`Promise.all(… await fetch(r.src) …)`, the bundle's line 22), and a
      navigation that cuts the fetch rejects it in Firefox (AbortError, or a TypeError NetworkError; Chromium stays
      silent), so the page logs an unhandled rejection. The suite skips exactly those two from that file in
      `e2e/helpers/members.ts` (`ae982e8`). Filing it is Alex's go.

## Done

- [x] Initial showcase app (dashboard, components, forms, data + CRUD, search, JSON API).
- [x] Bug fixes: modal outside-click, `/forms` field reset, static slider fill.
- [x] Restructure into `app/` + `e2e/` + `load-tests/`; project docs (`CLAUDE.md`, this file,
      `CHANGELOG.md`).
- [x] git init + first commit; adopted Conventional Commits; infrastructure plan
      (`infra/PLAN.md`).
