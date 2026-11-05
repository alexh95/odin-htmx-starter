# stores/sqlite/polls

Polls, their options, `poll_tally` (the counters every poll's bars read), `poll_voters` (who voted, `WITHOUT ROWID`, no time) and
`poll_votes` (a named poll's choices). An anonymous vote writes only the first two, in one transaction, so nothing in one copy of the file says
who chose what; a series of copies can (`features/polls/README.md`). SQLite only: there's no memory member, so a memory build that reaches `polls` fails to compile. A vote runs on the query pool under
`write_now`. A feature store.
