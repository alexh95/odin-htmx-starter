package obs

// ---- the store's memory ------------------------------------------------------
//
// SQLite is built with MEMSTATUS=0 (D16), so sqlite3_memory_used says nothing; each
// connection's sqlite3_db_status does. platform/store/sqlite pushes them here, the
// writer after each batch and each loop's reader on its 1 s timer, and ops reads the
// sum, so ops never imports the store (§15.4, LC §5).

import "core:sync"

Store_Memory :: struct {
	cache, schema, stmt: i64, // bytes
}

@(private)
store_mem: struct {
	slots:    [MAX_LOOPS + 1][3]i64, // atomic: slot 0 is the writer, 1 + n loop n's reader
	reported: bool, // atomic
}

store_report :: proc "contextless" (slot: int, m: Store_Memory) {
	if slot < 0 || slot >= len(store_mem.slots) { return }
	s := &store_mem.slots[slot]
	sync.atomic_store_explicit(&s[0], m.cache, .Relaxed)
	sync.atomic_store_explicit(&s[1], m.schema, .Relaxed)
	sync.atomic_store_explicit(&s[2], m.stmt, .Relaxed)
	sync.atomic_store_explicit(&store_mem.reported, true, .Relaxed)
}

// The sum over every connection that reported; ok is false in a build with no store.
store_memory :: proc() -> (m: Store_Memory, ok: bool) {
	if !sync.atomic_load_explicit(&store_mem.reported, .Relaxed) { return }
	for &s in store_mem.slots {
		m.cache += sync.atomic_load_explicit(&s[0], .Relaxed)
		m.schema += sync.atomic_load_explicit(&s[1], .Relaxed)
		m.stmt += sync.atomic_load_explicit(&s[2], .Relaxed)
	}
	return m, true
}

// ---- the newest backup ----------------------------------------------------------------
//
// platform/store/sqlite says when its newest backups were written (at open, from the files it
// finds, and after each one), and status shows their age, without either importing the other.
// The nightly is apart from the rest (a run by hand, promote's pre-deploy snapshot): only its
// age is the store's health, so neither can hide a nightly that stopped.

@(private)
backups: struct {
	nightly: i64, // atomic: unix ms; 0: none yet
	other:   i64, // atomic: the newest by hand or before a deploy; 0: none
	on:      bool, // atomic: a store here keeps backups (a file database)
}

// A value under 0 leaves that kind as it was.
backup_report :: proc "contextless" (nightly_ms, other_ms: i64) {
	if nightly_ms >= 0 { sync.atomic_store_explicit(&backups.nightly, nightly_ms, .Relaxed) }
	if other_ms >= 0 { sync.atomic_store_explicit(&backups.other, other_ms, .Relaxed) }
	sync.atomic_store_explicit(&backups.on, true, .Relaxed)
}

// ok false: nothing here keeps backups. 0: none of that kind yet.
last_backup :: proc() -> (nightly_ms, other_ms: i64, ok: bool) {
	if !sync.atomic_load_explicit(&backups.on, .Relaxed) { return 0, 0, false }
	return sync.atomic_load_explicit(&backups.nightly, .Relaxed), sync.atomic_load_explicit(&backups.other, .Relaxed), true
}
