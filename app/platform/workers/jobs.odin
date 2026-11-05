package workers

// ---- the scheduler over the mounted JOBS rows ------------------------------
//
// A profile mounts each feature's `JOBS` table (PLAN §7.2) and app.serve hands
// them here. One thread wakes every second and runs what is due, guarded: the
// frequent jobs (due every minute or more often) itself, one at a time, and the
// others on a long-run thread, one at a time, so a long one (the backup) never
// holds the frequent ones (M5-03). `run_now` asks for a run at the next wake (the
// jobs page's button) and `cancel_run` asks a run to stop. A job with `due` decides
// at its `every` whether there is work (the nightly backup's hour).
//
// Each run is data (PLAN §15.4, LC §9): an id, a state, progress and a bounded
// log, kept in a ring of the last RUNS_KEPT, which features/jobs reads (by
// `runs_since`) into its table and its live page; workers never calls a feature.
// A job reaches its own run through `current()`: `progress`, `log` and
// `cancelled` (a job that loops checks it, and returns). A job due every minute
// or more often (ops's sampler, the lab's beat) isn't kept as runs unless it was
// asked for by hand: its counts are in its Job_State.

import "core:fmt"
import "core:sync"
import "core:thread"
import "core:time"

import "../guard"
import "../obs"
import "../sys"

Job :: struct {
	id:    string, // "notify.prune": the feature's prefix, then the job
	every: time.Duration,
	run:   proc(), // guarded, on the scheduler's thread (a frequent job) or the long-run thread
	// Optional: when its `every` comes, whether there is work (the nightly backup wakes every
	// 10 min and runs at its hour): false skips to the next `every` with no run kept. A run asked
	// for by hand doesn't ask it.
	due:   proc() -> bool,
}

Job_State :: struct {
	runs, crashes:    int,
	last_start_ns:    i64, // unix ns, 0 = never
	last_ms:          i64,
	next_ns:          i64, // mono ns
	running, wanted:  bool,
	wanted_run:       u64, // the run run_now made for it
}

Run_State :: enum u8 {
	Queued,
	Running,
	Done,
	Failed, // it crashed, or (features/jobs, at boot) a restart interrupted it
	Cancelled,
}

RUN_STATE_NAMES := [Run_State]string {
	.Queued    = "queued",
	.Running   = "running",
	.Done      = "done",
	.Failed    = "failed",
	.Cancelled = "cancelled",
}

RUNS_KEPT :: 64
LOG_BYTES :: 4096 // a run's log; past it, the newest lines are dropped and the log says so

Run :: struct {
	id:         u64, // from 1, per process
	job:        string,
	state:      Run_State,
	by_hand:    bool,
	queued_ns:  i64, // unix ns
	started_ns: i64,
	ended_ns:   i64,
	done:       i64, // progress: done of total (0 of 0: none said)
	total:      i64,
	log:        [LOG_BYTES]byte,
	log_len:    int,
	cut:        bool, // the log ran out of room
	cancel:     bool, // asked to stop: the job reads it through `cancelled`
	failed:     bool, // the job said so (`fail`): it ends failed, though it returned
	version:    u64, // the ring's version when this run last changed
}

@(private)
sched: struct {
	mu:        guard.Mutex, // taken by loop handlers too (run_now, the jobs page): the guard's, so a crash under it is dirty (M5-10)
	jobs:    []Job,
	state:   []Job_State,
	stop:    bool, // atomic
	ticker:  ^thread.Thread, // the scheduler
	ring:    [RUNS_KEPT]Run,
	next_id: u64,
	version: u64,
	// The long-run thread's one run at a time.
	long_wake: sync.Sema,
	long_busy: bool,
	long_job:  int,
	long_run:  ^Run,
	long_at:   i64,
	long:      ^thread.Thread,
}

@(private, thread_local)
tl_run: ^Run

// Once, after the loops run. The tables are the profile's package-level JOBS.
schedule :: proc(tables: [][]Job) {
	n := 0
	for t in tables { n += len(t) }
	if n == 0 { return }
	sched.jobs = make([]Job, n)
	sched.state = make([]Job_State, n)
	i := 0
	now := sys.mono_ns()
	for t in tables {
		for j in t {
			sched.jobs[i] = j
			sched.state[i].next_ns = now + i64(j.every)
			i += 1
		}
	}
	sched.ticker = thread.create_and_start(scheduler, context)
	sched.long = thread.create_and_start(long_runner, context)
}

// The jobs, in mount order; the table lives as long as the process.
jobs :: proc() -> []Job { return sched.jobs }

// Asks for a run at the next wake, as a queued run the page can show at once; a job already
// asked for answers the run it has. ok false: no such job.
run_now :: proc(id: string) -> (run: u64, ok: bool) {
	guard.lock(&sched.mu)
	defer guard.unlock(&sched.mu)
	for j, i in sched.jobs {
		if j.id != id { continue }
		st := &sched.state[i]
		if !st.wanted || st.wanted_run == 0 {
			r := new_run(j.id, true)
			if r == nil { return 0, false } // the ring is all queued and running runs
			r.queued_ns = sys.now_unix_ns()
			st.wanted, st.wanted_run = true, r.id
		}
		return st.wanted_run, true
	}
	return 0, false
}

// Asks a run to stop: a queued one is cancelled at once, a running one when its job next reads
// `cancelled` (a job that never does runs to its end). false: no such run, or it has ended.
cancel_run :: proc(run: u64) -> bool {
	guard.lock(&sched.mu)
	defer guard.unlock(&sched.mu)
	r := find_run(run)
	if r == nil { return false }
	switch r.state {
	case .Queued:
		r.state, r.ended_ns = .Cancelled, sys.now_unix_ns()
		for &st in sched.state {
			if st.wanted_run == run { st.wanted, st.wanted_run = false, 0 }
		}
	case .Running:
		r.cancel = true
	case .Done, .Failed, .Cancelled:
		return false
	}
	touch(r)
	return true
}

// A copy for a page to read.
job_state :: proc(id: string) -> (s: Job_State, ok: bool) {
	guard.lock(&sched.mu)
	defer guard.unlock(&sched.mu)
	for j, i in sched.jobs {
		if j.id == id { return sched.state[i], true }
	}
	return
}

// The kept runs that changed after `version`, oldest first, and the version now: a reader
// passes back what it was given. A run that fell out of the ring between two reads is gone.
runs_since :: proc(version: u64, out: ^[dynamic]Run) -> (now: u64) {
	guard.lock(&sched.mu)
	defer guard.unlock(&sched.mu)
	first := len(out)
	for r in sched.ring {
		if r.id != 0 && r.version > version { append(out, r) }
	}
	// By id: the ring wraps.
	for i in first + 1 ..< len(out) {
		for k := i; k > first && out[k].id < out[k - 1].id; k -= 1 { out[k], out[k - 1] = out[k - 1], out[k] }
	}
	return sched.version
}

// One kept run, by id.
run_of :: proc(id: u64) -> (r: Run, ok: bool) {
	guard.lock(&sched.mu)
	defer guard.unlock(&sched.mu)
	p := find_run(id)
	if p == nil { return }
	return p^, true
}

// ---- inside a job ------------------------------------------------------------------

// The run this thread is running, or nil (a frequent job's, or no job's).
current :: proc() -> ^Run { return tl_run }

progress :: proc(done, total: i64) {
	r := tl_run
	if r == nil { return }
	guard.lock(&sched.mu)
	r.done, r.total = done, total
	touch(r)
	guard.unlock(&sched.mu)
}

// A line of the run's log; past LOG_BYTES the newest lines are dropped.
log :: proc(format: string, args: ..any) {
	r := tl_run
	if r == nil { return }
	line := fmt.tprintf(format, ..args)
	guard.lock(&sched.mu)
	defer guard.unlock(&sched.mu)
	if r.log_len + len(line) + 1 > LOG_BYTES {
		r.cut = true
	} else {
		r.log_len += copy(r.log[r.log_len:], line)
		r.log[r.log_len] = '\n'
		r.log_len += 1
	}
	touch(r)
}

// The run ends failed, with this line in its log, when the job returns.
fail :: proc(format: string, args: ..any) {
	log(format, ..args)
	r := tl_run
	if r == nil { return }
	guard.lock(&sched.mu)
	r.failed = true
	touch(r)
	guard.unlock(&sched.mu)
}

cancelled :: proc() -> bool {
	r := tl_run
	if r == nil { return false }
	guard.lock(&sched.mu)
	defer guard.unlock(&sched.mu)
	return r.cancel
}

// At drain: no new runs; a running job finishes, and exit doesn't wait for it.
unschedule :: proc() {
	sync.atomic_store(&sched.stop, true)
	sync.sema_post(&sched.long_wake) // the long-run thread leaves at its next wait
}

// ---- the thread ----------------------------------------------------------------------

@(private)
scheduler :: proc() {
	guard.thread_init()
	for !sync.atomic_load(&sched.stop) {
		time.sleep(time.Second)
		for i in 0 ..< len(sched.jobs) {
			if sync.atomic_load(&sched.stop) { return }
			now := sys.mono_ns()
			job := sched.jobs[i]
			guard.lock(&sched.mu)
			st := &sched.state[i]
			due := !st.running && (st.wanted || now >= st.next_ns)
			if due && !st.wanted && job.due != nil {
				guard.unlock(&sched.mu)
				@(static) wants: bool
				wants = false
				guard.call(proc(data: rawptr) { wants = (proc() -> bool)(data)() }, rawptr(job.due))
				guard.lock(&sched.mu)
				if !wants && !st.wanted {
					st.next_ns = now + i64(job.every)
					guard.unlock(&sched.mu)
					continue
				}
			}
			// A job due less often than every minute runs on the long-run thread, one at a time, so a
			// backup never stops the 1 s jobs (the runs' sync among them, which shows its progress:
			// M5-03); while that thread is busy it stays due, and goes at a later wake. A frequent
			// job stays here even when asked for by hand, so a click never parks it behind a
			// backup (M5-13).
			long := job.every > time.Minute
			kept := st.wanted_run != 0 || long
			if !due || long && sched.long_busy {
				guard.unlock(&sched.mu)
				continue
			}
			r: ^Run
			if st.wanted_run != 0 {
				r = find_run(st.wanted_run)
			} else if kept {
				r = new_run(job.id, false)
				if r != nil { r.queued_ns = sys.now_unix_ns() }
			}
			st.running, st.wanted, st.wanted_run = true, false, 0
			st.last_start_ns = sys.now_unix_ns()
			if r != nil {
				r.state, r.started_ns = .Running, st.last_start_ns
				touch(r)
			}
			if long {
				sched.long_busy, sched.long_job, sched.long_run, sched.long_at = true, i, r, now
				guard.unlock(&sched.mu)
				sync.sema_post(&sched.long_wake)
				continue
			}
			guard.unlock(&sched.mu)
			execute(i, r, now)
		}
	}
}

// The long-run thread: each kept run the scheduler hands it, in turn.
@(private)
long_runner :: proc() {
	guard.thread_init()
	for {
		sync.sema_wait(&sched.long_wake)
		if sync.atomic_load(&sched.stop) { return }
		guard.lock(&sched.mu)
		i, r, at := sched.long_job, sched.long_run, sched.long_at
		guard.unlock(&sched.mu)
		execute(i, r, at)
		guard.lock(&sched.mu)
		sched.long_busy = false
		guard.unlock(&sched.mu)
	}
}

// One run of job i, guarded, on this thread; its state and its run's after.
@(private)
execute :: proc(i: int, r: ^Run, now: i64) {
	job := sched.jobs[i]
	tl_run = r
	ok := guard.call(proc(data: rawptr) { (proc())(data)() }, rawptr(job.run))
	tl_run = nil
	if !ok { crashed() }
	// A job that runs every minute or more often (the lab's beat) logs its runs
	// at debug; its counts are in the job's state either way. One that said it
	// failed (`fail`) is a warning, so a nightly that stopped shows in the log.
	failed := r != nil && r.failed
	level: obs.Level = .Error if !ok else .Warning if failed else .Debug if job.every <= time.Minute else .Info
	if l, lok := obs.begin(level, "jobs", "run"); lok {
		obs.str(&l, "job", job.id)
		obs.num(&l, "ms", (sys.mono_ns() - now) / 1e6)
		if !ok { obs.str(&l, "result", "crashed") } else if failed { obs.str(&l, "result", "failed") }
		obs.end(&l)
	}
	guard.lock(&sched.mu)
	st := &sched.state[i]
	st.running = false
	st.runs += 1
	if !ok { st.crashes += 1 }
	st.last_ms = (sys.mono_ns() - now) / 1e6
	st.next_ns = sys.mono_ns() + i64(job.every)
	if r != nil {
		r.state = .Failed if !ok || r.failed else .Cancelled if r.cancel else .Done
		r.ended_ns = sys.now_unix_ns()
		touch(r)
	}
	guard.unlock(&sched.mu)
	free_all(context.temp_allocator)
}

// Under sched.mu: the ring's next slot, overwriting the oldest run; nil while that one is still
// queued or running (a running job holds a pointer to it).
@(private)
new_run :: proc(job: string, by_hand: bool) -> ^Run {
	slot := &sched.ring[sched.next_id % RUNS_KEPT]
	if slot.id != 0 && (slot.state == .Queued || slot.state == .Running) { return nil }
	sched.next_id += 1
	r := slot
	r^ = Run{id = sched.next_id, job = job, state = .Queued, by_hand = by_hand}
	touch(r)
	return r
}

@(private)
find_run :: proc(id: u64) -> ^Run {
	if id == 0 { return nil }
	r := &sched.ring[(id - 1) % RUNS_KEPT]
	return r if r.id == id else nil
}

@(private)
touch :: proc(r: ^Run) {
	sched.version += 1
	r.version = sched.version
}
