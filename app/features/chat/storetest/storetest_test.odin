package chat_storetest

// ---- the chat store contract, run against both families (D37) ---------------------------
//
// One test binary imports both stores and holds each to what both promise: the lobby goes into
// an empty store, a taken slug is refused, a post answers its stored message with the room's
// next version, recent is oldest first, count_after and after count and serve past a cursor,
// changed serves past a version, and only the author edits or deletes, inside the window, a
// delete leaving a tombstone. What the ring keeps and lets go is the memory store's own test; the
// SQLite store keeps every message, with ids that are rowids.

import "base:runtime"
import "core:nbio"
import "core:strings"
import "core:testing"
import "core:time"

import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import mem "../../../stores/memory/chat"
import sql "../../../stores/sqlite/chat"

@(private = "file")
Family :: struct {
	name:        string,
	init:        m.Store_Init,
	seed:        m.Store_Seed,
	room:        m.Store_Room,
	create_room: m.Store_Create_Room,
	recent:      m.Store_Recent,
	after:       m.Store_After,
	count_after: m.Store_Count_After,
	changed:     m.Store_Changed,
	message:     m.Store_Message,
	post:        m.Store_Post,
	change:      m.Store_Change,
}

@(private = "file")
answered: int

@(private = "file")
last: m.Message

@(private = "file")
last_err: m.Error

// What `done` saw, copied out: on SQLite it runs from the loop's callback, whose temp memory goes
// when it returns.
@(private = "file")
name_buf, body_buf: [64]byte

@(private = "file")
keep :: proc(msg: m.Message) {
	last = msg
	last.name = string(name_buf[:copy(name_buf[:], msg.name)])
	last.body = string(body_buf[:copy(body_buf[:], msg.body)])
}

@(private = "file")
wait :: proc(t: ^testing.T, f: Family, before: int) {
	deadline := time.tick_now()
	for answered == before && time.tick_since(deadline) < 5 * time.Second { nbio.tick(10 * time.Millisecond) }
	testing.expectf(t, answered == before + 1, "%s: the write answered", f.name)
}

@(private = "file")
DONE :: proc(o: ^store.Op) {
	answered += 1
	last_err = o.err
	store.free_op(o)
}

@(private = "file")
say :: proc(t: ^testing.T, f: Family, room: i64, author: u64, body: string) -> m.Message {
	op := store.new_op(m.Post, 2 * (len(body) + 8))
	a := store.op_allocator(op)
	op.room, op.author, op.name, op.body = room, author, strings.clone("ann", a), strings.clone(body, a)
	op.done = proc(o: ^store.Op) {
		p := (^m.Post)(o)
		last_err = o.err
		keep(p.result)
		answered += 1
		store.free_op(o)
	}
	before := answered
	testing.expectf(t, f.post(op), "%s: post accepted", f.name)
	wait(t, f, before)
	return last
}

@(private = "file")
alter :: proc(t: ^testing.T, f: Family, id: i64, author: u64, body: string, delete: bool) -> (m.Message, m.Error) {
	op := store.new_op(m.Change, 2 * len(body) + 16)
	op.id, op.author, op.body, op.delete, op.window = id, author, strings.clone(body, store.op_allocator(op)), delete, 600
	op.done = proc(o: ^store.Op) {
		p := (^m.Change)(o)
		last_err = o.err
		keep(p.result)
		answered += 1
		store.free_op(o)
	}
	before := answered
	testing.expectf(t, f.change(op), "%s: change accepted", f.name)
	wait(t, f, before)
	return last, last_err
}

@(private = "file")
conforms :: proc(t: ^testing.T, f: Family) {
	f.init(0)
	f.seed()
	f.seed() // into an empty store only
	lobby, err := f.room("lobby")
	testing.expectf(t, err == .None && lobby.name == "Lobby", "%s: the lobby, %v", f.name, err)
	_, err = f.create_room("lobby", "Again")
	testing.expectf(t, err == .Constraint, "%s: a taken slug, %v", f.name, err)
	side, serr := f.create_room("side", "Side")
	testing.expectf(t, serr == .None && side.slug == "side", "%s: a new room, %v", f.name, serr)

	first := say(t, f, lobby.id, 7, "first")
	testing.expectf(t, last_err == .None && first.body == "first" && first.name == "ann" && first.id > 0 && first.room == lobby.id, "%s: post = %v", f.name, first)
	for _ in 0 ..< 5 { say(t, f, lobby.id, 8, "more") }
	newest := say(t, f, lobby.id, 8, "newest")
	testing.expectf(t, newest.ver > first.ver && newest.id > first.id, "%s: versions and ids grow", f.name)
	say(t, f, side.id, 9, "elsewhere")

	msgs := make([dynamic]m.Message, context.temp_allocator)
	testing.expect_value(t, f.recent(lobby.id, 3, &msgs), m.Error.None)
	testing.expectf(t, len(msgs) == 3 && msgs[0].id < msgs[2].id && msgs[2].body == "newest", "%s: recent(3), oldest first: %v", f.name, msgs[:])
	testing.expect_value(t, f.count_after(lobby.id, first.id), 6)

	clear(&msgs)
	reached, aerr := f.after(lobby.id, first.id, &msgs)
	testing.expectf(t, aerr == .None && reached && len(msgs) == 6, "%s: after(first) = %d, %v", f.name, len(msgs), reached)

	clear(&msgs)
	ver, creached, cerr := f.changed(lobby.id, newest.ver - 2, &msgs)
	testing.expectf(t, cerr == .None && creached && len(msgs) == 2 && ver == newest.ver, "%s: changed = %d, ver %d", f.name, len(msgs), ver)

	// Only the author edits, inside the window; a delete leaves a tombstone, as an upsert would.
	_, eerr := alter(t, f, newest.id, 7, "nope", false)
	testing.expectf(t, eerr == .Constraint, "%s: someone else's edit, %v", f.name, eerr)
	edited, e2 := alter(t, f, newest.id, 8, "edited", false)
	testing.expectf(t, e2 == .None && edited.body == "edited" && edited.edited > 0 && edited.ver > newest.ver, "%s: an edit = %v", f.name, edited)
	gone, e3 := alter(t, f, newest.id, 8, "", true)
	testing.expectf(t, e3 == .None && gone.gone && gone.ver > edited.ver, "%s: a delete = %v", f.name, gone)
	msg, _ := f.message(newest.id)
	testing.expectf(t, msg.body == "" && msg.gone, "%s: the tombstone keeps its id", f.name)
	_, e4 := alter(t, f, newest.id, 8, "again", false)
	testing.expectf(t, e4 == .Not_Found, "%s: a deleted message isn't edited, %v", f.name, e4)
	_, e5 := alter(t, f, 1 << 40, 8, "x", false)
	testing.expectf(t, e5 == .Not_Found, "%s: no such message, %v", f.name, e5)
}

// One test, in order: the stores are process-wide.
@(test)
both_families :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()

	conforms(t, {"memory", mem.init, mem.seed, mem.room, mem.create_room, mem.recent, mem.after, mem.count_after, mem.changed, mem.message, mem.post, mem.change})

	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("chat", sql.MIGRATIONS[:])
	conforms(t, {"sqlite", sql.init, sql.seed, sql.room, sql.create_room, sql.recent, sql.after, sql.count_after, sql.changed, sql.message, sql.post, sql.change})
	free_all(context.temp_allocator)
}
