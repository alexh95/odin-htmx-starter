package uploads

// ---- uploads: the domain (PLAN §14.2, §17.6, D35, X13) -------------------------------------
//
// Chunks land in a part file; finishing one checks it and moves it to a blob named by its
// sha256, so the same image twice is one file. What it may be is decided by its bytes alone:
// magic bytes first, then the size its header claims against MAX_PIXELS, before anything
// allocates for it (a decode bomb is small on the wire), then a full decode. SVG and HTML never
// get in: only what core:image decodes here, PNG and JPEG. The disk work runs on web's pool.
//
// A blob lives while something holds it (§17.6). Whoever uses blobs registers a Holder, asked
// each time, so nothing counts and nothing drifts: the sweep takes what's a day old and unheld,
// which covers retention and images never posted.

import "base:runtime"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:image"
import "core:image/jpeg"
import "core:image/png"
import "core:mem/virtual"
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
DECODE_LIMIT :: 256 << 20 // what one decode may hold; past it an image is refused, whatever its pixels

// §17.5. An upload nobody finished stops counting after ABANDONED, and the sweep takes it.
AT_ONCE :: 2
ABANDONED :: time.Hour
UNHELD :: 24 * time.Hour // a blob with no holder, past this, goes

// Whether something still needs this blob. True when it can't tell: a file goes only on a no.
Holder :: proc(sha256: string) -> bool

ENV := [?]env.Row {
	{name = "UPLOADS_DIR", kind = .Path, def = "uploads", doc = "where parts and blobs live; a container's is on its volume"},
	{name = "UPLOADS_PER_HOUR", kind = .Int, def = "20", doc = "uploads a member may start in an hour (§17.5)"},
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
erase :: proc(sha: string) -> m.Error {
	if !valid_sha(sha) { return .Not_Found }
	if err := uploads_store.drop_blob(sha); err != .None { return err }
	_ = os.remove(blob_path(sha))
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
	if uploads_store.blobs(now() - i64(UNHELD / time.Second), &shas) == .None {
		for sha in shas {
			if !held(sha) && erase(sha) == .None { blobs += 1 }
		}
	}
	return
}

// ---- the bytes, on the pool -----------------------------------------------------------------

// `data` at `off` of the part file, and the row moved on. At an offset, not appended: a chunk sent
// twice (its answer was lost) lands where it landed before.
write_chunk :: proc(id: i64, off: int, data: []byte) -> m.Error {
	f, oerr := os.open(part_path(id), {.Write, .Create})
	if oerr != nil { return .Failed }
	defer os.close(f)
	n, werr := os.write_at(f, data, i64(off))
	if werr != nil || n != len(data) { return .Failed }
	return uploads_store.advance(id, off + n)
}

// A complete upload, checked and made a blob; refused, its part file goes. `problem` is the
// member's to read, `err` the store's or the disk's.
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
	if os.exists(blob_path(sha)) {
		_ = os.remove(path)
	} else if os.rename(path, blob_path(sha)) != nil {
		return {}, "", .Failed
	}
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
	for f in there {
		if !alive[strings.trim_suffix(f.name, ".part")] || strings.has_suffix(f.name, ".part") {
			if os.remove(f.fullpath) == nil { removed += 1 } else { ok = false }
		}
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

// Magic bytes alone.
sniff :: proc(data: []byte) -> Image_Kind {
	PNG_MAGIC :: "\x89PNG\r\n\x1a\n"
	if len(data) >= len(PNG_MAGIC) && string(data[:len(PNG_MAGIC)]) == PNG_MAGIC { return .Png }
	if len(data) >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF { return .Jpeg }
	return .None
}

// The width and height a file's header claims, read before anything is decoded. ok false: it
// names none, or isn't one the decoder may be given. A JPEG is walked to its end for that: its
// frame header can't be taken from the first SOF alone (a second one would size the decode), and
// core:image's JPEG reader sums a Huffman table's counts in a u8, so a table past 256 symbols
// wraps and indexes out of bounds: `huffman_fits` keeps those from it.
claimed_size :: proc(data: []byte, kind: Image_Kind) -> (width, height: int, ok: bool) {
	width, height, _, ok = read_header(data, kind)
	return
}

@(private)
read_header :: proc(data: []byte, kind: Image_Kind) -> (width, height: int, progressive, ok: bool) {
	be16 :: proc(b: []byte) -> int { return int(b[0]) << 8 | int(b[1]) }
	be32 :: proc(b: []byte) -> int { return int(b[0]) << 24 | int(b[1]) << 16 | int(b[2]) << 8 | int(b[3]) }
	switch kind {
	case .None:
	case .Png:
		// The signature, then IHDR: its length, its type, width, height.
		if len(data) < 24 || string(data[12:16]) != "IHDR" { return }
		return be32(data[16:20]), be32(data[20:24]), false, true
	case .Jpeg:
		i := 2
		for i + 4 <= len(data) {
			if data[i] != 0xFF { return 0, 0, false, false }
			marker := data[i + 1]
			switch marker {
			case 0xFF: // fill
				i += 1
				continue
			case 0x01, 0xD0 ..= 0xD8: // no length
				i += 2
				continue
			case 0xD9:
				return width, height, progressive, width > 0
			}
			n := be16(data[i + 2:])
			if n < 2 || i + 2 + n > len(data) { return 0, 0, false, false }
			segment := data[i + 4:i + 2 + n]
			i += 2 + n
			switch marker {
			case 0xC4:
				if !huffman_fits(segment) { return 0, 0, false, false }
			case 0xC0 ..= 0xC3, 0xC5 ..= 0xC7, 0xC9 ..= 0xCB, 0xCD ..= 0xCF: // SOFn
				if width != 0 || len(segment) < 5 { return 0, 0, false, false }
				width, height = be16(segment[3:]), be16(segment[1:])
				progressive = marker == 0xC2
			case 0xDA: // the scan: its data runs to the next marker that isn't stuffing or a restart
				for i + 1 < len(data) && (data[i] != 0xFF || data[i + 1] == 0 || data[i + 1] & 0xF8 == 0xD0) { i += 1 }
			}
		}
		return width, height, progressive, width > 0
	}
	return
}

// A DHT segment's tables, each within the 176 symbols the decoder's arrays hold, at every step.
@(private)
huffman_fits :: proc(segment: []byte) -> bool {
	HUFFMAN_MAX_SYMBOLS :: 176
	rest := segment
	for len(rest) > 0 {
		if len(rest) < 17 { return false }
		symbols := 0
		for count in rest[1:17] {
			symbols += int(count)
			if symbols > HUFFMAN_MAX_SYMBOLS { return false }
		}
		if len(rest) < 17 + symbols { return false }
		rest = rest[17 + symbols:]
	}
	return true
}

Checked :: struct {
	kind:          Image_Kind,
	width, height: int,
	sha256:        [64]byte,
}

// What an upload's bytes are, or why they're refused, in the member's words. Everything the
// decoders allocate goes in an arena of its own; nothing a file claims sizes an allocation until
// MAX_PIXELS has judged it.
check :: proc(data: []byte) -> (c: Checked, problem: string) {
	UNREADABLE :: "That image can't be read."
	TOO_LARGE :: "That image is too large: at most 40 megapixels."
	PROGRESSIVE :: "That's a progressive JPEG, which can't be read here. Save it as a regular JPEG or a PNG." // as images saved from the web often are
	if len(data) == 0 || len(data) > MAX_IMAGE { return c, "An image is at most 10 MiB." }
	c.kind = sniff(data)
	if c.kind == .None { return c, "Only PNG and JPEG images." }
	w, h, progressive, ok := read_header(data, c.kind)
	if !ok || w <= 0 || h <= 0 { return c, UNREADABLE }
	if progressive { return c, PROGRESSIVE }
	if w > MAX_PIXELS || h > MAX_PIXELS || w * h > MAX_PIXELS { return c, TOO_LARGE }

	// A hard cap: core:image's inflate doesn't stop at the size a PNG declares, and a 282-byte
	// stream that never ends grows its output until the allocator says no. It takes that no as
	// an error, so the arena is what ends it. Room for the raw rows and the pixels at 16 bits
	// and four channels, never more than a small container's share.
	arena: virtual.Arena
	if virtual.arena_init_static(&arena, uint(min(w * h * 8 * 3 + 16 << 20, DECODE_LIMIT))) != nil { return c, UNREADABLE }
	defer virtual.arena_destroy(&arena)
	a := virtual.arena_allocator(&arena)
	context.allocator = a
	img: ^image.Image
	err: image.Error
	switch c.kind {
	case .None:
	case .Png:
		img, err = png.load_from_bytes(data, {}, a)
	case .Jpeg:
		img, err = jpeg.load_from_bytes(data, {}, a)
	}
	if err != nil || img == nil { return c, UNREADABLE }
	c.width, c.height = img.width, img.height
	if c.width * c.height > MAX_PIXELS { return c, TOO_LARGE }

	sum: [32]byte
	hash.hash_bytes_to_buffer(.SHA256, data, sum[:])
	copy(c.sha256[:], hex.encode(sum[:], a))
	return c, ""
}

// A blob's address, checked: 64 lower-case hex digits, so no path comes through it.
valid_sha :: proc(s: string) -> bool {
	return len(s) == 64 && strings.trim_left(s, "0123456789abcdef") == ""
}
