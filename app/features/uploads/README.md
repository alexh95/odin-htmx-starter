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

**What the bytes are** is decided by the bytes: magic bytes, then the header's size against 40 MP before anything is
allocated for it, then a full decode with `core:image`. Only PNG and JPEG get through, so SVG and HTML never do, and no
progressive JPEG, which `core:image` doesn't read. `core:image` isn't written for hostile input, and two things stand
in front of it (the fuzz found both; both are upstream reports waiting in `TODO.md`):

- a JPEG's Huffman tables are checked first: its reader sums their counts in a `u8`, and past 256 symbols indexes out of
  bounds;
- a decode runs in an arena with a hard cap, room for its declared pixels and never more than 256 MiB: the inflate
  behind PNG doesn't stop at the declared size, and a 282-byte file would take all the memory there is. The allocator's
  refusal is what ends it. On a small container that cap is the real limit, below 40 MP for a deep PNG.

**Serving**: the type from the row, `nosniff` as on every response, `inline` (every blob is an image), immutable: an
address is its content. Blobs are for members, not for a room: an address held only by those who saw the image is the
capability, and it leaves with the message (PLAN §17.6, with what it can't reach: a browser's cache).

**Lifetime**: a blob lives while something holds it. `uploads.holds(proc)` registers a holder, asked each time, so nothing
counts. `uploads.sweep`, hourly, takes what's a day old and unheld; `release` is the same check at once, for a member's
delete; `erase` takes it regardless, once a moderator's removal has cleared its holders. A holder that can't tell answers
true: a file goes only on a no.

**Backups**: `uploads.mirror`, daily, keeps `<BACKUP_DIR>/blobs/` as the rows say (`docs/DATA.md`): a build with no backups
calls no `backs_up_to` and the job does nothing.

**Pools**: chunks on `uploads` (2 threads, queue 8: §17.6's 8 × 4 MiB), finishes on `decodes` (1, queue 8), reads on
`blobs` (2, queue 32); past a queue, 503.

It owns `/uploads`, its own prefix.
