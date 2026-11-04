package accounts_identity_accounts

// ---- accounts: usernames, passwords and server-side sessions (PLAN §17.1, D35) --------------
//
// A member of the `identity:` family, `full`'s (LC §3), on SQLite. A member signs in at /login
// with a username and a password (argon2id on platform/password's pool) and gets an opaque
// token in the `sid` cookie: `HttpOnly; SameSite=Lax; Path=/`, no Domain (host-only, so it never
// reaches `full`'s lab host), `Secure` per COOKIE_SECURE, and then named `__Host-sid`. The store keeps only the token's
// SHA-256. The token rotates on every sign-in; a privilege change rotates it too (slice 6).
// The first admin comes from ACCOUNTS_ADMIN_HASH, made with `--hash-password`.

import "core:crypto"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/env"
import "../../../platform/obs"
import "../../../platform/password"
import accounts ".."
import audit_store "store:audit"

NAME :: "accounts"
SETS_COOKIE :: true

// A Secure cookie is `__Host-sid`, which a browser takes only from this host, with no Domain and
// Path=/: a sibling under the same site (the lab host, another witness) can't plant one that
// signs a victim in as the attacker (M4-08). `sid` stays for COOKIE_SECURE=0 and plain-http auto.
COOKIE :: "sid"
COOKIE_HOST :: "__Host-sid"

cookie_name :: proc(https: bool) -> string { return COOKIE_HOST if secure(https) else COOKIE }

ENV := [?]env.Row {
	{name = "ACCOUNTS_ADMIN_HASH", kind = .Secret, def = "", doc = "the bootstrap admin's argon2id hash (bin --hash-password), used while no enabled admin exists"},
	{name = "ACCOUNTS_ADMIN_NAME", kind = .String, def = "admin", doc = "the bootstrap admin's username"},
	{name = "ACCOUNTS_ARGON_THREADS", kind = .Int, def = "0", doc = "argon2id pool threads, each holding 19 MiB: 0 = 1 with two cores or fewer, else 2"},
	{name = "ACCOUNTS_SESSION_IDLE", kind = .Duration, def = "14d", doc = "a session ends this long after it was last seen"},
	{name = "ACCOUNTS_SESSION_MAX", kind = .Duration, def = "30d", doc = "a session ends this long after sign-in, seen or not"},
	{name = "ACCOUNTS_LOGIN_PER_CLIENT", kind = .Int, def = "5", doc = "sign-in attempts per client per 15 min"},
	{name = "ACCOUNTS_LOGIN_PER_NET", kind = .Int, def = "20", doc = "sign-in attempts per network (an IPv4 /24, an IPv6 /48) per 15 min"},
	{name = "ACCOUNTS_LOGIN_OVERALL", kind = .Int, def = "40", doc = "password checks from everyone per 15 min: only attempts that reach the argon pool count"},
	{name = "ACCOUNTS_STEP_UP_PER_MEMBER", kind = .Int, def = "10", doc = "a member's step-up attempts per 15 min"},
	{name = "ACCOUNTS_ADMIN_TOTP", kind = .Enum, def = "required", choices = "required|optional", doc = "required: an Admin without TOTP is a Member until they turn it on (§17.1)"},
	{name = "ACCOUNTS_STEP_UP_WINDOW", kind = .Duration, def = "10m", doc = "how recent a password or code a .Step_Up route asks for"},
	{name = "ACCOUNTS_REGISTRATION", kind = .Enum, def = "invite", choices = "invite|open|closed", doc = "who may register at /register: with an invite (Q10), anyone, or no one"},
	{name = "ACCOUNTS_REGISTER_PER_HOUR", kind = .Int, def = "3", doc = "registrations tried per client per hour"},
	{name = "ACCOUNTS_CODES_PER_HOUR", kind = .Int, def = "10", doc = "invite and reset codes tried per client per hour"},
	{name = "ACCOUNTS_TOTP_KEY_FILE", kind = .Path, def = "", doc = "a file holding the 32-byte key TOTP secrets are sealed with (raw, or 64 hex digits); unset = stored in plaintext, said at boot"},
	{name = "ACCOUNTS_AUDIT_KEY", kind = .Secret, def = "", doc = "keys the audit log's client ids (an HMAC of the address), at least 32 bytes; unset = a key per boot, so a client's entries group within one run only"},
}

COOKIE_ENV := [?]env.Row {
	{name = "COOKIE_SECURE", kind = .Enum, def = "auto", choices = "auto|1|0", doc = "Secure on the session cookie: auto = when the request came as https through a trusted proxy; 0 warns at every boot"},
}

Secure :: enum u8 {
	Auto,
	Always,
	Never,
}

@(private)
st: struct {
	secure:      Secure,
	admin_totp:  bool,     // an Admin needs TOTP to be one
	pending_key: [32]byte, // signs a sign-in's pending second step; a restart drops them all
	// Keys the audit's client ids: unkeyed, the 2^32 IPv4 addresses hash back in seconds (M4-07).
	audit_key:   []byte,
	boot_key:    [32]byte,
	device_key:  [32]byte, // MACs the device cookies (doors.odin): the TOTP key's, else a boot's
	totp_key:     [32]byte, // seals the TOTP secrets (seal.odin)
	has_totp_key: bool,
}

// At boot, from app.boot: the env rows, the lifetimes and the argon pool.
init :: proc() {
	authz.theme_href = "/accounts/theme"
	// A change's audit entry goes in the change's own write (M4-04), through audit's store.
	accounts.set_audit_writer(audit_store.append_in)
	env.record("ACCOUNTS_", ENV[:])
	env.record("", COOKIE_ENV[:])
	switch env.str("COOKIE_SECURE") {
	case "1": st.secure = .Always
	case "0":
		st.secure = .Never
		// Plain-http stages need it (07 §5.5); say so every boot, so it isn't forgotten.
		if l, ok := obs.begin(.Warning, "accounts", "cookie_insecure"); ok {
			obs.str(&l, "msg", "COOKIE_SECURE=0: the session cookie travels over plain http")
			obs.end(&l)
		}
	}
	accounts.lifetimes = {
		idle_ms = i64(env.duration("ACCOUNTS_SESSION_IDLE") / time.Millisecond),
		max_ms = i64(env.duration("ACCOUNTS_SESSION_MAX") / time.Millisecond),
	}
	st.admin_totp = env.str("ACCOUNTS_ADMIN_TOTP") == "required"
	switch env.str("ACCOUNTS_REGISTRATION") {
	case "open":   accounts.registration = .Open
	case "closed": accounts.registration = .Closed
	case:          accounts.registration = .Invite
	}
	registers.n = env.int_("ACCOUNTS_REGISTER_PER_HOUR")
	codes_tried.n = env.int_("ACCOUNTS_CODES_PER_HOUR")
	authz.step_up_window = i64(env.duration("ACCOUNTS_STEP_UP_WINDOW") / time.Second)
	crypto.rand_bytes(st.pending_key[:])
	crypto.rand_bytes(st.boot_key[:])
	crypto.rand_bytes(st.device_key[:])
	load_totp_key()
	k := env.str("ACCOUNTS_AUDIT_KEY")
	st.audit_key = transmute([]byte)k if len(k) >= 32 else st.boot_key[:]
	if k != "" && len(k) < 32 {
		// Short, it falls with the 2^32 addresses to a search: a boot key instead.
		if l, ok := obs.begin(.Warning, "accounts", "audit_key"); ok {
			obs.str(&l, "msg", "ACCOUNTS_AUDIT_KEY is shorter than 32 bytes; using a boot key")
			obs.end(&l)
		}
	}
	logins_client.n = env.int_("ACCOUNTS_LOGIN_PER_CLIENT")
	logins_net.n = env.int_("ACCOUNTS_LOGIN_PER_NET")
	logins_all.n = env.int_("ACCOUNTS_LOGIN_OVERALL")
	step_ups.n = env.int_("ACCOUNTS_STEP_UP_PER_MEMBER")
	threads := env.int_("ACCOUNTS_ARGON_THREADS")
	if threads <= 0 { threads = 1 if os.get_processor_core_count() <= 2 else 2 }
	password.start(threads)
	obs.limit("argon", "memory", i64(threads) * 19 * 1024 * 1024, "bytes")
}

// The identity's own CLI flag: `--hash-password` reads a password from stdin (one line) and
// prints its PHC string, for ACCOUNTS_ADMIN_HASH, and to stderr how long the derive took,
// which says what a sign-in costs on this machine (§17.1: ≤ 100 ms wanted).
cli :: proc() { password.cli() }

// Every enabled admin, from any thread (a job's).
admin_ids :: proc(out: ^[dynamic]u64) { accounts.admin_ids(out) }

// From main, after the migrations: the first admin, while no enabled one exists. A hash that
// isn't one of platform/password's refuses to boot; no admin and no hash warns.
bootstrap :: proc() {
	// This identity audits: without the writer its changes would go unlogged, silently (M4-04).
	if !accounts.has_audit_writer() {
		fmt.eprintln("accounts: the audit writer is unset: identity_accounts' init must hand store:audit's append_in to the accounts store")
		os.exit(70)
	}
	seal_stored_secrets()
	phc := env.str("ACCOUNTS_ADMIN_HASH")
	if phc == "" {
		if n, _ := accounts.count_admins(); n == 0 {
			if l, ok := obs.begin(.Warning, "accounts", "no_admin"); ok {
				obs.str(&l, "msg", "no admin yet: set ACCOUNTS_ADMIN_HASH (bin --hash-password)")
				obs.end(&l)
			}
		}
		return
	}
	if _, _, _, ok := password.decode(phc); !ok {
		fmt.eprintln("accounts: ACCOUNTS_ADMIN_HASH is not an argon2id hash from --hash-password")
		os.exit(78)
	}
	// The name matters only when an admin is to be written: one made before under another rule boots.
	if n, err := accounts.count_admins(); err == .None && n > 0 { return }
	name, problem := accounts.check_username(env.str("ACCOUNTS_ADMIN_NAME"))
	if problem != "" {
		fmt.eprintfln("accounts: ACCOUNTS_ADMIN_NAME: %s", problem)
		os.exit(78)
	}
	made, err := accounts.bootstrap_admin(name, phc)
	if err == .Constraint {
		// 78, a configuration to change, as a bad hash is: a restart can't help either.
		fmt.eprintfln("accounts: ACCOUNTS_ADMIN_NAME %q is a member's username: name another admin", name)
		os.exit(78)
	}
	if err != .None {
		fmt.eprintln("accounts: the bootstrap admin could not be written")
		os.exit(70)
	}
	if made {
		if l, ok := obs.begin(.Info, "accounts", "admin_created"); ok {
			obs.str(&l, "name", name)
			obs.end(&l)
		}
	}
}

// The viewer a request's `sid` names; a cookie whose session has ended is cleared.
load_viewer :: proc(ask: authz.Ask) -> (v: authz.Viewer, set_cookie: string) {
	token := authz.cookie(ask.cookies, cookie_name(ask.https))
	if token == "" { return authz.GUEST, "" }
	now := accounts.now_ms()
	u, s, err := accounts.signed_in(token, now)
	#partial switch err {
	case .None:
	case .Not_Found:
		return authz.GUEST, forget(ask.https)
	case:
		// The store failed, not the session: a guest this once, and the cookie kept.
		if l, ok := obs.begin(.Warning, "accounts", "session_read"); ok {
			obs.str(&l, "err", fmt.tprint(err))
			obs.end(&l)
		}
		return authz.GUEST, ""
	}
	if now - s.last_seen >= accounts.TOUCH_EVERY_MS { touch(s.token_hash, now) }
	role := u.role
	// An Admin is one only with a second factor; until then /accounts/totp says why.
	if role == .Admin && u.totp_secret == "" && st.admin_totp { role = .User }
	// A failed read costs only the kept theme: the page renders the brand's.
	t, _ := accounts.theme_of(u.id)
	return authz.Viewer{
		id = u64(u.id), name = u.display, role = role, step_up_at = s.step_up_at / 1000,
		style = t.style, scheme = t.scheme, session = session_key(s.token_hash),
	}, ""
}

// A session's key for the hub (authz.Viewer.session): its hash's first 16 hex digits, never 0.
@(private)
session_key :: proc(token_hash: string) -> u64 {
	if len(token_hash) < 16 { return 1 }
	k, _ := strconv.parse_u64_of_base(token_hash[:16], 16)
	return k | 1
}

// ---- the cookie -------------------------------------------------------------------------

secure :: proc(https: bool) -> bool {
	switch st.secure {
	case .Always: return true
	case .Never:  return false
	case .Auto:
	}
	return https
}

insecure :: proc() -> bool { return st.secure == .Never }

// A Set-Cookie value for a new session's token; it lasts as long as the session can.
issue :: proc(token: string, https: bool) -> string {
	buf: [24]byte
	age := strconv.write_int(buf[:], accounts.lifetimes.max_ms / 1000, 10)
	return strings.concatenate({cookie_name(https), "=", token, "; Path=/; Max-Age=", age, "; HttpOnly; SameSite=Lax", "; Secure" if secure(https) else ""}, context.temp_allocator)
}

// A Set-Cookie value that ends the cookie.
forget :: proc(https: bool) -> string {
	return strings.concatenate({cookie_name(https), "=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax", "; Secure" if secure(https) else ""}, context.temp_allocator)
}
