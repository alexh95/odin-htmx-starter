package main

// ---- streamload: SSE and WebSocket fan-out, measured (PLAN §19.1.7) ----------------------
//
//   odin run tools/streamload -- fanout  [--sse N] [--ws N] [--publish K] [--every MS] [flags]
//   odin run tools/streamload -- restart [--sse N] [--ws N] [--within S] [flags]
//   odin run tools/streamload -- hold    [--sse N] [--ws N] [--for S] [flags]
//   flags: --base http://127.0.0.1:8080  --threads T (4)  --key K (random)
//   fanout's --room SLUG --cookies FILE: a chat room instead of the lab's: the sockets in
//            /chat/r/SLUG/ws as FILE's first line (a Cookie header's value), and each message a
//            POST to the room as a composer's, by the lines in turn: chat allows a member 5 in 10 s.
//
// Stock k6 returns from an SSE request only when the stream ends, xk6-sse is a
// custom AGPL k6 the repo won't ship, and Node clients left 03's numbers
// client-bound, so the fan-out budgets (§18.4) are measured here, on
// platform/stream/client: T threads, each an event loop holding its share of
// the clients, against the lab profile's endpoints.
//
//   fanout   N subscribers of /events?t=lab.feed:<key> and N sockets in
//            /lab/ws/chat?room=<key>; then K messages through /lab/publish, each
//            stamped with the publisher's clock, which every client reads back:
//            delivery percentiles per transport, and what never arrived.
//   restart  the clients connect, take K messages, then wait for the server to drop
//            them (restart it meanwhile); each reconnects after 0.5 s ±30 % (htmx's first backoff),
//            SSE with its Last-Event-ID: how long until every one is back, and how
//            many SSE streams resumed by replay or by resync.
//   hold     the clients connect and stay for S seconds: RSS and fds per stream,
//            read from outside (the drills, `ps`).

import "core:fmt"
import "core:nbio"
import "core:net"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import sc "../../app/platform/stream/client"

Mode :: enum { Fanout, Restart, Hold }

opt: struct {
	mode:    Mode,
	ep:      net.Endpoint,
	host:    string,
	sse, ws: int,
	threads: int,
	publish: int,
	every:   time.Duration,
	within:  time.Duration,
	hold:    time.Duration,
	key:     string,
	room:    string,
	cookies: []string,
}

// What every thread adds to, read by main once they are done.
shared: struct {
	open:       int, // atomic: clients with their head in
	dropped:    int, // atomic: clients that lost their stream (restart)
	back:       int, // atomic: clients connected again after a drop
	failed:     int, // atomic: opens refused or failed
	first_drop: i64, // atomic: mono ns of the first drop
	last_back:  i64, // atomic: mono ns of the latest reconnect
	replayed:   int, // atomic: SSE streams whose first events after a reconnect were a replay
	resynced:   int, // atomic: ... or a resync
	stop:       bool, // atomic: the threads wind down
	mu:         sync.Mutex,
	lat:        [2][dynamic]i64, // ns from publish to delivery, per transport (0 SSE, 1 WS)
	got:        [2]int,
	short:      [2]int, // clients that got fewer than every message
	shortest:   [2]int, // the fewest any client got
}

Client :: struct {
	conn:      sc.Conn,
	ws:        bool,
	last_id:   [64]byte,
	last_len:  int,
	dropped:   bool,
	fresh:     bool, // reconnected: the next event says replay or resync
	retry:     ^nbio.Operation,
	lat:       ^[dynamic]i64, // this thread's
	got:       ^int,
	count:     int, // messages this client got
}

main :: proc() {
	parse_args()
	shared.shortest = {max(int), max(int)}
	fmt.printfln("streamload %v: %d SSE + %d WS on %d threads -> %s (key %s)", opt.mode, opt.sse, opt.ws, opt.threads, opt.host, opt.key)

	threads := make([]^thread.Thread, opt.threads)
	for i in 0 ..< opt.threads {
		threads[i] = thread.create_and_start_with_poly_data(i, worker)
	}
	want := opt.sse + opt.ws
	t0 := time.tick_now()
	for sync.atomic_load(&shared.open) + sync.atomic_load(&shared.failed) < want && time.tick_since(t0) < 30 * time.Second {
		time.sleep(20 * time.Millisecond)
	}
	fmt.printfln("connected %d of %d in %v (%d failed)", sync.atomic_load(&shared.open), want, time.tick_since(t0), sync.atomic_load(&shared.failed))

	switch opt.mode {
	case .Fanout:
		time.sleep(300 * time.Millisecond) // the last subscriptions settle
		publish_all()
		time.sleep(2 * time.Second) // the last deliveries land
	case .Restart:
		// A few messages first, so each SSE client holds a cursor to resume from.
		time.sleep(300 * time.Millisecond)
		publish_all()
		fmt.println("waiting for the server to drop the clients: restart it now")
		for sync.atomic_load(&shared.dropped) == 0 { time.sleep(10 * time.Millisecond) }
		deadline := time.tick_now()
		for sync.atomic_load(&shared.back) < sync.atomic_load(&shared.dropped) || sync.atomic_load(&shared.dropped) < want {
			if time.tick_since(deadline) > opt.within { break }
			time.sleep(10 * time.Millisecond)
		}
	case .Hold:
		fmt.printfln("holding for %v (pid %d)", opt.hold, os.get_pid())
		time.sleep(opt.hold)
	}
	sync.atomic_store(&shared.stop, true)
	for t in threads { thread.join(t) }
	report(want)
}

report :: proc(want: int) {
	switch opt.mode {
	case .Fanout:
		expect := [2]int{opt.sse * opt.publish, opt.ws * opt.publish}
		for name, i in ([2]string{"SSE", "WS"}) {
			if expect[i] == 0 { continue }
			l := shared.lat[i][:]
			slice.sort(l)
			fmt.printfln("%-3s %d of %d delivered; ms p50 %.1f p95 %.1f p99 %.1f max %.1f", name, len(l), expect[i], pct(l, 50), pct(l, 95), pct(l, 99), pct(l, 100))
			if shared.short[i] > 0 { fmt.printfln("    %d clients got fewer than %d (the fewest %d)", shared.short[i], opt.publish, shared.shortest[i]) }
		}
	case .Restart:
		back := sync.atomic_load(&shared.back)
		ms := f64(sync.atomic_load(&shared.last_back) - sync.atomic_load(&shared.first_drop)) / 1e6
		fmt.printfln("back %d of %d dropped (%d clients) in %.0f ms from the first drop; SSE resumed by replay %d, by resync %d",
			back, sync.atomic_load(&shared.dropped), want, ms, sync.atomic_load(&shared.replayed), sync.atomic_load(&shared.resynced))
	case .Hold:
	}
}

pct :: proc(l: []i64, p: int) -> f64 {
	if len(l) == 0 { return 0 }
	i := min(len(l) - 1, (len(l) * p) / 100)
	return f64(l[i]) / 1e6
}

// ---- the clients' threads -------------------------------------------------------------

worker :: proc(index: int) {
	if err := nbio.acquire_thread_event_loop(); err != nil {
		fmt.eprintfln("thread %d: no event loop: %v", index, err)
		os.exit(1)
	}
	defer nbio.release_thread_event_loop()
	lat: [2][dynamic]i64
	got: [2]int
	clients: [dynamic]^Client
	share :: proc(n, index: int) -> int { return n / opt.threads + (1 if index < n % opt.threads else 0) }
	for kind in 0 ..< 2 {
		for _ in 0 ..< share(opt.sse if kind == 0 else opt.ws, index) {
			c := new(Client)
			c.ws, c.lat, c.got = kind == 1, &lat[kind], &got[kind]
			append(&clients, c)
			connect(c)
		}
	}
	for !sync.atomic_load(&shared.stop) {
		nbio.tick(50 * time.Millisecond)
	}
	for c in clients {
		if c.retry != nil { nbio.remove(c.retry) }
		sc.close(&c.conn)
	}
	// The closes and cancellations complete on later ticks: the loop goes only once they have.
	for tries := 0; nbio.num_waiting() > 0 && tries < 200; tries += 1 { nbio.tick(10 * time.Millisecond) }
	sync.lock(&shared.mu)
	for i in 0 ..< 2 {
		append(&shared.lat[i], ..lat[i][:])
		shared.got[i] += got[i]
	}
	for c in clients {
		k := 1 if c.ws else 0
		if c.count < opt.publish {
			shared.short[k] += 1
			shared.shortest[k] = min(shared.shortest[k], c.count)
		}
	}
	sync.unlock(&shared.mu)
}

connect :: proc(c: ^Client) {
	conn := &c.conn
	conn.user = c
	conn.on_open = proc(conn: ^sc.Conn) {
		c := (^Client)(conn.user)
		sync.atomic_add(&shared.open, 1)
		if c.dropped {
			c.dropped, c.fresh = false, !c.ws
			sync.atomic_add(&shared.back, 1)
			sync.atomic_store(&shared.last_back, i64(time.tick_now()._nsec))
		}
	}
	conn.on_sse = proc(conn: ^sc.Conn, ev: sc.Sse_Event) {
		c := (^Client)(conn.user)
		if ev.id != "" {
			c.last_len = copy(c.last_id[:], ev.id)
		}
		if c.fresh {
			c.fresh = false
			sync.atomic_add(&shared.resynced if ev.event == "resync" else &shared.replayed, 1)
		}
		stamp(c, ev.data)
	}
	conn.on_ws = proc(conn: ^sc.Conn, text: bool, data: []byte) {
		stamp((^Client)(conn.user), string(data))
	}
	conn.on_close = proc(conn: ^sc.Conn, why: sc.End) {
		c := (^Client)(conn.user)
		if why == .Closed { return }
		if why != .Dial_Failed && why != .Refused { sync.atomic_sub(&shared.open, 1) }
		if opt.mode != .Restart || sync.atomic_load(&shared.stop) {
			if why == .Dial_Failed || why == .Refused { sync.atomic_add(&shared.failed, 1) }
			return
		}
		if !c.dropped {
			c.dropped = true
			sync.atomic_add(&shared.dropped, 1)
			sync.atomic_compare_exchange_strong(&shared.first_drop, 0, i64(time.tick_now()._nsec))
		}
		// htmx's first reconnect: 500 ms ±30 %.
		wait := time.Duration(350 + (i64(time.tick_now()._nsec) / 1000) % 300) * time.Millisecond
		c.retry = nbio.timeout_poly(wait, c, proc(_: ^nbio.Operation, c: ^Client) {
			c.retry = nil
			if !sync.atomic_load(&shared.stop) { connect(c) }
		})
	}
	req: string
	if opt.room != "" {
		req = sc.request("GET", opt.host, fmt.tprintf("/chat/r/%s/ws", opt.room), fmt.tprintf("Cookie: %s\r\n", opt.cookies[0]))
	} else if c.ws {
		req = sc.request("GET", opt.host, strings.concatenate({"/lab/ws/chat?room=", opt.key}, context.temp_allocator))
	} else {
		extra := ""
		if c.last_len > 0 { extra = strings.concatenate({"Last-Event-ID: ", string(c.last_id[:c.last_len]), "\r\n"}, context.temp_allocator) }
		req = sc.request("GET", opt.host, strings.concatenate({"/events?t=lab.feed:", opt.key}, context.temp_allocator), extra)
	}
	sc.open(conn, opt.ep, req, .Ws if c.ws else .Sse)
}

// The publisher's stamp, `<MARK><ns>`, read back out of the delivered fragment.
stamp :: proc(c: ^Client, data: string) {
	mark := "stamp:" if opt.room != "" else "t=" // a chat fragment is full of `t=`: hx-target="…"
	i := strings.index(data, mark)
	if i < 0 { return }
	i += len(mark)
	j := i
	for j < len(data) && data[j] >= '0' && data[j] <= '9' { j += 1 }
	sent, ok := strconv.parse_i64(data[i:j], 10)
	if !ok { return }
	append(c.lat, i64(time.tick_now()._nsec) - sent)
	c.got^ += 1
	c.count += 1
}

// ---- the publisher ----------------------------------------------------------------------

// K messages `every` apart, to the feed and to the room, one connection each,
// on the main thread's own loop.
publish_all :: proc() {
	if err := nbio.acquire_thread_event_loop(); err != nil {
		fmt.eprintfln("publisher: no event loop: %v", err)
		os.exit(1)
	}
	defer nbio.release_thread_event_loop()
	Pending :: struct {
		conn: sc.Conn,
		done: bool,
		why:  sc.End,
	}
	refused := 0
	for i in 0 ..< opt.publish {
		start := time.tick_now()
		if opt.room != "" {
			p: Pending
			p.conn.user = &p
			p.conn.on_close = proc(conn: ^sc.Conn, why: sc.End) {
				p := (^Pending)(conn.user)
				p.done, p.why = true, why
			}
			// The first line's member holds the sockets; the rest post.
			cookie := opt.cookies[1 + i % (len(opt.cookies) - 1)] if len(opt.cookies) > 1 else opt.cookies[0]
			extra := fmt.tprintf("Content-Type: application/x-www-form-urlencoded\r\nCookie: %s\r\n", cookie)
			body := fmt.tprintf("body=stamp%%3A%d", time.tick_now()._nsec)
			sc.open(&p.conn, opt.ep, sc.request("POST", opt.host, fmt.tprintf("/chat/r/%s", opt.room), extra, body), .Body)
			for !p.done { nbio.tick(10 * time.Millisecond) }
			if p.why != .Done || p.conn.head.status != 200 { refused += 1 }
			sc.destroy(&p.conn)
			free_all(context.temp_allocator)
			continue
		}
		for target in ([2]string{"lab.feed", "lab.room"}) {
			if (target == "lab.feed" && opt.sse == 0) || (target == "lab.room" && opt.ws == 0) { continue }
			body := fmt.tprintf("id=m%d&text=t%%3D%d", i, time.tick_now()._nsec)
			path := fmt.tprintf("/lab/publish?t=%s:%s", target, opt.key)
			p: Pending
			p.conn.user = &p
			p.conn.on_close = proc(conn: ^sc.Conn, why: sc.End) {
				p := (^Pending)(conn.user)
				p.done, p.why = true, why
			}
			sc.open(&p.conn, opt.ep, sc.request("POST", opt.host, path, "Content-Type: application/x-www-form-urlencoded\r\n", body), .Body)
			for !p.done { nbio.tick(10 * time.Millisecond) }
			if p.why != .Done || p.conn.head.status != 204 { refused += 1 }
			sc.destroy(&p.conn)
			free_all(context.temp_allocator)
		}
		if left := opt.every - time.tick_since(start); left > 0 { time.sleep(left) }
	}
	if refused > 0 { fmt.eprintfln("publisher: %d publishes not answered 204", refused) }
}

// ---- arguments --------------------------------------------------------------------------

parse_args :: proc() {
	args := os.args[1:]
	if len(args) == 0 { usage() }
	switch args[0] {
	case "fanout":  opt.mode = .Fanout
	case "restart": opt.mode = .Restart
	case "hold":    opt.mode = .Hold
	case:           usage()
	}
	base := "http://127.0.0.1:8080"
	opt.threads, opt.publish, opt.every = 4, 50, 20 * time.Millisecond
	opt.within, opt.hold = 30 * time.Second, 60 * time.Second
	opt.key = fmt.aprintf("load-%x", time.tick_now()._nsec & 0xffffff)
	num :: proc(args: []string, i: ^int) -> int {
		i^ += 1
		if i^ >= len(args) { usage() }
		n, ok := strconv.parse_int(args[i^], 10)
		if !ok || n < 0 { usage() }
		return n
	}
	for i := 1; i < len(args); i += 1 {
		switch args[i] {
		case "--base":    i += 1; base = args[i] if i < len(args) else ""
		case "--key":     i += 1; opt.key = args[i] if i < len(args) else ""
		case "--sse":     opt.sse = num(args, &i)
		case "--ws":      opt.ws = num(args, &i)
		case "--threads": opt.threads = max(1, num(args, &i))
		case "--publish": opt.publish = num(args, &i)
		case "--every":   opt.every = time.Duration(num(args, &i)) * time.Millisecond
		case "--within":  opt.within = time.Duration(num(args, &i)) * time.Second
		case "--for":     opt.hold = time.Duration(num(args, &i)) * time.Second
		case "--room":    i += 1; opt.room = args[i] if i < len(args) else ""
		case "--cookies":
			i += 1
			if i >= len(args) { usage() }
			data, err := os.read_entire_file(args[i], context.allocator)
			if err != nil { usage() }
			opt.cookies = strings.split_lines(strings.trim_space(string(data)))
		case:             usage()
		}
	}
	rest := strings.trim_prefix(base, "http://")
	if rest == base || opt.key == "" || (opt.room != "" && len(opt.cookies) == 0) { usage() }
	opt.host = strings.trim_suffix(rest, "/")
	ep, ok := net.parse_endpoint(opt.host)
	if !ok { usage() }
	opt.ep = ep
}

usage :: proc() -> ! {
	fmt.eprintln("usage: streamload fanout|restart|hold [--sse N] [--ws N] [--threads T] [--publish K] [--every MS]")
	fmt.eprintln("                  [--within S] [--for S] [--base http://127.0.0.1:8080] [--key K]")
	fmt.eprintln("                  [--room SLUG --cookies FILE]")
	os.exit(2)
}
