package password

import "core:testing"

import "../fuzz"

// A stored hash comes back from the database or ACCOUNTS_ADMIN_HASH: decode refuses what it
// didn't make and never traps, whether the text is random or one byte off a real one (M4-13).
@(test)
decode_takes_any_text :: proc(t: ^testing.T) {
	PHC :: "$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0c2FsdA$dGFndGFndGFndGFndGFndGFndGFndGFndGFndGE"
	ALPHABET :: "$argon2idv=19m,tp0123456789ABCDEFabcdef+/=-_"
	alphabet := ALPHABET
	d := fuzz.seed(0xA0761D6478BD642F)
	buf: [128]byte
	for _ in 0 ..< fuzz.rounds(100_000) {
		_, _, _, _ = decode(string(fuzz.draw(&d, buf[:], ALPHABET)))
		n := copy(buf[:], PHC)
		buf[fuzz.next(&d) % u64(n)] = alphabet[fuzz.next(&d) % u64(len(alphabet))]
		_, _, _, _ = decode(string(buf[:n]))
		free_all(context.temp_allocator)
	}
	testing.expect(t, true)
}
