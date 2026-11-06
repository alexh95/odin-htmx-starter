# find

One search over a profile's `FIND_SOURCES` (PLAN §6, D6): `/find`, a plain GET form, and its results as a fragment. It imports no
other feature: each row names a domain's `find`, the perm that source needs, and its engine, and boot refuses a list that mixes FTS5
with a `contains_ci` scan (§11.8). Hits stay grouped by source. `/find` is `.Private`: it holds private-room and DM text, so it's never
history-cached. Packages: `find`, `models`, `views`, `web`. No store. It owns `/find`, its own prefix.

A member's `/bot` conversations are no source: they are their owner's alone (Q20).

Audited: 4f81819 2026-11-05 docs/audit/M8.md
