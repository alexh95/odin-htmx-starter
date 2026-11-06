package web

// ---- the platform's own routes (§6.3; LC §7) ---------------------------------------
//
// ROUTES: a site's main host (health, metrics, the sitemap, the ownership
// proofs). PUBLIC_ROUTES: every host (assets, robots.txt, the favicon, the
// notices). A profile mounts both, one line each, in its routes.odin. Derived,
// never declared twice: robots.txt's Disallow lines come from the host's
// .Fragment rows and the sitemap from its nav.

import "core:crypto"
import "core:hash"
import "core:net"
import "core:strings"
import "core:time"

import http "../../vendor/odin-http"
import "../authz"
import "../html"
import "../obs"
import "../store"

ROUTES := [?]Route {
	{.Get, "/healthz", healthz, .Public, {}, 0},
	{.Get, "/livez", livez, .Public, {}, 0},
	{.Get, "/readyz", readyz, .Public, {}, 0},
	{.Get, "/metrics", metrics, .Public, {}, 0}, // admin or METRICS_TOKEN_FILE's bearer, checked inside
	{.Get, "/sitemap%.xml", sitemap_xml, .Public, {}, 0},
	{.Get, "/BingSiteAuth%.xml", bing_site_auth, .Public, {}, 0},
	{.Get, "/([%x]+)%.txt", indexnow_key, .Public, {}, 0}, // 404 unless it is the brand's key
}

PUBLIC_ROUTES := [?]Route {
	{.Get, "/static/(.+)", serve_static, .Public, {}, 0},
	{.Get, "/robots%.txt", robots_txt, .Public, {}, 0},
	{.Get, "/favicon%.ico", serve_favicon_ico, .Public, {}, 0},
	{.Get, "/licenses", licenses, .Public, {}, 0},
}

// Where a profile on Header_Set.Reporting has browsers send CSP violations
// (streams, lab, full; §12.2). minimal and skeleton mount none of it.
REPORT_ROUTES := [?]Route {
	{.Post, "/csp%-report", csp_report, .Public, {.Fragment}, CSP_REPORT_CAP},
}

// The bearer /metrics accepts, read from METRICS_TOKEN_FILE at boot; "" = none.
metrics_token: string

@(private) NOTICES :: #load("../../../THIRD_PARTY_NOTICES", string)

// ---- CSP reports (§12.2, §17.5) -----------------------------------------------------

CSP_REPORT_CAP :: 16 * 1024
CSP_REPORTS_A_MINUTE :: 10 // per client id (§17.5)

@(private)
csp_reports := Limit{n = CSP_REPORTS_A_MINUTE, window = time.Minute}

// Logs a browser's violation report at warn, at most CSP_REPORTS_A_MINUTE a
// minute from one client (the rest are dropped), and answers 204 either way. The
// body is the browser's JSON, logged as one escaped value: a report is a hint to
// look, not evidence.
csp_report :: proc(req: ^Request, res: ^Response) {
	c := ctx()
	if ok, _ := limit_hit(&csp_reports, client_key(c.client)); ok {
		if l, lok := obs.begin(.Warning, "csp", "report"); lok {
			obs.str(&l, "body", c.body)
			obs.end(&l)
		}
	}
	http.respond(res, Status.No_Content)
}

// A client's address as a map key, for the per-client limits (CSP reports,
// stream admission, the bot's guests); the address itself is never kept. An
// IPv6 client is its /64: one host holds a whole /64, and keyed by its full
// address it could count as 2^64 clients (M2-11).
client_key :: proc(a: net.Address) -> u64 {
	switch v in a {
	case net.IP4_Address:
		b := v
		return hash.fnv64a(b[:])
	case net.IP6_Address:
		b := transmute([16]u8)v
		// An IPv4 client that a proxy reports as `::ffff:a.b.c.d` is its IPv4 address, keyed as
		// one: as a /64 every such client was one (M2-25).
		mapped := b[10] == 0xff && b[11] == 0xff
		for x in b[:10] { mapped &&= x == 0 }
		return hash.fnv64a(b[12:] if mapped else b[:8])
	}
	return 0
}

// The client's network, for a limit wider than one client (M4-03): its IPv4 /24, its IPv6 /48
// (a site's usual allocation), an IPv4-mapped address as IPv4.
net_key :: proc(a: net.Address) -> u64 {
	switch v in a {
	case net.IP4_Address:
		b := v
		return hash.fnv64a(b[:3])
	case net.IP6_Address:
		b := transmute([16]u8)v
		mapped := b[10] == 0xff && b[11] == 0xff
		for x in b[:10] { mapped &&= x == 0 }
		return hash.fnv64a(b[12:15] if mapped else b[:6])
	}
	return 0
}

// ---- health (§10.4) ----------------------------------------------------------------

// The skeleton's contract, which Fly and the CI smoke test compare: body exactly
// `ok` while every critical module answers (the store's SELECT 1), else 503. It
// is exempt from the canonical-host redirect: a probe that follows a redirect
// off-host fails the deploy.
healthz :: proc(req: ^Request, res: ^Response) {
	for h in obs.modules() {
		if h.critical && h.state == .Down {
			respond_plain(res, "store unavailable" if h.module == "store" else "unavailable", .Service_Unavailable)
			return
		}
	}
	respond_plain(res, "ok")
}

// No locks, no I/O: every loop ticked in the last 5 s. --healthcheck probes it.
livez :: proc(req: ^Request, res: ^Response) {
	_, age := obs.oldest_tick()
	if age > 5e9 {
		respond_plain(res, "stalled", .Service_Unavailable)
		return
	}
	respond_plain(res, "ok")
}

// Every critical module up and not draining; ?detail lists each module.
readyz :: proc(req: ^Request, res: ^Response) {
	ok, why := obs.ready()
	if obs.is_draining() { http.headers_set_unsafe(&res.headers, "x-draining", "1") }
	if query_get(req, "detail") != "" || has_query_key(req, "detail") {
		b := strings.builder_make(context.temp_allocator)
		strings.write_string(&b, "ready\n" if ok else "not ready\n")
		obs.render_health(&b)
		respond_plain(res, strings.to_string(b), .OK if ok else .Service_Unavailable)
		return
	}
	if !ok {
		respond_plain(res, why, .Service_Unavailable)
		return
	}
	respond_plain(res, "ok")
}

@(private)
has_query_key :: proc(req: ^Request, key: string) -> bool {
	q := req.url.query
	for part in strings.split_by_byte_iterator(&q, '&') {
		k, _, _ := strings.partition(part, "=")
		if k == key { return true }
	}
	return false
}

// Prometheus text, to an Admin or to the bearer in METRICS_TOKEN_FILE. With
// neither configured it isn't there at all.
metrics :: proc(req: ^Request, res: ^Response) {
	allowed := tl_ctx != nil && authz.can(tl_ctx.viewer, .Admin_Ops)
	if !allowed && metrics_token != "" {
		auth, _ := http.headers_get(req.headers, "authorization")
		given := strings.trim_prefix(auth, "Bearer ")
		allowed = len(given) == len(metrics_token) &&
			crypto.compare_constant_time(transmute([]byte)given, transmute([]byte)metrics_token) == 1
		if !allowed {
			http.headers_set_unsafe(&res.headers, "www-authenticate", "Bearer")
			respond_plain(res, "unauthorized", .Unauthorized)
			return
		}
	}
	if !allowed {
		not_found(req, res)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	obs.render(&b)
	res.status = .OK
	http.headers_set_content_type(&res.headers, "text/plain; version=0.0.4; charset=utf-8")
	http.body_set(res, strings.to_string(b))
	http.respond(res)
}

// ---- crawlers ----------------------------------------------------------------------

// The fragment routes answer with bare HTML built to be swapped into a page;
// indexed alone they'd be thin near-duplicates, so they are disallowed outright.
robots_txt :: proc(req: ^Request, res: ^Response) {
	respond_plain(res, ctx().site.robots)
}

// robots.txt for one host, at boot: a Disallow per .Fragment row's literal start,
// dropping one another line already covers ("/contacts/" under "/contacts"), and
// collapsing a family of rows under one first segment to it ("/ui/modal",
// "/ui/drawer", … → "/ui/"), unless a page lives under that segment too
// ("/lab/streams" beside "/lab/feed"). In mount order, each once. A Disallow is a
// prefix, so a row over a page anyone may read and index gets no line: POST /wiki
// mustn't hide GET /wiki, or the pages under it.
robots_for :: proc(site: ^Site, allocator := context.allocator) -> string {
	lits := make([dynamic]string, context.temp_allocator)
	pages := make([dynamic]string, context.temp_allocator)
	public := make([dynamic]string, context.temp_allocator)
	for m in site.router.rows {
		lit := m.pattern
		if i := strings.index_any(m.pattern, MAGIC); i >= 0 { lit = m.pattern[:i] }
		if .Fragment in m.flags {
			append(&lits, lit)
		} else if m.method == .Get {
			append(&pages, lit)
			if m.perm == .Public && .Private not_in m.flags { append(&public, lit) }
		}
	}
	#reverse for l, i in lits {
		for p in public {
			if strings.has_prefix(p, l) {
				ordered_remove(&lits, i)
				break
			}
		}
	}
	covered :: proc(lits: []string, l: string) -> bool {
		for o in lits {
			if o != l && strings.has_prefix(l, o) { return true }
		}
		return false
	}
	first_segment :: proc(l: string) -> string {
		j := strings.index_byte(l[1:], '/')
		return l[:j + 2] if j >= 0 else ""
	}
	lines := make([dynamic]string, context.temp_allocator)
	outer: for l in lits {
		if covered(lits[:], l) { continue }
		line := l
		if seg := first_segment(l); seg != "" {
			family := 0
			for o in lits {
				if strings.has_prefix(o, seg) && !covered(lits[:], o) { family += 1 }
			}
			for p in pages {
				if strings.has_prefix(p, seg) { family = 0 }
			}
			if family >= 2 { line = seg }
		}
		for x in lines {
			if x == line { continue outer }
		}
		append(&lines, line)
	}
	b := strings.builder_make(allocator)
	strings.write_string(&b, "User-agent: *\nAllow: /\n")
	for l in lines {
		strings.write_string(&b, "Disallow: ")
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	strings.write_string(&b, "\nSitemap: ")
	strings.write_string(&b, site.origin)
	strings.write_string(&b, "/sitemap.xml\n")
	return strings.to_string(b)
}

// The sitemap walks the host's nav, so a page can't be added to the nav and left
// out of the sitemap; absolute URLs on the canonical origin.
// The nav's pages this viewer can open whose label holds `q`: what a palette goes to.
nav_matching :: proc(v: authz.Viewer, q: string, out: ^[dynamic]html.Nav_Item) {
	site := ctx().site
	for item in site.nav {
		if !store.contains_ci(item.label, q) { continue }
		if m, _, _ := router_find(&site.router, .Get, item.href); m != nil && !authz.can(v, m.perm) { continue }
		append(out, item)
	}
}

sitemap_xml :: proc(req: ^Request, res: ^Response) {
	site := ctx().site
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
`)
	for item in site.nav {
		// A page only some viewers may see, or one marked noindex (.Private), is no
		// page for a crawler: a member's Inbox, chat's rooms.
		if m, _, _ := router_find(&site.router, .Get, item.href); m != nil && (m.perm != .Public || .Private in m.flags) { continue }
		strings.write_string(&b, "  <url><loc>")
		strings.write_string(&b, site.origin)
		strings.write_string(&b, item.href)
		strings.write_string(&b, "</loc></url>\n")
	}
	strings.write_string(&b, "</urlset>\n")
	http.respond_file_content(res, "sitemap.xml", transmute([]byte)strings.to_string(b))
}

// Bing verifies ownership by fetching this and matching the token; an unset token
// 404s, so a fork never advertises a stale one.
bing_site_auth :: proc(req: ^Request, res: ^Response) {
	token := ctx().site.brand.bing_site_auth
	if token == "" {
		not_found(req, res)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<?xml version="1.0"?>
<users>
	<user>`)
	strings.write_string(&b, token)
	strings.write_string(&b, `</user>
</users>
`)
	http.respond_file_content(res, "BingSiteAuth.xml", transmute([]byte)strings.to_string(b))
}

// IndexNow proves ownership by serving the key back, verbatim, at /<key>.txt.
indexnow_key :: proc(req: ^Request, res: ^Response) {
	key := ctx().site.brand.indexnow_key
	if key == "" || req.url_params[0] != key {
		not_found(req, res)
		return
	}
	respond_plain(res, key)
}

// The notices of what the binary contains (odin-http's MIT, Odin's zlib, …).
licenses :: proc(req: ^Request, res: ^Response) {
	respond_plain(res, NOTICES)
}
