package escape

// ---- platform/escape: the injection boundary (L1) --------------------------
//
// Every dynamic value reaches a page through one of these: text through esc, a
// URL component through url_encode, a JSON string through json_esc; markup only
// through w. One definition of each: platform/html re-exports them (html.esc …)
// for views, and platform/markdown, which domains call at write time (L2), uses
// them directly. A leaf: core only.

import "core:encoding/base64"
import "core:fmt"
import "core:net"
import "core:strings"

w :: proc(b: ^strings.Builder, s: string) {
	strings.write_string(b, s)
}

// HTML-escapes text content. The only defence against an injected '<' from a
// search box or a contact name, so it is not optional anywhere input is echoed.
// Also correct inside a quoted attribute.
esc :: proc(b: ^strings.Builder, s: string) {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&':  w(b, "&amp;")
		case '<':  w(b, "&lt;")
		case '>':  w(b, "&gt;")
		case '"':  w(b, "&#34;")
		case '\'': w(b, "&#39;")
		case:      strings.write_byte(b, s[i])
		}
	}
}

url_encode :: proc(s: string) -> string {
	return net.percent_encode(s, context.temp_allocator)
}

// A path on this site: never another origin (`//host`, `/\host`, which browsers
// read as `//host`), and no space or control byte. What a redirect's `next` and a
// link a producer hands the Inbox may be.
site_path :: proc(s: string) -> bool {
	if len(s) == 0 || s[0] != '/' || len(s) > 1 && (s[1] == '/' || s[1] == '\\') { return false }
	for c in transmute([]byte)s {
		if c < 0x21 || c == 0x7f { return false }
	}
	return true
}

// A search's snippet is text with these two private-use characters round each hit: FTS5 can't be
// asked to escape, and a store writes no markup.
MARK_ON :: "\uE000"
MARK_OFF :: "\uE001"

// Escapes a snippet and turns its marks to <mark>. A snippet is stored text, so a member can type the
// characters themselves: each opens only when shut and closes only when open, and the end closes,
// so a forged one is at worst a stray highlight, never unbalanced markup.
write_marked :: proc(b: ^strings.Builder, text: string) {
	PREFIX :: "\xEE\x80" // both marks' first two bytes
	open := false
	rest := text
	for {
		i := strings.index(rest, PREFIX)
		if i < 0 || i + 2 >= len(rest) {
			esc(b, rest)
			break
		}
		c := rest[i + 2]
		if c != MARK_ON[2] && c != MARK_OFF[2] {
			esc(b, rest[:i + 3])
			rest = rest[i + 3:]
			continue
		}
		esc(b, rest[:i])
		rest = rest[i + 3:]
		if c == MARK_ON[2] && !open {
			w(b, "<mark>")
			open = true
		} else if c == MARK_OFF[2] && open {
			w(b, "</mark>")
			open = false
		}
	}
	if open { w(b, "</mark>") }
}

// For the inside of a JSON string in a <script> block (JSON-LD). The HTML escaper
// is wrong there: entities aren't decoded inside <script>, so they would reach
// the JSON literally, and it leaves backslashes and control characters alone.
// `<`, `>` and `&` become \u escapes so the text can never close the script
// element; U+2028/9 too, which some JS parsers reject.
json_esc :: proc(b: ^strings.Builder, s: string) {
	for r in s {
		switch r {
		case '"':  w(b, `\"`)
		case '\\': w(b, `\\`)
		case '\n': w(b, `\n`)
		case '\r': w(b, `\r`)
		case '\t': w(b, `\t`)
		case '<', '>', '&', 0x00 ..< 0x20, 0x2028, 0x2029:
			fmt.sbprintf(b, `\u%04x`, int(r))
		case:
			strings.write_rune(b, r) // an invalid byte arrives as U+FFFD, re-encoded validly
		}
	}
}

// ---- base64 from a request ---------------------------------------------------
//
// core:encoding/base64 traps on some input a client can send (a lone `=` or `==` asks it for a
// buffer of length -1: M4-02), so a value from a cookie, a form or a header is held to the
// alphabet and the padding rules first. `url`: the URL-safe alphabet, padding optional.
b64_decode :: proc(s: string, url := false) -> (out: []byte, ok: bool) {
	data := strings.trim_right(s, "=")
	if len(data) == 0 || len(s) - len(data) > 2 || len(data) % 4 == 1 { return nil, false }
	if !url && len(s) % 4 != 0 { return nil, false }
	for c in transmute([]byte)data {
		switch c {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9':
		case '-', '_': if !url { return nil, false }
		case '+', '/': if url { return nil, false }
		case: return nil, false
		}
	}
	err: base64.Error
	out, err = base64.decode(s, base64.DEC_URL_TABLE if url else base64.DEC_TABLE, allocator = context.temp_allocator)
	return out, err == nil
}
