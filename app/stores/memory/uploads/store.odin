package uploads_store_memory

// ---- uploads in memory (PLAN §14.2, X13) ---------------------------------------------------
//
// The session rows and the blobs' metadata behind the store's lock, lost on restart: so an upload
// doesn't resume across one here, and a blob's file outlives its row. Bounded, the oldest going
// first: a nickname costs nothing to make.

import "core:strings"

import mem_store "../../../platform/store/memory"
import m "../../../features/uploads/models"

IMPL :: "memory"

MAX_ROWS :: 4096

@(private)
s: struct {
	lock:    mem_store.Lock,
	seq:     mem_store.Seq,
	uploads: [dynamic]m.Upload,
	blobs:   [dynamic]m.Blob, // their strings on the heap
}

init :: proc() {}

create :: proc(user: u64, size: int, at: i64) -> (id: i64, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if len(s.uploads) >= MAX_ROWS { ordered_remove(&s.uploads, 0) }
	id = mem_store.next_id(&s.seq)
	append(&s.uploads, m.Upload{id = id, user = user, size = size, at = at})
	return id, .None
}

@(private)
find :: proc(id: i64) -> ^m.Upload {
	for &u in s.uploads {
		if u.id == id { return &u }
	}
	return nil
}

upload :: proc(id: i64) -> (m.Upload, m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	if u := find(id); u != nil { return u^, .None }
	return {}, .Not_Found
}

advance :: proc(id: i64, received: int) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	u := find(id)
	if u == nil { return .Not_Found }
	u.received = received
	return .None
}

close :: proc(id: i64, state: m.Upload_State) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	u := find(id)
	if u == nil { return .Not_Found }
	u.state = state
	return .None
}

open_count :: proc(user: u64, since: i64) -> int {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	n := 0
	for u in s.uploads {
		if u.state == .Open && u.user == user && u.at >= since { n += 1 }
	}
	return n
}

stale :: proc(before: i64, out: ^[dynamic]i64) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for u in s.uploads {
		if u.state == .Open && u.at < before { append(out, u.id) }
	}
	return .None
}

add_blob :: proc(b: m.Blob) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for &old in s.blobs {
		if old.sha256 == b.sha256 {
			old.at = b.at // uploaded again, it's as new
			return .None
		}
	}
	if len(s.blobs) >= MAX_ROWS {
		delete(s.blobs[0].sha256)
		delete(s.blobs[0].mime)
		ordered_remove(&s.blobs, 0)
	}
	row := b
	row.sha256, row.mime = strings.clone(b.sha256), strings.clone(b.mime)
	append(&s.blobs, row)
	return .None
}

blobs :: proc(before: i64, out: ^[dynamic]string) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for b in s.blobs {
		if b.at < before { append(out, strings.clone(b.sha256, context.temp_allocator)) }
	}
	return .None
}

drop_blob :: proc(sha256: string, before: i64) -> (dropped: bool, err: m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for b, i in s.blobs {
		if b.sha256 == sha256 && b.at < before {
			delete(b.sha256)
			delete(b.mime)
			ordered_remove(&s.blobs, i)
			return true, .None
		}
	}
	return false, .None
}

bytes_held :: proc(user: u64, since: i64) -> (member, all: int) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for u in s.uploads {
		if u.user == user && u.at >= since { member += u.size }
	}
	for b in s.blobs { all += b.bytes }
	return
}

blob :: proc(sha256: string) -> (m.Blob, m.Error) {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	for b in s.blobs {
		if b.sha256 == sha256 {
			out := b
			out.sha256, out.mime = strings.clone(b.sha256, context.temp_allocator), strings.clone(b.mime, context.temp_allocator)
			return out, .None
		}
	}
	return {}, .Not_Found
}
