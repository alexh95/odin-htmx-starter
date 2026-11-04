# uploads

Chunked uploads (PLAN §14.2, §17.6, D35, X13): chat's images now, avatars and video later. Packages: `uploads` (the
domain: the caps, the part file, what the bytes are, the blob), `models` (the types and the store contract), `web`
(the routes, the pools, the hourly `uploads.sweep`), `static/uploads.js` (the fetch shim). Its stores: memory
(`app/stores/memory/uploads/`, an upload doesn't resume across a restart) and SQLite (`app/stores/sqlite/uploads/`);
`storetest` holds both to one contract. The bytes live in `UPLOADS_DIR`: `parts/<id>` and `blobs/<sha256>`.

**The flow**: `POST /uploads?size=` opens one; `PUT /uploads/<id>?off=` takes a chunk of at most 4 MiB at the offset the
server is at (409 and `received` otherwise, which is how a lost answer resumes; `GET /uploads/<id>` says the same);
`POST /uploads/<id>/finish` checks it and makes it a blob; `GET /uploads/blob/<sha256>` serves it. Twenty an hour and two
at once per member (`UPLOADS_PER_HOUR`); an upload nobody finished stops counting after an hour and the sweep takes it.
Progress comes from each chunk's answer, not from `uploads.upload:<id>`: the page's `#live` topics are fixed when it
loads, and the shim holds the answer already.

**What the bytes are** is decided by the bytes: magic bytes, then the size the header claims against 40 MP, with a JPEG walked
to its end by each segment's length and a second frame refused, so a decoy can't pass the cap in a browser. Only PNG and JPEG
get through, so SVG and HTML never do. Nothing decodes an image here: the server keeps the bytes and serves them, so an image
corrupt past its header is stored and shows as broken in the viewer's browser. PLAN §17.6 says why, and what a feature that
needs pixels must do (a child process with `RLIMIT_AS` and a CPU limit).

**Serving**: the type from the row, `nosniff` as on every response, `inline` (every blob is an image), immutable: an
address is its content. Blobs are for members, not for a room: an address held only by those who saw the image is the
capability, and it leaves with the message (PLAN §17.6, with what it can't reach: a browser's cache).

**Lifetime**: a blob lives while something holds it. `uploads.holds(proc)` registers a holder, asked each time, so nothing
counts. `uploads.sweep`, hourly, takes what's a day old and unheld; `release` is the same check at once, for a member's
delete; `erase` takes it regardless, once a moderator's removal has cleared its holders. A holder that can't tell answers
true: a file goes only on a no.

**Backups**: `uploads.mirror`, daily, keeps `<BACKUP_DIR>/blobs/` as the rows say (`docs/DATA.md`): a build with no backups
calls no `backs_up_to` and the job does nothing.

**Limits**: 256 MiB a member a day and 16 GiB overall (`UPLOADS_BYTES_PER_DAY`, `UPLOADS_MAX_BYTES`); a body of 1 MiB or more is counted before it's read, 8 at once and 2 a member (`web.large_begin`);
blob answers are counted to 64 MiB until they've gone.

**Pools**: chunks on `uploads` (2 threads, queue 8: §17.6's 8 × 4 MiB), finishes on `finishes` (1, queue 8: each reads and hashes up to 10 MiB), reads on
`blobs` (2, queue 32); past a queue, 503.

It owns `/uploads`, its own prefix.
