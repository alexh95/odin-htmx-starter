package chat_store_memory

import "core:strings"
import "core:testing"

import "../../../platform/store"
import m "../../../features/chat/models"

@(private = "file")
Probe :: struct {
	using post: m.Post,
	got:        ^m.Message,
}

@(private = "file")
say :: proc(room: i64, author: u64, body: string, got: ^m.Message = nil) {
	op := store.new_op(Probe, 2 * (len(body) + 8))
	op.room, op.author, op.name, op.body, op.got = room, author, "ann", body, got
	op.done = proc(o: ^store.Op) {
		p := (^Probe)(o)
		if p.got != nil {
			p.got^ = p.result
			p.got.body = strings.clone(p.result.body, context.temp_allocator) // the op's arena goes below
			p.got.name = strings.clone(p.result.name, context.temp_allocator)
		}
		store.free_op(p)
	}
	_ = post(op)
}

@(private = "file")
reset :: proc() {
	for r in s.rooms {
		for i in 0 ..< r.ring.n {
			msg := mem_store_newest(r, i)
			delete(msg.name)
			delete(msg.body)
		}
		delete(r.ring.items)
		delete(r.room.slug)
		delete(r.room.name)
		free(r)
	}
	delete(s.rooms)
	s = {}
}

@(private = "file")
mem_store_newest :: proc(r: ^Room_State, i: int) -> ^m.Message {
	return &r.ring.items[(r.ring.head + r.ring.n - 1 - i) % len(r.ring.items)]
}

// One test: the store is the package's.
@(test)
a_room_keeps_its_newest :: proc(t: ^testing.T) {
	defer reset()
	defer free_all(context.temp_allocator)
	init(0)
	seed()
	lobby, err := room("lobby")
	testing.expect_value(t, err, m.Error.None)
	testing.expect_value(t, lobby.name, "Lobby")
	_, err = create_room("lobby", "Again", .Public, 0, "")
	testing.expect_value(t, err, m.Error.Constraint)

	got: m.Message
	say(lobby.id, 7, "first", &got)
	testing.expect_value(t, got.body, "first")
	testing.expect(t, got.id > 0)
	for _ in 0 ..< KEEP + 5 { say(lobby.id, 8, "more") }

	msgs := make([dynamic]m.Message, context.temp_allocator)
	testing.expect_value(t, recent(lobby.id, 50, &msgs), m.Error.None)
	testing.expect_value(t, len(msgs), 50)
	testing.expect(t, msgs[0].id < msgs[49].id) // oldest first
	clear(&msgs)
	_ = recent(lobby.id, 1000, &msgs)
	testing.expect_value(t, len(msgs), KEEP) // the ring
	newest := msgs[len(msgs) - 1].id
	testing.expect_value(t, count_after(lobby.id, newest - 3), 3)

	clear(&msgs)
	ver, reached, _ := changed(lobby.id, max(i64), &msgs)
	testing.expect_value(t, len(msgs), 0)
	testing.expect(t, reached)
	testing.expect_value(t, ver, s.base + KEEP + 6)
	testing.expect(t, got.id > s.base) // ids count from the boot epoch
	clear(&msgs)
	_, reached, _ = changed(lobby.id, ver - 2, &msgs)
	testing.expect_value(t, len(msgs), 2)
	testing.expect(t, reached)
	// A tag from before the 5 the ring let go: those changes are gone, and it says so (M2-35).
	clear(&msgs)
	_, reached, _ = changed(lobby.id, s.base + 3, &msgs)
	testing.expect(t, !reached)
	testing.expect_value(t, len(msgs), KEEP)

	// Only the author edits, inside the window; a delete leaves a tombstone.
	edit := store.new_op(m.Change, 64)
	edit.id, edit.author, edit.body, edit.window = newest, 7, "nope", 600
	edit.done = proc(o: ^store.Op) {}
	_ = change(edit)
	testing.expect_value(t, edit.err, m.Error.Constraint)
	store.free_op(edit)
	gone := store.new_op(m.Change, 64)
	gone.id, gone.author, gone.delete, gone.window = newest, 8, true, 600
	gone.done = proc(o: ^store.Op) {}
	_ = change(gone)
	testing.expect_value(t, gone.err, m.Error.None)
	testing.expect(t, gone.result.gone)
	testing.expect(t, gone.result.ver > ver)
	store.free_op(gone)
	msg, _ := message(newest)
	testing.expect_value(t, msg.body, "")

	// Past the byte budget the oldest go first.
	init(4 * 1024)
	say(lobby.id, 9, "evict")
	clear(&msgs)
	_ = recent(lobby.id, 1000, &msgs)
	testing.expect(t, len(msgs) < KEEP)
	testing.expect(t, s.bytes <= 4 * 1024)

	// After the eviction a cursor from before what went can't be served whole; one at the
	// newest can (M2-31).
	newest_now: i64
	for kept in msgs { newest_now = max(newest_now, kept.id) }
	clear(&msgs)
	reached, err = after(lobby.id, 0, &msgs)
	testing.expect(t, err == .None && !reached && len(msgs) > 0)
	clear(&msgs)
	reached, err = after(lobby.id, newest_now, &msgs)
	testing.expect(t, err == .None && reached && len(msgs) == 0)
}
