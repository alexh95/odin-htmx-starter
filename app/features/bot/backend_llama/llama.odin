package bot_backend_llama

// ---- the llama.cpp binding (PLAN §14.3, D31) ---------------------------------------------------
//
// POST {BOT_LLAMA_URL}/v1/chat/completions with stream:true, on platform/stream/client, on the
// loop of the stream that asked: it never blocks, so it needs no pool of its own. Tokens are
// coalesced to at most 20 events a second, as the mock's are. The model's server takes a fixed
// number of generations at once (its slots, or BOT_CONCURRENCY), counted across every loop: past
// that a generation queues, first come first served, and hears Bot_Queued until a slot frees.
//
// A generation lives on the loop that started it. `cancel` from any thread is posted there and
// closes the socket, which is what stops llama.cpp's generation. Whatever ends a generation, its
// sink hears one last event: Bot_Done, or Bot_Error when nothing had been said.
//
// TODO(Alex): llama.cpp on the LAN. Set BOT_BACKEND=llama and BOT_LLAMA_URL; a port is never
// assumed here (07 §2.2).

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:nbio"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"

import "../../../platform/env"
import "../../../platform/escape"
import "../../../platform/guard"
import sc "../../../platform/stream/client"
import "../../../platform/sys"
import "../../../platform/workers"
import m "../models"

NAME :: "llama"

ENV := [?]env.Row {
	{name = "BOT_LLAMA_URL", kind = .String, doc = "the llama.cpp server, http://host:port; required for the llama backend"},
	{name = "BOT_LLAMA_KEY", kind = .Secret, doc = "its API key (BOT_LLAMA_KEY_FILE names a file holding it), sent as a bearer token"},
	{name = "BOT_CONCURRENCY", kind = .Int, def = "0", doc = "generations at once; 0 = the server's /props total_slots"},
	{name = "BOT_QUEUE", kind = .Int, def = "16", doc = "generations waiting for a slot; past it a question is refused"},
	{name = "BOT_LLAMA_FIRST_TOKEN", kind = .Duration, def = "30s", doc = "how long an answer may take to start"},
	{name = "BOT_LLAMA_IDLE", kind = .Duration, def = "15s", doc = "how long an answer may go quiet"},
	{name = "BOT_LLAMA_PROBE", kind = .Duration, def = "5s", doc = "how often its health is read"},
}

@(private) CONNECT :: 2 * time.Second
@(private) TICK :: 50 * time.Millisecond // 20 Hz: the emit, and the deadlines
// One server event, and one answer. A generation that runs past them is the server's fault.
@(private) MAX_EVENT :: 64 * 1024
@(private) MAX_ANSWER :: 256 * 1024
// A real delta nests five deep; the JSON parser recurses.
@(private) MAX_DEPTH :: 32

@(private)
Phase :: enum u8 {
	Queued,
	Running,
	Ended,
}

@(private)
Gen :: struct {
	conn:      sc.Conn,
	id:        m.Bot_Gen_Id,
	sink:      m.Bot_Sink,
	body:      string, // heap
	phase:     Phase,
	pending:   strings.Builder, // text waiting for the next emit
	timer:     ^nbio.Operation,
	t0, first, last, last_emit: i64,
	tokens:    int, // deltas
	predicted: int, // the server's own count, when it gave one
	bytes:     int,
	stop:      m.Bot_Stop, // Eos, or Length from finish_reason
	ended:     bool,       // the stream's own end arrived
	stopping:  bool,       // cancel closed it
	problem:   string,     // static: why it is being ended
	event:     string,     // the event being read, for the guarded proc
}

@(private)
Waiter :: struct {
	id:   m.Bot_Gen_Id,
	loop: ^nbio.Event_Loop,
}

@(private)
st: struct {
	mu:          guard.Mutex,
	gens:        map[m.Bot_Gen_Id]^Gen, // read from any thread by cancel; each written on its loop
	queue:       [dynamic]Waiter,
	busy:        int,
	limit:       int,  // the slots: BOT_CONCURRENCY, else /props's
	fixed:       bool, // BOT_CONCURRENCY set it
	queue_cap:   int,
	seq:         u64,
	first_token: i64,
	idle:        i64,
	ep:          net.Endpoint,
	host:        string, // the Host header: as written in the URL
	name:        string,
	port:        int,
	auth:        string, // "Authorization: Bearer …\r\n", or ""
	configured:  bool,
	resolved:    bool,
	draining:    bool, // no generation starts, and none waits
}

// Env rows and the URL. No URL leaves the backend Offline; bot_web refuses that as the default.
init :: proc() {
	env.record("BOT_", ENV[:])
	st.gens = make(map[m.Bot_Gen_Id]^Gen, heap())
	st.queue = make([dynamic]Waiter, heap())
	st.limit = env.int_("BOT_CONCURRENCY")
	st.fixed = st.limit > 0
	if !st.fixed { st.limit = 1 } // until /props says
	st.queue_cap = max(0, env.int_("BOT_QUEUE"))
	st.first_token = i64(env.duration("BOT_LLAMA_FIRST_TOKEN"))
	st.idle = i64(env.duration("BOT_LLAMA_IDLE"))
	if key := env.str("BOT_LLAMA_KEY"); key != "" {
		st.auth = fmt.aprintf("Authorization: Bearer %s\r\n", key, allocator = heap())
	}
	url := env.str("BOT_LLAMA_URL")
	if url == "" { return }
	name, port, ok := parse_url(url)
	if !ok {
		env.problem(fmt.aprintf("BOT_LLAMA_URL=%q: http://host:port, with nothing after it (plain http: the LAN needs no TLS)", url, allocator = heap()))
		return
	}
	st.name, st.port, st.configured = name, port, true
	st.host = fmt.aprintf("%s:%d", name, port, allocator = heap())
	resolve()
}

configured :: proc() -> bool { return st.configured }

// http://host:port, host a name or an address; nothing is assumed about the port (07 §2.2).
parse_url :: proc(url: string) -> (host: string, port: int, ok: bool) {
	rest := strings.trim_suffix(url, "/")
	if !strings.has_prefix(rest, "http://") { return }
	rest = rest[len("http://"):]
	colon := strings.last_index_byte(rest, ':')
	if colon <= 0 || strings.index_any(rest, "/?#@ ") >= 0 { return }
	p, parsed := strconv.parse_int(rest[colon + 1:], 10)
	if !parsed || p < 1 || p > 65535 { return }
	return rest[:colon], p, true
}

// A name is looked up at boot and by the probe, never on a loop or a request's path: a lookup
// blocks. A failed one keeps the last address it found.
@(private)
resolve :: proc() {
	ep, found := net.parse_endpoint(st.host)
	if !found {
		v4, _, err := net.resolve(st.host)
		if err != nil || v4.port == 0 { return }
		ep, found = v4, true
	}
	guard.lock(&st.mu)
	st.ep, st.resolved = ep, true
	guard.unlock(&st.mu)
}

// The chat request's JSON, on the heap: the generation may wait for a slot.
body_of :: proc(req: m.Bot_Request) -> string {
	b := strings.builder_make(heap())
	strings.write_string(&b, `{"messages":[`)
	if req.system != "" {
		strings.write_string(&b, `{"role":"system","content":"`)
		escape.json_esc(&b, req.system)
		strings.write_string(&b, `"},`)
	}
	for t, i in req.history {
		if i > 0 { strings.write_byte(&b, ',') }
		strings.write_string(&b, `{"role":"`)
		strings.write_string(&b, "user" if t.role == .User else "assistant")
		strings.write_string(&b, `","content":"`)
		escape.json_esc(&b, t.text)
		strings.write_string(&b, `"}`)
	}
	fmt.sbprintf(&b, `],"stream":true,"max_tokens":%d,"temperature":%.2f`, req.max_tokens, req.temperature)
	if len(req.stop) > 0 {
		strings.write_string(&b, `,"stop":[`)
		for s, i in req.stop {
			if i > 0 { strings.write_byte(&b, ',') }
			strings.write_byte(&b, '"')
			escape.json_esc(&b, s)
			strings.write_byte(&b, '"')
		}
		strings.write_byte(&b, ']')
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

// What one server event says. `ok` false: it wasn't JSON of that shape.
Delta :: struct {
	content:   string, // in `allocator`
	finish:    string,
	predicted: int,
	error:     string,
}

parse_delta :: proc(data: string, allocator := context.temp_allocator) -> (d: Delta, ok: bool) {
	depth, deepest := 0, 0
	for i in 0 ..< len(data) {
		switch data[i] {
		case '{', '[':
			depth += 1
			deepest = max(deepest, depth)
		case '}', ']':
			depth -= 1
		}
	}
	if deepest > MAX_DEPTH { return }
	parsed, err := json.parse_string(data, .JSON, true, allocator)
	if err != nil { return }
	root, is_obj := parsed.(json.Object)
	if !is_obj { return }
	if e, has := root["error"]; has {
		d.error = "The model's server refused the question."
		if o, is_o := e.(json.Object); is_o {
			if text, is_s := o["message"].(json.String); is_s && text != "" { d.error = text }
		}
		return d, true
	}
	if t, has := root["timings"].(json.Object); has {
		if n, is_n := t["predicted_n"].(json.Integer); is_n { d.predicted = int(n) }
		if n, is_n := t["predicted_n"].(json.Float); is_n { d.predicted = int(n) }
	}
	choices, is_list := root["choices"].(json.Array)
	if !is_list { return d, false }
	if len(choices) == 0 { return d, true } // a usage-only chunk
	c, is_c := choices[0].(json.Object)
	if !is_c { return d, false }
	if f, has := c["finish_reason"].(json.String); has { d.finish = f }
	if dl, has := c["delta"].(json.Object); has {
		if text, is_s := dl["content"].(json.String); is_s { d.content = text }
	}
	return d, true
}

// ---- starting -----------------------------------------------------------------------------------

// On the calling loop, which must be `sink.loop`. Its last event may come before this returns.
start :: proc(req: m.Bot_Request, sink: m.Bot_Sink) -> m.Bot_Gen_Id {
	g := new(Gen, heap())
	g.id = sink.gen if sink.gen != 0 else m.Bot_Gen_Id(sync.atomic_add(&st.seq, 1) + 1)
	g.sink = sink
	g.sink.gen = g.id
	g.pending = strings.builder_make(heap())
	g.conn.user = g
	g.conn.on_sse = on_sse
	g.conn.on_close = on_close
	id := g.id

	guard.lock(&st.mu)
	reachable := st.resolved && !st.draining
	free_slot := st.busy < st.limit
	full := len(st.queue) >= st.queue_cap
	position := len(st.queue) + 1
	if reachable && (free_slot || !full) {
		st.gens[id] = g
		if free_slot {
			st.busy += 1
		} else {
			append(&st.queue, Waiter{id, sink.loop})
		}
	}
	guard.unlock(&st.mu)

	switch {
	case !reachable:
		g.phase = .Ended
		g.sink.on_event(g.sink.user, id, m.Bot_Error{"The model's server can't be reached."})
		destroy(g)
	case !free_slot && full:
		g.phase = .Ended
		g.sink.on_event(g.sink.user, id, m.Bot_Error{"The bot is busy. Try again in a minute."})
		destroy(g)
	case:
		g.body = body_of(req)
		if free_slot {
			run(g)
		} else {
			g.sink.on_event(g.sink.user, id, m.Bot_Queued{position})
		}
	}
	return id
}

@(private)
run :: proc(g: ^Gen) {
	g.phase = .Running
	g.t0 = sys.mono_ns()
	g.last, g.last_emit = g.t0, g.t0
	guard.lock(&st.mu)
	ep := st.ep
	guard.unlock(&st.mu)
	extra := strings.concatenate({st.auth, "Content-Type: application/json\r\nAccept: text/event-stream\r\nConnection: close\r\n"}, context.temp_allocator)
	g.conn.sse.max = MAX_EVENT
	sc.open(&g.conn, ep, sc.request("POST", st.host, "/v1/chat/completions", extra, g.body), .Sse, CONNECT)
	g.timer = nbio.timeout_poly(TICK, g, tick)
}

// Idempotent, from any thread: the generation stops with Bot_Done{.Stopped}.
cancel :: proc(id: m.Bot_Gen_Id) {
	guard.lock(&st.mu)
	g, ok := st.gens[id]
	loop: ^nbio.Event_Loop
	if ok { loop = g.sink.loop }
	guard.unlock(&st.mu)
	if !ok { return }
	box := new(m.Bot_Gen_Id, heap())
	box^ = id
	if !workers.post(loop, box, on_cancel) { free(box, heap()) }
}

// `main`'s drain (§8.7 step 3): what is waiting and what is running stops now, each on its own
// loop, so no upstream socket outlives the stream it fed. A room's answer has no stream to close, and
// would run on into the shutdown otherwise. A loop already gone takes no post; its sockets go with
// the process.
drain :: proc() {
	guard.lock(&st.mu)
	st.draining = true
	ids := make([dynamic]m.Bot_Gen_Id, 0, len(st.gens), context.temp_allocator)
	for id in st.gens { append(&ids, id) }
	guard.unlock(&st.mu)
	for id in ids { cancel(id) }
}

// ---- on the generation's loop ------------------------------------------------------------------

@(private)
on_cancel :: proc(_: ^nbio.Operation, box: ^m.Bot_Gen_Id) {
	id := box^
	free(box, heap())
	guard.lock(&st.mu)
	g, ok := st.gens[id]
	if ok && g.phase == .Queued {
		for w, i in st.queue {
			if w.id == id {
				ordered_remove(&st.queue, i)
				break
			}
		}
	}
	guard.unlock(&st.mu)
	if !ok || g.phase == .Ended { return } // it finished first
	guard.call(proc(data: rawptr) {
		g := (^Gen)(data)
		g.stopping = true
		if g.phase == .Queued {
			end(g)
			tell_positions()
		} else {
			sc.close(&g.conn)
		}
	}, g)
	free_all(context.temp_allocator)
}

@(private)
on_sse :: proc(c: ^sc.Conn, ev: sc.Sse_Event) {
	g := (^Gen)(c.user)
	g.event = ev.data
	guard.call(read_event, g)
	free_all(context.temp_allocator)
}

@(private)
read_event :: proc(data: rawptr) {
	g := (^Gen)(data)
	now := sys.mono_ns()
	g.last = now
	if g.event == "[DONE]" {
		g.ended = true
		sc.close(&g.conn)
		return
	}
	d, ok := parse_delta(g.event)
	switch {
	case !ok:
		g.problem = "The model's server sent something unreadable."
		sc.close(&g.conn)
		return
	case d.error != "":
		g.problem = "The model's server refused the question."
		sc.close(&g.conn)
		return
	}
	if d.predicted > 0 { g.predicted = d.predicted }
	if d.finish == "length" { g.stop = .Length }
	if d.content != "" {
		if g.first == 0 { g.first = now }
		g.tokens += 1
		g.bytes += len(d.content)
		strings.write_string(&g.pending, d.content)
		if now - g.last_emit >= i64(TICK) { emit(g, now) }
	}
	if g.bytes > MAX_ANSWER {
		g.ended, g.stop = true, .Length
		sc.close(&g.conn)
	}
}

// The socket is gone, whoever ended it.
@(private)
on_close :: proc(c: ^sc.Conn, why: sc.End) {
	g := (^Gen)(c.user)
	if !g.ended && !g.stopping && g.problem == "" {
		switch why {
		case .Dial_Failed:
			g.problem = "The model's server can't be reached."
		case .Refused:
			switch c.head.status {
			case 503: g.problem = "The model is still loading. Try again in a minute."
			case 401: g.problem = "The model's server refused the bot's key."
			case:     g.problem = "The model's server refused the question."
			}
		case .Done, .Closed, .Bad_Response, .Peer_Closed, .Send_Failed:
			g.problem = "The answer was cut off."
		}
	}
	guard.call(proc(data: rawptr) { end((^Gen)(data)) }, g)
	free_all(context.temp_allocator)
}

// The deadlines, and text the 20 Hz limit held back.
@(private)
tick :: proc(_: ^nbio.Operation, g: ^Gen) {
	g.timer = nil
	if g.phase != .Running { return }
	guard.call(proc(data: rawptr) {
		g := (^Gen)(data)
		now := sys.mono_ns()
		emit(g, now)
		switch {
		case g.first == 0 && now - g.t0 > st.first_token:
			g.problem = "The model didn't start answering in time."
		case g.first != 0 && now - g.last > st.idle:
			g.problem = "The model went quiet."
		case:
			g.timer = nbio.timeout_poly(TICK, g, tick)
			return
		}
		sc.close(&g.conn)
	}, g)
	free_all(context.temp_allocator)
}

@(private)
emit :: proc(g: ^Gen, now: i64) {
	if strings.builder_len(g.pending) == 0 { return }
	g.last_emit = now
	text := strings.clone(strings.to_string(g.pending), context.temp_allocator)
	strings.builder_reset(&g.pending)
	g.sink.on_event(g.sink.user, g.id, m.Bot_Token{text})
}

// Its slot goes to the next in line, and its sink hears the last event.
@(private)
end :: proc(g: ^Gen) {
	if g.phase == .Ended { return }
	ran := g.phase == .Running
	g.phase = .Ended
	if g.timer != nil {
		nbio.remove(g.timer)
		g.timer = nil
	}
	now := sys.mono_ns()
	emit(g, now)
	guard.lock(&st.mu)
	delete_key(&st.gens, g.id)
	if ran { st.busy -= 1 }
	guard.unlock(&st.mu)
	if ran { pump() }

	first := int((g.first - g.t0) / 1e6) if g.first != 0 else 0
	total := int((now - g.t0) / 1e6) if g.t0 != 0 else 0
	tokens := g.predicted if g.predicted > 0 else g.tokens
	switch {
	case g.problem != "" && g.tokens == 0:
		g.sink.on_event(g.sink.user, g.id, m.Bot_Error{g.problem})
	case g.problem != "":
		g.sink.on_event(g.sink.user, g.id, m.Bot_Done{stop = .Error, tokens = tokens, ms_first_token = first, ms_total = total})
	case g.stopping:
		g.sink.on_event(g.sink.user, g.id, m.Bot_Done{stop = .Stopped, tokens = tokens, ms_first_token = first, ms_total = total})
	case:
		g.sink.on_event(g.sink.user, g.id, m.Bot_Done{stop = g.stop, tokens = tokens, ms_first_token = first, ms_total = total})
	}
	// The client is still on its way out of this callback: the Gen holds its Conn.
	nbio.timeout_poly(0, g, proc(_: ^nbio.Operation, g: ^Gen) { destroy(g) })
}

@(private)
destroy :: proc(g: ^Gen) {
	sc.destroy(&g.conn)
	strings.builder_destroy(&g.pending)
	delete(g.body, heap())
	free(g, heap())
}

// Free slots to the waiting, first come first served: each runs on its own loop. Any thread.
@(private)
pump :: proc() {
	moved := false
	for {
		guard.lock(&st.mu)
		if st.busy >= st.limit || len(st.queue) == 0 {
			guard.unlock(&st.mu)
			break
		}
		w := st.queue[0]
		ordered_remove(&st.queue, 0)
		st.busy += 1
		guard.unlock(&st.mu)
		moved = true
		box := new(m.Bot_Gen_Id, heap())
		box^ = w.id
		if !workers.post(w.loop, box, on_slot) { // that loop left: the process is going
			free(box, heap())
			guard.lock(&st.mu)
			st.busy -= 1
			guard.unlock(&st.mu)
		}
	}
	if moved { tell_positions() }
}

@(private)
on_slot :: proc(_: ^nbio.Operation, box: ^m.Bot_Gen_Id) {
	id := box^
	free(box, heap())
	guard.lock(&st.mu)
	g, ok := st.gens[id]
	guard.unlock(&st.mu)
	if !ok || g.phase != .Queued { // cancelled on its way here: the slot is the next one's
		guard.lock(&st.mu)
		st.busy -= 1
		guard.unlock(&st.mu)
		pump()
		return
	}
	guard.call(proc(data: rawptr) {
		g := (^Gen)(data)
		g.sink.on_event(g.sink.user, g.id, m.Bot_Queued{0})
		run(g)
	}, g)
	free_all(context.temp_allocator)
}

// Everyone left in line hears their new place.
@(private)
tell_positions :: proc() {
	guard.lock(&st.mu)
	line := make([]Waiter, len(st.queue), context.temp_allocator)
	copy(line, st.queue[:])
	guard.unlock(&st.mu)
	for w, i in line {
		box := new(Place, heap())
		box^ = {id = w.id, position = i + 1}
		if !workers.post(w.loop, box, on_place) { free(box, heap()) }
	}
}

@(private)
Place :: struct {
	id:       m.Bot_Gen_Id,
	position: int,
	g:        ^Gen,
}

@(private)
on_place :: proc(_: ^nbio.Operation, box: ^Place) {
	defer free(box, heap())
	guard.lock(&st.mu)
	g, ok := st.gens[box.id]
	guard.unlock(&st.mu)
	if !ok || g.phase != .Queued { return }
	box.g = g
	guard.call(proc(data: rawptr) {
		p := (^Place)(data)
		p.g.sink.on_event(p.g.sink.user, p.g.id, m.Bot_Queued{p.position})
	}, box)
	free_all(context.temp_allocator)
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }
