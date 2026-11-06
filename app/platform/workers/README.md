# platform/workers

Work off the event loops (S11, D16): `submit(pool, task)` on a loop runs `task.run` on a pool thread inside the
guard and `task.done` back on the submitting loop through `nbio.next_tick`; a full queue answers 503. Also the
scheduler over the mounted `JOBS` rows, one thread waking each second. Layer L2 (PLAN §5.1).

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its fixes, f42f032, read in the re-read; 23244f2's M5-13 fix is audit debt); 5c5ebf2 2026-10-27 docs/audit/M2.md; 4f81819 2026-11-05 docs/audit/M8.md (its M8 diff)
