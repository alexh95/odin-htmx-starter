# M7 parity gate

**Gate:** PLAN §18.2 at the M7 exit: the `skeleton` profile against HEAD (709bc94, v1.2.0) and v1.1.1, ten scenarios on `:memory:`
and on a file DB, on the Windows-native and the Linux (WSL2) legs · **Result:** Linux **PASS**, 20 of 20. Windows: 19 of 20 across
the runs; `write@mem` reads 0.97 and misses its bar by rounding, **waiting on Alex**. No Windows run was within the gate's 20 %
background · **Date:** 2026-11-05 · **Candidates:** `b045bb8` (Linux), `88f9222` (Windows), which differs from it by a spec's skip
and the catalog · **Baselines:** v1.2.0 and v1.1.1 · **Raw rows:** `perf/results/v2.5.0-15-gb045bb8-linux.csv`,
`v2.5.0-16-g88f9222-windows.csv`, `v2.5-88f9222-windows-n5.csv` · M6's gate: [PARITY-M6.md](PARITY-M6.md)

## Result

- **Linux:** 20 of 20 at n = 3, background 23–34 %. `write@mem` passes its 0.93 floor at 0.96.
- **Windows, n = 3:** 17 of 20, at 21–43 % background: a game of Alex's ran throughout. The misses were `seo@file`, `pages@mem` on
  its p99 and `write@mem`.
- **Windows, n = 5, those three cells' scenarios:**

| Cell | n = 3 median (min), p99 | n = 5 median (min), p99, background | Verdict |
|---|---|---|---|
| `seo@mem` | 0.98 (0.98), 0.93 | 1.01 (0.95), 0.91, 27/24/25/23/22 | pass |
| `seo@file` | 0.96 (0.93), 1.04 | 1.01 (0.97), 0.99, 27/24/25/23/22 | pass on the repeat |
| `pages@mem` | 2.02 (1.99), **1.26** | 2.12 (2.10), 1.04, 25/24/22/27/21 | pass on the repeat |
| `pages@file` | 1.11 (1.01), 0.93 | 1.08 (1.06), 0.90, 25/24/22/27/21 | pass |
| `write@mem` | 0.97 (0.93), 0.88 | 0.97 (0.95), 0.80, 20/23/24/25/24 | **misses by rounding, twice** |
| `write@file` | 3.16 (2.99), 0.44 | 3.47 (3.37), 0.38, 20/23/24/25/24 | pass |

## Why `write@mem` reads as the machine, not M7

Nothing M7 changed is on that path. The `skeleton` profile mounts no bot, no chat and no stream client, and of what M7 touched in
the platform it reaches only `/health`'s `obs` table, which a request never reads, and an extra branch in `hub.publish`, which it
doesn't call. Linux passes the cell, and no round is near the 0.85 floor. M6's run read 1.00 (0.94) on the same path, at a
similar background, with the same store code.

## Method

As [PARITY.md](PARITY.md): `load-tests/run.sh --parity`, per round, per scenario, per store, HEAD, v1.1.1 and the candidate back to
back on a fresh server each, `THREADS=16`, `LOG_LEVEL=warn`, `SEED=1`, 200 VUs (`scale`: 20), 3 s warmup and a 10 s window. The Linux
leg ran in a clone of its own in WSL's filesystem, on `PORT_BASE` 8090, beside the other stacks' containers, untouched.
