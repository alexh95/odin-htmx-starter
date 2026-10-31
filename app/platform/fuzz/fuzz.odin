package fuzz

// ---- random input for the parsers' tests (M4-13) --------------------------------------------
//
// Not libFuzzer, which Odin doesn't build for: a seeded xorshift over bytes drawn mostly from the
// parser's own alphabet, now and then any byte, so a failure reproduces from its seed. A trap
// fails the run. A test asks for `rounds(n)` and starts its Draw from `seed(s)`: n and its own s
// on every run, and in the nightly FUZZ_SCALE times as many rounds from FUZZ_SEED's seed, so each
// night tries inputs no run tried before (the seed is in its log to reproduce one). Only tests
// import it.

import "core:os"
import "core:strconv"

Draw :: struct {
	s: u64,
}

// The test's own seed, or FUZZ_SEED mixed into it; never 0, which xorshift would stay at.
seed :: proc(own: u64) -> Draw {
	s := own
	if v, ok := strconv.parse_u64(os.get_env("FUZZ_SEED", context.temp_allocator)); ok { s ~= v * 0x9E3779B97F4A7C15 }
	return {s if s != 0 else own}
}

// The test's own count, FUZZ_SCALE times over in the nightly.
rounds :: proc(n: int) -> int {
	if k, ok := strconv.parse_int(os.get_env("FUZZ_SCALE", context.temp_allocator)); ok && k > 1 { return n * k }
	return n
}

next :: proc(d: ^Draw) -> u64 {
	d.s ~= d.s << 13
	d.s ~= d.s >> 7
	d.s ~= d.s << 17
	return d.s
}

// Up to len(buf) bytes, most from `alphabet`, one in sixteen any byte.
draw :: proc(d: ^Draw, buf: []byte, alphabet: string) -> []byte {
	n := int(next(d) % u64(len(buf) + 1))
	for i in 0 ..< n {
		r := next(d)
		buf[i] = alphabet[r % u64(len(alphabet))] if r & 15 != 0 else byte(r >> 8)
	}
	return buf[:n]
}
