# stores/memory/uploads

Upload sessions and blobs' metadata in memory, the newest 4096 of each. A restart loses them: an upload doesn't resume,
and a blob's file stays on disk with no row to serve it by (X13). A feature store.
