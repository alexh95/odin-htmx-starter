package totp

import "core:testing"

import "../fuzz"

// A typed secret and a typed code are a member's text: any of it answers, never traps (M4-13).
@(test)
decode_and_verify_take_any_text :: proc(t: ^testing.T) {
	SECRET :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz234567 -=="
	CODE :: "0123456789 -"
	d := fuzz.seed(0xD1B54A32D192ED03)
	buf: [64]byte
	key: [SECRET_LEN]byte
	for _ in 0 ..< fuzz.rounds(100_000) {
		secret, ok := decode(string(fuzz.draw(&d, buf[:], SECRET)))
		if ok { key = secret }
		_, _ = verify(key[:], string(fuzz.draw(&d, buf[:12], CODE)), i64(fuzz.next(&d) >> 30))
		free_all(context.temp_allocator)
	}
	testing.expect(t, true)
}
