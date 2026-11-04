package main

// ---- writerbench: the writer task against one commit per write (PLAN §18, D38) ---------------
//
//   sh tools/drills/chat-budget.sh        (builds this with the SQLite family)
//   writerbench [--messages N] [--rate R] [--seconds S] [--cap ROOM_CAP] [--db PATH]
//
// Chat's own post, through the store's real path, on a file in WAL mode with the search index's
// triggers and a retention cap: the rows and the transaction a member's message costs.
//
//   alone    each post waits for its answer, so every commit holds one: what autocommit costs.
//   queued   up to a window of posts in flight: what the writer's batching buys.
//   paced    R posts a second for S seconds: how long one waits at that rate, and how full
//            the batches were.

import "base:runtime"
import "core:fmt"
import "core:nbio"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

import "../../app/platform/obs"
import "../../app/platform/store"
import db "../../app/platform/store/sqlite"
import "../../app/platform/guard"
import m "../../app/features/chat/models"
import chat_store "../../app/stores/sqlite/chat"

WINDOW :: 1024
BODY :: "A message of about the length people write, to the room, on an ordinary afternoon."

room: i64
answered: int
failed: int
waits: [dynamic]i64

Timed :: struct {
	using post: m.Post,
	sent:       time.Tick,
}

send :: proc() -> bool {
	op := store.new_op(Timed, 2 * (len(BODY) + 8))
	a := store.op_allocator(op)
	op.room, op.author, op.name, op.body = room, 1, strings.clone("bench", a), strings.clone(BODY, a)
	op.sent = time.tick_now()
	op.done = proc(o: ^store.Op) {
		t := (^Timed)(o)
		if o.err != .None { failed += 1 }
		append(&waits, i64(time.tick_since(t.sent)))
		answered += 1
		store.free_op(o)
	}
	return chat_store.post(&op.post)
}

// Messages a second.
alone :: proc(n: int) -> f64 {
	start := time.tick_now()
	for i in 0 ..< n {
		base := answered
		if !send() { fmt.panicf("refused at %d", i) }
		for answered == base { nbio.tick(0) } // no timeout: the wait is the writer's, not this loop's
	}
	return f64(n) / time.duration_seconds(time.tick_since(start))
}

queued :: proc(n: int) -> f64 {
	start := time.tick_now()
	base, sent := answered, 0
	for answered - base < n {
		for sent < n && sent - (answered - base) < WINDOW {
			if !send() { break }
			sent += 1
		}
		nbio.tick(0)
	}
	return f64(n) / time.duration_seconds(time.tick_since(start))
}

paced :: proc(rate: int, seconds: int) {
	clear(&waits)
	total := rate * seconds
	gap := time.Second / time.Duration(rate)
	start := time.tick_now()
	base := answered
	for i in 0 ..< total {
		for time.tick_since(start) < time.Duration(i) * gap { nbio.tick(50 * time.Microsecond) }
		if !send() { fmt.panicf("refused at %d", i) }
	}
	for answered - base < total { nbio.tick(time.Millisecond) }
	slice.sort(waits[:])
	pct :: proc(p: int) -> f64 { return f64(waits[min(len(waits) - 1, len(waits) * p / 100)]) / 1e6 }
	fmt.printfln("paced    %d msgs/s for %d s: %d answered, ms p50 %.2f p95 %.2f p99 %.2f max %.2f", rate, seconds, len(waits), pct(50), pct(95), pct(99), f64(waits[len(waits) - 1]) / 1e6)
}

main :: proc() {
	n, rate, seconds, cap := 20_000, 1000, 10, 10_000
	path := "writerbench.db"
	args := os.args[1:]
	for i := 0; i + 1 < len(args); i += 2 {
		v, _ := strconv.parse_int(args[i + 1], 10)
		switch args[i] {
		case "--messages": n = v
		case "--rate":     rate = v
		case "--seconds":  seconds = v
		case "--db":       path = args[i + 1]
		case "--cap":      cap = v
		case:              fmt.panicf("unknown flag %s", args[i])
		}
	}
	context.allocator = runtime.heap_allocator()
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	if err := nbio.acquire_thread_event_loop(); err != nil { fmt.panicf("no event loop: %v", err) }
	defer nbio.release_thread_event_loop()
	for suffix in ([?]string{"", "-wal", "-shm"}) { os.remove(strings.concatenate({path, suffix})) }
	if why := db.open_db(path, .File, "writerbench"); why != "" { fmt.panicf("open: %s", why) }
	defer db.close()
	db.migrate("chat", chat_store.MIGRATIONS[:])

	keep: m.Retention
	keep.cap[.Public] = cap
	chat_store.init(0, keep)
	chat_store.seed()
	lobby, err := chat_store.room("lobby")
	if err != .None { fmt.panicf("no lobby: %v", err) }
	room = lobby.id

	a := alone(n)
	fmt.printfln("alone    %d messages, one commit each: %.0f msgs/s", n, a)
	q := queued(n)
	fmt.printfln("queued   %d messages, %d in flight: %.0f msgs/s", n, WINDOW, q)
	fmt.printfln("ratio    %.1f× (budget ≥ 3×)", q / a)
	paced(rate, seconds)
	if failed > 0 { fmt.printfln("%d writes failed", failed) }
}
