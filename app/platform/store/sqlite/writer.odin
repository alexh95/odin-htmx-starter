package store_sqlite

// ---- the writer task: group commit (D16; S0.4's candidate C) --------------------
//
// One thread owns the writer. It takes every queued write, up to MAX_BATCH, runs
// them in one BEGIN IMMEDIATE … COMMIT, and posts each write's `done` back to the
// loop that queued it, one next_tick per loop per batch. It commits as soon as it
// is free, with no timer: writes that arrive during a commit form the next batch,
// and a fixed tick would add its period to every request write (S0.4). A write
// that fails alone (a constraint, a missing row) fails alone, because SQLite rolls
// back only the failing statement; a failed COMMIT fails the whole batch. A full
// queue is refused at once, and the caller answers 503.
//
// While idle it pings the store once a second (SELECT 1 on the writer, after a
// try-lock), so /readyz and /healthz report a store that has stopped answering.

import "core:nbio"
import "core:sync"
import "core:thread"
import "core:time"

import store ".."
import "../../guard"
import "../../obs"
import "../../sqlite"
import "../../sys"
import "../../workers"

MAX_BATCH :: 100
MAX_QUEUED :: 4096

@(private)
wq: struct {
	mu:       sync.Mutex,
	cond:     sync.Cond,
	head:     ^store.Op,
	tail:     ^store.Op,
	n:        int,
	stopping: bool,
	thread:   ^thread.Thread,
	depth:    obs.Gauge,
	batches:  obs.Counter,
	writes:   obs.Counter,
	refused:  obs.Counter,
}

// Queues `op` (its `run` set by the feature's store, its `done` by the caller).
// false: the queue is full, or the process is draining (as the pools refuse
// then: no new write starts that the loops might leave before it answers,
// M1-05); `done` will not run.
write :: proc(op: ^store.Op) -> bool {
	op.loop = nbio.current_thread_event_loop()
	op.err = .None
	op.next = nil
	sync.mutex_lock(&wq.mu)
	defer sync.mutex_unlock(&wq.mu)
	if wq.stopping || obs.is_draining() || wq.n >= MAX_QUEUED {
		obs.inc(wq.refused)
		return false
	}
	if wq.tail == nil { wq.head = op } else { wq.tail.next = op }
	wq.tail = op
	wq.n += 1
	obs.set(wq.depth, i64(wq.n))
	sync.cond_signal(&wq.cond)
	return true
}

// A statement on the writer: for a write's `run` (on the writer task, inside its
// batch) and for the seed. `defer reset(st)` as with reads.
writer_stmt :: proc(sql: string) -> Stmt {
	return cached(&db.writer, sql)
}

// The writer outside the task: at boot (the seed, the bootstrap admin) and from a thread with no
// loop for a queued write to answer on (the scheduler's jobs): one transaction under the
// writer's lock. `run` steps writer_stmt statements; false rolls back. false too once the
// store has closed: `close` takes the same lock (M5-06).
write_now :: proc(run: proc() -> bool) -> bool {
	guard.lock(&db.wlock)
	defer guard.unlock(&db.wlock)
	if !db.is_open || db.writer.db == nil { return false }
	if sqlite.exec(db.writer.db, "BEGIN IMMEDIATE") != sqlite.OK { return false }
	if !run() {
		sqlite.exec(db.writer.db, "ROLLBACK")
		return false
	}
	return sqlite.exec(db.writer.db, "COMMIT") == sqlite.OK
}

// Copies the WAL into the file and empties it, under the writer's lock: at boot, after a write
// whose old values must not linger in the WAL's frames (M4-12's sealing). false when a reader
// held it back.
checkpoint_truncate :: proc() -> bool {
	guard.lock(&db.wlock)
	defer guard.unlock(&db.wlock)
	if !db.is_open || db.writer.db == nil { return false }
	return sqlite.exec(db.writer.db, "PRAGMA wal_checkpoint(TRUNCATE)") == sqlite.OK
}

@(private)
writer_register :: proc() {
	wq.depth = obs.register_gauge("app_store_writer_queue", "", "Writes waiting for the writer task.")
	wq.batches = obs.register_counter("app_store_writer_batches_total", "", "Transactions the writer task committed.")
	wq.writes = obs.register_counter("app_store_writer_writes_total", "", "Writes the writer task ran.")
	wq.refused = obs.register_counter("app_store_writer_refused_total", "", "Writes refused: the queue was full (503).")
}

@(private)
writer_start :: proc() {
	wq.stopping = false
	wq.thread = thread.create_and_start(writer_run, context)
}

// The queue drains first: a write queued before the loops stopped is committed.
@(private)
writer_stop :: proc() {
	sync.mutex_lock(&wq.mu)
	wq.stopping = true
	sync.cond_broadcast(&wq.cond)
	sync.mutex_unlock(&wq.mu)
	if wq.thread != nil {
		thread.join(wq.thread)
		thread.destroy(wq.thread)
		wq.thread = nil
	}
}

@(private)
take_batch :: proc() -> (head: ^store.Op, n: int, stop: bool) {
	sync.mutex_lock(&wq.mu)
	defer sync.mutex_unlock(&wq.mu)
	for wq.n == 0 {
		if wq.stopping { return nil, 0, true }
		if !sync.cond_wait_with_timeout(&wq.cond, &wq.mu, time.Second) && wq.n == 0 {
			return nil, 0, false // idle a second: ping
		}
	}
	head = wq.head
	last := head
	n = 1
	for n < MAX_BATCH && last.next != nil {
		last = last.next
		n += 1
	}
	wq.head = last.next
	if wq.head == nil { wq.tail = nil }
	last.next = nil
	wq.n -= n
	obs.set(wq.depth, i64(wq.n))
	return head, n, false
}

// An entry point (D15 rule 1): the batch runs under the writer's lock, so a trap
// in it is dirty and the process drains and exits 70.
@(private)
writer_run :: proc() {
	guard.thread_init()
	for {
		head, n, stop := take_batch()
		if stop { return }
		if head == nil {
			ping()
			// Under the lock: the scheduler's write_now uses this connection too (M5-02).
			guard.lock(&db.wlock)
			report_memory(&db.writer, 0)
			guard.unlock(&db.wlock)
			continue
		}
		// A trap mid-batch is dirty (the process drains and exits 70), and the batch
		// never reached COMMIT: every op answers Failed, not the .None it was queued with.
		if !guard.call(commit_batch, head) { fail_batch(head, "the batch crashed") }
		obs.inc(wq.batches)
		obs.inc(wq.writes, u64(n))
		post_replies(head)
		free_all(context.temp_allocator)
	}
}

@(private)
commit_batch :: proc(data: rawptr) {
	head := (^store.Op)(data)
	w := db.writer.db
	guard.lock(&db.wlock)
	defer guard.unlock(&db.wlock)
	// Prepared once, from the statement cache: sqlite3_exec parsed both for every batch.
	if !run_cached("BEGIN IMMEDIATE") {
		fail_batch(head, sqlite.errmsg(w))
		return
	}
	for op := head; op != nil; op = op.next {
		op.run(op)
	}
	if !run_cached("COMMIT") {
		fail_batch(head, sqlite.errmsg(w))
		sqlite.exec(w, "ROLLBACK")
	}
	report_memory(&db.writer, 0) // still under the lock (M5-02)
}

@(private)
run_cached :: proc(sql: string) -> bool {
	st := writer_stmt(sql)
	defer sqlite.reset(st)
	return sqlite.step(st) == sqlite.DONE
}

@(private)
fail_batch :: proc(head: ^store.Op, msg: string) {
	if l, ok := obs.begin(.Error, "store", "batch_failed"); ok {
		obs.str(&l, "msg", msg)
		obs.end(&l)
	}
	for op := head; op != nil; op = op.next { op.err = .Failed }
}

// One next_tick per loop: the batch's ops are relinked into a chain per loop.
@(private)
post_replies :: proc(head: ^store.Op) {
	MAX :: 64
	loops: [MAX]rawptr
	chains: [MAX]^store.Op
	n := 0
	op := head
	for op != nil {
		next := op.next
		i := 0
		for i < n && loops[i] != op.loop { i += 1 }
		if i == n {
			if n == MAX { // more loops than slots: this one goes alone
				op.next = nil
				post_chain(op)
				op = next
				continue
			}
			loops[n], chains[n] = op.loop, nil
			n += 1
		}
		op.next = chains[i]
		chains[i] = op
		op = next
	}
	for i in 0 ..< n {
		post_chain(chains[i])
	}
}

// One loop's replies. A loop that has left gets none (M1-05): its ops are freed
// here, their continuations never run.
@(private)
post_chain :: proc(head: ^store.Op) {
	if workers.post((^nbio.Event_Loop)(head.loop), head, on_replies) { return }
	for op := head; op != nil; {
		next := op.next
		store.free_op(op)
		op = next
	}
}

// On the loop that queued them. A `done` frees its op, so the link is read first.
@(private)
on_replies :: proc(_: ^nbio.Operation, head: ^store.Op) {
	defer free_all(context.temp_allocator)
	op := head
	for op != nil {
		next := op.next
		guard.call(proc(data: rawptr) { op := (^store.Op)(data); op.done(op) }, op)
		op = next
	}
}

// TEST_ROUTES: a write that holds the writer 2 s, so a shutdown begun right after
// it lets the loops leave before its reply comes back (M1-05's drill). The reply
// does nothing but free the op.
@(private)
drill_late_write :: proc() {
	op := store.new_op(store.Op, 0)
	op.run = proc(_: ^store.Op) { time.sleep(2 * time.Second) }
	op.done = proc(op: ^store.Op) { store.free_op(op) }
	if !write(op) { store.free_op(op) }
}

// SELECT 1 on the writer within 100 ms of trying its lock: the store's health.
@(private)
ping :: proc() {
	deadline := sys.mono_ns() + 100 * 1e6
	for !guard.try_lock(&db.wlock) {
		if sys.mono_ns() > deadline {
			obs.set_health("store", .Down, "the write lock is held", critical = true)
			return
		}
		time.sleep(5 * time.Millisecond)
	}
	ok := sqlite.exec(db.writer.db, "SELECT 1") == sqlite.OK
	guard.unlock(&db.wlock)
	obs.set_health("store", .Ok if ok else .Down, "" if ok else "SELECT 1 failed", critical = true)
}
