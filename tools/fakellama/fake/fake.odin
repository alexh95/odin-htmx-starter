package fakellama

// ---- fakellama: a llama.cpp server with no model (PLAN §14.3) ---------------------------------
//
// What `backend_llama` is tested against, so nothing here needs a GPU: llama-server's routes and
// wire shapes, scripted answers and its faults. A thread per connection, on blocking core:net: this
// is a test double and nothing about it ships.
//
//   POST /v1/chat/completions   a chunked SSE answer: the question's words back, one delta each
//   GET  /health                200, or 503 "Loading model"
//   GET  /props                 total_slots, is_sleeping, the model
//   POST /__fake/state          ready | loading | sleeping
//   POST /__fake/reset          back to ready, the counters to 0
//   GET  /__fake/stats          what it saw, as JSON
//
// The last message's first word picks a fault, so a spec asks for one by typing it:
//
//   fake:split       every chunk boundary inside a `data:` line, and inside a multi-byte rune
//   fake:stall       the head, then nothing
//   fake:stall-mid   two deltas, then nothing
//   fake:drop        two deltas, then the socket closes, with no [DONE]
//   fake:quiet       two deltas, then empty events every 50 ms until the client goes
//   fake:error       200, then an OAI error event in the stream
//   fake:long        200 deltas, slower
//   fake:wall        500 deltas: 5,000 characters
//   fake:length      ends with finish_reason "length"
//   fake:silent      no text at all, then finish_reason "length": a thinking model that spent its tokens
//   fake:garbage     a data line that isn't JSON

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

Options :: struct {
	key:      string, // the bearer every route but /health wants; "" = none
	strict:   bool,   // /health wants it too, as a proxy in front of the server might
	slots:    int,
	delay:    time.Duration, // between deltas
	model:    string,
}

Mode :: enum i32 { Ready, Loading, Sleeping }

Stats :: struct {
	requests:  i32, // answers asked for
	closed:    i32, // answers the client walked away from
	finished:  i32, // answers sent to their [DONE]
	refused:   i32, // 401s
	busy:      i32, // answers being written now
	peak:      i32, // the most at once
	probes:    i32, // /health and /props
}

@(private)
s: struct {
	opt:    Options,
	mode:   Mode,
	stats:  Stats,
	slots:  sync.Sema,
	listen: net.TCP_Socket,
	stop:   bool,
	mu:     sync.Mutex,
	last:   string, // the last request body, on the heap
}

// Listens on loopback; port 0 picks one. Returns the port, with connections served on threads.
start :: proc(opt: Options, port := 0) -> (bound: int, err: net.Network_Error) {
	s.opt = opt
	if s.opt.slots <= 0 { s.opt.slots = 1 }
	if s.opt.delay == 0 { s.opt.delay = 5 * time.Millisecond }
	if s.opt.model == "" { s.opt.model = "fake-7b.Q4_K_M.gguf" }
	s.mode, s.stats, s.stop = .Ready, {}, false
	sync.sema_post(&s.slots, s.opt.slots)
	s.listen = net.listen_tcp({net.IP4_Loopback, port}) or_return
	ep := net.bound_endpoint(s.listen) or_return
	thread.create_and_start(accept_loop, self_cleanup = true)
	return ep.port, nil
}

set_mode :: proc(m: Mode) { sync.atomic_store(&s.mode, m) }

stats :: proc() -> Stats {
	return {
		requests = sync.atomic_load(&s.stats.requests), closed = sync.atomic_load(&s.stats.closed),
		finished = sync.atomic_load(&s.stats.finished), refused = sync.atomic_load(&s.stats.refused),
		busy = sync.atomic_load(&s.stats.busy), peak = sync.atomic_load(&s.stats.peak),
		probes = sync.atomic_load(&s.stats.probes),
	}
}

// The body of the last answer asked for, as sent: a test reads what the binding wrote.
last_body :: proc(allocator := context.temp_allocator) -> string {
	sync.lock(&s.mu)
	defer sync.unlock(&s.mu)
	return strings.clone(s.last, allocator)
}

@(private)
accept_loop :: proc() {
	for !sync.atomic_load(&s.stop) {
		client, _, err := net.accept_tcp(s.listen)
		if err != nil { return }
		t := thread.create(serve)
		t.user_index = int(client)
		t.init_context = context
		thread.start(t)
	}
}

// Ends the listener: a suite's last call. Threads still writing find their sockets gone.
stop :: proc() {
	sync.atomic_store(&s.stop, true)
	net.close(s.listen)
}

// ---- one connection, one request -------------------------------------------------------------

@(private)
Request :: struct {
	method, path: string,
	auth:         string,
	body:         string,
}

@(private)
serve :: proc(t: ^thread.Thread) {
	sock := net.TCP_Socket(t.user_index)
	defer net.close(sock)
	defer free_all(context.temp_allocator)
	req, ok := read_request(sock)
	if !ok { return }
	route(sock, req)
}

@(private)
read_request :: proc(sock: net.TCP_Socket) -> (req: Request, ok: bool) {
	buf := make([dynamic]byte, 0, 4096, context.temp_allocator)
	chunk: [4096]byte
	head_end := -1
	for head_end < 0 {
		n, err := net.recv_tcp(sock, chunk[:])
		if err != nil || n == 0 { return }
		append(&buf, ..chunk[:n])
		head_end = strings.index(string(buf[:]), "\r\n\r\n")
		if len(buf) > 1 << 20 { return }
	}
	head := string(buf[:head_end])
	length := 0
	lines := strings.split(head, "\r\n", context.temp_allocator)
	parts := strings.split(lines[0], " ", context.temp_allocator)
	if len(parts) < 2 { return }
	req.method, req.path = parts[0], parts[1]
	for l in lines[1:] {
		i := strings.index_byte(l, ':')
		if i < 0 { continue }
		name, value := strings.to_lower(l[:i], context.temp_allocator), strings.trim_space(l[i + 1:])
		switch name {
		case "content-length": length, _ = strconv.parse_int(value, 10)
		case "authorization":  req.auth = value
		}
	}
	for len(buf) < head_end + 4 + length {
		n, err := net.recv_tcp(sock, chunk[:])
		if err != nil || n == 0 { return }
		append(&buf, ..chunk[:n])
	}
	req.body = string(buf[head_end + 4:][:length])
	return req, true
}

@(private)
route :: proc(sock: net.TCP_Socket, r: Request) {
	switch {
	case r.method == "GET" && r.path == "/health" && (!s.opt.strict || authorized(r)):
		sync.atomic_add(&s.stats.probes, 1)
		if sync.atomic_load(&s.mode) == .Loading { loading(sock) } else { answer(sock, "200 OK", `{"status":"ok"}`) }
	case !authorized(r):
		sync.atomic_add(&s.stats.refused, 1)
		answer(sock, "401 Unauthorized", `{"error":{"code":401,"message":"Invalid API Key","type":"authentication_error"}}`)
	case r.method == "GET" && r.path == "/props":
		sync.atomic_add(&s.stats.probes, 1)
		if sync.atomic_load(&s.mode) == .Loading {
			loading(sock)
			return
		}
		sleeping := sync.atomic_load(&s.mode) == .Sleeping
		answer(sock, "200 OK", fmt.tprintf(`{{"total_slots":%d,"is_sleeping":%v,"model_path":"/models/%s"}}`, s.opt.slots, sleeping, s.opt.model))
	case r.method == "POST" && r.path == "/v1/chat/completions":
		if sync.atomic_load(&s.mode) == .Loading {
			loading(sock)
			return
		}
		complete(sock, r.body)
	case r.method == "POST" && r.path == "/__fake/state":
		switch strings.trim_space(r.body) {
		case "ready":    set_mode(.Ready)
		case "loading":  set_mode(.Loading)
		case "sleeping": set_mode(.Sleeping)
		case:
			answer(sock, "400 Bad Request", `{}`)
			return
		}
		answer(sock, "200 OK", `{}`)
	case r.method == "POST" && r.path == "/__fake/reset":
		set_mode(.Ready)
		s.stats = {}
		answer(sock, "200 OK", `{}`)
	case r.method == "GET" && r.path == "/__fake/stats":
		st := stats()
		answer(sock, "200 OK", fmt.tprintf(`{{"requests":%d,"closed":%d,"finished":%d,"refused":%d,"busy":%d,"peak":%d,"probes":%d}}`,
			st.requests, st.closed, st.finished, st.refused, st.busy, st.peak, st.probes))
	case:
		answer(sock, "404 Not Found", `{"error":{"code":404,"message":"File Not Found","type":"not_found_error"}}`)
	}
}

@(private)
authorized :: proc(r: Request) -> bool {
	if strings.has_prefix(r.path, "/__fake/") || s.opt.key == "" { return true }
	return r.auth == strings.concatenate({"Bearer ", s.opt.key}, context.temp_allocator)
}

@(private)
loading :: proc(sock: net.TCP_Socket) {
	answer(sock, "503 Service Unavailable", `{"error":{"code":503,"message":"Loading model","type":"unavailable_error"}}`)
}

@(private)
answer :: proc(sock: net.TCP_Socket, status, body: string) {
	send(sock, fmt.tprintf("HTTP/1.1 %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", status, len(body), body))
}

@(private)
send :: proc(sock: net.TCP_Socket, text: string) -> bool {
	_, err := net.send_tcp(sock, transmute([]byte)text)
	return err == nil
}

// ---- an answer ---------------------------------------------------------------------------------

@(private)
Fault :: enum { None, Split, Stall, Stall_Mid, Quiet, Drop, Error, Long, Wall, Length, Silent, Garbage }

@(private)
question_of :: proc(body: string) -> (q: string, fault: Fault) {
	parsed, err := json.parse_string(body, allocator = context.temp_allocator)
	if err != nil { return }
	root, ok := parsed.(json.Object)
	if !ok { return }
	msgs, is_list := root["messages"].(json.Array)
	if !is_list || len(msgs) == 0 { return }
	last, is_obj := msgs[len(msgs) - 1].(json.Object)
	if !is_obj { return }
	q, _ = last["content"].(json.String)
	switch strings.fields(q, context.temp_allocator)[0] if len(strings.fields(q, context.temp_allocator)) > 0 else "" {
	case "fake:split":     fault = .Split
	case "fake:stall":     fault = .Stall
	case "fake:stall-mid": fault = .Stall_Mid
	case "fake:drop":      fault = .Drop
	case "fake:quiet":     fault = .Quiet
	case "fake:error":     fault = .Error
	case "fake:long":      fault = .Long
	case "fake:wall":      fault = .Wall
	case "fake:length":    fault = .Length
	case "fake:silent":    fault = .Silent
	case "fake:garbage":   fault = .Garbage
	}
	return
}

// `data: <delta>\n\n`, as llama-server frames one.
@(private)
delta :: proc(id, content, finish: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `data: {{"choices":[{{"finish_reason":%s,"index":0,"delta":`, finish)
	if content == "" {
		strings.write_string(&b, `{}`)
	} else {
		strings.write_string(&b, `{"content":`)
		json_string(&b, content)
		strings.write_byte(&b, '}')
	}
	fmt.sbprintf(&b, `}}],"created":1762300000,"id":"%s","model":"%s","object":"chat.completion.chunk"}}`, id, s.opt.model)
	strings.write_string(&b, "\n\n")
	return strings.to_string(b)
}

@(private)
json_string :: proc(b: ^strings.Builder, text: string) {
	strings.write_byte(b, '"')
	for i in 0 ..< len(text) {
		switch c := text[i]; c {
		case '"', '\\':
			strings.write_byte(b, '\\')
			strings.write_byte(b, c)
		case '\n': strings.write_string(b, `\n`)
		case:      strings.write_byte(b, c)
		}
	}
	strings.write_byte(b, '"')
}

// One HTTP chunk.
@(private)
chunk :: proc(sock: net.TCP_Socket, text: string) -> bool {
	return send(sock, fmt.tprintf("%x\r\n%s\r\n", len(text), text))
}

@(private)
pause :: proc() { time.sleep(s.opt.delay) }

// `text` in two chunks, cut at `at`.
@(private)
chunk_split :: proc(sock: net.TCP_Socket, text: string, at: int) -> bool {
	cut := min(at, len(text) - 1)
	if !chunk(sock, text[:cut]) { return false }
	pause()
	return chunk(sock, text[cut:])
}

@(private)
complete :: proc(sock: net.TCP_Socket, body: string) {
	sync.atomic_add(&s.stats.requests, 1)
	sync.lock(&s.mu)
	delete(s.last)
	s.last = strings.clone(body)
	sync.unlock(&s.mu)
	q, fault := question_of(body)

	// llama.cpp queues past its slots: the head comes when a slot frees.
	sync.sema_wait(&s.slots)
	defer sync.sema_post(&s.slots)
	n := sync.atomic_add(&s.stats.busy, 1) + 1
	defer sync.atomic_sub(&s.stats.busy, 1)
	for {
		p := sync.atomic_load(&s.stats.peak)
		if n <= p { break }
		if _, swapped := sync.atomic_compare_exchange_strong(&s.stats.peak, p, n); swapped { break }
	}

	if !send(sock, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n") {
		gone()
		return
	}
	id := "chatcmpl-fake"
	if fault == .Stall {
		wait_for_close(sock)
		return
	}
	if !chunk(sock, `data: {"choices":[{"finish_reason":null,"index":0,"delta":{"role":"assistant","content":null}}],"id":"chatcmpl-fake","object":"chat.completion.chunk"}` + "\n\n") {
		gone()
		return
	}

	words := make([dynamic]string, context.temp_allocator)
	switch fault {
	case .Long:
		for i in 0 ..< 200 { append(&words, fmt.tprintf("word%d ", i)) }
	case .Wall:
		for _ in 0 ..< 500 { append(&words, "wallwalls ") }
	case .Silent:
	case .None, .Split, .Stall, .Stall_Mid, .Quiet, .Drop, .Error, .Length, .Garbage:
		append(&words, "You ", "asked: ")
		rest := q
		for w in strings.fields_iterator(&rest) {
			append(&words, strings.concatenate({w, " "}, context.temp_allocator))
		}
		if fault == .Split { append(&words, "héllo ", "wörld ", "🚀") }
	}

	for w, i in words {
		if i == 2 {
			#partial switch fault {
			case .Stall_Mid:
				wait_for_close(sock)
				return
			case .Quiet:
				for chunk(sock, `data: {"choices":[]}` + "\n\n") { time.sleep(50 * time.Millisecond) }
				gone()
				return
			case .Drop:
				return
			case .Error:
				chunk(sock, `data: {"error":{"code":500,"message":"Context size has been exceeded.","type":"exceed_context_size_error"}}` + "\n\n")
				chunk(sock, "")
				return
			case .Garbage:
				if !chunk(sock, "data: {not json\n\n") {
					gone()
					return
				}
			}
		}
		frame := delta(id, w, "null")
		sent: bool
		if fault == .Split {
			// Inside `data:`, inside the JSON, and for a rune past ASCII, inside the rune.
			at := 3
			for ch, j in frame { if ch > 127 { at = j + 1; break } }
			sent = chunk_split(sock, frame, at)
		} else {
			sent = chunk(sock, frame)
		}
		if !sent {
			gone()
			return
		}
		pause()
		if fault == .Long { pause() }
	}

	finish := `"length"` if fault == .Length || fault == .Silent else `"stop"`
	timed := fmt.tprintf(`data: {{"choices":[{{"finish_reason":%s,"index":0,"delta":{{}}}}],"id":"chatcmpl-fake","object":"chat.completion.chunk","usage":{{"completion_tokens":%d,"prompt_tokens":9,"total_tokens":%d}},"timings":{{"predicted_n":%d,"predicted_ms":%d,"prompt_ms":3}}}}` + "\n\n",
		finish, len(words), len(words) + 9, len(words), len(words) * 5)
	if !chunk(sock, timed) || !chunk(sock, "data: [DONE]\n\n") {
		gone()
		return
	}
	chunk(sock, "")
	sync.atomic_add(&s.stats.finished, 1)
}

@(private)
gone :: proc() { sync.atomic_add(&s.stats.closed, 1) }

// A stalled answer holds its slot until the client closes, as a generation that hangs would.
@(private)
wait_for_close :: proc(sock: net.TCP_Socket) {
	one: [1]byte
	_, _ = net.recv_tcp(sock, one[:])
	gone()
}
