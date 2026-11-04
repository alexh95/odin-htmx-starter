package store_sqlite

// ---- backups as a job (PLAN §11.6, §11.8; M5) --------------------------------------------
//
// `store.backup` writes `backup-<UTC date>-<time>.db` (`manual-…` when an admin asks for it on
// /admin/jobs) into BACKUP_DIR with VACUUM INTO (live-safe: one snapshot, WAL included,
// compacted), on a connection of its own, so the writer and the loops' readers go on. It writes
// to `<name>.part` and renames once a quick_check passes, so a copy cut short is never taken for
// a backup; then the newest BACKUP_KEEP of its kind stay. It wakes every 10 minutes and runs at
// BACKUP_HOUR_UTC once a day (`due`), on the long-run thread. A cancel stops the copy mid-way
// (SQLite's progress handler) and the part written goes. promote.ps1's pre-deploy snapshots
// (`pre-<tag>.db`) land in the same BACKUP_DIR, each kind pruned only by its owner (promote keeps
// 5 `pre-`; `backup_names` never lists one). Status judges by the newest nightly alone and shows
// the others' age beside it, so neither a run by hand nor a deploy hides a nightly that stopped.

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

import "../../env"
import "../../obs"
import "../../sqlite"
import "../../sys"
import "../../workers"

BACKUP_ENV := [?]env.Row {
	{name = "BACKUP_DIR", kind = .Path, def = "", doc = `where the nightly backups go; "" = backups/ beside DB_PATH`},
	{name = "BACKUP_HOUR_UTC", kind = .Int, def = "3", doc = "the hour (UTC) of the nightly backup; -1 = only when asked for by hand"},
	{name = "BACKUP_KEEP", kind = .Int, def = "7", doc = "the nightly backups kept, the newest; as many by hand, apart"},
}

// A profile on SQLite mounts this with its JOBS.
JOBS := [?]workers.Job {
	{"store.backup", 10 * time.Minute, backup_job, backup_due},
}

// A nightly backup younger than this is today's (the hour comes round again in 24 h).
@(private) BACKUP_FRESH :: 20 * time.Hour

@(private)
bk: struct {
	dir:  string, // "" when the database is no file
	hour: int,
	keep: int,
}

// From open, for a file database: where the backups go, and the newest one there to obs.
@(private)
backup_init :: proc() {
	bk.dir = ""
	if db.mode != .File || !env_recorded { return } // a store's own tests open without the env rows
	bk.hour, bk.keep = env.int_("BACKUP_HOUR_UTC"), max(env.int_("BACKUP_KEEP"), 1)
	bk.dir = env.str("BACKUP_DIR")
	bk.dir = join(filepath.dir(db.db_path), "backups", context.allocator) if bk.dir == "" else strings.clone(bk.dir)
	nightly, _ := newest_backup("backup-")
	by_hand, _ := newest_backup("manual-")
	before_deploy, _ := newest_backup("pre-")
	obs.backup_report(nightly, max(by_hand, before_deploy))
}

// Where the backups go, resolved; "" when the database is no file.
backup_dir :: proc() -> string { return bk.dir }

// Nightly: at its hour, and not yet today.
@(private)
backup_due :: proc() -> bool {
	if bk.dir == "" || bk.hour < 0 { return false }
	h, _, _ := time.clock(time.now())
	if h != bk.hour { return false }
	newest, _ := newest_backup("backup-")
	return newest == 0 || sys.now_unix_ns() / 1e6 - newest >= i64(BACKUP_FRESH / time.Millisecond)
}

@(private)
backup_job :: proc() {
	if bk.dir == "" {
		workers.log("nothing to back up: the database isn't a file")
		return
	}
	if err := os.make_directory_all(bk.dir); err != nil && !os.exists(bk.dir) {
		workers.fail("can't make %s: %v", bk.dir, err)
		return
	}
	// A run by hand is `manual-`, kept apart, so clicks never rotate out the nightly ones (M5-05).
	r := workers.current()
	prefix := "manual-" if r != nil && r.by_hand else "backup-"
	now := time.now()
	y, mo, d := time.date(now)
	h, mi, s := time.clock(now)
	name := fmt.tprintf("%s%04d%02d%02d-%02d%02d%02d.db", prefix, y, int(mo), d, h, mi, s)
	dest := join(bk.dir, name)
	// Written under a name no reader takes for a backup, and given its own once it checks: a
	// copy a restart cut short is never counted, kept or restored (M5-04).
	part := strings.concatenate({dest, ".part"}, context.temp_allocator)
	for stale in backup_names("", ".part") { _ = os.remove(join(bk.dir, stale)) }
	if os.exists(dest) {
		workers.fail("%s is there already", name)
		return
	}

	workers.progress(0, 3)
	workers.log("copying %s to %s", db.db_path, dest)
	if !vacuum_into(part) {
		_ = os.remove(part)
		return
	}
	workers.progress(1, 3)
	if problem := quick_check(part); problem != "" {
		workers.fail("the copy doesn't check: %s", problem)
		_ = os.remove(part)
		return
	}
	if err := os.rename(part, dest); err != nil {
		workers.fail("can't name it %s: %v", name, err)
		_ = os.remove(part)
		return
	}
	size := i64(0)
	if fi, err := os.stat(dest, context.temp_allocator); err == nil { size = fi.size }
	workers.log("checked: %d bytes", size)
	workers.progress(2, 3)
	prune_backups(prefix)
	workers.progress(3, 3)
	now_ms := sys.now_unix_ns() / 1e6
	obs.backup_report(now_ms if prefix == "backup-" else -1, now_ms if prefix == "manual-" else -1)
}

// VACUUM INTO on a connection of its own; a cancel interrupts it (the handler runs every 1000
// VM steps). false: it didn't finish, and said why.
@(private)
vacuum_into :: proc(dest: string) -> bool {
	conn, rc := sqlite.open(strings.clone_to_cstring(db.db_path, context.temp_allocator), sqlite.OPEN_READWRITE)
	defer sqlite.close(conn)
	if rc != sqlite.OK {
		workers.fail("can't open %s: %s", db.db_path, sqlite.errmsg(conn))
		return false
	}
	sqlite.busy_timeout(conn, 5000)
	sqlite.progress_handler(conn, 1000, proc "c" (_: rawptr) -> c.int {
		context = runtime.default_context()
		return 1 if workers.cancelled() else 0
	}, nil)
	st, prc := sqlite.prepare(conn, "VACUUM INTO ?")
	if prc != sqlite.OK {
		workers.fail("can't back up: %s", sqlite.errmsg(conn))
		return false
	}
	defer sqlite.finalize(st)
	sqlite.bind_text(st, 1, dest)
	if sqlite.step(st) != sqlite.DONE {
		if workers.cancelled() {
			workers.log("stopped: the part written is removed")
		} else {
			workers.fail("the copy failed: %s", sqlite.errmsg(conn))
		}
		return false
	}
	return true
}

// "" when the copy's quick_check says ok.
@(private)
quick_check :: proc(path: string) -> string {
	conn, rc := sqlite.open(strings.clone_to_cstring(path, context.temp_allocator), sqlite.OPEN_READONLY)
	defer sqlite.close(conn)
	if rc != sqlite.OK { return strings.clone(string(sqlite.errmsg(conn)), context.temp_allocator) }
	st, prc := sqlite.prepare(conn, "PRAGMA quick_check")
	if prc != sqlite.OK { return strings.clone(string(sqlite.errmsg(conn)), context.temp_allocator) }
	defer sqlite.finalize(st)
	if sqlite.step(st) != sqlite.ROW { return "no answer" }
	got := strings.clone(sqlite.column_text(st, 0), context.temp_allocator)
	return "" if got == "ok" else got
}

// The newest BACKUP_KEEP of one kind (nightly or by hand) stay; their names sort by time.
@(private)
prune_backups :: proc(prefix: string) {
	names := backup_names(prefix, ".db")
	slice.sort(names)
	for name in names[:max(len(names) - bk.keep, 0)] {
		if os.remove(join(bk.dir, name)) == nil { workers.log("removed %s", name) }
	}
}

// The newest backup's time (unix ms) whose name starts with `prefix` ("" any of ours or
// promote's); 0 when there is none.
@(private)
newest_backup :: proc(prefix: string) -> (unix_ms: i64, name: string) {
	infos, err := os.read_all_directory_by_path(bk.dir, context.temp_allocator)
	if err != nil { return }
	for fi in infos {
		ours := strings.has_prefix(fi.name, "backup-") || strings.has_prefix(fi.name, "manual-") || strings.has_prefix(fi.name, "pre-")
		if !ours || !strings.has_prefix(fi.name, prefix) || !strings.has_suffix(fi.name, ".db") { continue }
		ms := time.to_unix_nanoseconds(fi.modification_time) / 1e6
		if ms > unix_ms { unix_ms, name = ms, fi.name }
	}
	return
}

@(private)
join :: proc(a, b: string, allocator := context.temp_allocator) -> string {
	s, _ := filepath.join({a, b}, allocator)
	return s
}

@(private)
backup_names :: proc(prefix, suffix: string) -> []string {
	infos, err := os.read_all_directory_by_path(bk.dir, context.temp_allocator)
	if err != nil { return nil }
	out := make([dynamic]string, context.temp_allocator)
	for fi in infos {
		ours := strings.has_prefix(fi.name, "backup-") || strings.has_prefix(fi.name, "manual-")
		if ours && strings.has_prefix(fi.name, prefix) && strings.has_suffix(fi.name, suffix) { append(&out, fi.name) }
	}
	return out[:]
}
