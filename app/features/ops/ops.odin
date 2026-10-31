package ops

// ---- ops: the domain (PLAN §15.4, D36) -----------------------------------------------------
//
// A minute of once-a-second samples of what the process is doing, and the panel rendered
// from the newest: the 1 Hz job renders it once and every viewer gets that one copy, by
// whichever refresh they chose, so N viewers cost one render. The crash file the last run
// left is read at boot and shown after a restart. Plain values, never HTTP.

import "base:runtime"
import "core:os"
import "core:strings"

import "../../platform/env"
import "../../platform/guard"
import "../../platform/obs"

HISTORY :: 60 // samples: a minute at 1 Hz

// The crash file's text, at most this much.
CRASH_SHOWN :: 4096

Sample :: struct {
	at_ns:          i64, // unix
	requests:       u64, // since boot
	per_s:          int, // requests in the last second
	streams:        int,
	queued:         int, // bytes waiting in the streams' queues
	published:      u64, // the hub's, since boot
	published_per_s: int,
	dropped:        u64,
	resyncs:        u64,
	rss:            int, // bytes; 0 where the OS gives none
	loops:          int,
	oldest_tick_ms: int,
	store:          obs.Store_Memory, // the SQLite connections' caches, schemas and statements
	has_store:      bool,
	drops:          u64, // writes queued for no one (audit's entries) a full writer refused, since boot (M4-04)
	has_drops:      bool, // a store that counts them is linked: none (a memory build), and the card says nothing
}

// A module's health, as it pushed it to obs (§10.4).
Module :: struct {
	name, state, message: string,
}

// A declared limit, as `--limits` lists them.
Limit :: struct {
	module, name, unit: string,
	value:              i64,
}

modules :: proc(out: ^[dynamic]Module) {
	for h in obs.modules() { append(out, Module{h.module, obs.STATE_NAMES[h.state], h.message}) }
}

limits :: proc(out: ^[dynamic]Limit) {
	for l in obs.declared_limits() { append(out, Limit{l.module, l.name, l.unit, l.value}) }
}

@(private)
st: struct {
	mu:      guard.Mutex,
	ring:    [HISTORY]Sample,
	n, head: int,
	seq:     u64,    // samples taken
	panel:   string, // the newest render, on the heap
	tag:     u64,    // the sample it was rendered from: the poll's tag
	crash:   string,
}

init :: proc() {
	if path := env.str("CRASH_FILE"); path != "" {
		if data, err := os.read_entire_file(path, heap()); err == nil {
			st.crash = strings.trim_space(string(data[:min(len(data), CRASH_SHOWN)]))
		}
	}
}

// What the last run left in the crash file ("" for none).
last_crash :: proc() -> string { return st.crash }

// A new sample, with its rates from the one before it.
record :: proc(s: Sample) -> (out: Sample, seq: u64) {
	out = s
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	if st.n > 0 {
		prev := st.ring[(st.head + st.n - 1) % HISTORY]
		secs := max(f64(s.at_ns - prev.at_ns) / 1e9, 0.001)
		out.per_s = int(f64(s.requests - prev.requests) / secs + 0.5)
		out.published_per_s = int(f64(s.published - prev.published) / secs + 0.5)
	}
	if st.n < HISTORY {
		st.ring[(st.head + st.n) % HISTORY] = out
		st.n += 1
	} else {
		st.ring[st.head] = out
		st.head = (st.head + 1) % HISTORY
	}
	st.seq += 1
	return out, st.seq
}

// The minute so far, oldest first, and the tag of the newest.
history :: proc(out: ^[dynamic]Sample) -> (seq: u64) {
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	for i in 0 ..< st.n { append(out, st.ring[(st.head + i) % HISTORY]) }
	return st.seq
}

// Keeps the panel rendered from sample `seq` (the poll's answer), replacing the last.
keep_panel :: proc(html: string, seq: u64) {
	copy := strings.clone(html, heap())
	guard.lock(&st.mu)
	old := st.panel
	st.panel, st.tag = copy, seq
	guard.unlock(&st.mu)
	delete(old, heap())
}

// The newest panel render, copied into the request, and its tag.
panel :: proc() -> (html: string, tag: u64) {
	guard.lock(&st.mu)
	defer guard.unlock(&st.mu)
	return strings.clone(st.panel, context.temp_allocator), st.tag
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }
