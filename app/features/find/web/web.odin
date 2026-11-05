package find_web

// ---- find: /find (PLAN §6, D6) ---------------------------------------------------------------------
//
// A page of what the viewer may read, never history-cached and never stored: it holds private-room and DM
// text (§12). The `.Public` perm is the wiki's, which guests can read; each source's own perm is checked in
// the domain. It searches off the loop.

import "core:strings"
import "core:time"
import "core:unicode/utf8"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/web"
import find ".."
import m "../models"
import find_views "../views"

EXTS :: web.Exts{.Preload}

ROUTES := [?]web.Route {
	{.Get, "/find", page, .Public, {.Private}, 0},
	{.Get, "/find/results", fragment, .Public, {.Private, .Fragment}, 0},
}

// §6: 10 per second per user.
@(private) searches := web.Limit{n = 10, window = time.Second}

init :: proc(sources: []m.Source) {
	find.init(sources)
	web.use_palette()
}

@(private)
Finding :: struct {
	using scan: web.Scan,
	viewer:     authz.Viewer,
	q:          string, // the request's: it lives until the answer
	groups:     [dynamic]find.Group,
	failed:     bool,
	whole:      bool,   // the page, not its results
}

@(private) page :: proc(req: ^web.Request, res: ^web.Response) { run(req, res, true) }
@(private) fragment :: proc(req: ^web.Request, res: ^web.Response) { run(req, res, false) }

@(private)
run :: proc(req: ^web.Request, res: ^web.Response, whole: bool) {
	v := web.viewer(req)
	key := v.id if v.id != 0 else web.client_key(web.ctx().client)
	if ok, retry := web.limit_hit(&searches, key); !ok {
		web.respond_limited(res, retry, "Too many searches: wait a moment.")
		return
	}
	q := web.query_get(req, "q")
	if len(q) > find.MAX_QUERY {
		end := find.MAX_QUERY
		for end > 0 && !utf8.rune_start(q[end]) { end -= 1 } // not through a character
		q = q[:end]
	}
	s := web.new_scan(Finding, req, res, proc(scan: ^web.Scan) {
		s := (^Finding)(scan)
		s.groups = make([dynamic]find.Group, context.temp_allocator)
		s.failed = find.search(s.viewer, s.q, &s.groups)
	}, proc(scan: ^web.Scan, req: ^web.Request, res: ^web.Response) {
		s := (^Finding)(scan)
		web.impl(res, "find.engine", find.engine())
		if s.whole {
			web.render_page(req, res, "Search", "/find", "Search everything you can read here.", find_views.page(s.q, s.groups[:], s.failed))
			return
		}
		pages := make([dynamic]html.Nav_Item, context.temp_allocator)
		if q := strings.trim_space(s.q); q != "" { web.nav_matching(s.viewer, q, &pages) }
		b := strings.builder_make(context.temp_allocator)
		find_views.results(&b, s.q, s.groups[:], s.failed, pages[:])
		web.respond_html(res, strings.to_string(b))
	})
	if s == nil { return }
	s.viewer, s.q, s.whole = v, q, whole
	web.start_scan(req, res, s)
}
