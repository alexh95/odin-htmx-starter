package signed

import "core:strings"
import "core:testing"

import "../fuzz"

@(test)
a_signed_body_opens_and_nothing_else_does :: proc(t: ^testing.T) {
	key := transmute([]byte)string("a key of thirty-two bytes, or so")
	text := sign("7.1793000000", key)
	body, ok := open(text, key)
	testing.expect(t, ok && body == "7.1793000000")
	_, ok = open(text, transmute([]byte)string("another key"))
	testing.expect(t, !ok)
	longer := strings.concatenate({text, "A"}, context.temp_allocator)
	other := strings.concatenate({"8", text[1:]}, context.temp_allocator)
	for bad in ([]string{"", ".", "7", "7.", ".abc", "1.=", "1.==", text[:len(text) - 1], longer, other}) {
		_, ok = open(bad, key)
		testing.expectf(t, !ok, "%q opened", bad)
	}
	// Any one character changed, the MAC no longer matches.
	buf := transmute([]byte)string(text)
	for i in 0 ..< len(buf) {
		was := buf[i]
		buf[i] = 'x' if was != 'x' else 'y'
		_, ok = open(string(buf), key)
		testing.expectf(t, !ok, "a change at %d opened", i)
		buf[i] = was
	}
	free_all(context.temp_allocator)
}

// What a cookie or a form holds is anyone's: any of it answers, never traps, and opens only
// when it is a body the key signed (M4-13).
@(test)
open_takes_any_text :: proc(t: ^testing.T) {
	ALPHABET :: "0123456789.ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_="
	key := transmute([]byte)string("the fuzz test's own key")
	d := fuzz.seed(0xC2B2AE3D27D4EB4F)
	buf: [96]byte
	for _ in 0 ..< fuzz.rounds(200_000) {
		s := string(fuzz.draw(&d, buf[:], ALPHABET))
		if body, ok := open(s, key); ok {
			testing.expectf(t, sign(body, key) == s, "%q opened without being signed", s)
		}
		free_all(context.temp_allocator)
	}
}
