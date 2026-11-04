package sqlite

// ---- platform/sqlite: the SQLite amalgamation's binding (L1) --------------
//
// The only place the C ABI is crossed. prepare.* fetches the pinned amalgamation
// and compiles it with D16's flags into app/vendor/sqlite/ (sqlite3.lib on
// Windows, sqlite3.a elsewhere). There is no `vendor:sqlite3` in Odin (#3736,
// "won't implement"), so the amalgamation is bound directly.
//
// Every call into SQLite runs with the thread's `in_sqlite` counter raised
// (sys.counters), so a trap inside SQLite's C code is classified dirty (D15 rule
// 3): the foreign procs are private, and each public proc wraps one. The binding
// stays thin; the store's helpers (bind an id, clone a column, map an error) are
// platform/store/sqlite's.

import "core:c"

import "../sys"

when ODIN_OS == .Windows {
	foreign import lib "../../vendor/sqlite/sqlite3.lib"
} else {
	// OMIT_LOAD_EXTENSION: the library references no dlopen, so no system:dl (S0.11).
	foreign import lib {"../../vendor/sqlite/sqlite3.a", "system:pthread"}
}

DB :: distinct rawptr
Stmt :: distinct rawptr
Context :: distinct rawptr // what a function defined in Odin and called from SQL receives
Value :: distinct rawptr

// Result codes. Extended codes keep the primary one in their low byte.
OK :: 0
ERROR :: 1
INTERRUPT :: 9
BUSY :: 5
LOCKED :: 6
CONSTRAINT :: 19
ROW :: 100
DONE :: 101

// column_type results.
INTEGER :: 1
FLOAT :: 2
TEXT :: 3
BLOB :: 4
NULL :: 5

// open_v2 flags.
OPEN_READONLY :: 0x00000001
OPEN_READWRITE :: 0x00000002
OPEN_CREATE :: 0x00000004
OPEN_URI :: 0x00000040
OPEN_NOMUTEX :: 0x00008000 // one connection per thread, or under the writer's lock (THREADSAFE=2)

// db_config verbs.
DBCONFIG_ENABLE_QPSG :: 1007 // the query planner stability guarantee: a bound LIMIT re-prepared 100k of 100k calls without it (12 §2.1)

// db_status verbs (MEMSTATUS=0 turns off sqlite3_memory_used, so ops reads these).
DBSTATUS_CACHE_USED :: 1
DBSTATUS_SCHEMA_USED :: 2
DBSTATUS_STMT_USED :: 3

// sqlite3_limit categories.
LIMIT_LENGTH :: 0
LIMIT_ATTACHED :: 7

// The authorizer's answers, and the actions dbview allows (sqlite3_set_authorizer).
AUTH_OK :: 0
AUTH_DENY :: 1
ACTION_READ :: 20
ACTION_SELECT :: 21
ACTION_FUNCTION :: 31
ACTION_RECURSIVE :: 33

Authorizer :: #type proc "c" (user: rawptr, action: c.int, a, b, c_, d: cstring) -> c.int

// stmt_status verbs.
STMTSTATUS_FULLSCAN_STEP :: 1
STMTSTATUS_SORT :: 2
STMTSTATUS_REPREPARE :: 5
STMTSTATUS_RUN :: 6

// create_function_v2 flags: UTF-8 arguments; a result that depends only on them.
UTF8 :: 1
DETERMINISTIC :: 0x000000800

// SQLITE_TRANSIENT (-1): SQLite copies the bound bytes, so a temp-arena string
// needn't outlive the bind.
TRANSIENT :: rawptr(~uintptr(0))

Scalar_Func :: #type proc "c" (ctx: Context, argc: c.int, argv: [^]Value)
Progress_Func :: #type proc "c" (user: rawptr) -> c.int // nonzero interrupts the statement

@(private, default_calling_convention = "c")
foreign lib {
	sqlite3_open_v2 :: proc(filename: cstring, ppDb: ^DB, flags: c.int, zVfs: cstring) -> c.int ---
	sqlite3_close_v2 :: proc(db: DB) -> c.int ---
	sqlite3_exec :: proc(db: DB, sql: cstring, cb: rawptr, arg: rawptr, errmsg: ^cstring) -> c.int ---
	sqlite3_prepare_v2 :: proc(db: DB, sql: [^]u8, nByte: c.int, ppStmt: ^Stmt, pzTail: ^[^]u8) -> c.int ---
	sqlite3_limit :: proc(db: DB, id: c.int, newVal: c.int) -> c.int ---
	sqlite3_step :: proc(stmt: Stmt) -> c.int ---
	sqlite3_reset :: proc(stmt: Stmt) -> c.int ---
	sqlite3_clear_bindings :: proc(stmt: Stmt) -> c.int ---
	sqlite3_finalize :: proc(stmt: Stmt) -> c.int ---
	sqlite3_bind_text :: proc(stmt: Stmt, idx: c.int, text: [^]u8, nByte: c.int, destructor: rawptr) -> c.int ---
	sqlite3_bind_blob :: proc(stmt: Stmt, idx: c.int, data: rawptr, nByte: c.int, destructor: rawptr) -> c.int ---
	sqlite3_bind_int :: proc(stmt: Stmt, idx: c.int, val: c.int) -> c.int ---
	sqlite3_bind_int64 :: proc(stmt: Stmt, idx: c.int, val: i64) -> c.int ---
	sqlite3_bind_double :: proc(stmt: Stmt, idx: c.int, val: f64) -> c.int ---
	sqlite3_bind_null :: proc(stmt: Stmt, idx: c.int) -> c.int ---
	sqlite3_column_count :: proc(stmt: Stmt) -> c.int ---
	sqlite3_column_type :: proc(stmt: Stmt, col: c.int) -> c.int ---
	sqlite3_column_int :: proc(stmt: Stmt, col: c.int) -> c.int ---
	sqlite3_column_int64 :: proc(stmt: Stmt, col: c.int) -> i64 ---
	sqlite3_column_double :: proc(stmt: Stmt, col: c.int) -> f64 ---
	sqlite3_column_text :: proc(stmt: Stmt, col: c.int) -> [^]u8 ---
	sqlite3_column_blob :: proc(stmt: Stmt, col: c.int) -> rawptr ---
	sqlite3_column_bytes :: proc(stmt: Stmt, col: c.int) -> c.int ---
	sqlite3_column_name :: proc(stmt: Stmt, col: c.int) -> cstring ---
	sqlite3_last_insert_rowid :: proc(db: DB) -> i64 ---
	sqlite3_changes :: proc(db: DB) -> c.int ---
	sqlite3_errmsg :: proc(db: DB) -> cstring ---
	sqlite3_errcode :: proc(db: DB) -> c.int ---
	sqlite3_extended_errcode :: proc(db: DB) -> c.int ---
	sqlite3_busy_timeout :: proc(db: DB, ms: c.int) -> c.int ---
	sqlite3_db_config :: proc(db: DB, op: c.int, #c_vararg args: ..any) -> c.int ---
	sqlite3_db_status :: proc(db: DB, op: c.int, cur: ^c.int, hiwtr: ^c.int, reset: c.int) -> c.int ---
	sqlite3_stmt_status :: proc(stmt: Stmt, op: c.int, reset: c.int) -> c.int ---
	sqlite3_stmt_readonly :: proc(stmt: Stmt) -> c.int ---
	sqlite3_sql :: proc(stmt: Stmt) -> cstring ---
	sqlite3_next_stmt :: proc(db: DB, stmt: Stmt) -> Stmt ---
	sqlite3_db_handle :: proc(stmt: Stmt) -> DB ---
	sqlite3_progress_handler :: proc(db: DB, n: c.int, f: Progress_Func, user: rawptr) ---
	sqlite3_interrupt :: proc(db: DB) ---
	sqlite3_get_autocommit :: proc(db: DB) -> c.int ---
	sqlite3_set_authorizer :: proc(db: DB, f: Authorizer, user: rawptr) -> c.int ---
	sqlite3_create_function_v2 :: proc(db: DB, name: cstring, nargs: c.int, flags: c.int, app: rawptr, xfunc: Scalar_Func, xstep: rawptr, xfinal: rawptr, destroy: rawptr) -> c.int ---
	sqlite3_value_text :: proc(v: Value) -> [^]u8 ---
	sqlite3_value_bytes :: proc(v: Value) -> c.int ---
	sqlite3_value_int64 :: proc(v: Value) -> i64 ---
	sqlite3_value_type :: proc(v: Value) -> c.int ---
	sqlite3_result_int :: proc(ctx: Context, v: c.int) ---
	sqlite3_result_int64 :: proc(ctx: Context, v: i64) ---
	sqlite3_result_null :: proc(ctx: Context) ---
	sqlite3_libversion :: proc() -> cstring ---
}

@(private)
enter :: #force_inline proc "contextless" () { sys.counters.in_sqlite += 1 }
@(private)
leave :: #force_inline proc "contextless" () { sys.counters.in_sqlite -= 1 }

// ---- connections ----------------------------------------------------------

open :: proc(path: cstring, flags: c.int) -> (db: DB, rc: c.int) {
	enter(); defer leave()
	rc = sqlite3_open_v2(path, &db, flags, nil)
	return
}

close :: proc(db: DB) -> c.int {
	enter(); defer leave()
	return sqlite3_close_v2(db)
}

// A statement with no rows to read (PRAGMA, DDL, BEGIN). Its error, if any, is errmsg's.
exec :: proc(db: DB, sql: cstring) -> c.int {
	enter(); defer leave()
	return sqlite3_exec(db, sql, nil, nil, nil)
}

busy_timeout :: proc(db: DB, ms: int) -> c.int {
	enter(); defer leave()
	return sqlite3_busy_timeout(db, c.int(ms))
}

// QPSG on every connection before any prepare (D16).
enable_qpsg :: proc(db: DB) -> c.int {
	enter(); defer leave()
	return sqlite3_db_config(db, DBCONFIG_ENABLE_QPSG, c.int(1), rawptr(nil))
}

db_status :: proc(db: DB, op: c.int, reset := false) -> (cur, high: int, rc: c.int) {
	enter(); defer leave()
	cc, hh: c.int
	rc = sqlite3_db_status(db, op, &cc, &hh, c.int(reset))
	return int(cc), int(hh), rc
}

last_insert_rowid :: proc(db: DB) -> i64 {
	enter(); defer leave()
	return sqlite3_last_insert_rowid(db)
}

changes :: proc(db: DB) -> int {
	enter(); defer leave()
	return int(sqlite3_changes(db))
}

errcode :: proc(db: DB) -> c.int {
	enter(); defer leave()
	return sqlite3_extended_errcode(db)
}

// Valid until the next call on this connection: copy it before another.
errmsg :: proc(db: DB) -> string {
	enter(); defer leave()
	return string(sqlite3_errmsg(db))
}

in_transaction :: proc(db: DB) -> bool {
	enter(); defer leave()
	return sqlite3_get_autocommit(db) == 0
}

// Every `n` VM steps the handler runs; nonzero interrupts the statement (the query
// pool's budgets, dbview).
progress_handler :: proc(db: DB, n: int, f: Progress_Func, user: rawptr) {
	enter(); defer leave()
	sqlite3_progress_handler(db, c.int(n), f, user)
}

// Safe from another thread: the statement running on `db` returns INTERRUPT.
interrupt :: proc(db: DB) {
	enter(); defer leave()
	sqlite3_interrupt(db)
}

libversion :: proc() -> string {
	return string(sqlite3_libversion())
}

// ---- statements -----------------------------------------------------------

prepare :: proc(db: DB, sql: string) -> (s: Stmt, rc: c.int) {
	enter(); defer leave()
	rc = sqlite3_prepare_v2(db, raw_data(sql), c.int(len(sql)), &s, nil)
	return
}

// The first statement of `sql`, and the text after it (dbview refuses a second statement).
prepare_first :: proc(db: DB, sql: string) -> (s: Stmt, rc: c.int, rest: string) {
	enter(); defer leave()
	tail: [^]u8
	rc = sqlite3_prepare_v2(db, raw_data(sql), c.int(len(sql)), &s, &tail)
	if tail != nil {
		used := int(uintptr(tail) - uintptr(raw_data(sql)))
		if used >= 0 && used <= len(sql) { rest = sql[used:] }
	}
	return
}

// Asked at prepare, before a statement does anything (a PRAGMA's setting included): nil removes it.
set_authorizer :: proc(db: DB, f: Authorizer, user: rawptr = nil) -> c.int {
	enter(); defer leave()
	return sqlite3_set_authorizer(db, f, user)
}

// Sets a run-time limit on this connection; the old value.
limit :: proc(db: DB, id: c.int, value: int) -> int {
	return int(sqlite3_limit(db, id, c.int(value)))
}

step :: proc(s: Stmt) -> c.int {
	enter(); defer leave()
	return sqlite3_step(s)
}

reset :: proc(s: Stmt) -> c.int {
	enter(); defer leave()
	return sqlite3_reset(s)
}

clear_bindings :: proc(s: Stmt) -> c.int {
	enter(); defer leave()
	return sqlite3_clear_bindings(s)
}

finalize :: proc(s: Stmt) -> c.int {
	enter(); defer leave()
	return sqlite3_finalize(s)
}

// Resets every statement of the connection: the pulled reset after a pure trap
// (D15 rule 3), when the jump skipped a statement's deferred reset and left it
// holding a snapshot that pins the WAL.
reset_all :: proc(db: DB) -> (n: int) {
	enter(); defer leave()
	for s := sqlite3_next_stmt(db, nil); s != nil; s = sqlite3_next_stmt(db, s) {
		sqlite3_reset(s)
		n += 1
	}
	return
}

stmt_status :: proc(s: Stmt, op: c.int, reset := false) -> int {
	enter(); defer leave()
	return int(sqlite3_stmt_status(s, op, c.int(reset)))
}

stmt_readonly :: proc(s: Stmt) -> bool {
	enter(); defer leave()
	return sqlite3_stmt_readonly(s) != 0
}

// The connection a statement belongs to (for its error message).
db_handle :: proc(s: Stmt) -> DB {
	enter(); defer leave()
	return sqlite3_db_handle(s)
}

sql :: proc(s: Stmt) -> string {
	enter(); defer leave()
	return string(sqlite3_sql(s))
}

// ---- binds: idx counts from 1 ---------------------------------------------

// An empty Odin string has a nil data pointer, and SQLite binds a nil pointer as
// NULL, which a NOT NULL column then refuses. A real byte with length 0 binds ""
// as the empty text it is (and an empty blob as an empty blob).
@(private) EMPTY := [1]u8{}

bind_text :: proc(s: Stmt, idx: int, text: string) -> c.int {
	enter(); defer leave()
	p := raw_data(text)
	if p == nil { p = &EMPTY[0] }
	return sqlite3_bind_text(s, c.int(idx), p, c.int(len(text)), TRANSIENT)
}

bind_blob :: proc(s: Stmt, idx: int, data: []byte) -> c.int {
	enter(); defer leave()
	p := raw_data(data)
	if p == nil { p = &EMPTY[0] }
	return sqlite3_bind_blob(s, c.int(idx), p, c.int(len(data)), TRANSIENT)
}

bind_int :: proc(s: Stmt, idx: int, v: int) -> c.int {
	enter(); defer leave()
	return sqlite3_bind_int64(s, c.int(idx), i64(v))
}

bind_int64 :: proc(s: Stmt, idx: int, v: i64) -> c.int {
	enter(); defer leave()
	return sqlite3_bind_int64(s, c.int(idx), v)
}

bind_double :: proc(s: Stmt, idx: int, v: f64) -> c.int {
	enter(); defer leave()
	return sqlite3_bind_double(s, c.int(idx), v)
}

bind_null :: proc(s: Stmt, idx: int) -> c.int {
	enter(); defer leave()
	return sqlite3_bind_null(s, c.int(idx))
}

// ---- columns: col counts from 0 -------------------------------------------

column_count :: proc(s: Stmt) -> int {
	enter(); defer leave()
	return int(sqlite3_column_count(s))
}

column_type :: proc(s: Stmt, col: int) -> c.int { // INTEGER … NULL; tells NULL from 0 and ""
	enter(); defer leave()
	return sqlite3_column_type(s, c.int(col))
}

column_int :: proc(s: Stmt, col: int) -> int {
	enter(); defer leave()
	return int(sqlite3_column_int64(s, c.int(col)))
}

column_int64 :: proc(s: Stmt, col: int) -> i64 {
	enter(); defer leave()
	return sqlite3_column_int64(s, c.int(col))
}

column_double :: proc(s: Stmt, col: int) -> f64 {
	enter(); defer leave()
	return sqlite3_column_double(s, c.int(col))
}

// A view into the statement's buffer, valid until its next step or reset: clone it
// before either (the store's clone_col does).
column_text :: proc(s: Stmt, col: int) -> string {
	enter(); defer leave()
	p := sqlite3_column_text(s, c.int(col)) // before column_bytes: it may convert the value
	n := sqlite3_column_bytes(s, c.int(col))
	return string(p[:n]) if p != nil else ""
}

column_blob :: proc(s: Stmt, col: int) -> []byte {
	enter(); defer leave()
	p := ([^]byte)(sqlite3_column_blob(s, c.int(col)))
	n := sqlite3_column_bytes(s, c.int(col))
	return p[:n] if p != nil else nil
}

column_name :: proc(s: Stmt, col: int) -> string {
	enter(); defer leave()
	return string(sqlite3_column_name(s, c.int(col)))
}

// ---- functions defined in Odin, called from SQL ---------------------------
//
// These run inside SQLite (in_sqlite is already raised by the step that calls
// them), so the value and result procs need no wrapping of their own.

create_function :: proc(db: DB, name: cstring, nargs: int, f: Scalar_Func, deterministic := true) -> c.int {
	enter(); defer leave()
	flags := c.int(UTF8)
	if deterministic { flags |= DETERMINISTIC }
	return sqlite3_create_function_v2(db, name, c.int(nargs), flags, nil, f, nil, nil, nil)
}

value_text :: proc "contextless" (v: Value) -> string {
	p := sqlite3_value_text(v) // before value_bytes, as with columns
	n := sqlite3_value_bytes(v)
	return string(p[:n]) if p != nil else ""
}

value_int64 :: proc "contextless" (v: Value) -> i64 { return sqlite3_value_int64(v) }
value_is_null :: proc "contextless" (v: Value) -> bool { return sqlite3_value_type(v) == NULL }
result_int :: proc "contextless" (ctx: Context, v: int) { sqlite3_result_int64(ctx, i64(v)) }
result_null :: proc "contextless" (ctx: Context) { sqlite3_result_null(ctx) }

// The bytes a BLOB or TEXT value holds.
column_bytes :: proc(s: Stmt, col: int) -> int {
	enter(); defer leave()
	return int(sqlite3_column_bytes(s, c.int(col)))
}
