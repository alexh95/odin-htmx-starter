# stores/sqlite/polls

Polls, their options, `poll_tally` (the counters every poll's bars read), `poll_voters` (who voted, `WITHOUT ROWID`, no time) and
`poll_votes` (a named poll's choices). An anonymous vote writes only the first two, in one transaction, so nothing in one copy of the file says
who chose what; a series of copies can (`features/polls/README.md`). SQLite only: there's no memory member, so a memory build that reaches `polls` fails to compile. A vote runs on the query pool under
`write_now`. A feature store.

Audited: 4f81819 2026-11-05 docs/audit/M8.md (M8-01, as `features/polls/README.md` says)
