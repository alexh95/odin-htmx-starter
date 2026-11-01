package chat_store_sqlite

// ---- chat in SQLite (PLAN §14.1, D30; M6) ----------------------------------------------------
//
// Rooms and messages kept across restarts: ids are rowids, so a page resumes a room's topic from
// `@<rowid>` after a restart too (PERSISTED, D13). Reads on the loop's reader; a post or a change
// goes through the writer task, which bumps the room's version and reads the row back in the same
// batch, so the caller answers with exactly what was stored. Rooms are made at once (write_now):
// the caller answers with the room. Retention (slice 3) moves `dropped` and `dropped_ver`, which
// say a cursor below them can't be served whole.

import "core:strings"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/chat/models"

IMPL :: "sqlite"

PERSISTED :: true

MAX_ROOMS :: 1000

MIGRATIONS := [?]store.Migration {
	{1, "0001_chat.sql", #load("migrations/0001_chat.sql", string)},
}

@(private) ROOM_COLS :: "id, slug, name, at"
@(private) MSG_COLS :: "id, room, author, name, body, at, edited, gone, ver"
@(private) SQL_ROOMS :: "SELECT " + ROOM_COLS + " FROM chat_rooms ORDER BY id"
@(private) SQL_ROOM :: "SELECT " + ROOM_COLS + " FROM chat_rooms WHERE slug = ?"
@(private) SQL_ROOM_COUNT :: "SELECT count(*) FROM chat_rooms"
@(private) SQL_ADD_ROOM :: "INSERT INTO chat_rooms(slug, name, at) VALUES(?, ?, ?)"
@(private) SQL_ROOM_STATE :: "SELECT ver, dropped, dropped_ver FROM chat_rooms WHERE id = ?"
@(private) SQL_RECENT :: "SELECT " + MSG_COLS + " FROM (SELECT " + MSG_COLS + " FROM chat_messages WHERE room = ? ORDER BY id DESC LIMIT ?) ORDER BY id"
@(private) SQL_AFTER :: "SELECT " + MSG_COLS + " FROM chat_messages WHERE room = ? AND id > ? ORDER BY id"
@(private) SQL_COUNT_AFTER :: "SELECT count(*) FROM chat_messages WHERE room = ? AND id > ?"
@(private) SQL_CHANGED :: "SELECT " + MSG_COLS + " FROM chat_messages WHERE room = ? AND ver > ? ORDER BY id"
@(private) SQL_MESSAGE :: "SELECT " + MSG_COLS + " FROM chat_messages WHERE id = ?"
@(private) SQL_BUMP :: "UPDATE chat_rooms SET ver = ver + 1 WHERE id = ? RETURNING ver"
@(private) SQL_POST :: "INSERT INTO chat_messages(room, author, name, body, at, ver) VALUES(?, ?, ?, ?, ?, ?)"
@(private) SQL_EDIT :: "UPDATE chat_messages SET body = ?, edited = ?, ver = ? WHERE id = ?"
@(private) SQL_DELETE :: "UPDATE chat_messages SET body = '', gone = 1, ver = ? WHERE id = ?"

// Nothing to size: the in-memory ring of §14.1 arrives with retention.
init :: proc(ring_bytes: int) {}

rooms :: proc(out: ^[dynamic]m.Room) -> (err: m.Error) {
	q := db.read(SQL_ROOMS)
	defer db.reset(q)
	for db.next_row(q, &err) { append(out, one_room(q)) }
	return
}

room :: proc(slug: string) -> (r: m.Room, err: m.Error) {
	q := db.read(SQL_ROOM)
	defer db.reset(q)
	db.bind_text(q, 1, slug)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return one_room(q), .None
}

@(private) making: struct {
	slug, name: string,
	room:       m.Room,
	err:        m.Error,
}

// .Constraint: the slug is taken, or the rooms are full.
create_room :: proc(slug, name: string) -> (m.Room, m.Error) {
	making = {slug = slug, name = name}
	ok := db.write_now(proc() -> bool {
		c := db.writer_stmt(SQL_ROOM_COUNT)
		n := db.column_int(c, 0) if db.next_row(c, &making.err) else MAX_ROOMS
		db.reset(c)
		if n >= MAX_ROOMS {
			making.err = .Constraint
			return false
		}
		at := now()
		st := db.writer_stmt(SQL_ADD_ROOM)
		defer db.reset(st)
		db.bind_text(st, 1, making.slug)
		db.bind_text(st, 2, making.name)
		db.bind_id(st, 3, at)
		if making.err = db.step_done(st); making.err != .None { return false }
		making.room = {id = db.last_insert_id(), slug = strings.clone(making.slug, context.temp_allocator), name = strings.clone(making.name, context.temp_allocator), at = at}
		return true
	})
	if !ok { return {}, making.err if making.err != .None else .Failed }
	return making.room, .None
}

// Oldest first.
recent :: proc(room_id: i64, limit: int, out: ^[dynamic]m.Message) -> (err: m.Error) {
	q := db.read(SQL_RECENT)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	db.bind_int(q, 2, limit)
	for db.next_row(q, &err) { append(out, one_msg(q)) }
	return
}

// id > after, oldest first; reached: nothing after `after` was let go.
after :: proc(room_id: i64, after_id: i64, out: ^[dynamic]m.Message) -> (reached: bool, err: m.Error) {
	_, dropped, _ := state(room_id) or_return
	q := db.read(SQL_AFTER)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	db.bind_id(q, 2, after_id)
	for db.next_row(q, &err) { append(out, one_msg(q)) }
	return dropped <= after_id, err
}

count_after :: proc(room_id: i64, after_id: i64) -> int {
	q := db.read(SQL_COUNT_AFTER)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	db.bind_id(q, 2, after_id)
	err: m.Error
	return db.column_int(q, 0) if db.next_row(q, &err) else 0
}

// ver > since; the room's version; reached: nothing changed after `since` has left the room.
changed :: proc(room_id: i64, since: i64, out: ^[dynamic]m.Message) -> (ver: i64, reached: bool, err: m.Error) {
	v, _, dropped_ver := state(room_id) or_return
	q := db.read(SQL_CHANGED)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	db.bind_id(q, 2, since)
	for db.next_row(q, &err) { append(out, one_msg(q)) }
	return v, dropped_ver <= since, err
}

message :: proc(id: i64) -> (msg: m.Message, err: m.Error) {
	q := db.read(SQL_MESSAGE)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return one_msg(q), .None
}

post :: proc(op: ^m.Post) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Post)(o)
		ver: i64
		if ver, o.err = bump(op.room); o.err != .None { return }
		at := now()
		st := db.writer_stmt(SQL_POST)
		db.bind_id(st, 1, op.room)
		db.bind_id(st, 2, i64(op.author))
		db.bind_text(st, 3, op.name)
		db.bind_text(st, 4, op.body)
		db.bind_id(st, 5, at)
		db.bind_id(st, 6, ver)
		o.err = db.step_done(st)
		db.reset(st)
		if o.err != .None { return }
		a := store.op_allocator(o)
		op.result = {id = db.last_insert_id(), room = op.room, author = op.author, name = strings.clone(op.name, a), body = strings.clone(op.body, a), at = at, ver = ver}
	}
	return db.write(op)
}

// An edit or a delete of the author's own message inside `window`: .Not_Found for none or one
// deleted, .Constraint for someone else's or one too old.
change :: proc(op: ^m.Change) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Change)(o)
		a := store.op_allocator(o)
		q := db.writer_stmt(SQL_MESSAGE)
		db.bind_id(q, 1, op.id)
		found := db.next_row(q, &o.err)
		msg := one_msg(q, a) if found else {}
		db.reset(q)
		if o.err != .None { return }
		switch {
		case !found || msg.gone:
			o.err = .Not_Found
			return
		case msg.author != op.author || now() - msg.at > op.window:
			o.err = .Constraint
			return
		}
		ver: i64
		if ver, o.err = bump(msg.room); o.err != .None { return }
		edited := now()
		st := db.writer_stmt(SQL_DELETE if op.delete else SQL_EDIT)
		if op.delete {
			db.bind_id(st, 1, ver)
			db.bind_id(st, 2, op.id)
		} else {
			db.bind_text(st, 1, op.body)
			db.bind_id(st, 2, edited)
			db.bind_id(st, 3, ver)
			db.bind_id(st, 4, op.id)
		}
		o.err = db.step_done(st)
		db.reset(st)
		if o.err != .None { return }
		op.result = msg
		op.result.ver = ver
		if op.delete {
			op.result.body, op.result.gone = "", true
		} else {
			op.result.body, op.result.edited = strings.clone(op.body, a), edited
		}
	}
	return db.write(op)
}

// The lobby, into an empty store.
seed :: proc() {
	list := make([dynamic]m.Room, context.temp_allocator)
	if rooms(&list) == .None && len(list) == 0 { _, _ = create_room("lobby", "Lobby") }
}

// ---- helpers ------------------------------------------------------------------------------

// On the writer: the room's next version.
@(private)
bump :: proc(room_id: i64) -> (ver: i64, err: m.Error) {
	st := db.writer_stmt(SQL_BUMP)
	defer db.reset(st)
	db.bind_id(st, 1, room_id)
	if !db.next_row(st, &err) { return 0, err if err != .None else .Not_Found }
	return db.column_id(st, 0), .None
}

@(private)
state :: proc(room_id: i64) -> (ver, dropped, dropped_ver: i64, err: m.Error) {
	q := db.read(SQL_ROOM_STATE)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	if !db.next_row(q, &err) { return 0, 0, 0, err if err != .None else .Not_Found }
	return db.column_id(q, 0), db.column_id(q, 1), db.column_id(q, 2), .None
}

@(private)
one_room :: proc(q: db.Stmt) -> m.Room {
	return {id = db.column_id(q, 0), slug = db.clone_col(q, 1), name = db.clone_col(q, 2), at = db.column_id(q, 3)}
}

// Its strings in `a`: the request's arena on a loop, the op's own memory on the writer.
@(private)
one_msg :: proc(q: db.Stmt, a := context.temp_allocator) -> m.Message {
	return {
		id = db.column_id(q, 0), room = db.column_id(q, 1), author = u64(db.column_id(q, 2)), name = db.clone_col(q, 3, a),
		body = db.clone_col(q, 4, a), at = db.column_id(q, 5), edited = db.column_id(q, 6), gone = db.column_int(q, 7) != 0,
		ver = db.column_id(q, 8),
	}
}

@(private)
now :: proc() -> i64 { return time.time_to_unix(time.now()) }
