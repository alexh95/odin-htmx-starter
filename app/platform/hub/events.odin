package hub

// ---- /events: the page's one SSE stream (§9.1, §9.3) -----------------------------------
//
//   <div id="live" hx-sse:connect="/events?t=chat.room:12@88200,notify.user:42@5512&amp;after=<epoch>-<seq>">
//
// `t` names the topics, each persisted one with the newest rowid the page
// rendered; `after` is the hub sequence at render time. On connect, once every
// topic's perm and `allow` pass (one failure answers 403), each topic resumes
// by D13's procedure:
//
//   1. a Last-Event-ID from this process inside the topic's ring: replay from the ring;
//   2. otherwise `after`, the same way: this closes the gap between render and connect
//      on every boosted navigation that re-creates #live;
//   3. otherwise (a cursor from an earlier process, or older than the ring) a persisted
//      topic with a rowid replays from its store, and the rest get `event: resync`,
//      which the page answers by refetching the fragment (hx-trigger="resync from:body").
//
// Duplicates from an overlap are harmless: live elements have stable ids and
// swap by upsert or by id. A host subscribes only to the families its own
// TOPICS mount (§7.3).

import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"

import "../authz"
import "../env"
import "../escape"
import "../guard"
import "../obs"
import "../stream"
import "../web"

// Mounted by a profile that streams, as the platform's: {"platform", hub.ROUTES[:]}.
ROUTES := [?]web.Route {
	{.Get, "/events", events, .Public, {.Stream, .Fragment}, 0},
}

@(private)
Resume :: enum u8 {
	Live,   // no cursor: from now on
	Ring,   // replayed from the topic's ring
	Keyset, // replayed from the owning feature's store
	Resync, // `event: resync`: the page refetches
}

events :: proc(req: ^web.Request, res: ^web.Response) {
	ctx := web.ctx()
	table := h.hosts[ctx.site.name]

	want: [MAX_TOPICS]Wanted
	rows: [MAX_TOPICS]^Topic
	n := 0
	t := web.query_get(req, "t")
	for entry in strings.split_iterator(&t, ",") {
		if entry == "" { continue }
		w, ok := parse_wanted(entry)
		row := find_row(table, w.topic)
		if !ok || row == nil || n == MAX_TOPICS || (w.has_rowid && !row.persisted) {
			web.respond_status(res, .Bad_Request)
			return
		}
		want[n], rows[n] = w, row
		n += 1
	}
	if n == 0 {
		web.respond_status(res, .Bad_Request)
		return
	}
	for i in 0 ..< n {
		_, key := split_topic(want[i].topic)
		if !authz.can(ctx.viewer, rows[i].perm) || (rows[i].allow != nil && !rows[i].allow(key, ctx.viewer)) ||
		   rows[i].member && (ctx.viewer.id == 0 || key != member_key(ctx.viewer)) ||
		   rows[i].lan_only && !env.contains(h.lan, ctx.client) {
			web.respond_status(res, .Forbidden)
			return
		}
	}
	given, _ := web.header(req, "last-event-id")
	if given == "" { given = web.query_get(req, "after") }
	from, ours := parse_cursor(given, h.epoch)

	c := stream.sse_begin(res, nil, proc(c: ^stream.Conn) { unsubscribe((^Sub)(c.user)) })
	if c == nil { return } // admission answered 503 or 429
	topics: [MAX_TOPICS]string
	for i in 0 ..< n { topics[i] = want[i].topic }
	s := new_sub(c, topics[:n])
	c.user = s

	// Decide each topic under the mutex, and take refs on what its ring replays;
	// write after releasing it (03's prototype wrote under the lock).
	how: [MAX_TOPICS]Resume
	replay := make([dynamic]^Msg, 0, 16, context.temp_allocator)
	guard.lock(&h.mu)
	join_loop()
	revoked := revoked_since(ctx.viewer, ctx.start)
	snapshot := h.seq
	for i in 0 ..< n {
		r := h.rings.by_topic[want[i].topic]
		switch {
		case given == "":
			how[i] = .Live
		case ours && from <= snapshot && (r != nil && ring_covers(r, from) || r == nil && from >= h.floor):
			how[i] = .Ring
			if r != nil { ring_after(r, from, &replay) }
		case rows[i].persisted && want[i].has_rowid && rows[i].replay != nil:
			how[i] = .Keyset
		case:
			how[i] = .Resync
		}
	}
	// The ring still holds each of these, so its count can't reach zero meanwhile.
	for m in replay { sync.atomic_add(&m.refs, 1) }
	guard.unlock(&h.mu)

	// A backlog within the stream's budget: a replay past the queue cap closed the stream as
	// too slow, and every reconnect asked for the same replay again (M2-03). Past it the
	// ring's replay is dropped and those topics resync, which refetches the fragment. Counted
	// as the stream is sent it, SSE frames, not HTML (M2-23).
	budget := stream.backlog_budget()
	backlog := 0
	for m in replay { backlog += stream.sse_size(cursor(m.seq), "", m.html) }
	if backlog > budget {
		for m in replay { release(m) }
		clear(&replay)
		for i in 0 ..< n {
			if how[i] == .Ring { how[i] = .Resync }
		}
		backlog = 0
	}

	// Anything at or below the snapshot still in this loop's inbox is skipped by
	// `last`; anything above it arrives after this handler returns.
	s.last = snapshot
	s.session = ctx.viewer.session
	add_sub(s)
	// Revoked while this request was on its way: kicked as the revoke kicked its other streams.
	if revoked {
		for m in replay { release(m) }
		stream.write(c, stream.sse_event("", "kicked", want[0].topic))
		stream.end(c)
		return
	}
	// Before the writes below: one can end the stream, whose close frees `s` (and tells the
	// watchers it closed). Outside the hub mutex, since a watcher may publish (someone came online).
	for i in 0 ..< n {
		if rows[i].watch == nil { continue }
		if s.viewer.id != ctx.viewer.id {
			s.viewer = {id = ctx.viewer.id, role = ctx.viewer.role, name = strings.clone(ctx.viewer.name, heap())}
		}
		s.watch[i] = rows[i].watch
		_, key := split_topic(want[i].topic)
		rows[i].watch(key, s.viewer, true)
	}
	slice.sort_by(replay[:], proc(a, b: ^Msg) -> bool { return a.seq < b.seq })
	for m in replay {
		stream.write(c, stream.sse_event(cursor(m.seq), "", m.html))
		release(m)
	}
	now := cursor(snapshot)
	for i in 0 ..< n {
		switch how[i] {
		case .Live, .Ring:
		case .Keyset:
			items := make([dynamic]Replay_Item, 0, 32, context.temp_allocator)
			_, key := split_topic(want[i].topic)
			ok := rows[i].replay(key, want[i].rowid, &items)
			size := 0
			for it, j in items { size += stream.sse_size(now if j == len(items) - 1 else "", "", it.html) }
			if !ok || backlog + size > budget { // within the budget, as the ring's above
				how[i] = .Resync
			} else {
				backlog += size
				// The last carries the cursor, so the next reconnect replays from the ring.
				for it, j in items {
					stream.write(c, stream.sse_event(now if j == len(items) - 1 else "", "", it.html))
				}
			}
		case .Resync:
		}
		if how[i] == .Resync {
			// The id moves the client's cursor to now, so its next reconnect replays
			// from the ring instead of asking for a resync again.
			stream.write(c, stream.sse_event(now, "resync", want[i].topic))
			obs.inc(h.resyncs)
		}
	}

}

@(private)
find_row :: proc(table: []Topic, topic: string) -> ^Topic {
	family, _ := split_topic(topic)
	for &row in table {
		if row.family == family { return &row }
	}
	return nil
}

// A member row's key for this viewer: their id, as the topic names it.
member_key :: proc(v: authz.Viewer, allocator := context.temp_allocator) -> string {
	buf: [24]byte
	return strings.clone(strconv.write_uint(buf[:], v.id, 10), allocator)
}

// ---- the layout's #live (§9.1, D14) ------------------------------------------------------

// The page's one SSE stream: the viewer's own topics (every member row this host
// mounts, keyed by their id) and the page's, resuming after the hub's sequence now.
// "" when there is nothing to open. web.render_page calls it through web.on_live. A member's
// carries data-revoke: a revoke's `kicked` takes the page to sign in again, where a page's own
// kick (the lab's) reconnects.
live_html :: proc(page: []string) -> string {
	ctx := web.ctx()
	topics := make([dynamic]string, 0, MAX_TOPICS, context.temp_allocator)
	member := false
	if ctx.viewer.id != 0 {
		for row in h.hosts[ctx.site.name] {
			if row.member {
				append(&topics, strings.concatenate({row.family, ":", member_key(ctx.viewer)}, context.temp_allocator))
				member = true
			}
		}
	}
	for t in page {
		if len(topics) < MAX_TOPICS { append(&topics, t) }
	}
	if len(topics) == 0 { return "" }
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<div id="live"` if !member else `<div id="live" data-revoke="/login"`)
	strings.write_string(&b, ` hx-sse:connect="/events?t=`)
	escape.esc(&b, strings.join(topics[:], ",", context.temp_allocator))
	strings.write_string(&b, `&amp;after=`)
	escape.esc(&b, cursor_now())
	strings.write_string(&b, `"></div>`)
	return strings.to_string(b)
}
