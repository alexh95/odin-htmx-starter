package store_sqlite

// ---- platform/store/sqlite: store v3 (L2) -----------------------------------
//
// D16, PLAN §11.1. One writer connection under a guard.Mutex, written to by the
// writer task (writer.odin), which commits the writes every loop queued as one
// transaction. One read-only connection per thread that reads (each event loop,
// each query-pool worker), opened on that thread's first read: a loop runs its
// handlers one at a time, so its statements need no lock, and WAL lets every
// reader read while the writer writes. Every connection turns QPSG on before it
// prepares anything, so a bound LIMIT never re-prepares a statement (12 §2.1).
//
// DB_PATH picks the file; ":memory:" is served by MEMMODE (§11.3):
//   - ephemeral (default): a WAL database in an unsynced temp file (on /dev/shm
//     on Linux), deleted on close and swept at the next boot if the process died;
//     it runs the same code path as a file DB;
//   - single: one in-RAM connection, every read under the writer's lock.
//
// A feature's store reads with `read(SQL)` … `defer reset(q)` and writes through
// an op (store.Op) whose `run` binds and steps `writer_stmt(SQL)`. Statements are
// prepared once per connection, keyed by the SQL string's address: pass a
// constant, or a string built once at init, never one built per call.
//
// After a pure crash a loop's reader statements may be left mid-iteration (the
// jump skipped their deferred resets), and one that holds its snapshot pins the
// WAL without bound (12 §10). The reset is pulled from guard's recovery count,
// before each use of the reader and on a 1 s timer its first use arms (S0.6), so
// guard never calls into SQLite and a memory profile links none.

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:nbio"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

import store ".."
import "../../env"
import "../../guard"
import "../../obs"
import "../../sqlite"
import "../../sys"

Stmt :: sqlite.Stmt

Mode :: enum u8 {
	File,
	Ephemeral,
	Single,
}

MODE_NAMES := [Mode]string {
	.File      = "file",
	.Ephemeral = "ephemeral",
	.Single    = "single",
}

// A connection and the statements prepared on it.
Conn :: struct {
	db:    sqlite.DB,
	keys:  [CACHE]uintptr,
	lens:  [CACHE]int,
	stmts: [CACHE]Stmt,
	n:     int,
	seen:  u64, // guard.recoveries() when its statements were last known reset
	armed: bool, // its loop's reset timer runs
}

@(private) CACHE :: 128

@(private)
db: struct {
	open_path:    cstring, // what every connection opens
	db_path:      string, // DB_PATH as given
	temp_path:    string, // ephemeral: the file to delete on close
	mode:         Mode,
	unowned:      bool, // :memory:, or SEED=1: the demo rows go in
	writer:       Conn,
	wlock:        guard.Mutex,
	readers_mu:   sync.Mutex,
	readers:      [dynamic]^Conn,
	resets:       obs.Counter,
	is_open:      bool,
	generation:   int, // bumped per open
}

@(private, thread_local) tl_reader: ^Conn
@(private, thread_local) tl_generation: int // the open its reader belongs to: a closed store's reader is gone
@(private, thread_local) tl_read_locked: bool // single mode: this thread's read holds the writer's lock
@(private, thread_local) tl_in_handler: bool  // between store.handler_begin and handler_end
@(private, thread_local) tl_txn: ^Conn        // the reader holding this handler's read transaction
@(private, thread_local) tl_handler_seen: u64  // guard.recoveries() when this handler began

ENV := [?]env.Row {
	{name = "DB_PATH", kind = .Path, def = ":memory:", doc = "the SQLite file; :memory: is fresh per process"},
	{name = "SEED", kind = .Bool, def = "0", doc = "1 seeds the demo rows into an empty file DB (:memory: always is)"},
	{name = "MEMMODE", kind = .Enum, def = "ephemeral", choices = "ephemeral|single", doc = "how :memory: is served (PLAN §11.3)"},
}

// The one thing a store returns for a database it can't use: a message and exit 1.
@(private)
fatal :: proc(format: string, args: ..any) -> ! {
	if l, ok := obs.begin(.Fatal, "store", "boot"); ok {
		obs.str(&l, "msg", fmt.tprintf(format, ..args))
		obs.end(&l)
	}
	obs.flush()
	fmt.eprintfln(format, ..args)
	os.exit(1)
}

// Whether this database is nobody's yet (:memory:, or SEED=1): main seeds the
// demo rows then, into empty tables only (§8.6 step 6).
unowned :: proc() -> bool { return db.unowned }

mode :: proc() -> Mode { return db.mode }

// ---- connections ------------------------------------------------------------

// "" or why not. The writer's is fatal at boot; a reader's, in a request, is a
// failed read (M1-07).
@(private)
open_conn :: proc(conn: ^Conn, flags: c.int) -> (problem: string) {
	h, rc := sqlite.open(db.open_path, flags | sqlite.OPEN_NOMUTEX)
	if rc != sqlite.OK {
		problem = fmt.tprintf("can't open %s: %s", db.db_path, sqlite.errmsg(h) if h != nil else "out of memory")
		if h != nil { sqlite.close(h) }
		return
	}
	conn.db = h
	// Before any prepare: QPSG applies to the statements prepared after it.
	sqlite.enable_qpsg(h)
	sqlite.busy_timeout(h, 5000)
	if sqlite.create_function(h, "contains_ci", 2, sql_contains_ci) != sqlite.OK {
		fatal("store: can't register contains_ci: %s", sqlite.errmsg(h))
	}
	return ""
}

@(private)
sql_contains_ci :: proc "c" (ctx: sqlite.Context, argc: c.int, argv: [^]sqlite.Value) {
	context = runtime.default_context()
	sqlite.result_int(ctx, 1 if store.contains_ci(sqlite.value_text(argv[0]), sqlite.value_text(argv[1])) else 0)
}

// A connection's own statements, before it closes. Only these: sqlite3_next_stmt walks FTS5's
// internal ones too, and finalising those under it crashed the close that followed.
@(private)
finalize_cached :: proc(c: ^Conn) {
	for st in c.stmts[:] {
		if st != nil { sqlite.finalize(st) }
	}
}

// The statement for `sql` on `c`, prepared on first use.
@(private)
cached :: proc(c: ^Conn, sql: string) -> Stmt {
	key := uintptr(raw_data(sql))
	h := int((u64(key) >> 4) * 0x9E3779B97F4A7C15 >> 57) // the top 7 bits: 0 ..< CACHE
	for i in 0 ..< CACHE {
		j := (h + i) & (CACHE - 1)
		if c.keys[j] == key && c.lens[j] == len(sql) { return c.stmts[j] }
		if c.keys[j] != 0 { continue }
		st, rc := sqlite.prepare(c.db, sql)
		if rc != sqlite.OK {
			fmt.panicf("store: can't prepare %q: %s", sql, sqlite.errmsg(c.db))
		}
		c.keys[j], c.lens[j], c.stmts[j] = key, len(sql), st
		c.n += 1
		return st
	}
	fmt.panicf("store: more than %d statements on one connection: is SQL built per call? Pass a constant.", CACHE)
}

// ---- reads ------------------------------------------------------------------

// A statement on this thread's reader (single mode: on the writer, under its
// lock until `reset`). Bind, step with next_row, and `defer reset(q)` at once:
// an unreset statement holds its snapshot and pins the WAL. nil when this
// thread's reader can't open (out of descriptors, M1-07): SQLite's binds and
// reset take nil as a no-op, and next_row says .Failed, so the read answers 500
// and serving goes on.
read :: proc(sql: string) -> Stmt {
	if db.mode == .Single {
		assert(!tl_read_locked, "store: single mode reads one statement at a time: reset the last one first")
		guard.lock(&db.wlock)
		tl_read_locked = true
		return cached(&db.writer, sql)
	}
	r := reader()
	if r == nil { return nil }
	// A crash since the handler began ended it, whatever the flag says: a reader opened after
	// the crash has no reset to pull, and a continuation's read began a transaction no one
	// ended (M2-27).
	if tl_in_handler && tl_handler_seen != guard.recoveries() { tl_in_handler = false }
	// A handler's reads share one transaction, begun at its first (a deferred
	// request's continuation reads outside it, so no other request on this loop
	// meets a snapshot left open).
	if tl_in_handler && tl_txn == nil && step_cached(r, "BEGIN") { tl_txn = r }
	return cached(r, sql)
}

// The handler hooks (store.on_handler, registered at open). A transaction still
// open at begin is a crashed handler's: it is rolled back. The pulled reset runs
// here too, before this handler is in: at its first read it would take this
// handler for the crashed one.
@(private)
handler_began :: proc() {
	if tl_txn != nil { end_txn(false) }
	if tl_reader != nil && tl_generation == db.generation { pull_reset(tl_reader) }
	tl_in_handler, tl_handler_seen = true, guard.recoveries()
}

@(private)
handler_ended :: proc() {
	tl_in_handler = false
	if tl_txn != nil { end_txn(true) }
}

// COMMIT, or ROLLBACK (and a COMMIT that fails, which a statement left unreset
// can make one), after resetting the reader's statements.
@(private)
end_txn :: proc(commit: bool) {
	r := tl_txn
	tl_txn = nil
	if commit && step_cached(r, "COMMIT") { return }
	sqlite.reset_all(r.db)
	_ = step_cached(r, "ROLLBACK")
}

@(private)
step_cached :: proc(r: ^Conn, sql: string) -> bool {
	st := cached(r, sql)
	defer sqlite.reset(st)
	return sqlite.step(st) == sqlite.DONE
}

// Ends a read, or a write's statement: resets it, and gives back the writer's
// lock that a single-mode read took.
reset :: proc(st: Stmt) {
	sqlite.reset(st)
	if tl_read_locked {
		tl_read_locked = false
		guard.unlock(&db.wlock)
	}
}

@(private)
reader :: proc() -> ^Conn {
	r := tl_reader
	if r == nil || tl_generation != db.generation { r = open_reader() }
	if r == nil { return nil }
	pull_reset(r)
	return r
}

// nil, logged, when SQLite can't open it.
@(private)
open_reader :: proc() -> ^Conn {
	r := new(Conn, runtime.heap_allocator())
	if problem := open_conn(r, sqlite.OPEN_READONLY); problem != "" {
		free(r, runtime.heap_allocator())
		if l, ok := obs.begin(.Error, "store", "reader"); ok {
			obs.str(&l, "msg", problem)
			obs.end(&l)
		}
		return nil
	}
	r.seen = guard.recoveries()
	sync.mutex_lock(&db.readers_mu)
	append(&db.readers, r)
	sync.mutex_unlock(&db.readers_mu)
	tl_reader, tl_generation = r, db.generation
	// A loop arms its reset timer; a query-pool worker or a job resets before each use, and after a crash (`pool_crashed`).
	if obs.current_loop() >= 0 {
		r.armed = true
		nbio.timeout_poly(time.Second, r, on_reader_tick)
	}
	return r
}

// The pulled reset (D15 rule 3), when this thread recovered from a crash since the
// reader's last: guard never calls into SQLite itself.
@(private)
pull_reset :: proc(r: ^Conn) {
	if n := guard.recoveries(); n != r.seen { reset_reader(r, n) }
}

// A pool's or a job's thread has no timer, and may sit idle after a crash with a read left open.
@(private)
pool_crashed :: proc() {
	// A job can trap after the store closed, and its reader went with it.
	if db.is_open && tl_reader != nil && tl_generation == db.generation { pull_reset(tl_reader) }
}

// A crash skips handler_ended, so the crashed handler's transaction goes too: left
// open, every read on the loop outside a handler (a write's continuation) met its
// snapshot, and the WAL couldn't checkpoint past it until the next handler (M2-10).
@(private)
reset_reader :: proc(r: ^Conn, recoveries: u64) {
	n := sqlite.reset_all(r.db)
	if tl_txn == r { end_txn(false) }
	tl_in_handler = false
	r.seen = recoveries
	obs.inc(db.resets)
	if l, ok := obs.begin(.Warning, "store", "reader_reset"); ok {
		obs.num(&l, "statements", i64(n))
		obs.end(&l)
	}
}

// The pulled reset's timer: a loop that crashed and then got no more reads would
// otherwise keep its snapshot for good (S0.6: the WAL grew 165 MB in 5 s). It
// stops re-arming once the server drains, so it never holds a loop's exit.
@(private)
on_reader_tick :: proc(_: ^nbio.Operation, r: ^Conn) {
	defer free_all(context.temp_allocator)
	if !db.is_open || tl_reader != r { return } // its store closed: r is gone
	guard.call(proc(data: rawptr) { pull_reset((^Conn)(data)) }, r)
	report_memory(r, 1 + obs.current_loop())
	if obs.is_draining() || !db.is_open {
		r.armed = false
		return
	}
	nbio.timeout_poly(time.Second, r, on_reader_tick)
}

// What this connection holds, to obs for ops (MEMSTATUS=0: the per-connection numbers are
// the only ones). Slot 0 is the writer, 1 + n loop n's reader.
@(private)
report_memory :: proc(c: ^Conn, slot: int) {
	cache, _, _ := sqlite.db_status(c.db, sqlite.DBSTATUS_CACHE_USED)
	schema, _, _ := sqlite.db_status(c.db, sqlite.DBSTATUS_SCHEMA_USED)
	stmt, _, _ := sqlite.db_status(c.db, sqlite.DBSTATUS_STMT_USED)
	obs.store_report(slot, {i64(cache), i64(schema), i64(stmt)})
}

// ---- helpers for a feature's store ---------------------------------------------

// Ids are 64-bit: binding one through a 32-bit int once read (and deleted)
// contact #1 for /contacts/4294967297.
bind_id :: proc(st: Stmt, idx: int, id: i64) { sqlite.bind_int64(st, idx, id) }
bind_int :: proc(st: Stmt, idx: int, v: int) { sqlite.bind_int(st, idx, v) }
bind_text :: proc(st: Stmt, idx: int, s: string) { sqlite.bind_text(st, idx, s) } // "" binds as empty text
bind_bool :: proc(st: Stmt, idx: int, v: bool) { sqlite.bind_int(st, idx, 1 if v else 0) }
bind_null :: proc(st: Stmt, idx: int) { sqlite.bind_null(st, idx) }

column_id :: proc(st: Stmt, col: int) -> i64 { return sqlite.column_int64(st, col) }
column_int :: proc(st: Stmt, col: int) -> int { return sqlite.column_int(st, col) }
column_bool :: proc(st: Stmt, col: int) -> bool { return sqlite.column_int(st, col) != 0 }
is_null :: proc(st: Stmt, col: int) -> bool { return sqlite.column_type(st, col) == sqlite.NULL }

// A text column copied out of the statement's buffer, which its next step or
// reset reuses: into the request arena by default, or an op's allocator.
clone_col :: proc(st: Stmt, col: int, allocator := context.temp_allocator) -> string {
	return strings.clone(sqlite.column_text(st, col), allocator)
}

// Runs a write to its end. Anything but DONE is an error: last_insert_rowid and
// changes() then still describe the previous statement.
step_done :: proc(st: Stmt) -> store.Error {
	rc := sqlite.step(st)
	if rc == sqlite.DONE { return .None }
	return step_error(st, rc)
}

// Advances a read; false at the end of the rows or on an error, which lands in
// err^: `for next_row(q, &err) { … }`.
next_row :: proc(st: Stmt, err: ^store.Error) -> bool {
	if st == nil { // the reader couldn't open (read)
		err^ = .Failed
		return false
	}
	switch rc := sqlite.step(st); rc {
	case sqlite.ROW:  return true
	case sqlite.DONE: return false
	case:
		err^ = step_error(st, rc)
		return false
	}
}

@(private)
step_error :: proc(st: Stmt, rc: c.int) -> store.Error {
	if l, ok := obs.begin(.Error, "store", "step"); ok {
		obs.num(&l, "rc", i64(rc))
		obs.str(&l, "msg", sqlite.errmsg(sqlite.db_handle(st)))
		obs.end(&l)
	}
	// The low byte is the primary result code; the rest says which constraint.
	switch rc & 0xff {
	case sqlite.CONSTRAINT: return .Constraint
	case sqlite.BUSY, sqlite.LOCKED: return .Busy
	}
	return .Failed
}

// On the writer, inside a write's `run` or the seed: the last insert and the rows
// the last statement changed.
last_insert_id :: proc() -> i64 { return sqlite.last_insert_rowid(db.writer.db) }
changes :: proc() -> int { return sqlite.changes(db.writer.db) }

// ---- the store's own numbers, for ops (§10.4) -----------------------------------

@(private)
wal_bytes :: proc() -> i64 {
	if db.mode == .Single { return 0 }
	info, err := os.stat(strings.concatenate({string(db.open_path), "-wal"}, context.temp_allocator), context.temp_allocator)
	return info.size if err == nil else 0
}

@(private)
mono_ms :: proc() -> i64 { return sys.mono_ns() / 1e6 }

// TEST_ROUTES' `sqlite` drill (PLAN §19.1.10): a trap inside a function SQL
// calls, so in_sqlite is up and the guard must call the crash dirty. Registered
// only in a TEST_ROUTES build (guard.register_drill).
@(private)
drill_sqlite :: proc() {
	r := reader()
	sqlite.create_function(r.db, "drill_crash", 0, proc "c" (ctx: sqlite.Context, argc: c.int, argv: [^]sqlite.Value) {
		p := (^int)(uintptr(argc)) // argc is 0: a nil pointer the optimiser can't see
		p^ = 1
		sqlite.result_int(ctx, 0)
	}, deterministic = false)
	s, _ := sqlite.prepare(r.db, "SELECT drill_crash()")
	sqlite.step(s)
	sqlite.finalize(s)
}

// A MATCH expression: each word quoted, so nothing a member types is FTS5 syntax, and the last also
// matches as a prefix, from two bytes: one is most of the index (the tables' `prefix` holds 2 and 3).
fts_query :: proc(words: []string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for w, i in words {
		if i > 0 { strings.write_byte(&b, ' ') }
		strings.write_byte(&b, '"')
		for c in transmute([]byte)w {
			if c == '"' { strings.write_byte(&b, '"') }
			strings.write_byte(&b, c)
		}
		strings.write_byte(&b, '"')
		if i == len(words) - 1 && len(w) >= 2 { strings.write_byte(&b, '*') }
	}
	return strings.to_string(b)
}
