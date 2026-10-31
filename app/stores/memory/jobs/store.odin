package jobs_store_memory

// ---- jobs in memory: this process's runs ------------------------------------------------------
//
// A memory build keeps the runs for the process's life, the newest KEPT of them: there is no
// earlier boot whose runs a restart could have interrupted, so `fail_lapsed` finds none.

import "base:runtime"
import "core:slice"
import "core:strings"

import m "../../../features/jobs/models"
import mem_store "../../../platform/store/memory"

IMPL :: "memory"

KEPT :: 500

@(private)
mem: struct {
	mu:   mem_store.Lock,
	runs: [dynamic]m.Run_Row, // their strings on the heap
}

save :: proc(rows: []m.Run_Row) -> m.Error {
	mem_store.lock(&mem.mu)
	defer mem_store.unlock(&mem.mu)
	a := runtime.heap_allocator()
	for r in rows {
		kept := r
		kept.job, kept.state, kept.log, kept.note = strings.clone(r.job, a), strings.clone(r.state, a), strings.clone(r.log, a), strings.clone(r.note, a)
		found := false
		for &old in mem.runs {
			if old.boot != r.boot || old.id != r.id { continue }
			release(old)
			old, found = kept, true
			break
		}
		if !found {
			if mem.runs == nil { mem.runs = make([dynamic]m.Run_Row, a) }
			append(&mem.runs, kept)
		}
	}
	for len(mem.runs) > KEPT {
		release(mem.runs[0])
		ordered_remove(&mem.runs, 0)
	}
	return .None
}

recent :: proc(limit: int, into: ^[dynamic]m.Run_Row) -> m.Error {
	mem_store.lock(&mem.mu)
	defer mem_store.unlock(&mem.mu)
	first := len(into)
	for r in mem.runs {
		c := copy_of(r)
		c.log = ""
		append(into, c)
	}
	slice.sort_by(into[first:], proc(a, b: m.Run_Row) -> bool { return a.queued_at > b.queued_at || a.queued_at == b.queued_at && a.id > b.id })
	if len(into) - first > limit { resize(into, first + limit) }
	return .None
}

run :: proc(boot, id: i64) -> (m.Run_Row, m.Error) {
	mem_store.lock(&mem.mu)
	defer mem_store.unlock(&mem.mu)
	for r in mem.runs {
		if r.boot == boot && r.id == id { return copy_of(r), .None }
	}
	return {}, .Not_Found
}

fail_lapsed :: proc(boot, now: i64) -> (int, m.Error) { return 0, .None }

prune :: proc(before: i64) -> (int, m.Error) {
	mem_store.lock(&mem.mu)
	defer mem_store.unlock(&mem.mu)
	n := 0
	for i := 0; i < len(mem.runs); {
		if r := mem.runs[i]; r.ended_at != 0 && r.ended_at < before {
			release(r)
			ordered_remove(&mem.runs, i)
			n += 1
		} else {
			i += 1
		}
	}
	return n, .None
}

// In the caller's temp arena.
@(private)
copy_of :: proc(r: m.Run_Row) -> m.Run_Row {
	c := r
	c.job, c.state, c.log, c.note = strings.clone(r.job, context.temp_allocator), strings.clone(r.state, context.temp_allocator),
		strings.clone(r.log, context.temp_allocator), strings.clone(r.note, context.temp_allocator)
	return c
}

@(private)
release :: proc(r: m.Run_Row) {
	a := runtime.heap_allocator()
	delete(r.job, a)
	delete(r.state, a)
	delete(r.log, a)
	delete(r.note, a)
}
