# M7 bot budgets

**Budgets:** PLAN §18.4's bot row, and M7's exit gate · **Date:** 2026-11-05 · **Candidate:** `streams`, `-o:speed`, master after
`6dd7c83` · **Tool:** the `botmock` drill (`tools/drills/drills.mjs`), `e2e/tests/bot/llama.spec.ts`, `tools/fakellama/suite` · **Box:**
the dev PC on Windows, server and clients sharing it. CI's Linux drills job for `streams` holds the same budget on every push.

## Results

| Budget | Measured | Verdict |
|---|---|---|
| 1000 concurrent mock generations ≤ 1 core | 511 ms of CPU a second | met |
| and ≤ +30 MB | +11.9 MB over the idle server | met |
| Stop ≤ 100 ms, mock | timed in the page, best of up to three: under 100 ms on both deliveries | met |
| Stop ≤ 100 ms, llama | timed in the page against fakellama, best of up to three; under 100 ms at the binding as well | met |
| The queue, `BOT_CONCURRENCY=1` | the second answer says "Queued (#1)" and runs when the first stops; fakellama's peak is 1 | met |

## How the mock budget is measured

1000 guests' answers over SSE, each on a stream of its own, at `BOT_DELAY_MS=50`: 20 tokens a second, the budget's rate. A new
answer starts as one ends, so there are 1000 at once for the whole 10 s window, and the run read 16,574 frames/s and 553
answers/s, with 0 failed. A mock answer is shorter than the budget's 200 tokens, and that changes nothing here: the cost is
per token, and a token's rate is what's held. CPU is the server's own (`cpuMs`), not the clients'.

## What isn't measured yet

Tokens a second on the real server. §14.3's 40–60 tokens/s is an estimate until the server's own `timings` are read on apollo's GPU, which is
Alex's step after the promote.
