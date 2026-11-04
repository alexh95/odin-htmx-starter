package notify_storetest

// ---- the notify store contract, run against both families (D37) -------------------------
//
// One test binary imports both stores and holds each to the same behaviour: an add answers its
// stored item and the member's unread count through the caller's continuation, a list is a
// member's own, newest first, up to its limit, marking read zeroes the count, and the sweep
// takes only read items older than its cut. The SQLite family keeps a member's newest KEEP.

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
import mem "../../../stores/memory/notify"
import sql "../../../stores/sqlite/notify"

@(private = "file")
Family :: struct {
	name:      string,
	list:      m.Store_List,
	unread:    m.Store_Unread,
	add:       m.Store_Add,
	mark_read: m.Store_Mark_Read,
	prune:     m.Store_Prune,
	add_now:   m.Store_Add_Now,
	mute:      m.Store_Mute,
	muted:     m.Store_Muted,
	mutes:     m.Store_Mutes,
}

@(private = "file")
answered: int

@(private = "file")
last_unread: int

@(private = "file")
add :: proc(t: ^testing.T, f: Family, user: u64, html: string) {
	op := store.new_op(m.Add, 3 * len(html) + 64)
	a := store.op_allocator(op)
	op.user, op.kind, op.ref, op.html = user, "test.ping", strings.clone("/x", a), strings.clone(html, a)
	op.done = proc(o: ^store.Op) {
		assert(o.err == .None)
		last_unread = (^m.Add)(o).unread
		answered += 1
		store.free_op(o)
	}
	before := answered
	testing.expectf(t, f.add(op), "%s: add accepted", f.name)
	deadline := time.tick_now()
	for answered == before && time.tick_since(deadline) < 5 * time.Second { nbio.tick(10 * time.Millisecond) }
	testing.expectf(t, answered == before + 1, "%s: the add answered", f.name)
}

@(private = "file")
conforms :: proc(t: ^testing.T, f: Family) {
	for h in ([]string{"one", "two", "three"}) { add(t, f, 7, h) }
	testing.expectf(t, last_unread == 3, "%s: unread after three adds = %d", f.name, last_unread)
	add(t, f, 8, "someone else's")
	list := make([dynamic]m.Item, context.temp_allocator)
	testing.expect_value(t, f.list(7, 2, &list), m.Error.None)
	testing.expectf(t, len(list) == 2 && list[0].html == "three" && list[1].html == "two" && list[0].id > list[1].id, "%s: list(7, 2) = %v", f.name, list[:])
	testing.expect_value(t, f.unread(7), 3)
	testing.expect_value(t, f.unread(8), 1)

	testing.expect_value(t, f.mark_read(7), m.Error.None)
	testing.expect_value(t, f.unread(7), 0)
	testing.expect_value(t, f.unread(8), 1) // only the member's own
	// The sweep takes read items older than its cut: none before now, all of 7's after it.
	testing.expect_value(t, f.prune(0), 0)
	testing.expect_value(t, f.prune(time.time_to_unix(time.now()) + 1), 3)
	clear(&list)
	f.list(8, 10, &list)
	testing.expectf(t, len(list) == 1, "%s: an unread item stays", f.name)

	// From a job: stored at once, and counted. A mute is a member's, once, until it is lifted.
	it, unread, err := f.add_now(77, "jobs.failed", "/admin/jobs", "<b>failed</b>")
	testing.expectf(t, err == .None && it.id > 0 && it.kind == "jobs.failed" && unread == 1, "%s: add_now %v %d %v", f.name, it, unread, err)
	testing.expect_value(t, f.unread(77), 1)
	testing.expect_value(t, f.mute(77, "chat.mention", true), m.Error.None)
	testing.expect_value(t, f.mute(77, "chat.mention", true), m.Error.None)
	testing.expect_value(t, f.mute(77, "chat.room:1", true), m.Error.None)
	testing.expectf(t, f.muted(77, "chat.mention") && !f.muted(78, "chat.mention"), "%s: a member's own", f.name)
	keys := make([dynamic]string, context.temp_allocator)
	testing.expect_value(t, f.mutes(77, &keys), m.Error.None)
	testing.expectf(t, len(keys) == 2 && keys[0] == "chat.mention" && keys[1] == "chat.room:1", "%s: mutes %v", f.name, keys[:])
	testing.expect_value(t, f.mute(77, "chat.mention", false), m.Error.None)
	testing.expectf(t, !f.muted(77, "chat.mention"), "%s: lifted", f.name)
}

// One test, in order: the stores are process-wide.
@(test)
both_families :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()

	conforms(t, {"memory", mem.list, mem.unread, mem.add, mem.mark_read, mem.prune, mem.add_now, mem.mute, mem.muted, mem.mutes})

	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("notify", sql.MIGRATIONS[:])
	conforms(t, {"sqlite", sql.list, sql.unread, sql.add, sql.mark_read, sql.prune, sql.add_now, sql.mute, sql.muted, sql.mutes})

	// SQLite keeps a member's newest KEEP.
	for _ in 0 ..< sql.KEEP + 3 { add(t, {name = "sqlite", add = sql.add}, 9, "x") }
	all := make([dynamic]m.Item, context.temp_allocator)
	sql.list(9, 1000, &all)
	testing.expect_value(t, len(all), sql.KEEP)
}
