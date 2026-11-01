package chat_store_memory

// ---- chat in memory (PLAN §14.1, D16) ------------------------------------------------------
//
// In memory mode the ring is the history: the last KEEP messages per room, under one
// global byte budget (CHAT_RING_BYTES) that takes the oldest rooms' tails first, and a
// restart empties it all, which the room page says ("ephemeral"). Rows behind the
// store's lock; a message's strings are on the heap from its post until the ring or the
// budget lets it go, and a reader gets copies in its request arena.

import "core:fmt"
import "core:mem"
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
	msg_seq:   mem_store.Seq,
	base:      i64,
	bytes:     int,
	max_bytes: int,
}

init :: proc(ring_bytes: int) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	s.max_bytes = ring_bytes
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
		name = strings.clone(op.name), body = strings.clone(op.body),
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
	case msg.author != op.author || now() - msg.at > op.window:
		op.err = .Constraint
	case:
		r.ver += 1
		r.bytes -= cost(msg^)
		s.bytes -= cost(msg^)
		delete(msg.body)
		if op.delete {
			msg.body, msg.gone = "", true
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
	mem_store.finish(op)
	return true
}

// The lobby, into an empty store.
seed :: proc() {
	mem_store.lock(&s.lock)
	empty := len(s.rooms) == 0
	mem_store.unlock(&s.lock)
	if empty { _, _ = create_room("lobby", "Lobby", .Public, 0, "") }
}

// ---- inside the lock ----------------------------------------------------------------------

@(private)
add_room :: proc(slug, name: string, kind: m.Room_Kind, owner: u64) -> (^Room_State, m.Error) {
	if find(slug) != nil || len(s.rooms) >= MAX_ROOMS { return nil, .Constraint }
	r := new(Room_State)
	r.room = {id = mem_store.next_id(&s.room_seq), slug = strings.clone(slug), name = strings.clone(name), at = now(), kind = kind, owner = owner}
	mem_store.ring_init(&r.ring, KEEP)
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
	r.bytes -= cost(msg)
	s.bytes -= cost(msg)
	delete(msg.name)
	delete(msg.body)
}

@(private)
cost :: proc(msg: m.Message) -> int {
	return size_of(m.Message) + len(msg.name) + len(msg.body)
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
	return out
}
