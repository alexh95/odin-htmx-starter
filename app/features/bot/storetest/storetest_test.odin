package bot_storetest

// ---- the bot store contract, run against both families (D37) --------------------------------
//
// One test binary imports both stores and holds each to the same behaviour: a conversation and
// its turns are their owner's alone, turns come back oldest first with an answer's stats, a title
// given with a turn renames the conversation, and a member keeps their newest conversations and
// a conversation its last turns.

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
import mem "../../../stores/memory/bot"
import sql "../../../stores/sqlite/bot"

@(private = "file")
Family :: struct {
	name:          string,
	conversations: m.Store_Conversations,
	conversation:  m.Store_Conversation,
	turns:         m.Store_Turns,
	start:         m.Store_Start,
	append_turn:   m.Store_Append,
	keep, last:    int,
}

@(private = "file")
answered: int

@(private = "file")
last_conv: i64

@(private = "file")
last_err: m.Error

@(private = "file")
wait :: proc(t: ^testing.T, f: Family, before: int) {
	deadline := time.tick_now()
	for answered == before && time.tick_since(deadline) < 5 * time.Second { nbio.tick(10 * time.Millisecond) }
	testing.expectf(t, answered == before + 1, "%s: the op answered", f.name)
}

@(private = "file")
new_conversation :: proc(t: ^testing.T, f: Family, owner: u64, title: string) -> i64 {
	op := store.new_op(m.Start, 2 * len(title) + 16)
	op.owner, op.title = owner, strings.clone(title, store.op_allocator(op))
	op.done = proc(o: ^store.Op) {
		last_conv, last_err = (^m.Start)(o).result.id, o.err
		answered += 1
		store.free_op(o)
	}
	before := answered
	testing.expectf(t, f.start(op), "%s: start accepted", f.name)
	wait(t, f, before)
	testing.expect_value(t, last_err, m.Error.None)
	return last_conv
}

@(private = "file")
turn :: proc(t: ^testing.T, f: Family, owner: u64, conv: i64, role: m.Bot_Role, text: string, stats := m.Bot_Done{}, title := "") -> m.Error {
	op := store.new_op(m.Append, 2 * len(text) + len(title) + 16)
	a := store.op_allocator(op)
	op.owner = owner
	op.turn = {conv = conv, role = role, text = strings.clone(text, a), stats = stats}
	op.title = strings.clone(title, a)
	op.done = proc(o: ^store.Op) {
		last_err = o.err
		answered += 1
		store.free_op(o)
	}
	before := answered
	testing.expectf(t, f.append_turn(op), "%s: append accepted", f.name)
	wait(t, f, before)
	return last_err
}

@(private = "file")
conforms :: proc(t: ^testing.T, f: Family) {
	c := new_conversation(t, f, 7, "New conversation")
	testing.expect_value(t, turn(t, f, 7, c, .User, "why?", {}, "why?"), m.Error.None)
	stats := m.Bot_Done{stop = .Length, tokens = 12, ms_first_token = 34, ms_total = 56}
	testing.expect_value(t, turn(t, f, 7, c, .Assistant, "because", stats), m.Error.None)

	got, err := f.conversation(7, c)
	testing.expect_value(t, err, m.Error.None)
	testing.expectf(t, got.title == "why?" && got.turns == 2 && got.owner == 7, "%s: %v", f.name, got)

	list := make([dynamic]m.Turn, context.temp_allocator)
	testing.expect_value(t, f.turns(7, c, &list), m.Error.None)
	testing.expectf(t, len(list) == 2 && list[0].role == .User && list[0].text == "why?", "%s: turns %v", f.name, list[:])
	testing.expectf(t, list[1].role == .Assistant && list[1].stats == stats, "%s: an answer's stats, %v", f.name, list[1])

	// Q20: anyone else's id is as if it weren't there, for every read and write.
	_, err = f.conversation(8, c)
	testing.expect_value(t, err, m.Error.Not_Found)
	testing.expect_value(t, f.turns(8, c, &list), m.Error.Not_Found)
	testing.expect_value(t, turn(t, f, 8, c, .User, "mine now"), m.Error.Not_Found)
	theirs := make([dynamic]m.Conversation, context.temp_allocator)
	testing.expect_value(t, f.conversations(8, 50, &theirs), m.Error.None)
	testing.expect_value(t, len(theirs), 0)

	// A member's newest `keep`, newest first, and what fell out is gone with its turns.
	first := new_conversation(t, f, 9, "the first")
	testing.expect_value(t, turn(t, f, 9, first, .User, "kept?"), m.Error.None)
	newest: i64
	for _ in 0 ..< f.keep { newest = new_conversation(t, f, 9, "another") }
	testing.expect_value(t, f.conversations(9, 2 * f.keep, &theirs), m.Error.None)
	testing.expectf(t, len(theirs) == f.keep && theirs[0].id == newest, "%s: %d conversations kept", f.name, len(theirs))
	_, err = f.conversation(9, first)
	testing.expect_value(t, err, m.Error.Not_Found)

	// A conversation's last turns, oldest first, while its count goes on.
	long := new_conversation(t, f, 10, "long")
	for _ in 0 ..< f.last { testing.expect_value(t, turn(t, f, 10, long, .User, "old"), m.Error.None) }
	testing.expect_value(t, turn(t, f, 10, long, .Assistant, "new"), m.Error.None)
	clear(&list)
	testing.expect_value(t, f.turns(10, long, &list), m.Error.None)
	testing.expectf(t, len(list) == f.last && list[len(list) - 1].text == "new", "%s: %d turns kept", f.name, len(list))
	got, _ = f.conversation(10, long)
	testing.expect_value(t, got.turns, f.last + 1)
}

@(test)
both_families :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()

	conforms(t, {"memory", mem.conversations, mem.conversation, mem.turns, mem.start, mem.append_turn, mem.KEEP, mem.TURNS})

	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("bot", sql.MIGRATIONS[:])
	conforms(t, {"sqlite", sql.conversations, sql.conversation, sql.turns, sql.start, sql.append_turn, sql.KEEP, sql.TURNS})
}
