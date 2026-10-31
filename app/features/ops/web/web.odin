package ops_web

// ---- ops: /admin/ops and its 1 Hz panel (PLAN §15.4, D36, D8) --------------------------------
//
// One job, once a second, reads the process's numbers (obs's registry, the streams, the
// hub, the loops), renders the panel's cards once out of band and publishes them on
// ops.panel (.Sample: a viewer still taking the last one skips this one). The page picks its
// refresh per request (`?mode=`): the topic on its #live (SSE, the default), a poll of the
// kept render with its tag (304 until a new sample), or a multipart stream of its own on the
// topic. Admins only, from the LAN (§17).

import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"

import "../../../platform/hub"
import "../../../platform/obs"
import "../../../platform/stream"
import "../../../platform/sys"
import "../../../platform/web"
import "../../../platform/workers"
import ops ".."
import "../../../platform/store"
import ops_views "../views"

EXTS :: web.Exts{.Sse, .Ptag, .Multipart}

ROUTES := [?]web.Route {
	{.Get, "/admin/ops", page, .Admin_Ops, {.Private, .Lan_Only}, 0},
	{.Get, "/admin/ops/panel", panel, .Admin_Ops, {.Fragment, .Lan_Only}, 0},
	{.Get, "/admin/ops/parts", parts, .Admin_Ops, {.Stream, .Fragment, .Lan_Only}, 0},
}

PANEL :: "ops.panel"

TOPICS := [?]hub.Topic {
	{family = PANEL, policy = .Sample, perm = .Admin_Ops, lan_only = true},
}

JOBS := [?]workers.Job {
	{"ops.sample", time.Second, sample, nil},
}

init :: proc() {
	ops.init()
}

// ---- the job ---------------------------------------------------------------------------------

// Writes the stores queued for no one and lost (audit's entries, M4-04), since boot.
@(private)
drops :: proc() -> (n: u64) {
	for d in store.every_drops() { n += sync.atomic_load(&d.n) }
	return
}

@(private)
sample :: proc() {
	_, seq := ops.record(reading())
	samples := make([dynamic]ops.Sample, 0, ops.HISTORY, context.temp_allocator)
	_ = ops.history(&samples)
	modules := make([dynamic]ops.Module, context.temp_allocator)
	ops.modules(&modules)
	b := strings.builder_make(context.temp_allocator)
	ops_views.cards(&b, samples[:], modules[:], true)
	html := strings.to_string(b)
	ops.keep_panel(html, seq)
	hub.publish(PANEL, html)
}

// The process now, as a sample records it.
@(private)
reading :: proc() -> ops.Sample {
	n := hub.numbers()
	_, age := obs.oldest_tick()
	mem, has_store := obs.store_memory()
	return {
		at_ns          = sys.now_unix_ns(),
		requests       = obs.requests_total(),
		streams        = stream.open_total(),
		queued         = stream.queued_total(),
		published      = n.published,
		dropped        = n.dropped,
		resyncs        = n.resyncs,
		rss            = sys.rss_bytes(),
		loops          = int(obs.loops),
		oldest_tick_ms = int(age / 1e6),
		store          = mem,
		has_store      = has_store,
		drops          = drops(),
		has_drops      = len(store.every_drops()) > 0,
	}
}

// ---- the page and its refreshes -----------------------------------------------------------------

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	mode := ops_views.Mode.Sse
	switch web.query_get(req, "mode") {
	case "poll":      mode = .Poll
	case "multipart": mode = .Multipart
	}
	web.impl(res, "ops.mode", ops_views.MODES[mode].name)
	samples := make([dynamic]ops.Sample, 0, ops.HISTORY, context.temp_allocator)
	seq := ops.history(&samples)
	// Before the first sample, a reading of its own: the panel's swaps fill only the cards the
	// page has, so a page without the Store card would never get one.
	if len(samples) == 0 { append(&samples, reading()) }
	modules := make([dynamic]ops.Module, context.temp_allocator)
	ops.modules(&modules)
	limits := make([dynamic]ops.Limit, context.temp_allocator)
	ops.limits(&limits)
	wiring := ""
	live: []string
	switch mode {
	case .Sse:
		live = {PANEL}
	case .Poll:
		buf: [24]byte
		wiring = strings.concatenate({` hx-get="/admin/ops/panel" hx-trigger="every 1s" hx-swap="none" hx-ptag="`, strconv.write_uint(buf[:], seq, 10), `"`}, context.temp_allocator)
	case .Multipart:
		wiring = ` hx-multipart:connect="/admin/ops/parts" hx-swap="none"`
	}
	web.render_page(req, res, "Ops", "/admin/ops", "What the process is doing.",
		ops_views.page(samples[:], modules[:], limits[:], ops.last_crash(), mode, wiring), live = live)
}

// The kept render, unless the poller has it (HX-PTag: the sample it came from).
@(private)
panel :: proc(req: ^web.Request, res: ^web.Response) {
	html, tag := ops.panel()
	if have, ok := web.parse_digits(web.header(req, "hx-ptag")); ok && u64(have) == tag {
		web.respond_status(res, .Not_Modified)
		return
	}
	buf: [24]byte
	web.set_header(res, "hx-ptag", strconv.write_uint(buf[:], tag, 10))
	web.respond_html(res, html)
}

// A multipart stream on the topic: the kept render first, then every new one.
@(private)
parts :: proc(req: ^web.Request, res: ^web.Response) {
	c := stream.multipart_begin(res, .Mixed, nil, proc(c: ^stream.Conn) { hub.unsubscribe((^hub.Sub)(c.user)) })
	if c == nil { return }
	c.user = hub.subscribe(c, {PANEL}, web.ctx().viewer)
	if html, _ := ops.panel(); html != "" { stream.multipart_part(c, html, nil) }
}
