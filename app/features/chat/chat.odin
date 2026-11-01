package chat

// ---- chat: the domain (PLAN §14.1, D30) ---------------------------------------------------
//
// Rooms and their messages through the store, and what lives only in this process
// whatever the store: who is in a room (presence), how far each member has read, and
// the names mentions are matched against. Plain values and errors, never HTTP.

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"

import "../../platform/env"
import "../../platform/guard"
import "../../platform/sys"
import m "models"
import chat_store "store:chat"

IMPL :: chat_store.IMPL

// Whether a message's id survives a restart, so a page may resume a room's topic
// from the newest id it rendered (D13). The memory store's don't.
PERSISTED :: chat_store.PERSISTED

MAX_BODY :: 2000 // runes, cut by rune (the skeleton's rule)
MAX_ROOM_NAME :: 40
EDIT_WINDOW :: 10 * time.Minute
SNAPSHOT :: 50 // what a page, a socket's (re)connect and a resync show

// Presence (D14): online while a stream is open; away once the last closed, after
// a debounce so a reload doesn't flap; gone after AWAY_FOR.
PRESENCE_DEBOUNCE :: 10 * time.Second
AWAY_FOR :: 5 * time.Minute

// A nickname costs nothing to make, so what is kept per member is bounded: past
// MAX_MEMBERS names, or MAX_READERS readers of one room, one is forgotten to make
// room (a forgotten name is learnt again from the member's next page; a forgotten
// cursor shows no count until they next read). Each post publishes a count to
// every reader of its room, so readers are capped far lower (M2-08).
MAX_MEMBERS :: 4096
MAX_READERS :: 256

Transport :: enum u8 {
	Ws,
	Sse,
	Poll,
	Multipart,
}

// The name a cookie, `?transport=` and CHAT_TRANSPORT use, and the setting's label.
TRANSPORTS := [Transport]struct {
	name, label: string,
} {
	.Ws        = {"ws", "WebSocket"},
	.Sse       = {"sse", "Streaming"},
	.Poll      = {"poll", "Polling"},
	.Multipart = {"multipart", "Multipart"},
}

ENV := [?]env.Row {
	{name = "CHAT_TRANSPORT", kind = .Enum, def = "ws", choices = "ws|sse|poll|multipart", doc = "a room's connection when the viewer chose none (§14.1)"},
	{name = "CHAT_RING_BYTES", kind = .Size, def = "16MiB", doc = "bytes every room's last 100 messages hold in all; the oldest rooms' tails go first"},
}

@(private)
st: struct {
	mu:        guard.Mutex,
	transport: Transport,
	names:     map[u64]string,            // member → the name they last used here, for mentions
	read:      map[i64]map[u64]i64,       // room → member → the newest id they have seen
	here:      map[i64]map[u64]Presence,  // room → member → their presence
}

// At boot: the env rows, the store's ring budget, the lobby.
init :: proc() {
	env.record("CHAT_", ENV[:])
	st.transport = transport_named(env.str("CHAT_TRANSPORT")) or_else .Ws
	chat_store.init(env.size("CHAT_RING_BYTES"))
	chat_store.seed()
}

default_transport :: proc() -> Transport { return st.transport }

transport_named :: proc(name: string) -> (Transport, bool) {
	for t, k in TRANSPORTS {
		if t.name == name { return k, true }
	}
	return .Ws, false
}

// ---- topics (chat_web's TOPICS declares the families) --------------------------------------

// A room's messages, posted, edited and deleted.
room_topic :: proc(room: i64) -> string { return fmt.tprintf("chat.room:%d", room) }

// Who is in a room, and who is typing in it (.Latest, keyed per member).
presence_topic :: proc(room: i64) -> string { return fmt.tprintf("chat.presence:%d", room) }
typing_topic :: proc(room: i64) -> string { return fmt.tprintf("chat.typing:%d", room) }

// ---- rooms -------------------------------------------------------------------------------

rooms :: proc(out: ^[dynamic]m.Room) -> m.Error { return chat_store.rooms(out) }
room :: proc(slug: string) -> (m.Room, m.Error) { return chat_store.room(slug) }

// A room's name, trimmed, and the slug it gets ([a-z0-9-], from the name), or why
// it was refused.
check_room :: proc(name: string) -> (trimmed, slug, problem: string) {
	trimmed = strings.trim_space(name)
	n := utf8.rune_count_in_string(trimmed)
	if n == 0 { return "", "", "Name the room first." }
	if n > MAX_ROOM_NAME { return "", "", fmt.tprintf("A room's name is at most %d characters.", MAX_ROOM_NAME) }
	b := strings.builder_make(context.temp_allocator)
	dash := false
	for r in trimmed {
		switch {
		case r < utf8.RUNE_SELF && (unicode.is_letter(r) || unicode.is_digit(r)):
			if dash && strings.builder_len(b) > 0 { strings.write_byte(&b, '-') }
			strings.write_rune(&b, unicode.to_lower(r))
			dash = false
		case:
			dash = true
		}
	}
	slug = strings.to_string(b)
	if slug == "" { return "", "", "A room's name needs a letter or a digit (a-z, 0-9)." }
	return trimmed, slug, ""
}

create_room :: proc(slug, name: string) -> (m.Room, m.Error) { return chat_store.create_room(slug, name) }

// A message's room, for its menu's link.
room_by_id :: proc(id: i64) -> (m.Room, m.Error) {
	all := make([dynamic]m.Room, 0, 16, context.temp_allocator)
	if err := chat_store.rooms(&all); err != .None { return {}, err }
	for r in all {
		if r.id == id { return r, .None }
	}
	return {}, .Not_Found
}

// ---- messages ----------------------------------------------------------------------------

// The newest SNAPSHOT, oldest first.
recent :: proc(room: i64, out: ^[dynamic]m.Message) -> m.Error { return chat_store.recent(room, SNAPSHOT, out) }

// What came after `id`, oldest first: a multipart reconnect's HX-Last-Part-ID.
after :: proc(room, id: i64, out: ^[dynamic]m.Message) -> (reached: bool, err: m.Error) { return chat_store.after(room, id, out) }

// What changed (posted, edited, deleted) since the room's version `since`, the version
// now (the poll transport's tag), and whether the room still holds all of it: false when
// something changed after `since` has since left it (M2-35).
changed :: proc(room, since: i64, out: ^[dynamic]m.Message) -> (ver: i64, reached: bool, err: m.Error) {
	return chat_store.changed(room, since, out)
}

message :: proc(id: i64) -> (m.Message, m.Error) { return chat_store.message(id) }

// The newest SNAPSHOT and the room's version now: a poll's first answer, a resync's.
snapshot :: proc(room: i64, out: ^[dynamic]m.Message) -> (ver: i64, err: m.Error) {
	none := make([dynamic]m.Message, context.temp_allocator)
	ver, _ = chat_store.changed(room, max(i64), &none) or_return
	return ver, chat_store.recent(room, SNAPSHOT, out)
}

// The trimmed body, or why it was refused (the member's to fix).
check_body :: proc(body: string) -> (trimmed, problem: string) {
	trimmed = strings.trim_space(body)
	switch {
	case trimmed == "":
		return "", "Write something first."
	case utf8.rune_count_in_string(trimmed) > MAX_BODY:
		return "", fmt.tprintf("A message is at most %d characters.", MAX_BODY)
	}
	return trimmed, ""
}

// Stores op's message; op.done runs once it is. false: the store is busy.
post :: proc(op: ^m.Post) -> bool {
	seen(op.author, op.name)
	return chat_store.post(op)
}

// An edit or a delete of the member's own message, inside EDIT_WINDOW.
change :: proc(op: ^m.Change) -> bool {
	op.window = i64(EDIT_WINDOW / time.Second)
	return chat_store.change(op)
}

// Whether `who` may still edit or delete `msg`: the menu's question, which the
// store answers again when they do.
may_change :: proc(msg: m.Message, who: u64) -> bool {
	return !msg.gone && who != 0 && msg.author == who && now() - msg.at <= i64(EDIT_WINDOW / time.Second)
}

// ---- mentions -----------------------------------------------------------------------------

// Remembers the name a member uses, so `@name` finds them.
seen :: proc(id: u64, name: string) {
	if id == 0 { return }
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	if st.names == nil { st.names = make(map[u64]string, heap()) }
	if old, ok := st.names[id]; ok {
		if old == name { return }
		delete(old, heap())
	} else if len(st.names) >= MAX_MEMBERS {
		for k, n in st.names {
			delete(n, heap())
			delete_key(&st.names, k)
			break
		}
	}
	st.names[id] = strings.clone(name, heap())
}

// The members named by `@name` in `body` (a name as nick allows it, compared without
// case), the author left out.
mentioned :: proc(body: string, author: u64, out: ^[dynamic]u64) {
	names := make([dynamic]string, 0, 4, context.temp_allocator)
	rest := body
	for {
		at := strings.index_byte(rest, '@')
		if at < 0 { break }
		rest = rest[at + 1:]
		end := 0
		for r, i in rest {
			if !(unicode.is_letter(r) || unicode.is_digit(r) || r == '_' || r == '-' || r == '.') { break }
			end = i + utf8.rune_size(r)
		}
		name := strings.trim_right(rest[:end], ".")
		if name != "" && len(names) < 8 { append(&names, name) }
		rest = rest[end:]
	}
	if len(names) == 0 { return }
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	for id, known in st.names {
		if id == author { continue }
		for n in names {
			if strings.equal_fold(n, known) {
				append(out, id)
				break
			}
		}
	}
}

// ---- read cursors -------------------------------------------------------------------------

// A member has seen everything up to `upto`: true when that moved their cursor.
mark_read :: proc(room: i64, who: u64, upto: i64) -> bool {
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	if st.read == nil { st.read = make(map[i64]map[u64]i64, heap()) }
	r, ok := &st.read[room]
	if !ok {
		st.read[room] = make(map[u64]i64, heap())
		r = &st.read[room]
	}
	if r[who] >= upto { return false }
	if who not_in r && len(r) >= MAX_READERS {
		for k in r {
			delete_key(r, k)
			break
		}
	}
	r[who] = upto
	return true
}

// How many of a room's kept messages came after a member's cursor; -1 when they
// have never read it.
unread :: proc(room: i64, who: u64) -> int {
	guard.lock(&st.mu)
	r := st.read[room]
	last, ok := r[who]
	guard.unlock(&st.mu)
	if !ok { return -1 }
	return chat_store.count_after(room, last)
}

// The members who have read a room: whose unread counts a new message moves.
readers :: proc(room: i64, out: ^[dynamic]u64) {
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	r := st.read[room] // ranging over `st.read[room]` itself traps while the map is nil (dev-2026-10)
	for who in r { append(out, who) }
}

// ---- presence -----------------------------------------------------------------------------

Presence_State :: enum u8 {
	Gone,
	Online,
	Away,
}

Presence :: struct {
	name:      string,
	open:      int, // streams of theirs open on this room
	closed_ns: i64, // when the last one closed
	shown:     Presence_State, // what the room was last told
}

Presence_Change :: struct {
	room:  i64,
	who:   u64,
	name:  string,
	state: Presence_State,
}

// A stream of theirs opened on the room: a change to publish when the room didn't
// already show them online (a reload inside the debounce doesn't flap).
join :: proc(room: i64, who: u64, name: string) -> (c: Presence_Change, show: bool) {
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	r := room_presence(room)
	p, ok := &r[who]
	if !ok {
		r[who] = {name = strings.clone(name, heap())}
		p = &r[who]
	}
	p.open += 1
	if p.shown == .Online { return }
	p.shown = .Online
	return {room, who, clone_temp(p.name), .Online}, true
}

// A stream of theirs closed; the sweep shows them away once the debounce has passed.
leave :: proc(room: i64, who: u64) {
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	if r, has := &st.here[room]; has { // never made here: an empty map goes in the sweep
		if p, ok := &r[who]; ok {
			p.open = max(0, p.open - 1)
			if p.open == 0 { p.closed_ns = sys.mono_ns() }
		}
	}
}

// Every few seconds: who turned away, and who is gone, to publish.
sweep_presence :: proc(out: ^[dynamic]Presence_Change) {
	now_ns := sys.mono_ns()
	empty := make([dynamic]i64, 0, 4, context.temp_allocator)
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	for room, &r in st.here {
		gone := make([dynamic]u64, 0, 4, context.temp_allocator)
		for who, &p in r {
			if p.open > 0 { continue }
			idle := time.Duration(now_ns - p.closed_ns)
			switch {
			case p.shown == .Online && idle >= PRESENCE_DEBOUNCE:
				p.shown = .Away
				append(out, Presence_Change{room, who, clone_temp(p.name), .Away})
			case p.shown == .Away && idle >= AWAY_FOR:
				append(out, Presence_Change{room, who, clone_temp(p.name), .Gone})
				append(&gone, who)
			}
		}
		for who in gone {
			delete(r[who].name, heap())
			delete_key(&r, who)
		}
		if len(r) == 0 { append(&empty, room) }
	}
	// A room nobody is in keeps no map (M2-05).
	for room in empty {
		delete(st.here[room])
		delete_key(&st.here, room)
	}
}

// Who a room shows now, for its page.
present :: proc(room: i64, out: ^[dynamic]Presence_Change) {
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	r := st.here[room] // see readers
	for who, p in r {
		if p.shown != .Gone { append(out, Presence_Change{room, who, clone_temp(p.name), p.shown}) }
	}
}

@(private)
room_presence :: proc(room: i64) -> ^map[u64]Presence {
	if st.here == nil { st.here = make(map[i64]map[u64]Presence, heap()) }
	if room not_in st.here { st.here[room] = make(map[u64]Presence, heap()) }
	return &st.here[room]
}

// ---- helpers ------------------------------------------------------------------------------

now :: proc() -> i64 { return time.time_to_unix(time.now()) }

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

@(private)
clone_temp :: proc(s: string) -> string { return strings.clone(s, context.temp_allocator) }
