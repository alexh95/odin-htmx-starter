package store_sqlite

import "base:runtime"
import "core:fmt"
import "core:nbio"
import "core:os"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

import store ".."
import "../../guard"
import "../../obs"
import "../../sqlite"

// The skeleton's three migrations, as the contacts store holds them: copies, byte for byte, in
// this package's testdata, so a generated project without contacts still builds this test (test
// files compile into every build). A shipped migration is never edited, so the copies can't drift.
@(private = "file")
CONTACTS := [?]store.Migration {
	{1, "0001_init.sql", #load("testdata/contacts-0001_init.sql", string)},
	{2, "0002_events.sql", #load("testdata/contacts-0002_events.sql", string)},
	{3, "0003_contact_notes.sql", #load("testdata/contacts-0003_contact_notes.sql", string)},
}

@(private = "file")
CONTACTS_4 := [?]store.Migration {
	CONTACTS[0], CONTACTS[1], CONTACTS[2],
	{4, "0004_test_index.sql", "CREATE INDEX contacts_by_email_test ON contacts(email, id)"},
}

@(private = "file")
CHAT := [?]store.Migration{{1, "0001_chat.sql", "CREATE TABLE chat_messages (id INTEGER PRIMARY KEY, body TEXT NOT NULL)"}}

@(private = "file")
ITEMS := [?]store.Migration{{1, "0001_items.sql", "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)"}}

@(private = "file")
FIXTURE_HEAD :: #load("testdata/skeleton-709bc94.db")
@(private = "file")
FIXTURE_V111 :: #load("testdata/skeleton-v1.1.1.db")

@(private = "file")
tmp_dir: string

@(private = "file")
tmp :: proc(name: string, contents: []byte = nil) -> string {
	path := fmt.aprintf("%s/ohst-test-%d-%s", tmp_dir, os.get_pid(), name)
	remove_db_files(path)
	if contents != nil { _ = os.write_entire_file(path, contents) }
	return path
}

@(private = "file")
count :: proc(sql: string) -> int {
	return scalar(db.writer.db, sql)
}

@(private = "file")
expect_problem :: proc(t: ^testing.T, problem, want: string, loc := #caller_location) {
	testing.expectf(t, strings.contains(problem, want), "expected a problem with %q, got %q", want, problem, loc = loc)
}

// ---- the runner: research 12 §5's cases, on databases the real binaries wrote ----

@(private = "file")
runner_cases :: proc(t: ^testing.T) {
	// A fresh file: everything applies, once.
	p := tmp("fresh.db")
	testing.expect_value(t, open_db(p, .File, "skeleton", "contacts"), "")
	testing.expect_value(t, apply("contacts", CONTACTS[:]), "")
	testing.expect_value(t, count("SELECT count(*) FROM schema_migrations"), 3)
	testing.expect_value(t, count("PRAGMA application_id"), APP_ID)
	close()
	testing.expect_value(t, open_db(p, .File, "skeleton", "contacts"), "")
	testing.expect_value(t, apply("contacts", CONTACTS_4[:]), "") // only 0004 runs
	testing.expect_value(t, count("SELECT count(*) FROM schema_migrations"), 4)
	// An applied migration that changed, and a database newer than the binary.
	edited := CONTACTS_4
	edited[1].sql = "CREATE TABLE events (id INTEGER PRIMARY KEY)"
	expect_problem(t, apply("contacts", edited[:]), "must never change")
	expect_problem(t, apply("contacts", CONTACTS[:]), "newer build")
	close()

	// 709bc94's database: its three rows adopted, nothing re-run, the rows kept.
	p = tmp("head.db", FIXTURE_HEAD)
	testing.expect_value(t, open_db(p, .File, "skeleton", "contacts"), "")
	testing.expect_value(t, apply("contacts", CONTACTS_4[:]), "")
	testing.expect_value(t, count("SELECT count(*) FROM schema_migrations WHERE feature='contacts'"), 4)
	testing.expect_value(t, count("SELECT count(*) FROM schema_version"), 3) // frozen for the old binary
	testing.expect_value(t, count("SELECT count(*) FROM contacts"), 21)
	close()
	testing.expect_value(t, open_db(p, .File, "skeleton", "contacts"), "") // ours now
	testing.expect_value(t, apply("contacts", CONTACTS_4[:]), "")
	close()

	// v1.1.1's: numbers only, two of them, trusted; 0003 then applies.
	p = tmp("v111.db", FIXTURE_V111)
	testing.expect_value(t, open_db(p, .File, "skeleton", "contacts"), "")
	testing.expect_value(t, apply("contacts", CONTACTS[:]), "")
	testing.expect_value(t, count("SELECT count(*) FROM schema_migrations"), 3)
	testing.expect_value(t, count("SELECT count(*) FROM schema_version"), 2)
	testing.expect_value(t, count("SELECT count(*) FROM contacts"), 21)
	close()

	// A skeleton database under a profile that adopts no feature is refused.
	p = tmp("head2.db", FIXTURE_HEAD)
	expect_problem(t, open_db(p, .File, "lab"), "adopts none")

	// Rows of a feature this build doesn't migrate stay, dormant, and come back.
	p = tmp("dormant.db")
	testing.expect_value(t, open_db(p, .File, "full"), "")
	testing.expect_value(t, apply("contacts", CONTACTS[:]), "")
	testing.expect_value(t, apply("chat", CHAT[:]), "")
	close()
	testing.expect_value(t, open_db(p, .File, "full"), "")
	testing.expect_value(t, apply("contacts", CONTACTS[:]), "")
	testing.expect_value(t, count("SELECT count(*) FROM schema_migrations WHERE feature='chat'"), 1)
	testing.expect_value(t, apply("chat", CHAT[:]), "")
	testing.expect_value(t, count("SELECT count(*) FROM schema_migrations WHERE feature='chat'"), 1)
	close()

	// Profiles don't share a file by accident.
	expect_problem(t, open_db(p, .File, "minimal"), `belongs to profile "full"`)
	testing.expect_value(t, open_db(p, .File, "minimal", adopt_profile = true), "")
	testing.expect_value(t, get_meta("profile"), "minimal")
	close()

	// Foreign databases: tables with no records, another app's id.
	p = tmp("foreign.db")
	{
		conn, _ := sqlite.open(strings.clone_to_cstring(p, context.temp_allocator), sqlite.OPEN_READWRITE | sqlite.OPEN_CREATE)
		sqlite.exec(conn, "CREATE TABLE t (x)")
		sqlite.close(conn)
	}
	expect_problem(t, open_db(p, .File, "skeleton", "contacts"), "no migration records")
	p = tmp("appid.db")
	{
		conn, _ := sqlite.open(strings.clone_to_cstring(p, context.temp_allocator), sqlite.OPEN_READWRITE | sqlite.OPEN_CREATE)
		sqlite.exec(conn, "PRAGMA application_id=1234")
		sqlite.close(conn)
	}
	expect_problem(t, open_db(p, .File, "skeleton"), "another application")
}

// ---- reads and writes: ephemeral, as `skeleton` serves :memory: ----------------

@(private = "file")
Item_Op :: struct {
	using op: store.Op,
	name:     string,
	id:       i64,
	results:  ^[dynamic]store.Error,
}

@(private = "file") SQL_INSERT :: "INSERT INTO items(name) VALUES (?)"
@(private = "file") SQL_DELETE :: "DELETE FROM items WHERE id = ?"
@(private = "file") SQL_COUNT :: "SELECT count(*) FROM items"
@(private = "file") SQL_PAGE :: "SELECT id FROM items ORDER BY id LIMIT ? OFFSET ?"
@(private = "file") SQL_ALL :: "SELECT id FROM items ORDER BY id"

@(private = "file")
insert_run :: proc(op: ^store.Op) {
	o := (^Item_Op)(op)
	st := writer_stmt(SQL_INSERT)
	defer reset(st)
	bind_text(st, 1, o.name)
	op.err = step_done(st)
}

@(private = "file")
delete_run :: proc(op: ^store.Op) {
	o := (^Item_Op)(op)
	st := writer_stmt(SQL_DELETE)
	defer reset(st)
	bind_id(st, 1, o.id)
	if op.err = step_done(st); op.err == .None && changes() == 0 { op.err = .Not_Found }
}

@(private = "file")
item_done :: proc(op: ^store.Op) {
	o := (^Item_Op)(op)
	assert(op.loop == rawptr(nbio.current_thread_event_loop()), "done runs on the loop that queued it")
	append(o.results, op.err)
	store.free_op(op)
}

@(private = "file")
read_count :: proc() -> int {
	q := read(SQL_COUNT)
	defer reset(q)
	err: store.Error
	return column_int(q, 0) if next_row(q, &err) else -1
}

@(private = "file")
reads_and_writes :: proc(t: ^testing.T) {
	// The loop goes last: the writer can still be waking it after its last reply ran, and close()
	// joins the writer (a test's loop never joins workers' gate). ThreadSanitizer caught the free.
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()
	testing.expect_value(t, open_db(":memory:", .Ephemeral, "test"), "")
	defer close()
	testing.expect_value(t, apply("items", ITEMS[:]), "")
	testing.expect(t, write_now(proc() -> bool {
		for name in ([]string{"a", "b", "c"}) {
			st := writer_stmt(SQL_INSERT)
			bind_text(st, 1, name)
			ok := step_done(st) == .None
			reset(st)
			if !ok { return false }
		}
		return true
	}))

	// Another thread reads the writer's commits on its own connection.
	seen := -1
	th := thread.create_and_start_with_poly_data(&seen, proc(seen: ^int) { seen^ = read_count() })
	thread.join(th)
	thread.destroy(th)
	testing.expect_value(t, seen, 3)

	// QPSG: 1000 pages with changing bound LIMIT and OFFSET prepare once (§18.2's micro-guard).
	for i in 0 ..< 1000 {
		q := read(SQL_PAGE)
		bind_int(q, 1, 1 + i % 3)
		bind_int(q, 2, i % 2)
		err: store.Error
		for next_row(q, &err) {}
		reset(q)
	}
	testing.expect_value(t, sqlite.stmt_status(read(SQL_PAGE), sqlite.STMTSTATUS_REPREPARE), 0)
	reset(read(SQL_PAGE))

	// Group commit: seven writes from this loop; each answers as it would alone.
	results := make([dynamic]store.Error)
	defer delete(results)
	queue :: proc(run: proc(op: ^store.Op), name: string, id: i64, results: ^[dynamic]store.Error) -> bool {
		o := store.new_op(Item_Op, 64)
		o.run, o.done, o.results, o.id = run, item_done, results, id
		o.name = strings.clone(name, store.op_allocator(o))
		return write(o)
	}
	for name in ([]string{"d", "e", "a", "f"}) { testing.expect(t, queue(insert_run, name, 0, &results)) } // "a" exists
	testing.expect(t, queue(delete_run, "", 999, &results))                                                    // no such row
	testing.expect(t, queue(delete_run, "", 2, &results))
	testing.expect(t, queue(insert_run, "g", 0, &results))
	deadline := time.tick_now()
	for len(results) < 7 && time.tick_since(deadline) < 5 * time.Second { nbio.tick(10 * time.Millisecond) }
	testing.expect_value(t, len(results), 7)
	constraint, not_found, ok := 0, 0, 0
	for r in results {
		switch r {
		case .Constraint: constraint += 1
		case .Not_Found:  not_found += 1
		case .None:       ok += 1
		case .Busy, .Failed:
		}
	}
	testing.expect_value(t, constraint, 1)
	testing.expect_value(t, not_found, 1)
	testing.expect_value(t, ok, 5)
	testing.expect_value(t, read_count(), 3 + 4 - 1)

	// The pulled reset: a statement left mid-iteration by a pure trap is reset
	// before the reader's next use, and starts over.
	q := read(SQL_ALL)
	err: store.Error
	testing.expect(t, next_row(q, &err))
	before := obs.counter_value(db.resets)
	testing.expect(t, !guard.invoke(proc(_, _: rawptr) { panic("mid-iteration") }, nil, nil))
	_ = read_count() // the reader's next use
	testing.expect_value(t, obs.counter_value(db.resets), before + 1)
	testing.expect(t, next_row(q, &err))
	testing.expect_value(t, column_id(q, 0), 1) // from the top: it was reset
	reset(q)
}

// M1-07: a reader that can't open (out of descriptors, at the connection cap)
// fails its read with .Failed, a 500, where it used to exit the process.
@(private = "file")
reader_that_cant_open :: proc(t: ^testing.T) {
	testing.expect_value(t, open_db(":memory:", .Ephemeral, "test"), "")
	defer close()
	testing.expect_value(t, apply("items", ITEMS[:]), "")
	good := db.open_path
	db.open_path = strings.clone_to_cstring(fmt.tprintf("%s/ohst-no-such-dir-%d/x.db", tmp_dir, os.get_pid()))
	got := 0
	th := thread.create_and_start_with_poly_data(&got, proc(got: ^int) { got^ = read_count() }) // a thread with no reader yet
	thread.join(th)
	thread.destroy(th)
	db.open_path = good
	testing.expect_value(t, got, -1)
}

// A handler's reads share one read transaction (store.on_handler): one snapshot
// for the handler, the writer's commits seen by the next; and one left open by a
// handler that crashed is rolled back when the next begins.
@(private = "file")
handler_transactions :: proc(t: ^testing.T) {
	testing.expect_value(t, open_db(":memory:", .Ephemeral, "test"), "")
	defer close()
	testing.expect_value(t, apply("items", ITEMS[:]), "")
	insert :: proc(name: string) -> bool {
		@(static) n: string
		n = name
		return write_now(proc() -> bool {
			st := writer_stmt(SQL_INSERT)
			defer reset(st)
			bind_text(st, 1, n)
			return step_done(st) == .None
		})
	}
	testing.expect(t, insert("a"))

	handler_began()
	testing.expect_value(t, read_count(), 1)
	testing.expect(t, insert("b")) // committed on the writer mid-handler
	testing.expect_value(t, read_count(), 1) // the handler's snapshot
	handler_ended()
	testing.expect_value(t, read_count(), 2) // outside a handler: autocommit, the latest

	handler_began()
	testing.expect_value(t, read_count(), 2)
	testing.expect(t, insert("c"))
	// No handler_ended: the handler crashed. The next one starts fresh.
	handler_began()
	testing.expect_value(t, read_count(), 3)
	handler_ended()

	// A crash the guard recovers from, then no handler: the timer's reset (or a
	// continuation's read) rolls the crashed handler's snapshot back (M2-10).
	handler_began()
	testing.expect_value(t, read_count(), 3)
	testing.expect(t, !guard.invoke(proc(_, _: rawptr) { panic("mid-handler") }, nil, nil))
	testing.expect(t, insert("d"))
	pull_reset(tl_reader) // what on_reader_tick runs
	testing.expect(t, tl_txn == nil && !tl_in_handler)
	testing.expect_value(t, read_count(), 4)
	testing.expect(t, insert("e"))
	testing.expect_value(t, read_count(), 5) // no transaction left behind

	// The handler after a crash keeps its own snapshot: its first read doesn't reset.
	handler_began()
	testing.expect_value(t, read_count(), 5)
	testing.expect(t, !guard.invoke(proc(_, _: rawptr) { panic("mid-handler") }, nil, nil))
	handler_began()
	testing.expect_value(t, read_count(), 5)
	testing.expect(t, insert("f"))
	testing.expect_value(t, read_count(), 5)
	handler_ended()
	testing.expect_value(t, read_count(), 6)

	// A crash before the loop's reader exists, then a continuation's read: the reader opens
	// after the crash, so it has no reset to pull, and the read must begin no transaction for
	// the handler the crash ended (M2-27).
	handler_began()
	testing.expect(t, !guard.invoke(proc(_, _: rawptr) { panic("before any read") }, nil, nil))
	tl_reader.seen = guard.recoveries() // as a reader opened now is
	testing.expect_value(t, read_count(), 6)
	testing.expect(t, tl_txn == nil && !tl_in_handler)
}

// One test, in order: the store is process-wide.
@(test)
store_v3 :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {}, 1000)
	dir, _ := os.temp_directory(context.temp_allocator)
	tmp_dir = strings.clone(dir)
	runner_cases(t)
	reads_and_writes(t)
	reader_that_cant_open(t)
	handler_transactions(t)
	backup_kinds_apart(t)
}

// promote.ps1's pre-<tag>.db snapshots share BACKUP_DIR with the nightly ones: the nightly prune and
// due never count them, nor does status's health (the newest nightly alone), and each kind keeps its
// own number.
@(private = "file")
backup_kinds_apart :: proc(t: ^testing.T) {
	dir := fmt.tprintf("%s/backup-kinds-%d", tmp_dir, os.get_pid())
	testing.expect(t, os.make_directory_all(dir) == nil)
	saved := bk
	bk.dir, bk.keep = dir, 2
	defer {
		files, _ := os.read_all_directory_by_path(dir, context.temp_allocator)
		for f in files { _ = os.remove(join(dir, f.name)) }
		_ = os.remove(dir)
		bk = saved
	}
	names := []string{"backup-20200101-030000.db", "backup-20200102-030000.db", "backup-20200103-030000.db",
		"manual-20200101-120000.db", "pre-v1.0.0.db", "pre-v1.1.0.db", "pre-v1.2.0.db"}
	for name, i in names {
		path := join(dir, name)
		testing.expect(t, os.write_entire_file(path, "x") == nil)
		at := time.unix(1_600_000_000 + i64(i) * 60, 0) // in the list's order: a pre- is the newest
		_ = os.change_times(path, at, at)
	}
	prune_backups("backup-")
	left, _ := os.read_all_directory_by_path(dir, context.temp_allocator)
	kept := make([dynamic]string, context.temp_allocator)
	for f in left { append(&kept, f.name) }
	testing.expectf(t, len(kept) == 6 && !os.exists(join(dir, names[0])), "the nightly prune left %v", kept[:])
	_, newest_nightly := newest_backup("backup-")
	testing.expect_value(t, newest_nightly, "backup-20200103-030000.db")
	_, newest := newest_backup("")
	testing.expect_value(t, newest, "pre-v1.2.0.db")
}
