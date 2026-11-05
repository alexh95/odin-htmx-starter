package lists_web

// ---- lists: /lists (PLAN §6, D36) --------------------------------------------------------------------
//
// A change runs off the loop, then says on lists.list:<id> which columns changed, and each page fetches
// them. The topic is `.Latest` per column: it holds nothing past the newest word, and the reader's own fetch
// always gets the database's view, so a reconnect costs at most one more fetch.

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/web"
import notify_web "../../notify/web"
import lists ".."
import m "../models"
import lists_views "../views"

EXTS :: web.Exts{.Pending}

ROUTES := [?]web.Route {
	{.Get, "/lists", index, .Lists_Edit, {.Private}, 0},
	{.Post, "/lists", create, .Lists_Edit, {.Fragment}, 4096},
	{.Get, "/lists/(%d+)", page, .Lists_Edit, {.Private}, 0},
	{.Get, "/lists/(%d+)/columns/(%d+)", column, .Lists_Edit, {.Private, .Fragment}, 0},
	{.Post, "/lists/(%d+)/items", add, .Lists_Edit, {.Fragment}, 4096},
	{.Post, "/lists/(%d+)/move", move, .Lists_Edit, {.Fragment}, 4096},
	{.Post, "/lists/(%d+)/items/(%d+)/toggle", toggle, .Lists_Edit, {.Fragment}, 4096},
	{.Post, "/lists/(%d+)/items/(%d+)/delete", delete_item, .Lists_Edit, {.Fragment}, 4096},
	{.Post, "/lists/(%d+)/items/(%d+)/assign", assign, .Lists_Edit, {.Fragment}, 4096},
}

TOPICS := [?]hub.Topic {
	{family = "lists.list", policy = .Latest, ring = 16, perm = .Lists_Edit},
}

// A member's changes.
@(private) changes := web.Limit{n = 60, window = time.Minute}

@(private)
me :: proc(req: ^web.Request) -> m.Actor { return lists.actor(web.viewer(req)) }

@(private)
index :: proc(req: ^web.Request, res: ^web.Response) {
	all := make([dynamic]m.Summary, context.temp_allocator)
	if err := lists.summaries(&all); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, "Checklists", "/lists", "Shared checklists.", lists_views.index(all[:]))
}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	l, err := lists.list(id)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	board := web.query_get(req, "view") == "board"
	web.render_page(req, res, l.title, "/lists", "A shared checklist.", lists_views.page(l, board, me(req)), live = {fmt.tprintf("lists.list:%d", id)})
}

@(private)
column :: proc(req: ^web.Request, res: ^web.Response) {
	id, ok := web.parse_id(req.url_params[0])
	col, cok := web.parse_id(req.url_params[1])
	if !ok || !cok {
		web.not_found(req, res)
		return
	}
	l, err := lists.list(id)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	for c in l.columns {
		if c.id != col { continue }
		b := strings.builder_make(context.temp_allocator)
		lists_views.column(&b, l, c, me(req))
		web.respond_html(res, strings.to_string(b))
		return
	}
	web.not_found(req, res)
}

// ---- changes ---------------------------------------------------------------------------------------

@(private)
Kind :: enum {
	Create,
	Add,
	Move,
	Toggle,
	Remove,
	Assign,
}

@(private)
Change :: struct {
	using scan:         web.Scan,
	kind:               Kind,
	viewer:             authz.Viewer,
	list, item:         i64,
	col, after:         i64,
	who:                u64,
	title, text:        string,
	from, to:           i64,
	list_now:           m.List,
	err:                m.Error,
}

@(private)
limited :: proc(req: ^web.Request, res: ^web.Response) -> bool {
	ok, retry := web.limit_hit(&changes, web.viewer(req).id)
	if !ok { web.respond_limited(res, retry, "Too many changes: wait a moment.") }
	return !ok
}

@(private)
start :: proc(req: ^web.Request, res: ^web.Response, kind: Kind) -> ^Change {
	s := web.new_scan(Change, req, res, work, answer)
	if s == nil { return nil }
	s.kind, s.viewer = kind, web.viewer(req)
	return s
}

@(private)
work :: proc(scan: ^web.Scan) {
	s := (^Change)(scan)
	switch s.kind {
	case .Create: s.list, s.err = lists.create(s.title, s.text, s.viewer)
	case .Add:    s.from, s.err = lists.add(s.list, s.text, s.viewer)
	case .Move:   s.from, s.to, s.err = lists.move(s.list, s.item, s.col, s.after, s.viewer)
	case .Toggle: s.from, s.to, s.err = lists.toggle(s.list, s.item, s.viewer)
	case .Remove: s.from, s.err = lists.remove(s.list, s.item)
	case .Assign: s.from, s.text, s.err = lists.assign(s.list, s.item, s.who, s.viewer)
	}
	if s.err == .None && s.kind != .Create { s.list_now, s.err = lists.list(s.list) }
}

@(private)
go_to :: proc(req: ^web.Request, res: ^web.Response, href: string) {
	if web.header(req, "hx-request") == "true" {
		web.set_header(res, "hx-redirect", href)
		web.respond_status(res, .OK)
	} else {
		web.set_header(res, "location", href)
		web.respond_status(res, .See_Other)
	}
}

@(private)
answer :: proc(scan: ^web.Scan, req: ^web.Request, res: ^web.Response) {
	s := (^Change)(scan)
	href := fmt.tprintf("/lists/%d", s.list)
	switch {
	case s.err == .Constraint:
		web.respond_html(res, html.field_msg(false, "This list is full."), .Unprocessable_Content)
	case s.err != .None:
		web.respond_store_error(req, res, s.err)
	case s.kind == .Create:
		go_to(req, res, href)
	case:
		topic := fmt.tprintf("lists.list:%d", s.list)
		hub.publish(topic, lists_views.changed(s.list, s.from), 0, fmt.tprintf("%d", s.from))
		if s.to != 0 { hub.publish(topic, lists_views.changed(s.list, s.to), 0, fmt.tprintf("%d", s.to)) }
		if s.kind == .Assign && s.who != 0 && s.who != s.viewer.id {
			b := strings.builder_make(context.temp_allocator)
			html.esc(&b, s.viewer.name)
			html.w(&b, ` gave you “`)
			html.esc(&b, s.text)
			html.w(&b, `” on `)
			html.esc(&b, s.list_now.title)
			notify_web.send(s.who, "lists.assigned", href, strings.to_string(b))
		}
		if web.header(req, "hx-request") != "true" {
			web.set_header(res, "location", href)
			web.respond_status(res, .See_Other)
			return
		}
		b := strings.builder_make(context.temp_allocator)
		for c in s.list_now.columns {
			if c.id == s.from || c.id == s.to { lists_views.column_partial(&b, s.list_now, c, lists.actor(s.viewer)) }
		}
		web.respond_html(res, strings.to_string(b))
	}
}

@(private)
create :: proc(req: ^web.Request, res: ^web.Response) {
	if limited(req, res) { return }
	f := web.form(req)
	if problem := lists.check_title(f["title"]); problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	s := start(req, res, .Create)
	if s == nil { return }
	s.title, s.text = f["title"], f["template"]
	web.start_scan(req, res, s)
}

@(private)
add :: proc(req: ^web.Request, res: ^web.Response) {
	if limited(req, res) { return }
	id, ok := web.parse_id(req.url_params[0])
	text := web.form(req)["text"]
	if !ok {
		web.not_found(req, res)
		return
	}
	if problem := lists.check_text(text); problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	s := start(req, res, .Add)
	if s == nil { return }
	s.list, s.text = id, text
	web.start_scan(req, res, s)
}

@(private)
move :: proc(req: ^web.Request, res: ^web.Response) {
	if limited(req, res) { return }
	id, ok := web.parse_id(req.url_params[0])
	f := web.form(req)
	item, iok := web.parse_id(f["item"])
	col, cok := web.parse_id(f["col"])
	after, aok := strconv.parse_i64(f["after"], 10)
	if !ok || !iok || !cok {
		web.not_found(req, res)
		return
	}
	s := start(req, res, .Move)
	if s == nil { return }
	s.list, s.item, s.col, s.after = id, item, col, after if aok else -1
	web.start_scan(req, res, s)
}

// The list and item in a path.
@(private)
item_change :: proc(req: ^web.Request, res: ^web.Response, kind: Kind) -> ^Change {
	if limited(req, res) { return nil }
	id, ok := web.parse_id(req.url_params[0])
	item, iok := web.parse_id(req.url_params[1])
	if !ok || !iok {
		web.not_found(req, res)
		return nil
	}
	s := start(req, res, kind)
	if s != nil { s.list, s.item = id, item }
	return s
}

@(private)
toggle :: proc(req: ^web.Request, res: ^web.Response) {
	if s := item_change(req, res, .Toggle); s != nil { web.start_scan(req, res, s) }
}

@(private)
delete_item :: proc(req: ^web.Request, res: ^web.Response) {
	if s := item_change(req, res, .Remove); s != nil { web.start_scan(req, res, s) }
}

@(private)
assign :: proc(req: ^web.Request, res: ^web.Response) {
	if s := item_change(req, res, .Assign); s != nil {
		who, _ := strconv.parse_u64(web.form(req)["who"], 10)
		s.who = who
		web.start_scan(req, res, s)
	}
}
