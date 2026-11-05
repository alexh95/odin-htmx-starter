package web

// ---- a read off the loop (D16) ------------------------------------------------------------------
//
// What scans or ranks answers later: `work` runs on the store's query pool (at once where the store is
// memory, which has none), and `answer` back on this loop. Between the two everything lives in the
// scan's arena, which is the temp allocator for both; a pool thread's own is freed under it. The
// request's strings stay good: the connection waits for the answer.
//
//   Searching :: struct { using scan: web.Scan, q: string, hits: [dynamic]Hit }
//   s := web.new_scan(Searching, req, res, work, answer)
//   if s == nil { return }
//   s.q = q
//   web.start_scan(req, res, s)

import "base:runtime"
import "core:mem/virtual"

import "../workers"

Scan :: struct {
	using task: workers.Task,
	deferred:   Deferred,
	arena:      virtual.Arena,
	work:       proc(s: ^Scan),
	answer:     proc(s: ^Scan, req: ^Request, res: ^Response),
}

// nil: it has answered.
new_scan :: proc($T: typeid, req: ^Request, res: ^Response, work: proc(s: ^Scan), answer: proc(s: ^Scan, req: ^Request, res: ^Response)) -> ^T {
	t := new(T, runtime.heap_allocator())
	s := cast(^Scan)t
	if virtual.arena_init_growing(&s.arena) != nil {
		free(t, runtime.heap_allocator())
		respond_store_error(req, res, .Failed)
		return nil
	}
	s.work, s.answer = work, answer
	s.run = scan_run
	s.done = scan_done
	return t
}

// The handler's last word: the answer comes later.
start_scan :: proc(req: ^Request, res: ^Response, s: ^Scan) {
	defer_response(req, res, &s.deferred)
	if workers.query(&s.task) { return }
	if r := resume(&s.deferred); r != nil {
		respond_store_error(req, r, .Busy)
		finish(&s.deferred, r)
	}
	scan_free(s)
}

@(private = "file")
scan_run :: proc(t: ^workers.Task) {
	s := (^Scan)(t)
	context.temp_allocator = virtual.arena_allocator(&s.arena)
	s.work(s)
}

@(private = "file")
scan_done :: proc(t: ^workers.Task) {
	s := (^Scan)(t)
	defer scan_free(s)
	res := resume(&s.deferred)
	if res == nil { return }
	req := request(&s.deferred)
	context.temp_allocator = virtual.arena_allocator(&s.arena)
	switch {
	case !s.ran:    respond_store_error(req, res, .Busy)
	case s.crashed: respond_store_error(req, res, .Failed)
	case:           s.answer(s, req, res)
	}
	finish(&s.deferred, res)
}

@(private = "file")
scan_free :: proc(s: ^Scan) {
	virtual.arena_destroy(&s.arena)
	free(s, runtime.heap_allocator())
}
