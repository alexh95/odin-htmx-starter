package bot_web

// ---- bot: routes, the backend switch and the two deliveries (PLAN §14.3, D31, D8) ----------
//
// An ask is answered as a stream on the asker's own connection: SSE (the four frames as
// events, `hx:release` after the first words) or multipart (the four as parts, plus the
// title and the usage), chosen by the form. The backend is `bot_web`'s switch (only the
// mock until M7's llama), its events arriving on the stream's loop through the sink.
// Members keep conversations, ask one at a time and 30 an hour; guests get the mock, 5 an
// hour per client, and nothing is kept (Q20). Stop, and a browser that goes away, cancel.

import "base:runtime"
import "core:fmt"
import "core:nbio"
import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/env"
import "../../../platform/guard"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/obs"
import "../../../platform/store"
import "../../../platform/stream"
import "../../../platform/web"
import bot ".."
import bot_backend_llama "../backend_llama"
import bot_backend_mock "../backend_mock"
import m "../models"
import bot_views "../views"
import audit_store "store:audit"

EXTS :: web.Exts{.Sse, .Multipart, .Pending}

ROUTES := [?]web.Route {
	{.Get, "/bot", index, .Bot_Use, {.Private}, 0},
	{.Post, "/bot/c", new_conversation, .Account_Self, {.Fragment}, 0},
	{.Get, "/bot/c/(%d+)", conversation_page, .Account_Self, {.Private}, 0},
	{.Post, "/bot/c/(%d+)/ask", ask_member, .Account_Self, {.Stream, .Fragment}, ASK_CAP},
	{.Post, "/bot/ask", ask_guest, .Bot_Use, {.Stream, .Fragment}, ASK_CAP},
	{.Post, "/bot/gen/(%d+)/stop", stop, .Bot_Use, {.Fragment}, 0},
}

// /admin/bot, mounted where there is an admin to reach it.
ADMIN_ROUTES := [?]web.Route {
	{.Get, "/admin/bot", admin_page, .Admin_Modules, {.Private, .Lan_Only}, 0},
	{.Post, "/admin/bot/default", admin_default, .Admin_Modules, {.Fragment, .Lan_Only}, 0},
}

// bot.health: the badge, on a member's bot pages' #live, published when the llama server's state
// changes. A guest's badge is the mock's, which never does. bot.ask: chat's questions, server-side.
TOPICS := [?]hub.Topic {
	{family = "bot.health", policy = .Latest, perm = .Bot_Llama},
	{family = "bot.ask", policy = .Queue, perm = .Bot_Use, deliver = room_ask}, // room.odin
}

// A question is 4,000 runes; URL-encoded, a rune can take 12 bytes.
ASK_CAP :: 64 * 1024

@(private) members_hour := web.Limit{window = time.Hour}
// New conversations, per member: each is kept, so making them is limited too (M2-06).
@(private) starts := web.Limit{n = 10, window = time.Minute}
@(private) guests_hour := web.Limit{window = time.Hour}

// The generations in flight: whose each is (Stop's check), and how many each member has.
@(private)
gens: struct {
	mu:     guard.Mutex,
	owner:  map[m.Bot_Gen_Id]Who,
	active: map[u64]int,
	seq:    u64,
}

@(private)
Who :: struct {
	member:  bool,
	key:     u64, // a member's id, or a guest's client key
	backend: bot.Backend, // the generation's: the default may change while it runs
}

init :: proc() {
	bot.init()
	bot_backend_mock.init()
	bot_backend_llama.init()
	if bot.default_backend() == .Llama && !bot_backend_llama.configured() {
		env.problem("BOT_BACKEND=llama: BOT_LLAMA_URL is required; no host or port is assumed (§14.3)")
	}
	members_hour.n = bot.member_per_hour()
	guests_hour.n = bot.guest_per_hour()
	gens.owner = make(map[m.Bot_Gen_Id]Who, heap())
	gens.active = make(map[u64]int, heap())
	report(health(.Llama) if bot_backend_llama.configured() else m.Bot_Health{state = .Mock})
	obs.set_health_link("bot", "/admin/bot")
}

// After the loops run: the llama server's health probe.
start :: proc() {
	bot_backend_llama.start_probe(proc(h: m.Bot_Health) {
		report(h)
		hub.publish("bot.health", bot_views.health_frame(h))
	})
}

// `main`'s drain: a generation stops before the loops do (§8.7).
drain :: proc() { bot_backend_llama.drain() }

// The status page's line: an optional backend is degraded at worst, and never fails readiness
// (13 §5.3); the mock is always there behind it.
@(private)
report :: proc(h: m.Bot_Health) {
	state := obs.State.Ok
	line: string
	switch h.state {
	case .Mock:     line = "the mock answers"
	case .Ready:    line = "llama.cpp is ready"
	case .Sleeping: line = "llama.cpp is asleep and wakes on a question"
	case .Loading:
		state = .Degraded
		line = "llama.cpp is loading its model"
	case .Offline:
		state = .Degraded
		line = "llama.cpp isn't answering: the mock does"
	}
	// obs keeps the string for good: one small line per change of state or of the default.
	obs.set_health("bot", state, fmt.aprintf("default %s; %s", bot.BACKENDS[bot.default_backend()], line, allocator = heap()))
}

// ---- the backend switch (D8; LC §4) ----------------------------------------------------------

// Among the healthy, per request: a guest always gets the mock, and a member the default unless
// they asked for the other. A backend that can't answer now gives way to the mock.
@(private)
backend_of :: proc(v: authz.Viewer, asked := "") -> bot.Backend {
	if !may_use_llama(v) { return .Mock }
	pick := bot.default_backend()
	for name, b in bot.BACKENDS {
		if name == asked { pick = b }
	}
	return pick if healthy(pick) else .Mock
}

@(private)
may_use_llama :: proc(v: authz.Viewer) -> bool {
	return bot_backend_llama.configured() && v.id != 0 && authz.can(v, .Bot_Llama)
}

@(private)
healthy :: proc(b: bot.Backend) -> bool {
	state := health(b).state
	return state == .Ready || state == .Sleeping || state == .Mock // a sleeping server wakes on a question
}

// The badge a viewer's page shows: the llama server's to whoever may use it.
@(private)
shown :: proc(v: authz.Viewer) -> m.Bot_Health {
	return health(.Llama if may_use_llama(v) else .Mock)
}

@(private)
health :: proc(b: bot.Backend) -> m.Bot_Health {
	switch b {
	case .Mock: return bot_backend_mock.health()
	case .Llama: return bot_backend_llama.health()
	}
	return {}
}

@(private)
generate :: proc(b: bot.Backend, req: m.Bot_Request, sink: m.Bot_Sink) -> m.Bot_Gen_Id {
	switch b {
	case .Mock: return bot_backend_mock.start(req, sink)
	case .Llama: return bot_backend_llama.start(req, sink)
	}
	return 0
}

@(private)
cancel :: proc(b: bot.Backend, id: m.Bot_Gen_Id) {
	switch b {
	case .Mock: bot_backend_mock.cancel(id)
	case .Llama: bot_backend_llama.cancel(id)
	}
}

// ---- pages -------------------------------------------------------------------------------

@(private)
index :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	b := backend_of(v)
	web.impl(res, "bot.backend", bot.BACKENDS[b])
	if !authz.can(v, .Account_Self) {
		web.render_page(req, res, "Bot", "/bot", "Ask the house assistant.", bot_views.guest_page(shown(v), bot.guest_per_hour()))
		return
	}
	convs := make([dynamic]m.Conversation, context.temp_allocator)
	if err := bot.conversations(v.id, &convs); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, "Bot", "/bot", "Ask the house assistant.", bot_views.index_page(convs[:], shown(v)), live = {"bot.health"})
}

@(private)
conversation_page :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	c, err := bot.conversation(v.id, id)
	turns := make([dynamic]m.Turn, context.temp_allocator)
	if err == .None { err = bot.turns(v.id, id, &turns) }
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := backend_of(v)
	web.impl(res, "bot.backend", bot.BACKENDS[b])
	used := members_hour.n - remaining(&members_hour, v.id)
	web.render_page(req, res, fmt.tprintf("%s · Bot", c.title), "/bot", "A conversation with the house assistant.",
		bot_views.conversation_page(c, turns[:], shown(v), used, members_hour.n, b, may_use_llama(v) && healthy(.Llama)), live = {"bot.health"})
}

@(private)
Starting :: struct {
	using start: m.Start,
	deferred:    web.Deferred,
}

@(private)
new_conversation :: proc(req: ^web.Request, res: ^web.Response) {
	if ok, retry := web.limit_hit(&starts, web.viewer(req).id); !ok {
		web.respond_limited(res, retry, html.toast("error", "That's enough new conversations for a minute.", false))
		return
	}
	op := store.new_op(Starting, 64)
	op.owner = web.viewer(req).id
	op.title = "New conversation"
	op.done = proc(o: ^store.Op) {
		op := (^Starting)(o)
		defer store.free_op(op)
		res := web.resume(&op.deferred)
		if res == nil { return }
		if op.err != .None {
			web.respond_store_error(web.request(&op.deferred), res, op.err)
		} else {
			// htmx follows HX-Redirect; a plain form, the 303.
			to := fmt.tprintf("/bot/c/%d", op.result.id)
			if web.is_htmx(web.request(&op.deferred)) {
				web.set_header(res, "hx-redirect", to)
				web.respond_status(res, .No_Content)
			} else {
				web.set_header(res, "location", to)
				web.respond_status(res, .See_Other)
			}
		}
		web.finish(&op.deferred, res)
	}
	web.defer_response(req, res, &op.deferred)
	if !bot.start(op) {
		if r := web.resume(&op.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&op.deferred, r)
		}
		store.free_op(op)
	}
}

// ---- asking -------------------------------------------------------------------------------

// One answer in flight, on its stream's loop, from the ask to the backend's Bot_Done.
@(private)
Asking :: struct {
	conn:      ^stream.Conn, // nil once the stream ended
	multipart: bool,
	backend:   bot.Backend,
	gen:       m.Bot_Gen_Id,
	mid:       string, // heap
	who:       Who,
	conv:      i64,    // 0 for a guest's
	answer:    strings.Builder,
	released:  bool,
	used:      int,    // the asker's count this hour, for multipart's #usage
	title:     string, // heap; a conversation's new title, for multipart's #conv-title
	let_go:    bool,   // release ran
}

@(private)
ask_member :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	id, ok := web.parse_id(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	c, err := bot.conversation(v.id, id)
	turns := make([dynamic]m.Turn, context.temp_allocator)
	if err == .None { err = bot.turns(v.id, id, &turns) }
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	ask(req, res, Who{member = true, key = v.id}, c, turns[:])
}

@(private)
ask_guest :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	who := Who{member = true, key = v.id} if v.id != 0 else Who{member = false, key = web.client_key(web.ctx().client)}
	ask(req, res, who, {}, nil)
}

@(private)
ask :: proc(req: ^web.Request, res: ^web.Response, who: Who, c: m.Conversation, turns: []m.Turn) {
	f := web.form(req)
	q, problem := bot.check_question(f["q"])
	if problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	limit := &members_hour if who.member else &guests_hour
	if !admit(who) {
		web.respond_limited(res, 5 * time.Second, html.toast("error", "One answer at a time: wait for this one, or stop it.", false))
		return
	}
	if ok, retry := web.limit_hit(limit, who.key); !ok {
		leave(who)
		web.respond_limited(res, retry, html.toast("error", fmt.tprintf("That's %d questions this hour; the next one opens in %d minutes.", limit.n, max(1, int(retry / time.Minute))), false))
		return
	}
	v := web.viewer(req)
	backend := backend_of(v, f["backend"])
	web.impl(res, "bot.backend", bot.BACKENDS[backend])

	a := new(Asking, heap())
	a.multipart = f["delivery"] == "multipart"
	a.backend, a.who, a.conv = backend, who, c.id
	a.answer = strings.builder_make(heap())
	a.used = limit.n - remaining(limit, who.key)
	guard.lock(&gens.mu)
	gens.seq += 1
	a.gen = m.Bot_Gen_Id(gens.seq)
	gens.owner[a.gen] = {who.member, who.key, backend}
	guard.unlock(&gens.mu)
	a.mid = fmt.aprintf("g%d", u64(a.gen), allocator = heap())

	if a.multipart {
		a.conn = stream.multipart_begin(res, .Mixed, a, on_close)
	} else {
		a.conn = stream.sse_begin(res, a, on_close)
	}
	if a.conn == nil { // admission answered 503 or 429
		done(a)
		return
	}
	if c.id != 0 {
		title := bot.title_of(q) if len(turns) == 0 else ""
		keep(c.id, who.key, .User, q, {}, title)
		a.title = strings.clone(title, heap())
	}
	send(a, bot_views.shell(q, a.mid, a.gen))
	sink := m.Bot_Sink{user = a, loop = nbio.current_thread_event_loop(), gen = a.gen, on_event = on_event}
	generate(backend, bot.request(c.id, who.key, turns, q), sink)
}

// The backend's events, on this stream's loop.
@(private)
on_event :: proc(user: rawptr, _: m.Bot_Gen_Id, ev: m.Bot_Event) {
	a := (^Asking)(user)
	switch e in ev {
	case m.Bot_Token:
		if strings.builder_len(a.answer) + len(e.text) <= bot.MAX_ANSWER { strings.write_string(&a.answer, e.text) }
		send(a, bot_views.piece(a.mid, e.text))
		if !a.released && !a.multipart && a.conn != nil {
			a.released = true
			stream.write(a.conn, stream.sse_event("", "hx:release", ""))
		}
	case m.Bot_Queued:
		send(a, bot_views.queued(a.mid, e.position))
	case m.Bot_Error:
		release(a)
		send(a, bot_views.failed(a.mid, e.message))
		done(a)
	case m.Bot_Done:
		release(a)
		text := strings.to_string(a.answer)
		send(a, bot_views.final(a.mid, text, e))
		if a.multipart && a.conn != nil {
			b := strings.builder_make(context.temp_allocator)
			bot_views.usage(&b, a.used, (&members_hour if a.who.member else &guests_hour).n)
			stream.multipart_part(a.conn, strings.to_string(b), {{"HX-Target", "#usage"}, {"HX-Swap", "outerHTML"}})
			if a.title != "" && a.conn != nil { // the part above may have closed a too-slow stream
				t := strings.builder_make(context.temp_allocator)
				html.esc(&t, a.title)
				stream.multipart_part(a.conn, strings.to_string(t), {{"HX-Target", "#conv-title"}, {"HX-Swap", "innerHTML"}})
			}
		}
		if a.conv != 0 { keep(a.conv, a.who.key, .Assistant, text, e, "") }
		done(a)
	}
}

// Writes a frame as the stream's kind: an unnamed SSE event, or a part.
@(private)
send :: proc(a: ^Asking, frame: string) {
	if a.conn == nil { return }
	if a.multipart {
		stream.multipart_part(a.conn, frame, nil)
	} else {
		stream.write(a.conn, stream.sse_event("", "", frame))
	}
}

// The answer is over: the stream ends (if it still runs), the member may ask again.
@(private)
done :: proc(a: ^Asking) {
	if c := a.conn; c != nil {
		a.conn = nil
		c.user = nil // its close, now or later, finds nothing to cancel
		if a.multipart { stream.multipart_end(c) } else { stream.end(c) }
	}
	release(a)
	delete(a.mid, heap())
	delete(a.title, heap())
	strings.builder_destroy(&a.answer)
	free(a, heap())
}

// The member may ask again, and the generation is no longer theirs to stop. The last
// event runs it before it renders anything: the mock has already let the generation go,
// so a crash there would otherwise keep the member's slot, and every later ask was a 429
// (M2-13).
@(private)
release :: proc(a: ^Asking) {
	if a.let_go { return }
	a.let_go = true
	guard.lock(&gens.mu)
	delete_key(&gens.owner, a.gen)
	guard.unlock(&gens.mu)
	leave(a.who)
}

// The browser went away: the generation is cancelled, and its Bot_Done frees the rest.
@(private)
on_close :: proc(c: ^stream.Conn) {
	a := (^Asking)(c.user)
	if a == nil { return }
	a.conn = nil
	cancel(a.backend, a.gen)
}

// POST /bot/gen/<gid>/stop: the asker's own generation only.
@(private)
stop :: proc(req: ^web.Request, res: ^web.Response) {
	id, ok := web.parse_digits(req.url_params[0])
	if !ok {
		web.not_found(req, res)
		return
	}
	v := web.viewer(req)
	me := Who{member = true, key = v.id} if v.id != 0 else Who{member = false, key = web.client_key(web.ctx().client)}
	guard.lock(&gens.mu)
	who, found := gens.owner[m.Bot_Gen_Id(id)]
	guard.unlock(&gens.mu)
	if found && who.member == me.member && who.key == me.key { cancel(who.backend, m.Bot_Gen_Id(id)) }
	web.respond_status(res, .No_Content)
}

// ---- /admin/bot ---------------------------------------------------------------------------------

@(private)
admin_page :: proc(req: ^web.Request, res: ^web.Response) {
	u, err := bot.usage()
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	llama := bot_backend_llama.configured()
	web.render_page(req, res, "Bot · Admin", "/admin/bot", "The bot's default backend.",
		bot_views.admin_page(bot.default_backend(), health(.Llama if llama else .Mock), llama, u), live = {"bot.health"})
}

// In memory, audited and gone at a restart (D8). `obs` carries it to /admin/modules' health row.
@(private)
admin_default :: proc(req: ^web.Request, res: ^web.Response) {
	llama := bot_backend_llama.configured()
	asked := web.form(req)["backend"]
	found := false
	pick: bot.Backend
	for name, b in bot.BACKENDS {
		if name == asked { pick, found = b, true }
	}
	if !found || (pick == .Llama && !llama) {
		web.respond_html(res, html.field_msg(false, "That backend isn't available."), .Unprocessable_Content)
		return
	}
	was := bot.default_backend()
	bot.set_default_backend(pick)
	if was != pick {
		c := web.ctx()
		buf: [16]byte
		audit_store.append({i64(c.viewer.id), c.viewer.name, web.client_id(c.client, buf[:])}, "bot.default", {"bot", 0}, "", fmt.tprintf("%s to %s", bot.BACKENDS[was], bot.BACKENDS[pick]))
		report(health(.Llama if llama else .Mock))
	}
	b := strings.builder_make(context.temp_allocator)
	bot_views.admin_panel(&b, pick, health(.Llama if llama else .Mock), llama)
	web.respond_html(res, strings.to_string(b))
}

// ---- one at a time, per member ------------------------------------------------------------

@(private)
admit :: proc(who: Who) -> bool {
	if !who.member { return true }
	guard.lock(&gens.mu)
	defer guard.unlock(&gens.mu)
	if gens.active[who.key] > 0 { return false }
	gens.active[who.key] += 1
	return true
}

@(private)
leave :: proc(who: Who) {
	if !who.member { return }
	guard.lock(&gens.mu)
	defer guard.unlock(&gens.mu)
	if n := gens.active[who.key]; n <= 1 { delete_key(&gens.active, who.key) } else { gens.active[who.key] = n - 1 }
}

// ---- keeping a member's turns ---------------------------------------------------------------

@(private)
keep :: proc(conv: i64, owner: u64, role: m.Bot_Role, text: string, stats: m.Bot_Done, title: string) {
	op := store.new_op(m.Append, 2 * len(text) + len(title))
	a := store.op_allocator(op)
	op.owner = owner
	op.turn = {conv = conv, role = role, text = strings.clone(text, a), stats = stats}
	op.title = strings.clone(title, a)
	op.done = proc(o: ^store.Op) { store.free_op(o) }
	if !bot.append_turn(op) { store.free_op(op) }
}

@(private)
remaining :: proc(l: ^web.Limit, key: u64) -> int {
	return web.limit_left(l, key)
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }
