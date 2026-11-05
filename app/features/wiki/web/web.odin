package wiki_web

// ---- wiki: /wiki (PLAN §6, D36) --------------------------------------------------------------

import "core:strings"

import "../../../platform/web"
import wiki ".."
import m "../models"
import wiki_views "../views"

EXTS :: web.Exts{}

// Everyone holds Wiki_Read, and a host with no identity serves the Manual, so the read rows are public and
// a members' page is refused by the domain.
ROUTES := [?]web.Route {
	{.Get, "/wiki", index, .Public, {}, 0},
	{.Get, "/wiki/([%w%-]+)", page, .Public, {}, 0},
}

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
index :: proc(req: ^web.Request, res: ^web.Response) {
	pages := make([dynamic]m.Page, context.temp_allocator)
	if err := wiki.list(web.viewer(req), &pages); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.impl(res, "wiki.store", wiki.IMPL)
	web.render_page(req, res, copy.name, "/wiki", copy.description, wiki_views.index(copy.name, pages[:]))
}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	p, err := wiki.page(strings.to_lower(req.url_params[0], context.temp_allocator), web.viewer(req))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, p.title, "/wiki", copy.description, wiki_views.page(copy.name, p))
}
