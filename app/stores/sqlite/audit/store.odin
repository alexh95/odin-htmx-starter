package audit_store_sqlite

// ---- audit in SQLite -----------------------------------------------------------------------
//
// An append is an op through the writer task that nobody waits on; a page is a keyset read on
// the loop's reader, newest first. A change's own entry is no op of its own: `append_in` writes
// it as one more statement of the change's op, on the writer, so the two commit or fail together
// (M4-04). The table's triggers refuse an update, and a delete of an
// entry younger than 400 days, whatever the code above them does.

import "base:builtin"
import "core:strings"
import "core:sync"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/audit/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_audit.sql", #load("migrations/0001_audit.sql", string)},
}

@(private) SQL_APPEND :: "INSERT INTO audit_log(at, actor_id, actor_name, action, target_kind, target_id, reason, client_id, meta) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)"
// ?1 before (0: from the newest), ?2 the actor's name (any case; '' any), ?3 an action prefix ('' any), ?4 the page.
@(private) SQL_LIST :: "SELECT id, at, actor_id, actor_name, action, target_kind, target_id, reason, client_id, meta FROM audit_log " +
	"WHERE (?1 = 0 OR id < ?1) AND (?2 = '' OR actor_name = ?2 COLLATE NOCASE) AND (?3 = '' OR substr(action, 1, length(?3)) = ?3) " +
	"ORDER BY id DESC LIMIT ?4"

@(private)
Append :: struct {
	using op: store.Op,
	entry:    m.Entry,
}

append :: proc(actor: m.Actor, action: string, target: m.Target, reason, meta: string) -> bool {
	op := store.new_op(Append, len(actor.name) + len(actor.client) + len(action) + len(target.kind) + len(reason) + len(meta))
	a := store.op_allocator(op)
	op.entry = m.Entry {
		at = time.to_unix_nanoseconds(time.now()) / 1e6,
		actor = {id = actor.id, name = strings.clone(actor.name, a), client = strings.clone(actor.client, a)},
		action = strings.clone(action, a),
		target = {kind = strings.clone(target.kind, a), id = target.id},
		reason = strings.clone(reason, a),
		meta = strings.clone(meta, a),
	}
	op.run = proc(o: ^store.Op) {
		e := (^Append)(o).entry
		st := db.writer_stmt(SQL_APPEND)
		defer db.reset(st)
		db.bind_id(st, 1, e.at)
		db.bind_id(st, 2, e.actor.id)
		db.bind_text(st, 3, e.actor.name)
		db.bind_text(st, 4, e.action)
		db.bind_text(st, 5, e.target.kind)
		db.bind_id(st, 6, e.target.id)
		db.bind_text(st, 7, e.reason)
		db.bind_text(st, 8, e.actor.client)
		db.bind_text(st, 9, e.meta)
		o.err = db.step_done(st)
	}
	op.done = proc(o: ^store.Op) { store.free_op(o) }
	if !db.write(op) {
		store.free_op(op)
		store.dropped(&drops)
		return false
	}
	return true
}

@(private) drops := store.Drops{name = "audit"}

@(private, init)
register_drops :: proc "contextless" () { store.register_drops(&drops) }

dropped :: proc() -> u64 { return sync.atomic_load(&drops.n) }

// On the writer, inside another store's op: the entry as one more statement of it (M4-04).
append_in :: proc(actor_id: i64, actor_name, client, action, target_kind: string, target_id: i64, reason, meta: string) -> m.Error {
	st := db.writer_stmt(SQL_APPEND)
	defer db.reset(st)
	db.bind_id(st, 1, time.to_unix_nanoseconds(time.now()) / 1e6)
	db.bind_id(st, 2, actor_id)
	db.bind_text(st, 3, actor_name)
	db.bind_text(st, 4, action)
	db.bind_text(st, 5, target_kind)
	db.bind_id(st, 6, target_id)
	db.bind_text(st, 7, reason)
	db.bind_text(st, 8, client)
	db.bind_text(st, 9, meta)
	return db.step_done(st)
}

list :: proc(f: m.Filter, into: ^[dynamic]m.Entry) -> (err: m.Error) {
	q := db.read(SQL_LIST)
	defer db.reset(q)
	db.bind_id(q, 1, f.before)
	db.bind_text(q, 2, f.actor)
	db.bind_text(q, 3, f.action)
	db.bind_int(q, 4, f.limit)
	for db.next_row(q, &err) {
		builtin.append(into, m.Entry {
			id = db.column_id(q, 0),
			at = db.column_id(q, 1),
			actor = {id = db.column_id(q, 2), name = db.clone_col(q, 3), client = db.clone_col(q, 8)},
			action = db.clone_col(q, 4),
			target = {kind = db.clone_col(q, 5), id = db.column_id(q, 6)},
			reason = db.clone_col(q, 7),
			meta = db.clone_col(q, 9),
		})
	}
	return
}
