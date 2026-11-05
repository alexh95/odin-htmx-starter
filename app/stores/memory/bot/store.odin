package bot_store_memory

// ---- the bot's conversations in memory ----------------------------------------------------
//
// Each member's newest KEEP conversations, each with its last TURNS turns, behind the
// store's lock; they go with the process. A conversation is its owner's alone (Q20): every
// read and write names the owner, and another member's id answers .Not_Found. Strings live
// on the heap from their write until their conversation or turn is pushed out; a reader
// gets copies in its request arena, a writer's op in its own.

import "core:mem"
import "core:strings"
import "core:time"

import "../../../platform/store"
import mem_store "../../../platform/store/memory"
import m "../../../features/bot/models"

IMPL :: "memory"

KEEP :: 50   // conversations per member
TURNS :: 200 // turns per conversation

// Members whose conversations are kept: a nickname costs nothing to make, so past this a
// new member's first conversation pushes out another member's (M2-06).
MAX_OWNERS :: 4096

@(private)
Conv :: struct {
	conv:  m.Conversation,
	turns: mem_store.Ring(m.Turn),
}

@(private)
s: struct {
	lock:     mem_store.Lock,
	owners:   map[u64]^mem_store.Ring(^Conv),
	conv_seq: mem_store.Seq,
	turn_seq: mem_store.Seq,
}

conversations :: proc(owner: u64, limit: int, out: ^[dynamic]m.Conversation) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	r := s.owners[owner]
	if r == nil { return .None }
	for i in 0 ..< min(limit, r.n) { append(out, copy_conv(mem_store.ring_newest(r, i)^.conv, context.temp_allocator)) }
	return .None
}

conversation :: proc(owner: u64, id: i64) -> (m.Conversation, m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if c := find(owner, id); c != nil { return copy_conv(c.conv, context.temp_allocator), .None }
	return {}, .Not_Found
}

turns :: proc(owner: u64, conv: i64, out: ^[dynamic]m.Turn) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	c := find(owner, conv)
	if c == nil { return .Not_Found }
	for i := c.turns.n - 1; i >= 0; i -= 1 { append(out, copy_turn(mem_store.ring_newest(&c.turns, i)^, context.temp_allocator)) }
	return .None
}

usage :: proc() -> (u: m.Usage, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	first, total := 0, 0
	for _, r in s.owners {
		for i in 0 ..< r.n {
			c := mem_store.ring_newest(r, i)^
			u.conversations += 1
			for j in 0 ..< c.turns.n {
				t := mem_store.ring_newest(&c.turns, j)
				if t.role != .Assistant { continue }
				u.answers += 1
				u.tokens += t.stats.tokens
				first += t.stats.ms_first_token
				total += t.stats.ms_total
			}
		}
	}
	if u.answers > 0 { u.avg_first_ms, u.avg_total_ms = first / u.answers, total / u.answers }
	return
}

// Stored at once, so the caller's continuation runs before this returns.
start :: proc(op: ^m.Start) -> bool {
	mem_store.lock(&s.lock)
	if s.owners == nil { s.owners = make(map[u64]^mem_store.Ring(^Conv)) }
	r := s.owners[op.owner]
	if r == nil {
		if len(s.owners) >= MAX_OWNERS {
			for owner, old in s.owners {
				for i in 0 ..< old.n { forget(old.items[(old.head + i) % len(old.items)]) }
				delete(old.items)
				free(old)
				delete_key(&s.owners, owner)
				break
			}
		}
		r = new(mem_store.Ring(^Conv))
		mem_store.ring_init(r, KEEP)
		s.owners[op.owner] = r
	}
	c := new(Conv)
	c.conv = {id = mem_store.next_id(&s.conv_seq), owner = op.owner, title = strings.clone(op.title), at = now()}
	mem_store.ring_init(&c.turns, TURNS)
	if old, dropped := mem_store.ring_push(r, c); dropped { forget(old) }
	op.result = copy_conv(c.conv, store.op_allocator(op))
	mem_store.unlock(&s.lock)
	op.err = .None
	mem_store.finish(op)
	return true
}

append_turn :: proc(op: ^m.Append) -> bool {
	mem_store.lock(&s.lock)
	c := find(op.owner, op.turn.conv)
	if c == nil {
		mem_store.unlock(&s.lock)
		op.err = .Not_Found
		mem_store.finish(op)
		return true
	}
	t := op.turn
	t.id, t.at, t.text = mem_store.next_id(&s.turn_seq), now(), strings.clone(op.turn.text)
	if old, dropped := mem_store.ring_push(&c.turns, t); dropped { delete(old.text) }
	c.conv.turns += 1
	if op.title != "" {
		delete(c.conv.title)
		c.conv.title = strings.clone(op.title)
	}
	op.result = copy_turn(t, store.op_allocator(op))
	mem_store.unlock(&s.lock)
	op.err = .None
	mem_store.finish(op)
	return true
}

// ---- inside the lock ----------------------------------------------------------------------

@(private)
find :: proc(owner: u64, id: i64) -> ^Conv {
	r := s.owners[owner]
	if r == nil { return nil }
	for i in 0 ..< r.n {
		if c := mem_store.ring_newest(r, i)^; c.conv.id == id { return c }
	}
	return nil
}

@(private)
forget :: proc(c: ^Conv) {
	for i in 0 ..< c.turns.n { delete(mem_store.ring_newest(&c.turns, i).text) }
	delete(c.turns.items)
	delete(c.conv.title)
	free(c)
}

@(private)
now :: proc() -> i64 { return time.time_to_unix(time.now()) }

@(private)
copy_conv :: proc(c: m.Conversation, a: mem.Allocator) -> m.Conversation {
	out := c
	out.title = strings.clone(c.title, a)
	return out
}

@(private)
copy_turn :: proc(t: m.Turn, a: mem.Allocator) -> m.Turn {
	out := t
	out.text = strings.clone(t.text, a)
	return out
}
