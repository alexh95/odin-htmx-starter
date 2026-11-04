package web

// ---- rate limits (§17.5) ------------------------------------------------------------------
//
// spark's fixed-window limiter: `n` hits per `window` per key, a member's id or a
// client's `client_key`, counted per process. A fixed window allows 2× `n` across a
// boundary, which §17.5's "burst" figures are (chat's 5 per 10 s, burst 10). The keys
// are bounded: past MAX_KEYS a limit forgets everyone, which only ever lets a hit
// through that would have been refused.

import "base:runtime"
import "core:strconv"
import "core:time"

import "../guard"
import "../sys"

Limit :: struct {
	n:      int,
	window: time.Duration,
	mu:     guard.Mutex,
	keys:   map[u64][2]i64, // key → {the window it counts, hits in it}
}

@(private)
MAX_KEYS :: 4096

// Counts a hit for `key`: ok, or how long until its window ends.
limit_hit :: proc(l: ^Limit, key: u64) -> (ok: bool, retry_after: time.Duration) {
	now := sys.mono_ns()
	win := now / i64(l.window)
	guard.lock(&l.mu)
	if l.keys == nil { l.keys = make(map[u64][2]i64, runtime.heap_allocator()) }
	if len(l.keys) >= MAX_KEYS { clear(&l.keys) }
	seen := l.keys[key]
	if seen[0] != win { seen = {win, 0} }
	seen[1] += 1
	l.keys[key] = seen
	guard.unlock(&l.mu)
	if seen[1] <= i64(l.n) { return true, 0 }
	return false, time.Duration((win + 1) * i64(l.window) - now)
}

// What is left of `key`'s window: n less its hits in it.
limit_left :: proc(l: ^Limit, key: u64) -> int {
	win := sys.mono_ns() / i64(l.window)
	guard.lock(&l.mu)
	seen := l.keys[key]
	guard.unlock(&l.mu)
	if seen[0] != win { return l.n }
	return max(0, l.n - int(seen[1]))
}

// A refused hit's 429: `Retry-After` in whole seconds, and `body` (a toast the
// form's hx-status:429 routes to the toast slot).
respond_limited :: proc(res: ^Response, retry_after: time.Duration, body: string) {
	buf: [24]byte
	secs := max(1, i64((retry_after + time.Second - 1) / time.Second))
	set_header(res, "retry-after", strconv.write_int(buf[:], secs, 10))
	respond_html(res, body, .Too_Many_Requests)
}

// ---- large bodies (§17.6) -----------------------------------------------------------------

// A route whose body_cap is at least this holds up to that much in its connection's buffer before
// the handler runs, so `front` counts them, and refuses past the counts before reading a byte.
LARGE_BODY :: 1 << 20
LARGE_AT_ONCE :: 8
LARGE_PER_MEMBER :: 2

@(private)
large: struct {
	mu:   guard.Mutex,
	all:  int,
	each: map[u64]int,
}

// By its Content-Length; a body that won't say counts.
declares_large :: proc(req: ^Request) -> bool {
	n, ok := parse_digits(header(req, "content-length"))
	return !ok || n >= LARGE_BODY
}

large_begin :: proc(user: u64) -> bool {
	guard.lock(&large.mu)
	defer guard.unlock(&large.mu)
	if large.each == nil { large.each = make(map[u64]int, runtime.heap_allocator()) }
	if large.all >= LARGE_AT_ONCE || large.each[user] >= LARGE_PER_MEMBER { return false }
	large.all += 1
	large.each[user] += 1
	return true
}

large_end :: proc(user: u64) {
	guard.lock(&large.mu)
	defer guard.unlock(&large.mu)
	large.all -= 1
	if large.each[user] <= 1 { delete_key(&large.each, user) } else { large.each[user] -= 1 }
}

