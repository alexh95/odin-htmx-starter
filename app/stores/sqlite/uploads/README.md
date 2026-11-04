# stores/sqlite/uploads

Upload sessions and blobs' metadata in SQLite, kept across a restart so an upload resumes (X13). The bytes aren't here:
they're in `UPLOADS_DIR`. Written through `write_now`, from the uploads pools, which have no loop to answer on. A feature
store.

Audited: 771e5ef 2026-11-04 docs/audit/M6.md
