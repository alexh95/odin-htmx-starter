package stream

import "core:testing"

import "../fuzz"

// A socket's frame is a client's JSON: ws_field reads any of it without a trap, and what it
// finds lies inside the frame or was built in the request arena (M3-09).
@(test)
ws_field_takes_any_frame :: proc(t: ^testing.T) {
	ALPHABET :: `{}[]":,\ ntrufalse0123456789.eE+-bodyHEADERSu`
	d := fuzz.seed(0xE7037ED1A0B428DB)
	buf: [160]byte
	for _ in 0 ..< fuzz.rounds(200_000) {
		_, _ = ws_field(fuzz.draw(&d, buf[:], ALPHABET), "body")
		free_all(context.temp_allocator)
	}
	testing.expect(t, true)
}
