# wiki

Pages rendered from Markdown when written, and the starter's own docs as a read-only Manual (PLAN §6, D36). Packages: `wiki`
(the domain and the Manual's list), `models`, `views`, `web`, `storetest`. Its store follows the family: memory is `source_files`,
the Manual alone; SQLite is editable, with revisions, on `EDIT_ROUTES`, which a profile mounts before `ROUTES` where it has an identity and SQLite (`init` does the same).
A save runs on the query pool: it renders there, then writes under `write_now`. It owns `/wiki`, its own prefix.

The Manual is an explicit list in `wiki.odin`: a new doc needs a line there, in `.dockerignore` and in the Dockerfile. Each must fit
`markdown.MAX_INPUT` (64 KiB) and hold nothing private. PLAN and DECISIONS don't fit, so the docs link to them on GitHub.

Audited: 4f81819 2026-11-05 docs/audit/M8.md
