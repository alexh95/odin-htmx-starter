package web

// ---- responses and request helpers ---------------------------------------------
//
// odin-http names text types without a charset ("text/html"); the pages say
// UTF-8 in a <meta>, but the header is what a client reads first, so text goes
// out through these, never http.respond_html or http.respond_plain.

import "core:net"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

import http "../../vendor/odin-http"
import "../authz"
import "../html"
import "../store"

respond_html :: proc(res: ^Response, body: string, status := Status.OK) {
	body := body
	// A .Nonce_Csp response: the views' markers become this response's nonce (§12.2).
	if tl_ctx != nil && tl_ctx.nonce != "" { body, _ = strings.replace_all(body, html.NONCE_MARK, tl_ctx.nonce, context.temp_allocator) }
	respond_text(res, "text/html; charset=utf-8", body, status)
}

respond_plain :: proc(res: ^Response, body: string, status := Status.OK) {
	respond_text(res, "text/plain; charset=utf-8", body, status)
}

// A file for hx-download to save (or a browser to download): an attachment named `filename`, which
// the caller writes from its own rows, never the request.
respond_attachment :: proc(res: ^Response, content_type, filename, body: string) {
	set_header(res, "content-disposition", strings.concatenate({`attachment; filename="`, filename, `"`}, context.temp_allocator))
	respond_text(res, content_type, body, .OK)
}

respond_csv :: proc(res: ^Response, filename, body: string) {
	respond_attachment(res, "text/csv; charset=utf-8", filename, body)
}

respond_json :: proc(res: ^Response, v: any, status := Status.OK) {
	http.respond_json(res, v, status)
}

// Content type from the name's extension.
respond_file :: proc(res: ^Response, name: string, content: []byte, status := Status.OK) {
	http.respond_file_content(res, name, content, status)
}

// `content` as `content_type`, which the caller has from its own row: nothing is guessed.
respond_bytes :: proc(res: ^Response, content_type: string, content: []byte, status := Status.OK) {
	res.status = status
	http.headers_set_content_type(&res.headers, content_type)
	http.body_set(res, content)
	http.respond(res)
}

// Runs once this response has gone, or failed to, when its connection's memory is given back.
after_sent :: proc(res: ^Response, cb: proc(user: rawptr), user: rawptr) {
	res._after_sent, res._after_sent_user = cb, user
}

respond_status :: proc(res: ^Response, status: Status) {
	http.respond(res, status)
}

@(private)
respond_text :: proc(res: ^Response, content_type, body: string, status: Status) {
	res.status = status
	http.headers_set_content_type(&res.headers, content_type)
	http.body_set(res, body)
	http.respond(res)
}

header :: proc(req: ^Request, name: string) -> (string, bool) #optional_ok {
	return http.headers_get(req.headers, name)
}

has_header :: proc(req: ^Request, name: string) -> bool {
	return http.headers_has(req.headers, name)
}

set_header :: proc(res: ^Response, name, value: string) {
	http.headers_set(&res.headers, name, value)
}

// A Set-Cookie beside any other: headers hold one value a name, so a response that sets two
// cookies (a session and its device, M4-03) sends the second this way. HttpOnly, SameSite=Lax,
// Path=/; `max_age` 0 ends it.
add_cookie :: proc(res: ^Response, name, value: string, max_age: int, secure: bool) {
	append(&res.cookies, http.Cookie{name = name, value = value, max_age_secs = max_age, path = "/", http_only = true, secure = secure, same_site = .Lax})
}

is_htmx :: proc(req: ^Request) -> bool {
	return http.headers_has(req.headers, "hx-request")
}

// ---- pages ------------------------------------------------------------------------

// A whole page in the host's shell: its brand, its nav, the assets. A page on a
// fixed bundle (the lab's scripting and compat pages) names it (§12.1), and a
// boosted link into it gets HX-Redirect instead: a boosted swap would keep the
// old document's CSP and scripts, so the browser loads it whole.
// `live` names the page's own topics for the layout's one SSE stream (§9.1), as
// `chat.room:12`; the viewer's own topics (notify.user:<id>) join them without asking.
render_page :: proc(req: ^Request, res: ^Response, title, active, description, content: string, status := Status.OK, bundle := Bundle.Main, live: []string = nil) {
	if bundle != .Main && header(req, "hx-boosted") == "true" {
		set_header(res, "hx-redirect", req.url.raw)
		respond_status(res, .OK)
		return
	}
	respond_html(res, page_html(title, active, description, content, bundle, live), status)
}

// A build that mounts find has the Ctrl-K palette in every Main page's layout.
@(private) palette_on: bool

use_palette :: proc() { palette_on = true }

// The layout's #live, as the hub builds it for this request: set by hub.init, so a
// profile that doesn't stream links none of it and its pages open no stream.
Live_Proc :: #type proc(page: []string) -> string

@(private)
live_proc: Live_Proc

on_live :: proc(p: Live_Proc) {
	live_proc = p
}

page_html :: proc(title, active, description, content: string, bundle := Bundle.Main, live: []string = nil) -> string {
	c := ctx()
	site := c.site
	// Trusted Types blocks every hyperscript `put` (11 §2.3): such a page loads none.
	tt := c.route != nil && .Trusted_Types in c.route.flags
	return html.layout({
		brand = site.brand, origin = site.origin, nav = site.nav,
		css = assets.css_href, htmx = assets.bundle_href[bundle], js = assets.js_href,
		hs = "" if tt else assets.hs_href, behaviours = "" if tt else assets.behaviours_href,
		title = title, active = active, description = description,
		bundle = bundle, nonce = c.nonce, canonical = c.canonical, palette = palette_on && bundle == .Main, history_cache = c.history_cache && c.viewer.id == 0 && !c.private && (c.route == nil || .Private not_in c.route.flags),
		live = live_proc(live) if live_proc != nil else "",
		kept_style = c.viewer.style, kept_scheme = c.viewer.scheme,
		theme_href = authz.theme_href if c.viewer.id != 0 else "",
	}, content)
}

// A 404 a person might be looking at gets the site's own page; an htmx or API
// request gets a bare 404, since a page would be swapped into a fragment.
not_found :: proc(req: ^Request, res: ^Response) {
	if is_htmx(req) {
		http.respond(res, Status.Not_Found)
		return
	}
	msg := "There is nothing at this address. It may have moved, or never existed."
	respond_html(res, page_html("Not found", "", msg, html.error_body("Page not found", msg)), .Not_Found)
}

// A store failure the handler can't recover from. A missing row keeps its plain
// 404; anything else gets a status and, as htmx 4 swaps error responses too, an
// out-of-band toast for an htmx request (a response that is all OOB leaves its
// target alone) or an error page for a page load.
respond_store_error :: proc(req: ^Request, res: ^Response, err: store.Error) {
	status := Status.Internal_Server_Error
	msg := "Something went wrong on our side. Try again in a moment."
	#partial switch err {
	case .Not_Found:
		not_found(req, res)
		return
	case .Constraint:
		status, msg = .Conflict, "That change conflicts with what is already stored."
	case .Busy:
		status, msg = .Service_Unavailable, "The server is busy. Try again in a moment."
		http.headers_set_unsafe(&res.headers, "retry-after", "1")
	}
	if is_htmx(req) {
		respond_html(res, html.toast("error", msg, true), status)
	} else {
		respond_html(res, page_html("Error", "", msg, html.error_body("That didn't work", msg)), status)
	}
}

// ---- the query and the form --------------------------------------------------------

// One query parameter, decoded. odin-http hands over the raw query; it is walked
// once rather than built into a map for the one key wanted.
query_get :: proc(req: ^Request, key: string) -> string {
	q := req.url.query
	for part in strings.split_by_byte_iterator(&q, '&') {
		eq := strings.index_byte(part, '=')
		k := part if eq < 0 else part[:eq]
		if k == key {
			return form_decode("" if eq < 0 else part[eq + 1:])
		}
	}
	return ""
}

// An integer parameter; `fallback` when absent. Garbage parses as 0, as the
// skeleton's did: the services clamp what they get.
query_int :: proc(req: ^Request, key: string, fallback: int) -> int {
	s := query_get(req, key)
	if s == "" { return fallback }
	return to_int(s)
}

// The request's form fields, '+'- and percent-decoded; empty without a body.
// front read the body before routing, capped and same-origin checked.
form :: proc(req: ^Request) -> map[string]string {
	c := ctx()
	if !c.parsed {
		c.form = body_form(c.body)
		c.parsed = true
	}
	return c.form
}

// Every value of a key a form repeats (checkboxes of one name), which `form`'s map keeps one of.
form_values :: proc(req: ^Request, key: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	s := ctx().body
	for part in strings.split_by_byte_iterator(&s, '&') {
		eq := strings.index_byte(part, '=')
		if eq >= 0 && form_decode(part[:eq]) == key { append(&out, form_decode(part[eq + 1:])) }
	}
	return out[:]
}

// Parses an application/x-www-form-urlencoded body. Unlike http.body_url_encoded
// it decodes '+' as a space: htmx 4 sends spaces as '+' (the form-encoding
// standard), and odin-http's parser only percent-decodes.
@(private)
body_form :: proc(s: string) -> map[string]string {
	m := make(map[string]string, context.temp_allocator)
	s := s
	for part in strings.split_by_byte_iterator(&s, '&') {
		if part == "" { continue }
		eq := strings.index_byte(part, '=')
		key := part if eq < 0 else part[:eq]
		val := "" if eq < 0 else part[eq + 1:]
		m[form_decode(key)] = form_decode(val)
	}
	return m
}

// '+' to a space, then percent-decoding; a malformed escape is kept as typed. Always a
// copy in the request arena, never a slice of the body: a stream's begin frees the
// buffer a body lives in, and a malformed `%` handed a stream's handler that freed
// memory (M2-09).
form_decode :: proc(s: string) -> string {
	if s == "" { return "" }
	t := s
	if strings.index_byte(s, '+') >= 0 {
		t, _ = strings.replace_all(s, "+", " ", context.temp_allocator)
	}
	dec, ok := net.percent_decode(t, context.temp_allocator)
	return dec if ok else strings.clone(t, context.temp_allocator)
}

// A row id from a path capture: digits only, positive, within i64. An
// ownership check on one id must never act on another.
parse_id :: proc(s: string) -> (id: i64, ok: bool) {
	n, digits_ok := parse_digits(s)
	return i64(n), digits_ok && n > 0
}

// Digits only, within int. Not strconv.parse_int: it takes a sign and '_'
// separators, and wraps silently past 64 bits (18446744073709551617 parses as 1).
parse_digits :: proc(s: string) -> (n: int, ok: bool) {
	if s == "" { return 0, false }
	for i in 0 ..< len(s) {
		if s[i] < '0' || s[i] > '9' { return 0, false }
		d := int(s[i] - '0')
		if n > (max(int) - d) / 10 { return 0, false }
		n = n * 10 + d
	}
	return n, true
}

// A form or query integer, as the skeleton read one: strconv's prefix parse,
// garbage as 0. The services clamp what they get; ids go through parse_id.
to_int :: proc(s: string) -> int {
	n, _ := strconv.parse_int(s, 10)
	return n
}

// ---- an admin's reason ---------------------------------------------------------------

// What an admin write asks for in its prompt (hx-prompt), for the audit log; in characters.
MAX_REASON :: 200

// The admin's reason from HX-Prompt: required, decoded, capped; a refusal is answered here (422).
prompt_reason :: proc(req: ^Request, res: ^Response) -> (reason: string, ok: bool) {
	raw, _ := header(req, "hx-prompt")
	text, dok := net.percent_decode(raw, context.temp_allocator)
	if !dok { text = raw }
	text = strings.trim_space(text)
	if text == "" {
		respond_html(res, html.toast("error", "Give a reason: it goes to the audit log.", true), .Unprocessable_Content)
		return "", false
	}
	if utf8.rune_count_in_string(text) > MAX_REASON {
		respond_html(res, html.toast("error", "A reason is at most 200 characters.", true), .Unprocessable_Content)
		return "", false
	}
	return text, true
}
