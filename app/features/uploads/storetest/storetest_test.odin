package uploads_storetest

// ---- the uploads store contract, run against both families (D37) ------------------------

import "base:runtime"
import "core:nbio"
import "core:testing"

import "../../../platform/guard"
import "../../../platform/obs"
import db "../../../platform/store/sqlite"
import m "../models"
import mem "../../../stores/memory/uploads"
import sql "../../../stores/sqlite/uploads"

@(private = "file")
Family :: struct {
	name:       string,
	create:     m.Store_Create,
	upload:     m.Store_Upload,
	advance:    m.Store_Advance,
	close:      m.Store_Close,
	open_count: m.Store_Open_Count,
	stale:      m.Store_Stale,
	add_blob:   m.Store_Add_Blob,
	blob:       m.Store_Blob,
	blobs:      m.Store_Blobs,
	drop_blob:  m.Store_Drop_Blob,
	bytes_held: m.Store_Bytes_Held,
}

@(private = "file")
conforms :: proc(t: ^testing.T, f: Family) {
	NOW :: i64(1_800_000_000)
	a, err := f.create(7, 100, NOW)
	testing.expectf(t, err == .None && a > 0, "%s: create, %v", f.name, err)
	b, _ := f.create(7, 200, NOW - 7200)
	u, uerr := f.upload(a)
	testing.expectf(t, uerr == .None && u.user == 7 && u.size == 100 && u.received == 0 && u.state == .Open, "%s: a row, %v", f.name, u)
	testing.expect_value(t, f.advance(a, 40), m.Error.None)
	u, _ = f.upload(a)
	testing.expect_value(t, u.received, 40)
	testing.expect_value(t, f.open_count(7, NOW - 3600), 1) // the old one no longer counts
	testing.expect_value(t, f.open_count(7, NOW - 8000), 2)
	testing.expect_value(t, f.open_count(8, NOW - 8000), 0)
	old := make([dynamic]i64, context.temp_allocator)
	testing.expect_value(t, f.stale(NOW - 3600, &old), m.Error.None)
	testing.expectf(t, len(old) == 1 && old[0] == b, "%s: stale %v", f.name, old[:])
	testing.expect_value(t, f.close(a, .Done), m.Error.None)
	u, _ = f.upload(a)
	testing.expect_value(t, u.state, m.Upload_State.Done)
	testing.expect_value(t, f.open_count(7, NOW - 3600), 0)
	_, gone := f.upload(1 << 40)
	testing.expect_value(t, gone, m.Error.Not_Found)

	SHA :: "aa00000000000000000000000000000000000000000000000000000000000000"
	row := m.Blob{sha256 = SHA, mime = "image/png", bytes = 9, width = 3, height = 2, user = 7, at = NOW}
	testing.expect_value(t, f.add_blob(row), m.Error.None)
	again := row
	again.user = 8
	testing.expect_value(t, f.add_blob(again), m.Error.None) // the same content: the first stays
	got, berr := f.blob(SHA)
	testing.expectf(t, berr == .None && got.mime == "image/png" && got.width == 3 && got.height == 2 && got.user == 7, "%s: a blob, %v", f.name, got)
	_, none := f.blob("bb")
	testing.expect_value(t, none, m.Error.Not_Found)

	list := make([dynamic]string, context.temp_allocator)
	testing.expect_value(t, f.blobs(NOW, &list), m.Error.None)
	testing.expectf(t, len(list) == 0, "%s: none made before %d: %v", f.name, NOW, list[:])
	testing.expect_value(t, f.blobs(NOW + 1, &list), m.Error.None)
	testing.expectf(t, len(list) == 1 && list[0] == SHA, "%s: blobs %v", f.name, list[:])
	later := row
	later.at = NOW + 100
	testing.expect_value(t, f.add_blob(later), m.Error.None) // sent again: as new
	clear(&list)
	testing.expect_value(t, f.blobs(NOW + 1, &list), m.Error.None)
	testing.expect_value(t, len(list), 0)
	member, all := f.bytes_held(7, NOW)
	testing.expectf(t, member == 100 && all == 9, "%s: bytes %d %d", f.name, member, all) // the upload at NOW, not the older one
	stayed, _ := f.drop_blob(SHA, NOW + 100) // made at NOW + 100: not before it
	testing.expect(t, !stayed)
	went, derr := f.drop_blob(SHA, max(i64))
	testing.expect(t, went && derr == .None)
	_, dropped := f.blob(SHA)
	testing.expect_value(t, dropped, m.Error.Not_Found)
	went, _ = f.drop_blob(SHA, max(i64))
	testing.expect(t, !went)
}

// One test, in order: the stores are process-wide.
@(test)
both_families :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()
	conforms(t, {"memory", mem.create, mem.upload, mem.advance, mem.close, mem.open_count, mem.stale, mem.add_blob, mem.blob, mem.blobs, mem.drop_blob, mem.bytes_held})
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("uploads", sql.MIGRATIONS[:])
	conforms(t, {"sqlite", sql.create, sql.upload, sql.advance, sql.close, sql.open_count, sql.stale, sql.add_blob, sql.blob, sql.blobs, sql.drop_blob, sql.bytes_held})
	free_all(context.temp_allocator)
}
