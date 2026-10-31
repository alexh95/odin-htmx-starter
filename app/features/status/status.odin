package status

// ---- status: the domain (PLAN §15.4, D36) -------------------------------------------------
//
// What the status page shows, one probe a line: every module's health as it pushed it to obs
// (§10.4), whether every event loop still ticks, the process itself, the disk the data is on,
// and the STATUS_PROBES externals (the lab's witness board, M3: the other witnesses' /healthz).
// Each external has a prober thread of its own, probing every WATCH_EVERY and whenever a page
// asks for an answer fresher than FRESH. A probe's connect and reads share one PROBE_TIMEOUT
// (M5-09); a name to resolve takes the resolver's own time on top (core:net's 1 s a name server
// on POSIX, the system's on Windows), so give externals an address where that matters. A page
// waits on that thread's next answer (one probe in flight per external, however many pages ask),
// and its part goes out when it comes (M5: the parts swap in parallel order). A page never waits
// longer than ANSWER_WITHIN.

import "core:fmt"
import "core:hash"
import "core:net"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "../../platform/env"
import "../../platform/guard"
import "../../platform/obs"
import "../../platform/sys"

ENV := [?]env.Row {
	{name = "STATUS_PROBES", kind = .String, doc = "external probes: name=host:port, comma-separated (the lab's witnesses: their /healthz)"},
	{name = "STATUS_DISK", kind = .String, def = ".", doc = "the path whose filesystem the disk part reports (/data in the image)"},
}

WATCH_EVERY :: 10 * time.Second
PROBE_TIMEOUT :: 2 * time.Second
FRESH :: 5 * time.Second // an answer this recent is sent as it is
ANSWER_WITHIN :: PROBE_TIMEOUT + 500 * time.Millisecond // then the part says there was none
MAX_EXTERNALS :: 16
MAX_WAITERS :: 64 // per external: a page past these gets the last answer at once

// Free space under this share of the disk is degraded.
DISK_LOW :: 0.10

// A newest backup older than this is degraded: the nightly one was missed.
BACKUP_STALE :: 26 * time.Hour

// A loop that hasn't ticked for this long is stuck (/livez says the same at 30 s, and the
// watchdog exits at 10 s: past 2 s the page already says something is wrong).
STUCK :: 2 * time.Second

Probe :: struct {
	name, state, message: string,
	public:               bool, // an external's message (its version, its time) is what it answers anyone
}

// An external probe and what it last said; `message` lives on the heap, owned by its prober.
External :: struct {
	name, host: string,
	state:      string,
	message:    string,
	answered:   i64,  // mono ns of the last answer; 0: none yet
	asked:      bool, // a page wants an answer: the prober goes now
	waiters:    [dynamic]^Waiter,
	wake:       sync.Sema, // posted once per ask; the prober sleeps on it between probes
}

// A page waiting for one external's next answer. `answered` runs on the prober's thread, so it
// only hands the news on to the page's loop.
Waiter :: struct {
	answered: proc(w: ^Waiter),
	user:     rawptr,
	index:    int,
}

@(private)
externals: struct {
	mu:   guard.Mutex, // loop handlers take it, so a trap under it is dirty (M5-10)
	list: [dynamic]External, // never grows after init: the probers hold pointers into it
}

@(private)
st: struct {
	started_ns: i64,
	disk:       string,
}

init :: proc() {
	st.started_ns = sys.mono_ns()
	env.record("", ENV[:])
	st.disk = env.str("STATUS_DISK")
	externals.list = parse_probes(env.str("STATUS_PROBES"))
	for i in 0 ..< len(externals.list) {
		thread.create_and_start_with_poly_data(i, prober, self_cleanup = true)
	}
}

// `name=host:port,…`: a name is lower-case letters, digits and dashes (it becomes an element
// id); a malformed entry is skipped, and so said on stderr by the caller's env dump.
parse_probes :: proc(s: string) -> [dynamic]External {
	out := make([dynamic]External)
	rest := s
	for item in strings.split_iterator(&rest, ",") {
		eq := strings.index_byte(item, '=')
		if eq <= 0 { continue }
		name, host := strings.trim_space(item[:eq]), strings.trim_space(item[eq + 1:])
		if !is_name(name) || strings.index_byte(host, ':') <= 0 || len(out) == MAX_EXTERNALS { continue }
		append(&out, External{name = strings.clone(name), host = strings.clone(host), state = "checking"})
	}
	return out
}

@(private)
is_name :: proc(s: string) -> bool {
	if s == "" { return false }
	for c in transmute([]byte)s {
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') { return false }
	}
	return true
}

externals_count :: proc() -> int { return len(externals.list) }

// An external's last answer, its message in the temp arena; `fresh` when it is recent enough to
// send as it is.
external :: proc(i: int) -> (p: Probe, fresh: bool) {
	guard.lock(&externals.mu)
	defer guard.unlock(&externals.mu)
	e := &externals.list[i]
	p = Probe{e.name, e.state, strings.clone(e.message, context.temp_allocator), true}
	return p, e.answered != 0 && sys.mono_ns() - e.answered < i64(FRESH)
}

// Asks for external i's next answer, which calls w.answered; false when too many already wait
// (the caller sends the last answer).
wait_for :: proc(i: int, w: ^Waiter) -> bool {
	guard.lock(&externals.mu)
	defer guard.unlock(&externals.mu)
	e := &externals.list[i]
	if len(e.waiters) >= MAX_WAITERS { return false }
	w.index = i
	append(&e.waiters, w)
	if !e.asked { sync.sema_post(&e.wake) }
	e.asked = true
	return true
}

// One external's thread: a probe at once, then every WATCH_EVERY or as soon as a page asks.
@(private)
prober :: proc(i: int) {
	host := externals.list[i].host
	for {
		state, message := probe(host)
		guard.lock(&externals.mu)
		e := &externals.list[i]
		delete(e.message)
		e.state, e.message, e.answered, e.asked = state, message, sys.mono_ns(), false
		waiting := make([]^Waiter, len(e.waiters), context.temp_allocator)
		copy(waiting, e.waiters[:])
		clear(&e.waiters)
		guard.unlock(&externals.mu)
		for w in waiting { w.answered(w) }
		// This thread is no request: nothing frees its temp allocator but this, and every probe's
		// request line and resolver lookups land there (M3-01).
		free_all(context.temp_allocator)
		// The lock is never held while sleeping: every page that reads the board would wait out the sleep.
		since := time.tick_now()
		for {
			guard.lock(&externals.mu)
			asked := externals.list[i].asked
			guard.unlock(&externals.mu)
			left := WATCH_EVERY - time.tick_since(since)
			if asked || left <= 0 { break }
			_ = sync.sema_wait_with_timeout(&externals.list[i].wake, left)
		}
	}
}

// GET /healthz on `host` (host:port), blocking on this thread: "ok" with the witness's version
// and time, or "down" and why. The message is heap-allocated for the board.
probe :: proc(host: string) -> (state, message: string) {
	t0 := time.tick_now()
	ep, rerr := net.resolve_ip4(host)
	if rerr != nil { return "down", fmt.aprintf("%s doesn't resolve", host) }
	any_sock, serr := net.create_socket(.IP4, .TCP)
	if serr != nil { return "down", fmt.aprintf("%s: no socket", host) }
	sock := any_sock.(net.TCP_Socket)
	defer net.close(sock)
	connected, timed_out := sys.connect_within(sock, ep, PROBE_TIMEOUT)
	if timed_out { return "down", fmt.aprintf("%s: no connection in %.0f ms", host, time.duration_milliseconds(PROBE_TIMEOUT)) }
	if !connected { return "down", fmt.aprintf("%s refused the connection", host) }
	net.set_option(sock, .Send_Timeout, PROBE_TIMEOUT)
	req := fmt.tprintf("GET /healthz HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", host)
	if _, err := net.send_tcp(sock, transmute([]byte)req); err != nil { return "down", fmt.aprintf("%s: the request didn't go out", host) }
	buf: [2048]byte
	n := 0
	// Each read waits only for what is left of PROBE_TIMEOUT, against a peer that drips (M5-09).
	for n < len(buf) {
		// Under a millisecond the option rounds to 0, which is no timeout at all (M5-19).
		left := PROBE_TIMEOUT - time.tick_since(t0)
		if left < time.Millisecond || net.set_option(sock, .Receive_Timeout, left) != nil { break }
		got, err := net.recv_tcp(sock, buf[n:])
		if err != nil || got == 0 { break }
		n += got
	}
	head := string(buf[:n])
	ms := time.duration_milliseconds(time.tick_since(t0))
	if !strings.has_prefix(head, "HTTP/1.1 200 ") {
		if n == 0 { return "down", fmt.aprintf("no answer in %.0f ms", ms) }
		line, _, _ := strings.partition(head, "\r\n")
		return "down", fmt.aprintf("%s", line)
	}
	version := "?"
	lines := head
	for line in strings.split_lines_iterator(&lines) {
		if len(line) > 11 && strings.equal_fold(line[:10], "x-version:") { version = strings.trim_space(line[10:]); break }
	}
	return "ok", fmt.aprintf("version %s, %.0f ms", version, ms)
}

// The probes the process answers itself; `board` adds the externals' last answers.
local :: proc(version: string, out: ^[dynamic]Probe) {
	for h in obs.modules() { append(out, Probe{h.module, obs.STATE_NAMES[h.state], h.message, false}) }
	loop, age := obs.oldest_tick()
	if age > i64(STUCK) {
		append(out, Probe{"loops", "down", fmt.tprintf("loop %d last ticked %d ms ago", loop, age / 1e6), false})
	} else {
		append(out, Probe{"loops", "ok", fmt.tprintf("%d ticking", obs.loops), false})
	}
	up := time.Duration(sys.mono_ns() - st.started_ns)
	append(out, Probe{"process", "ok", fmt.tprintf("up %s, version %s", uptime(up), version), false})
	append(out, disk())
	if p, ok := backups(); ok { append(out, p) }
}

board :: proc(version: string, out: ^[dynamic]Probe) {
	local(version, out)
	guard.lock(&externals.mu)
	for e in externals.list {
		append(out, Probe{e.name, e.state, strings.clone(e.message, context.temp_allocator), true})
	}
	guard.unlock(&externals.mu)
}

// The data's filesystem: degraded under DISK_LOW free.
disk :: proc() -> Probe {
	free, total, ok := sys.disk_free(st.disk)
	if !ok || total <= 0 { return Probe{"disk", "down", fmt.tprintf("%s can't be read", st.disk), false} }
	state := "ok" if f64(free) >= DISK_LOW * f64(total) else "degraded"
	return Probe{"disk", state, fmt.tprintf("%s free of %s", size(free), size(total)), false}
}

// The newest backup's age, where the store keeps backups (a file database).
backups :: proc() -> (p: Probe, ok: bool) {
	ms, kept := obs.last_backup()
	if !kept { return }
	if ms == 0 { return Probe{"backups", "degraded", "none yet", false}, true }
	age := time.Duration(sys.now_unix_ns() - ms * 1e6)
	state := "ok" if age < BACKUP_STALE else "degraded"
	return Probe{"backups", state, fmt.tprintf("the newest is %s old", uptime(age)), false}, true
}

@(private)
size :: proc(n: i64) -> string {
	GB :: 1 << 30
	if n >= 10 * GB { return fmt.tprintf("%d GB", n / GB) }
	return fmt.tprintf("%.1f GB", f64(n) / GB)
}

// The board's tag for a poll: the states alone, so a message that changes (the uptime) is no
// reason to send the board again.
tag :: proc(probes: []Probe) -> u64 {
	h: u64 = 14695981039346656037
	for p in probes {
		h = hash.fnv64a(transmute([]byte)p.name, h)
		h = hash.fnv64a(transmute([]byte)p.state, h)
	}
	return h
}

@(private)
uptime :: proc(d: time.Duration) -> string {
	s := int(d / time.Second)
	switch {
	case s < 60:    return fmt.tprintf("%d s", s)
	case s < 3600:  return fmt.tprintf("%d min", s / 60)
	case s < 86400: return fmt.tprintf("%d h %d min", s / 3600, s % 3600 / 60)
	}
	return fmt.tprintf("%d d %d h", s / 86400, s % 86400 / 3600)
}
