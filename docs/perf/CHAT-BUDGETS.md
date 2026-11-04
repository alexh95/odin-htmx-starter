# M6 chat budgets

**Budgets:** PLAN §18.4 and D38's chat rows, and M6 slice 10 · **Date:** 2026-11-04 · **Candidate:** `full`, `-o:speed`,
master after `84ff461` with this slice's fixes · **Tool:** `sh tools/drills/chat-budget.sh` (`tools/writerbench`,
`tools/streamload fanout --room`, `tools/drills/chat-latency.mjs`, `tools/drills/bomb-png.mjs`) · **Box:** the dev PC, in
CI's Playwright image under WSL2, 4 pinned cores, the server and clients sharing them

## Results

| Budget | Measured | Verdict |
|---|---|---|
| WS, 1000 sockets × 20 messages delivered ≤ 2 s | 20,000 of 20,000 through a real room, each POSTed as a composer posts it; p50 6.2, p95 15.2, p99 17.5 ms | met |
| Writer ≥ 3× autocommit | 12,265 against 3,062 msgs/s on one commit each: 4.0× | met |
| 1000 msgs/s offered | 10,000 of 10,000 answered; p50 0.19, p95 8.9, p99 13.7 ms | met |
| Writer ≥ 50k msgs/s batched on a file WAL (§18.4) | 12,265 msgs/s at a 10,000-message cap; about 21,000 with no cap | **not met**, see below |
| Send to another member's DOM p95 ≤ 50 ms, LAN through NPM | direct: p95 5.3 ms over WS, 11.3 ms over SSE, in a real browser | **not yet measured through NPM** |
| A worst decode fits Houston's 512 MiB | peak RSS 246.8 MiB during a hold of 1000 sockets; the cap allows 314 MiB at most | met |

## The 50k row

It came from early measurements of a bare insert (`12 §3.1`: 131–163k at 100 a transaction). A post today is more: a
savepoint, a room version, an FTS5 insert through a trigger and, at its room's cap, a trim that deletes through FTS5 too.
Chat's own limit is 5 messages in 10 s per member, so nothing here is near either number. §18.4's row wants restating
against a real post; nothing was tuned to chase it.

## What this slice found

**A message over a socket on `full` waited for a timer.** The first direct run read 103 ms; a bare socket read 700 ms,
always landing on a second boundary, while `streams` read 0.6 ms. The writer's answer comes back from another thread, and
its callback queues the hub's drain; F-23 looked only at the loop's own queue before waiting, so the drain sat until the
next timer or any other event. HTTP posts hid it, since their response wakes the loop. Fixed in F-23: work posted from
another thread counts, with a test that takes 100 ms without the fix. A socket's send to echo is now 0.9 ms.

## The decode cap

`core:image`'s decoders hold far more than their pixels: measured, in bytes a pixel, about 8.6 for JPEG, 11.4 for an RGB
PNG, 15 for RGBA and 31 for 16-bit RGBA. So under the 256 MiB cap the real limits are about 31 MP for a JPEG, 23 MP for
an RGB PNG, 17 MP RGBA and 8.8 MP at 16 bits, all below §17.6's 40 MP. A 22 MP RGB PNG decoded in 0.26 s at the cap's edge.

## Method

- **Writer:** chat's own store path, on a file with the FTS triggers and a retention cap; `alone` awaits each answer,
  `queued` keeps 1024 in flight, `paced` offers 1000 a second for 10 s.
- **Fan-out:** 1000 sockets of one member in the lobby, 20 messages posted by others at once (a member may post 5 in 10 s).
- **Send to DOM:** one reader, 12 senders of 5 messages each; a stamp in the page at submit, a MutationObserver in the
  reader's. One browser, so one clock.
- **Worst decode:** two finishes during the 1000-socket hold: 4400² at 16 bits, past the cap and refused, then 5000 × 4400
  RGB.
- **Poll** isn't in the DOM row: its latency is its interval.
