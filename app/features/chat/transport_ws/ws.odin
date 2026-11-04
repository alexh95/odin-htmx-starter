package chat_transport_ws

// ---- chat over a WebSocket: transport A, the default (PLAN §14.1) --------------------------
//
// The room pane is the socket (hx-ws:connect) and the composer sends on it (hx-ws:send,
// JSON in). As each (re)connect opens, the page sends the room's version it has seen
// (#ver-<room>'s form, on hx-ws's after:connection; hx-ws keeps the URL it first read),
// and gets what changed since, or the room's last SNAPSHOT replacing its log when the
// room let some of that go (M2-31); then everything the room's topic carries, upserted.
// A frame is posted the way a form's POST is, by chat_web (`post`), which this package
// can't import.

import "base:runtime"
import "core:fmt"
import "core:strings"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/stream"
import "../../../platform/web"
import chat ".."
import m "../models"
import chat_views "../views"

NAME :: "ws"

EXTS :: web.Exts{.Ws}

// §17.5: frames a second per connection, then 1008.
MAX_RATE :: 20

Socket :: struct {
	conn: ^stream.Conn,
	sub:  ^hub.Sub,
	room: m.Room,       // its id, slug and name, on the heap: a frame re-reads the rest
	who:  authz.Viewer, // name on the heap
	// The page's version is answered once: a reconnect is a new socket, and a version on
	// every frame would buy a snapshot render each (M3-02).
	caught_up: bool,
}

// Set by chat_web at init: a frame's body, posted (or refused back down the socket).
post: proc(s: ^Socket, body: string)

wiring :: proc(r: m.Room) -> chat_views.Wiring {
	b := strings.builder_make(context.temp_allocator)
	html_esc(&b, ` hx-ws:connect="/chat/r/`, r.slug, `/ws"`)
	hello := fmt.tprintf(` hx-ws:send hx-trigger="htmx:ws:after:connection from:#pane-%d"`, r.id)
	return {pane = strings.to_string(b), composer = ` hx-ws:send`, version = hello}
}

// GET /chat/r/<slug>/ws.
socket :: proc(req: ^web.Request, res: ^web.Response) {
	r, err := chat.room_for(req.url_params[0], web.viewer(req))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	c, uerr := stream.ws_upgrade(req, res, on_message, on_close, max_rate = MAX_RATE)
	if uerr != .None { return }
	v := web.viewer(req)
	s := new(Socket, heap())
	s.conn = c
	s.room = {id = r.id, slug = strings.clone(r.slug, heap()), name = strings.clone(r.name, heap()), at = r.at}
	s.who = {id = v.id, role = v.role, name = strings.clone(v.name, heap())}
	c.user = s
	// Subscribed before the page's version arrives: a message between the two arrives
	// twice rather than never, and upsert keeps one.
	s.sub = hub.subscribe(c, {chat.room_topic(r.id)}, v)
}

// The page's first frame, its version: what changed since, or the snapshot replacing
// the log when the room let some of it go. A version that doesn't parse gets the
// snapshot upserted, as every connect once did.
@(private)
catch_up :: proc(s: ^Socket, ver: string) {
	msgs := make([dynamic]m.Message, 0, chat.SNAPSHOT, context.temp_allocator)
	whole := false
	err: m.Error
	if since, ok := web.parse_digits(ver); ok {
		reached: bool
		_, reached, err = chat.changed(s.room.id, i64(since), &msgs)
		if err == .None && !reached {
			clear(&msgs)
			err = chat.recent(s.room.id, &msgs)
			whole = true
		}
	} else {
		err = chat.recent(s.room.id, &msgs)
	}
	if err != .None || len(msgs) == 0 { return }
	html, _ := chat_views.snapshot(s.room.id, s.room.slug, msgs[:], stream.backlog_budget(), whole)
	stream.ws_send_text(s.conn, html)
}

// Writes `html` (a refusal, a toast) to this socket alone.
send :: proc(s: ^Socket, html: string) {
	stream.ws_send_text(s.conn, html)
}

@(private)
on_message :: proc(c: ^stream.Conn, text: bool, data: []byte) {
	if !text { return }
	if ver, _ := stream.ws_field(data, "ver"); ver != "" {
		s := (^Socket)(c.user)
		if !s.caught_up {
			s.caught_up = true
			catch_up(s, ver)
		}
		return
	}
	body, ok := stream.ws_field(data, "body")
	if !ok {
		// Not hx-ws's JSON (or nested past stream.WS_JSON_DEPTH), so the member hears why it went nowhere.
		send((^Socket)(c.user), html.toast("error", "That message couldn't be read.", true))
		return
	}
	if post != nil { post((^Socket)(c.user), body) }
}

@(private)
on_close :: proc(c: ^stream.Conn) {
	s := (^Socket)(c.user)
	if s == nil { return }
	hub.unsubscribe(s.sub)
	delete(s.room.slug, heap())
	delete(s.room.name, heap())
	delete(s.who.name, heap())
	free(s, heap())
}

@(private)
html_esc :: proc(b: ^strings.Builder, before, value, after: string) {
	strings.write_string(b, before)
	chat_views.esc(b, value)
	strings.write_string(b, after)
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }
