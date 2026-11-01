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

import "../../../platform/authz"
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
EXTS :: chat_transport_ws.EXTS + chat_transport_sse.EXTS + chat_transport_poll.EXTS + chat_transport_multipart.EXTS + web.Exts{.Upsert}

// A message's body is 2,000 runes; URL-encoded, a rune can take 12 bytes.
POST_CAP :: 32 * 1024

ROUTES := [?]web.Route {
	{.Get, "/chat", index, .Public, {.Private}, 0}, // the rooms, or the LAN notice
	{.Post, "/chat/rooms", create_room, .Chat_Create_Room, {.Fragment}, 1024},
	{.Post, "/chat/transport", set_transport, .Chat_Read, {.Fragment}, 256},
	{.Get, "/chat/r/([%w%-]+)", room_page, .Chat_Read, {.Private}, 0},
	{.Post, "/chat/r/([%w%-]+)", post_message, .Chat_Post, {.Fragment}, POST_CAP},
	{.Post, "/chat/r/([%w%-]+)/typing", typing, .Chat_Post, {.Fragment}, POST_CAP},
	{.Post, "/chat/r/([%w%-]+)/read", read, .Chat_Read, {.Fragment}, 0},
	{.Get, "/chat/r/([%w%-]+)/ws", chat_transport_ws.socket, .Chat_Read, {.Stream, .Fragment}, 0},
	{.Get, "/chat/r/([%w%-]+)/since", chat_transport_poll.since, .Chat_Read, {.Fragment}, 0},
	{.Get, "/chat/r/([%w%-]+)/parts", chat_transport_multipart.parts, .Chat_Read, {.Stream, .Fragment}, 0},
	{.Get, "/chat/m/(%d+)/menu", menu, .Chat_Read, {.Fragment}, 0},
	{.Get, "/chat/m/(%d+)/edit", edit_form, .Chat_Post, {.Fragment}, 0},
	{.Post, "/chat/m/(%d+)/edit", edit, .Chat_Post, {.Fragment}, POST_CAP},
	{.Post, "/chat/m/(%d+)/delete", delete_message, .Chat_Post, {.Fragment}, 0},
}

// chat.room:<id>: a room's messages (the SSE transport's on #live, the socket's and
// multipart's on their own streams). chat.presence:<id> and chat.typing:<id> ride
// every room page's #live, keyed per member (.Latest); presence learns who is there
// from those streams opening and closing (`watch`).
TOPICS := [?]hub.Topic {
	{family = "chat.room", policy = .Queue, persisted = chat.PERSISTED, perm = .Chat_Read, allow = room_exists, replay = replay_room},
	{family = "chat.presence", policy = .Latest, perm = .Chat_Read, allow = room_exists, watch = watch_room},
	{family = "chat.typing", policy = .Latest, ring = 64, perm = .Chat_Read, allow = room_exists},
}

JOBS := [?]workers.Job {
	{"chat.presence", 5 * time.Second, sweep_presence, nil},
}

// §17.5: posts 5 per 10 s per member (a fixed window: up to 10 across a boundary),
// typing 1 per 2 s.
@(private) posts := web.Limit{n = 5, window = 10 * time.Second}
@(private) typists := web.Limit{n = 1, window = 2 * time.Second}

@(private)
SLOW_DOWN :: "Slow down: at most 5 messages in 10 seconds."

COOKIE :: "chat_transport"

// At boot, before app.check: the domain's env rows and store, and the socket's post path.
init :: proc() {
	chat.init()
	chat_transport_ws.post = socket_post
}

// The transport a request's page uses: `?transport=` (the specs'), the member's
// setting (a cookie), else CHAT_TRANSPORT.
transport :: proc(req: ^web.Request) -> chat.Transport {
	if t, ok := chat.transport_named(web.query_get(req, "transport")); ok { return t }
	if t, ok := chat.transport_named(web.cookie(req, COOKIE)); ok { return t }
	return chat.default_transport()
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
	if err := chat.rooms(&all); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	rows := make([]chat_views.Room_Row, len(all), context.temp_allocator)
	for r, i in all { rows[i] = {r, chat.unread(r.id, v.id)} }
	web.render_page(req, res, "Chat", "/chat", "The rooms on the LAN.", chat_views.index_page(rows, transport(req), authz.can(v, .Chat_Create_Room)))
}

@(private)
room_page :: proc(req: ^web.Request, res: ^web.Response) {
	r, err := chat.room(req.url_params[0])
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	v := web.viewer(req)
	chat.seen(v.id, v.name)
	t := transport(req)
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
	case .Sse:
		wiring = chat_transport_sse.wiring(r)
		append(&live, chat_transport_sse.live_topic(r, msgs[len(msgs) - 1].id if len(msgs) > 0 else 0))
	case .Poll:
		wiring = chat_transport_poll.wiring(r, ver)
	case .Multipart:
		wiring = chat_transport_multipart.wiring(r)
	}
	web.render_page(req, res, fmt.tprintf("#%s", r.name), "/chat", "A chat room on the LAN.",
		chat_views.room_page(r, msgs[:], ver, here[:], v.id, t, wiring), live = live[:])
}

// The Connection setting: a cookie for a year, then back to the rooms.
@(private)
set_transport :: proc(req: ^web.Request, res: ^web.Response) {
	t, ok := chat.transport_named(web.form(req)["transport"])
	if !ok {
		web.respond_status(res, .Bad_Request)
		return
	}
	web.set_header(res, "set-cookie", fmt.tprintf("%s=%s; Path=/chat; Max-Age=31536000; SameSite=Lax; HttpOnly%s", COOKIE, chat.TRANSPORTS[t].name, "; Secure" if web.ctx().https else ""))
	web.set_header(res, "location", "/chat")
	web.respond_status(res, .See_Other)
}

@(private)
create_room :: proc(req: ^web.Request, res: ^web.Response) {
	name, slug, problem := chat.check_room(web.form(req)["name"])
	if problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	r, err := chat.create_room(slug, name)
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

// ---- posting --------------------------------------------------------------------------------

// What a post carries to its continuation.
@(private)
Posting :: struct {
	using post: m.Post,
	deferred:   web.Deferred,
	http:       bool, // a form's POST, answered with the message; a socket's is answered by the hub
	slug:       string,
	room_name:  string,
}

@(private)
post_message :: proc(req: ^web.Request, res: ^web.Response) {
	r, err := chat.room(req.url_params[0])
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	v := web.viewer(req)
	body, problem := chat.check_body(web.form(req)["body"])
	if problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	if ok, retry := web.limit_hit(&posts, v.id); !ok {
		web.respond_limited(res, retry, html.toast("error", SLOW_DOWN, false))
		return
	}
	op := posting(v, r, body)
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
socket_post :: proc(s: ^chat_transport_ws.Socket, raw: string) {
	if !authz.can(s.who, .Chat_Post) { return }
	body, problem := chat.check_body(raw)
	if problem != "" {
		chat_transport_ws.send(s, fmt.tprintf(`<p hx-swap-oob="innerHTML:#err-%d">%s</p>`, s.room.id, escaped(problem)))
		return
	}
	if ok, _ := web.limit_hit(&posts, s.who.id); !ok {
		chat_transport_ws.send(s, html.toast("error", SLOW_DOWN, true))
		return
	}
	op := posting(s.who, s.room, body)
	if !chat.post(op) {
		store.free_op(op)
		chat_transport_ws.send(s, html.toast("error", "Chat is busy. Try again in a moment.", true))
	}
}

@(private)
posting :: proc(v: authz.Viewer, r: m.Room, body: string) -> ^Posting {
	// The inputs, and the stored message the store answers with in the same arena.
	op := store.new_op(Posting, 2 * (len(body) + len(v.name)) + len(r.slug) + len(r.name))
	a := store.op_allocator(op)
	op.room, op.author = r.id, v.id
	op.name, op.body = strings.clone(v.name, a), strings.clone(body, a)
	op.slug, op.room_name = strings.clone(r.slug, a), strings.clone(r.name, a)
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
	if op.err == .None { announce(op.slug, op.room_name, op.result) }
	if res == nil { return } // a socket's post, or the client left: the message is posted all the same
	if op.err != .None {
		web.respond_store_error(web.request(&op.deferred), res, op.err)
	} else {
		web.respond_html(res, chat_views.one(op.room, op.slug, op.result))
	}
	web.finish(&op.deferred, res)
}

// A new message to the room, the Inbox of whoever it mentions, and the unread counts
// of everyone who has read the room (theirs on every page, through notify.user).
@(private)
announce :: proc(slug, room_name: string, msg: m.Message) {
	hub.publish(chat.room_topic(msg.room), chat_views.one(msg.room, slug, msg), msg.id)

	who := make([dynamic]u64, 0, 8, context.temp_allocator)
	chat.mentioned(msg.body, msg.author, &who)
	if len(who) > 0 {
		ref := fmt.tprintf("/chat/r/%s#m-%d", slug, msg.id)
		line := chat_views.mention_line(msg.name, room_name, msg.body)
		for id in who { notify_web.send(id, "chat.mention", ref, line) }
	}

	clear(&who)
	chat.readers(msg.room, &who)
	for id in who {
		if id == msg.author { continue }
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
	web.respond_html(res, chat_views.menu(msg, r.slug, chat.may_change(msg, web.viewer(req).id)))
}

@(private)
edit_form :: proc(req: ^web.Request, res: ^web.Response) {
	msg, _, ok := message_of(req, res)
	if !ok { return }
	if !chat.may_change(msg, web.viewer(req).id) {
		web.respond_html(res, html.field_msg(false, "Only your own messages, for 10 minutes."), .Forbidden)
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
}

@(private)
edit :: proc(req: ^web.Request, res: ^web.Response) {
	msg, r, ok := message_of(req, res)
	if !ok { return }
	typed := web.form(req)["body"]
	body, problem := chat.check_body(typed)
	if problem != "" {
		web.respond_html(res, chat_views.edit_form(msg.id, typed, problem), .Unprocessable_Content)
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
	v := web.viewer(req)
	op := store.new_op(Changing, 3 * len(body) + 2 * len(msg.name) + len(r.slug) + len(r.name))
	a := store.op_allocator(op)
	op.id, op.author, op.delete = msg.id, v.id, del
	op.body, op.typed = strings.clone(body, a), strings.clone(body, a)
	op.slug, op.room_name = strings.clone(r.slug, a), strings.clone(r.name, a)
	op.done = changed
	web.defer_response(req, res, &op.deferred)
	if !chat.change(op) {
		if rr := web.resume(&op.deferred); rr != nil {
			web.respond_store_error(req, rr, .Busy)
			web.finish(&op.deferred, rr)
		}
		store.free_op(op)
	}
}

@(private)
changed :: proc(o: ^store.Op) {
	op := (^Changing)(o)
	defer store.free_op(op)
	res := web.resume(&op.deferred) // first, as posted's
	if op.err == .None {
		hub.publish(chat.room_topic(op.result.room), chat_views.one(op.result.room, op.slug, op.result), op.result.id)
	}
	if res == nil { return }
	switch op.err {
	case .None:
		web.respond_html(res, chat_views.one(op.result.room, op.slug, op.result))
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
	r, err := chat.room(req.url_params[0])
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	v := web.viewer(req)
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
	r, err := chat.room(req.url_params[0])
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

// ---- the hub's hooks ---------------------------------------------------------------------------

// A topic's key names a room that exists: any other id would keep a presence map and a
// hub ring for good (M2-05).
@(private)
room_exists :: proc(key: string, _: authz.Viewer) -> bool {
	id, ok := web.parse_id(key)
	if !ok { return false }
	_, err := chat.room_by_id(id)
	return err == .None
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
