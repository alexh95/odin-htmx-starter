# Chat retention, with FTS5 on

The budget (PLAN §14.1, 12 §7): 6.4 ms per 1000 rows retention deletes, FTS5's triggers included, which make a
delete about 5× dearer.

Measured by `features/chat/storetest`'s `chunks` case: 1500 messages through the writer, then one age sweep across two
1000-row transactions, on the SQLite store at `-o:speed`.

| Date | Where | ms per 1000 rows |
|---|---|---|
| 2026-11-04 | dev PC, Windows | 3.83, 4.50, 4.21 |

The case fails at ten times the budget (64 ms), so a regression shows on any box, CI's included.
