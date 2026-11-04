package uploads

// ---- what an upload's bytes are: the sniff, the claimed size, the decode bomb (§17.6) ---------

import "base:runtime"
import "core:fmt"
import "core:hash"
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
// 32×32: for the fuzz, where a 1×1 file stops short of most of a decoder.
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

@(test)
checks_a_real_image :: proc(t: ^testing.T) {
	for data in ([?][]byte{TINY_PNG, TINY_JPEG}) {
		c, why := check(data)
		testing.expectf(t, why == "" && c.width == 1 && c.height == 1 && valid_sha(string(c.sha256[:])), "%q %v", why, c)
	}
}

// A file whose header claims 60 000 × 60 000 is refused from the header: no pixel is allocated.
@(test)
refuses_a_bomb_before_decoding :: proc(t: ^testing.T) {
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

@(test)
addresses_are_hex :: proc(t: ^testing.T) {
	testing.expect(t, valid_sha("aa00000000000000000000000000000000000000000000000000000000000000"))
	testing.expect(t, !valid_sha("../../etc/passwd"))
	testing.expect(t, !valid_sha("AA00000000000000000000000000000000000000000000000000000000000000"))
}

// More symbols than the decoder's arrays hold, the sum wrapping a u8: refused before it.
@(test)
refuses_an_oversized_huffman_table :: proc(t: ^testing.T) {
	segment := make([]byte, 17 + 300, context.temp_allocator)
	for i in 1 ..< 17 { segment[i] = 20 }
	testing.expect(t, !huffman_fits(segment))
	for i in 1 ..< 17 { segment[i] = 2 }
	testing.expect(t, huffman_fits(segment[:17 + 32]))
}

// The CRC each chunk ends with made right again, so a flipped byte reaches the inflate and the
// filters instead of stopping at the checksum.
@(private = "file")
fix_png_crcs :: proc(data: []byte) {
	i := 8
	for i + 12 <= len(data) {
		n := int(data[i]) << 24 | int(data[i + 1]) << 16 | int(data[i + 2]) << 8 | int(data[i + 3])
		if n < 0 || i + 12 + n > len(data) { return }
		sum := hash.crc32(data[i + 4:i + 8 + n])
		for k in 0 ..< 4 { data[i + 8 + n + k] = byte(sum >> uint(24 - 8 * k)) }
		i += 12 + n
	}
}

// A deflate stream that never ends, in a small file: core:image's inflate would run until the
// machine had no memory left. Found by the fuzz below; the arena's cap is what ends it.
@(test)
stops_an_endless_stream :: proc(t: ^testing.T) {
	_, why := check(#load("testdata/endless.png"))
	testing.expect(t, why != "")
}

// The audit's files (M6-01, M6-03), height 6400 and width 6250, all nothing but headers. Each is refused
// at the frame, before `blocks` is made: no trap, no pages touched.
@(private = "file")
FRAME :: "\xFF\xD8\xFF\xC0\x00\x11\x08\x19\x00\x18\x6A\x03"
@(private = "file")
SCAN :: "\xFF\xDA\x00\x0C\x03\x01\x00\x02\x00\x03\x00\x00\x3F\x00\xFF\xD9"

@(test)
refuses_a_frame_the_decoder_cant_scan :: proc(t: ^testing.T) {
	Case :: struct { name, components: string }
	cases := [?]Case{
		{"Cb sampled finer than Y", "\x01\x11\x00\x02\x12\x00\x03\x11\x00"},
		{"no Y at all", "\x02\x11\x00\x02\x11\x00\x02\x11\x00"},
		{"Cb twice", "\x01\x11\x00\x02\x11\x00\x02\x11\x00"},
	}
	for c in cases {
		data := transmute([]byte)strings.concatenate({FRAME, c.components, SCAN}, context.temp_allocator)
		_, why := check(data)
		testing.expectf(t, why == "That image can't be read.", "%s: %q", c.name, why)
	}
}

// A JFXX segment naming a thumbnail larger than itself: the decoder goes by the segment's length,
// as the header read does, so what a COM hides stays hidden from both.
@(test)
walks_a_file_as_the_header_read_does :: proc(t: ^testing.T) {
	JFXX :: "\xFF\xE0\x00\x08JFXX\x00\x13\xFF\xD9"
	data := transmute([]byte)strings.concatenate({"\xFF\xD8", JFXX}, context.temp_allocator)
	_, why := check(data)
	testing.expect_value(t, why, "That image can't be read.")
}

// Flipped bytes of real files, cut short at any length: an answer, never a trap, and nothing past
// the pixel cap gets through.
@(test)
fuzz_the_decoders :: proc(t: ^testing.T) {
	d := fuzz.seed(0x1A7E)
	for _ in 0 ..< fuzz.rounds(1000) {
		seed := SEEDS[fuzz.next(&d) % len(SEEDS)]
		data := make([]byte, len(seed), context.temp_allocator)
		copy(data, seed)
		for _ in 0 ..= fuzz.next(&d) % 8 {
			r := fuzz.next(&d)
			data[r % u64(len(data))] = byte(r >> 32)
		}
		if sniff(data) == .Png { fix_png_crcs(data) }
		n := len(data) if fuzz.next(&d) & 3 != 0 else int(fuzz.next(&d) % u64(len(data))) + 1
		c, why := check(data[:n])
		if why == "" { testing.expectf(t, c.width * c.height <= MAX_PIXELS, "%v", c) }
		free_all(context.temp_allocator)
	}
}

// What phones and editors make, with what can't be read refused in the member's words.
@(test)
reads_each_seed :: proc(t: ^testing.T) {
	for seed, i in SEEDS {
		c, why := check(seed)
		if i == 6 { // core:image doesn't read those, and the member hears why
			testing.expectf(t, strings.contains(why, "progressive"), "%q", why)
			continue
		}
		testing.expectf(t, why == "", "%d: %q", i, why)
		testing.expect(t, c.width > 0 && c.height > 0)
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
	free_all(context.temp_allocator)
}
