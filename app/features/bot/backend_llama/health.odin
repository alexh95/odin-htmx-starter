package bot_backend_llama

// ---- the server's health (PLAN §14.3) ----------------------------------------------------------
//
// A thread of its own reads /health and /props every BOT_LLAMA_PROBE, on an event loop of its own
// through the one client: it can wait out a dead host without holding a server loop or the
// scheduler's other jobs. 503 is Loading, /props's is_sleeping Sleeping, nothing at all Offline.
// `/props` also gives the slots, unless BOT_CONCURRENCY fixed them. A change reaches `on_change`.

import "core:encoding/json"
import "core:nbio"
import "core:strings"
import "core:thread"
import "core:time"

import "../../../platform/env"
import "../../../platform/guard"
import sc "../../../platform/stream/client"
import "../../../platform/sys"
import "../../../platform/web"
import m "../models"

@(private) PROBE_WAIT :: 3 * time.Second
@(private) MAX_REPLY :: 64 * 1024

@(private)
seen: struct {
	mu:        guard.Mutex,
	state:     m.Bot_Health_State,
	slots:     int,
	model:     string, // heap
	on_change: proc(h: m.Bot_Health),
}

health :: proc(allocator := context.temp_allocator) -> m.Bot_Health {
	guard.lock(&seen.mu)
	h := m.Bot_Health{state = seen.state, slots_total = seen.slots, model = strings.clone(seen.model, allocator)}
	guard.unlock(&seen.mu)
	guard.lock(&st.mu)
	h.slots_busy, h.queued = st.busy, len(st.queue)
	if h.slots_total == 0 { h.slots_total = st.limit }
	guard.unlock(&st.mu)
	return h
}

// After the loops run. `on_change` runs on the probe's thread.
start_probe :: proc(on_change: proc(h: m.Bot_Health)) {
	seen.on_change = on_change
	if !st.configured { return }
	thread.create_and_start(probe_loop, self_cleanup = true)
}

@(private)
probe_loop :: proc() {
	guard.thread_init()
	if nbio.acquire_thread_event_loop() != nil { return }
	defer nbio.release_thread_event_loop()
	every := env.duration("BOT_LLAMA_PROBE")
	for !web.is_closing() {
		if !guard.call(proc(_: rawptr) { probe() }, nil) { update(.Offline, 0, "") }
		free_all(context.temp_allocator)
		for waited := time.Duration(0); waited < every && !web.is_closing(); waited += 50 * time.Millisecond {
			time.sleep(50 * time.Millisecond)
		}
	}
}

@(private)
Reply :: struct {
	conn:   sc.Conn,
	body:   [dynamic]byte,
	done:   bool,
	why:    sc.End,
	status: int,
}

// One GET, waited for on this thread's own loop.
@(private)
get :: proc(path: string, r: ^Reply) {
	r^ = {}
	r.body = make([dynamic]byte, context.temp_allocator)
	r.conn.user = r
	r.conn.on_body = proc(c: ^sc.Conn, data: []byte) {
		r := (^Reply)(c.user)
		if len(r.body) + len(data) <= MAX_REPLY { append(&r.body, ..data) }
	}
	r.conn.on_close = proc(c: ^sc.Conn, why: sc.End) {
		r := (^Reply)(c.user)
		r.done, r.why, r.status = true, why, c.head.status
	}
	guard.lock(&st.mu)
	ep := st.ep
	guard.unlock(&st.mu)
	extra := strings.concatenate({st.auth, "Connection: close\r\n"}, context.temp_allocator)
	sc.open(&r.conn, ep, sc.request("GET", st.host, path, extra), .Body, CONNECT)
	t0 := sys.mono_ns()
	for !r.done {
		_ = nbio.tick(50 * time.Millisecond)
		if !r.done && sys.mono_ns() - t0 > i64(PROBE_WAIT) { sc.close(&r.conn) }
	}
	sc.destroy(&r.conn)
}

@(private)
probe :: proc() {
	resolve() // a name's address may have moved, or not have been there at boot

	state := m.Bot_Health_State.Offline
	slots := 0
	model := ""
	r: Reply
	guard.lock(&st.mu)
	known := st.resolved
	guard.unlock(&st.mu)
	if known {
		get("/health", &r)
		switch {
		case r.why == .Done && r.status == 200:
			state = .Ready
			get("/props", &r)
			if r.why == .Done && r.status == 200 {
				sleeping: bool
				slots, sleeping, model = read_props(string(r.body[:]))
				if sleeping { state = .Sleeping }
			} else if r.why == .Refused && r.status == 503 {
				state = .Loading
			} else {
				state = .Offline // a key it refuses is as good as no server
			}
		case r.why == .Refused && r.status == 503:
			state = .Loading
		}
	}
	update(state, slots, model)
}

// `/props`, for what it says of the slots and the model. A build without a field leaves it zero.
read_props :: proc(text: string) -> (slots: int, sleeping: bool, model: string) {
	if !shallow(text) { return }
	parsed, err := json.parse_string(text, .JSON, true, context.temp_allocator)
	if err != nil { return }
	root, ok := parsed.(json.Object)
	if !ok { return }
	if n, is_n := root["total_slots"].(json.Integer); is_n { slots = int(n) }
	if b, is_b := root["is_sleeping"].(json.Boolean); is_b { sleeping = b }
	if p, is_s := root["model_path"].(json.String); is_s {
		model = p[max(strings.last_index_any(p, `/\`) + 1, 0):]
	}
	return
}

@(private)
update :: proc(state: m.Bot_Health_State, slots: int, model: string) {
	if slots > 0 && !st.fixed {
		guard.lock(&st.mu)
		st.limit = slots
		guard.unlock(&st.mu)
		pump()
	}
	guard.lock(&seen.mu)
	changed := state != seen.state || (model != "" && model != seen.model) || (slots > 0 && slots != seen.slots)
	seen.state = state
	if slots > 0 { seen.slots = slots }
	if model != "" && model != seen.model {
		delete(seen.model, heap())
		seen.model = strings.clone(model, heap())
	}
	guard.unlock(&seen.mu)
	if changed && seen.on_change != nil { seen.on_change(health()) }
}
