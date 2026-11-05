package obs

// ---- health and limits ----------------------------------------------------
//
// The operability contract (PLAN §10.4, LC §5): a feature pushes its health when
// it changes, never through a call that could wait on a lock, and declares every
// cap and timeout at init by name, value and unit, which boot prints, --limits
// lists and /readyz?detail shows. A critical module that is Down fails /readyz;
// an optional backend reports Degraded and never does.

import "core:strings"
import "core:sync"

import "../sys"

State :: enum u8 {
	Ok,
	Degraded,
	Down,
}

STATE_NAMES := [State]string {
	.Ok       = "ok",
	.Degraded = "degraded",
	.Down     = "down",
}

Health :: struct {
	module:   string,
	state:    State,
	since:    i64, // unix ns
	message:  string, // a literal, or a string that lives as long as the process
	critical: bool,
	link:     string, // a literal: the module's own page, when it has one
}

Limit :: struct {
	module, name: string,
	value:        i64,
	unit:         string, // "B", "ms", "conns", "" …
}

MAX_MODULES :: 64

@(private)
health: struct {
	mu:      sync.Mutex,
	modules: [MAX_MODULES]Health,
	n:       int,
}

@(private)
limits: [dynamic]Limit

set_health :: proc(module: string, s: State, message := "", critical := false) {
	sync.mutex_lock(&health.mu)
	defer sync.mutex_unlock(&health.mu)
	for &h in health.modules[:health.n] {
		if h.module == module {
			if h.state != s { h.since = sys.now_unix_ns() }
			h.state, h.message = s, message
			h.critical ||= critical
			return
		}
	}
	assert(health.n < MAX_MODULES, "obs: too many modules")
	health.modules[health.n] = {module = module, state = s, since = sys.now_unix_ns(), message = message, critical = critical}
	health.n += 1
}

// A copy, so the caller reads it without the lock.
modules :: proc(allocator := context.temp_allocator) -> []Health {
	sync.mutex_lock(&health.mu)
	defer sync.mutex_unlock(&health.mu)
	out := make([]Health, health.n, allocator)
	copy(out, health.modules[:health.n])
	return out
}

// Every critical module is up and the server isn't draining.
ready :: proc() -> (ok: bool, why: string) {
	if is_draining() { return false, "draining" }
	sync.mutex_lock(&health.mu)
	defer sync.mutex_unlock(&health.mu)
	for h in health.modules[:health.n] {
		if h.critical && h.state == .Down { return false, h.module }
	}
	return true, ""
}

// Where a module is run from: /admin/modules links there without importing it (LC §9).
set_health_link :: proc(module, link: string) {
	sync.mutex_lock(&health.mu)
	defer sync.mutex_unlock(&health.mu)
	for &h in health.modules[:health.n] {
		if h.module == module { h.link = link }
	}
}

// At init, before the loops run.
limit :: proc(module, name: string, value: i64, unit := "") {
	append(&limits, Limit{module, name, value, unit})
}

declared_limits :: proc() -> []Limit {
	return limits[:]
}

// `ok`, or one line per module: `store ok`, `llama degraded: no answer in 2 s`.
render_health :: proc(b: ^strings.Builder) {
	for h in modules() {
		strings.write_string(b, h.module)
		strings.write_byte(b, ' ')
		strings.write_string(b, STATE_NAMES[h.state])
		if h.message != "" {
			strings.write_string(b, ": ")
			strings.write_string(b, h.message)
		}
		strings.write_byte(b, '\n')
	}
}
