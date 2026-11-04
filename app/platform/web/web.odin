package web

// ---- platform/web: routes, requests and responses (L3) ----------------------
//
// The one platform package that imports odin-http (the fork, app/vendor). It
// re-exports the request and response types, so every handler is written over
// ^web.Request and ^web.Response and no feature imports odin-http. It holds the
// route row (D5), the per-host prefix router (§8.3), the responses with their
// charset, the embedded assets, the platform's own routes, and the request
// context `front` (platform/app) fills before a handler runs.

import "core:net"
import "core:strings"

import http "../../vendor/odin-http"
import "../authz"
import "../ext"
import "../html"

Request :: http.Request
Response :: http.Response
Method :: http.Method
Status :: http.Status
Headers :: http.Headers

Ext :: ext.Ext
Exts :: ext.Exts
Bundle :: ext.Bundle

Handler :: #type proc(req: ^Request, res: ^Response)

Route_Flag :: enum u8 {
	Step_Up,       // a recent password or TOTP check (M4)
	Lan_Only,      // 404 unless the client is in LAN_CIDRS
	Private,       // no-store, noindex, hx-history="false"
	Fragment,      // bare HTML to swap into a page: kept out of robots.txt's crawl
	Stream,        // SSE, WS, multipart: no buffering by a proxy (M2)
	Frame_Games,   // frame-src for the games origin (M10)
	Media,         // Range, immutable (M9)
	Nonce_Csp,     // a per-response nonce CSP (lab pages, M2)
	Lab_Host,      // a mount rule: only on a host where no cookie-setting identity runs
	Trusted_Types, // with .Nonce_Csp: Trusted Types enforced, and no hyperscript on the page (/scripting/tt)
}

Route_Flags :: bit_set[Route_Flag]

// One row of a feature's ROUTES table (D5; PLAN §6.1). The pattern is a Lua
// pattern, anchored at both ends; its route id is "<METHOD> <pattern>".
Route :: struct {
	method:   Method,
	pattern:  string,
	handler:  Handler,
	perm:     authz.Perm,
	flags:    Route_Flags,
	body_cap: int, // 0 = MAX_BODY
}

// Far above any form a feature posts (each caps its own fields), so it only ever
// stops abuse: a larger body gets 413 before a byte of it is read.
MAX_BODY :: 64 * 1024

// A host, as boot made it from the profile's app.Host row and its brand: what
// `front` dispatches on and what a page renders with.
Site :: struct {
	name:      string, // "main", "lab": the host's log and metrics label
	origin:    string, // https://… without a trailing slash: SITE_URL, resolved at boot
	hostname:  string, // the origin's host, without the port, matched against Host
	identity:  bool,   // whether front runs the identity here
	brand:     ^html.Brand,
	nav:       []html.Nav_Item,
	router:    Router,
	robots:    string, // derived at boot: the .Fragment rows' prefixes and the sitemap
	redirect:  bool,   // *.fly.dev answers 301 to `origin` (off for a placeholder origin)
}

// What the build is, as platform/app knows it at boot (§15.4): for /admin/modules, which may
// not import platform/app. Read-only once serving starts.
Build :: struct {
	profile, store, identity, client, theme: string,
	features:                                []string,
	exts:                                    Exts, // the main bundle's
	routes:                                  []Route_Info,
}

Route_Info :: struct {
	host, feature, id, perm: string,
	flags:                   Route_Flags,
}

build: Build

// What a request carries through `front` to its handler. A handler runs
// synchronously on its loop, so the context is the thread's while it runs; a
// write's continuation, which runs on a later tick, keeps what it needs itself.
Req_Ctx :: struct {
	req:    ^Request,
	res:    ^Response,
	start:  i64, // mono ns, when front began
	site:   ^Site,
	route:  ^Mounted,
	viewer: authz.Viewer,
	client: net.Address,
	https:  bool,
	id:     string,
	body:   string,
	form:   map[string]string, // parsed on first use
	parsed: bool,
	impl:     string, // "chat.transport=sse": sent as x-impl and logged
	deferred: bool,   // the handler deferred its response: its continuation logs it
	large:    bool,   // holds a large body's count until it's read
	allow:    []string, // no route: the methods that would answer (405)
	nonce:    string,   // a .Nonce_Csp route's, this response's (§12.2); "" otherwise
}

@(private, thread_local) tl_ctx: ^Req_Ctx

// The current request's context, inside a handler.
ctx :: proc() -> ^Req_Ctx {
	assert(tl_ctx != nil, "web.ctx: not inside a handler")
	return tl_ctx
}

// For platform/app's front, around each handler call.
set_ctx :: proc(c: ^Req_Ctx) { tl_ctx = c }

viewer :: proc(req: ^Request) -> authz.Viewer { return ctx().viewer }

// Says which implementation of a runtime-switched axis served this request
// (D8): `x-impl: chat.transport=sse`, and `impl=` in its access-log line.
impl :: proc(res: ^Response, axis, name: string) {
	v := strings.concatenate({axis, "=", name}, context.temp_allocator)
	http.headers_set_unsafe(&res.headers, "x-impl", v)
	if tl_ctx != nil { tl_ctx.impl = v }
}

// The route id a row is counted and logged under.
route_id :: proc(r: Route, allocator := context.allocator) -> string {
	return strings.concatenate({http.method_string(r.method), " ", r.pattern}, allocator)
}
