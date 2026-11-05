package store

// ---- platform/store: what every store shares (L2) --------------------------
//
// Both families import it: the SQLite stores (app/stores/sqlite/<f>/) and the
// memory stores (app/stores/memory/<f>/). Each feature's store contract, its
// proc types, lives in the feature's models package (PLAN §6.4); this package
// holds only the vocabulary they all use.

import "base:intrinsics"
import "core:mem"
import "core:strings"
import "core:sync"
import "core:unicode"
import "core:unicode/utf8"

import "../escape"

// What a store call fails with, a value the layers above branch on. The
// store's own message goes to the log, never to the client.
Error :: enum u8 {
	None,
	Not_Found,  // no row with that id
	Constraint, // the row broke a NOT NULL, UNIQUE, CHECK or FOREIGN KEY rule
	Busy,       // a queue is full (the writer task, the query pool): answer 503
	Failed,     // anything else: I/O, a lock held past busy_timeout, a full disk
}

// What a store does around each handler, which platform/app's front runs: the
// SQLite store reads a handler's statements in one transaction, one WAL read
// lock where each statement took its own (M1's profile put that lock at 13 % of
// a page). A store registers its pair at open; the memory family has none.
@(private) handler_hooks: [dynamic][2]proc()

on_handler :: proc(begin, end: proc()) {
	append(&handler_hooks, [2]proc(){begin, end})
}

handler_begin :: proc() {
	for h in handler_hooks { h[0]() }
}

handler_end :: proc() {
	for h in handler_hooks { h[1]() }
}

// One migration of one feature's SQLite store: `MIGRATIONS := [?]store.Migration{
// {1, "0001_init.sql", #load("migrations/0001_init.sql", string)}, …}`, a package
// variable (a slice literal inside a proc would point into its frame, 09 §4.4).
// Applied migrations are keyed (feature, seq, name, sha256) and never change.
Migration :: struct {
	seq:  int,
	name: string,
	sql:  string,
}

// The migrations in force, per feature, once the boot's `migrate` calls have run: what
// /admin/modules lists. A memory build has none. Written at boot only.
In_Force :: struct {
	feature: string,
	seq:     int,
	name:    string,
}

in_force: [dynamic]In_Force

// An enum read from a column or a form: an out-of-range value is an error, never
// an index (02 F3: an unchecked enum read from SQLite indexed a label table out
// of bounds). `ok` is false for anything not a member.
enum_from_int :: proc($E: typeid, v: int) -> (e: E, ok: bool) where intrinsics.type_is_enum(E) {
	for m in E {
		if int(m) == v { return m, true }
	}
	return {}, false
}

// One hit of a global search (find): each source's domain fills these. A list of them comes from one
// engine (PLAN §11.8).
Search_Hit :: struct {
	title:   string,
	snippet: string, // text, its hits between escape.MARK_ON and MARK_OFF: html.write_marked writes it
	href:    string,
}

// ---- writes: an op and its continuation ------------------------------------
//
// Under store v3 a write commits on the writer task (D16), batched with the
// writes other loops queued meanwhile; the memory family does it at once. Either
// way the caller's `done` runs afterwards on the loop that queued it: the tail
// of a write handler (publish, notify, answer) is that named proc, with its
// response deferred meanwhile (F-13). A feature's models declare its op, `using`
// Op first, with the input and the result; the family's store fills `run`:
//
//   Create :: struct { using op: store.Op, input: Contact_Input, result: Contact, ref: … }
//
// An op owns its memory, because it can outlive the request that made it: a
// peer that leaves closes its connection, and the arena with it, while the write
// is still queued. `new_op` allocates the op with a block for its strings
// (`op_allocator`), and `free_op` releases both, from `done`.
Op :: struct {
	run:   proc(op: ^Op),   // the family's: does the write (the SQLite family on its writer thread)
	done:  proc(op: ^Op),   // the caller's continuation, on its own loop
	err:   Error,
	loop:  rawptr,          // where `done` runs: the family's bookkeeping
	next:  ^Op,             // the writer queue's link
	arena: mem.Arena,
}

// `bytes`: what its strings need, input and result together; the arena pads each
// allocation for alignment, which OP_SLACK covers.
new_op :: proc($T: typeid, bytes: int) -> ^T where intrinsics.type_is_struct(T) {
	block, _ := mem.alloc_bytes(size_of(T) + bytes + OP_SLACK, align_of(T))
	t := (^T)(raw_data(block))
	mem.arena_init(&(^Op)(t).arena, block[size_of(T):])
	return t
}

OP_SLACK :: 256

// ---- drops: writes a store queued for no one and lost (M4-04) -------------------------------
//
// A store that queues writes nobody waits on (audit's appends) counts the ones a full writer
// refused in a Drops of its own, registered here, so /admin/ops can show them without importing
// that store.

Drops :: struct {
	name: string,
	n:    u64, // atomic
}

MAX_DROPS :: 8

@(private) drops_table: [MAX_DROPS]^Drops
@(private) drops_n: int // atomic

// From the store's @(init): before any thread runs.
register_drops :: proc "contextless" (d: ^Drops) {
	if i := sync.atomic_add(&drops_n, 1); i < MAX_DROPS { drops_table[i] = d }
}

dropped :: proc "contextless" (d: ^Drops) { sync.atomic_add(&d.n, 1) }

every_drops :: proc "contextless" () -> []^Drops { return drops_table[:min(sync.atomic_load(&drops_n), MAX_DROPS)] }

op_allocator :: proc(op: ^Op) -> mem.Allocator {
	return mem.arena_allocator(&op.arena)
}

free_op :: proc(op: ^Op) {
	free(op)
}

// ---- contains_ci: search for both families ----------------------------------
//
// Whether needle occurs in haystack, ignoring case rune by rune (unicode.to_lower,
// as strings.to_lower lowers), so "turİng" finds "Turing" and "straße" finds
// "Straẞe". The SQLite family registers it as the SQL function contains_ci(text,
// q), so a query filters inside the database; SQLite's own LIKE folds ASCII only,
// which would quietly change what a search finds. The memory family calls it
// directly. It walks the original text and allocates nothing (12 §7: FTS5 is for
// big tables, and one result list never mixes the two).
contains_ci :: proc(haystack, needle: string) -> bool {
	if needle == "" { return true }
	for i := 0; i < len(haystack); {
		if _, ok := prefix_ci(haystack[i:], needle); ok { return true }
		_, w := utf8.decode_rune_in_string(haystack[i:])
		i += w
	}
	return false
}

// How much of `s`, in bytes, equals `prefix` ignoring case.
@(private = "file")
prefix_ci :: proc(s, prefix: string) -> (n: int, ok: bool) {
	i, j := 0, 0
	for j < len(prefix) {
		if i >= len(s) { return 0, false }
		// ASCII on both sides (most text, and every e-mail) without the rune decode
		// and the table lookups: SQLite runs this for every row a search examines.
		if x, y := s[i], prefix[j]; x < utf8.RUNE_SELF && y < utf8.RUNE_SELF {
			if x != y && ascii_lower(x) != ascii_lower(y) { return 0, false }
			i += 1
			j += 1
			continue
		}
		a, aw := utf8.decode_rune_in_string(s[i:])
		b, bw := utf8.decode_rune_in_string(prefix[j:])
		if unicode.to_lower(a) != unicode.to_lower(b) { return 0, false }
		i += aw
		j += bw
	}
	return i, true
}

SNIPPET_BEFORE :: 40 // runes kept before the first hit
SNIPPET_RUNES :: 160

// A contains_ci scan's snippet: as FTS5's snippet() gives a SQLite family's, a window of `text` round
// the first hit, every word marked.
snippet :: proc(text: string, words: []string, allocator := context.temp_allocator) -> string {
	hit_at :: proc(s: string, words: []string) -> int {
		for word in words {
			if word == "" { continue }
			if n, ok := prefix_ci(s, word); ok { return n }
		}
		return 0
	}
	first := 0
	for i := 0; i < len(text); {
		if hit_at(text[i:], words) > 0 {
			first = i
			break
		}
		_, width := utf8.decode_rune_in_string(text[i:])
		i += width
	}
	start := first
	for k := 0; k < SNIPPET_BEFORE && start > 0; k += 1 {
		_, width := utf8.decode_last_rune_in_string(text[:start])
		start -= width
	}
	b := strings.builder_make(allocator)
	if start > 0 { strings.write_string(&b, "…") }
	i := start
	for runes := 0; i < len(text) && runes < SNIPPET_RUNES; runes += 1 {
		if n := hit_at(text[i:], words); n > 0 {
			strings.write_string(&b, escape.MARK_ON)
			strings.write_string(&b, text[i:i + n])
			strings.write_string(&b, escape.MARK_OFF)
			i += n
			continue
		}
		_, width := utf8.decode_rune_in_string(text[i:])
		strings.write_string(&b, text[i:i + width])
		i += width
	}
	if i < len(text) { strings.write_string(&b, "…") }
	return strings.to_string(b)
}

@(private = "file")
ascii_lower :: #force_inline proc "contextless" (c: u8) -> u8 {
	return c + ('a' - 'A') if c >= 'A' && c <= 'Z' else c
}
