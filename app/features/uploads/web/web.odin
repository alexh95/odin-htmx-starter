package uploads_web

// ---- uploads: routes and handlers (PLAN §14.2, §17.6) ---------------------------------------
//
// JSON for static/uploads.js, the fetch shim: create, PUT each chunk, finish. Chunks, finishes
// and blobs touch the disk, so they run on pools of their own and answer through a deferred
// response; a pool's queue is the bound on what's held in memory (§17.6: 8 × 4 MiB), and past it
// `submit` refuses: 503, which the shim tries again. One decode at a time: a 40 MP image is a few
// hundred MiB of pixels. Reads have a wider pool: a room's page asks for its images all at once.
// A body is bounded before that, in `front` (its route's body_cap makes it a large one).

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:time"

import "../../../platform/guard"
import "../../../platform/web"
import "../../../platform/workers"
import uploads ".."
import m "../models"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Post, "/uploads", create, .Chat_Attach, {.Fragment}, 256},
	{.Get, "/uploads/(%d+)", progress, .Chat_Attach, {.Fragment}, 0},
	{.Put, "/uploads/(%d+)", chunk, .Chat_Attach, {.Fragment}, uploads.MAX_CHUNK},
	{.Post, "/uploads/(%d+)/finish", finish, .Chat_Attach, {.Fragment}, 0},
	{.Get, "/uploads/blob/(%w+)", blob, .Chat_Read, {.Fragment}, 0},
}

JOBS := [?]workers.Job {
	{"uploads.sweep", time.Hour, sweep_job, nil},
	{"uploads.mirror", 10 * time.Minute, mirror_job, mirror_due},
}

@(private) starts := web.Limit{window = time.Hour} // n: UPLOADS_PER_HOUR
@(private) writes: workers.Pool
@(private) decodes: workers.Pool
@(private) answering: int // atomic: bytes of blobs in answers not yet sent
@(private) MAX_ANSWERING :: 64 << 20
@(private) reads: workers.Pool

// At boot.
init :: proc() {
	uploads.init()
	guard.watch_work(&uploads.decoding)
	starts.n = uploads.per_hour()
	workers.start(&writes, "uploads", 2, 8)
	workers.start(&decodes, "decodes", 1, 8)
	workers.start(&reads, "blobs", 2, 32)
}

@(private)
sweep_job :: proc() {
	abandoned, unheld := uploads.sweep()
	if abandoned + unheld > 0 { workers.log("%d abandoned, %d blobs unheld", abandoned, unheld) }
}

// Where the nightly copy goes, from main.
backs_up_to :: proc(dir: string) { uploads.backs_up_to(dir) }

// Once a day, wherever there's a backup to sit beside.
@(private) MIRROR_EVERY :: 24 * time.Hour
@(private) mirrored: time.Tick

@(private)
mirror_due :: proc() -> bool {
	return uploads.mirror_dir() != "" && (mirrored == {} || time.tick_since(mirrored) >= MIRROR_EVERY)
}

@(private)
mirror_job :: proc() {
	dir := uploads.mirror_dir()
	if dir == "" {
		workers.log("no backups here")
		return
	}
	copied, removed, ok := uploads.mirror(dir)
	mirrored = time.tick_now()
	if ok {
		workers.log("%d copied, %d removed", copied, removed)
	} else {
		workers.fail("%d copied, %d removed, and some failed", copied, removed)
	}
}

@(private)
Refused :: struct {
	error: string `json:"error"`,
}

@(private)
refuse :: proc(res: ^web.Response, why: string, status: web.Status) {
	web.respond_json(res, Refused{why}, status)
}

// ---- the session ----------------------------------------------------------------------------

@(private)
create :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	if ok, retry := web.limit_hit(&starts, v.id); !ok {
		web.respond_limited(res, retry, "")
		return
	}
	size := web.query_int(req, "size", 0)
	id, problem, err := uploads.begin(v.id, size)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if problem != "" {
		refuse(res, problem, .Unprocessable_Content)
		return
	}
	Made :: struct {
		id:    i64 `json:"id"`,
		chunk: int `json:"chunk"`,
	}
	web.respond_json(res, Made{id, uploads.MAX_CHUNK}, .Created)
}

// The upload a path names, if it's the viewer's and still open; otherwise answered.
@(private)
open_upload :: proc(req: ^web.Request, res: ^web.Response) -> (u: m.Upload, ok: bool) {
	id, valid := web.parse_id(req.url_params[0])
	if !valid {
		web.not_found(req, res)
		return
	}
	err: m.Error
	if u, err = uploads.upload(id); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if u.user != web.viewer(req).id || u.state != .Open {
		web.not_found(req, res)
		return
	}
	return u, true
}

@(private)
Received :: struct {
	received: int `json:"received"`,
	size:     int `json:"size"`,
}

// How far it got: where a resume starts from.
@(private)
progress :: proc(req: ^web.Request, res: ^web.Response) {
	if u, ok := open_upload(req, res); ok { web.respond_json(res, Received{u.received, u.size}) }
}

// ---- a chunk --------------------------------------------------------------------------------

@(private)
Chunk :: struct {
	using task: workers.Task,
	deferred:   web.Deferred,
	id:         i64,
	off:        int,
	data:       []byte,
	err:        m.Error,
	size:       int,
}

@(private)
chunk :: proc(req: ^web.Request, res: ^web.Response) {
	u, ok := open_upload(req, res)
	if !ok { return }
	body := web.ctx().body
	off := web.query_int(req, "off", -1)
	if off != u.received {
		web.respond_json(res, Received{u.received, u.size}, .Conflict)
		return
	}
	if len(body) == 0 || off + len(body) > u.size {
		refuse(res, "That's more than the upload said it was.", .Unprocessable_Content)
		return
	}
	t := new(Chunk)
	t.id, t.off, t.size = u.id, off, u.size
	t.data = transmute([]byte)strings.clone(body) // the request's memory may be gone when it runs
	t.run, t.done = run_chunk, chunk_done
	web.defer_response(req, res, &t.deferred)
	if !workers.submit(&writes, &t.task) { chunk_done(&t.task) }
}

@(private)
run_chunk :: proc(t: ^workers.Task) {
	c := (^Chunk)(t)
	c.err = uploads.write_chunk(c.id, c.off, c.data)
}

// Back on the loop, or at once when the pool refused it.
@(private)
chunk_done :: proc(t: ^workers.Task) {
	c := (^Chunk)(t)
	defer free(c)
	defer delete(c.data)
	res := web.resume(&c.deferred)
	if res == nil { return }
	defer web.finish(&c.deferred, res)
	switch {
	case c.crashed, !c.ran:
		refuse(res, "Busy: try again in a moment.", .Service_Unavailable)
	case c.err != .None:
		web.respond_store_error(web.request(&c.deferred), res, c.err)
	case:
		web.respond_json(res, Received{c.off + len(c.data), c.size})
	}
}

// ---- finishing ------------------------------------------------------------------------------

@(private)
Finish :: struct {
	using task: workers.Task,
	deferred:   web.Deferred,
	upload:     m.Upload,
	holding:    uploads.Decoding, // freed here, on the loop, trap or not
	sha256:     [64]byte,
	problem:    string, // a constant of the domain's
	err:        m.Error,
}

@(private)
finish :: proc(req: ^web.Request, res: ^web.Response) {
	u, ok := open_upload(req, res)
	if !ok { return }
	if u.received != u.size {
		web.respond_json(res, Received{u.received, u.size}, .Conflict)
		return
	}
	t := new(Finish)
	t.upload = u
	t.run, t.done = run_finish, finish_done
	web.defer_response(req, res, &t.deferred)
	if !workers.submit(&decodes, &t.task) { finish_done(&t.task) }
}

@(private)
run_finish :: proc(t: ^workers.Task) {
	f := (^Finish)(t)
	b: m.Blob
	b, f.problem, f.err = uploads.conclude(f.upload, &f.holding)
	copy(f.sha256[:], b.sha256)
}

@(private)
finish_done :: proc(t: ^workers.Task) {
	f := (^Finish)(t)
	defer free(f)
	defer uploads.free_decoding(&f.holding)
	if f.crashed { uploads.drop(f.upload.id) } // a client that left doesn't get to try these bytes again
	res := web.resume(&f.deferred)
	if res == nil { return }
	defer web.finish(&f.deferred, res)
	Done :: struct {
		sha256: string `json:"sha256"`,
	}
	switch {
	case f.crashed: // the decoder trapped on these bytes
		refuse(res, "That image can't be read.", .Unprocessable_Content)
	case !f.ran:
		refuse(res, "Busy: try again in a moment.", .Service_Unavailable)
	case f.err != .None:
		web.respond_store_error(web.request(&f.deferred), res, f.err)
	case f.problem != "":
		refuse(res, f.problem, .Unprocessable_Content)
	case:
		web.respond_json(res, Done{string(f.sha256[:])})
	}
}

// ---- a blob ---------------------------------------------------------------------------------

@(private)
Reading :: struct {
	using task: workers.Task,
	deferred:   web.Deferred,
	sha256:     [64]byte,
	png:        bool,
	bytes:      int,
	data:       []byte,
	found:      bool,
}

// Only images exist here (the domain's check), and each goes out as what its row says, never as
// what a client guesses (`nosniff` on every response); §17.6's attachment waits for the first
// type that isn't one. Immutable: the address is the content.
@(private)
blob :: proc(req: ^web.Request, res: ^web.Response) {
	sha := req.url_params[0]
	if !uploads.valid_sha(sha) {
		web.not_found(req, res)
		return
	}
	b, err := uploads.blob(sha)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	// An answer sits in its connection's memory until the peer has it, so what's out is counted
	// until then: a pool's queue bounds only what's waiting to be read.
	if sync.atomic_add(&answering, b.bytes) + b.bytes > MAX_ANSWERING {
		sync.atomic_sub(&answering, b.bytes)
		web.respond_status(res, .Service_Unavailable)
		return
	}
	t := new(Reading)
	copy(t.sha256[:], sha)
	t.png = b.mime == uploads.MIME[.Png]
	t.bytes = b.bytes
	t.run, t.done = run_read, read_done
	web.defer_response(req, res, &t.deferred)
	if !workers.submit(&reads, &t.task) { read_done(&t.task) }
}

// What the sent answer, or the one that never went, gives back.
@(private)
answered :: proc(bytes: rawptr) { sync.atomic_sub(&answering, int(uintptr(bytes))) }

@(private)
run_read :: proc(t: ^workers.Task) {
	r := (^Reading)(t)
	r.data, r.found = uploads.read_blob(string(r.sha256[:]))
}

@(private)
read_done :: proc(t: ^workers.Task) {
	r := (^Reading)(t)
	defer free(r)
	defer uploads.free_bytes(r.data)
	res := web.resume(&r.deferred)
	if res == nil {
		answered(rawptr(uintptr(r.bytes)))
		return
	}
	web.after_sent(res, answered, rawptr(uintptr(r.bytes)))
	defer web.finish(&r.deferred, res)
	switch {
	case !r.ran:
		web.respond_status(res, .Service_Unavailable)
	case !r.found:
		web.respond_status(res, .Not_Found) // its row outlived its file
	case:
		web.set_header(res, "cache-control", "private, max-age=31536000, immutable")
		web.set_header(res, "content-disposition", "inline")
		web.respond_file(res, fmt.tprintf("%s.%s", string(r.sha256[:]), "png" if r.png else "jpg"), r.data)
	}
}
