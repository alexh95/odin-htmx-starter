package uploads

// ---- uploads: the domain (PLAN §14.2, §17.6, D35, X13) -------------------------------------
//
// Chunks land in a part file; finishing one checks it and moves it to a blob named by its
// sha256, so the same image twice is one file. What it may be is decided by its bytes alone:
// magic bytes first, then the size its header claims against MAX_PIXELS, before anything
// walks a JPEG to its end so that a decoy frame can't pass it. SVG and HTML never get in. Nothing
// decodes an image here: the server keeps the bytes and serves them, so pixels would buy it nothing
// but a decoder's bugs (§17.6). The disk work runs on web's pool.
//
// A blob lives while something holds it (§17.6). Whoever uses blobs registers a Holder, asked
// each time, so nothing counts and nothing drifts: the sweep takes what's a day old and unheld,
// which covers retention and images never posted.

import "base:runtime"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import "../../platform/env"
import "../../platform/obs"
import m "models"
import uploads_store "store:uploads"

IMPL :: uploads_store.IMPL

MAX_IMAGE :: 10 << 20 // bytes (§17.6)
MAX_CHUNK :: 4 << 20
MAX_PIXELS :: 40_000_000

// §17.5. An upload nobody finished stops counting after ABANDONED, and the sweep takes it.
AT_ONCE :: 2
ABANDONED :: time.Hour
UNHELD :: 24 * time.Hour // a blob with no holder, past this, goes

// Whether something still needs this blob. True when it can't tell: a file goes only on a no.
Holder :: proc(sha256: string) -> bool

ENV := [?]env.Row {
	{name = "UPLOADS_DIR", kind = .Path, def = "uploads", doc = "where parts and blobs live; a container's is on its volume"},
	{name = "UPLOADS_PER_HOUR", kind = .Int, def = "20", doc = "uploads a member may start in an hour (§17.5)"},
	{name = "UPLOADS_BYTES_PER_DAY", kind = .Size, def = "256MiB", doc = "what a member may upload in a day"},
	{name = "UPLOADS_MAX_BYTES", kind = .Size, def = "16GiB", doc = "what all the blobs together may hold"},
}

@(private)
st: struct {
	parts, blobs: string,
	mirror:       string, // where the nightly copy goes; "": no backups here
	holders:      [8]Holder,
	n_holders:    int,
}

// At boot: the env rows. The directories wait for the first upload: `bin --limits` makes none.
init :: proc() {
	env.record("UPLOADS_", ENV[:])
	uploads_store.init()
	dir := strings.trim_right(env.str("UPLOADS_DIR"), "/\\")
	st.parts = strings.concatenate({dir, "/parts"})
	st.blobs = strings.concatenate({dir, "/blobs"})
}

// At boot, by whatever keeps blobs in its rows.
holds :: proc(h: Holder) {
	st.holders[st.n_holders] = h
	st.n_holders += 1
}

@(private)
held :: proc(sha: string) -> bool {
	for h in st.holders[:st.n_holders] {
		if h(sha) { return true }
	}
	return false
}

per_hour :: proc() -> int { return env.int_("UPLOADS_PER_HOUR") }

@(private)
now :: proc() -> i64 { return time.time_to_unix(time.now()) }

@(private)
oldest_open :: proc() -> i64 { return now() - i64(ABANDONED / time.Second) }

@(private)
part_path :: proc(id: i64) -> string { return fmt.tprintf("%s/%d", st.parts, id) }

@(private)
blob_path :: proc(sha: string) -> string { return fmt.tprintf("%s/%s", st.blobs, sha) }

// ---- the rows -----------------------------------------------------------------------------

// Whether the directories are there, made if not. Without them uploads refuse, and the rest serves.
@(private)
directories :: proc() -> bool {
	if os.is_dir(st.parts) && os.is_dir(st.blobs) { return true }
	_ = os.make_directory_all(st.parts)
	_ = os.make_directory_all(st.blobs)
	ok := os.is_dir(st.parts) && os.is_dir(st.blobs)
	if !ok {
		if l, on := obs.begin(.Error, "uploads", "no_directory"); on {
			obs.str(&l, "dir", st.parts)
			obs.end(&l)
		}
	}
	return ok
}

// A new upload of `size` bytes, or why not: a size the member can fix, or too many at once.
begin :: proc(user: u64, size: int) -> (id: i64, problem: string, err: m.Error) {
	if size <= 0 || size > MAX_IMAGE { return 0, "An image is at most 10 MiB.", .None }
	if uploads_store.open_count(user, oldest_open()) >= AT_ONCE { return 0, "Two uploads at a time: wait for one to finish.", .None }
	member, all := uploads_store.bytes_held(user, now() - 86_400)
	if member + size > env.size("UPLOADS_BYTES_PER_DAY") { return 0, "That's as much as you can upload today.", .None }
	if all + size > env.size("UPLOADS_MAX_BYTES") { return 0, "The image store is full: tell an admin.", .None }
	if !directories() { return 0, "", .Failed }
	id, err = uploads_store.create(user, size, now())
	return id, "", err
}

upload :: proc(id: i64) -> (m.Upload, m.Error) { return uploads_store.upload(id) }
blob :: proc(sha: string) -> (m.Blob, m.Error) { return uploads_store.blob(sha) }

// Gives up on an upload: the row and its part file.
drop :: proc(id: i64) {
	_ = uploads_store.close(id, .Gone)
	_ = os.remove(part_path(id))
}

// A blob's row and file, whoever may hold it: a moderator's removal, once its holders let it go.
// Only one made before `before`: the sweep's list is old by the time it acts, and the same image
// uploaded since is new.
erase :: proc(sha: string, before: i64 = max(i64)) -> m.Error {
	if !valid_sha(sha) { return .Not_Found }
	dropped, err := uploads_store.drop_blob(sha, before)
	if err != .None { return err }
	if dropped { _ = os.remove(blob_path(sha)) }
	return .None
}

// A holder let go of it: gone now if nothing else holds it (a photo posted by mistake).
release :: proc(sha: string) {
	if valid_sha(sha) && !held(sha) { _ = erase(sha) }
}

// The hourly job: uploads nobody finished, and blobs a day old that nothing holds.
sweep :: proc() -> (uploads, blobs: int) {
	ids := make([dynamic]i64, context.temp_allocator)
	if uploads_store.stale(oldest_open(), &ids) == .None {
		for id in ids { drop(id) }
		uploads = len(ids)
	}
	shas := make([dynamic]string, context.temp_allocator)
	before := now() - i64(UNHELD / time.Second)
	if uploads_store.blobs(before, &shas) == .None {
		for sha in shas {
			if !held(sha) && erase(sha, before) == .None { blobs += 1 }
		}
	}
	return
}

// ---- the bytes, on the pool -----------------------------------------------------------------

// `data` at `off` of the part file, and the row moved on. At an offset, not appended: a chunk sent
// twice (its answer was lost) lands where it landed before.
write_chunk :: proc(id: i64, off: int, data: []byte) -> m.Error {
	// Created by the first chunk alone: a late one has no file to bring back.
	f, oerr := os.open(part_path(id), {.Write, .Create} if off == 0 else {.Write})
	if oerr != nil { return .Failed }
	defer os.close(f)
	n, werr := os.write_at(f, data, i64(off))
	if werr != nil || n != len(data) { return .Failed }
	return uploads_store.advance(id, off + n)
}

// A complete upload, checked and made a blob; refused, its part file goes. `problem` is the
// member's to read, `err` the store's or the disk's. The blob is written from the bytes that were
// checked, not the part file, which a chunk still queued could change under the hash.
conclude :: proc(u: m.Upload) -> (b: m.Blob, problem: string, err: m.Error) {
	path := part_path(u.id)
	data, rerr := os.read_entire_file(path, runtime.heap_allocator())
	if rerr != nil { return {}, "", .Failed }
	defer delete(data, runtime.heap_allocator())
	c, why := check(data)
	if why != "" {
		drop(u.id)
		return {}, why, .None
	}
	sha := string(c.sha256[:])
	to := blob_path(sha)
	if !os.exists(to) {
		part := fmt.tprintf("%s.%d", to, u.id)
		if os.write_entire_file(part, data) != nil || os.rename(part, to) != nil {
			_ = os.remove(part)
			return {}, "", .Failed
		}
	}
	_ = os.remove(path)
	b = {sha256 = strings.clone(sha, context.temp_allocator), mime = MIME[c.kind], bytes = len(data), width = c.width, height = c.height, user = u.user, at = now()}
	if err = uploads_store.add_blob(b); err != .None { return }
	err = uploads_store.close(u.id, .Done)
	return
}

// A blob's bytes, on the heap: the caller frees them with `free_bytes`.
read_blob :: proc(sha: string) -> ([]byte, bool) {
	data, err := os.read_entire_file(blob_path(sha), runtime.heap_allocator())
	return data, err == nil
}

free_bytes :: proc(data: []byte) { delete(data, runtime.heap_allocator()) }

// ---- the backup's copy (§11.6, DATA.md) --------------------------------------------------------

// From main, where there are backups to sit beside: BACKUP_DIR, as SQLite's package resolved it.
// A build that never calls it has no copy.
backs_up_to :: proc(dir: string) {
	if dir != "" { st.mirror = strings.concatenate({strings.trim_right(dir, "/\\"), "/blobs"}) }
}

mirror_dir :: proc() -> string { return st.mirror }

// `dest` as the blobs are: what's new copied by name (a part file, then a rename), and each copy
// whose row has gone deleted, so a moderator's removal reaches the backup. By row, not by file: a
// live disk that lost its files mustn't take the copies with it. ok false: something failed, and
// the rest was still tried.
mirror :: proc(dest: string) -> (copied, removed: int, ok: bool) {
	ok = true
	if !os.is_dir(st.blobs) { return } // nothing uploaded yet
	if os.make_directory_all(dest) != nil && !os.is_dir(dest) { return 0, 0, false }
	live := make([dynamic]string, context.temp_allocator)
	if uploads_store.blobs(max(i64), &live) != .None { return 0, 0, false }
	alive := make(map[string]bool, context.temp_allocator)
	for sha in live {
		alive[sha] = true
		to := fmt.tprintf("%s/%s", dest, sha)
		if os.exists(to) || !os.exists(blob_path(sha)) { continue }
		part := fmt.tprintf("%s.part", to)
		data, rerr := os.read_entire_file(blob_path(sha), runtime.heap_allocator())
		if rerr != nil {
			ok = false
			continue
		}
		werr := os.write_entire_file(part, data)
		delete(data, runtime.heap_allocator())
		if werr != nil || os.rename(part, to) != nil {
			_ = os.remove(part)
			ok = false
			continue
		}
		copied += 1
	}
	there, lerr := os.read_all_directory_by_path(dest, context.temp_allocator)
	if lerr != nil { return copied, 0, false }
	going := make([dynamic]string, context.temp_allocator)
	for f in there {
		if !alive[strings.trim_suffix(f.name, ".part")] || strings.has_suffix(f.name, ".part") { append(&going, f.fullpath) }
	}
	// No rows at all, or most of the copies going at once, isn't a day's removals: it's the wrong
	// database, a volume not mounted. The copies stay, and the failed run tells an admin. The floor
	// lets a store of a few images lose most of them in a day.
	if len(going) > 0 && len(live) == 0 { return copied, 0, false }
	if len(going) > 8 && len(going) * 2 > len(there) { return copied, 0, false }
	for path in going {
		if os.remove(path) == nil { removed += 1 } else { ok = false }
	}
	return
}

// ---- what the bytes are ---------------------------------------------------------------------

Image_Kind :: enum u8 {
	None,
	Png,
	Jpeg,
}

MIME := [Image_Kind]string {
	.None = "",
	.Png  = "image/png",
	.Jpeg = "image/jpeg",
}

// What a blob's row says it is.
kind_of :: proc(mime: string) -> Image_Kind {
	for name, k in MIME {
		if name == mime { return k }
	}
	return .None
}

// Magic bytes alone.
sniff :: proc(data: []byte) -> Image_Kind {
	PNG_MAGIC :: "\x89PNG\r\n\x1a\n"
	if len(data) >= len(PNG_MAGIC) && string(data[:len(PNG_MAGIC)]) == PNG_MAGIC { return .Png }
	if len(data) >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF { return .Jpeg }
	return .None
}

// The width and height a file's header claims. ok false: it names none, or isn't plainly a JPEG. A JPEG
// is walked to its end by each segment's length, as a browser's decoder goes, and anything a decoder
// might read another way is refused rather than guessed at: a second frame, or stuffing or a
// reserved marker where a marker belongs. Otherwise a file could show this check a small image
// and a browser a huge one, past the pixel cap (decoy.spec holds each engine to it).
claimed_size :: proc(data: []byte, kind: Image_Kind) -> (width, height: int, ok: bool) {
	be16 :: proc(b: []byte) -> int { return int(b[0]) << 8 | int(b[1]) }
	be32 :: proc(b: []byte) -> int { return int(b[0]) << 24 | int(b[1]) << 16 | int(b[2]) << 8 | int(b[3]) }
	switch kind {
	case .None:
	case .Png:
		// The signature, then IHDR: its length, its type, width, height.
		if len(data) < 24 || string(data[12:16]) != "IHDR" { return }
		return be32(data[16:20]), be32(data[20:24]), true
	case .Jpeg:
		framed := false
		i := 2
		for i + 4 <= len(data) {
			if data[i] != 0xFF { return 0, 0, false }
			marker := data[i + 1]
			switch marker {
			case 0xFF: // fill
				i += 1
				continue
			case 0x01, 0xD0 ..= 0xD8: // no length
				i += 2
				continue
			case 0xD9:
				return width, height, framed
			case 0xC0 ..= 0xC7, 0xC9 ..= 0xCF, 0xDA ..= 0xDD, 0xE0 ..= 0xEF, 0xFE: // what has a length
			case: // stuffing, or reserved: a decoder may scan on from here, past what a length would skip
				return 0, 0, false
			}
			n := be16(data[i + 2:])
			if n < 2 || i + 2 + n > len(data) { return 0, 0, false }
			segment := data[i + 4:i + 2 + n]
			i += 2 + n
			switch marker {
			case 0xC0 ..= 0xC3, 0xC5 ..= 0xC7, 0xC9 ..= 0xCB, 0xCD ..= 0xCF: // SOFn
				if framed || len(segment) < 5 { return 0, 0, false }
				width, height, framed = be16(segment[3:]), be16(segment[1:]), true
			case 0xDA: // a scan: its data runs to the next marker that isn't stuffing or a restart
				for i + 1 < len(data) && (data[i] != 0xFF || data[i + 1] == 0 || data[i + 1] & 0xF8 == 0xD0) { i += 1 }
			}
		}
		return width, height, framed
	}
	return
}

Checked :: struct {
	kind:          Image_Kind,
	width, height: int,
	sha256:        [64]byte,
}

// What an upload's bytes are, or why they're refused, in the member's words. A file that passes and
// is corrupt past its header is stored, and shows as a broken image: what keeps a blob safe is the
// type from its row, `nosniff`, the CSP and the pixel cap, which a decode here wouldn't add to.
check :: proc(data: []byte) -> (c: Checked, problem: string) {
	if len(data) == 0 || len(data) > MAX_IMAGE { return c, "An image is at most 10 MiB." }
	c.kind = sniff(data)
	if c.kind == .None { return c, "Only PNG and JPEG images." }
	ok: bool
	c.width, c.height, ok = claimed_size(data, c.kind)
	if !ok || c.width <= 0 || c.height <= 0 { return c, "That image can't be read." }
	if c.width > MAX_PIXELS || c.height > MAX_PIXELS || c.width * c.height > MAX_PIXELS {
		return c, "That image is too large: at most 40 megapixels."
	}
	sum: [32]byte
	hash.hash_bytes_to_buffer(.SHA256, data, sum[:])
	copy(c.sha256[:], hex.encode(sum[:], context.temp_allocator))
	return c, ""
}

// A blob's address, checked: 64 lower-case hex digits, so no path comes through it.
valid_sha :: proc(s: string) -> bool {
	return len(s) == 64 && strings.trim_left(s, "0123456789abcdef") == ""
}
