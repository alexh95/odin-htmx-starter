package polls_web

// ---- polls: /polls (PLAN §15.1, D36, Q36) ----------------------------------------------------------------
//
// A change runs off the loop, then says on polls.poll:<id> that the poll changed, and each page fetches its
// bars. The chosen option comes in the form body and goes no further than the store: no log line, audit row or
// notice here has it, which is what an anonymous poll promises.

import "core:fmt"
import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/web"
import "../../../platform/workers"
import notify_web "../../notify/web"
import polls ".."
import m "../models"
import polls_views "../views"

EXTS :: web.Exts{.Pending}

ROUTES := [?]web.Route {
	{.Get, "/polls", index, .Polls_Vote, {.Private}, 0},
	{.Post, "/polls", create, .Polls_Create, {.Fragment}, 8192},
	{.Get, "/polls/(%d+)", page, .Polls_Vote, {.Private}, 0},
	{.Get, "/polls/(%d+)/results", results, .Polls_Vote, {.Private, .Fragment}, 0},
	{.Post, "/polls/(%d+)/vote", vote, .Polls_Vote, {.Fragment}, 4096},
	{.Post, "/polls/(%d+)/close", close, .Polls_Create, {.Fragment}, 4096},
}

TOPICS := [?]hub.Topic {
	{family = "polls.poll", policy = .Latest, ring = 4, perm = .Polls_Vote},
}

JOBS := [?]workers.Job {
	{"polls.close", time.Minute, close_due, nil},
}

@(private) votes := web.Limit{n = 10, window = time.Minute}
@(private) asks := web.Limit{n = 10, window = time.Minute}

@(private)
index :: proc(req: ^web.Request, res: ^web.Response) {
	all := make([dynamic]m.Summary, context.temp_allocator)
	if err := polls.summaries(&all); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, "Go/No-go", "/polls", "Quick polls.", polls_views.index(all[:]))
}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	v := web.viewer(req)
	p, err := polls.poll(id, v)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, p.question, "/polls", "A poll.", polls_views.page(p, v.id), live = {topic(id)})
}

@(private)
results :: proc(req: ^web.Request, res: ^web.Response) {
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	v := web.viewer(req)
	p, err := polls.poll(id, v)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.respond_html(res, polls_views.results(p, v.id))
}

@(private)
topic :: proc(id: i64) -> string { return fmt.tprintf("polls.poll:%d", id) }

// The element it changes, the `.Latest` key.
@(private)
say_changed :: proc(id: i64) {
	hub.publish(topic(id), polls_views.changed(id), 0, fmt.tprintf("poll-stale-%d", id))
}

// Closed, so everyone who voted hears of it. Off the loop: the job's thread or the query pool.
@(private)
tell :: proc(c: m.Closed) {
	say_changed(c.id)
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `“`)
	html.esc(&b, c.question)
	html.w(&b, `” has closed`)
	for who in c.voters { notify_web.send_now(who, "polls.closed", fmt.tprintf("/polls/%d", c.id), strings.to_string(b)) }
}

@(private)
close_due :: proc() {
	closed, err := polls.close_due()
	for c in closed { tell(c) }
	if err != .None { workers.fail("the sweep stopped: %v", err) }
}

// ---- changes ---------------------------------------------------------------------------------------

@(private)
Kind :: enum {
	Create,
	Vote,
	Close,
}

@(private)
Change :: struct {
	using scan: web.Scan,
	kind:       Kind,
	viewer:     authz.Viewer,
	poll:       i64,
	new:        m.New_Poll,
	options:    []i64,
	result:     m.Vote_Result,
	now:        m.Poll,
	err:        m.Error,
}

@(private)
limited :: proc(req: ^web.Request, res: ^web.Response, l: ^web.Limit) -> bool {
	ok, retry := web.limit_hit(l, web.viewer(req).id)
	if !ok { web.respond_limited(res, retry, "Too many at once: wait a moment.") }
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
	case .Create:
		s.poll, s.err = polls.create(s.new, s.viewer)
		return
	case .Vote:
		s.result, s.err = polls.vote(s.poll, s.options, s.viewer)
	case .Close:
		closed: m.Closed
		if closed, s.err = polls.close(s.poll, s.viewer); s.err == .None { tell(closed) }
	}
	if s.err == .None { s.now, s.err = polls.poll(s.poll, s.viewer) }
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
	href := fmt.tprintf("/polls/%d", s.poll)
	switch {
	case s.err != .None:
		web.respond_store_error(req, res, s.err)
	case s.kind == .Create:
		go_to(req, res, href)
	case s.kind == .Vote && s.result == .Already:
		web.respond_html(res, html.field_msg(false, "You have already voted, and a vote here is final."), .Conflict)
	case s.kind == .Vote && s.result == .Closed:
		web.respond_html(res, html.field_msg(false, "This poll has closed."), .Conflict)
	case:
		if s.kind == .Vote { say_changed(s.poll) }
		if web.header(req, "hx-request") != "true" {
			go_to(req, res, href)
			return
		}
		web.respond_html(res, polls_views.voted(s.now, s.viewer.id))
	}
}

@(private)
create :: proc(req: ^web.Request, res: ^web.Response) {
	if limited(req, res, &asks) { return }
	f := web.form(req)
	go_nogo := f["kind"] != "options"
	options := polls.GO_NOGO[:] if go_nogo else polls.split_options(f["options"])
	if problem := polls.check(f["question"], options); problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	s := start(req, res, .Create)
	if s == nil { return }
	s.new = {strings.trim_space(f["question"]), options, f["multiple"] != "" && !go_nogo, f["anonymous"] != "", polls.closes_at(f["closes"])}
	web.start_scan(req, res, s)
}

@(private)
vote :: proc(req: ^web.Request, res: ^web.Response) {
	if limited(req, res, &votes) { return }
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	values := web.form_values(req, "option")
	if len(values) == 0 || len(values) > polls.MAX_OPTIONS {
		web.respond_html(res, html.field_msg(false, "Choose an option."), .Unprocessable_Content)
		return
	}
	options := make([]i64, len(values), context.temp_allocator)
	for v, i in values {
		option, ook := web.parse_id(v)
		if !ook {
			web.not_found(req, res)
			return
		}
		options[i] = option
	}
	s := start(req, res, .Vote)
	if s == nil { return }
	s.poll, s.options = id, options
	web.start_scan(req, res, s)
}

@(private)
close :: proc(req: ^web.Request, res: ^web.Response) {
	if limited(req, res, &asks) { return }
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	s := start(req, res, .Close)
	if s == nil { return }
	s.poll = id
	web.start_scan(req, res, s)
}
