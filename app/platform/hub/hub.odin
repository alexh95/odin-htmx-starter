package hub

// ---- platform/hub: server events to every subscriber, on every loop (L3) ----------
//
// D13, PLAN §9.2-9.4. One cross-thread hub with an inbox per event loop:
//
//   publisher, any thread (a handler, a write's continuation after commit, a worker)
//     │ hub.publish(topic, html, rowid, key)
//     ▼
//   hub mutex (a guard.Mutex): the hub sequence, the topic's ring, a snapshot of
//   the inboxes with subscribers; one refcounted Msg, a ref per inbox and the ring
//     ├─► inbox[loop 0]  the first message since its last drain: one next_tick
//     └─► inbox[loop N]  already armed: append only
//   drain, on that loop: encode once per transport, write to its subscribers of
//   the topic, release the ref.
//
// At most one cross-thread wakeup per loop per burst: nbio's queue holds 128 slots
// and spins when full, and posting per message per connection livelocked it (07
// §0.2). A trap under the hub mutex is dirty and exits 70; otherwise delivery
// would stop while /healthz stayed 200 (13 §1.3).
//
// Topics are `<feature>.<family>:<key>`, declared per package in a TOPICS table
// (a Topic row per family) that the profile mounts per host with `hub.mount`,
// beside its ROUTES. A profile that streams calls `hub.init` and `hub.mount`
// in main and mounts `hub.ROUTES` (`/events`); one that doesn't links none of
// this. A loop joins the hub when it gets its first subscriber.

import "base:runtime"
import "core:nbio"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"

import "../authz"
import "../env"
import "../guard"
import "../obs"
import "../stream"
import "../sys"
import "../web"
import "../workers"

MAX_MESSAGE :: 64 * 1024 // §9.4: publish refuses a larger one

// What a ring costs beyond its messages, about: its struct, its topic, its map slot and its
// array's first block. Counted against HUB_RINGS_BYTES, or a million one-byte rings fit it
// (M2-24).
RING_OVERHEAD :: 512
MAX_TOPICS  :: 8         // per subscription
RING_TTL    :: 10 * time.Minute // a topic with no publish for this long lets its ring go

ENV := [?]env.Row {
	{name = "HUB_RING", kind = .Int, def = "256", doc = "messages each topic keeps for a reconnect to replay"},
	{name = "HUB_RING_BYTES", kind = .Size, def = "1MiB", doc = "bytes each topic's ring holds at most"},
	{name = "HUB_RINGS_BYTES", kind = .Size, def = "64MiB", doc = "bytes every topic's ring holds in all; past it the ring published to longest ago goes"},
}

// A persisted topic's keyset replay: what came after the page's rowid, oldest
// first, from the owning feature's store. ok = false: more than it replays (200)
// are missing, and the page gets `resync` instead (D13).
Replay_Item :: struct {
	rowid: i64,
	html:  string,
}
Replay_Proc :: #type proc(key: string, after: i64, out: ^[dynamic]Replay_Item) -> (ok: bool)

// Whether this viewer may subscribe to this key, past the row's perm (a room's
// members, a user's own notifications).
Allow_Proc :: #type proc(key: string, viewer: authz.Viewer) -> bool

// A server-side row runs once per publish on the publisher's thread (M7's bot.ask).
Deliver_Proc :: #type proc(topic, html: string, rowid: i64)

// A page's #live subscribed to this key (`open`), or that stream ended: who is
// in a room (presence, §14.1), on the stream's own loop.
Watch_Proc :: #type proc(key: string, viewer: authz.Viewer, open: bool)

// One row of a package's TOPICS table: a family of topics, as a route row is a
// family of paths. Subscribing runs it as a GET runs a route's handler: the
// perm, then `allow`, then for a persisted topic the keyset replay.
Topic :: struct {
	family:    string, // "chat.room"
	policy:    Policy,
	ring:      int, // 0 = HUB_RING
	persisted: bool, // publishes carry a rowid, and `replay` reads the store
	member:    bool, // keyed by the viewer's id (notify.user:<id>): on every page of theirs, and theirs alone
	lan_only:  bool, // only to a client in LAN_CIDRS, as its page's .Lan_Only route (M2-18)
	perm:      authz.Perm,
	allow:     Allow_Proc,
	replay:    Replay_Proc,
	deliver:   Deliver_Proc,
	watch:     Watch_Proc,
}

Kind :: enum u8 {
	Html, // swapped by the page: an SSE `data:` block, a WS text frame
	Kick, // ends the topic's streams: SSE gets `event: kicked`, a socket closes with `code`
}

Msg :: struct {
	refs:    int, // atomic
	kind:    Kind,
	policy:  Policy,
	code:    u16,
	seq:     u64, // 0 for a kick, which never enters a ring
	user:    u64, // a revoke's kick: every stream of this user, whatever its topics; 0 = by topic
	session: u64, // with `user`: only the streams this session opened; 0 = every one
	rowid:   i64,
	topic:   string,
	key:     string,
	html:    string,
}

@(private)
Inbox :: struct {
	loop:  ^nbio.Event_Loop,
	mu:    sync.Mutex, // only around the swap: publishers append, the drain swaps
	items: [dynamic]^Msg,
	spare: [dynamic]^Msg, // the drain's half of the double buffer
	armed: bool,          // a drain is queued on the loop
	subs:  int,           // atomic: an inbox with none gets no messages
}

@(private)
h: struct {
	mu:         guard.Mutex,
	epoch:      u64,
	seq:        u64,
	inboxes:    [dynamic]^Inbox,
	rings:      Rings,
	floor:      u64, // the newest seq of a ring the idle sweep let go
	since_sweep: int,
	lan:        []env.Cidr, // LAN_CIDRS, for a lan_only topic
	ring_cap:   int,
	ring_bytes: int,
	rings_max:  int, // HUB_RINGS_BYTES
	rings_held: int, // what every ring holds, in bytes
	revoked:    [REVOKES_KEPT]Revoked, // the newest revokes, a ring: what a stream admitted meanwhile missed
	revoked_n:  int,
	hosts:      map[string][]Topic, // per host name, mounted at boot
	families:   map[string]^Topic,  // every mounted row, for publish
	published:  obs.Counter,
	dropped:    obs.Counter,
	resyncs:    obs.Counter,
}

// Per event-loop thread, once it has a subscriber.
@(private, thread_local)
local: struct {
	inbox: ^Inbox,
	subs:  [dynamic]^Sub,
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

// §8.6 step 3, before app.check: the hub's and the streams' env rows. The epoch
// is the boot time in milliseconds, so a cursor from an earlier process, even one
// that restarted inside the same second, is never read as this one's (S0.3).
init :: proc() {
	stream.init()
	env.record("", ENV[:])
	h.epoch = u64(sys.now_unix_ns() / 1e6)
	h.lan = env.cidrs("LAN_CIDRS")
	h.ring_cap = max(1, env.int_("HUB_RING"))
	h.ring_bytes = env.size("HUB_RING_BYTES")
	h.rings_max = max(h.ring_bytes, env.size("HUB_RINGS_BYTES"))
	h.rings.by_topic = make(map[string]^Ring, heap())
	h.hosts = make(map[string][]Topic, heap())
	h.families = make(map[string]^Topic, heap())
	h.inboxes.allocator = heap()
	web.on_live(live_html)
	h.published = obs.register_counter("app_hub_published_total", "", "messages published to the hub")
	h.dropped = obs.register_counter("app_hub_dropped_total", "", "publishes refused: no mounted topic, too large, or draining")
	h.resyncs = obs.register_counter("app_hub_resyncs_total", "", "subscriptions told to refetch instead of replaying")
	obs.limit("hub", "ring", i64(h.ring_cap))
	obs.limit("hub", "ring_bytes", i64(h.ring_bytes), "B")
	obs.limit("hub", "rings_bytes", i64(h.rings_max), "B")
	obs.limit("hub", "message", MAX_MESSAGE, "B")
	obs.set_health("hub", .Ok, "")
}

// A host's TOPICS tables, at boot. A family is mounted once per host; the
// same row may serve several hosts.
mount :: proc(host: string, tables: ..[]Topic) {
	rows := make([dynamic]Topic, heap())
	for t in tables {
		for &row in t {
			for r in rows { assert(r.family != row.family, "hub.mount: a topic family mounted twice on one host") }
			assert(strings.index_byte(row.family, '.') > 0 && strings.index_byte(row.family, ':') < 0, "hub.mount: a family is <feature>.<name>")
			append(&rows, row)
			h.families[row.family] = &row
		}
	}
	h.hosts[host] = rows[:]
}

// The hub sequence now, as a cursor: what a page renders as `after`.
cursor_now :: proc(allocator := context.temp_allocator) -> string {
	guard.lock(&h.mu)
	seq := h.seq
	guard.unlock(&h.mu)
	return cursor(seq, allocator)
}

cursor :: proc(seq: u64, allocator := context.temp_allocator) -> string {
	buf: [48]byte
	e := strconv.write_uint(buf[:24], h.epoch, 10)
	s := strconv.write_uint(buf[24:], seq, 10)
	return strings.concatenate({e, "-", s}, allocator)
}

// ---- publish -----------------------------------------------------------------------

// From any thread: the message to every subscriber of `topic` on every loop,
// and into its ring. A persisted topic passes the store's rowid, after its write
// committed (D13); `.Latest` passes the element id it targets as `key` ("" = the
// topic). Returns the hub sequence, 0 when refused.
publish :: proc(topic, html: string, rowid: i64 = 0, key := "") -> u64 {
	family, _ := split_topic(topic)
	row := h.families[family]
	// Sent as SSE at worst, a message framed past the backlog budget could be neither replayed
	// nor, near the queue cap, delivered: 60,000 line feeds closed every subscriber as too slow,
	// and every reconnect again (M2-23).
	if row == nil || len(html) > MAX_MESSAGE || stream.sse_size("", "", html) > stream.backlog_budget() || web.is_closing() {
		obs.inc(h.dropped)
		return 0
	}
	if row.deliver != nil { row.deliver(topic, html, rowid) }
	m := new_msg(.Html, row.policy, topic, key if key != "" else topic, html)
	m.rowid = rowid
	return post(m, row.ring if row.ring > 0 else h.ring_cap)
}

// Ends every stream subscribed to `topic`: a kick, a revoke (§9.4). SSE gets the
// named event `kicked`, which navigates the page; a socket closes with `code`
// (1008 stops hx-ws for good).
kick :: proc(topic: string, code: u16) {
	m := new_msg(.Kick, .Queue, topic, "", "")
	m.code = code
	post(m, 0)
}

// Ends a member's streams on every host (§17.2.3, X19): a role change, a disable. Each of their
// member topics is kicked with 1008, which hx-ws doesn't retry, and a page whose #live names
// where to go (data-revoke) goes there on `kicked`. A row mounted on two hosts is kicked twice,
// which ends nothing more.
revoke :: proc(user_id: u64) { revoke_session(user_id, 0) }

// Ends the streams one session of a member's opened (a sign-out, a member's revoke of a device:
// M4-09), as `revoke` ends all of them; `session` is authz.Viewer.session, 0 for every session.
revoke_session :: proc(user_id, session: u64) {
	record_revoke(user_id, session)
	// One kick, matched by user rather than topic, so it also ends the streams a handler
	// subscribed itself (the ops panel's parts, M5-16); its topic is what `kicked` carries.
	buf: [24]byte
	id := strconv.write_uint(buf[:], user_id, 10)
	topic := ""
	for _, rows in h.hosts {
		for row in rows {
			if row.member && topic == "" { topic = strings.concatenate({row.family, ":", id}, context.temp_allocator) }
		}
	}
	m := new_msg(.Kick, .Queue, topic, "", "")
	m.code, m.user, m.session = stream.WS_POLICY, user_id, session
	post(m, 0)
}

// A revoke's record, kept for the streams being admitted while it happens: a viewer loaded just
// before the change committed would otherwise subscribe after the kick, with the old grant (M4-09).
// Recorded before the kicks are posted, and read under the same mutex as `join_loop`, so a stream
// either is counted on its loop before the kicks go out, or finds the record.
REVOKES_KEPT :: 64

Revoked :: struct {
	user, session: u64, // session 0: every session of the user
	at:            i64, // mono ns
}

// Before the kicks are posted: what a stream being admitted meanwhile reads.
@(private)
record_revoke :: proc(user_id, session: u64) {
	guard.lock(&h.mu)
	h.revoked[h.revoked_n % REVOKES_KEPT] = {user_id, session, sys.mono_ns()}
	h.revoked_n += 1
	guard.unlock(&h.mu)
}

// Under the hub mutex: whether `v` was revoked since `since` (mono ns, the request's start).
@(private)
revoked_since :: proc(v: authz.Viewer, since: i64) -> bool {
	if v.id == 0 { return false }
	for r in h.revoked[:min(h.revoked_n, REVOKES_KEPT)] {
		if r.user == v.id && r.at >= since && (r.session == 0 || r.session == v.session) { return true }
	}
	return false
}

@(private)
new_msg :: proc(kind: Kind, policy: Policy, topic, key, html: string) -> ^Msg {
	m := new(Msg, heap())
	m.kind, m.policy = kind, policy
	m.topic = strings.clone(topic, heap())
	m.key = m.topic if key == topic else strings.clone(key, heap())
	m.html = strings.clone(html, heap())
	return m
}

@(private)
release :: proc(m: ^Msg) {
	if sync.atomic_sub(&m.refs, 1) == 1 {
		if m.key != m.topic { delete(m.key, heap()) }
		delete(m.topic, heap())
		delete(m.html, heap())
		free(m, heap())
	}
}

@(private)
post :: proc(m: ^Msg, ring_cap: int) -> u64 {
	boxes := make([dynamic]^Inbox, 0, 16, context.temp_allocator)
	wake := make([dynamic]bool, 0, 16, context.temp_allocator)
	out := make([dynamic]^Msg, 0, 4, context.temp_allocator)
	html := m.kind == .Html

	guard.lock(&h.mu)
	for b in h.inboxes {
		if sync.atomic_load(&b.subs) > 0 { append(&boxes, b) }
	}
	m.refs = len(boxes)
	if html {
		h.seq += 1
		m.seq = h.seq
		m.refs += 1
		r := ring_for(&h.rings, m.topic, m.policy, ring_cap, h.ring_bytes, h.floor, heap())
		ring_touch(&h.rings, r, sys.mono_ns())
		before := r.bytes
		ring_add(r, m, &out)
		h.rings_held += r.bytes - before
		// Every topic's ring in all, within its budget: a public publisher could otherwise fill
		// ring after ring until the process ran out of memory (M2-07).
		for h.rings_held + len(h.rings.by_topic) * RING_OVERHEAD > h.rings_max {
			floor, freed, ok := ring_evict_oldest(&h.rings, r, &out, heap())
			if !ok { break }
			h.floor = max(h.floor, floor)
			h.rings_held -= freed
		}
		h.since_sweep += 1
		if h.since_sweep >= 1024 { sweep_rings(&out) }
	}
	seq := m.seq
	unowned := m.refs == 0
	// Into every inbox while the sequence is still ours, so each inbox holds its messages in
	// sequence order: `deliver` skips what is at or below the newest it wrote, and appends made
	// after the mutex let two publishers' messages cross and the lower one drop (M2-02). An
	// inbox's lock nests inside the hub's; the drain takes its own alone.
	for b in boxes {
		sync.lock(&b.mu)
		append(&b.items, m)
		append(&wake, !b.armed)
		b.armed = true
		sync.unlock(&b.mu)
	}
	guard.unlock(&h.mu)

	for old in out { release(old) }
	if html { obs.inc(h.published) }
	if unowned {
		release_unowned(m)
		return seq
	}
	// A loop that has left takes no wakeup (M1-05); its inbox goes with the exiting process.
	for b, i in boxes {
		if wake[i] { _ = workers.post(b.loop, b, drain) }
	}
	return seq
}

// A kick with no inbox to go to.
@(private)
release_unowned :: proc(m: ^Msg) {
	m.refs = 1
	release(m)
}

// Under the hub mutex: rings with no publish for RING_TTL let their messages
// go, and `floor` remembers how far they reached, so a cursor below it on a
// topic with no ring is resynced rather than trusted.
@(private)
sweep_rings :: proc(out: ^[dynamic]^Msg) {
	h.since_sweep = 0
	floor, freed := ring_sweep(&h.rings, sys.mono_ns(), i64(RING_TTL), out, heap())
	h.floor = max(h.floor, floor)
	h.rings_held -= freed
}

// ---- delivery, on each loop ---------------------------------------------------------

Sub :: struct {
	conn:     ^stream.Conn,
	topics:   [MAX_TOPICS]string,
	n_topics: int,
	last:     u64, // the newest seq written: a live copy at or below it is skipped
	slot:     int,
	watch:    [MAX_TOPICS]Watch_Proc, // per topic, told when the stream ends
	viewer:   authz.Viewer,           // whom /events subscribed, for `watch`; its name on the heap
	user:     u64,                    // whom it was admitted for, and for which session: a revoke
	session:  u64,                    // finds it by these (authz.Viewer.id and .session)
}

@(private)
drain :: proc(_: ^nbio.Operation, b: ^Inbox) {
	sync.lock(&b.mu)
	b.items, b.spare = b.spare, b.items
	b.armed = false
	sync.unlock(&b.mu)
	guard.call(proc(data: rawptr) {
		b := (^Inbox)(data)
		for m in b.spare { deliver(m) }
	}, b)
	for m in b.spare { release(m) }
	clear(&b.spare)
	stream.refresh_queued()
	free_all(context.temp_allocator) // the tick's context: odin-http never frees its temp allocator
}

@(private)
wants :: proc(s: ^Sub, topic: string) -> bool {
	for t in s.topics[:s.n_topics] {
		if t == topic { return true }
	}
	return false
}

// Encodes once per transport, then writes to this loop's subscribers. Backwards,
// re-checking the length: a write can end a stream, whose close unsubscribes it
// and moves the last entry into its slot.
@(private)
deliver :: proc(m: ^Msg) {
	sse, ws: string
	for i := len(local.subs) - 1; i >= 0; i -= 1 {
		if i >= len(local.subs) { continue }
		s := local.subs[i]
		if m.user != 0 ? !(s.user == m.user && (m.session == 0 || s.session == m.session)) : !wants(s, m.topic) { continue }
		c := s.conn
		switch m.kind {
		case .Html:
			if m.seq <= s.last { continue }
			s.last = m.seq
			// .Sample drops an update while the last one is still on its way.
			if m.policy == .Sample && stream.queued(c) > 0 { continue }
			switch c.proto {
			case .Sse:
				if sse == "" { sse = stream.sse_event(cursor(m.seq), "", m.html) }
				stream.write(c, sse)
			case .Ws:
				if ws == "" { ws = stream.ws_frame(stream.WS_TEXT, transmute([]byte)m.html) }
				stream.ws_write_frame(c, ws)
			case .Multipart:
				// A part per message, its id the rowid when the publisher gave one (a chat
				// message's), so a reconnect's HX-Last-Part-ID names what it has.
				buf: [24]byte
				id := strconv.write_int(buf[:], m.rowid, 10) if m.rowid > 0 else cursor(m.seq)
				stream.multipart_part(c, m.html, {{"HX-Part-ID", id}})
			}
		case .Kick:
			switch c.proto {
			case .Sse:
				stream.write(c, stream.sse_event("", "kicked", m.topic))
				stream.end(c)
			case .Ws:
				stream.ws_close(c, m.code)
			case .Multipart:
				stream.multipart_part(c, "", {{"HX-Trigger", "kicked"}})
				stream.multipart_end(c)
			}
		}
	}
}

// ---- subscribers ----------------------------------------------------------------------

// Subscribes a stream on its own loop, from its handler, to live messages only:
// a socket's room, say, which sends its own snapshot (§14.1). Call `unsubscribe`
// from the stream's on_close. The topics are copied. A member's stream names its viewer,
// so revoking them ends it too.
subscribe :: proc(c: ^stream.Conn, topics: []string, viewer := authz.Viewer{}) -> ^Sub {
	s := new_sub(c, topics)
	s.user, s.session = viewer.id, viewer.session
	guard.lock(&h.mu)
	join_loop()
	s.last = h.seq
	guard.unlock(&h.mu)
	add_sub(s)
	return s
}

unsubscribe :: proc(s: ^Sub) {
	if s == nil { return }
	last := pop(&local.subs)
	if last != s {
		local.subs[s.slot] = last
		last.slot = s.slot
	}
	sync.atomic_sub(&local.inbox.subs, 1)
	for t, i in s.topics[:s.n_topics] {
		if s.watch[i] != nil {
			_, key := split_topic(t)
			s.watch[i](key, s.viewer, false)
		}
		delete(t, heap())
	}
	delete(s.viewer.name, heap())
	free(s, heap())
}

@(private)
new_sub :: proc(c: ^stream.Conn, topics: []string) -> ^Sub {
	s := new(Sub, heap())
	s.conn = c
	for t in topics[:min(len(topics), MAX_TOPICS)] {
		s.topics[s.n_topics] = strings.clone(t, heap())
		s.n_topics += 1
	}
	return s
}

// Under the hub mutex: this loop's inbox, made on its first subscriber, and
// one more subscriber counted, so a publish from here on reaches it.
@(private)
join_loop :: proc() {
	if local.inbox == nil {
		b := new(Inbox, heap())
		b.loop = nbio.current_thread_event_loop()
		b.items.allocator, b.spare.allocator = heap(), heap()
		local.inbox = b
		local.subs = make([dynamic]^Sub, heap())
		append(&h.inboxes, b)
	}
	sync.atomic_add(&local.inbox.subs, 1)
}

// ---- numbers ---------------------------------------------------------------------------

Numbers :: struct {
	cursor:          string, // the hub sequence now
	loops:           int,    // loops that have had a subscriber
	loops_with_subs: int,    // loops with one now: fan-out spans more than one on Linux (03 §10.4)
	published:       u64,    // since boot, as /metrics counts them
	dropped:         u64,
	resyncs:         u64,
}

numbers :: proc(allocator := context.temp_allocator) -> (n: Numbers) {
	guard.lock(&h.mu)
	seq := h.seq
	n.loops = len(h.inboxes)
	for b in h.inboxes {
		if sync.atomic_load(&b.subs) > 0 { n.loops_with_subs += 1 }
	}
	guard.unlock(&h.mu)
	n.cursor = cursor(seq, allocator)
	n.published, n.dropped, n.resyncs = obs.counter_value(h.published), obs.counter_value(h.dropped), obs.counter_value(h.resyncs)
	return
}

@(private)
add_sub :: proc(s: ^Sub) {
	s.slot = len(local.subs)
	append(&local.subs, s)
}
