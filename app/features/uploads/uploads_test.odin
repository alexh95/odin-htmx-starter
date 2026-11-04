package uploads

// ---- what an upload's bytes are: the sniff, the claimed size, the decode bomb (§17.6) ---------

import "core:hash"
import "core:testing"

import "../../platform/fuzz"

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
		// Only the progressive one: core:image doesn't read those.
		testing.expectf(t, why == "" || i == 6, "%d: %q", i, why)
		if why == "" { testing.expect(t, c.width > 0 && c.height > 0) }
	}
}
