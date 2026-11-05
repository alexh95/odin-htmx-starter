package chat_web

// ---- chat: routes, topics and the transport switch (PLAN §14.1, §6.4) ----------------------
//
// Four transports carry a room, all linked, chosen per request (`transport`): the
// pane's wiring and its endpoint are the chosen package's, everything else is here,
// once: a message is checked, limited, stored and announced by the same code whether
// it came as a form's POST or a socket's frame. Announcing is the room's topic (every
// transport's subscribers), the Inbox of everyone it mentions (notify_web.send, the
// one web-to-web import), and the unread counts of everyone who has read the room.

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

import "../../../platform/authz"
import "../../../platform/env"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/store"
import "../../../platform/web"
import "../../../platform/workers"
import notify_web "../../notify/web"
import chat ".."
import m "../models"
import chat_transport_multipart "../transport_multipart"
import chat_transport_poll "../transport_poll"
import chat_transport_sse "../transport_sse"
import chat_transport_ws "../transport_ws"
import chat_views "../views"

// Every transport's extensions, whichever a page uses (RESOLUTIONS X29; §12.1), and
// upsert, which every message swaps by.
EXTS :: chat_transport_ws.EXTS + chat_transport_sse.EXTS + chat_transport_poll.EXTS + chat_transport_multipart.EXTS + web.Exts{.Upsert, .Prompt}

// A message's body is 2,000 runes; URL-encoded, a rune can take 12 bytes.
POST_CAP :: 32 * 1024

ROUTES := [?]web.Route {
	{.Get, "/chat", index, .Public, {.Private}, 0}, // the rooms, or the LAN notice
	{.Get, "/chat/search", search_page, .Chat_Read, {.Private}, 0},
	{.Post, "/chat/rooms", create_room, .Chat_Create_Room, {.Fragment}, 1024},
	{.Post, "/chat/transport", set_transport, .Chat_Read, {.Fragment}, 256},
	{.Get, "/chat/r/([%w%-]+)", room_page, .Chat_Read, {.Private}, 0},
	{.Post, "/chat/r/([%w%-]+)", post_message, .Chat_Post, {.Fragment}, POST_CAP},
	{.Post, "/chat/r/([%w%-]+)/typing", typing, .Chat_Post, {.Fragment}, POST_CAP},
	{.Post, "/chat/r/([%w%-]+)/read", read, .Chat_Read, {.Fragment}, 0},
	{.Get, "/chat/r/([%w%-]+)/ws", chat_transport_ws.socket, .Chat_Read, {.Stream, .Fragment}, 0},
	{.Get, "/chat/r/([%w%-]+)/since", chat_transport_poll.since, .Chat_Read, {.Fragment}, 0},
	{.Get, "/chat/r/([%w%-]+)/parts", chat_transport_multipart.parts, .Chat_Read, {.Stream, .Fragment}, 0},
	{.Post, "/chat/r/([%w%-]+)/invite", invite, .Chat_Read, {.Fragment}, 64},
	{.Post, "/chat/r/([%w%-]+)/invites/(%d+)/revoke", revoke_invite, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/r/([%w%-]+)/leave", leave_room, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/dm/(%d+)", start_dm, .Chat_Dm, {.Fragment}, 0},
	{.Get, "/chat/join/([%w%-_%.]+)", join_page, .Chat_Read, {.Private}, 0},
	{.Post, "/chat/join/([%w%-_%.]+)", join_room, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/r/([%w%-]+)/lock", lock_room, .Chat_Moderate, {.Fragment}, 64},
	{.Post, "/chat/r/([%w%-]+)/slow", slow_room, .Chat_Moderate, {.Fragment}, 64},
	{.Post, "/chat/r/([%w%-]+)/mute/(%d+)", mute_member, .Chat_Moderate, {.Fragment}, 64},
	{.Post, "/chat/r/([%w%-]+)/kick/(%d+)", kick_member, .Chat_Moderate, {.Fragment}, 64},
	{.Get, "/chat/reports", reports_page, .Chat_Moderate, {.Private}, 0},
	{.Post, "/chat/reports/(%d+)/remove", report_remove, .Chat_Moderate, {.Fragment}, 0},
	{.Post, "/chat/reports/(%d+)/dismiss", report_dismiss, .Chat_Moderate, {.Fragment}, 0},
	{.Get, "/chat/m/(%d+)/menu", menu, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/m/(%d+)/remove", remove_message, .Chat_Moderate, {.Fragment}, 0},
	{.Post, "/chat/m/(%d+)/report", report_message, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/m/(%d+)/block", block_author, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/r/([%w%-]+)/block", block_peer, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/r/([%w%-]+)/remove/(%d+)", remove_member, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/r/([%w%-]+)/allow/(%d+)", allow_member, .Chat_Read, {.Fragment}, 0},
	{.Post, "/chat/unblock/(%d+)", unblock, .Chat_Read, {.Fragment}, 0},
	{.Get, "/chat/blocks", blocks_page, .Chat_Read, {.Private}, 0},
	{.Get, "/chat/m/(%d+)/edit", edit_form, .Chat_Post, {.Fragment}, 0},
	{.Post, "/chat/m/(%d+)/edit", edit, .Chat_Post, {.Fragment}, POST_CAP},
	{.Post, "/chat/m/(%d+)/delete", delete_message, .Chat_Post, {.Fragment}, 0},
}

// chat.room:<id>: a room's messages (the SSE transport's on #live, the socket's and
// multipart's on their own streams). chat.presence:<id> and chat.typing:<id> ride
// every room page's #live, keyed per member (.Latest); presence learns who is there
// from those streams opening and closing (`watch`). chat.reply: the bot's room answers, which
// arrive by name and are stored; nothing subscribes to it.
TOPICS := [?]hub.Topic {
	{family = "chat.room", policy = .Queue, persisted = chat.PERSISTED, perm = .Chat_Read, allow = room_readable, replay = replay_room},
	{family = "chat.presence", policy = .Latest, perm = .Chat_Read, allow = room_readable, watch = watch_room},
	{family = "chat.typing", policy = .Latest, ring = 64, perm = .Chat_Read, allow = room_readable},
	{family = "chat.reply", policy = .Queue, perm = .Chat_Read, deliver = store_reply},
}

JOBS := [?]workers.Job {
	{"chat.presence", 5 * time.Second, sweep_presence, nil},
	{"chat.retention", time.Minute, sweep_old, nil},
	{"chat.optimize", time.Hour, optimize_index, sunday_night},
}

// §17.5: posts 5 per 10 s per member (a fixed window: up to 10 across a boundary),
// typing 1 per 2 s.
@(private) posts := web.Limit{n = 5, window = 10 * time.Second}
@(private) typists := web.Limit{n = 1, window = 2 * time.Second}
@(private) reporting := web.Limit{window = time.Minute} // n's from the env, as these three
@(private) writes := web.Limit{window = time.Minute}
@(private) searches := web.Limit{window = time.Second}

@(private)
SLOW_DOWN :: "Slow down: at most 5 messages in 10 seconds."

@(private)
SLOW_MODE :: "Slow mode: one message every %d seconds here."

COOKIE :: "chat_transport"
FALLBACK :: "chat_fallback"

// At boot, before app.check: the domain's env rows and store, and the socket's post path.
init :: proc() {
	chat.init()
	chat_transport_ws.post = socket_post
	reporting.n = env.int_("CHAT_REPORTS_PER_MINUTE")
	writes.n = env.int_("CHAT_WRITES_PER_MINUTE")
	searches.n = env.int_("CHAT_SEARCHES_PER_SECOND")
}

// From main, once the store is open: the lobby into an empty one.
seed :: proc() { chat.seed() }

// The viewer's setting: kept on their account, else their browser's, else CHAT_TRANSPORT.
setting :: proc(req: ^web.Request) -> string {
	if s := web.viewer(req).connection; chat.known_setting(s) { return s }
	if s := web.cookie(req, COOKIE); chat.known_setting(s) { return s }
	return chat.default_setting()
}

// The transport a request's page uses: `?transport=` (the specs'), else the setting. `auto`: the
// page falls back by itself, and FALLBACK is what it left behind when it did.
transport :: proc(req: ^web.Request) -> (t: chat.Transport, auto: bool) {
	s := web.query_get(req, "transport")
	if !chat.known_setting(s) { s = setting(req) }
	if s == chat.AUTO {
		return .Sse if web.cookie(req, FALLBACK) == "sse" else .Ws, true
	}
	t, _ = chat.transport_named(s)
	return t, false
}

// ---- pages -------------------------------------------------------------------------------

@(private)
index :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	if !authz.can(v, .Chat_Read) {
		web.render_page(req, res, "Chat", "/chat", "Chat is open on the LAN.", chat_views.lan_notice_page())
		return
	}
	all := make([dynamic]m.Room, context.temp_allocator)
	if err := chat.rooms_for(v, &all); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	rows := make([]chat_views.Room_Row, len(all), context.temp_allocator)
	for r, i in all { rows[i] = {r, chat.unread(r.id, v.id)} }
	web.render_page(req, res, "Chat", "/chat", "The rooms on the LAN.", chat_views.index_page(rows, setting(req), chat.may_create(.Public, v), chat.may_create(.Announce, v), open_reports(v)))
}

// What a member finds in the rooms they may read (a plain GET form: it works with no script).
@(private)
search_page :: proc(req: ^web.Request, res: ^web.Response) {
	q := web.query_get(req, "q")
	if len(q) > chat.MAX_SEARCH_QUERY {
		end := chat.MAX_SEARCH_QUERY
		for end > 0 && !utf8.rune_start(q[end]) { end -= 1 } // not through a character
		q = q[:end]
	}
	if ok, retry := web.limit_hit(&searches, web.viewer(req).id); !ok {
		web.respond_limited(res, retry, "Too many searches: wait a moment.")
		return
	}
	s := web.new_scan(Searching, req, res, proc(scan: ^web.Scan) {
		s := (^Searching)(scan)
		s.hits = make([dynamic]m.Hit, context.temp_allocator)
		s.err = chat.search(s.viewer, s.q, &s.hits)
	}, proc(scan: ^web.Scan, req: ^web.Request, res: ^web.Response) {
		s := (^Searching)(scan)
		if s.err != .None {
			web.respond_store_error(req, res, s.err)
			return
		}
		web.render_page(req, res, "Search", "/chat", "Search the rooms you can read.", chat_views.search_page(s.q, s.hits[:]))
	})
	if s == nil { return }
	s.viewer, s.q = web.viewer(req), q
	web.start_scan(req, res, s)
}

@(private)
Searching :: struct {
	using scan: web.Scan,
	viewer:     authz.Viewer,
	q:          string, // the request's: it lives until the answer
	hits:       [dynamic]m.Hit,
	err:        m.Error,
}

@(private)
sunday_night :: proc() -> bool {
	t := time.now()
	hour, _, _ := time.clock_from_time(t)
	return time.weekday(t) == .Sunday && hour == 3
}

@(private)
optimize_index :: proc() {
	if err := chat.optimize(); err != .None { workers.fail("the index: %v", err) }
}

@(private)
room_page :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	r, err := chat.room_for(req.url_params[0], v)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	chat.seen(v.id, v.name)
	t, auto := transport(req)
	web.impl(res, "chat.transport", chat.TRANSPORTS[t].name)
	msgs := make([dynamic]m.Message, 0, chat.SNAPSHOT, context.temp_allocator)
	ver, serr := chat.snapshot(r.id, &msgs)
	if serr != .None {
		web.respond_store_error(req, res, serr)
		return
	}
	here := make([dynamic]chat.Presence_Change, context.temp_allocator)
	chat.present(r.id, &here)

	live := make([dynamic]string, 0, 3, context.temp_allocator)
	append(&live, chat.presence_topic(r.id), chat.typing_topic(r.id))
	wiring: chat_views.Wiring
	switch t {
	case .Ws:
		wiring = chat_transport_ws.wiring(r)
		if auto { wiring.pane = strings.concatenate({wiring.pane, " data-auto"}, context.temp_allocator) }
	case .Sse:
		wiring = chat_transport_sse.wiring(r)
		append(&live, chat_transport_sse.live_topic(r, msgs[len(msgs) - 1].id if len(msgs) > 0 else 0))
	case .Poll:
		wiring = chat_transport_poll.wiring(r, ver)
	case .Multipart:
		wiring = chat_transport_multipart.wiring(r)
	}
	peer: chat_views.Dm_Peer
	if r.kind == .Dm {
		peer.id = chat.dm_peer(r, v.id)
		peer.blocked = chat.blocking(v.id, peer.id)
	}
	kept_out := make([dynamic]m.Ban, context.temp_allocator)
	if chat.may_remove(r, v) { _ = chat.removed_members(r, &kept_out) }
	rv := chat_views.Room_View{
		peer = peer, removed = kept_out[:], may_remove = chat.may_remove(r, v),
		cannot_post = chat.why_not_post(r, v), may_invite = chat.may_invite(r, v), may_leave = chat.may_leave(r, v),
		may_moderate = chat.may_moderate(r, v), may_attach = authz.can(v, .Chat_Attach), mute_button = notify_web.mute_button(v.id, chat.room_topic(r.id), "this room"),
	}
	if r.kind == .Private || r.kind == .Dm {
		list := make([dynamic]m.Member, context.temp_allocator)
		if merr := chat.members(r, &list); merr != .None {
			web.respond_store_error(req, res, merr)
			return
		}
		rv.members = list[:]
	}
	if rv.may_invite {
		open := make([dynamic]m.Invite, context.temp_allocator)
		if ierr := chat.invites(r, &open); ierr != .None {
			web.respond_store_error(req, res, ierr)
			return
		}
		rv.invites = open[:]
	}
	title := r.name if r.kind == .Dm else fmt.tprintf("#%s", r.name)
	web.render_page(req, res, title, "/chat", "A chat room on the LAN.",
		chat_views.room_page(r, msgs[:], ver, here[:], v.id, t, wiring, rv), live = live[:])
}

// The Connection setting, on the member's account where the build keeps one, else a cookie for
// a year, then back to the rooms.
@(private)
set_transport :: proc(req: ^web.Request, res: ^web.Response) {
	s := web.form(req)["transport"]
	if !chat.known_setting(s) {
		web.respond_status(res, .Bad_Request)
		return
	}
	v := web.viewer(req)
	if v.id != 0 && !write_allowed(req, res) { return }
	if authz.keep_connection == nil || v.id == 0 || !authz.keep_connection(v.id, s) {
		web.set_header(res, "set-cookie", fmt.tprintf("%s=%s; Path=/chat; Max-Age=31536000; SameSite=Lax; HttpOnly%s", COOKIE, s, "; Secure" if web.ctx().https else ""))
	}
	web.set_header(res, "location", "/chat")
	web.respond_status(res, .See_Other)
}

// A room's kind as the form names it; an unknown one is refused.
@(private)
KINDS := [?]struct {
	name: string,
	kind: m.Room_Kind,
} {{"public", .Public}, {"private", .Private}, {"announce", .Announce}}

@(private)
create_room :: proc(req: ^web.Request, res: ^web.Response) {
	if !write_allowed(req, res) { return }
	if chat.too_many_rooms(web.viewer(req)) {
		web.respond_html(res, html.field_msg(false, "You have as many rooms as you can."), .Unprocessable_Content)
		return
	}
	f := web.form(req)
	name, slug, problem := chat.check_room(f["name"])
	if problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	kind, known := m.Room_Kind.Public, f["kind"] == ""
	for k in KINDS {
		if k.name == f["kind"] { kind, known = k.kind, true }
	}
	if !known {
		web.respond_html(res, html.field_msg(false, "Pick who reads the room."), .Unprocessable_Content)
		return
	}
	v := web.viewer(req)
	if !chat.may_create(kind, v) {
		web.respond_html(res, html.field_msg(false, "Announcements are the moderators' to make."), .Forbidden)
		return
	}
	r, err := chat.create_room(slug, name, kind, v)
	switch err {
	case .None:
	case .Constraint:
		web.respond_html(res, html.field_msg(false, "That room exists already, or there are as many rooms as there may be."), .Unprocessable_Content)
		return
	case .Not_Found, .Busy, .Failed:
		web.respond_store_error(req, res, err)
		return
	}
	web.set_header(res, "hx-redirect", fmt.tprintf("/chat/r/%s", r.slug))
	web.respond_status(res, .No_Content)
}

// One limit over what's rare and small enough to write as it comes (§14.1): its answers are the
// toast slot's.
@(private)
write_allowed :: proc(req: ^web.Request, res: ^web.Response) -> bool {
	ok, retry := web.limit_hit(&writes, web.viewer(req).id)
	if !ok { web.respond_limited(res, retry, html.toast("error", "That's a lot of changes at once: wait a minute.", false)) }
	return ok
}

// ---- posting --------------------------------------------------------------------------------

// What a post carries to its continuation.
@(private)
Posting :: struct {
	using post: m.Post,
	deferred:   web.Deferred,
	http:       bool, // a form's POST, answered with the message; a socket's is answered by the hub
	slug:       string,
	room_name:  string,
	room_kind:  m.Room_Kind,
}

@(private)
post_message :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	r, err := chat.room_for(req.url_params[0], v)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if why := chat.why_not_post(r, v); why != "" {
		web.respond_html(res, html.field_msg(false, why), .Forbidden)
		return
	}
	f := web.form(req)
	blob := attachment(v, f["attachment"])
	body, problem := chat.check_post(f["body"], blob)
	if problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	if ok, retry := web.limit_hit(&posts, v.id); !ok {
		web.respond_limited(res, retry, html.toast("error", SLOW_DOWN, false))
		return
	}
	if wait := chat.slow_wait(r, v); wait > 0 {
		web.respond_limited(res, time.Duration(wait) * time.Second, html.toast("error", fmt.tprintf(SLOW_MODE, r.slow), false))
		return
	}
	chat.slow_mark(r, v.id)
	op := posting(v, r, body, blob)
	op.http = true
	web.defer_response(req, res, &op.deferred)
	if !chat.post(op) {
		if rr := web.resume(&op.deferred); rr != nil {
			web.respond_store_error(req, rr, .Busy)
			web.finish(&op.deferred, rr)
		}
		store.free_op(op)
	}
}

// A socket's frame takes the form's path; what it refuses goes back down the socket.
@(private)
socket_post :: proc(s: ^chat_transport_ws.Socket, raw, attached: string) {
	if !authz.can(s.who, .Chat_Post) { return }
	// The room as it is now: a socket outlives a lock, slow mode, a kick and a leave.
	r, err := chat.room_for(s.room.slug, s.who)
	if err != .None { return }
	if why := chat.why_not_post(r, s.who); why != "" {
		chat_transport_ws.send(s, fmt.tprintf(`<p hx-swap-oob="innerHTML:#err-%d">%s</p>`, r.id, escaped(why)))
		return
	}
	blob := attachment(s.who, attached)
	body, problem := chat.check_post(raw, blob)
	if problem != "" {
		chat_transport_ws.send(s, fmt.tprintf(`<p hx-swap-oob="innerHTML:#err-%d">%s</p>`, s.room.id, escaped(problem)))
		return
	}
	if ok, _ := web.limit_hit(&posts, s.who.id); !ok {
		chat_transport_ws.send(s, html.toast("error", SLOW_DOWN, true))
		return
	}
	if chat.slow_wait(r, s.who) > 0 {
		chat_transport_ws.send(s, html.toast("error", fmt.tprintf(SLOW_MODE, r.slow), true))
		return
	}
	chat.slow_mark(r, s.who.id)
	op := posting(s.who, r, body, blob)
	if !chat.post(op) {
		store.free_op(op)
		chat_transport_ws.send(s, html.toast("error", "Chat is busy. Try again in a moment.", true))
	}
}

// What a post may attach: nothing, without the perm.
@(private)
attachment :: proc(v: authz.Viewer, sha: string) -> string { return sha if authz.can(v, .Chat_Attach) else "" }

@(private)
posting :: proc(v: authz.Viewer, r: m.Room, body, blob: string) -> ^Posting {
	// The inputs, and the stored message the store answers with in the same arena.
	op := store.new_op(Posting, 2 * (len(body) + len(v.name) + len(blob)) + len(r.slug) + len(r.name))
	a := store.op_allocator(op)
	op.room, op.author = r.id, v.id
	op.name, op.body, op.blob = strings.clone(v.name, a), strings.clone(body, a), strings.clone(blob, a)
	op.slug, op.room_name, op.room_kind = strings.clone(r.slug, a), strings.clone(r.name, a), r.kind
	op.done = posted
	return op
}

@(private)
posted :: proc(o: ^store.Op) {
	op := (^Posting)(o)
	defer store.free_op(op)
	// Resumed before anything else runs: a crash in the publishing is then this request's
	// 500, not a connection left deferred and unwatched (M2-12).
	res: ^web.Response
	if op.http { res = web.resume(&op.deferred) }
	if op.err == .None { announce(op.slug, op.room_name, op.room_kind, op.result) }
	if res == nil { return } // a socket's post, or the client left: the message is posted all the same
	if op.err != .None {
		web.respond_store_error(web.request(&op.deferred), res, op.err)
	} else {
		web.respond_html(res, chat_views.one(op.room, op.slug, op.result))
	}
	web.finish(&op.deferred, res)
}

// chat.reply:<room>'s row: the bot's answer, as a message from it, cut to what a message may hold.
// It may have come out of a question nobody here wrote, so it goes where any message goes, escaped.
@(private)
store_reply :: proc(topic, text: string, _: i64) {
	_, key := hub.split_topic(topic)
	id, ok := strconv.parse_i64(key, 10)
	if !ok { return }
	r, err := chat.room_by_id(id)
	if err != .None { return }
	body := chat.cut_body(text)
	if body == "" { return }
	op := posting({name = chat.BOT_NAME}, r, body, "")
	op.done = replied
	if !chat.post(op) { store.free_op(op) }
}

// Not `announce`: an answer is a model's words, and asking it to says anything. To the room and its
// unread counts only, so it names nobody into their Inbox and can't ask the bot in turn.
@(private)
replied :: proc(o: ^store.Op) {
	op := (^Posting)(o)
	defer store.free_op(op)
	if op.err != .None { return }
	hub.publish(chat.room_topic(op.result.room), chat_views.one(op.result.room, op.slug, op.result), op.result.id)
	unread_counts(op.slug, m.Room{id = op.result.room, kind = op.room_kind}, op.result)
}

// A new message to the room, the Inbox of whoever it mentions, and the unread counts
// of everyone who has read the room (theirs on every page, through notify.user). Only to
// those who may read it: a private room's mention of someone outside it says nothing to them.
@(private)
announce :: proc(slug, room_name: string, kind: m.Room_Kind, msg: m.Message) {
	hub.publish(chat.room_topic(msg.room), chat_views.one(msg.room, slug, msg), msg.id)
	if kind != .Dm {
		if q, asked := chat.asks_bot(msg.body); asked {
			// By name: without bot nothing mounts it, and the publish is dropped and counted (X37).
			hub.publish(fmt.tprintf("bot.ask:%d", msg.room), fmt.tprintf("%d\n%s", msg.author, q), msg.id)
		}
	}
	r := m.Room{id = msg.room, kind = kind}
	ref := fmt.tprintf("/chat/r/%s#m-%d", slug, msg.id)
	scope := chat.room_topic(msg.room) // what a member mutes a room by

	who := make([dynamic]u64, 0, 8, context.temp_allocator)
	if kind == .Dm {
		// Every message of a DM is for its other member; a mention would say so twice.
		pair := make([dynamic]m.Member, 0, 2, context.temp_allocator)
		_ = chat.members(r, &pair)
		line := chat_views.dm_line(msg.name, msg.body)
		for mem in pair {
			if mem.who != msg.author && !chat.blocking(mem.who, msg.author) { notify_web.send(mem.who, "chat.dm", ref, line, scope) }
		}
	} else {
		chat.mentioned(msg.body, msg.author, &who)
		if len(who) > 0 {
			line := chat_views.mention_line(msg.name, room_name, msg.body)
			for id in who {
				if chat.reads(r, id) && !chat.blocking(id, msg.author) { notify_web.send(id, "chat.mention", ref, line, scope) }
			}
		}
	}

	unread_counts(slug, r, msg)
}

// Everyone who has read the room but `msg`'s author: their count, on every page of theirs.
@(private)
unread_counts :: proc(slug: string, r: m.Room, msg: m.Message) {
	who := make([dynamic]u64, 0, 8, context.temp_allocator)
	chat.readers(msg.room, &who)
	for id in who {
		if id == msg.author || !chat.reads(r, id) { continue }
		hub.publish(notify_web.topic(id), chat_views.unread(slug, chat.unread(msg.room, id)))
	}
}

// ---- a message's menu, edit and delete ---------------------------------------------------------

// The menu, rendered for this viewer: their own message gets Edit and Delete while
// the window lasts.
@(private)
menu :: proc(req: ^web.Request, res: ^web.Response) {
	msg, r, ok := message_of(req, res)
	if !ok { return }
	v := web.viewer(req)
	other := msg.author != 0 && msg.author != v.id
	acts := chat_views.Menu{
		may_change = chat.may_change(msg, v.id), may_dm = authz.can(v, .Chat_Dm) && other,
		// The bot's aren't a member's, but what it said can be reported and removed like anyone's.
		may_moderate = chat.may_moderate(r, v) && msg.author != v.id, may_discipline = chat.may_moderate(r, v) && other, may_report = msg.author != v.id && v.id != 0,
		may_block = other && v.id != 0, blocked = other && chat.blocking(v.id, msg.author),
	}
	web.respond_html(res, chat_views.menu(msg, r.slug, acts))
}

@(private)
edit_form :: proc(req: ^web.Request, res: ^web.Response) {
	msg, r, ok := message_of(req, res)
	if !ok { return }
	v := web.viewer(req)
	if !chat.may_change(msg, v.id) {
		web.respond_html(res, html.field_msg(false, "Only your own messages, for 10 minutes."), .Forbidden)
		return
	}
	if why := chat.why_not_post(r, v); why != "" {
		web.respond_html(res, html.field_msg(false, why), .Forbidden)
		return
	}
	web.respond_html(res, chat_views.edit_form(msg.id, msg.body, ""))
}

@(private)
Changing :: struct {
	using change: m.Change,
	deferred:     web.Deferred,
	slug:         string,
	room_name:    string,
	typed:        string,
	refresh:      bool, // answered by reloading the page (a report's removal), not with the message
	closes:       i64,  // the report this removal closes, once it's stored
}

@(private)
edit :: proc(req: ^web.Request, res: ^web.Response) {
	msg, r, ok := message_of(req, res)
	if !ok { return }
	typed := web.form(req)["body"]
	v := web.viewer(req)
	if why := chat.why_not_post(r, v); why != "" { // a mute or a lock holds for what's already said
		web.respond_html(res, chat_views.edit_form(msg.id, typed, why), .Forbidden)
		return
	}
	body, problem := chat.check_body(typed)
	if problem != "" {
		web.respond_html(res, chat_views.edit_form(msg.id, typed, problem), .Unprocessable_Content)
		return
	}
	if allowed, retry := web.limit_hit(&posts, v.id); !allowed {
		web.respond_limited(res, retry, html.toast("error", SLOW_DOWN, false))
		return
	}
	change(req, res, msg, r, body, false)
}

@(private)
delete_message :: proc(req: ^web.Request, res: ^web.Response) {
	msg, r, ok := message_of(req, res)
	if !ok { return }
	change(req, res, msg, r, "", true)
}

@(private)
change :: proc(req: ^web.Request, res: ^web.Response, msg: m.Message, r: m.Room, body: string, del: bool) {
	op := changing(req, res, msg, r, body, del)
	if !chat.change(op) { unqueued(req, op) }
}

// A Changing op for `msg`, its response deferred.
@(private)
changing :: proc(req: ^web.Request, res: ^web.Response, msg: m.Message, r: m.Room, body: string, del: bool) -> ^Changing {
	v := web.viewer(req)
	// The store clones the row beside the new text; `remove` adds an audit entry's strings.
	op := store.new_op(Changing, 3 * len(body) + 2 * (len(msg.name) + len(msg.body) + len(msg.blob)) + len(r.slug) + len(r.name) + len(v.name) + 256 + 4 * web.MAX_REASON)
	a := store.op_allocator(op)
	op.id, op.author, op.delete = msg.id, v.id, del
	op.body, op.typed = strings.clone(body, a), strings.clone(body, a)
	op.slug, op.room_name = strings.clone(r.slug, a), strings.clone(r.name, a)
	op.done = changed
	web.defer_response(req, res, &op.deferred)
	return op
}

// The store was busy: the deferred response answers 503, and the op goes.
@(private)
unqueued :: proc(req: ^web.Request, op: ^Changing) {
	if rr := web.resume(&op.deferred); rr != nil {
		web.respond_store_error(req, rr, .Busy)
		web.finish(&op.deferred, rr)
	}
	store.free_op(op)
}

@(private)
changed :: proc(o: ^store.Op) {
	op := (^Changing)(o)
	defer store.free_op(op)
	res := web.resume(&op.deferred) // first, as posted's
	if op.err == .None {
		hub.publish(chat.room_topic(op.result.room), chat_views.one(op.result.room, op.slug, op.result), op.result.id)
		chat.released(op.released)
		if op.closes != 0 { op.err = chat.close_report(op.closes, op.audit) }
		if op.delete { notify_web.retract(fmt.tprintf("/chat/r/%s#m-%d", op.slug, op.result.id)) }
	}
	if res == nil { return }
	switch op.err {
	case .None:
		if op.refresh {
			web.set_header(res, "hx-refresh", "true")
			web.respond_status(res, .No_Content)
		} else {
			web.respond_html(res, chat_views.one(op.result.room, op.slug, op.result))
		}
	case .Constraint:
		web.respond_html(res, chat_views.edit_form(op.id, op.typed, "Only your own messages, for 10 minutes."), .Unprocessable_Content)
	case .Not_Found, .Busy, .Failed:
		web.respond_store_error(web.request(&op.deferred), res, op.err)
	}
	web.finish(&op.deferred, res)
}

@(private)
message_of :: proc(req: ^web.Request, res: ^web.Response) -> (msg: m.Message, r: m.Room, ok: bool) {
	id, idok := web.parse_id(req.url_params[0])
	if !idok {
		web.not_found(req, res)
		return
	}
	err: m.Error
	if msg, err = chat.message(id); err == .None { r, err = chat.room_by_id(msg.room) }
	if err == .None && !chat.may_read(r, web.viewer(req)) { err = .Not_Found } // as the room is
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	return msg, r, true
}

// ---- typing and reading ------------------------------------------------------------------------

// "<name> is typing", at most once in 2 s per member; the rest are dropped quietly.
@(private)
typing :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	r, err := chat.room_for(req.url_params[0], v)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if !chat.may_post(r, v) {
		web.respond_status(res, .Forbidden)
		return
	}
	if ok, _ := web.limit_hit(&typists, v.id); ok {
		buf: [24]byte
		hub.publish(chat.typing_topic(r.id), chat_views.typing(r.id, v.id, v.name), 0, strconv.write_uint(buf[:], v.id, 10))
	}
	web.respond_status(res, .No_Content)
}

// A read receipt: the member's cursor moves to `upto`, and their unread count for the
// room, on every page of theirs, to what is left.
@(private)
read :: proc(req: ^web.Request, res: ^web.Response) {
	r, err := chat.room_for(req.url_params[0], web.viewer(req))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	upto, ok := web.parse_id(web.query_get(req, "upto"))
	if !ok {
		web.respond_status(res, .Bad_Request)
		return
	}
	v := web.viewer(req)
	if chat.mark_read(r.id, v.id, upto) {
		hub.publish(notify_web.topic(v.id), chat_views.unread(r.slug, chat.unread(r.id, v.id)))
	}
	web.respond_status(res, .No_Content)
}

// ---- private rooms and DMs: invites, leaving, starting one --------------------------------------

// A new invite link to a private room (`once`: a single use), and its open invites, for its owner
// or a moderator among its members.
@(private)
invite :: proc(req: ^web.Request, res: ^web.Response) {
	if !write_allowed(req, res) { return }
	r, v, ok := inviting(req, res)
	if !ok { return }
	inv, token, err := chat.new_invite(r, v, web.form(req)["once"] == "1")
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	open_invites(req, res, r, token, inv, 0)
}

@(private)
revoke_invite :: proc(req: ^web.Request, res: ^web.Response) {
	if !write_allowed(req, res) { return }
	r, _, ok := inviting(req, res)
	if !ok { return }
	id, idok := web.parse_id(req.url_params[1])
	if !idok {
		web.not_found(req, res)
		return
	}
	if err := chat.revoke_invite(r, id); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	open_invites(req, res, r, "", {}, id)
}

@(private)
inviting :: proc(req: ^web.Request, res: ^web.Response) -> (r: m.Room, v: authz.Viewer, ok: bool) {
	v = web.viewer(req)
	err: m.Error
	if r, err = chat.room_for(req.url_params[0], v); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if !chat.may_invite(r, v) {
		web.respond_html(res, html.field_msg(false, "Only the room's owner hands out its invites."), .Forbidden)
		return
	}
	return r, v, true
}

// The open invites after a write: the handler's reads share one snapshot, taken before it, so the
// one just made is added and the one just revoked left out here.
@(private)
open_invites :: proc(req: ^web.Request, res: ^web.Response, r: m.Room, token: string, added: m.Invite, revoked: i64) {
	read := make([dynamic]m.Invite, context.temp_allocator)
	if err := chat.invites(r, &read); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	list := make([dynamic]m.Invite, 0, len(read) + 1, context.temp_allocator)
	if added.id != 0 { append(&list, added) }
	for inv in read {
		if inv.id != revoked && inv.id != added.id { append(&list, inv) }
	}
	web.respond_html(res, chat_views.invites(r, list[:], token))
}

// The link's page. Its token is in the path: the access log names the route's pattern only, and
// the page sends a Referer to this origin alone, so the token goes nowhere else. Not no-referrer:
// under it a browser sends the form's POST `Origin: null`, which the cross-site write guard
// refuses wherever there is no Sec-Fetch-Site to go by (plain http to a non-local host).
@(private)
join_page :: proc(req: ^web.Request, res: ^web.Response) {
	token := req.url_params[0]
	r, _, err := chat.invited_to(token)
	web.set_header(res, "referrer-policy", "same-origin")
	v := web.viewer(req)
	if err != .None || chat.kept_out(r, v.id) {
		web.not_found(req, res) // forged, revoked, expired or spent, or not for them: no room to name
		return
	}
	web.render_page(req, res, "Join a room", "/chat", "An invite to a private room.", chat_views.join_page(r, token, chat.may_read(r, v)))
}

@(private)
join_room :: proc(req: ^web.Request, res: ^web.Response) {
	if !write_allowed(req, res) { return }
	r, inv, err := chat.invited_to(req.url_params[0])
	web.set_header(res, "referrer-policy", "same-origin")
	if err != .None || chat.kept_out(r, web.viewer(req).id) {
		web.not_found(req, res)
		return
	}
	if jerr := chat.accept_invite(inv, web.viewer(req)); jerr != .None {
		if jerr == .Not_Found { // spent or revoked between the two reads
			web.not_found(req, res)
			return
		}
		web.respond_store_error(req, res, jerr)
		return
	}
	web.set_header(res, "location", fmt.tprintf("/chat/r/%s", r.slug))
	web.respond_status(res, .See_Other) // a plain form's POST: the browser follows it
}

// Leaving a private room: back to the rooms, and a new invite to come back.
@(private)
leave_room :: proc(req: ^web.Request, res: ^web.Response) {
	if !write_allowed(req, res) { return }
	v := web.viewer(req)
	r, err := chat.room_for(req.url_params[0], v)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if !chat.may_leave(r, v) {
		web.respond_status(res, .Forbidden)
		return
	}
	if lerr := chat.leave_room(r, v); lerr != .None {
		web.respond_store_error(req, res, lerr)
		return
	}
	out_of_room(r, v.id)
	web.set_header(res, "hx-redirect", "/chat")
	web.respond_status(res, .No_Content)
}

// The room an owner's Remove or Allow names, and the member: an owner's alone, private rooms' alone.
@(private)
owned_member :: proc(req: ^web.Request, res: ^web.Response) -> (r: m.Room, who: u64, ok: bool) {
	if !write_allowed(req, res) { return }
	v := web.viewer(req)
	err: m.Error
	if r, err = chat.room_for(req.url_params[0], v); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if !chat.may_remove(r, v) {
		web.respond_status(res, .Forbidden)
		return
	}
	id, idok := web.parse_id(req.url_params[1])
	if !idok || u64(id) == v.id {
		web.not_found(req, res)
		return
	}
	return r, u64(id), true
}

@(private)
remove_member :: proc(req: ^web.Request, res: ^web.Response) {
	r, who, ok := owned_member(req, res)
	if !ok { return }
	list := make([dynamic]m.Member, 0, 8, context.temp_allocator)
	_ = chat.members(r, &list)
	for mem in list {
		if mem.who != who { continue }
		if err := chat.remove_member(r, actor(), who, mem.name); err != .None {
			web.respond_store_error(req, res, err)
			return
		}
		out_of_room(r, who)
		refresh(res)
		return
	}
	web.not_found(req, res)
}

@(private)
allow_member :: proc(req: ^web.Request, res: ^web.Response) {
	r, who, ok := owned_member(req, res)
	if !ok { return }
	if !chat.kept_out(r, who) {
		web.not_found(req, res)
		return
	}
	if err := chat.allow_member(r, actor(), who); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	refresh(res)
}

// A DM with a message's author (the menu's "Message <name>"): theirs, made when there is none.
@(private)
start_dm :: proc(req: ^web.Request, res: ^web.Response) {
	if !write_allowed(req, res) { return }
	other, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	v := web.viewer(req)
	if chat.walled(v.id, u64(other)) {
		web.respond_html(res, html.toast("error", chat.CANT_MESSAGE, true), .Forbidden)
		return
	}
	r, err := chat.dm(v, u64(other))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.set_header(res, "hx-redirect", fmt.tprintf("/chat/r/%s", r.slug))
	web.respond_status(res, .No_Content)
}

// ---- blocks ------------------------------------------------------------------------------------
//
// A's alone: a DM closes both ways, and B's mentions and DMs stop reaching A's Inbox. Public rooms
// don't change (no per-viewer filtering of the fan-out), moderation doesn't notice, nothing's audited.

@(private)
block_member :: proc(req: ^web.Request, res: ^web.Response, other: u64, name: string) {
	if !write_allowed(req, res) { return }
	v := web.viewer(req)
	if err := chat.block(v.id, other, name); err != .None {
		web.respond_html(res, html.toast("error", "You can't block yourself.", true), .Unprocessable_Content)
		return
	}
	refresh(res)
}

// From a message's menu: its author, under the name they wrote it under.
@(private)
block_author :: proc(req: ^web.Request, res: ^web.Response) {
	msg, _, ok := message_of(req, res)
	if ok { block_member(req, res, msg.author, msg.name) }
}

// From a DM's page: its other member.
@(private)
block_peer :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	r, err := chat.room_for(req.url_params[0], v)
	if err == .None && (r.kind != .Dm || !chat.may_read(r, v)) { err = .Not_Found }
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	pair := make([dynamic]m.Member, 0, 2, context.temp_allocator)
	_ = chat.members(r, &pair)
	for mem in pair {
		if mem.who != v.id {
			block_member(req, res, mem.who, mem.name)
			return
		}
	}
	web.not_found(req, res)
}

@(private)
unblock :: proc(req: ^web.Request, res: ^web.Response) {
	if !write_allowed(req, res) { return }
	other, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	if err := chat.unblock(web.viewer(req).id, u64(other)); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	refresh(res)
}

@(private)
blocks_page :: proc(req: ^web.Request, res: ^web.Response) {
	list := make([dynamic]m.Block, context.temp_allocator)
	if err := chat.blocks(web.viewer(req).id, &list); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, "Blocked members", "/chat", "The members you've blocked.", chat_views.blocks_page(list[:]))
}

// ---- moderation (§14.1) -------------------------------------------------------------------------
//
// A moderator's acts in a public room or announcements, each with its reason (hx-prompt) and
// audited; private rooms and DMs only through a member's report.

@(private)
actor :: proc() -> chat.Actor {
	c := web.ctx()
	buf := make([]byte, 16, context.temp_allocator)
	return {c.viewer.id, c.viewer.name, web.client_id(c.client, buf)}
}

// The room, when the viewer moderates it, and their reason; otherwise answered here.
@(private)
moderating :: proc(req: ^web.Request, res: ^web.Response) -> (r: m.Room, reason: string, ok: bool) {
	v := web.viewer(req)
	err: m.Error
	if r, err = chat.room_for(req.url_params[0], v); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if !chat.may_moderate(r, v) {
		web.respond_html(res, html.toast("error", "Private rooms and DMs are moderated through reports.", true), .Forbidden)
		return
	}
	reason, ok = web.prompt_reason(req, res)
	return
}

// A change to the room's state shows on the next page: reload this one.
@(private)
refresh :: proc(res: ^web.Response) {
	web.set_header(res, "hx-refresh", "true")
	web.respond_status(res, .No_Content)
}

@(private)
lock_room :: proc(req: ^web.Request, res: ^web.Response) {
	r, reason, ok := moderating(req, res)
	if !ok { return }
	if err := chat.set_lock(r, actor(), web.form(req)["locked"] == "1", reason); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	refresh(res)
}

@(private)
slow_room :: proc(req: ^web.Request, res: ^web.Response) {
	r, reason, ok := moderating(req, res)
	if !ok { return }
	seconds, sok := strconv.parse_int(web.form(req)["seconds"], 10)
	if !sok || seconds < 0 {
		web.respond_html(res, html.toast("error", "Slow mode is a number of seconds.", true), .Unprocessable_Content)
		return
	}
	if err := chat.set_slow(r, actor(), seconds, reason); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	refresh(res)
}

@(private)
mute_member :: proc(req: ^web.Request, res: ^web.Response) { ban_member(req, res, .Mute) }

@(private)
kick_member :: proc(req: ^web.Request, res: ^web.Response) { ban_member(req, res, .Kick) }

// A mute or a kick of a room's member for `minutes` (0 lifts it).
@(private)
ban_member :: proc(req: ^web.Request, res: ^web.Response, kind: m.Ban_Kind) {
	r, reason, ok := moderating(req, res)
	if !ok { return }
	who, wok := web.parse_id(req.url_params[1])
	minutes, mok := strconv.parse_int(web.form(req)["minutes"], 10)
	if !wok || !mok || minutes < 0 {
		web.respond_html(res, html.toast("error", "Name a member and the minutes.", true), .Unprocessable_Content)
		return
	}
	if u64(who) == web.viewer(req).id {
		web.respond_html(res, html.toast("error", "Not yourself.", true), .Unprocessable_Content)
		return
	}
	if err := chat.set_ban(r, actor(), u64(who), kind, minutes, reason); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if kind == .Kick && minutes > 0 { out_of_room(r, u64(who)) }
	what := "Muted" if kind == .Mute else "Kicked"
	if minutes == 0 { what = "Unmuted" if kind == .Mute else "Let back in" }
	web.respond_html(res, html.toast("ok", fmt.tprintf("%s for %d minutes.", what, min(minutes, chat.MAX_BAN)) if minutes > 0 else what, true))
}

// Who no longer reads a room keeps no stream on it: whatever their transport (a socket's or
// multipart's own, the room on #live) and their page's presence.
@(private)
out_of_room :: proc(r: m.Room, who: u64) {
	hub.kick_member(chat.room_topic(r.id), who, "/chat")
	hub.kick_member(chat.presence_topic(r.id), who, "/chat")
	hub.kick_member(chat.typing_topic(r.id), who, "/chat")
}

// A moderator's delete, in a room they moderate: to a tombstone, published as an edit is.
@(private)
remove_message :: proc(req: ^web.Request, res: ^web.Response) {
	msg, r, ok := message_of(req, res)
	if !ok { return }
	if !chat.may_moderate(r, web.viewer(req)) {
		web.respond_html(res, html.toast("error", "Private rooms and DMs are moderated through reports.", true), .Forbidden)
		return
	}
	reason, rok := web.prompt_reason(req, res)
	if !rok { return }
	if err := purge(msg.blob, actor(), reason); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	op := changing(req, res, msg, r, "", true)
	if !chat.remove(op, actor(), reason, "chat.remove") { unqueued(req, op) }
}

// An image out of everywhere, and the open pages told, as an edit tells them.
@(private)
purge :: proc(sha: string, a: chat.Actor, reason: string) -> m.Error {
	if sha == "" { return .None }
	changed := make([dynamic]m.Message, context.temp_allocator)
	if err := chat.purge_image(sha, a, reason, &changed); err != .None { return err }
	for msg in changed {
		if r, err := chat.room_by_id(msg.room); err == .None {
			hub.publish(chat.room_topic(msg.room), chat_views.one(msg.room, r.slug, msg), msg.id)
		}
	}
	return .None
}

// Any reader's report of someone else's message, with a copy of it for the moderators.
@(private)
report_message :: proc(req: ^web.Request, res: ^web.Response) {
	msg, _, ok := message_of(req, res)
	if !ok { return }
	v := web.viewer(req)
	if msg.author == v.id || msg.gone {
		web.respond_html(res, html.toast("error", "There is nothing to report there.", true), .Unprocessable_Content)
		return
	}
	reason, rok := web.prompt_reason(req, res)
	if !rok { return }
	if allowed, retry := web.limit_hit(&reporting, v.id); !allowed {
		web.respond_limited(res, retry, html.toast("error", SLOW_DOWN, false))
		return
	}
	if _, err := chat.report(msg, v, reason); err == .Constraint {
		web.respond_html(res, html.toast("error", "Too many reports are open right now.", true), .Unprocessable_Content)
		return
	} else if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.respond_html(res, html.toast("ok", "Reported: a moderator will look at it.", true))
}

@(private)
reports_page :: proc(req: ^web.Request, res: ^web.Response) {
	list := make([dynamic]m.Report, context.temp_allocator)
	if err := chat.reports(&list); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	rows := make([]chat_views.Report_Row, len(list), context.temp_allocator)
	for rep, i in list {
		rows[i].report = rep
		rows[i].room, _ = chat.room_by_id(rep.room)
	}
	web.render_page(req, res, "Reports", "/chat", "Reported messages, for the moderators.", chat_views.reports_page(rows))
}

// An open report, and the moderator's reason for closing it.
@(private)
resolving :: proc(req: ^web.Request, res: ^web.Response) -> (rep: m.Report, reason: string, ok: bool) {
	id, idok := web.parse_id(req.url_params[0])
	err: m.Error
	if !idok { err = .Not_Found } else { rep, err = chat.report_of(id) }
	if err == .None && rep.resolved != 0 { err = .Not_Found }
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	reason, ok = web.prompt_reason(req, res)
	return
}

// Removes the reported message, whatever its room (a moderator acts on a private room's or a DM's
// through its report alone), and closes the report.
@(private)
report_remove :: proc(req: ^web.Request, res: ^web.Response) {
	rep, reason, ok := resolving(req, res)
	if !ok { return }
	a := actor()
	if err := purge(rep.blob, a, reason); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	msg, merr := chat.message(rep.msg)
	if merr != .None || msg.gone { // already gone: there's only the report to close
		if err := chat.resolve(rep, a, "removed", reason); err != .None {
			web.respond_store_error(req, res, err)
			return
		}
		refresh(res)
		return
	}
	r, _ := chat.room_by_id(msg.room)
	op := changing(req, res, msg, r, "", true)
	op.refresh = true
	op.closes = rep.id // once it's gone, so a failure can't leave it live and the report closed
	if !chat.remove(op, a, reason, "chat.remove") { unqueued(req, op) }
}

@(private)
report_dismiss :: proc(req: ^web.Request, res: ^web.Response) {
	rep, reason, ok := resolving(req, res)
	if !ok { return }
	if err := chat.resolve(rep, actor(), "dismissed", reason); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	refresh(res)
}

// How many reports wait, for a moderator's rooms page; -1 for anyone else.
@(private)
open_reports :: proc(v: authz.Viewer) -> int {
	return chat.open_reports() if authz.can(v, .Chat_Moderate) else -1
}

// ---- the hub's hooks ---------------------------------------------------------------------------

// A topic's key names a room the viewer may read: any other id would keep a presence map and
// a hub ring for good (M2-05), and a private room's or a DM's is its members' alone.
@(private)
room_readable :: proc(key: string, v: authz.Viewer) -> bool {
	id, ok := web.parse_id(key)
	if !ok || fmt.tprintf("%d", id) != key { return false } // one spelling: a kick matches topics by name
	r, err := chat.room_by_id(id)
	return err == .None && chat.may_read(r, v)
}

// A page's #live opened or closed on chat.presence:<room>.
@(private)
watch_room :: proc(key: string, v: authz.Viewer, open: bool) {
	room, ok := web.parse_id(key)
	if !ok || v.id == 0 { return }
	if !open {
		chat.leave(room, v.id)
		return
	}
	if c, show := chat.join(room, v.id, v.name); show { publish_presence(c) }
}

// What is past its room kind's age goes (§14.1): the cap is the post's own to keep.
@(private)
sweep_old :: proc() {
	removed, err := chat.sweep()
	if err != .None {
		workers.fail("the sweep stopped: %v", err)
		return
	}
	if removed > 0 { workers.log("let %d messages go", removed) }
}

@(private)
sweep_presence :: proc() {
	changes := make([dynamic]chat.Presence_Change, context.temp_allocator)
	chat.sweep_presence(&changes)
	for c in changes { publish_presence(c) }
}

@(private)
publish_presence :: proc(c: chat.Presence_Change) {
	buf: [24]byte
	hub.publish(chat.presence_topic(c.room), chat_views.presence(c), 0, strconv.write_uint(buf[:], c.who, 10))
}

// The keyset replay of a persisted room (D13): what came after the page's newest.
@(private)
replay_room :: proc(key: string, after: i64, out: ^[dynamic]hub.Replay_Item) -> bool {
	room, ok := web.parse_id(key)
	if !ok { return false }
	r, err := chat.room_by_id(room)
	if err != .None { return false }
	msgs := make([dynamic]m.Message, 0, 32, context.temp_allocator)
	// Not reached: the room let go of messages after the page's newest, and a replay would
	// skip them unseen; false resyncs, which refetches the log (M2-31).
	reached: bool
	reached, err = chat.after(room, after, &msgs)
	if err != .None || !reached || len(msgs) > 200 { return false }
	for msg in msgs { append(out, hub.Replay_Item{msg.id, chat_views.one(room, r.slug, msg)}) }
	return true
}

@(private)
escaped :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.esc(&b, s)
	return strings.to_string(b)
}
