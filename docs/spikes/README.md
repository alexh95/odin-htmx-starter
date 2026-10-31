# M0 spikes

Each spike closes one unverified item before M1 builds on it (PLAN §22.2; D44). Each writes `S0.<n>.md` here with its
criterion, result and decision; a failure changes the design (PLAN or DECISIONS) before M1 starts. Spike code that M1
or M2 keeps (the fork's changes, the stream prototype, `tools/bundle`, `tools/baseline`) is costed once, here (PLAN
§22.1).

| Spike | Closes | Record |
|---|---|---|
| S0.1 Baseline capture | the reference and its noise band | [S0.1.md](S0.1.md) |
| S0.2 The fork under the skeleton's k6 | the fork keeps the request-path throughput | [S0.2.md](S0.2.md) |
| S0.3 htmx extensions in real browsers against Odin streams | hx-sse, hx-ws and hx-multipart never ran in a browser against Odin | [S0.3.md](S0.3.md) |
| S0.4 `:memory:` parity | D17's candidates | [S0.4.md](S0.4.md) |
| S0.5 Workers and argon2id | the login flow off the loops | [S0.5.md](S0.5.md) |
| S0.6 The guard in the fork + watchdog | the guard's integration | [S0.6.md](S0.6.md) |
| S0.7 Drain and restart | the unbounded waits at shutdown | [S0.7.md](S0.7.md) |
| S0.8 Caddy and streams | whether Caddy's `encode` delays events | [S0.8.md](S0.8.md) |
| S0.9 Linux leg on the dev PC | Odin in WSL2, a TSan build | [S0.9.md](S0.9.md) |
| S0.10 Bundles | `tools/bundle` and the bundle race | [S0.10.md](S0.10.md) |
| S0.11 Tuned SQLite | S10's flags across OSes | [S0.11.md](S0.11.md) |
| S0.12 apollo facts | the host's numbers | [S0.12.md](S0.12.md) |
| M6.1 hx-ws's errors | what Auto falls back on: closes, not errors | [M6.1.md](M6.1.md) |

## The Fly witness at M0

PLAN §20.6's cost check, and the M0 exit gate's "`x-version: 6d37506` on the Fly witness and its cost recorded":

| Check (2026-10-26) | Result |
|---|---|
| `curl -sI https://odin-htmx.alexh95.com/` | `x-version: 6d37506` (v1.2.1), deployed by the re-run of 6d37506's CI (run 40229122156, attempt 2: the chromium e2e job and then `Deploy (Fly.io)` succeeded) |
| `odin-htmx-skeleton.fly.dev` | 301 to `https://odin-htmx.alexh95.com/`, `x-version: 6d37506`, served from fra |
| addresses | a shared IPv4 (no charge) and an IPv6 (no charge); no dedicated IPv4 |
| machine (from `fly.toml`) | one `shared-cpu-1x` with 256 MB in fra, `min_machines_running = 1` |
| monthly cost | **about $2.50**: Fly's price list (read 2026-10-26) gives $2.19 per 30 days for that size in its cheapest regions, and fra costs about 15 % more (its 1 GB price is $7.73 against $6.70); EU egress is $0.02/GB, and the witness's traffic is small (26 views in 14 days, 10 §0) |
| over $10/month? | no: no warning to Alex |

The figure is an estimate from the configuration and the public price list: `flyctl` is not logged in on the dev PC,
so the invoice wasn't read. A second machine that `fly launch` may have created stays stopped between requests and
costs its root filesystem only ($0.15/GB/month). Alex can confirm the amount on Fly's billing page; the next check is
at the M3 exit (§20.6).

## How a record reads

```
# S0.<n> <title>

**Closes:** <from PLAN §22.2> · **Pass criterion:** <verbatim from PLAN §22.2>
**Result:** PASS | FAIL | PASS with a change — one sentence · **Date:** YYYY-MM-DD · **Commit:** <the repo commit measured>

## Decision
What the plan does now, and whether PLAN.md or DECISIONS.md changed (which sections).

## Method
Box, toolchain, builds, commands; enough to re-run it.

## Results
Tables of the numbers, each with its unit and n.

## Caveats
What this does not show, and what is still UNVERIFIED (and which gate settles it).
```

Numbers come from runs made for the record, on the box named in Method. A claim with no run behind it is marked
**UNVERIFIED (…)** with the gate that settles it, as in the plan.

## Public-repo hygiene

The repo is public. Records name no LAN address, host path, user name, apollo hardware or service: they use the
placeholders of PLAN §2 (`<APOLLO_LAN_IP>`, `<APOLLO_CPU>`, `<APOLLO_DATA_DIR>` …), whose values live in the git-ignored
`docs/private/SITE.md`. Before a record is committed, SITE.md's hygiene grep must print nothing for it.
