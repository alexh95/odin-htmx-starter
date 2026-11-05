package wiki_web

// ---- wiki: /wiki (PLAN §6, D36) --------------------------------------------------------------

import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/markdown"
import "../../../platform/web"
import wiki ".."
import m "../models"
import wiki_views "../views"

EXTS :: web.Exts{.Download, .History_Cache, .Head, .Preload}

// Everyone holds Wiki_Read, and a host with no identity serves the Manual, so the read rows are public and
// a members' page is refused by the domain.
ROUTES := [?]web.Route {
	{.Get, "/wiki", index, .Public, {}, 0},
	{.Get, "/wiki/([%w%-]+)%.md", export, .Public, {}, 0},
	{.Get, "/wiki/([%w%-]+)", page, .Public, {}, 0},
}

// Past its own cap a text is refused by the domain, with a reason, so the cap here is the percent
// encoding's three bytes for one, and the rest of the form.
@(private) BODY_CAP :: markdown.MAX_INPUT * 3 + 4096

// Only where pages can be written: SQLite, and an identity to write them. Before ROUTES: `/wiki/new`
// would otherwise be a page's name, and wiki.RESERVED is why no page has it.
EDIT_ROUTES := [?]web.Route {
	{.Get, "/wiki/new", new_page, .Wiki_Edit, {.Private}, 0},
	{.Post, "/wiki/preview", preview, .Wiki_Edit, {.Fragment}, BODY_CAP},
	{.Post, "/wiki", create, .Wiki_Edit, {.Fragment}, BODY_CAP},
	{.Post, "/wiki/([%w%-]+)", update, .Wiki_Edit, {.Fragment}, BODY_CAP},
	{.Get, "/wiki/([%w%-]+)/edit", edit, .Wiki_Edit, {.Private}, 0},
	{.Get, "/wiki/([%w%-]+)/history", history, .Wiki_Edit, {.Private}, 0},
	{.Get, "/wiki/([%w%-]+)/history/(%d+)", revision, .Wiki_Edit, {.Private}, 0},
}

// A member's saves and previews. The editor previews as they type, every half second at most.
@(private) saves := web.Limit{n = 30, window = time.Minute}
@(private) previews := web.Limit{n = 5, window = time.Second}

// The profile's words.
Copy :: struct {
	name, description: string,
	repo:              string, // where a doc that isn't in the Manual is linked
}

@(private) copy: Copy

init :: proc(c: Copy) {
	copy = c
	wiki.init(c.repo)
}

// After the migrations.
seed :: proc() { wiki.seed() }

@(private)
may_edit :: proc(req: ^web.Request) -> bool {
	return wiki.IMPL != "source_files" && authz.can(web.viewer(req), .Wiki_Edit)
}

@(private)
slug_param :: proc(req: ^web.Request) -> string {
	return strings.to_lower(req.url_params[0], context.temp_allocator)
}

@(private)
index :: proc(req: ^web.Request, res: ^web.Response) {
	pages := make([dynamic]m.Page, context.temp_allocator)
	if err := wiki.list(web.viewer(req), &pages); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.impl(res, "wiki.store", wiki.IMPL)
	if web.viewer(req).id == 0 { web.keep_in_history() } // a member's lists their pages' titles
	web.render_page(req, res, copy.name, "/wiki", copy.description, wiki_views.index(copy.name, pages[:], may_edit(req)))
}

// A members' page is private by response: no shared cache, no index.
@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	p, err := wiki.page(slug_param(req), web.viewer(req))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if p.visibility == .Members { web.set_private(res) } else { web.keep_in_history() }
	web.set_canonical(strings.concatenate({"/wiki/", p.slug}, context.temp_allocator))
	web.render_page(req, res, p.title, "/wiki", wiki.summary(p), wiki_views.page(copy.name, p, may_edit(req)))
}

@(private)
export :: proc(req: ^web.Request, res: ^web.Response) {
	p, err := wiki.page(slug_param(req), web.viewer(req))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if p.visibility == .Members { web.set_private(res) }
	web.respond_attachment(res, "text/markdown; charset=utf-8", strings.concatenate({p.slug, ".md"}, context.temp_allocator), p.md)
}

@(private)
new_page :: proc(req: ^web.Request, res: ^web.Response) {
	web.render_page(req, res, "New page", "/wiki", copy.description, wiki_views.editor(copy.name, {}))
}

@(private)
edit :: proc(req: ^web.Request, res: ^web.Response) {
	p, err := wiki.page(slug_param(req), web.viewer(req))
	if err == .None && p.manual { err = .Not_Found } // the Manual is the binary's
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, p.title, "/wiki", copy.description, wiki_views.editor(copy.name, p))
}

// ---- saving: off the loop, where it renders ---------------------------------------------------------

@(private)
Saving :: struct {
	using scan: web.Scan,
	viewer:     authz.Viewer,
	slug:       string, // "": a new page
	title, md:  string,
	visibility: m.Visibility,
	base_rev:   i64,
	current:    m.Page,
	conflict:   bool,
	lines:      []wiki.Diff_Line,
	err:        m.Error,
}

@(private) create :: proc(req: ^web.Request, res: ^web.Response) { save(req, res, "") }
@(private) update :: proc(req: ^web.Request, res: ^web.Response) { save(req, res, slug_param(req)) }

@(private)
save :: proc(req: ^web.Request, res: ^web.Response, slug: string) {
	v := web.viewer(req)
	if ok, retry := web.limit_hit(&saves, v.id); !ok {
		web.respond_limited(res, retry, "Too many saves: wait a moment.")
		return
	}
	f := web.form(req)
	title, md := f["title"], f["md"]
	if problem := wiki.check(title, md, slug == ""); problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	base, _ := strconv.parse_i64(f["rev"], 10)
	if slug != "" && base <= 0 {
		web.respond_html(res, html.field_msg(false, "Reload the page and try again."), .Unprocessable_Content)
		return
	}
	s := web.new_scan(Saving, req, res, proc(scan: ^web.Scan) {
		s := (^Saving)(scan)
		s.current, s.conflict, s.err = wiki.save(s.viewer, s.slug, s.title, s.md, s.visibility, s.base_rev)
		if s.conflict { s.lines = wiki.diff(s.current.md, s.md) }
	}, saved)
	if s == nil { return }
	s.viewer, s.slug, s.title, s.md, s.base_rev = v, slug, title, md, base
	s.visibility = .Public if f["visibility"] == "public" else .Members
	web.start_scan(req, res, s)
}

@(private)
saved :: proc(scan: ^web.Scan, req: ^web.Request, res: ^web.Response) {
	s := (^Saving)(scan)
	switch {
	case s.conflict:
		web.respond_html(res, wiki_views.conflict(s.current, s.lines), .Conflict)
	case s.err == .Constraint && s.slug == "":
		web.respond_html(res, html.field_msg(false, "That title is taken."), .Unprocessable_Content)
	case s.err != .None:
		web.respond_store_error(req, res, s.err)
	case:
		href := strings.concatenate({"/wiki/", s.current.slug}, context.temp_allocator)
		if web.header(req, "hx-request") == "true" {
			web.set_header(res, "hx-redirect", href)
			web.respond_status(res, .OK)
		} else {
			web.set_header(res, "location", href)
			web.respond_status(res, .See_Other)
		}
	}
}

@(private)
Previewing :: struct {
	using scan: web.Scan,
	md:         string,
	rendered:   string,
}

@(private)
preview :: proc(req: ^web.Request, res: ^web.Response) {
	if ok, retry := web.limit_hit(&previews, web.viewer(req).id); !ok {
		web.respond_limited(res, retry, "")
		return
	}
	s := web.new_scan(Previewing, req, res, proc(scan: ^web.Scan) {
		s := (^Previewing)(scan)
		if r, ok := wiki.render(s.md, ""); ok { s.rendered = r.html }
	}, proc(scan: ^web.Scan, _: ^web.Request, res: ^web.Response) {
		s := (^Previewing)(scan)
		web.respond_html(res, wiki_views.preview(s.rendered))
	})
	if s == nil { return }
	s.md = web.form(req)["md"]
	web.start_scan(req, res, s)
}

// ---- history -------------------------------------------------------------------------------------

@(private)
history :: proc(req: ^web.Request, res: ^web.Response) {
	p, err := wiki.page(slug_param(req), web.viewer(req))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	revisions := make([dynamic]m.Revision, context.temp_allocator)
	if err = wiki.history(p.slug, &revisions); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, p.title, "/wiki", copy.description, wiki_views.history(copy.name, p, revisions[:]))
}

@(private)
Diffing :: struct {
	using scan: web.Scan,
	viewer:     authz.Viewer,
	slug:       string,
	rev:        i64,
	page:       m.Page,
	revision:   m.Revision,
	lines:      []wiki.Diff_Line,
	err:        m.Error,
}

// A revision against what replaced it, the next one or the page itself.
@(private)
revision :: proc(req: ^web.Request, res: ^web.Response) {
	rev, ok := web.parse_id(req.url_params[1])
	if !ok {
		web.not_found(req, res)
		return
	}
	s := web.new_scan(Diffing, req, res, proc(scan: ^web.Scan) {
		s := (^Diffing)(scan)
		if s.page, s.err = wiki.page(s.slug, s.viewer); s.err != .None { return }
		if s.revision, s.err = wiki.revision(s.slug, s.rev); s.err != .None { return }
		after := s.page.md
		if s.rev + 1 < s.page.rev {
			next: m.Revision
			if next, s.err = wiki.revision(s.slug, s.rev + 1); s.err != .None { return }
			after = next.md
		}
		s.lines = wiki.diff(s.revision.md, after)
	}, proc(scan: ^web.Scan, req: ^web.Request, res: ^web.Response) {
		s := (^Diffing)(scan)
		if s.err != .None {
			web.respond_store_error(req, res, s.err)
			return
		}
		web.render_page(req, res, s.page.title, "/wiki", copy.description, wiki_views.revision(copy.name, s.page, s.revision, s.lines))
	})
	if s == nil { return }
	s.viewer, s.slug, s.rev = web.viewer(req), slug_param(req), rev
	web.start_scan(req, res, s)
}
