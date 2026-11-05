# find's budgets (M8)

**Gate:** PLAN §22.3, M8's row: FTS MATCH ≤ 3 ms at 100k messages · **Result:** **pass**. Every search a member can send takes under 0.5 ms at
its worst · **Date:** 2026-11-05 · **Tool:** `tools/findbench`, `-o:speed` · **Host:** the dev PC, Windows, a game running

100k messages of twelve Zipf-distributed words over 40 rooms, half of them private, in a file database in WAL, for a member of three of those.
200 runs of each, in ms.

| Query | p50 | p95 | worst |
|---|---:|---:|---:|
| MATCH, rare word | 0.015 | 0.016 | 0.076 |
| MATCH, a word in most messages | 0.043 | 0.072 | 0.158 |
| MATCH, two words | 0.088 | 0.143 | 0.321 |
| Search, rare word (membership rows and `snippet()`) | 0.044 | 0.077 | 0.317 |
| Search, a word in most messages | 0.095 | 0.193 | 0.349 |
| Search, two words | 0.114 | 0.167 | 0.245 |
| Search, a two-byte prefix | 0.090 | 0.129 | 0.194 |
| Search, a three-byte prefix | 0.058 | 0.092 | 0.435 |
| Search, a word only private rooms hold | 0.041 | 0.084 | 0.232 |
| `snippet()` alone, 10 hits | 0.107 | 0.124 | 0.441 |
| bm25 over every hit, a word in most messages | 25.5 | 30.3 | 31.5 |
| bm25 over every hit, a one-byte prefix | 130 | 140 | 148 |
| MATCH, a one-byte prefix | 41.5 | 46.8 | 51.6 |

## What the run changed

- **The prefix index.** A search's last word is also a prefix, and that was the cost: with no index for it FTS5 merges every matching term's list,
  so one common word took 33 ms and two words 19.5 ms. `prefix = '2 3'` on all three indexes (chat's in `0010_fts_prefix.sql`) brings those to 0.095
  and 0.114 ms. On this data the index goes from 3.8 MB to 8.6 MB, and rebuilding 100k messages takes 355 ms, which the migration does once.
- **No one-byte prefix.** It stayed at 41 ms, and it's what a search box sends at the first keystroke. From two bytes the last word is a prefix;
  a single byte is matched as a word. No MATCH a search sends costs what the last row costs.

## bm25

Only the wiki ranks, on the query pool: the whole Manual is a dozen pages, so its cost is the small end of these numbers. Chat doesn't: newest first
sorts nothing, and bm25 would read every hit, 25 ms here, on a query that otherwise reads ten.
