package app

// ---- platform/app: the composition package (L4) -----------------------------------
//
// Only cmd/* imports it. A profile's main is the boot sequence as plain calls
// (PLAN §7.2, §8.6, §8.7):
//
//   app.boot("skeleton")               // CLI short-circuits, NOFILE, logs, the guard, the platform's env
//   … each feature's init …            // records and reads its env rows, declares its limits
//   store_sqlite.init()                // SQLite profiles: the store's env rows
//   app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS)   // the boot checks; --features, --routes, --limits answer here
//   store_sqlite.open(…); migrate …    // SQLite profiles only
//   app.serve(HOSTS[:], JOBS[:], &BRAND)        // assets, CSP, bind, loops, the banner; returns once they run
//   … each feature's start …
//   app.wait()                         // a signal (or a dirty crash): /readyz answers 503
//   … each feature's drain …
//   app.shutdown()                     // the fork's bounded drain: idle peers, active requests, timers
//   store_sqlite.close()               // SQLite profiles: the writer's last batch, a checkpoint
//   app.exit()                         // logs flushed; exit 0, or 70 after a dirty crash
//
// It imports the `identity:` family, whose load_viewer front calls, and L1-L3.

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "../env"
import "../guard"
import "../html"
import "../obs"
import "../stream"
import "../sys"
import "../web"
import "../workers"
import identity "identity:."

// One table a host mounts, with the feature it belongs to: the name labels its
// rows in --routes and --features and in boot check 5's message.
Mount :: struct {
	feature: string,
	rows:    []web.Route,
}

// A host in a profile's routes.odin (§7.2): its log and metrics label, the env
// var that names its origin, whether front runs the identity there, its tables
// and its nav.
Host :: struct {
	name:     string,
	site_env: string,
	identity: bool,
	routes:   []Mount,
	nav:      []html.Nav_Item,
}

PLATFORM_ENV := [?]env.Row {
	{name = "PORT", kind = .Int, def = "8080", doc = "listen port; the first argument when unset"},
	{name = "BIND_ALL", kind = .String, doc = "any value listens on 0.0.0.0 (containers); unset = loopback"},
	{name = "SITE_URL", kind = .String, doc = "the canonical origin; brand.odin's when unset"},
	{name = "THREADS", kind = .Int, def = "0", doc = "event-loop threads; 0 = one per core"},
	{name = "LOG_LEVEL", kind = .Enum, def = "info", choices = "debug|info|warn|warning|error", doc = "warn silences the access log"},
	{name = "MAX_CONNS", kind = .Int, def = "0", doc = "connection cap, 503 past it; 0 = the fd soft limit - 64 (F-8)"},
	{name = "HEADER_TIMEOUT_MS", kind = .Int, def = "10000", doc = "request line and headers (F-7)"},
	{name = "IDLE_TIMEOUT_MS", kind = .Int, def = "75000", doc = "a kept-alive connection's next request (F-7)"},
	{name = "BODY_TIMEOUT_MS", kind = .Int, def = "30000", doc = "a request body (F-7)"},
	{name = "SEND_TIMEOUT_MS", kind = .Int, def = "30000", doc = "one send to a client that doesn't read; then the connection is cut (M1-02)"},
	{name = "DRAIN_DEADLINE_MS", kind = .Int, def = "5000", doc = "what active requests get at shutdown (F-9)"},
	{name = "TRUST_PROXY", kind = .Cidrs, doc = "proxies whose X-Real-IP and X-Forwarded-Proto count; empty = none"},
	{name = "LAN_CIDRS", kind = .Cidrs, def = "192.168.0.0/16", doc = "what .Lan_Only routes accept"},
	{name = "METRICS_TOKEN_FILE", kind = .Path, doc = "a file holding the bearer token for /metrics"},
	{name = "CRASH_FILE", kind = .Path, def = "last-crash.txt", doc = "where a dirty crash or a watchdog exit writes its reason"},
	{name = "GUARD_BURST", kind = .Int, def = "100", doc = "pure recoveries a minute before they count as dirty (D15)"},
}

@(private)
st: struct {
	profile:   string,
	start_ns:  i64,
	sites:     [dynamic]web.Site,
	exit_code: int, // atomic: 70 after a dirty crash or a watchdog exit
	signalled: sync.Sema,
	stop_once: bool, // atomic
	lan:       []env.Cidr,
	port:      int,
	threads:   int,
}

// §8.6 steps 1-3, before any feature's init.
boot :: proc(profile: string) {
	st.profile = profile
	st.start_ns = sys.mono_ns()
	level := obs.Level.Info
	switch os.get_env("LOG_LEVEL", context.temp_allocator) {
	case "debug":          level = .Debug
	case "warn", "warning": level = .Warning
	case "error":          level = .Error
	}
	// A listing (--routes, --features, --limits) prints only its answer, which a
	// script parses: boot's warnings (nick's boot key, say) would land in it.
	for a in os.args[1:] {
		if a == "--routes" || a == "--features" || a == "--limits" { level = .Error }
	}
	obs.init(level)

	// The short-circuits that need no server state.
	for a in os.args[1:] {
		switch a {
		case "--healthcheck": os.exit(healthcheck())
		case "--worker":
			fmt.eprintln("--worker: this build runs no worker processes")
			os.exit(2)
		}
	}

	sys.raise_nofile()
	env.record("", PLATFORM_ENV[:])
	identity.init() // its env rows and keys, after the platform's (LAN_CIDRS)
	burst := guard.RECOVERY_BURST
	if v, ok := os.lookup_env("GUARD_BURST", context.temp_allocator); ok {
		if n, nok := strconv.parse_int(v, 10); nok && n > 0 { burst = n }
	}
	guard.install(on_crash, burst)
}

// §8.6 step 4: the boot checks, then the CLI that lists what boot recorded.
// `page_bundles` names the fixed bundles the profile's pages load (§12.1): the
// BUNDLES lines of its scripting and compat packages.
check :: proc(hosts: []Host, jobs: [][]workers.Job, bundle_exts: web.Exts, page_bundles := bit_set[web.Bundle]{}) {
	// A build that streams but has no topics calls no hub.init (a generated `status` alone, or
	// `scripting`): its streams' env rows are read here, or its first stream trapped.
	for h in hosts {
		for m in h.routes {
			for row in m.rows {
				if .Stream in row.flags { stream.init() }
			}
		}
	}
	mount(hosts)
	for &s in st.sites {
		for m in s.router.rows { m.obs = obs.register_route(m.id) }
	}
	problems := boot_checks(hosts, st.sites[:], jobs, bundle_exts, page_bundles)
	for p in env.problems() { append(&problems, p) }
	if len(problems) > 0 {
		fmt.eprintfln("%s: %d problem(s) at boot:", st.profile, len(problems))
		for p in problems { fmt.eprintfln("  - %s", p) }
		os.exit(2)
	}
	for name in env.unknown() {
		if l, ok := obs.begin(.Warning, "app", "env"); ok {
			obs.str(&l, "unknown", name)
			obs.end(&l)
		}
	}
	record_build(hosts, bundle_exts)
	answer_cli(hosts)
}

// The boot checks alone, for a profile's routes_test.odin: the problems, no exit.
dry_check :: proc(hosts: []Host, jobs: [][]workers.Job, bundle_exts: web.Exts, page_bundles := bit_set[web.Bundle]{}) -> [dynamic]string {
	sites := make([dynamic]web.Site, context.temp_allocator)
	for h in hosts { append(&sites, mounted(h)) }
	return boot_checks(hosts, sites[:], jobs, bundle_exts, page_bundles)
}

@(private)
mount :: proc(hosts: []Host) {
	for h in hosts { append(&st.sites, mounted(h)) }
	// A TEST_ROUTES build's crash drills, on every host (PLAN §19.1.10): a stream drill runs on
	// the host that mounts the stream (full's lab host). They sit in the router, not in a
	// mounted table, so --routes, the boot checks and route coverage never see them.
	when web.TEST_ROUTES {
		for &s in st.sites { web.router_mount(&s.router, web.TEST_ROUTE_ROWS[:]) }
		web.test_shutdown = request_shutdown
	}
}

@(private)
mounted :: proc(h: Host) -> (s: web.Site) {
	s.name, s.identity, s.nav = h.name, h.identity, h.nav
	for m in h.routes {
		web.router_mount(&s.router, m.rows)
	}
	return
}

// §8.6 steps 6-10: everything that serves, then the banner. Returns once every
// loop runs.
// `brands` names each host's brand in HOSTS' order where a second host has its own (full's lab
// host); without it every host is `brand`'s.
serve :: proc(hosts: []Host, jobs: [][]workers.Job, brand: ^html.Brand, headers := web.Header_Set.Standard, brands: []^html.Brand = nil) {
	// odin-http logs through core:log, whose default discards every line (F-8's
	// accept errors, F-12's io_uring hint). The threads started from here inherit it.
	context.logger = obs.logger()
	for &s, i in st.sites {
		s.brand = brands[i] if i < len(brands) && brands[i] != nil else brand
		origin := env.str(hosts[i].site_env) if hosts[i].site_env == "SITE_URL" else os.get_env(hosts[i].site_env, context.allocator)
		if origin == "" { origin = s.brand.site_url }
		s.origin = origin
		s.hostname = hostname_of(origin)
		s.redirect = !web.placeholder_origin(origin)
		s.robots = web.robots_for(&s)
	}
	// A request finds its host by name, so two hosts on one name would leave one unreachable.
	for s, i in st.sites {
		for t in st.sites[:i] {
			if s.hostname == t.hostname { fatal("%s and %s both name the host %q: give each its own (SITE_URL, %s)", t.name, s.name, s.hostname, hosts[i].site_env) }
		}
	}
	web.assets_init()
	web.security_init(headers, env.cidrs("TRUST_PROXY"))
	st.lan = env.cidrs("LAN_CIDRS")
	if path := env.str("METRICS_TOKEN_FILE"); path != "" {
		data, err := os.read_entire_file(path, context.allocator)
		if err != nil { fatal("METRICS_TOKEN_FILE=%s: can't read it (%v)", path, err) }
		web.metrics_token = strings.trim_space(string(data))
	}

	st.port = env.int_("PORT") if env.is_set("PORT") else port_from_args()
	st.threads = env.int_("THREADS")
	if st.threads <= 0 { st.threads = os.get_processor_core_count() }
	address: net.Address = net.IP4_Loopback
	host := "127.0.0.1"
	if env.str("BIND_ALL") != "" { address, host = net.IP4_Any, "0.0.0.0" }
	ms :: proc(name: string) -> time.Duration { return time.Duration(env.int_(name)) * time.Millisecond }
	obs.limit("http", "header_timeout", i64(env.int_("HEADER_TIMEOUT_MS")), "ms")
	obs.limit("http", "idle_timeout", i64(env.int_("IDLE_TIMEOUT_MS")), "ms")
	obs.limit("http", "body_timeout", i64(env.int_("BODY_TIMEOUT_MS")), "ms")
	obs.limit("http", "send_timeout", i64(env.int_("SEND_TIMEOUT_MS")), "ms")
	obs.limit("http", "drain_deadline", i64(env.int_("DRAIN_DEADLINE_MS")), "ms")
	obs.limit("http", "max_body", web.MAX_BODY, "B")

	guard.watchdog_start(on_fatal)
	install_signals()
	err := web.start({
		endpoint        = {address = address, port = st.port},
		threads         = st.threads,
		header_timeout  = ms("HEADER_TIMEOUT_MS"),
		idle_timeout    = ms("IDLE_TIMEOUT_MS"),
		body_timeout    = ms("BODY_TIMEOUT_MS"),
		send_timeout    = ms("SEND_TIMEOUT_MS"),
		drain_deadline  = ms("DRAIN_DEADLINE_MS"),
		max_connections = env.int_("MAX_CONNS"),
		front           = front,
		on_loop_start   = loop_start,
		on_loop_stop    = loop_stop,
		on_loop_release = loop_release,
	})
	if err != nil { fatal("listen on %s:%d failed: %v", host, st.port, err) }
	workers.schedule(jobs)

	// After bind: readiness is /readyz, never this line (13 §3.3).
	fmt.printfln("odin-htmx-starter %s listening on http://%s:%d (%d threads)", st.profile, host, st.port, st.threads)
	if l, ok := obs.begin(.Info, "app", "serving"); ok {
		obs.str(&l, "profile", st.profile)
		obs.str(&l, "version", web.VERSION)
		obs.str(&l, "site", st.sites[0].origin)
		obs.num(&l, "port", i64(st.port))
		obs.num(&l, "threads", i64(st.threads))
		obs.num(&l, "boot_ms", (sys.mono_ns() - st.start_ns) / 1e6)
		obs.end(&l)
	}
}

// §8.7 steps 1-2: blocks until SIGINT or SIGTERM (a second one exits at once),
// or a dirty crash; /readyz answers 503 from then on.
wait :: proc() {
	sync.sema_wait(&st.signalled)
	obs.set_draining()
}

// §8.7 steps 3-6: the fork's bounded drain on every loop (idle peers closed,
// active requests given DRAIN_DEADLINE_MS, timers cancelled); returns once
// every loop has finished.
shutdown :: proc() {
	obs.set_draining()
	// The watchdog stops here, so this bounds the rest (M1-05): the drain, then the
	// profile's closes (a store's writer can wait out SQLITE_BUSY) within 1.5 s more.
	thread.create_and_start_with_poly_data(time.Duration(env.int_("DRAIN_DEADLINE_MS")) * time.Millisecond + SHUTDOWN_GRACE, proc(after: time.Duration) {
		time.sleep(after)
		obs.bound_writes()
		if l, ok := obs.begin(.Fatal, "app", "exit"); ok {
			obs.str(&l, "why", "the shutdown didn't finish")
			obs.end(&l)
		}
		obs.flush()
		os.exit(guard.EXIT_DIRTY)
	})
	workers.unschedule()
	guard.watchdog_stop()
	web.stop()
}

// What the shutdown gets past DRAIN_DEADLINE_MS, for the profile's closes.
SHUTDOWN_GRACE :: 1500 * time.Millisecond

// §8.7 steps 7-8: logs flushed, then exit 0, or 70 after a dirty crash.
exit :: proc() -> ! {
	code := sync.atomic_load(&st.exit_code)
	if l, ok := obs.begin(.Info, "app", "exit"); ok {
		obs.num(&l, "code", i64(code))
		obs.end(&l)
	}
	obs.flush()
	os.exit(code)
}

// ---- the per-loop hooks (F-4) ---------------------------------------------------------

@(private)
loop_start :: proc(loop: int) {
	guard.thread_init()
	obs.thread_init(loop)
	arm_tick()
	workers.joined()     // other threads post to this loop only while it hasn't left (M1-05)
}

@(private)
loop_release :: proc(loop: int) {
	workers.leaving()
}

@(private)
loop_stop :: proc(loop: int) {
	disarm_tick()
	workers.drain_all() // queued tasks cancelled, so every reply lands within one task (S0.5)
	obs.flush()
}

// ---- helpers ------------------------------------------------------------------------

@(private)
fatal :: proc(format: string, args: ..any) -> ! {
	msg := fmt.tprintf(format, ..args)
	if l, ok := obs.begin(.Fatal, "app", "boot"); ok {
		obs.str(&l, "msg", msg)
		obs.end(&l)
	}
	obs.flush()
	fmt.eprintln(msg)
	os.exit(1)
}

@(private)
port_from_args :: proc() -> int {
	if len(os.args) > 1 {
		if p, ok := strconv.parse_int(os.args[1], 10); ok { return p }
	}
	return 8080
}

@(private)
hostname_of :: proc(origin: string) -> string {
	h := origin
	if i := strings.index(h, "://"); i >= 0 { h = h[i + 3:] }
	if i := strings.index_any(h, "/:"); i >= 0 { h = h[:i] }
	return h
}

@(private)
is_lan :: proc(a: net.Address) -> bool { return env.contains(st.lan, a) }
