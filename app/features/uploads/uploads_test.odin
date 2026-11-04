package uploads

// ---- what an upload's bytes are: the sniff, the header's claim, the walk to a JPEG's end (§17.6) ----

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "../../platform/fuzz"
import "../../platform/obs"
import m "models"
import uploads_store "store:uploads"

// 1×1, RGB, one white pixel.
@(private = "file")
TINY_PNG := #load("testdata/tiny.png")
@(private = "file")
TINY_JPEG := #load("testdata/tiny.jpg")
// 32×32, for the walk: a progressive JPEG and one with restart markers among them.
@(private = "file")
SEEDS := [?][]byte {
	TINY_PNG, TINY_JPEG, #load("testdata/gradient.png"), #load("testdata/palette.png"), #load("testdata/gradient.jpg"),
	#load("testdata/gray.jpg"), #load("testdata/progressive.jpg"), #load("testdata/restart.jpg"),
}

@(test)
sniffs_by_bytes_alone :: proc(t: ^testing.T) {
	testing.expect_value(t, sniff(TINY_PNG), Image_Kind.Png)
	testing.expect_value(t, sniff(TINY_JPEG), Image_Kind.Jpeg)
	refused := [?]string{"", "GIF89a", "<svg xmlns='http://www.w3.org/2000/svg'/>", "<!doctype html>", "\xff\xd8", "\x89PNG"}
	for s in refused { testing.expectf(t, sniff(transmute([]byte)s) == .None, "%q", s) }
}

@(test)
reads_what_a_header_claims :: proc(t: ^testing.T) {
	w, h, ok := claimed_size(TINY_PNG, .Png)
	testing.expect(t, ok && w == 1 && h == 1)
	w, h, ok = claimed_size(TINY_JPEG, .Jpeg)
	testing.expect(t, ok && w == 1 && h == 1)
}

// What phones and editors make, a progressive JPEG among them: the header says, and the bytes stay.
@(test)
reads_each_seed :: proc(t: ^testing.T) {
	for seed, i in SEEDS {
		c, why := check(seed)
		testing.expectf(t, why == "" && c.width > 0 && c.height > 0 && valid_sha(string(c.sha256[:])), "%d: %q %v", i, why, c)
	}
}

// A file whose header claims 60 000 × 60 000 goes at the header.
@(test)
refuses_a_bomb_by_its_header :: proc(t: ^testing.T) {
	bomb := make([]byte, len(TINY_PNG), context.temp_allocator)
	copy(bomb, TINY_PNG)
	bomb[16], bomb[17], bomb[18], bomb[19] = 0, 0, 0xEA, 0x60
	bomb[20], bomb[21], bomb[22], bomb[23] = 0, 0, 0xEA, 0x60
	_, why := check(bomb)
	testing.expect_value(t, why, "That image is too large: at most 40 megapixels.")
	// Past int on a 32-bit multiply, and any multiply: each side is judged first.
	bomb[16], bomb[20] = 0xFF, 0xFF
	_, why = check(bomb)
	testing.expect_value(t, why, "That image is too large: at most 40 megapixels.")
}

// A frame and then another, larger: this would judge the first and a browser might draw the second.
@(test)
refuses_a_second_frame :: proc(t: ^testing.T) {
	SOF :: "\xFF\xC0\x00\x11\x08\x00\x10\x00\x10\x03\x01\x11\x00\x02\x11\x00\x03\x11\x00"
	HUGE :: "\xFF\xC2\x00\x11\x08\xFF\xFF\xFF\xFF\x03\x01\x11\x00\x02\x11\x00\x03\x11\x00"
	one := strings.concatenate({"\xFF\xD8", SOF, "\xFF\xD9"}, context.temp_allocator)
	_, why := check(transmute([]byte)one)
	testing.expect_value(t, why, "")
	two := strings.concatenate({"\xFF\xD8", SOF, HUGE, "\xFF\xD9"}, context.temp_allocator)
	_, why = check(transmute([]byte)two)
	testing.expect_value(t, why, "That image can't be read.")
}

// A segment whose length runs off the file, and a file with no frame at all.
@(test)
refuses_a_walk_that_ends_badly :: proc(t: ^testing.T) {
	for bad in ([?]string{"\xFF\xD8\xFF\xE0\xFF\xFF\x00", "\xFF\xD8\xFF\xD9", "\xFF\xD8\xFF\x00\x00\x00"}) {
		_, why := check(transmute([]byte)bad)
		testing.expectf(t, why == "That image can't be read.", "%q: %q", bad, why)
	}
}

// `FF 00` is stuffing, not a segment: a length read there would skip what a browser's decoder sees, here
// a huge frame hidden behind a decoy of 1×1.
@(test)
refuses_stuffing_where_a_marker_belongs :: proc(t: ^testing.T) {
	HIDDEN :: "\xFF\xD8\xFF\x00\x00\x0F\xFF\xC0\x00\x0B\x08\xFF\xDC\xFF\xDC\x01\x01\x11\x00"
	DECOY :: "\xFF\xC0\x00\x0B\x08\x00\x01\x00\x01\x01\x01\x11\x00\xFF\xD9"
	_, why := check(transmute([]byte)strings.concatenate({HIDDEN, DECOY}, context.temp_allocator))
	testing.expect_value(t, why, "That image can't be read.")
}

@(test)
refuses_a_reserved_marker :: proc(t: ^testing.T) {
	for bad in ([?]string{"\xFF\xD8\xFF\x02\x00\x02", "\xFF\xD8\xFF\xC8\x00\x02", "\xFF\xD8\xFF\xF0\x00\x02"}) {
		_, why := check(transmute([]byte)bad)
		testing.expectf(t, why == "That image can't be read.", "%q: %q", bad, why)
	}
}

// A frame of width 0 is still a frame: a second one doesn't get to take its place.
@(test)
counts_a_frame_of_no_width :: proc(t: ^testing.T) {
	NIL :: "\xFF\xC0\x00\x0B\x08\x00\x01\x00\x00\x01\x01\x11\x00"
	REAL :: "\xFF\xC0\x00\x0B\x08\x00\x01\x00\x01\x01\x01\x11\x00"
	_, why := check(transmute([]byte)strings.concatenate({"\xFF\xD8", NIL, REAL, "\xFF\xD9"}, context.temp_allocator))
	testing.expect_value(t, why, "That image can't be read.")
}

// Corrupt past its header: stored, and a broken image in a browser. Nothing here reads that far.
@(test)
keeps_what_its_header_vouches_for :: proc(t: ^testing.T) {
	_, why := check(TINY_PNG[:40])
	testing.expect_value(t, why, "")
}

@(test)
addresses_are_hex :: proc(t: ^testing.T) {
	testing.expect(t, valid_sha("aa00000000000000000000000000000000000000000000000000000000000000"))
	testing.expect(t, !valid_sha("../../etc/passwd"))
	testing.expect(t, !valid_sha("AA00000000000000000000000000000000000000000000000000000000000000"))
}

// Flipped bytes of real files, cut short at any length: the header walk answers, never traps, and
// nothing past the pixel cap gets through.
@(test)
fuzz_the_header_walk :: proc(t: ^testing.T) {
	d := fuzz.seed(0x1A7E)
	for _ in 0 ..< fuzz.rounds(20000) {
		seed := SEEDS[fuzz.next(&d) % len(SEEDS)]
		data := make([]byte, len(seed), context.temp_allocator)
		copy(data, seed)
		for _ in 0 ..= fuzz.next(&d) % 8 {
			r := fuzz.next(&d)
			data[r % u64(len(data))] = byte(r >> 32)
		}
		n := len(data) if fuzz.next(&d) & 3 != 0 else int(fuzz.next(&d) % u64(len(data))) + 1
		c, why := check(data[:n])
		if why == "" { testing.expectf(t, c.width * c.height <= MAX_PIXELS, "%v", c) }
		free_all(context.temp_allocator)
	}
}

// ---- a blob's lifetime, on the build's store, in a directory of its own -------------------------

@(private = "file")
SHA_A :: "a000000000000000000000000000000000000000000000000000000000000000"
@(private = "file")
SHA_B :: "b000000000000000000000000000000000000000000000000000000000000000"

@(test)
sweep_and_mirror :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	obs.init(.Fatal)
	dir := fmt.tprintf("%s/uploads-test-%d", os.temp_directory(context.temp_allocator) or_else ".", os.get_pid())
	defer os.remove_all(dir)
	st.parts, st.blobs = fmt.tprintf("%s/parts", dir), fmt.tprintf("%s/blobs", dir)
	testing.expect(t, directories())
	st.n_holders = 0
	holds(proc(sha: string) -> bool { return sha == SHA_A })

	old := now() - i64(UNHELD / time.Second) - 60
	for sha in ([?]string{SHA_A, SHA_B}) {
		_ = os.write_entire_file(blob_path(sha), transmute([]byte)sha)
		testing.expect_value(t, uploads_store.add_blob(m.Blob{sha256 = sha, mime = "image/png", at = old}), m.Error.None)
	}

	dest := fmt.tprintf("%s/backup/blobs", dir)
	copied, removed, ok := mirror(dest)
	testing.expect(t, ok && copied == 2 && removed == 0)
	again, _, _ := mirror(dest)
	testing.expect_value(t, again, 0) // by name: nothing new

	// A live disk that lost a file doesn't take its copy: the row is still there.
	_ = os.remove(blob_path(SHA_A))
	_, removed, ok = mirror(dest)
	testing.expect(t, ok && removed == 0 && os.exists(fmt.tprintf("%s/%s", dest, SHA_A)))
	_ = os.write_entire_file(blob_path(SHA_A), string(SHA_A))

	// A day old: the unheld one goes, the held one stays, and the copy follows.
	_, unheld := sweep()
	testing.expect_value(t, unheld, 1)
	testing.expect(t, os.exists(blob_path(SHA_A)) && !os.exists(blob_path(SHA_B)))
	_, gone := blob(SHA_B)
	testing.expect_value(t, gone, m.Error.Not_Found)
	_, removed, _ = mirror(dest)
	testing.expect_value(t, removed, 1)
	testing.expect(t, os.exists(fmt.tprintf("%s/%s", dest, SHA_A)) && !os.exists(fmt.tprintf("%s/%s", dest, SHA_B)))

	// A table that's lost its rows doesn't take the copies: past a handful, most going at once fails.
	many := fmt.tprintf("%s/backup2/blobs", dir)
	testing.expect(t, os.make_directory_all(many) == nil)
	for i in 0 ..< 12 { _ = os.write_entire_file(fmt.tprintf("%s/%064d", many, i), "x") }
	_, removed, ok = mirror(many)
	testing.expect(t, !ok && removed == 0)

	// A release with no grace, and a holder that can't tell keeps it.
	release(SHA_A)
	testing.expect(t, os.exists(blob_path(SHA_A)))
	st.n_holders = 0
	release(SHA_A)
	testing.expect(t, !os.exists(blob_path(SHA_A)))

	// No rows at all: however few the copies, none goes, and the run fails.
	_, removed, ok = mirror(dest)
	testing.expect(t, !ok && removed == 0 && os.exists(fmt.tprintf("%s/%s", dest, SHA_A)))
	free_all(context.temp_allocator)
}
