package escape

import "core:testing"

import "../fuzz"

// Whatever a cookie, a form or a header holds, b64_decode answers without a trap (M4-02), and
// what it accepts decodes to no more than the text could hold.
@(test)
b64_decode_takes_any_text :: proc(t: ^testing.T) {
	ALPHABET :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/-_=="
	d := fuzz.seed(0x9E3779B97F4A7C15)
	buf: [96]byte
	for i in 0 ..< fuzz.rounds(200_000) {
		s := string(fuzz.draw(&d, buf[:], ALPHABET))
		out, ok := b64_decode(s, i & 1 == 0)
		if ok && len(out) > len(s) * 3 / 4 + 1 {
			testing.expectf(t, false, "%q decoded to %d bytes", s, len(out))
			break
		}
		free_all(context.temp_allocator)
	}
}
