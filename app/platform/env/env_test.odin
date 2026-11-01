package env

import "core:net"
import "core:os"
import "core:slice"
import "core:testing"
import "core:time"

// v2.4.0 warned unknown=ACCOUNTS_TOTP_KEY for its own ACCOUNTS_TOTP_KEY_FILE row: the _FILE was cut
// before the names were compared.
@(test)
unknown_knows_a_row_named_file :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer table = {}
	// HASH is set itself, so the file HASH_FILE names is never read.
	for kv in ([][2]string{{"ENVTEST_KEY_FILE", "/run/keys/k"}, {"ENVTEST_HASH", "h"}, {"ENVTEST_HASH_FILE", "/run/h"}, {"ENVTEST_TYPO", "1"}}) {
		os.set_env(kv[0], kv[1])
	}
	defer for name in ([]string{"ENVTEST_KEY_FILE", "ENVTEST_HASH", "ENVTEST_HASH_FILE", "ENVTEST_TYPO"}) { os.unset_env(name) }
	record("ENVTEST_", {{name = "ENVTEST_KEY_FILE", kind = .Path}, {name = "ENVTEST_HASH", kind = .Secret}})
	got := unknown()
	testing.expectf(t, slice.equal(got, []string{"ENVTEST_TYPO"}), "unknown: %v", got)
}

@(test)
parses_each_kind :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	ok :: proc(t: ^testing.T, row: Row, text: string) -> Value {
		v, problem := parse(row, text)
		testing.expectf(t, problem == "", "%s=%q: %s", row.name, text, problem)
		return v
	}
	bad :: proc(t: ^testing.T, row: Row, text: string) {
		_, problem := parse(row, text)
		testing.expectf(t, problem != "", "%s=%q should be refused", row.name, text)
	}

	testing.expect_value(t, ok(t, {name = "N", kind = .Int}, "8080").i, 8080)
	bad(t, {name = "N", kind = .Int}, "80a")
	testing.expect_value(t, ok(t, {name = "B", kind = .Bool}, "yes").i, 1)
	testing.expect_value(t, ok(t, {name = "B", kind = .Bool}, "0").i, 0)
	bad(t, {name = "B", kind = .Bool}, "maybe")
	testing.expect_value(t, time.Duration(ok(t, {name = "D", kind = .Duration}, "7d").i), 7 * 24 * time.Hour)
	testing.expect_value(t, time.Duration(ok(t, {name = "D", kind = .Duration}, "500ms").i), 500 * time.Millisecond)
	bad(t, {name = "D", kind = .Duration}, "5")
	bad(t, {name = "D", kind = .Duration}, "-5s")
	testing.expect_value(t, ok(t, {name = "S", kind = .Size}, "16MiB").i, 16 << 20)
	testing.expect_value(t, ok(t, {name = "S", kind = .Size}, "512").i, 512)
	bad(t, {name = "S", kind = .Size}, "16MB")
	bad(t, {name = "S", kind = .Size}, "99999999999999GiB")
	ok(t, {name = "E", kind = .Enum, choices = "single|ephemeral"}, "single")
	bad(t, {name = "E", kind = .Enum, choices = "single|ephemeral"}, "multi")
	testing.expect_value(t, ok(t, {name = "U", kind = .Int}, "").i, 0) // unset, no default

	c := ok(t, {name = "C", kind = .Cidrs}, "192.168.0.0/16, 10.0.0.1").cidrs
	testing.expect_value(t, len(c), 2)
	testing.expect(t, contains(c, net.IP4_Address{192, 168, 4, 20}))
	testing.expect(t, contains(c, net.IP4_Address{10, 0, 0, 1}))
	testing.expect(t, !contains(c, net.IP4_Address{10, 0, 0, 2}))
	testing.expect(t, !contains(c, net.IP4_Address{192, 169, 0, 1}))
	bad(t, {name = "C", kind = .Cidrs}, "192.168.0.0/33")
	bad(t, {name = "C", kind = .Cidrs}, "not-an-ip/8")
}
