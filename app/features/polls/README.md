# polls

Go/No-go (PLAN §15.1, D36, Q36): a question with options or the Go/No-go preset, one choice or several, named or anonymous, with a closing
time. Anyone who can vote sees the bars, which move live: `polls.poll:<id>` (`.Latest`) says the poll changed, and each page fetches them.
Closing notifies whoever voted, by the `polls.close` job each minute or the maker's button. Packages: `polls`, `models`, `views`, `web`,
`storetest`. SQLite only. It owns `/polls`, its own prefix.

**A named poll** keeps who chose what, shows the names, and a vote can change until it closes.

**An anonymous poll** keeps counters and who has voted, with nothing in one copy of the file that joins them, and a vote is final. Nobody can be shown what
someone chose, that person included: after voting the page says "You voted". Who voted is never listed but in an admin's dbview, only how many. The chosen option
stays in the form body and goes no further than the counters: no access log, audit entry, obs line or notice has it. `anonymous` is set at
creation and a trigger holds it there.

**The promise is about one copy of the file.** One copy can't pair a voter with an option. A series of copies can: two backups with one new
voter between them show that voter's choice in the difference of `poll_voters` and `poll_tally`, and so can anyone holding the data volume
(M8-01, Q36). `BACKUP_KEEP` keeps seven nightly copies by default, and `promote.ps1`'s `pre-<tag>.db` snapshots are the same kind of copy.

What this doesn't promise. The poll says all of this but the WAL. The site keeps who has voted, and an admin's dbview can read that. With
one voter, or where everyone agrees, the bars show how people voted; someone watching the bars while one person votes can guess theirs;
anyone who compares backups from before and after can tell. Whoever changes the server's code could log votes from then on. SQLite's WAL
holds a vote's two pages side by side until later writes overwrite them, which can be days on a quiet house, and a checkpoint doesn't
erase them.
