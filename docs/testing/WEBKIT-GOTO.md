# WebKit's `page.goto: WebKit encountered an internal error`

A time-boxed chase, about 2 hours, on 2026-11-05 (planning's call): the error shows in most CI runs on Linux WebKit, and has since at
least 2026-11-01, at any page, nearly always passing on its retry. **No root cause.** It is narrowed, and nothing here changed
the server or added a retry.

## What is established

- **The message is WebKit's.** Its stderr says `WebKit encountered an internal error. This is a WebKit bug.`, from
  `WebLoaderStrategy::internallyFailedLoadTimerFired`. Playwright only passes it on.
- **A browser process dies of heap corruption just before.** The log has `malloc_consolidate(): unaligned fastbin chunk detected`, at
  times `corrupted` lines and `libsoup-CRITICAL: soup_session_feature_request_queued`. A later load is what fails. Of 16 suite rounds
  in CI's image, two had the abort, and the one round with the `goto` error was one of those two. Both CI jobs read that day had one.
- **That it is the network process is inferred**: libsoup lives there and loads fail after it, but no log names the process.
- **Lines of that error without a failed `goto` are mostly expected.** About 10 a run come from `chat.spec`'s "offline a while", whose
  own requests fail while it is offline, so a count of the message alone says nothing.

## Reproducing it

A loop on a browser of its own, four at once in CI's Playwright image, `streams`' server: a context signs in with a nickname, opens
a page, waits 200–500 ms, closes, then a fresh context loads `/about`. About 3 % of rounds fail. Counts are of failed `goto`s; a
run's heap aborts are per mode group.

| Round | Rounds | Failed `goto` | Heap aborts |
|---|---:|---:|---:|
| Member, a room, mixed transports, closed abruptly | 146 | 2 | 5, with the next row |
| The same, `setOffline` with its streams open | 135 | 2 | |
| Member, a room over ws | 114 | 4 | 8, with the next three |
| over sse | 66 | 1 | |
| over poll | 113 | 3 | |
| over multipart | 123 | **0** | |
| Member, ws and poll, `about:blank` before the close | 232 | 5 | 8 |
| Member, `/about` only | 153 | 2 | 7, with the next row |
| Member, `/notify` | 119 | 3 | |
| Guest, `/about`, four streamed POSTs, closed abruptly or after `about:blank` | 393 | **0** | 0 |
| Guest, `/about`, `setOffline`, then a fresh context | 58 | **0** | 0 |

## Ruled out, as far as these go

- **`setOffline` leaking to a later context:** no failure in 58 rounds alone, and rounds without it fail as often.
- **A transport:** ws, sse and poll all fail, and so does `/about` with no room. Multipart's 0 of 123 is about 3 % likely by chance, so it isn't proven clean.
- **Closing a context with streams open:** leaving the page first didn't help.
- **WebKit with any server:** a bare Node server shows 0 failures and 0 aborts in about 260 rounds of each of a `Set-Cookie`, none, a form
  POST answered 303 with a cookie, the same with none, a held-open stream under a `fetch` reader, under `EventSource`, and a cookie with
  a stream together.

## What is left

Every failing round signed in on this server, and no guest or bare-server round failed. So something about this server's sign-in or a
member's pages reaches the bug, and that is unexplained: not a cookie alone, not a 303, not a stream alone. Next, if anyone
takes it up: capture `POST /login` and the member page's real responses, headers and bodies, and replay them from the bare server,
one difference at a time. The abort is in the browser whatever triggers it. Inferred, unverified: Safari has a different network stack, so
members on it wouldn't meet this.

The specs stay as they are, on Playwright's one retry, and it can still fail a job when both attempts lose (`ce6a8ce`).
