package store_sqlite

// ---- the query pool (D16) ---------------------------------------------------------
//
// Two threads for anything that scans, ranks, exports, backs up or can hit a
// budget: an inline 4 ms scan cut a loop's fast path from 51.4k to 11.5k rps; on
// the pool it stayed at 51-52k (12 §4). Each worker reads on its own connection,
// as a loop does. The caller defers its response (F-13) and answers in the task's
// `done`; a full queue answers 503.

import "../../workers"

QUERY_THREADS :: 2
QUERY_QUEUE :: 64

@(private) query_pool: workers.Pool

// On a loop: runs `t.run` on a pool thread (where `read` gives that thread's own
// reader), then `t.done` back here. false: the pool is full or draining.
query :: proc(t: ^workers.Task) -> bool {
	return workers.submit(&query_pool, t)
}

@(private)
pool_start :: proc() {
	workers.start(&query_pool, "query", QUERY_THREADS, QUERY_QUEUE)
	workers.query_pool = &query_pool
}

@(private)
pool_stop :: proc() {
	workers.query_pool = nil
	if query_pool.threads != nil { workers.stop(&query_pool) }
}
