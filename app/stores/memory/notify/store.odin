package notify_store_memory

// ---- notify in memory ---------------------------------------------------------------------
//
// A ring of the newest per member, behind the store's lock; they go when the process
// does. An item's strings are copied to the heap when it is added and freed when its
// ring pushes it out or the sweep takes it; a reader gets copies in its request arena.

import "core:slice"
import "core:strings"
import "core:time"

import "../../../platform/store"
import mem_store "../../../platform/store/memory"
import m "../../../features/notify/models"

IMPL :: "memory"

// notify.KEEP: the store can't import the domain, which imports it.
KEEP :: 200

// Members whose items are kept: a nickname costs nothing to make, so past this a new
// member's first item pushes out another member's whole Inbox (M2-06).
MAX_USERS :: 4096

@(private)
s: struct {
	lock:  mem_store.Lock,
	users: map[u64]^mem_store.Ring(m.Item),
	seq:   mem_store.Seq,
	mutes: map[Mute]bool, // keys on the heap, as long as the process
}

@(private)
Mute :: struct {
	user: u64,
	key:  string,
}

list :: proc(user: u64, limit: int, out: ^[dynamic]m.Item) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := s.users[user]
	if r == nil { return .None }
	for i in 0 ..< min(limit, r.n) {
		it := mem_store.ring_newest(r, i)^
		it.kind = strings.clone(it.kind, context.temp_allocator)
		it.ref = strings.clone(it.ref, context.temp_allocator)
		it.html = strings.clone(it.html, context.temp_allocator)
		append(out, it)
	}
	return .None
}

unread :: proc(user: u64) -> int {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	return count_unread(s.users[user])
}

// Stored at once, so the caller's continuation runs before this returns.
add :: proc(op: ^m.Add) -> bool {
	mem_store.lock(&s.lock)
	it, unread := put(op.user, op.kind, op.ref, op.html)
	op.unread = unread
	mem_store.unlock(&s.lock)
	a := store.op_allocator(op)
	op.result = it
	op.result.kind, op.result.ref, op.result.html = strings.clone(it.kind, a), strings.clone(it.ref, a), strings.clone(it.html, a)
	op.err = .None
	mem_store.finish(op)
	return true
}

add_now :: proc(user: u64, kind, ref, html: string) -> (it: m.Item, unread: int, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	stored: m.Item
	stored, unread = put(user, kind, ref, html)
	it = stored
	it.kind, it.ref, it.html = strings.clone(kind, context.temp_allocator), strings.clone(ref, context.temp_allocator), strings.clone(html, context.temp_allocator)
	return it, unread, .None
}

// Inside the lock: the item on the heap, and the member's unread count.
@(private)
put :: proc(user: u64, kind, ref, html: string) -> (m.Item, int) {
	r := s.users[user]
	if r == nil {
		if len(s.users) >= MAX_USERS {
			for who, old in s.users {
				for i in 0 ..< old.n { free_item(old.items[(old.head + i) % len(old.items)]) }
				delete(old.items)
				free(old)
				delete_key(&s.users, who)
				break
			}
		}
		r = new(mem_store.Ring(m.Item))
		mem_store.ring_init(r, KEEP)
		s.users[user] = r
	}
	it := m.Item{
		id = mem_store.next_id(&s.seq), user = user, at = time.time_to_unix(time.now()),
		kind = strings.clone(kind), ref = strings.clone(ref), html = strings.clone(html),
	}
	if old, dropped := mem_store.ring_push(r, it); dropped { free_item(old) }
	return it, count_unread(r)
}

mute :: proc(user: u64, key: string, on: bool) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	k := Mute{user, key}
	if on {
		if k not_in s.mutes {
			if len(s.mutes) >= MAX_USERS { return .Constraint }
			s.mutes[Mute{user, strings.clone(key)}] = true
		}
	} else {
		owned, _ := delete_key(&s.mutes, k)
		delete(owned.key)
	}
	return .None
}

muted :: proc(user: u64, key: string) -> bool {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	return Mute{user, key} in s.mutes
}

mutes :: proc(user: u64, out: ^[dynamic]string) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	start := len(out)
	for k in s.mutes {
		if k.user == user { append(out, strings.clone(k.key, context.temp_allocator)) }
	}
	slice.sort(out[start:])
	return .None
}

mark_read :: proc(user: u64) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if r := s.users[user]; r != nil {
		for i in 0 ..< r.n { mem_store.ring_newest(r, i).read = true }
	}
	return .None
}

prune :: proc(read_before: i64) -> int {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	gone := 0
	cut := read_before
	for _, r in s.users {
		before := r.n
		for i in 0 ..< r.n {
			it := mem_store.ring_newest(r, i)
			if it.read && it.at < cut { free_item(it^) }
		}
		mem_store.ring_filter(r, proc(it: ^m.Item, data: rawptr) -> bool {
			return !(it.read && it.at < (^i64)(data)^)
		}, &cut)
		gone += before - r.n
	}
	return gone
}

@(private)
count_unread :: proc(r: ^mem_store.Ring(m.Item)) -> int {
	if r == nil { return 0 }
	n := 0
	for i in 0 ..< r.n {
		if !mem_store.ring_newest(r, i).read { n += 1 }
	}
	return n
}

@(private)
free_item :: proc(it: m.Item) {
	delete(it.kind)
	delete(it.ref)
	delete(it.html)
}
