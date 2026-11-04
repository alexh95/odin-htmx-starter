package chat_transport_multipart

// ---- chat over one long multipart response: transport D (PLAN §14.1) -----------------------
//
// The pane holds hx-multipart:connect; each message is a part whose HX-Part-ID is its
// id (the hub writes the rowid it was published with), so a reconnect's
// HX-Last-Part-ID asks for what came after it, and the first connect for the room's
// last SNAPSHOT. The composer POSTs, as SSE's does.

import "core:strconv"
import "core:strings"

import "../../../platform/hub"
import "../../../platform/stream"
import "../../../platform/web"
import chat ".."
import m "../models"
import chat_views "../views"

NAME :: "multipart"

EXTS :: web.Exts{.Multipart, .Pending}

wiring :: proc(r: m.Room) -> chat_views.Wiring {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, ` hx-multipart:connect="/chat/r/`)
	chat_views.esc(&b, r.slug)
	// Uncached: Firefox holds a second fetch of a URL until the first one's response has ended
	// (its cache entry), whatever that response's Cache-Control, so a member's second tab got no
	// parts at all while the first stayed open. The SSE and the hub's #live differ by their cursor.
	strings.write_string(&b, `/parts" hx-config='{"cache":"no-store"}'`)
	return {pane = strings.to_string(b), composer = chat_views.post_composer(r)}
}

// GET /chat/r/<slug>/parts.
parts :: proc(req: ^web.Request, res: ^web.Response) {
	web.impl(res, "chat.transport", "multipart")
	r, err := chat.room_for(req.url_params[0], web.viewer(req))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	last, resumed := web.parse_digits(web.header(req, "hx-last-part-id"))
	c := stream.multipart_begin(res, .Mixed, nil, proc(c: ^stream.Conn) { hub.unsubscribe((^hub.Sub)(c.user)) })
	if c == nil { return } // admission answered 503 or 429
	// Subscribed first, as the socket is: a message between the two comes twice, never not.
	c.user = hub.subscribe(c, {chat.room_topic(r.id)}, web.viewer(req))
	msgs := make([dynamic]m.Message, 0, chat.SNAPSHOT, context.temp_allocator)
	reached := true
	if resumed { reached, err = chat.after(r.id, i64(last), &msgs) } else { err = chat.recent(r.id, &msgs) }
	if err != .None || len(msgs) == 0 { return }
	// A resume the room can't serve whole replaces the log: upserted, it looked continuous
	// across what the room had let go in between (M2-31).
	html, newest := chat_views.snapshot(r.id, r.slug, msgs[:], stream.backlog_budget(), whole = !reached)
	buf: [24]byte
	stream.multipart_part(c, html, {{"HX-Part-ID", strconv.write_int(buf[:], newest, 10)}})
}
