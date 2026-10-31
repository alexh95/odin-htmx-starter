package accounts_identity_envadmin

// ---- envadmin: one admin from the environment, a signed cookie (PLAN §17.1, D35) ------------
//
// A member of the `identity:` family for the profiles with no SQLite (D18): one admin, whose
// password is ACCOUNTS_ADMIN_HASH (made with `--hash-password`), signs in at /login and gets a
// stateless cookie, `admin=<issued>.<expires>.<mac>` (HMAC-SHA256 with ACCOUNTS_ENVADMIN_KEY,
// `HttpOnly; SameSite=Lax; Path=/`, host-only, `Secure` per COOKIE_SECURE). There is no
// session to revoke: sign-out forgets the cookie in this browser, and a new key signs everyone
// out. Everyone else is a Guest. The time it was issued is the last password check, for
// step-up (/step-up issues a fresh one). The spark pattern (06 §3.1).

import "core:crypto"
import "core:crypto/hash"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/env"
import "../../../platform/obs"
import "../../../platform/password"
import "../../../platform/signed"

NAME :: "envadmin"
SETS_COOKIE :: true

COOKIE :: "admin"

ENV := [?]env.Row {
	{name = "ACCOUNTS_ADMIN_HASH", kind = .Secret, def = "", doc = "the admin's argon2id hash (bin --hash-password); unset = no one can sign in"},
	{name = "ACCOUNTS_ADMIN_NAME", kind = .String, def = "admin", doc = "the admin's name, as pages show it"},
	{name = "ACCOUNTS_ENVADMIN_KEY", kind = .Secret, def = "", doc = "the cookie's signing key, at least 32 bytes; unset = one made at boot, so a restart signs the admin out"},
	{name = "ACCOUNTS_ENVADMIN_LIFE", kind = .Duration, def = "7d", doc = "how long a sign-in lasts"},
	{name = "ACCOUNTS_ARGON_THREADS", kind = .Int, def = "1", doc = "argon2id pool threads, each holding 19 MiB"},
	{name = "ACCOUNTS_LOGIN_PER_CLIENT", kind = .Int, def = "5", doc = "sign-in attempts per client per 15 min"},
	{name = "ACCOUNTS_LOGIN_OVERALL", kind = .Int, def = "40", doc = "sign-in attempts from everyone per 15 min"},
	{name = "ACCOUNTS_STEP_UP_WINDOW", kind = .Duration, def = "10m", doc = "how recent a password a .Step_Up route asks for"},
}

COOKIE_ENV := [?]env.Row {
	{name = "COOKIE_SECURE", kind = .Enum, def = "auto", choices = "auto|1|0", doc = "Secure on the cookie: auto = when the request came as https through a trusted proxy; 0 warns at every boot"},
}

@(private)
st: struct {
	key:    [32]byte,
	hash:   string,
	name:   string,
	life:   i64, // seconds
	secure: enum u8 { Auto, Always, Never },
}

init :: proc() {
	env.record("ACCOUNTS_", ENV[:])
	env.record("", COOKIE_ENV[:])
	st.hash, st.name = env.str("ACCOUNTS_ADMIN_HASH"), env.str("ACCOUNTS_ADMIN_NAME")
	st.life = i64(env.duration("ACCOUNTS_ENVADMIN_LIFE") / time.Second)
	authz.step_up_window = i64(env.duration("ACCOUNTS_STEP_UP_WINDOW") / time.Second)
	switch env.str("COOKIE_SECURE") {
	case "1": st.secure = .Always
	case "0":
		st.secure = .Never
		warn("cookie_insecure", "COOKIE_SECURE=0: the admin cookie travels over plain http")
	}
	if k := env.str("ACCOUNTS_ENVADMIN_KEY"); len(k) >= 32 {
		hash.hash_string_to_buffer(.SHA256, k, st.key[:])
	} else {
		crypto.rand_bytes(st.key[:])
		warn("envadmin_key", "ACCOUNTS_ENVADMIN_KEY is shorter than 32 bytes; using a boot key" if k != "" else "no ACCOUNTS_ENVADMIN_KEY: a restart signs the admin out")
	}
	if st.hash == "" {
		warn("no_admin", "no ACCOUNTS_ADMIN_HASH: no one can sign in (bin --hash-password)")
	} else if _, _, _, ok := password.decode(st.hash); !ok {
		fmt.eprintln("accounts: ACCOUNTS_ADMIN_HASH is not an argon2id hash from --hash-password")
		os.exit(78)
	}
	logins_client.n = env.int_("ACCOUNTS_LOGIN_PER_CLIENT")
	logins_all.n = env.int_("ACCOUNTS_LOGIN_OVERALL")
	threads := max(env.int_("ACCOUNTS_ARGON_THREADS"), 1)
	password.start(threads)
	obs.limit("argon", "memory", i64(threads) * 19 * 1024 * 1024, "bytes")
}

@(private)
warn :: proc(ev, msg: string) {
	if l, ok := obs.begin(.Warning, "accounts", ev); ok {
		obs.str(&l, "msg", msg)
		obs.end(&l)
	}
}

cli :: proc() { password.cli() }

// The admin, while the cookie's MAC is ours and it hasn't expired; anyone else is a Guest.
load_viewer :: proc(ask: authz.Ask) -> (v: authz.Viewer, set_cookie: string) {
	value := authz.cookie(ask.cookies, COOKIE)
	if value == "" { return authz.GUEST, "" }
	issued, ok := read(value, st.key[:], time.time_to_unix(time.now()))
	if !ok { return authz.GUEST, forget(ask.https) }
	return authz.Viewer{id = 1, name = st.name, role = .Admin, step_up_at = issued}, ""
}

// ---- the cookie -------------------------------------------------------------------------

// `<issued>.<expires>.<mac>`, the MAC over the rest.
sign :: proc(key: []byte, issued, expires: i64) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_i64(&b, issued)
	strings.write_byte(&b, '.')
	strings.write_i64(&b, expires)
	return signed.sign(strings.to_string(b), key)
}

// When the value was issued, if its MAC is `key`'s and `now` is before its end.
read :: proc(value: string, key: []byte, now: i64) -> (issued: i64, ok: bool) {
	body := signed.open(value, key) or_return // the untrusted part, fuzzed there (M4-13)
	i_text, _, e_text := strings.partition(body, ".")
	i, iok := strconv.parse_i64_of_base(i_text, 10)
	e, eok := strconv.parse_i64_of_base(e_text, 10)
	if !iok || !eok || now >= e || i > now { return }
	return i, true
}

@(private)
secure :: proc(https: bool) -> bool {
	switch st.secure {
	case .Always: return true
	case .Never:  return false
	case .Auto:
	}
	return https
}

// A Set-Cookie value for a sign-in now.
issue :: proc(https: bool) -> string {
	now := time.time_to_unix(time.now())
	buf: [24]byte
	return strings.concatenate({
		COOKIE, "=", sign(st.key[:], now, now + st.life), "; Path=/; Max-Age=", strconv.write_int(buf[:], st.life, 10),
		"; HttpOnly; SameSite=Lax", "; Secure" if secure(https) else "",
	}, context.temp_allocator)
}

forget :: proc(https: bool) -> string {
	return strings.concatenate({COOKIE, "=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax", "; Secure" if secure(https) else ""}, context.temp_allocator)
}
