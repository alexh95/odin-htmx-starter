# platform/fuzz

The parsers' tests' random input (M4-13): a seeded xorshift over bytes drawn mostly from a parser's alphabet. A test
takes `seed(own)` and `rounds(n)`; the nightly's `fuzz` job sets `FUZZ_SCALE` (rounds times that) and `FUZZ_SEED` (mixed
into every seed), so each night tries new input, and the seed in its log reproduces a failure. A test too slow for its
scale takes a `budget()` and stops when it's `spent`, at `FUZZ_MINUTES`, saying how many rounds it ran (markdown's). Not libFuzzer, which
Odin builds no target for. Only `*_test.odin` files import it. L1: core only.
