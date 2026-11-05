package chat_storetest

// ---- the chat store contract, run against both families (D37) ---------------------------
//
// One test binary imports both stores and holds each to what both promise: the lobby goes into
// an empty store, a taken slug is refused, a post answers its stored message with the room's
// next version, recent is oldest first, count_after and after count and serve past a cursor,
// changed serves past a version, and only the author edits or deletes, inside the window, a
// delete leaving a tombstone. Rooms come in kinds: a private room's owner is its first member,
// rooms_for lists the public rooms, announcements and the viewer's own, a DM is found again rather
// than made twice, and members join (once) and leave. An invite is open until it is revoked,
// expires or is used up; using it joins once, and a member already in counts no use. Retention
// keeps a room's newest `cap` (the gap said by `dropped` and `after`'s reached), and the sweep lets
// go of what is past its kind's age. Moderation: a room's lock and slow mode read back, a ban holds
// until its time and is lifted by one in the past, a report is resolved once, and a moderator's
// delete takes anyone's message and writes its audit entry, whose failure (SQLite) undoes it. Search
// finds a message in the rooms a member may read and nowhere else, follows an edit and a delete,
// and treats what is typed as words, never as syntax. What the ring keeps and lets go is the
// memory store's own test; the SQLite store keeps every message, with ids that are rowids.

import "base:runtime"
import "core:log"
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
	rooms_for:   m.Store_Rooms_For,
	create_room: m.Store_Create_Room,
	dm:          m.Store_Dm,
	members:     m.Store_Members,
	is_member:   m.Store_Is_Member,
	join:        m.Store_Join,
	leave:       m.Store_Leave,
	sweep:       m.Store_Sweep,
	search:      m.Store_Search,
	optimize:    m.Store_Optimize,
	set_audit:   m.Store_Set_Audit_Writer,
	set_room:    m.Store_Set_Room,
	ban:         m.Store_Ban,
	banned:      m.Store_Banned,
	report:      m.Store_Report,
	reports:     m.Store_Reports,
	report_of:   m.Store_Report_Of,
	resolve:     m.Store_Resolve,
	add_invite:  m.Store_Add_Invite,
	invite:      m.Store_Invite,
	invites:     m.Store_Invites,
	revoke:      m.Store_Revoke_Invite,
	use_invite:  m.Store_Use_Invite,
	recent:      m.Store_Recent,
	after:       m.Store_After,
	count_after: m.Store_Count_After,
	changed:     m.Store_Changed,
	message:     m.Store_Message,
	post:        m.Store_Post,
	change:      m.Store_Change,
	open_reports: m.Store_Open_Reports,
	room_of:     m.Store_Room_Of,
	rooms_owned: m.Store_Rooms_Owned,
	blob_held:   m.Store_Blob_Held,
	purge_blob:  m.Store_Purge_Blob,
	block:       m.Store_Block,
	unblock:     m.Store_Unblock,
	blocking:    m.Store_Blocking,
	blocks:      m.Store_Blocks,
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
	f.init(0, {})
	f.seed()
	f.seed() // into an empty store only
	lobby, err := f.room("lobby")
	testing.expectf(t, err == .None && lobby.name == "Lobby", "%s: the lobby, %v", f.name, err)
	_, err = f.create_room("lobby", "Again", .Public, 0, "")
	testing.expectf(t, err == .Constraint, "%s: a taken slug, %v", f.name, err)
	side, serr := f.create_room("side", "Side", .Public, 7, "ann")
	testing.expectf(t, serr == .None && side.slug == "side" && side.kind == .Public && side.owner == 7, "%s: a new room, %v", f.name, serr)
	rooms_of_kinds(t, f)
	images(t, f)
	blocks(t, f)

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
	retention(t, f)
	moderation(t, f)
	searching(t, f)
}

@(private = "file")
searching :: proc(t: ^testing.T, f: Family) {
	NOW :: i64(1_800_000_000)
	found :: proc(f: Family, who: u64, words: ..string) -> [dynamic]m.Hit {
		hits := make([dynamic]m.Hit, context.temp_allocator)
		_ = f.search(who, words, NOW, 20, &hits)
		return hits
	}
	open, _ := f.create_room("found", "Found", .Public, 7, "ann")
	shut, _ := f.create_room("hidden", "Hidden", .Private, 7, "ann")
	a := say(t, f, open.id, 7, "the zebra crossing")
	b := say(t, f, shut.id, 7, "a zebra in private")
	hits := found(f, 7, "zebra")
	testing.expectf(t, len(hits) == 2 && hits[0].msg.id == b.id && hits[1].msg.id == a.id, "%s: the owner finds both, newest first: %v", f.name, hits[:])
	testing.expectf(t, hits[1].room.slug == "found" && hits[1].msg.body == "the zebra crossing", "%s: a hit's room and body, %v", f.name, hits[1])
	hits = found(f, 8, "zebra")
	testing.expectf(t, len(hits) == 1 && hits[0].msg.id == a.id, "%s: a private room is its members' alone: %v", f.name, hits[:])
	testing.expect_value(t, f.join(shut.id, 8, "bob"), m.Error.None)
	testing.expectf(t, len(found(f, 8, "zebra")) == 2, "%s: a member finds it", f.name)
	testing.expect_value(t, f.ban({room = open.id, who = 8, kind = .Kick, until = NOW + 60, by = 1}, {}), m.Error.None)
	hits = found(f, 8, "zebra")
	testing.expectf(t, len(hits) == 1 && hits[0].msg.id == b.id, "%s: nor a room they're kicked from: %v", f.name, hits[:])

	testing.expectf(t, len(found(f, 7, "zebra", "crossing")) == 1, "%s: every word", f.name)
	testing.expectf(t, len(found(f, 7, "zebra", "nothing")) == 0, "%s: every word, none here", f.name)
	testing.expectf(t, len(found(f, 7, "ZEBRA")) == 2, "%s: any case", f.name)
	testing.expectf(t, len(found(f, 7, "zeb")) == 2, "%s: the last word as a prefix", f.name)
	testing.expectf(t, len(found(f, 7, `ze"bra OR *`)) == 0, "%s: what is typed is no syntax", f.name)
	testing.expectf(t, len(found(f, 7)) == 0, "%s: nothing asked, nothing found", f.name)

	// A member who left, and the bot's words, follow the room.
	left, _ := f.create_room("left", "Left", .Private, 7, "ann")
	testing.expect_value(t, f.join(left.id, 9, "cid"), m.Error.None)
	say(t, f, left.id, 0, "the walrus answer")
	testing.expectf(t, len(found(f, 9, "walrus")) == 1, "%s: a member finds the bot's answer", f.name)
	testing.expectf(t, len(found(f, 8, "walrus")) == 0, "%s: nobody else does", f.name)
	testing.expect_value(t, f.leave(left.id, 9), m.Error.None)
	testing.expectf(t, len(found(f, 9, "walrus")) == 0, "%s: nor once they've left", f.name)
	testing.expectf(t, len(found(f, 0, "walrus")) == 0, "%s: nor a guest", f.name)

	// The marks round the hit, and a typed mark only a character.
	marks, _ := f.create_room("marks", "Marks", .Public, 7, "ann")
	say(t, f, marks.id, 7, "an ibex \uE000 walks")
	hits = found(f, 7, "ibex")
	testing.expectf(t, len(hits) == 1 && strings.contains(hits[0].snippet, "\uE000ibex\uE001"), "%s: a hit is marked: %q", f.name, hits[0].snippet if len(hits) > 0 else "")
	// FTS folds and a scan doesn't (§11.8), and each marks what it found.
	say(t, f, marks.id, 7, "the café noir")
	hits = found(f, 7, "cafe")
	if f.name == "sqlite" {
		testing.expectf(t, len(hits) == 1 && strings.contains(hits[0].snippet, "café"), "sqlite folds: %v", hits[:])
	} else {
		testing.expectf(t, len(hits) == 0, "memory doesn't: %v", hits[:])
		hits = found(f, 7, "CAFÉ")
		testing.expectf(t, len(hits) == 1 && strings.contains(hits[0].snippet, "café"), "memory, its case: %v", hits[:])
	}
	testing.expect_value(t, f.optimize(), m.Error.None)
	testing.expectf(t, len(found(f, 7, "ibex")) == 1, "%s: the index survives its optimize", f.name)

	// An edit and a tombstone reach the index.
	edited, _ := alter(t, f, a.id, 7, "a giraffe now", false)
	testing.expectf(t, edited.body == "a giraffe now" && len(found(f, 7, "giraffe")) == 1 && len(found(f, 7, "crossing")) == 0, "%s: an edit, %v", f.name, edited)
	_, _ = alter(t, f, b.id, 7, "", true)
	testing.expectf(t, len(found(f, 7, "zebra")) == 0, "%s: a tombstone is gone from search", f.name)
}

@(private = "file")
audited: [dynamic]string

@(private = "file")
audit_fails: bool

@(private = "file")
moderation :: proc(t: ^testing.T, f: Family) {
	// On the heap: SQLite's ops answer from the loop's callback, whose temp memory goes when it returns.
	audited = make([dynamic]string, runtime.heap_allocator())
	defer delete(audited)
	f.set_audit(proc(actor_id: i64, actor_name, client, action, target_kind: string, target_id: i64, reason, meta: string) -> m.Error {
		if audit_fails { return .Failed }
		append(&audited, action)
		return .None
	})
	defer f.set_audit(nil)
	room, _ := f.create_room("modded", "Modded", .Public, 7, "ann")
	A :: proc(action: string) -> m.Audit { return {actor_id = 1, actor_name = "mod", action = action, target_kind = "room", reason = "why"} }

	testing.expect_value(t, f.set_room(room.id, true, 30, A("chat.lock")), m.Error.None)
	again, _ := f.room("modded")
	testing.expectf(t, again.locked && again.slow == 30, "%s: lock and slow read back, %v", f.name, again)
	testing.expect_value(t, f.set_room(1 << 40, false, 0, {}), m.Error.Not_Found)

	NOW :: i64(1_800_000_000)
	testing.expect_value(t, f.ban({room = room.id, who = 8, kind = .Mute, until = NOW + 60, by = 1}, A("chat.mute")), m.Error.None)
	testing.expect_value(t, f.banned(room.id, 8, .Mute, NOW), NOW + 60)
	testing.expect_value(t, f.banned(room.id, 8, .Kick, NOW), i64(0))
	testing.expect_value(t, f.banned(room.id, 8, .Mute, NOW + 60), i64(0))
	testing.expect_value(t, f.ban({room = room.id, who = 8, kind = .Mute, until = NOW, by = 1}, A("chat.unmute")), m.Error.None)
	testing.expect_value(t, f.banned(room.id, 8, .Mute, NOW), i64(0)) // lifted: its time has come

	msg := say(t, f, room.id, 8, "rude")
	id, rerr := f.report({room = room.id, msg = msg.id, author = 8, author_name = "bob", body = "rude", by = 7, by_name = "ann", reason = "spam", at = NOW})
	testing.expectf(t, rerr == .None && id > 0, "%s: a report, %v", f.name, rerr)
	open := make([dynamic]m.Report, context.temp_allocator)
	_ = f.reports(100, &open)
	testing.expectf(t, len(open) == 1 && open[0].body == "rude" && open[0].reason == "spam" && open[0].by_name == "ann", "%s: open reports %v", f.name, open[:])
	testing.expect_value(t, f.resolve(id, NOW, "dismissed", A("chat.report_dismissed")), m.Error.None)
	testing.expect_value(t, f.resolve(id, NOW, "removed", A("chat.report_removed")), m.Error.Not_Found)
	row, _ := f.report_of(id)
	testing.expectf(t, row.resolved == NOW && row.outcome == "dismissed", "%s: resolved once, %v", f.name, row)
	clear(&open)
	_ = f.reports(100, &open)
	testing.expectf(t, len(open) == 0, "%s: no open reports", f.name)

	// A moderator's delete: someone else's message, past any window, with its audit entry.
	removed, derr := moderate(t, f, msg.id, false)
	testing.expectf(t, derr == .None && removed.gone, "%s: a moderator's delete, %v", f.name, derr)
	want := []string{"chat.lock", "chat.mute", "chat.unmute", "chat.report_dismissed", "chat.remove"}
	testing.expectf(t, len(audited) == len(want), "%s: audited %v", f.name, audited[:])
	for a, i in want {
		if i < len(audited) { testing.expectf(t, audited[i] == a, "%s: audit %d is %q", f.name, i, audited[i]) }
	}
	if f.name == "sqlite" {
		// The entry is one statement of the change's unit: its failure undoes the delete.
		other := say(t, f, room.id, 8, "kept")
		audit_fails = true
		_, ferr := moderate(t, f, other.id, false)
		audit_fails = false
		kept, _ := f.message(other.id)
		testing.expectf(t, ferr == .Failed && !kept.gone && kept.body == "kept", "sqlite: a failed audit undoes the delete, %v %v", ferr, kept)
	}
}

@(private = "file")
moderate :: proc(t: ^testing.T, f: Family, id: i64, _: bool) -> (m.Message, m.Error) {
	op := store.new_op(m.Change, 64)
	op.id, op.author, op.delete, op.moderated = id, 1, true, true
	op.audit = {actor_id = 1, actor_name = "mod", action = "chat.remove", target_kind = "message", target_id = id, reason = "rude"}
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

// A public room keeps its newest 5 (trimmed on every insert under so small a cap); announcements
// nothing past a minute, once the sweep runs.
@(private = "file")
retention :: proc(t: ^testing.T, f: Family) {
	keep: m.Retention
	keep.cap[.Public], keep.age[.Announce] = 5, 60
	f.init(0, keep)
	small, err := f.create_room("small", "Small", .Public, 7, "ann")
	testing.expectf(t, err == .None, "%s: a capped room, %v", f.name, err)
	first := say(t, f, small.id, 7, "one")
	for _ in 0 ..< 6 { say(t, f, small.id, 7, "more") }
	msgs := make([dynamic]m.Message, context.temp_allocator)
	testing.expect_value(t, f.recent(small.id, 50, &msgs), m.Error.None)
	testing.expectf(t, len(msgs) == 5 && msgs[0].id > first.id, "%s: the newest 5 of 7 kept: %d", f.name, len(msgs))
	again, _ := f.room("small")
	testing.expectf(t, again.dropped > first.id && again.dropped < msgs[0].id, "%s: dropped says the gap, %v", f.name, again)
	clear(&msgs)
	reached, _ := f.after(small.id, first.id, &msgs)
	testing.expectf(t, !reached, "%s: a cursor below the gap isn't served whole", f.name)

	news, _ := f.create_room("bulletin", "Bulletin", .Announce, 7, "ann")
	for _ in 0 ..< 3 { say(t, f, news.id, 7, "old news") }
	at := time.time_to_unix(time.now())
	removed, serr := f.sweep(at + 30)
	testing.expectf(t, serr == .None && removed == 0, "%s: nothing past a minute yet, %d %v", f.name, removed, serr)
	removed, serr = f.sweep(at + 120)
	testing.expectf(t, serr == .None && removed == 3, "%s: the sweep let 3 go, %d %v", f.name, removed, serr)
	clear(&msgs)
	_ = f.recent(news.id, 50, &msgs)
	gone, _ := f.room("bulletin")
	testing.expectf(t, len(msgs) == 0 && gone.dropped > 0, "%s: the room after the sweep, %d %v", f.name, len(msgs), gone)
	if f.name == "sqlite" { chunks(t, f) }
	f.init(0, {})
}

// A blob is held by a live message or an open report; a purge takes it out of every message, in
// any room, and bumps each room's version so a poll sees it go.
@(private = "file")
images :: proc(t: ^testing.T, f: Family) {
	SHA :: "cc00000000000000000000000000000000000000000000000000000000000000"
	lobby, _ := f.room("lobby")
	testing.expect(t, !f.blob_held(SHA))
	op := store.new_op(m.Post, 256)
	a := store.op_allocator(op)
	op.room, op.author, op.name, op.body, op.blob = lobby.id, 7, strings.clone("ann", a), strings.clone("", a), strings.clone(SHA, a)
	op.done = proc(o: ^store.Op) {
		last_err = o.err
		keep((^m.Post)(o).result)
		answered += 1
		store.free_op(o)
	}
	before := answered
	testing.expect(t, f.post(op))
	wait(t, f, before)
	testing.expectf(t, last_err == .None && last.blob == SHA, "%s: a post keeps its image, %v", f.name, last)
	msg := last
	testing.expectf(t, f.blob_held(SHA), "%s: a live message holds it", f.name)

	id, rerr := f.report({room = lobby.id, msg = msg.id, author = 7, author_name = "ann", blob = SHA, by = 8, by_name = "bob", reason = "why", at = 100})
	testing.expect_value(t, rerr, m.Error.None)
	rep, _ := f.report_of(id)
	testing.expect_value(t, rep.blob, SHA)
	twice, _ := f.report({room = lobby.id, msg = msg.id, author = 7, author_name = "ann", by = 8, by_name = "bob", reason = "again", at = 101})
	testing.expect_value(t, twice, i64(0)) // open already
	theirs, all := f.open_reports(8)
	testing.expectf(t, theirs >= 1 && all >= theirs, "%s: open %d of %d", f.name, theirs, all)
	one, oerr := f.room_of(lobby.id)
	testing.expectf(t, oerr == .None && one.slug == "lobby", "%s: room_of %v", f.name, one)
	_, none := f.room_of(1 << 40)
	testing.expect_value(t, none, m.Error.Not_Found)
	owned := f.rooms_owned(7)
	testing.expectf(t, owned >= 1, "%s: owned %d", f.name, owned)

	out := make([dynamic]m.Message, context.temp_allocator)
	testing.expect_value(t, f.purge_blob(SHA, {}, &out), m.Error.None)
	testing.expectf(t, len(out) == 1 && out[0].id == msg.id && out[0].blob == "" && out[0].ver > msg.ver, "%s: purged %v", f.name, out[:])
	testing.expectf(t, !f.blob_held(SHA), "%s: nothing holds it now", f.name)
	again, _ := f.message(msg.id)
	testing.expect_value(t, again.blob, "")
	rep, _ = f.report_of(id)
	testing.expect_value(t, rep.blob, "")
	testing.expect_value(t, f.resolve(id, 200, "dismissed", {}), m.Error.None)
	rep, _ = f.report_of(id)
	testing.expect_value(t, rep.body, "") // a closed report keeps the record, not the copy
}

@(private = "file")
blocks :: proc(t: ^testing.T, f: Family) {
	testing.expect(t, !f.blocking(7, 8))
	testing.expect_value(t, f.block(7, 8, "bob", 100), m.Error.None)
	testing.expect_value(t, f.block(7, 8, "bob", 101), m.Error.None) // again: nothing changes
	testing.expect_value(t, f.block(7, 9, "cat", 102), m.Error.None)
	testing.expect(t, f.blocking(7, 8))
	testing.expect(t, !f.blocking(8, 7)) // one way
	list := make([dynamic]m.Block, context.temp_allocator)
	testing.expect_value(t, f.blocks(7, &list), m.Error.None)
	testing.expectf(t, len(list) == 2 && list[0].name == "cat" && list[1].other == 8, "%s: blocks %v", f.name, list[:])
	testing.expect_value(t, f.unblock(7, 8), m.Error.None)
	testing.expect_value(t, f.unblock(7, 9), m.Error.None)
	testing.expect(t, !f.blocking(7, 8))
}

// SQLite's deletes go 1000 rows a transaction: a sweep past a chunk takes two, and lets all go.
@(private = "file")
chunks :: proc(t: ^testing.T, f: Family) {
	testing.expect_value(t, sql.trim_every(5), 1)
	testing.expect_value(t, sql.trim_every(100), 10)
	testing.expect_value(t, sql.trim_every(500), 50)
	testing.expect_value(t, sql.trim_every(5000), 50)
	big, _ := f.create_room("big", "Big", .Announce, 7, "ann")
	for _ in 0 ..< 1500 { say(t, f, big.id, 7, "x") }
	start := time.tick_now()
	removed, err := f.sweep(time.time_to_unix(time.now()) + 120)
	took := time.tick_since(start)
	testing.expectf(t, err == .None && removed == 1500, "sqlite: a sweep across chunks, %d %v", removed, err)
	// §14.1's budget is 6.4 ms per 1000 rows with the FTS triggers on; ten times it fails here, on
	// any box, and docs/perf/CHAT-RETENTION.md keeps the figure.
	per_1000 := time.duration_milliseconds(took) * 1000 / f64(max(removed, 1))
	log.infof("retention: %.2f ms per 1000 rows", per_1000)
	testing.expectf(t, per_1000 < 64, "sqlite: retention at %.2f ms per 1000 rows", per_1000)
}

@(private = "file")
rooms_of_kinds :: proc(t: ^testing.T, f: Family) {
	// A private room: its owner is in it, nobody else is, and it is only theirs to list.
	den, err := f.create_room("den", "Den", .Private, 7, "ann")
	testing.expectf(t, err == .None && den.kind == .Private && den.owner == 7, "%s: a private room, %v", f.name, err)
	news, nerr := f.create_room("news", "News", .Announce, 7, "ann")
	testing.expectf(t, nerr == .None && news.kind == .Announce, "%s: announcements, %v", f.name, nerr)
	again, _ := f.room("den")
	testing.expectf(t, again.kind == .Private && again.owner == 7, "%s: the kind and owner read back, %v", f.name, again)
	testing.expectf(t, f.is_member(den.id, 7) && !f.is_member(den.id, 8), "%s: the owner is its first member", f.name)
	testing.expectf(t, !f.is_member(news.id, 7), "%s: announcements keep no members", f.name)
	slugs :: proc(f: Family, who: u64) -> string {
		list := make([dynamic]m.Room, context.temp_allocator)
		_ = f.rooms_for(who, &list)
		b := strings.builder_make(context.temp_allocator)
		for r in list {
			strings.write_string(&b, r.slug)
			strings.write_byte(&b, ' ')
		}
		return strings.to_string(b)
	}
	testing.expectf(t, slugs(f, 7) == "lobby side den news ", "%s: the owner's rooms: %q", f.name, slugs(f, 7))
	testing.expectf(t, slugs(f, 8) == "lobby side news ", "%s: another's rooms: %q", f.name, slugs(f, 8))

	// Members join once and leave; their name is kept as it was.
	testing.expect_value(t, f.join(den.id, 8, "bob"), m.Error.None)
	testing.expect_value(t, f.join(den.id, 8, "bob"), m.Error.None)
	who := make([dynamic]m.Member, context.temp_allocator)
	testing.expect_value(t, f.members(den.id, &who), m.Error.None)
	testing.expectf(t, len(who) == 2 && who[0].who == 7 && who[1].who == 8 && who[1].name == "bob", "%s: members %v", f.name, who[:])
	testing.expectf(t, slugs(f, 8) == "lobby side den news ", "%s: a member's rooms: %q", f.name, slugs(f, 8))
	testing.expect_value(t, f.leave(den.id, 8), m.Error.None)
	testing.expectf(t, !f.is_member(den.id, 8), "%s: left", f.name)

	// A DM: two members, found again whichever of them asks, never made twice.
	d1, derr := f.dm(7, "ann", 9, "cat", "dm-0011223344556677")
	testing.expectf(t, derr == .None && d1.kind == .Dm && d1.name == "ann and cat", "%s: a DM, %v %v", f.name, d1, derr)
	d2, _ := f.dm(9, "cat", 7, "ann", "dm-8899aabbccddeeff")
	testing.expectf(t, d2.id == d1.id && d2.slug == "dm-0011223344556677", "%s: the same DM from the other side, %v", f.name, d2)
	testing.expectf(t, f.is_member(d1.id, 7) && f.is_member(d1.id, 9) && !f.is_member(d1.id, 8), "%s: a DM's two members", f.name)
	testing.expectf(t, slugs(f, 8) == "lobby side news ", "%s: a DM is not a third's: %q", f.name, slugs(f, 8))
	invites_open_and_close(t, f, den)
}

@(private = "file")
invites_open_and_close :: proc(t: ^testing.T, f: Family, den: m.Room) {
	NOW :: i64(1_800_000_000)
	open_ids :: proc(f: Family, room: i64, at: i64) -> [dynamic]i64 {
		list := make([dynamic]m.Invite, context.temp_allocator)
		_ = f.invites(room, at, &list)
		ids := make([dynamic]i64, context.temp_allocator)
		for inv in list { append(&ids, inv.id) }
		return ids
	}
	many, err := f.add_invite({room = den.id, hash = "aa", by = 7, by_name = "ann", at = NOW, expires = NOW + 3600})
	testing.expectf(t, err == .None && many > 0, "%s: an invite, %v", f.name, err)
	once, _ := f.add_invite({room = den.id, hash = "bb", by = 7, by_name = "ann", at = NOW, expires = NOW + 3600, max_uses = 1})
	soon, _ := f.add_invite({room = den.id, hash = "cc", by = 7, by_name = "ann", at = NOW, expires = NOW + 10})
	row, _ := f.invite(many)
	testing.expectf(t, row.hash == "aa" && row.by == 7 && row.by_name == "ann" && row.expires == NOW + 3600, "%s: the row reads back, %v", f.name, row)
	ids := open_ids(f, den.id, NOW)
	testing.expectf(t, len(ids) == 3 && ids[0] == soon && ids[2] == many, "%s: open, newest first: %v", f.name, ids[:])
	testing.expectf(t, len(open_ids(f, den.id, NOW + 10)) == 2, "%s: expired is not open", f.name)
	testing.expect_value(t, f.use_invite(soon, NOW + 10, 10, "dan"), m.Error.Not_Found)

	// A one-use invite: it joins its first, and then nobody; a member already in uses nothing.
	testing.expect_value(t, f.use_invite(once, NOW, 7, "ann"), m.Error.None)
	row, _ = f.invite(once)
	testing.expectf(t, row.uses == 0, "%s: the owner, already in, used nothing", f.name)
	testing.expect_value(t, f.use_invite(once, NOW, 10, "dan"), m.Error.None)
	testing.expectf(t, f.is_member(den.id, 10), "%s: joined by the invite", f.name)
	testing.expect_value(t, f.use_invite(once, NOW, 11, "eve"), m.Error.Not_Found)
	testing.expectf(t, !f.is_member(den.id, 11), "%s: a spent invite joins nobody", f.name)

	// Revoked: closed to everyone, and only its own room's to revoke.
	testing.expect_value(t, f.revoke(many, den.id + 999, NOW), m.Error.Not_Found)
	testing.expect_value(t, f.revoke(many, den.id, NOW), m.Error.None)
	testing.expect_value(t, f.revoke(many, den.id, NOW), m.Error.Not_Found)
	testing.expect_value(t, f.use_invite(many, NOW, 11, "eve"), m.Error.Not_Found)
	row, _ = f.invite(many)
	testing.expectf(t, row.revoked == NOW, "%s: revoked when, %v", f.name, row)
	testing.expectf(t, len(open_ids(f, den.id, NOW)) == 1, "%s: open after: %v", f.name, open_ids(f, den.id, NOW)[:])
	_, gone := f.invite(1 << 40)
	testing.expect_value(t, gone, m.Error.Not_Found)
}

// One test, in order: the stores are process-wide.
@(test)
both_families :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()

	conforms(t, {"memory", mem.init, mem.seed, mem.room, mem.rooms_for, mem.create_room, mem.dm, mem.members, mem.is_member, mem.join, mem.leave, mem.sweep, mem.search, mem.optimize, mem.set_audit_writer, mem.set_room, mem.ban, mem.banned, mem.report, mem.reports, mem.report_of, mem.resolve, mem.add_invite, mem.invite, mem.invites, mem.revoke_invite, mem.use_invite, mem.recent, mem.after, mem.count_after, mem.changed, mem.message, mem.post, mem.change, mem.open_reports, mem.room_of, mem.rooms_owned, mem.blob_held, mem.purge_blob, mem.block, mem.unblock, mem.blocking, mem.blocks})

	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("chat", sql.MIGRATIONS[:])
	conforms(t, {"sqlite", sql.init, sql.seed, sql.room, sql.rooms_for, sql.create_room, sql.dm, sql.members, sql.is_member, sql.join, sql.leave, sql.sweep, sql.search, sql.optimize, sql.set_audit_writer, sql.set_room, sql.ban, sql.banned, sql.report, sql.reports, sql.report_of, sql.resolve, sql.add_invite, sql.invite, sql.invites, sql.revoke_invite, sql.use_invite, sql.recent, sql.after, sql.count_after, sql.changed, sql.message, sql.post, sql.change, sql.open_reports, sql.room_of, sql.rooms_owned, sql.blob_held, sql.purge_blob, sql.block, sql.unblock, sql.blocking, sql.blocks})

	// The search takes the index's order, and sorts nothing (M6-13).
	plan := db.read("EXPLAIN QUERY PLAN " + sql.SQL_SEARCH)
	defer db.reset(plan)
	err: store.Error
	for db.next_row(plan, &err) {
		testing.expectf(t, !strings.contains(db.clone_col(plan, 3), "TEMP B-TREE"), "a search sorts: %s", db.clone_col(plan, 3))
	}
	free_all(context.temp_allocator)
}
