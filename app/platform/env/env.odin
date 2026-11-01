package env

// ---- platform/env: the typed environment table (L2) ------------------------
//
// D10, PLAN §8.5. `app.boot` records the platform's rows and each feature's
// `init` records its own, then reads them; features never import platform/app.
// Every value is parsed once, when its row is recorded; a bad one is fatal with
// a message naming the variable. `NAME_FILE` reads the value from a file (a
// compose secret) when `NAME` itself is unset. --limits and --features --json
// print the table with secrets masked, and boot warns on an unknown variable
// inside a recorded prefix (`CHAT_RINGBYTES`, a typo).

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Kind :: enum u8 {
	String,
	Int,
	Bool,
	Duration, // 500ms, 30s, 15m, 2h, 7d
	Size,     // 512, 64KiB, 16MiB, 1GiB
	Cidrs,    // 192.168.0.0/16,10.0.0.0/8
	Enum,     // one of `choices`, "a|b|c"
	Path,
	Secret,   // never printed
}

Row :: struct {
	name:    string,
	kind:    Kind,
	def:     string, // the default, written as the variable would be; "" = unset
	doc:     string,
	choices: string, // Enum: "single|ephemeral"
}

Cidr :: struct {
	addr: net.Address,
	bits: int,
}

Value :: struct {
	row:   Row,
	text:  string, // as given, or the default
	set:   bool,   // given in the environment, not defaulted
	i:     i64,    // Int, Duration (ns), Size (bytes), Bool (0/1)
	cidrs: []Cidr,
}

@(private)
table: struct {
	values:   [dynamic]Value,
	prefixes: [dynamic]string,
	problems: [dynamic]string,
}

// Records `rows` and parses each one's value. `prefix` ("CHAT_") is the
// feature's: an unknown variable that starts with it is warned about; the
// platform's rows pass "". Problems are fatal at `check_problems`.
record :: proc(prefix: string, rows: []Row) {
	if prefix != "" { append(&table.prefixes, prefix) }
	for row in rows {
		text, set := lookup(row.name)
		if !set { text = row.def }
		v, problem := parse(row, text)
		v.set = set
		if problem != "" {
			append(&table.problems, fmt.aprintf("%s=%q: %s", row.name, text if row.kind != .Secret else "…", problem))
		}
		append(&table.values, v)
	}
}

// `NAME`, else the contents of the file `NAME_FILE` names, trimmed.
@(private)
lookup :: proc(name: string) -> (text: string, set: bool) {
	if v, ok := os.lookup_env(name, context.allocator); ok { return v, true }
	file_var := strings.concatenate({name, "_FILE"}, context.temp_allocator)
	if path, ok := os.lookup_env(file_var, context.temp_allocator); ok && path != "" {
		data, err := os.read_entire_file(path, context.allocator)
		if err != nil {
			append(&table.problems, fmt.aprintf("%s=%q: can't read it (%v)", file_var, path, err))
			return "", false
		}
		return strings.trim_space(string(data)), true
	}
	return "", false
}

// Parses `text` for `row`; "" with no default is a valid unset value.
parse :: proc(row: Row, text: string) -> (v: Value, problem: string) {
	v.row, v.text = row, text
	if text == "" { return }
	switch row.kind {
	case .String, .Path, .Secret:
	case .Int:
		n, ok := strconv.parse_i64_of_base(text, 10)
		if !ok { return v, "not a whole number" }
		v.i = n
	case .Bool:
		switch strings.to_lower(text, context.temp_allocator) {
		case "1", "true", "yes", "on":  v.i = 1
		case "0", "false", "no", "off": v.i = 0
		case: return v, "not 1/0, true/false, yes/no or on/off"
		}
	case .Duration:
		d, ok := parse_duration(text)
		if !ok { return v, "not a duration like 500ms, 30s, 15m, 2h or 7d" }
		v.i = i64(d)
	case .Size:
		n, ok := parse_size(text)
		if !ok { return v, "not a size like 512, 64KiB or 16MiB" }
		v.i = n
	case .Cidrs:
		cidrs, ok := parse_cidrs(text)
		if !ok { return v, "not a comma-separated list of CIDRs like 192.168.0.0/16" }
		v.cidrs = cidrs
	case .Enum:
		rest := row.choices
		for c in strings.split_iterator(&rest, "|") {
			if c == text { return }
		}
		return v, fmt.tprintf("not one of %s", row.choices)
	}
	return
}

parse_duration :: proc(s: string) -> (d: time.Duration, ok: bool) {
	UNITS := [?]struct {
		suffix: string,
		unit:   time.Duration,
	}{{"ms", time.Millisecond}, {"s", time.Second}, {"m", time.Minute}, {"h", time.Hour}, {"d", 24 * time.Hour}}
	for u in UNITS {
		if strings.has_suffix(s, u.suffix) {
			num := s[:len(s) - len(u.suffix)]
			n, nok := strconv.parse_i64_of_base(num, 10)
			if !nok || n < 0 { return }
			return time.Duration(n) * u.unit, true
		}
	}
	return
}

parse_size :: proc(s: string) -> (bytes: i64, ok: bool) {
	UNITS := [?]struct {
		suffix: string,
		unit:   i64,
	}{{"GiB", 1 << 30}, {"MiB", 1 << 20}, {"KiB", 1 << 10}, {"B", 1}}
	num, unit := s, i64(1)
	for u in UNITS {
		if strings.has_suffix(s, u.suffix) {
			num, unit = s[:len(s) - len(u.suffix)], u.unit
			break
		}
	}
	n, nok := strconv.parse_i64_of_base(num, 10)
	if !nok || n < 0 || n > max(i64) / unit { return }
	return n * unit, true
}

parse_cidrs :: proc(s: string) -> (out: []Cidr, ok: bool) {
	list := make([dynamic]Cidr)
	rest := s
	for part in strings.split_iterator(&rest, ",") {
		p := strings.trim_space(part)
		if p == "" { continue }
		addr_text, slash, bits_text := strings.partition(p, "/")
		addr := net.parse_address(addr_text)
		if addr == nil { delete(list); return }
		_, v4 := addr.(net.IP4_Address)
		width := 32 if v4 else 128
		bits := width
		if slash != "" {
			n, nok := strconv.parse_int(bits_text, 10)
			if !nok || n < 0 || n > width { delete(list); return }
			bits = n
		}
		append(&list, Cidr{addr, bits})
	}
	return list[:], true
}

// Whether `a` falls in any of `cidrs`.
contains :: proc(cidrs: []Cidr, a: net.Address) -> bool {
	for c in cidrs {
		switch x in c.addr {
		case net.IP4_Address:
			y := a.(net.IP4_Address) or_continue
			xb, yb := x, y
			if prefix_equal(xb[:], yb[:], c.bits) { return true }
		case net.IP6_Address:
			y := a.(net.IP6_Address) or_continue
			xb := transmute([16]u8)x
			yb := transmute([16]u8)y
			if prefix_equal(xb[:], yb[:], c.bits) { return true }
		}
	}
	return false
}

@(private)
prefix_equal :: proc(a, b: []u8, bits: int) -> bool {
	full := bits / 8
	for i in 0 ..< full {
		if a[i] != b[i] { return false }
	}
	if rem := bits % 8; rem != 0 {
		mask := u8(0xff) << u8(8 - rem)
		if a[full] & mask != b[full] & mask { return false }
	}
	return true
}

// ---- reads: at boot, by the package that recorded the row ------------------

get :: proc(name: string) -> ^Value {
	for &v in table.values {
		if v.row.name == name { return &v }
	}
	fmt.panicf("env: %s was never recorded", name)
}

str :: proc(name: string) -> string { return get(name).text }
int_ :: proc(name: string) -> int { return int(get(name).i) }
bool_ :: proc(name: string) -> bool { return get(name).i != 0 }
duration :: proc(name: string) -> time.Duration { return time.Duration(get(name).i) }
size :: proc(name: string) -> int { return int(get(name).i) }
cidrs :: proc(name: string) -> []Cidr { return get(name).cidrs }
is_set :: proc(name: string) -> bool { return get(name).set }

values :: proc() -> []Value { return table.values[:] }

// The bad values, one line each; app.check exits when there is any.
problems :: proc() -> []string { return table.problems[:] }

// Variables inside a recorded prefix that no row names: a typo, most likely.
unknown :: proc(allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	environ, _ := os.environ(context.temp_allocator)
	outer: for kv in environ {
		raw, _, _ := strings.partition(kv, "=")
		name := strings.trim_suffix(raw, "_FILE")
		for p in table.prefixes {
			if !strings.has_prefix(name, p) { continue }
			// A row may itself end in _FILE (ACCOUNTS_TOTP_KEY_FILE names a file it reads raw).
			for v in table.values {
				if v.row.name == name || v.row.name == raw { continue outer }
			}
			append(&out, name)
			continue outer
		}
	}
	return out[:]
}
