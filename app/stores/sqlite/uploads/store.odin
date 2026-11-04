package uploads_store_sqlite

// ---- uploads in SQLite (PLAN §14.2, X13) ---------------------------------------------------
//
// The session rows and the blobs' metadata, kept across a restart, so an upload resumes. Rare and
// small, and written from the uploads pool's threads, which have no loop for an op to answer on:
// all through write_now. Its `run` takes no arguments and runs on the caller's own thread, hence
// the thread_local inputs. Reads come from handlers, on their loop's connection; `stale` comes
// from the sweep, a job with no reader of its own, so it asks on the writer's.

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/uploads/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_uploads.sql", #load("migrations/0001_uploads.sql", string)},
}

@(private) SQL_CREATE :: "INSERT INTO uploads_parts(user_id, size, at) VALUES(?, ?, ?)"
@(private) SQL_UPLOAD :: "SELECT id, user_id, size, received, state, at FROM uploads_parts WHERE id = ?"
@(private) SQL_ADVANCE :: "UPDATE uploads_parts SET received = ? WHERE id = ?"
@(private) SQL_CLOSE :: "UPDATE uploads_parts SET state = ? WHERE id = ?"
@(private) SQL_OPEN :: "SELECT count(*) FROM uploads_parts WHERE state = 0 AND user_id = ? AND at >= ?"
@(private) SQL_STALE :: "SELECT id FROM uploads_parts WHERE state = 0 AND at < ?"
@(private) SQL_ADD_BLOB :: "INSERT INTO uploads_blobs(sha256, mime, bytes, width, height, user_id, at) VALUES(?, ?, ?, ?, ?, ?, ?) ON CONFLICT(sha256) DO UPDATE SET at = excluded.at"
@(private) SQL_BLOBS :: "SELECT sha256 FROM uploads_blobs WHERE at < ?"
@(private) SQL_DROP_BLOB :: "DELETE FROM uploads_blobs WHERE sha256 = ? AND at < ?"
@(private) SQL_BYTES_MEMBER :: "SELECT coalesce(sum(size), 0) FROM uploads_parts WHERE user_id = ? AND at >= ?"
@(private) SQL_BYTES_ALL :: "SELECT coalesce(sum(bytes), 0) FROM uploads_blobs"
@(private) SQL_BLOB :: "SELECT sha256, mime, bytes, width, height, user_id, at FROM uploads_blobs WHERE sha256 = ?"

@(private, thread_local) t: struct {
	id:   i64,
	user: u64,
	n:    int,
	at:   i64,
	blob: m.Blob,
	out:  ^[dynamic]i64,
	shas: ^[dynamic]string,
	sql:  string,
	err:  m.Error,
}

init :: proc() {}

@(private)
outcome :: proc(ok: bool) -> m.Error { return .None if ok else t.err if t.err != .None else .Failed }

create :: proc(user: u64, size: int, at: i64) -> (id: i64, err: m.Error) {
	t = {user = user, n = size, at = at}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_CREATE)
		defer db.reset(st)
		db.bind_id(st, 1, i64(t.user))
		db.bind_int(st, 2, t.n)
		db.bind_id(st, 3, t.at)
		if t.err = db.step_done(st); t.err != .None { return false }
		t.id = db.last_insert_id()
		return true
	})
	return t.id, outcome(ok)
}

upload :: proc(id: i64) -> (u: m.Upload, err: m.Error) {
	q := db.read(SQL_UPLOAD)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	state, _ := store.enum_from_int(m.Upload_State, db.column_int(q, 4))
	return {id = db.column_id(q, 0), user = u64(db.column_id(q, 1)), size = db.column_int(q, 2), received = db.column_int(q, 3), state = state, at = db.column_id(q, 5)}, .None
}

@(private)
set_field :: proc(sql: string, id: i64, n: int) -> m.Error {
	t = {id = id, n = n, sql = sql}
	return outcome(db.write_now(proc() -> bool {
		st := db.writer_stmt(t.sql)
		defer db.reset(st)
		db.bind_int(st, 1, t.n)
		db.bind_id(st, 2, t.id)
		t.err = db.step_done(st)
		return t.err == .None
	}))
}

advance :: proc(id: i64, received: int) -> m.Error { return set_field(SQL_ADVANCE, id, received) }
close :: proc(id: i64, state: m.Upload_State) -> m.Error { return set_field(SQL_CLOSE, id, int(state)) }

open_count :: proc(user: u64, since: i64) -> int {
	q := db.read(SQL_OPEN)
	defer db.reset(q)
	db.bind_id(q, 1, i64(user))
	db.bind_id(q, 2, since)
	err: m.Error
	return db.column_int(q, 0) if db.next_row(q, &err) else 0
}

stale :: proc(before: i64, out: ^[dynamic]i64) -> m.Error {
	t = {at = before, out = out}
	return outcome(db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_STALE)
		defer db.reset(q)
		db.bind_id(q, 1, t.at)
		for db.next_row(q, &t.err) { append(t.out, db.column_id(q, 0)) }
		return t.err == .None
	}))
}

// From the sweep and the mirror, on the writer's connection as `stale` is.
blobs :: proc(before: i64, out: ^[dynamic]string) -> m.Error {
	t = {at = before, shas = out}
	return outcome(db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_BLOBS)
		defer db.reset(q)
		db.bind_id(q, 1, t.at)
		for db.next_row(q, &t.err) { append(t.shas, db.clone_col(q, 0)) }
		return t.err == .None
	}))
}

drop_blob :: proc(sha256: string, before: i64) -> (dropped: bool, err: m.Error) {
	t = {blob = {sha256 = sha256}, at = before}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_DROP_BLOB)
		defer db.reset(st)
		db.bind_text(st, 1, t.blob.sha256)
		db.bind_id(st, 2, t.at)
		t.err = db.step_done(st)
		t.n = db.changes()
		return t.err == .None
	})
	return t.n > 0, outcome(ok)
}

bytes_held :: proc(user: u64, since: i64) -> (member, all: int) {
	err: m.Error
	q := db.read(SQL_BYTES_MEMBER)
	db.bind_id(q, 1, i64(user))
	db.bind_id(q, 2, since)
	if db.next_row(q, &err) { member = int(db.column_id(q, 0)) }
	db.reset(q)
	q = db.read(SQL_BYTES_ALL)
	if db.next_row(q, &err) { all = int(db.column_id(q, 0)) }
	db.reset(q)
	return
}

// Uploaded again, it's as new: the sweep's 24 h count from the last time anyone sent it.
add_blob :: proc(b: m.Blob) -> m.Error {
	t = {blob = b}
	return outcome(db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_ADD_BLOB)
		defer db.reset(st)
		b := t.blob
		db.bind_text(st, 1, b.sha256)
		db.bind_text(st, 2, b.mime)
		db.bind_int(st, 3, b.bytes)
		db.bind_int(st, 4, b.width)
		db.bind_int(st, 5, b.height)
		db.bind_id(st, 6, i64(b.user))
		db.bind_id(st, 7, b.at)
		t.err = db.step_done(st)
		return t.err == .None
	}))
}

blob :: proc(sha256: string) -> (b: m.Blob, err: m.Error) {
	q := db.read(SQL_BLOB)
	defer db.reset(q)
	db.bind_text(q, 1, sha256)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return {
		sha256 = db.clone_col(q, 0), mime = db.clone_col(q, 1), bytes = db.column_int(q, 2), width = db.column_int(q, 3),
		height = db.column_int(q, 4), user = u64(db.column_id(q, 5)), at = db.column_id(q, 6),
	}, .None
}
