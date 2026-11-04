# M6 chat budgets

**Budgets:** PLAN §18.4 and D38's chat rows, and M6 slice 10 · **Date:** 2026-11-04 · **Candidate:** `full`, `-o:speed`,
master after `84ff461` with this slice's fixes · **Tool:** `sh tools/drills/chat-budget.sh` (`tools/writerbench`,
`tools/streamload fanout --room`, `tools/drills/chat-latency.mjs`) · **Box:** the dev PC, in
CI's Playwright image under WSL2, 4 pinned cores, the server and clients sharing them

## Results

| Budget | Measured | Verdict |
|---|---|---|
| WS, 1000 sockets × 20 messages delivered ≤ 2 s | 20,000 of 20,000 through a real room, each POSTed as a composer posts it; p50 6.2, p95 15.2, p99 17.5 ms | met |
| Writer ≥ 10k msgs/s at a retention cap, a real post | 12,265 msgs/s at a 10,000-message cap; about 21,000 with no cap | met |
| Writer ≥ 3× autocommit | 12,265 against 3,062 msgs/s on one commit each: 4.0× | met |
| 1000 msgs/s offered, p95 ≤ 50 ms | 10,000 of 10,000 answered; p50 0.19, p95 8.9, p99 13.7 ms | met |
| The old row: writer ≥ 50k msgs/s batched on a file WAL | the same 12,265 msgs/s | **restated**, see below |
| Send to another member's DOM p95 ≤ 50 ms, LAN through NPM | 60 of 60 landed over WS on Houston at v2.5.0; p50 5.5, p95 9.3, max 11.7 ms (direct: p95 5.3 ms over WS, 11.3 ms over SSE) | met |
| ~~A worst decode fits Houston's 512 MiB~~ | peak RSS 246.8 MiB during a hold of 1000 sockets | **superseded**: the server no longer decodes (PLAN §17.6) |

## The 50k row, restated

It came from early measurements of a bare insert (`12 §3.1`: 131–163k at 100 a transaction). A post today is more: a
savepoint, a room version, an FTS5 insert through a trigger and, at its room's cap, a trim that deletes through FTS5 too.
Chat's own limit is 5 messages in 10 s per member, so nothing here is near either number, and nothing was tuned to chase
it. Planning restated §18.4 and D38 on 2026-11-04 in three parts on a real post, the throughput floor kept so that the
1000 msgs/s bar alone can't hide a large regression.

## What this slice found

**A message over a socket on `full` waited for a timer.** The first direct run read 103 ms; a bare socket read 700 ms,
always landing on a second boundary, while `streams` read 0.6 ms. The writer's answer comes back from another thread, and
its callback queues the hub's drain; F-23 looked only at the loop's own queue before waiting, so the drain sat until the
next timer or any other event. HTTP posts hid it, since their response wakes the loop. Fixed in F-23: work posted from
another thread counts, with a test that takes 100 ms without the fix. A socket's send to echo is now 0.9 ms.

## Method

- **Writer:** chat's own store path, on a file with the FTS triggers and a retention cap; `alone` awaits each answer,
  `queued` keeps 1024 in flight, `paced` offers 1000 a second for 10 s.
- **Fan-out:** 1000 sockets of one member in the lobby, 20 messages posted by others at once (a member may post 5 in 10 s).
- **Send to DOM:** one reader, 12 senders of 5 messages each; a stamp in the page at submit, a MutationObserver in the
  reader's. One browser, so one clock.
- **Send to DOM through NPM** (2026-11-04): Alex's machine on the LAN, against the live site through NPM, two accounts in
  one room: `node tools/drills/chat-latency.mjs <Houston URL> --login <reader>:<pw>,<sender>:<pw> --room <slug> --count 60`.
  One sender keeps to the post limit and deletes each message once it lands; Houston's log shows the 60 deletes all 200,
  with no warning or error.
- **Poll** isn't in the DOM row: its latency is its interval.
