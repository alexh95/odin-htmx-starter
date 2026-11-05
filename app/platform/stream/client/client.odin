package stream_client

// ---- platform/stream/client: one non-blocking HTTP, SSE and WebSocket client (L3) ----------
//
// PLAN §8.2, D12: the one definition of the streaming client, for the bot's
// llama binding (M7), the Pi's terminal agent (M11) and tools/streamload. A Conn
// lives on the event loop of the thread that opens it (core:nbio), never
// blocks, and reports through callbacks on that thread:
//
//   open(c, endpoint, request, .Sse)   on_sse per event       (/events, a llama stream)
//   open(c, endpoint, request, .Ws)    on_ws per message      (a room, the terminal)
//   open(c, endpoint, request, .Body)  on_body per decoded read, chunked or not
//
// on_open follows the response head (its status in c.head), on_close the end,
// with why. Plain HTTP only: the LAN and loopback need no TLS (§14.3), and a
// proxy in front terminates it. The parsers are parse.odin's.

import "base:runtime"
import "core:nbio"
import "core:net"
import "core:strings"
import "core:time"

Mode :: enum u8 {
	Body, // a plain response: its decoded body to on_body
	Sse,  // a text/event-stream body: each event to on_sse
	Ws,   // an upgrade: each message to on_ws, and ws_send
}

End :: enum u8 {
	Done,        // the body ended, or a close frame came
	Dial_Failed,
	Refused,     // the head said no (a status other than 2xx, or 101 for .Ws)
	Bad_Response,
	Peer_Closed,
	Send_Failed,
	Closed,      // close() was called
}

Conn :: struct {
	user:     rawptr,
	on_open:  proc(c: ^Conn),
	on_sse:   proc(c: ^Conn, ev: Sse_Event),
	on_ws:    proc(c: ^Conn, text: bool, data: []byte),
	on_body:  proc(c: ^Conn, data: []byte),
	on_close: proc(c: ^Conn, why: End),

	mode:     Mode,
	head:     Head,
	code:     u16, // the server's close code, when a socket ends with one
	socket:   net.TCP_Socket,
	state:    enum u8 {Idle, Dialing, Head, Body, Gone},
	key:      [24]byte,
	key_len:  int,
	inbuf:    [dynamic]byte, // read, not yet parsed
	body:     [dynamic]byte, // a chunked body's decoded bytes, per read
	chunked:  Chunked,
	sse:      Sse,
	frag:     [dynamic]byte,
	frag_op:  u8,
	got:      int, // body bytes of a Content-Length response so far
	out:      [dynamic]byte, // waiting for the socket
	flight:   [dynamic]byte,
	send_op:  ^nbio.Operation,
	recv_op:  ^nbio.Operation,
	dial_op:  ^nbio.Operation,
	recv_buf: [8192]byte,
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }

// A request's bytes: `extra` is header lines, each ending in CRLF. A .Ws open
// adds the upgrade headers and its key itself.
request :: proc(method, host, path: string, extra := "", body := "", allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, method)
	strings.write_byte(&b, ' ')
	strings.write_string(&b, path)
	strings.write_string(&b, " HTTP/1.1\r\nHost: ")
	strings.write_string(&b, host)
	strings.write_string(&b, "\r\n")
	strings.write_string(&b, extra)
	if body != "" || method == "POST" {
		strings.write_string(&b, "Content-Length: ")
		strings.write_int(&b, len(body))
		strings.write_string(&b, "\r\n")
	}
	strings.write_string(&b, "\r\n")
	strings.write_string(&b, body)
	return strings.to_string(b)
}

// Dials `ep` on this thread's loop and sends `req` (from `request`, or the
// caller's own bytes). The Conn's callbacks and user are set beforehand; it
// must stay put until on_close.
open :: proc(c: ^Conn, ep: net.Endpoint, req: string, mode: Mode, timeout := 5 * time.Second) {
	c.mode, c.state, c.head, c.code = mode, .Dialing, {}, 0
	c.chunked, c.got, c.frag_op = {}, 0, 0
	for d in ([?]^[dynamic]byte{&c.inbuf, &c.body, &c.frag, &c.out, &c.flight, &c.sse.line, &c.sse.data, &c.sse.event, &c.sse.id}) {
		if d.allocator.procedure == nil { d.allocator = heap() }
		clear(d)
	}
	c.sse.has_data, c.sse.after_cr, c.sse.over = false, false, false
	if mode == .Ws {
		k := ws_key(&c.key)
		c.key_len = len(k)
		end := strings.index(req, "\r\n\r\n")
		assert(end > 0, "stream_client.open: a request ends its head with a blank line")
		append(&c.out, req[:end + 2])
		append(&c.out, "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ")
		append(&c.out, k)
		append(&c.out, "\r\n\r\n")
	} else {
		append(&c.out, req)
	}
	c.dial_op = nbio.dial_poly(ep, c, proc(op: ^nbio.Operation, c: ^Conn) {
		c.dial_op = nil
		if c.state == .Gone { return }
		if op.dial.err != nil {
			finish(c, .Dial_Failed)
			return
		}
		c.socket = op.dial.socket
		c.state = .Head
		kick(c)
		read(c)
	}, timeout)
}

// Sends one WebSocket message; false unless the socket is open.
ws_send :: proc(c: ^Conn, text: bool, data: []byte) -> bool {
	if c.mode != .Ws || c.state != .Body { return false }
	ws_frame(&c.out, 0x1 if text else 0x2, data)
	kick(c)
	return true
}

ws_send_text :: proc(c: ^Conn, s: string) -> bool { return ws_send(c, true, transmute([]byte)s) }

// Hangs up at once: on_close follows with .Closed.
close :: proc(c: ^Conn) {
	if c.state == .Gone || c.state == .Idle { return }
	finish(c, .Closed)
}

// Frees what the Conn holds; call it after on_close, before reusing or freeing the Conn.
destroy :: proc(c: ^Conn) {
	delete(c.inbuf)
	delete(c.body)
	delete(c.frag)
	delete(c.out)
	delete(c.flight)
	sse_destroy(&c.sse)
}

// ---- the socket ------------------------------------------------------------------------

@(private)
kick :: proc(c: ^Conn) {
	if c.state == .Gone || c.state == .Dialing || c.send_op != nil || len(c.out) == 0 { return }
	c.out, c.flight = c.flight, c.out
	c.send_op = nbio.send_poly(c.socket, {c.flight[:]}, c, proc(op: ^nbio.Operation, c: ^Conn) {
		c.send_op = nil
		if c.state == .Gone { return }
		if op.send.err != nil {
			finish(c, .Send_Failed)
			return
		}
		clear(&c.flight)
		kick(c)
	})
}

@(private)
read :: proc(c: ^Conn) {
	c.recv_op = nbio.recv_poly(c.socket, {c.recv_buf[:]}, c, proc(op: ^nbio.Operation, c: ^Conn) {
		c.recv_op = nil
		if c.state == .Gone { return }
		if op.recv.err != nil || op.recv.received == 0 {
			// A close-delimited body ends here; anything else was cut off.
			finish(c, .Done if c.state == .Body && !c.head.chunked && c.head.length < 0 && c.mode != .Ws else .Peer_Closed)
			return
		}
		append(&c.inbuf, ..c.recv_buf[:op.recv.received])
		feed(c)
		if c.state != .Gone { read(c) }
	})
}

@(private)
feed :: proc(c: ^Conn) {
	if c.state == .Head {
		n := head_end(c.inbuf[:])
		if n == 0 { return }
		h, ok := parse_head(string(c.inbuf[:max(n, 0)]))
		switch {
		case n < 0 || !ok:
			finish(c, .Bad_Response)
			return
		case c.mode == .Ws && (h.status != 101 || !ws_accept_ok(string(c.key[:c.key_len]), h.accept)):
			c.head = h
			finish(c, .Refused)
			return
		case c.mode != .Ws && (h.status < 200 || h.status > 299):
			c.head = h
			finish(c, .Refused)
			return
		}
		c.head = h
		c.head.accept, c.head.ctype = "", "" // they point into inbuf, which moves on
		remove_range(&c.inbuf, 0, n)
		c.state = .Body
		if c.on_open != nil { c.on_open(c) }
		if c.state == .Gone { return }
		// No body follows a 204 or a 304, whatever the head says (RFC 9110 §15.3.5, §15.4.5).
		if h.status == 204 || h.status == 304 {
			finish(c, .Done)
			return
		}
	}
	switch c.mode {
	case .Ws:
		feed_ws(c)
	case .Body, .Sse:
		data := c.inbuf[:]
		done := false
		if c.head.chunked {
			clear(&c.body)
			_, d, bad := chunked_feed(&c.chunked, data, &c.body)
			if bad {
				finish(c, .Bad_Response)
				return
			}
			data, done = c.body[:], d
		} else if c.head.length >= 0 {
			data = data[:min(len(data), c.head.length - c.got)]
			c.got += len(data)
			done = c.got >= c.head.length
		}
		deliver(c, data)
		clear(&c.inbuf)
		if c.sse.over {
			finish(c, .Bad_Response)
			return
		}
		if done && c.state != .Gone { finish(c, .Done) }
	}
}

@(private)
deliver :: proc(c: ^Conn, data: []byte) {
	if len(data) == 0 { return }
	if c.mode == .Sse {
		sse_feed(&c.sse, data, c, proc(user: rawptr, ev: Sse_Event) {
			c := (^Conn)(user)
			if c.state != .Gone && c.on_sse != nil { c.on_sse(c, ev) }
		})
	} else if c.on_body != nil {
		c.on_body(c, data)
	}
}

@(private)
feed_ws :: proc(c: ^Conn) {
	used := 0
	for c.state == .Body {
		f, n, bad := ws_read(c.inbuf[used:])
		if bad {
			finish(c, .Bad_Response)
			return
		}
		if n == 0 { break }
		used += n
		switch f.op {
		case 0x0:
			append(&c.frag, ..f.payload)
			if f.fin { message(c, c.frag_op == 0x1, c.frag[:]) }
		case 0x1, 0x2:
			if f.fin { message(c, f.op == 0x1, f.payload) } else {
				c.frag_op = f.op
				clear(&c.frag)
				append(&c.frag, ..f.payload)
			}
		case 0x8:
			c.code = f.code
			finish(c, .Done)
		case 0x9:
			ws_frame(&c.out, 0xA, f.payload)
			kick(c)
		}
	}
	if c.state != .Gone { remove_range(&c.inbuf, 0, used) }
}

@(private)
message :: proc(c: ^Conn, text: bool, data: []byte) {
	if c.on_ws != nil { c.on_ws(c, text, data) }
}

@(private)
finish :: proc(c: ^Conn, why: End) {
	if c.state == .Gone { return }
	dialing := c.state == .Dialing
	c.state = .Gone
	for op in ([?]^^nbio.Operation{&c.dial_op, &c.send_op, &c.recv_op}) {
		if op^ != nil { nbio.remove(op^); op^ = nil }
	}
	if !dialing { nbio.close(c.socket) }
	if c.on_close != nil { c.on_close(c, why) }
}
