package chat_store_sqlite

// ---- chat in SQLite (PLAN §14.1, D30; M6) ----------------------------------------------------
//
// Rooms and messages kept across restarts: ids are rowids, so a page resumes a room's topic from
// `@<rowid>` after a restart too (PERSISTED, D13). Reads on the loop's reader; a post or a change
// goes through the writer task, which bumps the room's version and reads the row back in the same
// batch, so the caller answers with exactly what was stored. Rooms, DMs and memberships are made
// at once (write_now, rare and small): the caller answers with the room.
//
// Retention (§14.1, D16): a post trims its room past its kind's cap in the post's own batch, every
// `trim_every` inserts (50 at the defaults, so a delete is amortised; every one under a small
// cap), and the 60 s sweep lets go of what is past its kind's age, both 1000 rows a transaction at
// most and pinned messages never. Each moves the room's `dropped` and `dropped_ver` first, which
// say a cursor below them can't be served whole.

import "base:runtime"
import "core:fmt"
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
	{2, "0002_rooms.sql", #load("migrations/0002_rooms.sql", string)},
	{3, "0003_retention.sql", #load("migrations/0003_retention.sql", string)},
	{4, "0004_moderation.sql", #load("migrations/0004_moderation.sql", string)},
	{5, "0005_fts.sql", #load("migrations/0005_fts.sql", string)},
	{6, "0006_images.sql", #load("migrations/0006_images.sql", string)},
	{7, "0007_blocks.sql", #load("migrations/0007_blocks.sql", string)},
	{8, "0008_reports.sql", #load("migrations/0008_reports.sql", string)},
}

@(private) ROOM_COLS :: "id, slug, name, at, kind, owner, dropped, locked, slow"
@(private) MSG_COLS :: "id, room, author, name, body, at, edited, gone, ver, blob"
@(private) SQL_ROOMS :: "SELECT " + ROOM_COLS + " FROM chat_rooms ORDER BY id"
@(private) SQL_ROOMS_FOR :: "SELECT " + ROOM_COLS + " FROM chat_rooms WHERE kind IN (0, 2) OR id IN (SELECT room FROM chat_members WHERE who = ?) ORDER BY id"
@(private) SQL_ROOM :: "SELECT " + ROOM_COLS + " FROM chat_rooms WHERE slug = ?"
@(private) SQL_ROOM_COUNT :: "SELECT count(*) FROM chat_rooms WHERE kind <> 3" // a DM's a pair's, and takes no one's room
@(private) SQL_ROOM_OF :: "SELECT " + ROOM_COLS + " FROM chat_rooms WHERE id = ?"
@(private) SQL_ROOMS_OWNED :: "SELECT count(*) FROM chat_rooms WHERE owner = ? AND kind <> 3"
@(private) SQL_ADD_ROOM :: "INSERT INTO chat_rooms(slug, name, at, kind, owner, dm) VALUES(?, ?, ?, ?, ?, ?)"
@(private) SQL_DM :: "SELECT " + ROOM_COLS + " FROM chat_rooms WHERE dm = ?"
@(private) SQL_MEMBERS :: "SELECT room, who, name, at FROM chat_members WHERE room = ? ORDER BY who = (SELECT owner FROM chat_rooms WHERE id = room) DESC, at, who"
@(private) SQL_IS_MEMBER :: "SELECT 1 FROM chat_members WHERE room = ? AND who = ?"
@(private) SQL_JOIN :: "INSERT INTO chat_members(room, who, name, at) VALUES(?, ?, ?, ?) ON CONFLICT DO NOTHING"
@(private) SQL_LEAVE :: "DELETE FROM chat_members WHERE room = ? AND who = ?"
@(private) INVITE_COLS :: "id, room, hash, made_by, by_name, at, expires, max_uses, uses, revoked"
@(private) OPEN :: "revoked = 0 AND expires > ? AND (max_uses = 0 OR uses < max_uses)"
@(private) SQL_ADD_INVITE :: "INSERT INTO chat_invites(room, hash, made_by, by_name, at, expires, max_uses) VALUES(?, ?, ?, ?, ?, ?, ?)"
@(private) SQL_INVITE :: "SELECT " + INVITE_COLS + " FROM chat_invites WHERE id = ?"
@(private) SQL_INVITES :: "SELECT " + INVITE_COLS + " FROM chat_invites WHERE room = ? AND " + OPEN + " ORDER BY id DESC"
@(private) SQL_REVOKE :: "UPDATE chat_invites SET revoked = ? WHERE id = ? AND room = ? AND revoked = 0"
@(private) SQL_OPEN_ROOM :: "SELECT room FROM chat_invites WHERE id = ? AND " + OPEN
@(private) SQL_COUNT_USE :: "UPDATE chat_invites SET uses = uses + 1 WHERE id = ?"
@(private) SQL_ROOM_STATE :: "SELECT ver, dropped, dropped_ver FROM chat_rooms WHERE id = ?"
@(private) SQL_RECENT :: "SELECT " + MSG_COLS + " FROM (SELECT " + MSG_COLS + " FROM chat_messages WHERE room = ? ORDER BY id DESC LIMIT ?) ORDER BY id"
@(private) SQL_AFTER :: "SELECT " + MSG_COLS + " FROM chat_messages WHERE room = ? AND id > ? ORDER BY id"
@(private) SQL_COUNT_AFTER :: "SELECT count(*) FROM chat_messages WHERE room = ? AND id > ?"
@(private) SQL_CHANGED :: "SELECT " + MSG_COLS + " FROM chat_messages WHERE room = ? AND ver > ? ORDER BY id"
@(private) SQL_MESSAGE :: "SELECT " + MSG_COLS + " FROM chat_messages WHERE id = ?"
@(private) SQL_BUMP :: "UPDATE chat_rooms SET ver = ver + 1 WHERE id = ? RETURNING ver, kind"
@(private) CHUNK :: 1000
@(private) PAST_CAP :: "SELECT id, ver FROM chat_messages WHERE room = ? AND pinned = 0 ORDER BY id DESC LIMIT 1000 OFFSET ?"
@(private) SQL_PAST_CAP :: "SELECT max(id), max(ver), count(*) FROM (" + PAST_CAP + ")"
@(private) SQL_TRIM :: "DELETE FROM chat_messages WHERE id IN (SELECT id FROM (" + PAST_CAP + "))"
@(private) PAST_AGE :: "SELECT m.room AS room, m.id AS id, m.ver AS ver FROM chat_messages m JOIN chat_rooms r ON r.id = m.room WHERE r.kind = ? AND m.pinned = 0 AND m.at < ? ORDER BY m.id LIMIT 1000"
@(private) SQL_PAST_AGE :: "SELECT room, max(id), max(ver), count(*) FROM (" + PAST_AGE + ") GROUP BY room"
@(private) SQL_AGE_OUT :: "DELETE FROM chat_messages WHERE id IN (SELECT id FROM (" + PAST_AGE + "))"
@(private) SQL_SEARCH :: "SELECT m.id, m.room, m.author, m.name, m.body, m.at, m.edited, m.gone, m.ver, m.blob, r.id, r.slug, r.name, r.at, r.kind, r.owner, r.dropped, r.locked, r.slow " +
	"FROM chat_fts f JOIN chat_messages m ON m.id = f.rowid JOIN chat_rooms r ON r.id = m.room " +
	"WHERE chat_fts MATCH ? AND m.gone = 0 " +
	"AND (r.kind IN (0, 2) OR EXISTS (SELECT 1 FROM chat_members c WHERE c.room = r.id AND c.who = ?)) " +
	"AND NOT EXISTS (SELECT 1 FROM chat_bans b WHERE b.room = r.id AND b.who = ? AND b.kind = 1 AND b.until > ?) " +
	"ORDER BY m.id DESC LIMIT ?"
@(private) SQL_SAVE :: "SAVEPOINT op"
@(private) SQL_UNDO :: "ROLLBACK TO op"
@(private) SQL_RELEASE :: "RELEASE op"
@(private) SQL_SET_ROOM :: "UPDATE chat_rooms SET locked = ?, slow = ? WHERE id = ?"
@(private) SQL_BAN :: "INSERT INTO chat_bans(room, who, kind, until, made_by) VALUES(?, ?, ?, ?, ?) ON CONFLICT(room, who, kind) DO UPDATE SET until = excluded.until, made_by = excluded.made_by"
@(private) SQL_BANNED :: "SELECT until FROM chat_bans WHERE room = ? AND who = ? AND kind = ? AND until > ?"
@(private) REPORT_COLS :: "id, room, msg, author, author_name, body, made_by, by_name, reason, at, resolved, outcome, blob"
@(private) SQL_REPORT :: "INSERT INTO chat_reports(room, msg, author, author_name, body, made_by, by_name, reason, at, blob) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING"
@(private) SQL_REPORTS :: "SELECT " + REPORT_COLS + " FROM chat_reports WHERE resolved = 0 ORDER BY id LIMIT ?"
@(private) SQL_REPORTS_THEIRS :: "SELECT count(*) FROM chat_reports WHERE resolved = 0 AND made_by = ?"
@(private) SQL_REPORTS_ALL :: "SELECT count(*) FROM chat_reports WHERE resolved = 0"
@(private) SQL_REPORT_OF :: "SELECT " + REPORT_COLS + " FROM chat_reports WHERE id = ?"
@(private) SQL_RESOLVE :: "UPDATE chat_reports SET resolved = ?, outcome = ?, body = '', blob = '' WHERE id = ? AND resolved = 0"
@(private) SQL_BLOB_HELD :: "SELECT EXISTS(SELECT 1 FROM chat_messages WHERE blob = ?1) OR EXISTS(SELECT 1 FROM chat_reports WHERE blob = ?1 AND resolved = 0)"
@(private) SQL_HOLDING :: "SELECT " + MSG_COLS + " FROM chat_messages WHERE blob = ?"
@(private) SQL_UNBLOB :: "UPDATE chat_messages SET blob = '', ver = ? WHERE id = ?"
@(private) SQL_UNBLOB_REPORTS :: "UPDATE chat_reports SET blob = '' WHERE blob = ?"
@(private) SQL_BLOCK :: "INSERT INTO chat_blocks(who, other, name, at) VALUES(?, ?, ?, ?) ON CONFLICT DO NOTHING"
@(private) SQL_UNBLOCK :: "DELETE FROM chat_blocks WHERE who = ? AND other = ?"
@(private) SQL_BLOCKING :: "SELECT 1 FROM chat_blocks WHERE who = ? AND other = ?"
@(private) SQL_BLOCKS :: "SELECT other, name, at FROM chat_blocks WHERE who = ? ORDER BY at DESC, other"
@(private) SQL_DROPPED :: "UPDATE chat_rooms SET dropped = max(dropped, ?), dropped_ver = max(dropped_ver, ?) WHERE id = ?"
@(private) SQL_POST :: "INSERT INTO chat_messages(room, author, name, body, at, ver, blob) VALUES(?, ?, ?, ?, ?, ?, ?)"
@(private) SQL_EDIT :: "UPDATE chat_messages SET body = ?, edited = ?, ver = ? WHERE id = ?"
@(private) SQL_DELETE :: "UPDATE chat_messages SET body = '', blob = '', gone = 1, ver = ? WHERE id = ?"

// What each kind keeps, set at boot before the writer starts; the writer's own count of inserts
// per room since boot, which `trim_every` reads (the writer is one thread).
@(private) keep: m.Retention
@(private) inserts: map[i64]int

// SQLite keeps no ring of its own: the page cache is it.
init :: proc(ring_bytes: int, retention: m.Retention) { keep = retention }

// How often a room capped at `cap` is trimmed: every tenth of its cap, between 1 and 50 inserts.
trim_every :: proc(cap: int) -> int { return clamp(cap / 10, 1, 50) }

rooms :: proc(out: ^[dynamic]m.Room) -> (err: m.Error) {
	q := db.read(SQL_ROOMS)
	defer db.reset(q)
	for db.next_row(q, &err) { append(out, one_room(q)) }
	return
}

rooms_for :: proc(who: u64, out: ^[dynamic]m.Room) -> (err: m.Error) {
	q := db.read(SQL_ROOMS_FOR)
	defer db.reset(q)
	db.bind_id(q, 1, i64(who))
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

// write_now's run takes no arguments: what it works on is here. write_now runs it on the caller's
// own thread, so a loop's is its own while another loop makes a room too.
@(private, thread_local) making: struct {
	ban:        m.Ban,
	report:     m.Report,
	audit:      m.Audit,
	invite:     m.Invite,
	now:        i64,
	slug, name: string,
	kind:       m.Room_Kind,
	owner:      u64,
	dm:         string,
	members:    [2]m.Member,
	n_members:  int,
	room:       m.Room,
	err:        m.Error,
}

// .Constraint: the slug is taken, or the rooms are full.
create_room :: proc(slug, name: string, kind: m.Room_Kind, owner: u64, owner_name: string) -> (m.Room, m.Error) {
	members := kind == .Private || kind == .Dm
	making = {slug = slug, name = name, kind = kind, owner = owner, n_members = 1 if members else 0}
	making.members[0] = {who = owner, name = owner_name}
	if !db.write_now(make_room) { return {}, making.err if making.err != .None else .Failed }
	return making.room, .None
}

// The DM of `a` and `b`, or a new one with both as members.
dm :: proc(a: u64, a_name: string, b: u64, b_name: string, slug: string) -> (m.Room, m.Error) {
	making = {slug = slug, name = fmt.tprintf("%s and %s", a_name, b_name), kind = .Dm, owner = a, n_members = 2}
	making.dm = fmt.tprintf("%d:%d", min(a, b), max(a, b))
	making.members = {{who = a, name = a_name}, {who = b, name = b_name}}
	ok := db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_DM)
		db.bind_text(q, 1, making.dm)
		found := db.next_row(q, &making.err)
		if found { making.room = one_room(q) }
		db.reset(q)
		if found { return true }
		if making.err != .None { return false }
		return make_room()
	})
	if !ok { return {}, making.err if making.err != .None else .Failed }
	return making.room, .None
}

// On the writer, inside write_now: `making`'s room and its members.
@(private)
make_room :: proc() -> bool {
	c := db.writer_stmt(SQL_ROOM_COUNT)
	n := db.column_int(c, 0) if db.next_row(c, &making.err) else MAX_ROOMS
	db.reset(c)
	if n >= MAX_ROOMS {
		making.err = .Constraint
		return false
	}
	at := now()
	st := db.writer_stmt(SQL_ADD_ROOM)
	db.bind_text(st, 1, making.slug)
	db.bind_text(st, 2, making.name)
	db.bind_id(st, 3, at)
	db.bind_int(st, 4, int(making.kind))
	db.bind_id(st, 5, i64(making.owner))
	if making.dm != "" { db.bind_text(st, 6, making.dm) } else { db.bind_null(st, 6) }
	making.err = db.step_done(st)
	db.reset(st)
	if making.err != .None { return false }
	id := db.last_insert_id()
	for mem in making.members[:making.n_members] {
		if making.err = add_member(id, mem.who, mem.name, at); making.err != .None { return false }
	}
	making.room = {
		id = id, slug = strings.clone(making.slug, context.temp_allocator), name = strings.clone(making.name, context.temp_allocator),
		at = at, kind = making.kind, owner = making.owner,
	}
	return true
}

@(private)
add_member :: proc(room_id: i64, who: u64, name: string, at: i64) -> m.Error {
	st := db.writer_stmt(SQL_JOIN)
	defer db.reset(st)
	db.bind_id(st, 1, room_id)
	db.bind_id(st, 2, i64(who))
	db.bind_text(st, 3, name)
	db.bind_id(st, 4, at)
	return db.step_done(st)
}

members :: proc(room_id: i64, out: ^[dynamic]m.Member) -> (err: m.Error) {
	q := db.read(SQL_MEMBERS)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	for db.next_row(q, &err) {
		append(out, m.Member{room = db.column_id(q, 0), who = u64(db.column_id(q, 1)), name = db.clone_col(q, 2), at = db.column_id(q, 3)})
	}
	return
}

is_member :: proc(room_id: i64, who: u64) -> bool {
	q := db.read(SQL_IS_MEMBER)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	db.bind_id(q, 2, i64(who))
	err: m.Error
	return db.next_row(q, &err)
}

// .None when they are in it already.
join :: proc(room_id: i64, who: u64, name: string) -> m.Error {
	making = {}
	making.members[0] = {room = room_id, who = who, name = name}
	ok := db.write_now(proc() -> bool {
		j := making.members[0]
		making.err = add_member(j.room, j.who, j.name, now())
		return making.err == .None
	})
	return .None if ok else making.err if making.err != .None else .Failed
}

leave :: proc(room_id: i64, who: u64) -> m.Error {
	making = {}
	making.members[0] = {room = room_id, who = who}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_LEAVE)
		defer db.reset(st)
		db.bind_id(st, 1, making.members[0].room)
		db.bind_id(st, 2, i64(making.members[0].who))
		making.err = db.step_done(st)
		return making.err == .None
	})
	return .None if ok else making.err if making.err != .None else .Failed
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

room_of :: proc(id: i64) -> (r: m.Room, err: m.Error) {
	q := db.read(SQL_ROOM_OF)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return one_room(q), .None
}

rooms_owned :: proc(owner: u64) -> int {
	q := db.read(SQL_ROOMS_OWNED)
	defer db.reset(q)
	db.bind_id(q, 1, i64(owner))
	err: m.Error
	return db.column_int(q, 0) if db.next_row(q, &err) else 0
}

post :: proc(op: ^m.Post) -> bool {
	op.run = proc(o: ^store.Op) { unit(o, post_run) }
	return db.write(op)
}

@(private)
post_run :: proc(o: ^store.Op) {
	op := (^m.Post)(o)
	ver: i64
	kind: m.Room_Kind
	if ver, kind, o.err = bump(op.room); o.err != .None { return }
	at := now()
	st := db.writer_stmt(SQL_POST)
	db.bind_id(st, 1, op.room)
	db.bind_id(st, 2, i64(op.author))
	db.bind_text(st, 3, op.name)
	db.bind_text(st, 4, op.body)
	db.bind_id(st, 5, at)
	db.bind_id(st, 6, ver)
	db.bind_text(st, 7, op.blob)
	o.err = db.step_done(st)
	db.reset(st)
	if o.err != .None { return }
	a := store.op_allocator(o)
	op.result = {id = db.last_insert_id(), room = op.room, author = op.author, name = strings.clone(op.name, a), body = strings.clone(op.body, a), blob = strings.clone(op.blob, a), at = at, ver = ver}
	if inserts == nil { inserts = make(map[i64]int, runtime.heap_allocator()) }
	inserts[op.room] += 1
	if keep.cap[kind] > 0 && inserts[op.room] % trim_every(keep.cap[kind]) == 0 { o.err = trim(op.room, keep.cap[kind]) }
}

// On the writer: room's unpinned messages past its newest `cap`, a chunk at most, after its
// `dropped` says so.
@(private)
trim :: proc(room_id: i64, cap: int) -> (err: m.Error) {
	q := db.writer_stmt(SQL_PAST_CAP)
	db.bind_id(q, 1, room_id)
	db.bind_int(q, 2, cap)
	has := db.next_row(q, &err) && db.column_int(q, 2) > 0
	newest, newest_ver := db.column_id(q, 0), db.column_id(q, 1)
	db.reset(q)
	if !has { return }
	dropped(room_id, newest, newest_ver) or_return
	st := db.writer_stmt(SQL_TRIM)
	defer db.reset(st)
	db.bind_id(st, 1, room_id)
	db.bind_int(st, 2, cap)
	return db.step_done(st)
}

@(private)
dropped :: proc(room_id, newest, newest_ver: i64) -> m.Error {
	st := db.writer_stmt(SQL_DROPPED)
	defer db.reset(st)
	db.bind_id(st, 1, newest)
	db.bind_id(st, 2, newest_ver)
	db.bind_id(st, 3, room_id)
	return db.step_done(st)
}

// What `sweep` works on: write_now runs on the job's own thread.
@(private, thread_local) sweeping: struct {
	kind:    m.Room_Kind,
	cutoff:  i64,
	removed: int,
	err:     m.Error,
}

// Every room's messages past its kind's age, a chunk a transaction, until a chunk comes up short.
sweep :: proc(at: i64) -> (removed: int, err: m.Error) {
	for kind in m.Room_Kind {
		if keep.age[kind] <= 0 { continue }
		for {
			sweeping = {kind = kind, cutoff = at - keep.age[kind]}
			ok := db.write_now(proc() -> bool {
				q := db.writer_stmt(SQL_PAST_AGE)
				db.bind_int(q, 1, int(sweeping.kind))
				db.bind_id(q, 2, sweeping.cutoff)
				for db.next_row(q, &sweeping.err) {
					sweeping.removed += db.column_int(q, 3)
					if sweeping.err = dropped(db.column_id(q, 0), db.column_id(q, 1), db.column_id(q, 2)); sweeping.err != .None { break }
				}
				db.reset(q)
				if sweeping.err != .None { return false }
				if sweeping.removed == 0 { return true }
				st := db.writer_stmt(SQL_AGE_OUT)
				defer db.reset(st)
				db.bind_int(st, 1, int(sweeping.kind))
				db.bind_id(st, 2, sweeping.cutoff)
				sweeping.err = db.step_done(st)
				return sweeping.err == .None
			})
			if !ok { return removed, sweeping.err if sweeping.err != .None else .Failed }
			removed += sweeping.removed
			if sweeping.removed < CHUNK { break }
		}
	}
	return removed, .None
}

// An edit or a delete of the author's own message inside `window`: .Not_Found for none or one
// deleted, .Constraint for someone else's or one too old. A moderator's (`moderated`) takes any,
// and its audit entry is one more statement of the unit.
change :: proc(op: ^m.Change) -> bool {
	op.run = proc(o: ^store.Op) { unit(o, change_run) }
	return db.write(op)
}

@(private)
change_run :: proc(o: ^store.Op) {
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
	case !op.moderated && (msg.author != op.author || now() - msg.at > op.window):
		o.err = .Constraint
		return
	}
	ver: i64
	if ver, _, o.err = bump(msg.room); o.err != .None { return }
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
		op.released = msg.blob
		op.result.body, op.result.blob, op.result.gone = "", "", true
	} else {
		op.result.body, op.result.edited = strings.clone(op.body, a), edited
	}
	if op.moderated { o.err = note(op.audit) }
}

// An op of several statements fails as one, as the accounts store's (M4-06): SQLite undoes only
// the failing statement, and the batch's transaction would commit the rest.
@(private)
unit :: proc(o: ^store.Op, run: proc(o: ^store.Op)) {
	exec(SQL_SAVE)
	run(o)
	if o.err != .None { exec(SQL_UNDO) }
	exec(SQL_RELEASE)
}

@(private)
exec :: proc(sql: string) {
	st := db.writer_stmt(sql)
	_ = db.step_done(st)
	db.reset(st)
}

// ---- search --------------------------------------------------------------------------------

// Each word quoted, so nothing a member types is FTS5 syntax; the last also matches as a prefix.
@(private)
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
		if i == len(words) - 1 { strings.write_byte(&b, '*') }
	}
	return strings.to_string(b)
}

search :: proc(who: u64, words: []string, at: i64, limit: int, out: ^[dynamic]m.Hit) -> (err: m.Error) {
	if len(words) == 0 { return }
	q := db.read(SQL_SEARCH)
	defer db.reset(q)
	db.bind_text(q, 1, fts_query(words))
	db.bind_id(q, 2, i64(who))
	db.bind_id(q, 3, i64(who))
	db.bind_id(q, 4, at)
	db.bind_int(q, 5, limit)
	for db.next_row(q, &err) {
		kind, _ := store.enum_from_int(m.Room_Kind, db.column_int(q, 14))
		append(out, m.Hit{
			msg = one_msg(q),
			room = {
				id = db.column_id(q, 10), slug = db.clone_col(q, 11), name = db.clone_col(q, 12), at = db.column_id(q, 13), kind = kind,
				owner = u64(db.column_id(q, 15)), dropped = db.column_id(q, 16), locked = db.column_int(q, 17) != 0, slow = db.column_int(q, 18),
			},
		})
	}
	return
}

// ---- moderation ----------------------------------------------------------------------------

@(private) audit_writer: m.Audit_Writer

set_audit_writer :: proc(w: m.Audit_Writer) { audit_writer = w }

// On the writer, inside the change's transaction: its audit entry, whose failure undoes the change.
@(private)
note :: proc(a: m.Audit) -> m.Error {
	if a.action == "" || audit_writer == nil { return .None }
	return audit_writer(a.actor_id, a.actor_name, a.client, a.action, a.target_kind, a.target_id, a.reason, a.meta)
}

set_room :: proc(room_id: i64, locked: bool, slow: int, audit: m.Audit) -> m.Error {
	making = {}
	making.room = {id = room_id, locked = locked, slow = slow}
	making.audit = audit
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_SET_ROOM)
		db.bind_int(st, 1, 1 if making.room.locked else 0)
		db.bind_int(st, 2, making.room.slow)
		db.bind_id(st, 3, making.room.id)
		making.err = db.step_done(st)
		db.reset(st)
		if making.err == .None && db.changes() == 0 { making.err = .Not_Found }
		if making.err == .None { making.err = note(making.audit) }
		return making.err == .None
	})
	return .None if ok else making.err if making.err != .None else .Failed
}

ban :: proc(b: m.Ban, audit: m.Audit) -> m.Error {
	making = {ban = b, audit = audit}
	ok := db.write_now(proc() -> bool {
		b := making.ban
		st := db.writer_stmt(SQL_BAN)
		db.bind_id(st, 1, b.room)
		db.bind_id(st, 2, i64(b.who))
		db.bind_int(st, 3, int(b.kind))
		db.bind_id(st, 4, b.until)
		db.bind_id(st, 5, i64(b.by))
		making.err = db.step_done(st)
		db.reset(st)
		if making.err == .None { making.err = note(making.audit) }
		return making.err == .None
	})
	return .None if ok else making.err if making.err != .None else .Failed
}

banned :: proc(room_id: i64, who: u64, kind: m.Ban_Kind, at: i64) -> (until: i64) {
	q := db.read(SQL_BANNED)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	db.bind_id(q, 2, i64(who))
	db.bind_int(q, 3, int(kind))
	db.bind_id(q, 4, at)
	err: m.Error
	return db.column_id(q, 0) if db.next_row(q, &err) else 0
}

report :: proc(r: m.Report) -> (id: i64, err: m.Error) {
	making = {report = r}
	ok := db.write_now(proc() -> bool {
		r := making.report
		st := db.writer_stmt(SQL_REPORT)
		defer db.reset(st)
		db.bind_id(st, 1, r.room)
		db.bind_id(st, 2, r.msg)
		db.bind_id(st, 3, i64(r.author))
		db.bind_text(st, 4, r.author_name)
		db.bind_text(st, 5, r.body)
		db.bind_id(st, 6, i64(r.by))
		db.bind_text(st, 7, r.by_name)
		db.bind_text(st, 8, r.reason)
		db.bind_id(st, 9, r.at)
		db.bind_text(st, 10, r.blob)
		if making.err = db.step_done(st); making.err != .None { return false }
		making.report.id = db.last_insert_id() if db.changes() > 0 else 0
		return true
	})
	if !ok { return 0, making.err if making.err != .None else .Failed }
	return making.report.id, .None
}

reports :: proc(limit: int, out: ^[dynamic]m.Report) -> (err: m.Error) {
	q := db.read(SQL_REPORTS)
	defer db.reset(q)
	db.bind_int(q, 1, limit)
	for db.next_row(q, &err) { append(out, one_report(q)) }
	return
}

open_reports :: proc(by: u64) -> (theirs, all: int) {
	err: m.Error
	q := db.read(SQL_REPORTS_THEIRS)
	db.bind_id(q, 1, i64(by))
	if db.next_row(q, &err) { theirs = db.column_int(q, 0) }
	db.reset(q)
	q = db.read(SQL_REPORTS_ALL)
	if db.next_row(q, &err) { all = db.column_int(q, 0) }
	db.reset(q)
	return
}

report_of :: proc(id: i64) -> (r: m.Report, err: m.Error) {
	q := db.read(SQL_REPORT_OF)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return one_report(q), .None
}

resolve :: proc(id: i64, at: i64, outcome: string, audit: m.Audit) -> m.Error {
	making = {now = at, audit = audit}
	making.report = {id = id, outcome = outcome}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_RESOLVE)
		db.bind_id(st, 1, making.now)
		db.bind_text(st, 2, making.report.outcome)
		db.bind_id(st, 3, making.report.id)
		making.err = db.step_done(st)
		db.reset(st)
		if making.err == .None && db.changes() == 0 { making.err = .Not_Found }
		if making.err == .None { making.err = note(making.audit) }
		return making.err == .None
	})
	return .None if ok else making.err if making.err != .None else .Failed
}

@(private)
one_report :: proc(q: db.Stmt) -> m.Report {
	return {
		id = db.column_id(q, 0), room = db.column_id(q, 1), msg = db.column_id(q, 2), author = u64(db.column_id(q, 3)),
		author_name = db.clone_col(q, 4), body = db.clone_col(q, 5), by = u64(db.column_id(q, 6)), by_name = db.clone_col(q, 7),
		reason = db.clone_col(q, 8), at = db.column_id(q, 9), resolved = db.column_id(q, 10), outcome = db.clone_col(q, 11),
		blob = db.clone_col(q, 12),
	}
}

// ---- blobs ------------------------------------------------------------------------------------

@(private, thread_local) blobbing: struct {
	sha:  string,
	held: bool,
	audit: m.Audit,
	out:  ^[dynamic]m.Message,
	err:  m.Error,
}

// From the uploads sweep's thread too, which has no reader: on the writer's connection.
blob_held :: proc(sha256: string) -> bool {
	blobbing = {sha = sha256, held = true}
	_ = db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_BLOB_HELD)
		defer db.reset(q)
		db.bind_text(q, 1, blobbing.sha)
		if db.next_row(q, &blobbing.err) { blobbing.held = db.column_int(q, 0) != 0 }
		return blobbing.err == .None
	})
	return blobbing.held
}

purge_blob :: proc(sha256: string, audit: m.Audit, out: ^[dynamic]m.Message) -> m.Error {
	blobbing = {sha = sha256, audit = audit, out = out}
	ok := db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_HOLDING)
		db.bind_text(q, 1, blobbing.sha)
		for db.next_row(q, &blobbing.err) { append(blobbing.out, one_msg(q)) }
		db.reset(q)
		if blobbing.err != .None { return false }
		for &msg in blobbing.out {
			ver: i64
			if ver, _, blobbing.err = bump(msg.room); blobbing.err != .None { return false }
			st := db.writer_stmt(SQL_UNBLOB)
			db.bind_id(st, 1, ver)
			db.bind_id(st, 2, msg.id)
			blobbing.err = db.step_done(st)
			db.reset(st)
			if blobbing.err != .None { return false }
			msg.blob, msg.ver = "", ver
		}
		st := db.writer_stmt(SQL_UNBLOB_REPORTS)
		db.bind_text(st, 1, blobbing.sha)
		blobbing.err = db.step_done(st)
		db.reset(st)
		if blobbing.err != .None { return false }
		blobbing.err = note(blobbing.audit)
		return blobbing.err == .None
	})
	return .None if ok else blobbing.err if blobbing.err != .None else .Failed
}

// ---- blocks -----------------------------------------------------------------------------------

@(private, thread_local) blocking_: struct {
	who, other: u64,
	name:       string,
	at:         i64,
	err:        m.Error,
}

block :: proc(who, other: u64, name: string, at: i64) -> m.Error {
	blocking_ = {who = who, other = other, name = name, at = at}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_BLOCK)
		defer db.reset(st)
		db.bind_id(st, 1, i64(blocking_.who))
		db.bind_id(st, 2, i64(blocking_.other))
		db.bind_text(st, 3, blocking_.name)
		db.bind_id(st, 4, blocking_.at)
		blocking_.err = db.step_done(st)
		return blocking_.err == .None
	})
	return .None if ok else blocking_.err if blocking_.err != .None else .Failed
}

unblock :: proc(who, other: u64) -> m.Error {
	blocking_ = {who = who, other = other}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_UNBLOCK)
		defer db.reset(st)
		db.bind_id(st, 1, i64(blocking_.who))
		db.bind_id(st, 2, i64(blocking_.other))
		blocking_.err = db.step_done(st)
		return blocking_.err == .None
	})
	return .None if ok else blocking_.err if blocking_.err != .None else .Failed
}

blocking :: proc(who, other: u64) -> bool {
	q := db.read(SQL_BLOCKING)
	defer db.reset(q)
	db.bind_id(q, 1, i64(who))
	db.bind_id(q, 2, i64(other))
	err: m.Error
	return db.next_row(q, &err)
}

blocks :: proc(who: u64, out: ^[dynamic]m.Block) -> (err: m.Error) {
	q := db.read(SQL_BLOCKS)
	defer db.reset(q)
	db.bind_id(q, 1, i64(who))
	for db.next_row(q, &err) {
		append(out, m.Block{other = u64(db.column_id(q, 0)), name = db.clone_col(q, 1), at = db.column_id(q, 2)})
	}
	return
}

// ---- invites -------------------------------------------------------------------------------

add_invite :: proc(inv: m.Invite) -> (id: i64, err: m.Error) {
	making = {invite = inv}
	ok := db.write_now(proc() -> bool {
		i := making.invite
		st := db.writer_stmt(SQL_ADD_INVITE)
		defer db.reset(st)
		db.bind_id(st, 1, i.room)
		db.bind_text(st, 2, i.hash)
		db.bind_id(st, 3, i64(i.by))
		db.bind_text(st, 4, i.by_name)
		db.bind_id(st, 5, i.at)
		db.bind_id(st, 6, i.expires)
		db.bind_int(st, 7, i.max_uses)
		if making.err = db.step_done(st); making.err != .None { return false }
		making.invite.id = db.last_insert_id()
		return true
	})
	if !ok { return 0, making.err if making.err != .None else .Failed }
	return making.invite.id, .None
}

invite :: proc(id: i64) -> (inv: m.Invite, err: m.Error) {
	q := db.read(SQL_INVITE)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return one_invite(q), .None
}

invites :: proc(room_id: i64, at: i64, out: ^[dynamic]m.Invite) -> (err: m.Error) {
	q := db.read(SQL_INVITES)
	defer db.reset(q)
	db.bind_id(q, 1, room_id)
	db.bind_id(q, 2, at)
	for db.next_row(q, &err) { append(out, one_invite(q)) }
	return
}

revoke_invite :: proc(id, room_id, at: i64) -> m.Error {
	making = {now = at}
	making.invite = {id = id, room = room_id}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_REVOKE)
		defer db.reset(st)
		db.bind_id(st, 1, making.now)
		db.bind_id(st, 2, making.invite.id)
		db.bind_id(st, 3, making.invite.room)
		if making.err = db.step_done(st); making.err != .None { return false }
		if db.changes() == 0 { making.err = .Not_Found }
		return making.err == .None
	})
	return .None if ok else making.err if making.err != .None else .Failed
}

use_invite :: proc(id, at: i64, who: u64, name: string) -> m.Error {
	making = {now = at}
	making.invite = {id = id}
	making.members[0] = {who = who, name = name}
	ok := db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_OPEN_ROOM)
		db.bind_id(q, 1, making.invite.id)
		db.bind_id(q, 2, making.now)
		found := db.next_row(q, &making.err)
		room := db.column_id(q, 0) if found else 0
		db.reset(q)
		if !found {
			if making.err == .None { making.err = .Not_Found }
			return false
		}
		j := making.members[0]
		in_it := db.writer_stmt(SQL_IS_MEMBER)
		db.bind_id(in_it, 1, room)
		db.bind_id(in_it, 2, i64(j.who))
		already := db.next_row(in_it, &making.err)
		db.reset(in_it)
		if already || making.err != .None { return making.err == .None }
		if making.err = add_member(room, j.who, j.name, making.now); making.err != .None { return false }
		st := db.writer_stmt(SQL_COUNT_USE)
		defer db.reset(st)
		db.bind_id(st, 1, making.invite.id)
		making.err = db.step_done(st)
		return making.err == .None
	})
	return .None if ok else making.err if making.err != .None else .Failed
}

// The lobby, into an empty store.
seed :: proc() {
	list := make([dynamic]m.Room, context.temp_allocator)
	if rooms(&list) == .None && len(list) == 0 { _, _ = create_room("lobby", "Lobby", .Public, 0, "") }
}

// ---- helpers ------------------------------------------------------------------------------

// On the writer: the room's next version, and its kind.
@(private)
bump :: proc(room_id: i64) -> (ver: i64, kind: m.Room_Kind, err: m.Error) {
	st := db.writer_stmt(SQL_BUMP)
	defer db.reset(st)
	db.bind_id(st, 1, room_id)
	if !db.next_row(st, &err) { return 0, .Public, err if err != .None else .Not_Found }
	kind, _ = store.enum_from_int(m.Room_Kind, db.column_int(st, 1))
	return db.column_id(st, 0), kind, .None
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
	kind, _ := store.enum_from_int(m.Room_Kind, db.column_int(q, 4)) // an unknown kind reads as public
	return {
		id = db.column_id(q, 0), slug = db.clone_col(q, 1), name = db.clone_col(q, 2), at = db.column_id(q, 3),
		kind = kind, owner = u64(db.column_id(q, 5)), dropped = db.column_id(q, 6),
		locked = db.column_int(q, 7) != 0, slow = db.column_int(q, 8),
	}
}

@(private)
one_invite :: proc(q: db.Stmt) -> m.Invite {
	return {
		id = db.column_id(q, 0), room = db.column_id(q, 1), hash = db.clone_col(q, 2), by = u64(db.column_id(q, 3)),
		by_name = db.clone_col(q, 4), at = db.column_id(q, 5), expires = db.column_id(q, 6), max_uses = db.column_int(q, 7),
		uses = db.column_int(q, 8), revoked = db.column_id(q, 9),
	}
}

// Its strings in `a`: the request's arena on a loop, the op's own memory on the writer.
@(private)
one_msg :: proc(q: db.Stmt, a := context.temp_allocator) -> m.Message {
	return {
		id = db.column_id(q, 0), room = db.column_id(q, 1), author = u64(db.column_id(q, 2)), name = db.clone_col(q, 3, a),
		body = db.clone_col(q, 4, a), at = db.column_id(q, 5), edited = db.column_id(q, 6), gone = db.column_int(q, 7) != 0,
		ver = db.column_id(q, 8), blob = db.clone_col(q, 9, a),
	}
}

@(private)
now :: proc() -> i64 { return time.time_to_unix(time.now()) }
