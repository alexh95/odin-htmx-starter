# status

`/status` (PLAN §15.4, D36; basic at M2, full at M5): is everything up? Packages: `status` (the domain: a probe per
module that reports its health to obs, plus the loops, the process and the disk), `views` (a card per probe) and `web`.
The page writes each card as "checking", and its board fills them from one `multipart/parallel` response,
`GET /status/parts`, a part per probe into its own card as the probe answers: the process's own at once, each
external's when it next answers, so a fast one is up while a slow one is still being checked (`status.spec` holds the
order); an external with no answer in 2.5 s is said to have none, and the response ends. `?mode=poll` fetches the cards every 30 s instead (`GET /status/board`, hx-ptag over the states: 304
while none changed). A probe's message is shown to `Admin_Ops` only, but an external's (its version and time) is
what it answers anyone.

`STATUS_PROBES` (`name=host:port,…`, at most 16) adds externals: each has a thread of its own that probes its `/healthz`
every 10 s, and at once when a page wants an answer fresher than 5 s, within 2 s, connect and reads together (a name to
resolve takes the resolver's own time on top: on a stack network a stopped container doesn't resolve at all). One
probe is in flight per external however many pages ask; at most 64 pages wait on one, and the rest get its last
answer. `STATUS_DISK` (`.`; `/data` in Houston's container) names the filesystem the disk part reports: degraded under
10 % free. In `lab` that is the witness board (M3): `deploy/compose.yaml` names the
other witnesses by their service names.

It owns `/status`, its own prefix.

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its fixes, f42f032, read in the re-read); 6bad255 2026-10-30 docs/audit/M3.md (M3-01's fix read in the re-read)
