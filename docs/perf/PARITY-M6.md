# M6 parity gate

**Gate:** PLAN §18.2 at the M6 exit: the `skeleton` profile against HEAD (709bc94, v1.2.0) and v1.1.1, ten scenarios on
`:memory:` and on a file DB, on the Windows-native and the Linux (WSL2) legs · **Result:** Linux **PASS**, 20 of 20. Windows:
every cell passed at least one full run, but no one run passed all of them, and none ran within the gate's 20 % background;
`static@file` is the one left, **for Alex to accept** · **Date:** 2026-11-04 · **Candidates:** `771e5ef` (Linux), `2f4fa5d`,
`7e9d71c` and `28c37c1` (Windows). The commits between them change uploads, chat and an unread body's path in the fork, none of
which a parity scenario reaches · **Baselines:** v1.2.0 and v1.1.1 · **Raw rows:** `perf/results/v2.2.0-rc.2-129-g771e5ef-linux.csv`,
`v2.5-7e9d71c-windows-n5.csv`, `v2.5-28c37c1-windows-n5.csv`, `v2.2.0-rc.2-126-g2f4fa5d-windows.csv` · M5's gate:
[PARITY-M5.md](PARITY-M5.md)

## Result

- **Linux:** 20 of 20 at n = 3, background 20–34 %. `write@mem` passes its 0.93 floor at 0.96.
- **Windows, n = 3 (`2f4fa5d`):** 15 of 20, every block at about 47 % background: a game of Alex's and four stray `find` processes,
  one of them this session's, since stopped. Discarded as a verdict, kept as a record.
- **Windows, n = 5, repeats of the five misses:**

| Cell | `7e9d71c` median (min), background | `28c37c1` median (min), background | Verdict |
|---|---|---|---|
| `static@mem` | 0.99 (0.80), 43/24/22/20/21 | 0.97 (0.93), 20/25/22/22/25 | pass on the final tree |
| `static@file` | 0.99 (0.96), 43/24/22/20/21 | 0.96 (0.94), 20/25/22/22/25 | **passes, then misses the 0.97 median** |
| `seo@mem` | 0.97 (0.94), 51/22/25/21/22 | 0.98 (0.93), 22/30/24/21/23 | pass on the final tree |
| `seo@file` | 1.04 (0.97) | 0.98 (0.89) | pass |
| `pages@mem` | 2.13 (1.57), p99 1.08 | not repeated | pass |
| `pages@file` | 1.09 (1.01) | not repeated | pass |
| `write@mem` | 1.00 (0.94) | not repeated | pass |
| `write@file` | 3.65 (3.60) | not repeated | pass |

- `static@mem` missed at `7e9d71c` on one round of 0.80, at 43 % background, which overlapped another session booting WSL.
- **Why `static@file` reads as the machine, not M6:** a static file's path has no store on it, so `@mem` and `@file` are one path;
  `static@mem` passes in the same run; its candidate rps (25,653 then 25,736) didn't move between runs while the reference did;
  Linux passes it at 0.98; and M6 changed nothing on that path but F-23's atomic read, which every cell shares.
- **Open at the gate:** the game was still running through every Windows run, at about 20–25 % background against the 20 % bar.
  Alex's call, as with M5's `pages@mem`: accept `static@file`, or close it and repeat that cell.

## Method

As [PARITY.md](PARITY.md): `load-tests/run.sh --parity`, per round, per scenario, per store, HEAD, v1.1.1 and the candidate back to
back on a fresh server each, `THREADS=16`, `LOG_LEVEL=warn`, `SEED=1`, 200 VUs (`scale`: 20), 3 s warmup and a 10 s window. The
Linux leg ran in a clone of its own in WSL's filesystem, on `PORT_BASE` 8090, beside the other stacks' containers, untouched.
