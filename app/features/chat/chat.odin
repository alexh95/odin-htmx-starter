package chat

// ---- chat: the domain (PLAN §14.1, D30) ---------------------------------------------------
//
// Rooms and their messages through the store, and what lives only in this process
// whatever the store: who is in a room (presence), how far each member has read, and
// the names mentions are matched against. Plain values and errors, never HTTP.

import "base:runtime"
import "core:crypto"
import "core:crypto/hash"
import "core:encoding/base64"
import "core:encoding/hex"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"

import "../../platform/authz"
import "../../platform/env"
import "../../platform/guard"
import "../../platform/store"
import "../../platform/sys"
import m "models"
import uploads "../uploads"
import audit_store "store:audit"
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

// An invite to a private room is a row in the store, and its link `/chat/join/<id>.<secret>`
// (the secret's hash is all the store keeps): it outlives a restart, and lasts this long, or
// until its owner revokes it or its one use is spent.
INVITE_FOR :: 7 * 24 * time.Hour
INVITE_SECRET :: 24 // bytes
INVITE_SECRET_TEXT :: 32 // its base64url characters

Transport :: enum u8 {
	Ws,
	Sse,
	Poll,
	Multipart,
}

// The setting that's no one transport: a WebSocket, Streaming once two connects fail (static/chat.js).
AUTO :: "auto"

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
	{name = "CHAT_TRANSPORT", kind = .Enum, def = "auto", choices = "auto|ws|sse|poll|multipart", doc = "a room's connection when the viewer chose none (§14.1)"},
	{name = "CHAT_RING_BYTES", kind = .Size, def = "16MiB", doc = "bytes every room's last 100 messages hold in all; the oldest rooms' tails go first"},
	// Retention (§14.1, Q19): whichever hits first; pinned messages exempt.
	{name = "CHAT_ROOM_CAP", kind = .Int, def = "500", doc = "messages a public or private room keeps, the newest"},
	{name = "CHAT_ROOM_MAX_AGE", kind = .Duration, def = "7d", doc = "and none older than this"},
	{name = "CHAT_DM_CAP", kind = .Int, def = "1000", doc = "messages a DM keeps"},
	{name = "CHAT_DM_MAX_AGE", kind = .Duration, def = "30d", doc = "and none older than this"},
	{name = "CHAT_ANNOUNCE_CAP", kind = .Int, def = "100", doc = "messages announcements keep"},
	{name = "CHAT_REPORTS_PER_MINUTE", kind = .Int, def = "5", doc = "reports a member may file in a minute"},
	{name = "CHAT_WRITES_PER_MINUTE", kind = .Int, def = "30", doc = "rooms, DMs, invites, joins, leaves, blocks and settings a member may change in a minute"},
	{name = "CHAT_ROOMS_PER_MEMBER", kind = .Int, def = "20", doc = "rooms a member may own, DMs aside; moderators aren't held to it"},
	{name = "CHAT_SEARCHES_PER_SECOND", kind = .Int, def = "10", doc = "searches a member may run in a second (§17.5)"},
	{name = "CHAT_ANNOUNCE_MAX_AGE", kind = .Duration, def = "365d", doc = "and none older than this"},
}

@(private)
st: struct {
	mu:        guard.Mutex,
	setting:   string,
	names:     map[u64]string,            // member → the name they last used here, for mentions
	read:      map[i64]map[u64]i64,       // room → member → the newest id they have seen
	here:      map[i64]map[u64]Presence,  // room → member → their presence
	keep:      m.Retention,
	posted:    map[i64]map[u64]i64, // room → member → when they last posted there: slow mode's clock
}

// At boot: the env rows, the store's ring budget, the lobby.
init :: proc() {
	env.record("CHAT_", ENV[:])
	st.setting = env.str("CHAT_TRANSPORT")
	secs :: proc(name: string) -> i64 { return i64(env.duration(name) / time.Second) }
	for kind in m.Room_Kind {
		switch kind {
		case .Public, .Private:
			st.keep.cap[kind], st.keep.age[kind] = env.int_("CHAT_ROOM_CAP"), secs("CHAT_ROOM_MAX_AGE")
		case .Dm:
			st.keep.cap[kind], st.keep.age[kind] = env.int_("CHAT_DM_CAP"), secs("CHAT_DM_MAX_AGE")
		case .Announce:
			st.keep.cap[kind], st.keep.age[kind] = env.int_("CHAT_ANNOUNCE_CAP"), secs("CHAT_ANNOUNCE_MAX_AGE")
		}
	}
	chat_store.init(env.size("CHAT_RING_BYTES"), st.keep)
	chat_store.set_audit_writer(audit_store.append_in)
	uploads.holds(chat_store.blob_held)
}

// What a room of `kind` keeps: its newest `cap` messages, none older than `days`.
keeps :: proc(kind: m.Room_Kind) -> (cap: int, days: i64) { return st.keep.cap[kind], st.keep.age[kind] / 86_400 }

// The 60 s job: every room's messages past its kind's age.
sweep :: proc() -> (removed: int, err: m.Error) { return chat_store.sweep(now()) }

// The lobby, into an empty store: after the store's open and migrations, which a SQLite profile
// runs after init.
seed :: proc() { chat_store.seed() }

default_setting :: proc() -> string { return st.setting }

// A setting: a transport's name, or AUTO.
known_setting :: proc(name: string) -> bool {
	_, ok := transport_named(name)
	return ok || name == AUTO
}

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

// The rooms `v` may read: public ones, announcements, and the private rooms and DMs they are in.
rooms_for :: proc(v: authz.Viewer, out: ^[dynamic]m.Room) -> m.Error { return chat_store.rooms_for(v.id, out) }

// A room by slug, when `v` may read it. A private room or a DM someone isn't in is .Not_Found to
// them, as a room that doesn't exist: its slug says nothing.
room_for :: proc(slug: string, v: authz.Viewer) -> (m.Room, m.Error) {
	r, err := chat_store.room(slug)
	if err != .None { return {}, err }
	if !may_read(r, v) { return {}, .Not_Found }
	return r, .None
}

// ---- who reads, who posts (D30, D35) -----------------------------------------------------------

may_read :: proc(r: m.Room, v: authz.Viewer) -> bool { return reads(r, v.id) }

// Whether member `who` may read `r`: whose mentions and unread counts a message moves. A member a
// moderator kicked doesn't, until the kick ends.
reads :: proc(r: m.Room, who: u64) -> bool {
	switch r.kind {
	case .Public, .Announce:
		return who == 0 || chat_store.banned(r.id, who, .Kick, now()) == 0
	case .Private, .Dm:
		return who != 0 && chat_store.is_member(r.id, who)
	}
	return false
}

// Announcements are their owner's and the moderators' to post; a private room and a DM their
// members'. A locked room is the moderators' alone, and a muted member posts nothing until the
// mute ends. The route's perm (Chat_Post) comes first.
may_post :: proc(r: m.Room, v: authz.Viewer) -> bool { return why_not_post(r, v) == "" }

// Why `v` may not post in `r`, for the room page and a refused post; "" when they may.
why_not_post :: proc(r: m.Room, v: authz.Viewer) -> string {
	mod := authz.can(v, .Chat_Moderate)
	switch r.kind {
	case .Public:
	case .Announce:
		if v.id == 0 || (v.id != r.owner && !mod) { return "Only its owner and the moderators post here." }
	case .Private, .Dm:
		if !reads(r, v.id) { return "Only its members post here." }
		if r.kind == .Dm && walled(v.id, dm_peer(r, v.id)) { return CANT_MESSAGE }
	}
	if r.locked && !mod { return "A moderator locked this room: only moderators post for now." }
	if until := chat_store.banned(r.id, v.id, .Mute, now()); until != 0 {
		return fmt.tprintf("A moderator muted you here until %s.", clock(until))
	}
	return ""
}

// Slow mode (§14.1): the seconds `who` waits before posting in `r` again; 0 when they needn't.
// Moderators never wait. A post that goes ahead starts the clock (`slow_mark`).
slow_wait :: proc(r: m.Room, v: authz.Viewer) -> int {
	if r.slow <= 0 || authz.can(v, .Chat_Moderate) { return 0 }
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	last := (st.posted[r.id] or_else nil)[v.id]
	return max(0, int(last + i64(r.slow) - now()))
}

slow_mark :: proc(r: m.Room, who: u64) {
	if r.slow <= 0 { return }
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	if st.posted == nil { st.posted = make(map[i64]map[u64]i64, heap()) }
	p, ok := &st.posted[r.id]
	if !ok {
		st.posted[r.id] = make(map[u64]i64, heap())
		p = &st.posted[r.id]
	}
	if who not_in p && len(p) >= MAX_READERS {
		for k in p {
			delete_key(p, k)
			break
		}
	}
	p[who] = now()
}

// HH:MM UTC, for a ban's end.
@(private)
clock :: proc(at: i64) -> string {
	h, mi, _ := time.clock(time.unix(at, 0))
	return fmt.tprintf("%02d:%02d UTC", h, mi)
}

// ---- moderation (§14.1, planning 2026-11-01) ---------------------------------------------------
//
// A moderator acts directly in public rooms and announcements; a private room or a DM, which they
// don't read, only through a report on one of its messages. Each act is audited, with the
// moderator's reason, in its own transaction; a message's body never goes in the audit log.

// Bounds on what a moderator sets.
MAX_SLOW :: 3600     // seconds between posts
MAX_BAN :: 7 * 1440  // minutes a mute or a kick lasts

may_moderate :: proc(r: m.Room, v: authz.Viewer) -> bool {
	return authz.can(v, .Chat_Moderate) && (r.kind == .Public || r.kind == .Announce)
}

// Who did it, for the audit entry.
Actor :: struct {
	id:     u64,
	name:   string,
	client: string,
}

@(private)
audit :: proc(a: Actor, action, target_kind: string, target_id: i64, reason, meta: string) -> m.Audit {
	return {i64(a.id), a.name, a.client, action, target_kind, target_id, reason, meta}
}

set_lock :: proc(r: m.Room, a: Actor, locked: bool, reason: string) -> m.Error {
	return chat_store.set_room(r.id, locked, r.slow, audit(a, "chat.lock" if locked else "chat.unlock", "room", r.id, reason, ""))
}

set_slow :: proc(r: m.Room, a: Actor, seconds: int, reason: string) -> m.Error {
	s := clamp(seconds, 0, MAX_SLOW)
	return chat_store.set_room(r.id, r.locked, s, audit(a, "chat.slow", "room", r.id, reason, fmt.tprintf("seconds=%d", s)))
}

// Mutes or kicks `who` in `r` for `minutes`; 0 lifts it.
set_ban :: proc(r: m.Room, a: Actor, who: u64, kind: m.Ban_Kind, minutes: int, reason: string) -> m.Error {
	mins := clamp(minutes, 0, MAX_BAN)
	name := "chat.mute" if kind == .Mute else "chat.kick"
	if mins == 0 { name = "chat.unmute" if kind == .Mute else "chat.unkick" }
	b := m.Ban{room = r.id, who = who, kind = kind, until = now() + i64(mins) * 60, by = a.id}
	return chat_store.ban(b, audit(a, name, "user", i64(who), reason, fmt.tprintf("room=%d minutes=%d", r.id, mins)))
}

// ---- an owner's Remove --------------------------------------------------------------------------

// Moderators don't act in private rooms, so this is how someone added by mistake leaves one.
may_remove :: proc(r: m.Room, v: authz.Viewer) -> bool { return r.kind == .Private && v.id != 0 && r.owner == v.id }

// As long as there's a room: only its owner lifts it.
REMOVED_UNTIL :: i64(1) << 62

// Out of the room, and kept out by the row, whatever invite they hold. The caller ends their streams.
remove_member :: proc(r: m.Room, a: Actor, who: u64, name: string) -> m.Error {
	b := m.Ban{room = r.id, who = who, kind = .Removed, until = REMOVED_UNTIL, by = a.id, name = name}
	if err := chat_store.ban(b, audit(a, "chat.member_removed", "user", i64(who), "", fmt.tprintf("room=%d", r.id))); err != .None { return err }
	return chat_store.leave(r.id, who)
}

// They may come back by an invite; it doesn't put them back.
allow_member :: proc(r: m.Room, a: Actor, who: u64) -> m.Error {
	b := m.Ban{room = r.id, who = who, kind = .Removed, until = 0, by = a.id}
	return chat_store.ban(b, audit(a, "chat.member_allowed", "user", i64(who), "", fmt.tprintf("room=%d", r.id)))
}

removed_members :: proc(r: m.Room, out: ^[dynamic]m.Ban) -> m.Error { return chat_store.removed(r.id, now(), out) }
kept_out :: proc(r: m.Room, who: u64) -> bool { return who != 0 && chat_store.banned(r.id, who, .Removed, now()) != 0 }

// A moderator's delete of `msg` to a tombstone, audited; op.done runs once it is stored. The op
// can outlive its connection, so what its audit entry names is in the op's own memory.
remove :: proc(op: ^m.Change, a: Actor, reason, action: string) -> bool {
	op.delete, op.moderated = true, true
	mem := store.op_allocator(op)
	op.audit = audit({a.id, strings.clone(a.name, mem), strings.clone(a.client, mem)}, action, "message", op.id, strings.clone(reason, mem), "")
	return chat_store.change(op)
}

// A member's report of `msg` in `r` (any kind of room), with a copy of it for the moderators; again
// answers as the first did. .Constraint: past what may be open, theirs or anyone's. A moderator's
// page lists the oldest REPORTS_SHOWN, so the rest wait behind them.
report :: proc(msg: m.Message, v: authz.Viewer, reason: string) -> (i64, m.Error) {
	theirs, all := chat_store.open_reports(v.id)
	if theirs >= MAX_OPEN_REPORTS_EACH || all >= MAX_OPEN_REPORTS { return 0, .Constraint }
	return chat_store.report({
		room = msg.room, msg = msg.id, author = msg.author, author_name = msg.name, body = msg.body, blob = msg.blob,
		by = v.id, by_name = v.name, reason = reason, at = now(),
	})
}

// A report closed by the removal `removal` audited: its actor and reason, its own action.
close_report :: proc(id: i64, removal: m.Audit) -> m.Error {
	entry := removal
	entry.action, entry.target_kind, entry.target_id = "chat.report_removed", "report", id
	return chat_store.resolve(id, now(), "removed", entry)
}

reports :: proc(out: ^[dynamic]m.Report) -> m.Error { return chat_store.reports(REPORTS_SHOWN, out) }
open_reports :: proc() -> int {
	_, all := chat_store.open_reports(0)
	return all
}
report_of :: proc(id: i64) -> (m.Report, m.Error) { return chat_store.report_of(id) }

// A report closed as `outcome` ("removed" or "dismissed"), audited.
resolve :: proc(rep: m.Report, a: Actor, outcome, reason: string) -> m.Error {
	return chat_store.resolve(rep.id, now(), outcome, audit(a, fmt.tprintf("chat.report_%s", outcome), "report", rep.id, reason, fmt.tprintf("message=%d", rep.msg)))
}

// A private room's owner, or a moderator among its members (no one else reads it to get there),
// hands out its invite links, lists the open ones and revokes them.
may_invite :: proc(r: m.Room, v: authz.Viewer) -> bool {
	return r.kind == .Private && v.id != 0 && (v.id == r.owner || authz.can(v, .Chat_Moderate))
}

// Only a private room is left, and not by its owner, who would leave it to no one: a DM is its
// two members', and the rest have no members.
may_leave :: proc(r: m.Room, v: authz.Viewer) -> bool { return r.kind == .Private && v.id != r.owner && reads(r, v.id) }

members :: proc(r: m.Room, out: ^[dynamic]m.Member) -> m.Error { return chat_store.members(r.id, out) }
leave_room :: proc(r: m.Room, v: authz.Viewer) -> m.Error { return chat_store.leave(r.id, v.id) }

// The DM of `v` and `other`, made when they have none. `other` must be someone chat knows (their
// name from a page or a post here): .Not_Found otherwise, and for `v` themself.
dm :: proc(v: authz.Viewer, other: u64) -> (m.Room, m.Error) {
	if other == 0 || other == v.id { return {}, .Not_Found }
	guard.lock(&st.mu)
	known, ok := st.names[other]
	name := strings.clone(known, context.temp_allocator) if ok else ""
	guard.unlock(&st.mu)
	if !ok { return {}, .Not_Found }
	raw: [8]byte
	crypto.rand_bytes(raw[:])
	slug := fmt.tprintf("dm-%s", hex.encode(raw[:], context.temp_allocator))
	return chat_store.dm(v.id, v.name, other, name, slug)
}

// ---- invites to a private room -----------------------------------------------------------------

// A new invite to `r` from `v`: its token, `<id>.<secret>`, which is shown once and never kept.
// `once`: a single use.
new_invite :: proc(r: m.Room, v: authz.Viewer, once: bool) -> (inv: m.Invite, token: string, err: m.Error) {
	raw: [INVITE_SECRET]byte
	crypto.rand_bytes(raw[:])
	secret := base64.encode(raw[:], base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding})
	at := now()
	inv = {
		room = r.id, hash = secret_hash(secret), by = v.id, by_name = v.name, at = at,
		expires = at + i64(INVITE_FOR / time.Second), max_uses = 1 if once else 0,
	}
	inv.id = chat_store.add_invite(inv) or_return
	return inv, fmt.tprintf("%d.%s", inv.id, secret), .None
}

// A room's open invites, newest first.
invites :: proc(r: m.Room, out: ^[dynamic]m.Invite) -> m.Error { return chat_store.invites(r.id, now(), out) }

revoke_invite :: proc(r: m.Room, id: i64) -> m.Error { return chat_store.revoke_invite(id, r.id, now()) }

// The private room an open invite's token names. A forged token, a revoked, expired or spent
// invite all answer .Not_Found alike; the secret is compared by its hash, in constant time.
invited_to :: proc(token: string) -> (m.Room, m.Invite, m.Error) {
	id_text, _, secret := strings.partition(token, ".")
	id, ok := strconv.parse_u64(id_text, 10)
	if !ok || id == 0 || id > u64(max(i64)) || len(secret) != INVITE_SECRET_TEXT { return {}, {}, .Not_Found }
	inv, err := chat_store.invite(i64(id))
	if err != .None { return {}, {}, err }
	want, sent := inv.hash, secret_hash(secret)
	if len(want) != len(sent) || crypto.compare_constant_time(transmute([]byte)want, transmute([]byte)sent) != 1 { return {}, {}, .Not_Found }
	t := now()
	if inv.revoked != 0 || inv.expires <= t || (inv.max_uses > 0 && inv.uses >= inv.max_uses) { return {}, {}, .Not_Found }
	r, rerr := room_by_id(inv.room)
	if rerr != .None || r.kind != .Private { return {}, {}, .Not_Found }
	return r, inv, .None
}

// `v` joins by invite `inv`, which the store checks is still open as it counts the use.
accept_invite :: proc(inv: m.Invite, v: authz.Viewer) -> m.Error { return chat_store.use_invite(inv.id, now(), v.id, v.name) }

@(private)
secret_hash :: proc(secret: string) -> string {
	sum: [32]byte
	hash.hash_string_to_buffer(.SHA256, secret, sum[:])
	return string(hex.encode(sum[:], context.temp_allocator))
}

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

// A room of `kind` made by `v`: they own it, and a private room starts with them in it.
create_room :: proc(slug, name: string, kind: m.Room_Kind, v: authz.Viewer) -> (m.Room, m.Error) {
	return chat_store.create_room(slug, name, kind, v.id, v.name)
}

// Who may make a room of `kind`: announcements are the moderators'.
may_create :: proc(kind: m.Room_Kind, v: authz.Viewer) -> bool {
	switch kind {
	case .Public, .Private:
		return authz.can(v, .Chat_Create_Room)
	case .Announce:
		return authz.can(v, .Chat_Moderate)
	case .Dm:
		return false // made by `dm`, never by name
	}
	return false
}

// A message's room, for its menu's link.
room_by_id :: proc(id: i64) -> (m.Room, m.Error) { return chat_store.room_of(id) }

// ---- search ------------------------------------------------------------------------------

SEARCH_HITS :: 50
MAX_SEARCH_WORDS :: 8

// What `q` finds in the rooms `v` may read, newest first; its strings in the temp allocator, and it may
// run off the loop. Global search is `find`'s.
search :: proc(v: authz.Viewer, q: string, out: ^[dynamic]m.Hit) -> m.Error {
	words := make([dynamic]string, 0, MAX_SEARCH_WORDS, context.temp_allocator)
	rest, _ := strings.remove_all(q, "\x00", context.temp_allocator) // FTS5 reads its query as a C string
	for w in strings.fields_iterator(&rest) {
		if len(words) == MAX_SEARCH_WORDS { break }
		append(&words, w)
	}
	return chat_store.search(v.id, words[:], now(), SEARCH_HITS, out)
}

optimize :: proc() -> m.Error { return chat_store.optimize() }

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

// A post's body and its image: the image may stand alone. Any member's blob may be attached, not
// only one they uploaded: the same image twice is one blob, with its first uploader's name on it.
check_post :: proc(body, blob: string) -> (trimmed, problem: string) {
	if blob == "" { return check_body(body) }
	if !uploads.valid_sha(blob) { return "", "That image isn't there any more." }
	if _, err := uploads.blob(blob); err != .None { return "", "That image isn't there any more." }
	if strings.trim_space(body) == "" { return "", "" }
	return check_body(body)
}

// ---- images ------------------------------------------------------------------------------------

// A member's delete let go of an image: it goes now, if nothing else holds it.
released :: proc(sha: string) {
	if sha != "" { uploads.release(sha) }
}

// A moderator's removal (§17.6) takes the image everywhere: out of every message holding it, in any
// room, private ones and DMs too (they act on what a report showed them, which opens no room to
// reading), and off the disk. A re-upload is a new post, for moderators to handle.
purge_image :: proc(sha: string, a: Actor, reason: string, out: ^[dynamic]m.Message) -> m.Error {
	entry := audit(a, "chat.image_removed", "blob", 0, reason, fmt.tprintf("sha256=%s", sha))
	if err := chat_store.purge_blob(sha, entry, out); err != .None { return err }
	return uploads.erase(sha)
}

// ---- blocks ------------------------------------------------------------------------------------

CANT_MESSAGE :: "You can't message this member."
MAX_OPEN_REPORTS :: 1000
MAX_OPEN_REPORTS_EACH :: 20
REPORTS_SHOWN :: 100
MAX_SEARCH_QUERY :: 200 // bytes

blocking :: proc(who, other: u64) -> bool { return chat_store.blocking(who, other) }

// Either has blocked the other: a DM is closed both ways.
walled :: proc(a, b: u64) -> bool {
	return a != 0 && b != 0 && (chat_store.blocking(a, b) || chat_store.blocking(b, a))
}

block :: proc(who, other: u64, name: string) -> m.Error {
	if other == 0 || who == other { return .Constraint }
	return chat_store.block(who, other, name, now())
}

unblock :: proc(who, other: u64) -> m.Error { return chat_store.unblock(who, other) }
blocks :: proc(who: u64, out: ^[dynamic]m.Block) -> m.Error { return chat_store.blocks(who, out) }

// The other member of a DM, or 0.
dm_peer :: proc(r: m.Room, me: u64) -> u64 {
	pair := make([dynamic]m.Member, 0, 2, context.temp_allocator)
	_ = chat_store.members(r.id, &pair)
	for mem in pair {
		if mem.who != me { return mem.who }
	}
	return 0
}

// Stores op's message; op.done runs once it is. false: the store is busy.
post :: proc(op: ^m.Post) -> bool {
	if op.author != 0 { seen(op.author, op.name) } // the bot isn't a member to mention
	return chat_store.post(op)
}

// An edit or a delete of the member's own message, inside EDIT_WINDOW.
change :: proc(op: ^m.Change) -> bool {
	op.window = i64(EDIT_WINDOW / time.Second)
	return chat_store.change(op)
}

// Past what they may own? Moderators make rooms for everyone, and aren't held to it.
too_many_rooms :: proc(v: authz.Viewer) -> bool {
	return !authz.can(v, .Chat_Moderate) && chat_store.rooms_owned(v.id) >= env.int_("CHAT_ROOMS_PER_MEMBER")
}

// Whether `who` may still edit or delete `msg`: the menu's question, which the
// store answers again when they do.
may_change :: proc(msg: m.Message, who: u64) -> bool {
	return !msg.gone && who != 0 && msg.author == who && now() - msg.at <= i64(EDIT_WINDOW / time.Second)
}

// ---- the bot ------------------------------------------------------------------------------------

// Whose name the bot's answers go under (author 0: no member's).
BOT_NAME :: "Capcom"

// Whether `body` asks the bot, and the question: `@bot`, as its own word and without case,
// taken out.
asks_bot :: proc(body: string) -> (question: string, asked: bool) {
	word :: proc(r: rune) -> bool { return unicode.is_letter(r) || unicode.is_digit(r) || r == '_' || r == '-' || r == '.' }
	for at := 0; at + 4 <= len(body); at += 1 {
		if !strings.equal_fold(body[at:at + 4], "@bot") { continue }
		before, _ := utf8.decode_last_rune_in_string(body[:at])
		after, _ := utf8.decode_rune_in_string(body[at + 4:])
		if at > 0 && word(before) || at + 4 < len(body) && word(after) && after != '.' { continue }
		return strings.trim_space(strings.concatenate({body[:at], body[at + 4:]}, context.temp_allocator)), true
	}
	return "", false
}

// A message's worth of `text`: its first MAX_BODY runes.
cut_body :: proc(text: string) -> string {
	trimmed := strings.trim_space(text)
	n := 0
	for _, i in trimmed {
		if n == MAX_BODY - 1 { return strings.concatenate({trimmed[:i], "…"}, context.temp_allocator) }
		n += 1
	}
	return trimmed
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
