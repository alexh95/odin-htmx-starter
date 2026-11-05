package stream_client

// The client's parsers, apart from the socket (unit-tested): the response head,
// a chunked body, SSE events and the server's WebSocket frames. Each is
// incremental: it takes whatever bytes a read brought and keeps its place.

import "core:crypto"
import "core:crypto/legacy/sha1"
import "core:encoding/base64"
import "core:strconv"
import "core:strings"

// ---- the response head ----------------------------------------------------------

Head :: struct {
	status:  int,
	chunked: bool,
	length:  int, // Content-Length, or -1
	accept:  string, // Sec-WebSocket-Accept, in the head's own bytes
	ctype:   string, // Content-Type, likewise
}

MAX_HEAD :: 16 * 1024

// The head's length (through the blank line) once it is all in `b`; 0 until
// then, -1 for a malformed or oversized one.
head_end :: proc(b: []byte) -> int {
	for i in 3 ..< len(b) {
		if b[i] == '\n' && b[i - 1] == '\r' && b[i - 2] == '\n' && b[i - 3] == '\r' { return i + 1 }
	}
	return -1 if len(b) > MAX_HEAD else 0
}

parse_head :: proc(text: string) -> (h: Head, ok: bool) {
	h.length = -1
	rest := text
	line, _ := strings.split_iterator(&rest, "\r\n")
	if !strings.has_prefix(line, "HTTP/1.") || len(line) < 12 { return }
	h.status = strconv.parse_int(line[9:12], 10) or_return
	for l in strings.split_iterator(&rest, "\r\n") {
		colon := strings.index_byte(l, ':')
		if colon <= 0 { continue }
		name, value := l[:colon], strings.trim_space(l[colon + 1:])
		switch {
		case strings.equal_fold(name, "transfer-encoding"):
			h.chunked = strings.contains(strings.to_lower(value, context.temp_allocator), "chunked")
		case strings.equal_fold(name, "content-length"):
			h.length = strconv.parse_int(value, 10) or_return
		case strings.equal_fold(name, "sec-websocket-accept"):
			h.accept = value
		case strings.equal_fold(name, "content-type"):
			h.ctype = value
		}
	}
	return h, true
}

// ---- a chunked body ----------------------------------------------------------------

Chunked :: struct {
	state: enum u8 {Size, Ext, Size_LF, Data, Data_CR, Data_LF, Trailer, Trailer_LF, Done},
	left:  int,  // the chunk's bytes still to come, or the size being read
	digits: int,
	blank: bool, // the trailer line being read is empty so far
}

// Feeds raw body bytes, appending the decoded data to `out`. done: the last
// chunk and its trailer are in; bad: the framing is broken. Returns how many
// bytes of `b` it used (all of them, unless done comes first).
chunked_feed :: proc(c: ^Chunked, b: []byte, out: ^[dynamic]byte) -> (used: int, done, bad: bool) {
	i := 0
	for i < len(b) && c.state != .Done {
		ch := b[i]
		switch c.state {
		case .Size:
			switch ch {
			case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
				c.digits += 1
				if c.digits > 15 { return i, false, true }
				c.left = c.left * 16 + hex_value(ch)
			case ';', ' ', '\t':
				c.state = .Ext
			case '\r':
				c.state = .Size_LF
			case:
				return i, false, true
			}
			i += 1
		case .Ext:
			if ch == '\r' { c.state = .Size_LF }
			i += 1
		case .Size_LF:
			if ch != '\n' || c.digits == 0 { return i, false, true }
			c.state, c.blank = (.Trailer if c.left == 0 else .Data), true
			i += 1
		case .Data:
			n := min(c.left, len(b) - i)
			append(out, ..b[i:i + n])
			c.left -= n
			i += n
			if c.left == 0 { c.state = .Data_CR }
		case .Data_CR:
			if ch != '\r' { return i, false, true }
			c.state = .Data_LF
			i += 1
		case .Data_LF:
			if ch != '\n' { return i, false, true }
			c.state, c.left, c.digits = .Size, 0, 0
			i += 1
		case .Trailer:
			if ch == '\r' { c.state = .Trailer_LF } else { c.blank = false }
			i += 1
		case .Trailer_LF:
			if ch != '\n' { return i, false, true }
			i += 1
			if c.blank { c.state = .Done } else { c.state, c.blank = .Trailer, true }
		case .Done:
		}
	}
	return i, c.state == .Done, false
}

@(private)
hex_value :: proc(ch: byte) -> int {
	switch ch {
	case '0' ..= '9': return int(ch - '0')
	case 'a' ..= 'f': return int(ch - 'a') + 10
	case:             return int(ch - 'A') + 10
	}
}

// ---- SSE ---------------------------------------------------------------------------

// One event, valid until the next feed.
Sse_Event :: struct {
	id, event, data: string,
}

Sse :: struct {
	line:     [dynamic]byte,
	data:     [dynamic]byte,
	event:    [dynamic]byte,
	id:       [dynamic]byte,
	has_data: bool,
	after_cr: bool, // the last byte was a CR: an LF next ends nothing new
	max:      int,  // an event's bytes at most; 0 = no cap
	over:     bool, // past `max`: the read stops here
}

sse_destroy :: proc(p: ^Sse) {
	delete(p.line)
	delete(p.data)
	delete(p.event)
	delete(p.id)
}

// Feeds decoded body bytes; `on_event` gets each dispatched event. Lines end at
// CR, LF or CRLF, as hx-sse splits them; a comment line is skipped.
sse_feed :: proc(p: ^Sse, b: []byte, user: rawptr, on_event: proc(user: rawptr, ev: Sse_Event)) {
	for ch in b {
		if ch == '\n' && p.after_cr {
			p.after_cr = false
			continue
		}
		p.after_cr = ch == '\r'
		if ch != '\r' && ch != '\n' {
			if p.max > 0 && len(p.line) + len(p.data) >= p.max {
				p.over = true
				return
			}
			append(&p.line, ch)
			continue
		}
		line := string(p.line[:])
		switch {
		case line == "":
			if p.has_data || len(p.event) > 0 {
				on_event(user, {string(p.id[:]), string(p.event[:]), string(p.data[:])})
			}
			clear(&p.data)
			clear(&p.event)
			p.has_data = false
		case line[0] == ':':
		case:
			name, value := line, ""
			if colon := strings.index_byte(line, ':'); colon >= 0 {
				name, value = line[:colon], line[colon + 1:]
				if len(value) > 0 && value[0] == ' ' { value = value[1:] }
			}
			switch name {
			case "data":
				if p.has_data { append(&p.data, '\n') }
				append(&p.data, value)
				p.has_data = true
			case "event":
				clear(&p.event)
				append(&p.event, value)
			case "id":
				clear(&p.id)
				append(&p.id, value)
			}
		}
		clear(&p.line)
	}
}

// ---- WebSocket, the client's side -----------------------------------------------------

WS_GUID :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

// A fresh Sec-WebSocket-Key in `buf`.
ws_key :: proc(buf: ^[24]byte) -> string {
	raw: [16]byte
	crypto.rand_bytes(raw[:])
	enc := base64.encode(raw[:], allocator = context.temp_allocator)
	copy(buf[:], enc)
	return string(buf[:len(enc)])
}

ws_accept_ok :: proc(key, accept: string) -> bool {
	ctx: sha1.Context
	digest: [sha1.DIGEST_SIZE]byte
	sha1.init(&ctx)
	sha1.update(&ctx, transmute([]byte)key)
	sha1.update(&ctx, transmute([]byte)string(WS_GUID))
	sha1.final(&ctx, digest[:])
	return accept == base64.encode(digest[:], allocator = context.temp_allocator)
}

// One masked client frame with FIN set, appended to `out`.
ws_frame :: proc(out: ^[dynamic]byte, op: u8, payload: []byte) {
	mask: [4]byte
	crypto.rand_bytes(mask[:])
	n := len(payload)
	append(out, 0x80 | op)
	switch {
	case n < 126:   append(out, 0x80 | byte(n))
	case n < 65536: append(out, 0x80 | 126, byte(n >> 8), byte(n))
	case:
		append(out, 0x80 | 127)
		for i := 7; i >= 0; i -= 1 { append(out, byte(u64(n) >> (uint(i) * 8))) }
	}
	append(out, ..mask[:])
	start := len(out)
	append(out, ..payload)
	for i in 0 ..< n { out[start + i] ~= mask[i & 3] }
}

Ws_Frame :: struct {
	fin:     bool,
	op:      u8,
	payload: []byte,
	code:    u16, // a close frame's, 0 when it carries none
}

// Reads one server frame (unmasked) from the front of `b`. n = 0: not all here
// yet; bad: a masked or malformed frame.
ws_read :: proc(b: []byte, max := 16 << 20) -> (f: Ws_Frame, n: int, bad: bool) {
	if len(b) < 2 { return }
	f.fin, f.op = b[0] & 0x80 != 0, b[0] & 0x0F
	if b[1] & 0x80 != 0 || b[0] & 0x70 != 0 { return f, 0, true }
	plen := u64(b[1] & 0x7F)
	pos := 2
	if plen == 126 {
		if len(b) < 4 { return }
		plen, pos = u64(b[2]) << 8 | u64(b[3]), 4
	} else if plen == 127 {
		if len(b) < 10 { return }
		plen = 0
		for i in 0 ..< 8 { plen = plen << 8 | u64(b[2 + i]) }
		pos = 10
	}
	if plen > u64(max) { return f, 0, true }
	total := pos + int(plen)
	if len(b) < total { return }
	f.payload = b[pos:total]
	if f.op == 0x8 && plen >= 2 { f.code = u16(f.payload[0]) << 8 | u16(f.payload[1]) }
	return f, total, false
}
