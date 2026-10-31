package audit_storetest

// ---- the audit store contract (SQLite; the memory member keeps nothing to read) ------------
//
// An append lands and reads back newest first; the filters match an actor in any case and an
// action by prefix; the keyset pages; the table refuses an update and the delete of an entry
// younger than 400 days, and lets an older one go.

import "base:runtime"
import "core:nbio"
import "core:testing"
import "core:time"

import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import sql "../../../stores/sqlite/audit"

@(private = "file")
settle :: proc(t: ^testing.T, want: int) {
	start := time.tick_now()
	for count() < want && time.tick_since(start) < 5 * time.Second { nbio.tick(10 * time.Millisecond) }
	testing.expectf(t, count() == want, "%d of %d entries landed", count(), want)
}

@(private = "file")
count :: proc() -> int {
	all := make([dynamic]m.Entry, context.temp_allocator)
	sql.list({limit = 1000}, &all)
	return len(all)
}

// One statement on the writer, in its own transaction: whether it went through.
@(private = "file")
run :: proc(statement: string) -> bool {
	@(static) text: string
	text = statement
	return db.write_now(proc() -> bool {
		st := db.writer_stmt(text)
		defer db.reset(st)
		return db.step_done(st) == .None
	})
}

@(test)
the_log_appends_filters_and_keeps :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	// Closed at the end, by the case that needs it closed.
	db.migrate("audit", sql.MIGRATIONS[:])

	alex := m.Actor{id = 1, name = "Alex", client = "00ff00ff00ff00ff"}
	testing.expect(t, sql.append(alex, "accounts.sign_in", {"session", 0}, "", ""))
	testing.expect(t, sql.append({client = "1111"}, "accounts.sign_in_failed", {"user", 1}, "", ""))
	testing.expect(t, sql.append(alex, "accounts.revoke", {"session", 0}, "lost phone", "n=1"))
	settle(t, 3)

	all := make([dynamic]m.Entry, context.temp_allocator)
	testing.expect_value(t, sql.list({limit = 10}, &all), store.Error.None)
	testing.expect(t, len(all) == 3 && all[0].action == "accounts.revoke" && all[0].reason == "lost phone" && all[0].actor.client == "00ff00ff00ff00ff")
	testing.expect(t, all[1].action == "accounts.sign_in_failed" && all[1].target.kind == "user" && all[1].target.id == 1)

	mine := make([dynamic]m.Entry, context.temp_allocator)
	sql.list({actor = "ALEX", limit = 10}, &mine)
	testing.expect_value(t, len(mine), 2) // any case
	sign := make([dynamic]m.Entry, context.temp_allocator)
	sql.list({action = "accounts.sign_in", limit = 10}, &sign)
	testing.expect_value(t, len(sign), 2) // a prefix: sign_in and sign_in_failed
	older := make([dynamic]m.Entry, context.temp_allocator)
	sql.list({before = all[0].id, limit = 1}, &older)
	testing.expect(t, len(older) == 1 && older[0].id == all[1].id) // the keyset

	testing.expect(t, !run("UPDATE audit_log SET reason = 'changed'"))
	testing.expect(t, !run("DELETE FROM audit_log"))
	testing.expect_value(t, count(), 3)

	// An entry 401 days old may go; the trigger names no other.
	testing.expect(t, run("INSERT INTO audit_log(at, actor_id, actor_name, action, target_kind, target_id, reason, client_id, meta) VALUES(CAST(unixepoch('subsec') * 1000 AS INTEGER) - 401 * 86400000, 0, '', 'old', '', 0, '', '', '')"))
	testing.expect_value(t, count(), 4)
	testing.expect(t, run("DELETE FROM audit_log WHERE action = 'old'"))
	testing.expect_value(t, count(), 3)

	// A refused append is lost, and counted (M4-04): once the store has closed, the writer refuses.
	before := sql.dropped()
	db.close()
	testing.expect(t, !sql.append(alex, "accounts.sign_in", {"session", 0}, "", ""))
	testing.expect_value(t, sql.dropped(), before + 1)
}
