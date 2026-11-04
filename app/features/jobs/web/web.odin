package jobs_web

// ---- jobs: /admin/jobs (PLAN §15.4) ----------------------------------------------------------
//
// Every mounted job and its runs, live: `jobs.sync` reads the runs that changed each second into
// the store and publishes each one's row on `jobs.runs` (.Latest, keyed by the row's id), so a
// page upserts it and a viewer who arrives mid-run replays the latest row of each. An admin can
// run a job now and stop a run, each with a reason, audited; a run's log is a download. Admins
// only, from the LAN (§17.2, D41).

import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/web"
import "../../../platform/workers"
import notify_web "../../notify/web"
import jobs ".."
import m "../models"
import jobs_views "../views"
import audit_store "store:audit"

EXTS :: web.Exts{.Prompt, .Sse, .Upsert}

TOPIC :: "jobs.runs"

ROUTES := [?]web.Route {
	{.Get, "/admin/jobs", page, .Admin_Jobs, {.Private, .Lan_Only}, 0},
	{.Post, "/admin/jobs/run", run_now, .Admin_Jobs, {.Fragment, .Lan_Only, .Step_Up}, 256},
	{.Post, "/admin/jobs/cancel", cancel, .Admin_Jobs, {.Fragment, .Lan_Only, .Step_Up}, 256},
	{.Get, "/admin/jobs/runs/(%d+)/(%d+)/log", log, .Admin_Jobs, {.Fragment, .Lan_Only}, 0},
}

TOPICS := [?]hub.Topic {
	{family = TOPIC, policy = .Latest, perm = .Admin_Jobs, lan_only = true},
}

// Who hears of a failed run (§14.2): the identity's admins. Set by main, which alone reaches the
// identity; unset, nobody does.
admin_ids: proc(out: ^[dynamic]u64)

JOBS := [?]workers.Job {
	{"jobs.sync", time.Second, sync, nil},
}

// After the store's migration: this boot's id, and the runs an earlier one left behind.
init :: proc() {
	jobs.init()
}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	list := make([dynamic]jobs.Job_Row, context.temp_allocator)
	jobs.list(&list)
	runs := make([dynamic]m.Run_Row, context.temp_allocator)
	if err := jobs.recent(&runs); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Admin", "Jobs", "What runs on its own, and every run of it.")
	jobs_views.page(&b, list[:], runs[:])
	web.render_page(req, res, "Jobs", "/admin/jobs", "The jobs and their runs.", strings.to_string(b), live = {TOPIC})
}

// POST /admin/jobs/run: job (its id); the reason from the prompt.
@(private)
run_now :: proc(req: ^web.Request, res: ^web.Response) {
	job := web.form(req)["job"]
	reason, ok := web.prompt_reason(req, res)
	if !ok { return }
	id, queued := jobs.run_now(job)
	if !queued {
		web.respond_html(res, html.toast("error", "No such job, or too many runs are waiting.", true), .Unprocessable_Content)
		return
	}
	acted(req, "jobs.run_now", id, reason, strings.concatenate({"job=", job, " boot=", i64_text(jobs.boot())}, context.temp_allocator))
	web.respond_html(res, html.toast("ok", "Queued: it starts within a second.", true))
}

// POST /admin/jobs/cancel: run (`<boot>-<id>`); the reason from the prompt.
@(private)
cancel :: proc(req: ^web.Request, res: ^web.Response) {
	boot, id, found := run_key(web.form(req)["run"])
	if !found {
		web.not_found(req, res)
		return
	}
	reason, ok := web.prompt_reason(req, res)
	if !ok { return }
	if !jobs.cancel(boot, id) {
		web.respond_html(res, html.toast("error", "That run has ended.", true), .Conflict)
		return
	}
	acted(req, "jobs.cancel", id, reason, strings.concatenate({"boot=", i64_text(boot)}, context.temp_allocator))
	web.respond_html(res, html.toast("ok", "Asked to stop.", true))
}

@(private)
log :: proc(req: ^web.Request, res: ^web.Response) {
	boot, bok := web.parse_id(req.url_params[0])
	id, iok := web.parse_id(req.url_params[1])
	if !bok || !iok {
		web.not_found(req, res)
		return
	}
	r, err := jobs.run(boot, id)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	buf: [64]byte
	name := strings.concatenate({`attachment; filename="`, safe_name(r.job), "-", strconv.write_int(buf[:], id, 10), `.log"`}, context.temp_allocator)
	web.set_header(res, "content-disposition", name)
	web.respond_plain(res, jobs_views.log_text(r))
}

// The job's thread: the changed runs into the store, and each one's row to the live pages.
@(private)
sync :: proc() {
	rows, err := jobs.sync()
	if err != .None { return }
	for r in rows {
		b := strings.builder_make(context.temp_allocator)
		jobs_views.update(&b, r)
		key := strings.concatenate({"run-", i64_text(r.boot), "-", i64_text(r.id)}, context.temp_allocator)
		hub.publish(TOPIC, strings.to_string(b), 0, key)
		if r.state == "failed" { tell_admins(r) }
	}
}

// A failed run, once (a run's row comes round again only while it is live), in every admin's Inbox.
@(private)
tell_admins :: proc(r: m.Run_Row) {
	if admin_ids == nil { return }
	who := make([dynamic]u64, 0, 4, context.temp_allocator)
	admin_ids(&who)
	line := jobs_views.failed_line(r)
	for id in who { notify_web.send_now(id, "jobs.failed", "/admin/jobs", line) }
}

// A row's job id as a file name: letters, digits, `.`, `-` and `_` (a header is no place for
// anything else, whatever the table holds: M5-12).
@(private)
safe_name :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for c in transmute([]byte)s {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '-', '_': strings.write_byte(&b, c)
		case: strings.write_byte(&b, '_')
		}
	}
	return strings.to_string(b)
}

// `<boot>-<id>`, both digits.
@(private)
run_key :: proc(s: string) -> (boot, id: i64, ok: bool) {
	dash := strings.index_byte(s, '-')
	if dash <= 0 { return }
	boot, ok = web.parse_id(s[:dash])
	if !ok { return }
	id, ok = web.parse_id(s[dash + 1:])
	return
}

@(private)
acted :: proc(req: ^web.Request, action: string, run: i64, reason, meta: string) {
	c := web.ctx()
	buf: [16]byte
	audit_store.append({i64(c.viewer.id), c.viewer.name, web.client_id(c.client, buf[:])}, action, {"run", run}, reason, meta)
}

@(private)
i64_text :: proc(n: i64) -> string {
	buf := make([]byte, 24, context.temp_allocator)
	return strconv.write_int(buf, n, 10)
}
