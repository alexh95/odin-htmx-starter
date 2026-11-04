package notify_web

// ---- notify: routes, the member topic and send (PLAN §14.2, §6.2) -------------------------
//
// `send` is the one web-to-web import (§6.2): a producer (chat's mentions, the bot's
// late replies) calls notify_web.send(user, kind, ref, html), which stores the item
// and pushes it on notify.user:<id>, a member row: the layout's #live carries it on
// every page of theirs, so the log and every `.notify-count` follow at once.

import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/env"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/obs"
import "../../../platform/store"
import "../../../platform/web"
import "../../../platform/workers"
import notify ".."
import m "../models"
import notify_views "../views"

// notify.user rides the layout's #live (hx-sse) on every page of a member's.
EXTS :: web.Exts{.Sse}

ROUTES := [?]web.Route {
	{.Get, "/notify", page, .Account_Self, {.Private}, 0},
	{.Get, "/notify/list", list, .Account_Self, {.Fragment}, 0},
	{.Post, "/notify/read", read_all, .Account_Self, {.Fragment}, 0},
	{.Post, "/notify/mute", mute, .Account_Self, {.Fragment}, 256},
}

USER :: "notify.user"

TOPICS := [?]hub.Topic {
	{family = USER, policy = .Queue, member = true, perm = .Account_Self},
}

JOBS := [?]workers.Job {
	{"notify.prune", time.Hour, prune, nil},
}

// ---- send ------------------------------------------------------------------------------------

// Stores a notification for `user` and pushes it to them: `kind` is the producer's
// namespaced name, `ref` a path on this site ("" for none), `html` its line, escaped
// by the producer. `scope` is what a member may mute it by beside its kind ("chat.room:12").
// A muted one is dropped; a refused one (a bug in the producer) is logged and dropped.
send :: proc(user: u64, kind, ref, line: string, scope := "") {
	if !deliverable(user, kind, ref, line, scope) { return }
	op := store.new_op(m.Add, 2 * (len(kind) + len(ref) + len(line)))
	a := store.op_allocator(op)
	op.user = user
	op.kind, op.ref, op.html = strings.clone(kind, a), strings.clone(ref, a), strings.clone(line, a)
	op.done = sent
	if !notify.add(op) { store.free_op(op) }
}

// `send` from a thread with no loop to answer on (a job).
send_now :: proc(user: u64, kind, ref, line: string, scope := "") {
	if !deliverable(user, kind, ref, line, scope) { return }
	if it, unread, err := notify.add_now(user, kind, ref, line); err == .None {
		hub.publish(topic(user), notify_views.pushed(it, unread))
	}
}

@(private)
deliverable :: proc(user: u64, kind, ref, line, scope: string) -> bool {
	if why := notify.check(user, kind, ref, line); why != "" {
		if l, ok := obs.begin(.Warning, "notify", "refused"); ok {
			obs.str(&l, "kind", kind)
			obs.str(&l, "why", why)
			obs.end(&l)
		}
		return false
	}
	return !notify.muted(user, kind, scope)
}

// A button muting or unmuting `key` for `user`, as a producer's page offers it: "Mute <what>".
mute_button :: proc(user: u64, key, what: string) -> string {
	on := !notify.muted(user, key, "")
	b := strings.builder_make(context.temp_allocator)
	notify_views.mute_form(&b, key, on, strings.concatenate({"Mute " if on else "Unmute ", what}, context.temp_allocator))
	return strings.to_string(b)
}

@(private)
sent :: proc(o: ^store.Op) {
	op := (^m.Add)(o)
	defer store.free_op(op)
	if op.err != .None { return }
	hub.publish(topic(op.user), notify_views.pushed(op.result, op.unread))
}

topic :: proc(user: u64) -> string {
	return strings.concatenate({USER, ":", hub.member_key({id = user})}, context.temp_allocator)
}

// ---- pages ----------------------------------------------------------------------------------

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	items := make([dynamic]m.Item, context.temp_allocator)
	if err := notify.list(v.id, &items); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	muted_keys := make([dynamic]string, context.temp_allocator)
	if err := notify.mutes(v.id, &muted_keys); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, "Inbox", "/notify", "Your notifications.", notify_views.page(items[:], notify.unread(v.id), muted_keys[:]))
}

// The log's items: what a resync refetches.
@(private)
list :: proc(req: ^web.Request, res: ^web.Response) {
	items := make([dynamic]m.Item, context.temp_allocator)
	if err := notify.list(web.viewer(req).id, &items); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	notify_views.items(&b, items[:])
	web.respond_html(res, strings.to_string(b))
}

// Marks everything read: the log again, and every count to 0.
@(private)
read_all :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	if ok, retry := web.limit_hit(&writes, v.id); !ok {
		web.respond_limited(res, retry, "")
		return
	}
	if err := notify.mark_read(v.id); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	items := make([dynamic]m.Item, context.temp_allocator)
	_ = notify.list(v.id, &items)
	b := strings.builder_make(context.temp_allocator)
	notify_views.items(&b, items[:])
	html.w(&b, `<span hx-swap-oob="innerHTML:.notify-count">0</span>`)
	web.respond_html(res, strings.to_string(b))
}

// A member mutes or unmutes a kind or a producer's scope; the page shows it on its next render.
@(private)
mute :: proc(req: ^web.Request, res: ^web.Response) {
	if ok, retry := web.limit_hit(&writes, web.viewer(req).id); !ok {
		web.respond_limited(res, retry, "")
		return
	}
	f := web.form(req)
	key := f["key"]
	if !notify.valid_key(key) {
		web.respond_html(res, html.toast("error", "That can't be muted.", true), .Unprocessable_Content)
		return
	}
	if err := notify.mute(web.viewer(req).id, key, f["on"] == "1"); err == .Constraint {
		web.respond_html(res, html.toast("error", "That's as many mutes as you can have.", true), .Unprocessable_Content)
		return
	} else if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.set_header(res, "hx-refresh", "true")
	web.respond_status(res, .No_Content)
}

// A producer took this back: its items go from every Inbox, with what they quoted.
retract :: proc(ref: string) { _ = notify.retract(ref) }

@(private) writes := web.Limit{window = time.Minute} // n: NOTIFY_WRITES_PER_MINUTE

ENV := [?]env.Row {
	{name = "NOTIFY_WRITES_PER_MINUTE", kind = .Int, def = "30", doc = "mutes and Mark read a member may press in a minute"},
}

// At boot.
init :: proc() {
	env.record("NOTIFY_", ENV[:])
	writes.n = env.int_("NOTIFY_WRITES_PER_MINUTE")
}

// The home page's card: a member's count and newest few; a guest's nothing.
home_card :: proc(b: ^strings.Builder, v: authz.Viewer) {
	if !authz.can(v, .Account_Self) { return }
	items := make([dynamic]m.Item, context.temp_allocator)
	_ = notify.list(v.id, &items)
	notify_views.card(b, items[:], notify.unread(v.id))
}

@(private)
prune :: proc() {
	if n := notify.prune(); n > 0 {
		if l, ok := obs.begin(.Debug, "notify", "pruned"); ok {
			obs.num(&l, "n", i64(n))
			obs.end(&l)
		}
	}
}
