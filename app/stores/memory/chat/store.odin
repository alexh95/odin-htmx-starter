package chat_store_memory

// ---- chat in memory (PLAN §14.1, D16) ------------------------------------------------------
//
// In memory mode the ring is the history: the last KEEP messages per room, under one
// global byte budget (CHAT_RING_BYTES) that takes the oldest rooms' tails first, or fewer when its
// kind's cap is under KEEP, none older than its kind's age (the sweep), and a
// restart empties it all, which the room page says ("ephemeral"). Rows behind the
// store's lock; a message's strings are on the heap from its post until the ring or the
// budget lets it go, and a reader gets copies in its request arena.

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"

import "../../../platform/store"
import mem_store "../../../platform/store/memory"
import m "../../../features/chat/models"

IMPL :: "memory"

// Not persisted (D13): a gap after a restart can't replay ids from another process,
// so the room's topic resyncs instead.
PERSISTED :: false

// Message ids and room versions count from the boot time (ms) × EPOCH_SPAN, the
// `<epoch>-<seq>` of §14.1 as one number: a page from before a restart keeps its
// messages, and the new process's never take their ids (upsert would replace them),
// while a poll's old tag or a multipart's old part id reads as older than anything here.
EPOCH_SPAN :: 1_000_000

KEEP :: 100       // per room, the ring (§14.1)
MAX_ROOMS :: 100  // rooms of every kind in a memory build
MAX_MEMBERS :: 64 // of a private room in a memory build

@(private)
Room_State :: struct {
	room:    m.Room,
	ring:    mem_store.Ring(m.Message),
	ver:     i64,
	bytes:   int,
	dropped: i64, // the newest message let go: a cursor below it can't be served whole (M2-31)
	dropped_ver: i64, // and the newest version among those let go: a poll's tag below it can't be (M2-35)
	members: [dynamic]m.Member, // a private room's or a DM's; names on the heap
	dm:      [2]u64, // a DM's pair, the lower id first
}

@(private)
s: struct {
	lock:      mem_store.Lock,
	rooms:     [dynamic]^Room_State,
	room_seq:  mem_store.Seq,
	invite_seq: mem_store.Seq,
	invites:   [dynamic]m.Invite, // strings on the heap; a revoked or spent one stays, as a row would
	bans:      [dynamic]m.Ban,
	reports:   [dynamic]m.Report, // strings on the heap; MAX_REPORTS, the oldest resolved going first
	report_seq: mem_store.Seq,
	msg_seq:   mem_store.Seq,
	blocks:    [dynamic]Block_Row, // names on the heap; MAX_BLOCKS, the oldest going first
	base:      i64,
	bytes:     int,
	max_bytes: int,
	keep:      m.Retention,
}

init :: proc(ring_bytes: int, keep: m.Retention) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	s.max_bytes = ring_bytes
	s.keep = keep
	if s.base == 0 {
		s.base = time.time_to_unix_nano(time.now()) / 1e6 * EPOCH_SPAN
		s.msg_seq.last = s.base
	}
}

rooms :: proc(out: ^[dynamic]m.Room) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for r in s.rooms { append(out, copy_room(r.room)) }
	return .None
}

rooms_for :: proc(who: u64, out: ^[dynamic]m.Room) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for r in s.rooms {
		if r.room.kind == .Public || r.room.kind == .Announce || member_at(r, who) >= 0 { append(out, copy_room(r.room)) }
	}
	return .None
}

room :: proc(slug: string) -> (m.Room, m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if r := find(slug); r != nil { return copy_room(r.room), .None }
	return {}, .Not_Found
}

create_room :: proc(slug, name: string, kind: m.Room_Kind, owner: u64, owner_name: string) -> (room: m.Room, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := add_room(slug, name, kind, owner) or_return
	if kind == .Private || kind == .Dm { add_member(r, owner, owner_name) }
	return copy_room(r.room), .None
}

// The DM of `a` and `b`, or a new one with both as members.
dm :: proc(a: u64, a_name: string, b: u64, b_name: string, slug: string) -> (room: m.Room, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	pair := [2]u64{min(a, b), max(a, b)}
	for r in s.rooms {
		if r.room.kind == .Dm && r.dm == pair { return copy_room(r.room), .None }
	}
	r := add_room(slug, fmt.tprintf("%s and %s", a_name, b_name), .Dm, a) or_return
	r.dm = pair
	add_member(r, a, a_name)
	add_member(r, b, b_name)
	return copy_room(r.room), .None
}

members :: proc(room_id: i64, out: ^[dynamic]m.Member) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := by_id(room_id)
	if r == nil { return .Not_Found }
	for mem in r.members {
		c := mem
		c.name = strings.clone(mem.name, context.temp_allocator)
		append(out, c)
	}
	return .None
}

is_member :: proc(room_id: i64, who: u64) -> bool {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := by_id(room_id)
	return r != nil && member_at(r, who) >= 0
}

// .None when they are in it already; .Constraint when the room is full.
join :: proc(room_id: i64, who: u64, name: string) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := by_id(room_id)
	if r == nil { return .Not_Found }
	if member_at(r, who) >= 0 { return .None }
	if len(r.members) >= MAX_MEMBERS { return .Constraint }
	add_member(r, who, name)
	return .None
}

leave :: proc(room_id: i64, who: u64) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := by_id(room_id)
	if r == nil { return .Not_Found }
	if i := member_at(r, who); i >= 0 {
		delete(r.members[i].name)
		ordered_remove(&r.members, i)
	}
	return .None
}

recent :: proc(room_id: i64, limit: int, out: ^[dynamic]m.Message) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := by_id(room_id)
	if r == nil { return .Not_Found }
	n := min(limit, r.ring.n)
	for i := n - 1; i >= 0; i -= 1 { append(out, copy_msg(mem_store.ring_newest(&r.ring, i)^)) }
	return .None
}

after :: proc(room_id: i64, after_id: i64, out: ^[dynamic]m.Message) -> (reached: bool, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := by_id(room_id)
	if r == nil { return false, .Not_Found }
	for i := r.ring.n - 1; i >= 0; i -= 1 {
		msg := mem_store.ring_newest(&r.ring, i)
		if msg.id > after_id { append(out, copy_msg(msg^)) }
	}
	return r.dropped <= after_id, .None
}

count_after :: proc(room_id: i64, after_id: i64) -> int {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := by_id(room_id)
	if r == nil { return 0 }
	n := 0
	for i in 0 ..< r.ring.n {
		if mem_store.ring_newest(&r.ring, i).id <= after_id { break }
		n += 1
	}
	return n
}

changed :: proc(room_id: i64, since: i64, out: ^[dynamic]m.Message) -> (ver: i64, reached: bool, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := by_id(room_id)
	if r == nil { return 0, false, .Not_Found }
	for i := r.ring.n - 1; i >= 0; i -= 1 {
		msg := mem_store.ring_newest(&r.ring, i)
		if msg.ver > since { append(out, copy_msg(msg^)) }
	}
	return r.ver, r.dropped_ver <= since, .None
}

message :: proc(id: i64) -> (m.Message, m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if msg, _ := find_msg(id); msg != nil { return copy_msg(msg^), .None }
	return {}, .Not_Found
}

// Stored at once, so the caller's continuation runs before this returns.
post :: proc(op: ^m.Post) -> bool {
	mem_store.lock(&s.lock)
	r := by_id(op.room)
	if r == nil {
		mem_store.unlock(&s.lock)
		op.err = .Not_Found
		mem_store.finish(op)
		return true
	}
	r.ver += 1
	msg := m.Message{
		id = mem_store.next_id(&s.msg_seq), room = r.room.id, author = op.author, at = now(), ver = r.ver,
		name = strings.clone(op.name), body = strings.clone(op.body), blob = strings.clone(op.blob),
	}
	if old, dropped := mem_store.ring_push(&r.ring, msg); dropped { forget(r, old) }
	r.bytes += cost(msg)
	s.bytes += cost(msg)
	evict()
	mem_store.unlock(&s.lock)
	op.result = clone_into(msg, store.op_allocator(op))
	op.err = .None
	mem_store.finish(op)
	return true
}

change :: proc(op: ^m.Change) -> bool {
	mem_store.lock(&s.lock)
	msg, r := find_msg(op.id)
	switch {
	case msg == nil || msg.gone:
		op.err = .Not_Found
	case !op.moderated && (msg.author != op.author || now() - msg.at > op.window):
		op.err = .Constraint
	case:
		r.ver += 1
		r.bytes -= cost(msg^)
		s.bytes -= cost(msg^)
		delete(msg.body)
		if op.delete {
			op.released = strings.clone(msg.blob, store.op_allocator(op))
			delete(msg.blob)
			msg.body, msg.blob, msg.gone = "", "", true
		} else {
			msg.body, msg.edited = strings.clone(op.body), now()
		}
		msg.ver = r.ver
		r.bytes += cost(msg^)
		s.bytes += cost(msg^)
		op.result = clone_into(msg^, store.op_allocator(op))
		op.err = .None
	}
	mem_store.unlock(&s.lock)
	if op.err == .None && op.moderated { note(op.audit) } // a log line: nothing to undo
	mem_store.finish(op)
	return true
}

// ---- search --------------------------------------------------------------------------------

// A contains_ci scan of the rings: what FTS5 folds (`cafe` for `café`) this doesn't (§11.8).
search :: proc(who: u64, words: []string, at: i64, limit: int, out: ^[dynamic]m.Hit) -> m.Error {
	if len(words) == 0 { return .None }
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	lower := make([]string, len(words), context.temp_allocator)
	for w, i in words { lower[i] = strings.to_lower(w, context.temp_allocator) }
	start := len(out)
	for r in s.rooms {
		switch r.room.kind {
		case .Public, .Announce:
			if kicked(r.room.id, who, at) { continue }
		case .Private, .Dm:
			if member_at(r, who) < 0 { continue }
		}
		for i in 0 ..< r.ring.n { // newest first
			msg := mem_store.ring_newest(&r.ring, i)
			if msg.gone { continue }
			body := strings.to_lower(msg.body, context.temp_allocator)
			all := true
			for w in lower {
				if !strings.contains(body, w) {
					all = false
					break
				}
			}
			if all { append(out, m.Hit{msg = copy_msg(msg^), room = copy_room(r.room)}) }
		}
	}
	slice.sort_by(out[start:], proc(a, b: m.Hit) -> bool { return a.msg.id > b.msg.id })
	if len(out) - start > limit { resize(out, start + limit) }
	return .None
}

@(private)
kicked :: proc(room_id: i64, who: u64, at: i64) -> bool {
	for b in s.bans {
		if b.room == room_id && b.who == who && b.kind == .Kick && b.until > at { return true }
	}
	return false
}

// ---- moderation ----------------------------------------------------------------------------

MAX_REPORTS :: 1000 // in a memory build

@(private) audit_writer: m.Audit_Writer

set_audit_writer :: proc(w: m.Audit_Writer) { audit_writer = w }

// The memory family's audit is a log line, written after the change: there is no transaction to
// share, and a line can't fail.
@(private)
note :: proc(a: m.Audit) {
	if a.action != "" && audit_writer != nil { _ = audit_writer(a.actor_id, a.actor_name, a.client, a.action, a.target_kind, a.target_id, a.reason, a.meta) }
}

set_room :: proc(room_id: i64, locked: bool, slow: int, audit: m.Audit) -> m.Error {
	mem_store.lock(&s.lock)
	r := by_id(room_id)
	if r != nil { r.room.locked, r.room.slow = locked, slow }
	mem_store.unlock(&s.lock)
	if r == nil { return .Not_Found }
	note(audit)
	return .None
}

ban :: proc(b: m.Ban, audit: m.Audit) -> m.Error {
	mem_store.lock(&s.lock)
	found := false
	for &old in s.bans {
		if old.room == b.room && old.who == b.who && old.kind == b.kind {
			old.until, old.by, found = b.until, b.by, true
			break
		}
	}
	if !found {
		row := b
		row.name = strings.clone(b.name) // for as long as the process, as a ban's row is
		append(&s.bans, row)
	}
	mem_store.unlock(&s.lock)
	note(audit)
	return .None
}

removed :: proc(room: i64, at: i64, out: ^[dynamic]m.Ban) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for b in s.bans {
		if b.room == room && b.kind == .Removed && b.until > at {
			row := b
			row.name = strings.clone(b.name, context.temp_allocator)
			append(out, row)
		}
	}
	return .None
}

banned :: proc(room_id: i64, who: u64, kind: m.Ban_Kind, at: i64) -> (until: i64) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for b in s.bans {
		if b.room == room_id && b.who == who && b.kind == kind && b.until > at { return b.until }
	}
	return 0
}

report :: proc(r: m.Report) -> (id: i64, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for old in s.reports {
		if old.resolved == 0 && old.msg == r.msg && old.by == r.by { return 0, .None }
	}
	if len(s.reports) >= MAX_REPORTS {
		gone := 0
		for old, i in s.reports {
			if old.resolved != 0 {
				gone = i
				break
			}
		}
		free_report(s.reports[gone])
		ordered_remove(&s.reports, gone)
	}
	row := r
	row.id, row.resolved, row.outcome = mem_store.next_id(&s.report_seq), 0, ""
	row.author_name, row.body, row.by_name, row.reason = strings.clone(r.author_name), strings.clone(r.body), strings.clone(r.by_name), strings.clone(r.reason)
	row.blob = strings.clone(r.blob)
	append(&s.reports, row)
	return row.id, .None
}

reports :: proc(limit: int, out: ^[dynamic]m.Report) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for r in s.reports {
		if r.resolved == 0 && len(out) < limit { append(out, copy_report(r)) }
	}
	return .None
}

open_reports :: proc(by: u64) -> (theirs, all: int) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for r in s.reports {
		if r.resolved != 0 { continue }
		all += 1
		if r.by == by { theirs += 1 }
	}
	return
}

room_of :: proc(id: i64) -> (m.Room, m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if r := by_id(id); r != nil { return copy_room(r.room), .None }
	return {}, .Not_Found
}

rooms_owned :: proc(owner: u64) -> int {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	n := 0
	for r in s.rooms {
		if r.room.owner == owner && r.room.kind != .Dm { n += 1 }
	}
	return n
}

report_of :: proc(id: i64) -> (m.Report, m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for r in s.reports {
		if r.id == id { return copy_report(r), .None }
	}
	return {}, .Not_Found
}

resolve :: proc(id: i64, at: i64, outcome: string, audit: m.Audit) -> m.Error {
	mem_store.lock(&s.lock)
	found := false
	for &r in s.reports {
		if r.id == id && r.resolved == 0 {
			r.resolved, r.outcome, found = at, outcome, true // the outcome is one of two literals
			delete(r.body)
			delete(r.blob)
			r.body, r.blob = "", ""
			break
		}
	}
	mem_store.unlock(&s.lock)
	if !found { return .Not_Found }
	note(audit)
	return .None
}

@(private)
copy_report :: proc(r: m.Report) -> m.Report {
	out := r
	out.author_name, out.body = strings.clone(r.author_name, context.temp_allocator), strings.clone(r.body, context.temp_allocator)
	out.by_name, out.reason = strings.clone(r.by_name, context.temp_allocator), strings.clone(r.reason, context.temp_allocator)
	out.blob = strings.clone(r.blob, context.temp_allocator)
	return out
}

@(private)
free_report :: proc(r: m.Report) {
	delete(r.author_name)
	delete(r.body)
	delete(r.by_name)
	delete(r.reason)
	delete(r.blob)
}

// ---- blobs ------------------------------------------------------------------------------------

blob_held :: proc(sha256: string) -> bool {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for r in s.rooms {
		for i in 0 ..< r.ring.n {
			if mem_store.ring_newest(&r.ring, i).blob == sha256 { return true }
		}
	}
	for rep in s.reports {
		if rep.resolved == 0 && rep.blob == sha256 { return true }
	}
	return false
}

purge_blob :: proc(sha256: string, audit: m.Audit, out: ^[dynamic]m.Message) -> m.Error {
	mem_store.lock(&s.lock)
	for r in s.rooms {
		for i in 0 ..< r.ring.n {
			msg := mem_store.ring_newest(&r.ring, i)
			if msg.blob != sha256 { continue }
			r.ver += 1
			r.bytes -= cost(msg^)
			s.bytes -= cost(msg^)
			delete(msg.blob)
			msg.blob, msg.ver = "", r.ver
			r.bytes += cost(msg^)
			s.bytes += cost(msg^)
			append(out, copy_msg(msg^))
		}
	}
	for &rep in s.reports {
		if rep.blob == sha256 {
			delete(rep.blob)
			rep.blob = ""
		}
	}
	mem_store.unlock(&s.lock)
	note(audit)
	return .None
}

// ---- blocks -----------------------------------------------------------------------------------

MAX_BLOCKS :: 4096

@(private)
Block_Row :: struct {
	who: u64,
	row: m.Block,
}

block :: proc(who, other: u64, name: string, at: i64) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for b in s.blocks {
		if b.who == who && b.row.other == other { return .None }
	}
	if len(s.blocks) >= MAX_BLOCKS {
		delete(s.blocks[0].row.name)
		ordered_remove(&s.blocks, 0)
	}
	append(&s.blocks, Block_Row{who, {other, strings.clone(name), at}})
	return .None
}

unblock :: proc(who, other: u64) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for b, i in s.blocks {
		if b.who == who && b.row.other == other {
			delete(b.row.name)
			ordered_remove(&s.blocks, i)
			break
		}
	}
	return .None
}

blocking :: proc(who, other: u64) -> bool {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for b in s.blocks {
		if b.who == who && b.row.other == other { return true }
	}
	return false
}

blocks :: proc(who: u64, out: ^[dynamic]m.Block) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	#reverse for b in s.blocks {
		if b.who == who { append(out, m.Block{b.row.other, strings.clone(b.row.name, context.temp_allocator), b.row.at}) }
	}
	return .None
}

// What is older than each room's kind's age goes, oldest first.
sweep :: proc(at: i64) -> (removed: int, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for r in s.rooms {
		age := s.keep.age[r.room.kind]
		if age <= 0 { continue }
		for r.ring.n > 0 {
			oldest := mem_store.ring_newest(&r.ring, r.ring.n - 1)^
			if oldest.at >= at - age { break }
			r.ring.head = (r.ring.head + 1) % len(r.ring.items)
			r.ring.n -= 1
			forget(r, oldest)
			removed += 1
		}
	}
	return removed, .None
}

// The lobby, into an empty store.
seed :: proc() {
	mem_store.lock(&s.lock)
	empty := len(s.rooms) == 0
	mem_store.unlock(&s.lock)
	if empty { _, _ = create_room("lobby", "Lobby", .Public, 0, "") }
}

// ---- inside the lock ----------------------------------------------------------------------

// ---- invites -------------------------------------------------------------------------------

MAX_INVITES :: 1000 // in a memory build: past it, the oldest closed one goes, else the oldest

add_invite :: proc(inv: m.Invite) -> (id: i64, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if by_id(inv.room) == nil { return 0, .Not_Found }
	if len(s.invites) >= MAX_INVITES {
		at, gone := now(), 0
		for old, i in s.invites {
			if !is_open(old, at) {
				gone = i
				break
			}
		}
		delete(s.invites[gone].hash)
		delete(s.invites[gone].by_name)
		ordered_remove(&s.invites, gone)
	}
	row := inv
	row.id, row.uses, row.revoked = mem_store.next_id(&s.invite_seq), 0, 0
	row.hash, row.by_name = strings.clone(inv.hash), strings.clone(inv.by_name)
	append(&s.invites, row)
	return row.id, .None
}

invite :: proc(id: i64) -> (m.Invite, m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if i := invite_at(id); i >= 0 { return copy_invite(s.invites[i]), .None }
	return {}, .Not_Found
}

invites :: proc(room_id: i64, at: i64, out: ^[dynamic]m.Invite) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	#reverse for inv in s.invites {
		if inv.room == room_id && is_open(inv, at) { append(out, copy_invite(inv)) }
	}
	return .None
}

revoke_invite :: proc(id, room_id, at: i64) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	i := invite_at(id)
	if i < 0 || s.invites[i].room != room_id || s.invites[i].revoked != 0 { return .Not_Found }
	s.invites[i].revoked = at
	return .None
}

use_invite :: proc(id, at: i64, who: u64, name: string) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	i := invite_at(id)
	if i < 0 || !is_open(s.invites[i], at) { return .Not_Found }
	r := by_id(s.invites[i].room)
	if r == nil { return .Not_Found }
	for b in s.bans {
		if b.room == r.room.id && b.who == who && b.kind == .Removed && b.until > at { return .Not_Found }
	}
	if member_at(r, who) >= 0 { return .None }
	if len(r.members) >= MAX_MEMBERS { return .Constraint }
	add_member(r, who, name)
	s.invites[i].uses += 1
	return .None
}

@(private)
is_open :: proc(inv: m.Invite, at: i64) -> bool {
	return inv.revoked == 0 && inv.expires > at && (inv.max_uses == 0 || inv.uses < inv.max_uses)
}

@(private)
invite_at :: proc(id: i64) -> int {
	for inv, i in s.invites {
		if inv.id == id { return i }
	}
	return -1
}

@(private)
copy_invite :: proc(inv: m.Invite) -> m.Invite {
	out := inv
	out.hash = strings.clone(inv.hash, context.temp_allocator)
	out.by_name = strings.clone(inv.by_name, context.temp_allocator)
	return out
}

@(private)
add_room :: proc(slug, name: string, kind: m.Room_Kind, owner: u64) -> (^Room_State, m.Error) {
	if find(slug) != nil || len(s.rooms) >= MAX_ROOMS { return nil, .Constraint }
	r := new(Room_State)
	r.room = {id = mem_store.next_id(&s.room_seq), slug = strings.clone(slug), name = strings.clone(name), at = now(), kind = kind, owner = owner}
	cap := s.keep.cap[kind]
	mem_store.ring_init(&r.ring, min(KEEP, cap) if cap > 0 else KEEP)
	r.ver = s.base
	append(&s.rooms, r)
	return r, .None
}

@(private)
add_member :: proc(r: ^Room_State, who: u64, name: string) {
	append(&r.members, m.Member{room = r.room.id, who = who, name = strings.clone(name), at = now()})
}

// Its index in the room's members, or -1.
@(private)
member_at :: proc(r: ^Room_State, who: u64) -> int {
	for mem, i in r.members {
		if mem.who == who { return i }
	}
	return -1
}

@(private)
find :: proc(slug: string) -> ^Room_State {
	for r in s.rooms {
		if r.room.slug == slug { return r }
	}
	return nil
}

@(private)
by_id :: proc(id: i64) -> ^Room_State {
	for r in s.rooms {
		if r.room.id == id { return r }
	}
	return nil
}

@(private)
find_msg :: proc(id: i64) -> (^m.Message, ^Room_State) {
	for r in s.rooms {
		for i in 0 ..< r.ring.n {
			msg := mem_store.ring_newest(&r.ring, i)
			if msg.id == id { return msg, r }
		}
	}
	return nil, nil
}

// Past the budget, the oldest message of whichever room holds the oldest goes, until
// it fits: the quiet rooms' tails first (§14.1).
@(private)
evict :: proc() {
	for s.max_bytes > 0 && s.bytes > s.max_bytes {
		oldest: ^Room_State
		for r in s.rooms {
			if r.ring.n == 0 { continue }
			if oldest == nil || mem_store.ring_newest(&r.ring, r.ring.n - 1).id < mem_store.ring_newest(&oldest.ring, oldest.ring.n - 1).id { oldest = r }
		}
		if oldest == nil { return }
		tail := mem_store.ring_newest(&oldest.ring, oldest.ring.n - 1)^
		oldest.ring.head = (oldest.ring.head + 1) % len(oldest.ring.items)
		oldest.ring.n -= 1
		forget(oldest, tail)
	}
}

@(private)
forget :: proc(r: ^Room_State, msg: m.Message) {
	r.dropped = max(r.dropped, msg.id)
	r.dropped_ver = max(r.dropped_ver, msg.ver)
	r.room.dropped = r.dropped
	r.bytes -= cost(msg)
	s.bytes -= cost(msg)
	delete(msg.name)
	delete(msg.body)
	delete(msg.blob)
}

@(private)
cost :: proc(msg: m.Message) -> int {
	return size_of(m.Message) + len(msg.name) + len(msg.body) + len(msg.blob)
}

@(private)
now :: proc() -> i64 { return time.time_to_unix(time.now()) }

@(private)
copy_room :: proc(r: m.Room) -> m.Room {
	out := r
	out.slug = strings.clone(r.slug, context.temp_allocator)
	out.name = strings.clone(r.name, context.temp_allocator)
	return out
}

@(private)
copy_msg :: proc(msg: m.Message) -> m.Message {
	return clone_into(msg, context.temp_allocator)
}

@(private)
clone_into :: proc(msg: m.Message, a: mem.Allocator) -> m.Message {
	out := msg
	out.name = strings.clone(msg.name, a)
	out.body = strings.clone(msg.body, a)
	out.blob = strings.clone(msg.blob, a)
	return out
}
