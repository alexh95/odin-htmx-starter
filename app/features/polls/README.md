# polls

Go/No-go (PLAN §15.1, D36, Q36): a question with options or the Go/No-go preset, one choice or several, named or anonymous, with a closing
time. Anyone who can vote sees the bars, which move live: `polls.poll:<id>` (`.Latest`) says the poll changed, and each page fetches them.
Closing notifies whoever voted, by the `polls.close` job each minute or the maker's button. Packages: `polls`, `models`, `views`, `web`,
`storetest`. SQLite only. It owns `/polls`, its own prefix.

**A named poll** keeps who chose what, shows the names, and a vote can change until it closes.

**An anonymous poll** keeps counters and who has voted, with nothing that joins them, and a vote is final. Nobody can be shown what
someone chose, that person included: after voting the page says "You voted". Who voted is never listed, only how many. The chosen option
stays in the form body and goes no further than the counters: no access log, audit entry, obs line or notice has it. `anonymous` is set at
creation and a trigger holds it there.

What this doesn't promise, and the poll says so: with one voter, or where everyone agrees, the bars show how people voted. Whoever changes
the server's code could log votes from then on. Someone watching the bars while one person votes can guess theirs. SQLite's WAL holds a vote's two
pages together until the next checkpoint, so the file on disk could pair a voter with a tally for a short while (`docs/audit/M8.md`).
