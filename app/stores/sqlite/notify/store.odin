package notify_store_sqlite

// ---- notify in SQLite (PLAN §14.2, M6) -------------------------------------------------------
//
// A member's newest KEEP items, kept across restarts. Reads on the loop's reader; an add goes
// through the writer task, which trims the member's oldest past KEEP in the same batch and
// counts what is unread, so the caller answers with exactly what was stored. Marking read and
// the sweep are writes the caller waits on (write_now): one UPDATE or DELETE each.

import "core:strings"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/notify/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_notify.sql", #load("migrations/0001_notify.sql", string)},
}

// notify.KEEP: the store can't import the domain, which imports it.
KEEP :: 200

@(private) SQL_LIST :: "SELECT id, kind, ref, html, at, read FROM notify_items WHERE user_id = ? ORDER BY id DESC LIMIT ?"
@(private) SQL_UNREAD :: "SELECT count(*) FROM notify_items WHERE user_id = ? AND read = 0"
@(private) SQL_ADD :: "INSERT INTO notify_items(user_id, kind, ref, html, at) VALUES(?, ?, ?, ?, ?)"
@(private) SQL_TRIM :: "DELETE FROM notify_items WHERE user_id = ?1 AND id <= (SELECT id FROM notify_items WHERE user_id = ?1 ORDER BY id DESC LIMIT 1 OFFSET ?2)"
@(private) SQL_READ :: "UPDATE notify_items SET read = 1 WHERE user_id = ? AND read = 0"
@(private) SQL_PRUNE :: "DELETE FROM notify_items WHERE read = 1 AND at < ?"

list :: proc(user: u64, limit: int, out: ^[dynamic]m.Item) -> (err: m.Error) {
	q := db.read(SQL_LIST)
	defer db.reset(q)
	db.bind_id(q, 1, i64(user))
	db.bind_int(q, 2, limit)
	for db.next_row(q, &err) {
		append(out, m.Item {
			id = db.column_id(q, 0), user = user, kind = db.clone_col(q, 1), ref = db.clone_col(q, 2),
			html = db.clone_col(q, 3), at = db.column_id(q, 4), read = db.column_int(q, 5) != 0,
		})
	}
	return
}

unread :: proc(user: u64) -> int {
	q := db.read(SQL_UNREAD)
	defer db.reset(q)
	db.bind_id(q, 1, i64(user))
	err: m.Error
	return db.column_int(q, 0) if db.next_row(q, &err) else 0
}

add :: proc(op: ^m.Add) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Add)(o)
		at := time.time_to_unix(time.now())
		st := db.writer_stmt(SQL_ADD)
		db.bind_id(st, 1, i64(op.user))
		db.bind_text(st, 2, op.kind)
		db.bind_text(st, 3, op.ref)
		db.bind_text(st, 4, op.html)
		db.bind_id(st, 5, at)
		o.err = db.step_done(st)
		db.reset(st)
		if o.err != .None { return }
		a := store.op_allocator(o)
		op.result = {
			id = db.last_insert_id(), user = op.user, at = at,
			kind = strings.clone(op.kind, a), ref = strings.clone(op.ref, a), html = strings.clone(op.html, a),
		}
		tr := db.writer_stmt(SQL_TRIM)
		db.bind_id(tr, 1, i64(op.user))
		db.bind_int(tr, 2, KEEP)
		o.err = db.step_done(tr)
		db.reset(tr)
		if o.err != .None { return }
		c := db.writer_stmt(SQL_UNREAD)
		db.bind_id(c, 1, i64(op.user))
		op.unread = db.column_int(c, 0) if db.next_row(c, &o.err) else 0
		db.reset(c)
	}
	return db.write(op)
}

@(private) marking: u64

mark_read :: proc(user: u64) -> m.Error {
	marking = user
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_READ)
		defer db.reset(st)
		db.bind_id(st, 1, i64(marking))
		return db.step_done(st) == .None
	})
	return .None if ok else .Busy
}

@(private) pruning: struct {
	before: i64,
	n:      int,
}

prune :: proc(read_before: i64) -> int {
	pruning.before, pruning.n = read_before, 0
	db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_PRUNE)
		defer db.reset(st)
		db.bind_id(st, 1, pruning.before)
		if db.step_done(st) != .None { return false }
		pruning.n = db.changes()
		return true
	})
	return pruning.n
}
