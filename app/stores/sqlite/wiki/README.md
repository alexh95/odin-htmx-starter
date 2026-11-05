# stores/sqlite/wiki

The wiki in SQLite: pages with their Markdown, rendered HTML and plain text, a revision per save (the newest 50 a page), FTS5 over
title and plain text, and the Manual, which each boot brings up to the binary's. A save runs on the query pool, under `write_now`. A
feature store.
