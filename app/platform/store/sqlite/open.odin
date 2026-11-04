package store_sqlite

// ---- open and close ---------------------------------------------------------
//
// A SQLite profile's main, in order (PLAN §7.2, §8.6 step 5):
//
//   store_sqlite.open("skeleton", legacy = "contacts")   // --backup answers here, then DB_PATH and MEMMODE
//   store_sqlite.migrate("contacts", contacts_store.MIGRATIONS[:])   // one line per store, dependency order
//   if store_sqlite.unowned() { contacts_store.seed() }
//   …
//   app.shutdown()
//   store_sqlite.close()     // the writer's last batch, a checkpoint, the ephemeral file gone

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"

import "../../env"
import "../../guard"
import "../../obs"
import "../../sqlite"
import "../../store"
import "../../sys"

APP_ID :: 0x4F485354 // 'OHST' in the header's application_id (12 §5)
APP_NAME :: "odin-htmx-starter"

// §8.6 step 3: the store's env rows, recorded before app.check so --limits prints
// them; open reads them.
init :: proc() {
	if env_recorded { return }
	env.record("", ENV[:])
	env.record("", BACKUP_ENV[:])
	env_recorded = true
}

@(private) env_recorded: bool

// `profile` is the build's ("skeleton"), recorded in the database so another
// profile doesn't open it by accident. `legacy` names the feature that adopts a
// database the skeleton wrote (its schema_version rows); "" adopts none.
open :: proc(profile: string, legacy := "") {
	init()
	for p in env.problems() {
		if strings.has_prefix(p, "DB_PATH") || strings.has_prefix(p, "SEED") || strings.has_prefix(p, "MEMMODE") {
			fatal("store: %s", p)
		}
	}
	db.db_path = env.str("DB_PATH")
	adopt_profile := false
	for a, i in os.args {
		switch a {
		case "--backup":
			os.exit(backup(db.db_path, os.args[i + 1] if i + 1 < len(os.args) else ""))
		case "--adopt-profile":
			adopt_profile = true
		}
	}

	m := Mode.File
	if db.db_path == ":memory:" {
		m = .Single if env.str("MEMMODE") == "single" else .Ephemeral
	}
	if problem := open_db(db.db_path, m, profile, legacy, adopt_profile); problem != "" {
		fatal("store: %s", problem)
	}
	db.unowned = db.db_path == ":memory:" || env.bool_("SEED")

	guard.watch_lock(&db.wlock, "store write lock")
	obs.set_health("store", .Ok, critical = true)
	obs.limit("store", "busy_timeout", 5000, "ms")
	obs.limit("store", "writer_queue", MAX_QUEUED, "writes")
	obs.limit("store", "writer_batch", MAX_BATCH, "writes")
	if l, ok := obs.begin(.Info, "store", "open"); ok {
		obs.str(&l, "path", db.db_path)
		obs.str(&l, "mode", MODE_NAMES[db.mode])
		obs.str(&l, "sqlite", sqlite.libversion())
		obs.end(&l)
	}
}

// Opens the writer at `path` in mode `m`, checks the database is this app's and
// this profile's, and starts the writer task and the query pool. "" or why not:
// open() makes that fatal; tests read it.
open_db :: proc(path: string, m: Mode, profile: string, legacy := "", adopt_profile := false) -> (problem: string) {
	@(static) registered: bool
	if !registered {
		registered = true
		db.resets = obs.register_counter("app_store_reader_resets_total", "", "Reader statements reset after a pure crash (D15 rule 3).")
		writer_register()
		guard.register_drill("sqlite", drill_sqlite)
		guard.register_drill("latewrite", drill_late_write)
	}
	db.db_path = path
	db.mode = m
	db.generation += 1
	open := path
	if m == .Ephemeral {
		db.temp_path = ephemeral_path()
		open = db.temp_path
	}
	db.open_path = strings.clone_to_cstring(open)
	db.readers = make([dynamic]^Conn, runtime.heap_allocator())

	if problem = open_conn(&db.writer, sqlite.OPEN_READWRITE | sqlite.OPEN_CREATE); problem != "" { return }
	w := db.writer.db
	if m != .Single {
		must(w, "PRAGMA journal_mode=WAL")
		must(w, "PRAGMA journal_size_limit=67108864") // 64 MiB: what a checkpoint leaves of the WAL file
	}
	// NORMAL survives a process crash; only a power loss or an OS crash loses the last
	// commits (12 §3.1). An ephemeral file outlives nothing, so it syncs nothing.
	must(w, "PRAGMA synchronous=OFF" if m == .Ephemeral else "PRAGMA synchronous=NORMAL")
	must(w, "PRAGMA foreign_keys=ON") // the build's default; said again for a library built without it

	if problem = check_identity(profile, legacy, adopt_profile); problem != "" {
		close()
		return
	}
	db.is_open = true
	backup_init()
	report_memory(&db.writer, 0) // before the writer runs: ops's Store card is there from its first render
	writer_start()
	pool_start()
	@(static) hooked: bool
	if !hooked && m != .Single {
		hooked = true
		store.on_handler(handler_began, handler_ended)
	}
	return ""
}

// After app.shutdown: every loop is done, so no read is in flight. The writer
// commits what is queued, then every connection closes; the last close
// checkpoints the WAL into the file.
close :: proc() {
	if db.is_open {
		db.is_open = false
		writer_stop()
		pool_stop()
	}
	sync.mutex_lock(&db.readers_mu)
	for r in db.readers {
		finalize_cached(r)
		sqlite.close(r.db)
		free(r, runtime.heap_allocator())
	}
	clear(&db.readers)
	sync.mutex_unlock(&db.readers_mu)
	delete(db.readers)
	// Under the writer's lock: a job's write_now may still be running on the scheduler's thread,
	// which drain doesn't wait for (M5-06).
	guard.lock(&db.wlock)
	if db.writer.db != nil {
		finalize_cached(&db.writer)
		sqlite.close(db.writer.db)
	}
	db.writer = {}
	guard.unlock(&db.wlock)
	if db.temp_path != "" {
		remove_db_files(db.temp_path)
		delete(db.temp_path)
		db.temp_path = ""
	}
	delete(db.open_path)
	db.open_path = nil
}

@(private)
must :: proc(conn: sqlite.DB, sql: cstring) {
	if sqlite.exec(conn, sql) != sqlite.OK {
		fatal("store: %s failed: %s", sql, sqlite.errmsg(conn))
	}
}

// ---- ephemeral files ----------------------------------------------------------
//
// <dir>/ohst-mem-<pid>-<n>.db (and its -wal and -shm), dir being
// /dev/shm/odin-htmx-starter on Linux (a tmpfs: the file never reaches a disk) or
// odin-htmx-starter in the temp directory. A process killed before its close
// leaves them, so each boot deletes those of processes that are gone (§8.6 step
// 6). A directory of their own, because the sweep lists it: a Windows temp
// directory of 3,900 entries took 170 ms to list, against a 50 ms boot budget.

@(private) EPHEMERAL_PREFIX :: "ohst-mem-"
@(private) ephemeral_seq: int

@(private)
ephemeral_path :: proc() -> string {
	dir := ephemeral_dir()
	sweep_ephemeral(dir)
	n := sync.atomic_add(&ephemeral_seq, 1)
	path := fmt.aprintf("%s/%s%d-%d.db", dir, EPHEMERAL_PREFIX, os.get_pid(), n)
	remove_db_files(path)
	return path
}

@(private)
ephemeral_dir :: proc() -> string {
	base := "."
	when ODIN_OS == .Linux {
		if os.is_dir("/dev/shm") { base = "/dev/shm" }
	}
	if base == "." {
		if dir, err := os.temp_directory(context.temp_allocator); err == nil && dir != "" { base = dir }
	}
	dir := fmt.aprintf("%s/%s", base, APP_NAME)
	if !os.is_dir(dir) { os.make_directory(dir) } // two servers may race to make it: either wins
	return dir
}

@(private)
sweep_ephemeral :: proc(dir: string) {
	files, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil { return }
	for f in files {
		if !strings.has_prefix(f.name, EPHEMERAL_PREFIX) { continue }
		rest := f.name[len(EPHEMERAL_PREFIX):]
		dash := strings.index_byte(rest, '-')
		if dash <= 0 { continue }
		pid, ok := strconv.parse_int(rest[:dash], 10)
		if !ok || pid == os.get_pid() || sys.process_alive(pid) { continue }
		os.remove(f.fullpath)
	}
}

@(private)
remove_db_files :: proc(path: string) {
	for suffix in ([]string{"", "-wal", "-shm"}) {
		os.remove(fmt.tprintf("%s%s", path, suffix))
	}
}

// ---- --backup ---------------------------------------------------------------------
//
// A consistent, compacted copy of DB_PATH written to `dest` with VACUUM INTO. Safe
// while a server runs: it reads one snapshot, WAL included, which a plain copy of
// the file does not. SQLite refuses to write over an existing file. Exit code:
// 0, 1 when it failed, 2 for a usage error.
@(private)
backup :: proc(src, dest: string) -> int {
	if dest == "" || src == "" || src == ":memory:" {
		fmt.eprintln("usage: DB_PATH=<live db> <bin> --backup <new file>   (DB_PATH must be a file)")
		return 2
	}
	// No OPEN_CREATE: backing up a path that isn't a database is a mistake to report.
	conn, rc := sqlite.open(strings.clone_to_cstring(src, context.temp_allocator), sqlite.OPEN_READWRITE)
	defer sqlite.close(conn) // a failed open can still hand back a handle to free
	if rc != sqlite.OK {
		fmt.eprintfln("backup: can't open %s: %s", src, sqlite.errmsg(conn))
		return 1
	}
	sqlite.busy_timeout(conn, 5000)
	st, prc := sqlite.prepare(conn, "VACUUM INTO ?")
	if prc != sqlite.OK {
		fmt.eprintfln("backup: can't back up %s: %s", src, sqlite.errmsg(conn))
		return 1
	}
	defer sqlite.finalize(st)
	sqlite.bind_text(st, 1, dest)
	if sqlite.step(st) != sqlite.DONE {
		fmt.eprintfln("backup: to %s failed: %s", dest, sqlite.errmsg(conn))
		return 1
	}
	fmt.printfln("backup: %s -> %s", src, dest)
	return 0
}
