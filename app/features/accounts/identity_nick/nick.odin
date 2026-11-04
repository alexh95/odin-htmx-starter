package accounts_identity_nick

// ---- nick: a signed nickname, on the LAN (PLAN §17.1, D35; ANSWERS round 9) -------------
//
// A member of the `identity:` family, `streams`' (LC §3). A visitor picks a nickname
// at /login and gets it back as a signed cookie, `nick=<id>.<name>.<expiry>.<mac>`,
// with no account behind it: the id is random, so two people may share a name and
// still be two members. What the cookie is worth is decided on every request, from
// where it comes: a client in ACCOUNTS_NICK_ADMIN_CIDRS is Admin (none by default),
// one in LAN_CIDRS a Member (ACCOUNTS_NICK_FROM=lan, the default; `all` drops the
// check), anyone else a Guest, whose /chat says chat is open on the LAN. The cookie
// is HMAC-SHA256 over the rest with ACCOUNTS_NICK_KEY (ACCOUNTS_NICK_KEY_FILE); with
// none, a key made at boot, so nicknames last until a restart.

import "core:crypto"
import "core:crypto/hash"
import "core:crypto/hmac"
import "core:encoding/base64"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"

import "../../../platform/authz"
import "../../../platform/env"
import "../../../platform/escape"
import "../../../platform/obs"

NAME :: "nick"
SETS_COOKIE :: true

COOKIE :: "nick"

// A nickname: 1 to MAX_NAME runes after trimming, letters, digits, spaces, `_`, `-`
// and `.`, runs of spaces kept to one.
MAX_NAME :: 24

// A nickname lasts this long, renewed when half of it is gone.
LIFE :: 30 * 24 * time.Hour

ENV := [?]env.Row {
	{name = "ACCOUNTS_NICK_FROM", kind = .Enum, def = "lan", choices = "lan|all", doc = "who a nickname makes a Member: lan = clients in LAN_CIDRS, all = anyone"},
	{name = "ACCOUNTS_NICK_ADMIN_CIDRS", kind = .Cidrs, def = "", doc = "clients a nickname makes Admin (/admin/ops): none by default; the e2e suite sets loopback"},
	{name = "ACCOUNTS_NICK_KEY", kind = .Secret, def = "", doc = "the nickname cookies' signing key, at least 32 bytes; unset = one made at boot, so nicknames last until a restart"},
}

@(private)
st: struct {
	key:    [32]byte,
	lan:    []env.Cidr,
	admins: []env.Cidr,
	anyone: bool,
}

// At boot, from app.boot: the env rows, and the key.
init :: proc() {
	env.record("ACCOUNTS_", ENV[:])
	st.lan = env.cidrs("LAN_CIDRS")
	st.admins = env.cidrs("ACCOUNTS_NICK_ADMIN_CIDRS")
	st.anyone = env.str("ACCOUNTS_NICK_FROM") == "all"
	if k := env.str("ACCOUNTS_NICK_KEY"); len(k) >= 32 {
		hash.hash_string_to_buffer(.SHA256, k, st.key[:])
	} else {
		crypto.rand_bytes(st.key[:])
		// Every nickname ends with the process: say so, once, at boot.
		if l, ok := obs.begin(.Warning, "accounts", "nick_key"); ok {
			obs.str(&l, "msg", "ACCOUNTS_NICK_KEY is shorter than 32 bytes; using a boot key" if k != "" else "no ACCOUNTS_NICK_KEY: nicknames last until a restart")
			obs.end(&l)
		}
	}
}

// The identity's own CLI flags: nick has none.
cli :: proc() {}

// A nickname's admin is one by its address, with no list to read.
admin_ids :: proc(out: ^[dynamic]u64) {}

// What a request's cookie and address make its viewer, and a renewed cookie when
// half of its life is gone.
load_viewer :: proc(ask: authz.Ask) -> (v: authz.Viewer, set_cookie: string) {
	id, name, expires, ok := read(authz.cookie(ask.cookies, COOKIE))
	if !ok { return authz.GUEST, "" }
	switch {
	case env.contains(st.admins, ask.client):          v.role = .Admin
	case st.anyone || env.contains(st.lan, ask.client): v.role = .User
	case:                                              return authz.GUEST, ""
	}
	v.id, v.name = id, name
	if expires - time.time_to_unix(time.now()) < i64(LIFE / time.Second) / 2 {
		set_cookie = issue(id, name, ask.https)
	}
	return
}

// Whether a request from `client` may take a nickname: the LAN (or anyone, with
// ACCOUNTS_NICK_FROM=all), and the admin CIDRs.
may_pick :: proc(client: net.Address) -> bool {
	return st.anyone || env.contains(st.lan, client) || env.contains(st.admins, client)
}

// The trimmed nickname, or why it was refused.
check :: proc(raw: string) -> (name: string, problem: string) {
	b := strings.builder_make(context.temp_allocator)
	space := false
	for r in strings.trim_space(raw) {
		switch {
		case unicode.is_space(r):
			space = true
			continue
		case unicode.is_letter(r), unicode.is_digit(r), r == '_', r == '-', r == '.':
		case:
			return "", "A nickname is letters, digits, spaces, _, - and ."
		}
		if space { strings.write_byte(&b, ' ') }
		space = false
		strings.write_rune(&b, r)
	}
	name = strings.to_string(b)
	switch n := utf8.rune_count_in_string(name); {
	case n == 0:        return "", "Pick a nickname first."
	case n > MAX_NAME:  return "", "A nickname is at most 24 characters."
	}
	return name, ""
}

// A Set-Cookie value for a new nickname, with a new id; `keep` keeps an id (a
// renamed member stays the same member).
pick :: proc(name: string, https: bool, keep: u64 = 0) -> string {
	id := keep
	for id == 0 {
		buf: [8]byte
		crypto.rand_bytes(buf[:])
		id = (transmute(u64)buf) >> 11 // 53 bits: exact in a JSON number and a JS one
	}
	return issue(id, name, https)
}

// A Set-Cookie value that ends the nickname.
forget :: proc(https: bool) -> string {
	return strings.concatenate({COOKIE, "=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax", "; Secure" if https else ""}, context.temp_allocator)
}

// ---- the cookie -------------------------------------------------------------------------

@(private)
issue :: proc(id: u64, name: string, https: bool) -> string {
	expires := time.time_to_unix(time.now()) + i64(LIFE / time.Second)
	b := strings.builder_make(context.temp_allocator)
	strings.write_u64(&b, id)
	strings.write_byte(&b, '.')
	strings.write_string(&b, base64.encode(transmute([]byte)name, base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding}))
	strings.write_byte(&b, '.')
	strings.write_i64(&b, expires)
	body := strings.to_string(b)
	mac: [32]byte
	hmac.sum(.SHA256, mac[:], transmute([]byte)body, st.key[:])
	return strings.concatenate({
		COOKIE, "=", body, ".", base64.encode(mac[:], base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding}),
		"; Path=/; Max-Age=", max_age(), "; HttpOnly; SameSite=Lax", "; Secure" if https else "",
	}, context.temp_allocator)
}

@(private)
max_age :: proc() -> string {
	buf: [24]byte
	return strings.clone(strconv.write_int(buf[:], i64(LIFE / time.Second), 10), context.temp_allocator)
}

// The cookie's parts, when its MAC is ours and it hasn't expired.
@(private)
read :: proc(value: string) -> (id: u64, name: string, expires: i64, ok: bool) {
	if value == "" { return }
	dot := strings.last_index_byte(value, '.')
	if dot <= 0 { return }
	body, given := value[:dot], value[dot + 1:]
	mac: [32]byte
	hmac.sum(.SHA256, mac[:], transmute([]byte)body, st.key[:])
	sent, sok := escape.b64_decode(given, url = true)
	if !sok || len(sent) != len(mac) || crypto.compare_constant_time(sent, mac[:]) != 1 { return }
	parts := strings.split(body, ".", context.temp_allocator)
	if len(parts) != 3 { return }
	n, nok := strconv.parse_u64_of_base(parts[0], 10)
	e, eok := strconv.parse_i64_of_base(parts[2], 10)
	raw, derr := base64.decode(parts[1], base64.DEC_URL_TABLE, nil, context.temp_allocator)
	if !nok || !eok || derr != nil || n == 0 || e < time.time_to_unix(time.now()) { return }
	return n, string(raw), e, true
}
