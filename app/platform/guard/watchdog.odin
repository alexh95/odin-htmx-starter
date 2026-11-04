package guard

// ---- the watchdog (D15 rule 4) ---------------------------------------------
//
// A thread that wakes every second. A loop whose last tick is older than STALL,
// or a watched lock held longer than LOCK_LIMIT, is a hang the guard can't see
// (nothing traps), so it becomes an exit: one fatal line naming the loop, its
// route and request id, then the app's `on_fatal` (it writes last-crash.txt and
// exits 70). Docker outside Swarm never restarts an unhealthy container (13 §3),
// so this is what turns a hang into a restart. It is told to stop at drain and
// never joined: it sleeps between checks, and exit doesn't wait for it (S0.7).

import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

import "../obs"

STALL :: 10 * time.Second
LOCK_LIMIT :: 5 * time.Second

// The app's last words before a watchdog exit: it keeps what it keeps (the crash
// file) and arms the exit, which the log line after it can't then hold up
// (M1-03). id and route: the stalled request, if any.
On_Fatal :: #type proc(why, id, route: string)

@(private)
Watched :: struct {
	m:    ^Mutex,
	name: string,
}

@(private)
wd: struct {
	on_fatal: On_Fatal,
	stall:    time.Duration,
	locks:    [8]Watched,
	nlocks:   int,
	stop:     bool, // atomic
}

// At boot, before the watchdog starts: the store's write lock.
watch_lock :: proc(m: ^Mutex, name: string) {
	assert(wd.nlocks < len(wd.locks))
	wd.locks[wd.nlocks] = {m, name}
	wd.nlocks += 1
}

watchdog_start :: proc(on_fatal: On_Fatal, stall := STALL) {
	wd.on_fatal = on_fatal
	wd.stall = stall
	thread.create_and_start(_watchdog_run, context)
}

watchdog_stop :: proc() {
	sync.atomic_store(&wd.stop, true)
}

@(private)
_watchdog_run :: proc() {
	buf: [64]byte
	for !sync.atomic_load(&wd.stop) {
		time.sleep(time.Second)
		if sync.atomic_load(&wd.stop) { return }
		loop, age := obs.oldest_tick()
		if loop >= 0 && time.Duration(age) > wd.stall {
			id, route := obs.loop_request(loop, buf[:])
			_fatal("loop stalled", loop, age, id, route)
			return
		}
		for w in wd.locks[:wd.nlocks] {
			if held := held_ns(w.m); time.Duration(held) > LOCK_LIMIT {
				_fatal(w.name, -1, held, "", "")
				return
			}
		}
	}
}

@(private)
_fatal :: proc(why: string, loop: int, age_ns: i64, id, route: string) {
	// The exit first: a stalled log pipe is one of the hangs this ends (M1-03).
	obs.bound_writes()
	if wd.on_fatal != nil { wd.on_fatal(why, id, route) }
	if l, ok := obs.begin(.Fatal, "guard", "watchdog"); ok {
		obs.str(&l, "why", why)
		if loop >= 0 { obs.num(&l, "loop", i64(loop)) }
		obs.num(&l, "ms", age_ns / 1e6)
		obs.str(&l, "id", id)
		obs.str(&l, "route", route)
		obs.end(&l)
	}
	obs.flush()
	os.exit(EXIT_DIRTY)
}
