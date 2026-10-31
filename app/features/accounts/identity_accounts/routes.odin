package accounts_identity_accounts

// ---- /login, /logout and the member's sessions ---------------------------------------------
//
// Mounted by a profile on the accounts identity as {"accounts", identity.ROUTES[:]}. A sign-in
// is two hops off the loop, answered through one deferred response: the password's verify on
// the argon pool, then the session's write on the writer task. Sign-ins, wrong passwords for an
// existing account and a revoke of another session go to the audit log (§17.7).

import "base:runtime"
import "core:crypto/hmac"
import "core:crypto/sha2"
import "core:encoding/endian"
import "core:fmt"
import "core:hash"
import "core:strings"
import "core:time"

import "../../../platform/guard"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/password"
import "../../../platform/store"
import "../../../platform/web"
import "../../../platform/workers"
import accounts ".."
import m "../models"
import views "../views"
import audit_store "store:audit"

EXTS :: web.Exts{.Prompt, .Sse} // an admin's reason for each change (HX-Prompt); a member's #live

// The member's own topic, on every page of theirs (§9.1): what a revoke ends (hub.revoke, on a
// role change or a disable) and where an account notice will go.
TOPICS := [?]hub.Topic {
	{family = "accounts.user", policy = .Queue, member = true, perm = .Account_Self},
}

ROUTES := [?]web.Route {
	{.Get, "/login", page, .Public, {.Private}, 0},
	{.Post, "/login", sign_in, .Public, {.Fragment}, 2048},
	{.Post, "/logout", sign_out, .Public, {.Fragment}, 0},
	{.Get, "/accounts/sessions", sessions_page, .Account_Self, {.Private}, 0},
	{.Post, "/accounts/sessions/revoke", revoke, .Account_Self, {.Fragment}, 256},
	{.Post, "/login/code", second_factor, .Public, {.Fragment}, 1024},
	{.Get, "/step%-up", step_up_page, .Account_Self, {.Private}, 0},
	{.Post, "/step%-up", step_up, .Account_Self, {.Fragment}, 2048},
	{.Get, "/accounts/totp", totp_page, .Account_Self, {.Private}, 0},
	{.Post, "/accounts/totp", totp_on, .Account_Self, {.Fragment, .Step_Up}, 512},
	{.Post, "/accounts/totp/codes", totp_codes, .Account_Self, {.Fragment, .Step_Up}, 0},
	{.Post, "/accounts/totp/off", totp_off, .Account_Self, {.Fragment, .Step_Up}, 0},
	{.Get, "/register", register_page, .Public, {.Private}, 0},
	{.Post, "/register", register, .Public, {.Fragment}, 2048},
	{.Get, "/reset", reset_page, .Public, {.Private}, 0},
	{.Post, "/reset", reset, .Public, {.Fragment}, 2048},
	{.Get, "/accounts/profile", profile_page, .Account_Self, {.Private}, 0},
	{.Post, "/accounts/profile", profile, .Account_Self, {.Fragment}, 512},
	{.Post, "/accounts/theme", keep_theme, .Account_Self, {.Fragment}, 256},
	{.Get, "/admin/accounts", admin_page, .Admin_Accounts, {.Private, .Lan_Only}, 0},
	{.Post, "/admin/accounts/(%d+)/role", admin_role, .Admin_Accounts, {.Fragment, .Lan_Only, .Step_Up}, 256},
	{.Post, "/admin/accounts/(%d+)/disable", admin_disable, .Admin_Accounts, {.Fragment, .Lan_Only, .Step_Up}, 0},
	{.Post, "/admin/accounts/(%d+)/enable", admin_enable, .Admin_Accounts, {.Fragment, .Lan_Only, .Step_Up}, 0},
	{.Post, "/admin/accounts/(%d+)/reset", admin_reset, .Admin_Accounts, {.Fragment, .Lan_Only, .Step_Up}, 0},
	{.Post, "/admin/accounts/(%d+)/two%-step%-off", admin_totp_off, .Admin_Accounts, {.Fragment, .Lan_Only, .Step_Up}, 0},
	{.Post, "/admin/accounts/invites", admin_invite, .Admin_Accounts, {.Fragment, .Lan_Only, .Step_Up}, 256},
	{.Post, "/admin/accounts/invites/delete", admin_uninvite, .Admin_Accounts, {.Fragment, .Lan_Only, .Step_Up}, 256},
}

// §17.5: attempts, right or wrong, per client and from everyone (n set at init).
@(private)
WINDOW :: 15 * time.Minute
@(private)
logins_client := web.Limit{n = 5, window = WINDOW}
@(private)
logins_all := web.Limit{n = 40, window = WINDOW}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	b := strings.builder_make(context.temp_allocator)
	if c.viewer.id != 0 {
		html.page_head(&b, "Account", fmt.tprintf("Signed in as %s", c.viewer.name), "Sign out here, or see where else you are signed in.")
		views.signed_in(&b)
	} else {
		html.page_head(&b, "Account", "Sign in", "With the username and password an admin gave you.")
		views.login_form(&b, safe_next(web.query_get(req, "next")), insecure())
	}
	web.render_page(req, res, "Sign in", "/login", "Sign in to your account.", strings.to_string(b))
}

// ---- signing in ---------------------------------------------------------------------------

// What a verified password goes on to: a session (or the code step first), or a step-up.
@(private)
Then :: enum u8 {
	Sign_In,
	Step_Up,
}

// On the heap from the handler to the answer: the pool's task, then the session's op.
@(private)
Login :: struct {
	using verify: password.Verify,
	deferred:     web.Deferred,
	then:         Then,
	user_id:      i64,
	failed:       int,
	known:        bool, // an enabled user by that name: a wrong password counts against it
	ghost:        u64,  // otherwise the name's key in `ghosts`, where its wrong passwords count
	totp:         bool, // the account has a second factor: a sign-in asks for a code next
	https:        bool,
	client:       u64, // web.client_key: the audit's client id
	name:         [4 * accounts.MAX_DISPLAY]byte, // a display name: up to 40 runes
	name_len:     int,
	next:         [512]byte,
	next_len:     int,
	old:          [64]byte, // the session the request carried: closed by a sign-in, stepped up by a step-up
	old_len:      int,
}

@(private)
new_login :: proc(req: ^web.Request, u: m.User, known: bool, next: string, then: Then) -> ^Login {
	c := web.ctx()
	l := new(Login, runtime.heap_allocator())
	l.then, l.user_id, l.failed, l.known, l.totp = then, u.id, u.failed_logins, known, known && u.totp_secret != ""
	l.https, l.client = c.https, web.client_key(c.client)
	l.name_len = copy(l.name[:], u.display)
	l.next_len = copy(l.next[:], next)
	l.old_len = copy(l.old[:], current_hash(req))
	return l
}

// Answers a deferred request that ends here, and lets the Login go.
@(private)
answer :: proc(l: ^Login, body: string, status: web.Status) {
	if r := web.resume(&l.deferred); r != nil {
		web.respond_html(r, body, status)
		web.finish(&l.deferred, r)
	}
	free(l, runtime.heap_allocator())
}

@(private)
Opening :: struct {
	using open: m.Open_Session,
	login:      ^Login,
	token:      string, // the cookie's, in the op's arena
}

// POST /login, `username`, `password` and `next`.
@(private)
sign_in :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	if ok, retry := web.limit_hit(&logins_client, web.client_key(c.client)); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many sign-ins from here: wait a little, then try again."))
		return
	}
	if ok, retry := web.limit_hit(&logins_all, 0); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many sign-ins right now: wait a little, then try again."))
		return
	}
	f := web.form(req)
	name, pw := strings.trim_space(f["username"]), f["password"]
	if name == "" || pw == "" {
		web.respond_html(res, html.field_msg(false, "Enter your username and password."), .Unprocessable_Content)
		return
	}
	u, err := accounts.user_by_name(name)
	if err != .None && err != .Not_Found {
		web.respond_store_error(req, res, err)
		return
	}
	known := err == .None && u.disabled_at == 0
	ghost := u64(0) if known else ghost_key(name)
	until := u.backoff_until if known else ghost_until(ghost)
	if now := accounts.now_ms(); until > now {
		web.respond_limited(res, time.Duration(until - now) * time.Millisecond,
			html.field_msg(false, "Too many wrong passwords: wait a little, then try again."))
		return
	}

	l := new_login(req, u, known, safe_next(f["next"]), .Sign_In)
	l.ghost = ghost
	web.defer_response(req, res, &l.deferred)
	// An unknown name is verified against the dummy all the same: the answer's time is the same.
	if !password.submit(&l.verify, pw, u.pw_hash if known else "", verified) {
		answer(l, html.field_msg(false, "Busy: try again in a moment."), .Service_Unavailable)
	}
}

// Back on the loop from the pool.
@(private)
verified :: proc(t: ^workers.Task) {
	l := (^Login)(t)
	switch {
	case !l.ran:
		answer(l, html.field_msg(false, "Busy: try again in a moment."), .Service_Unavailable)
	case !l.ok:
		if l.known {
			count_failure(l.user_id, l.failed + 1)
			audit_store.append({client = client_id(l.client)}, "accounts.sign_in_failed", {"user", l.user_id}, "", "factor=password")
		} else if l.ghost != 0 {
			ghost_failed(l.ghost)
		}
		answer(l, html.field_msg(false, "Wrong username or password." if l.then == .Sign_In else "That isn't your password."), .Unprocessable_Content)
	case l.then == .Step_Up:
		step_up_write(l, 0)
	case l.totp:
		// The password was right; the session waits for the code (second.odin).
		b := strings.builder_make(context.temp_allocator)
		views.code_form(&b, pending(l.user_id), string(l.next[:l.next_len]))
		answer(l, strings.to_string(b), .OK)
	case:
		open_session(l, 0, "")
	}
}

// The session for a verified sign-in: by password alone, or with the second factor it spends.
@(private)
open_session :: proc(l: ^Login, step: i64, recovery_hash: string) {
	now := accounts.now_ms()
	token, hash := accounts.new_token()
	old := string(l.old[:l.old_len])
	op := store.new_op(Opening, len(token) + len(hash) + len(old) + len(recovery_hash))
	a := store.op_allocator(op)
	op.login = l
	op.token, op.token_hash, op.old_hash = strings.clone(token, a), strings.clone(hash, a), strings.clone(old, a)
	op.totp_step, op.recovery_hash = step, strings.clone(recovery_hash, a)
	op.user_id, op.now = l.user_id, now
	op.expires_at, op.idle_before = now + accounts.lifetimes.max_ms, now - accounts.lifetimes.idle_ms
	op.done = opened
	if !accounts.open_session(op) {
		if r := web.resume(&l.deferred); r != nil {
			web.respond_store_error(web.request(&l.deferred), r, .Busy)
			web.finish(&l.deferred, r)
		}
		store.free_op(op)
		free(l, runtime.heap_allocator())
	}
}

@(private)
opened :: proc(o: ^store.Op) {
	op := (^Opening)(o)
	l := op.login
	defer {
		store.free_op(op)
		free(l, runtime.heap_allocator())
	}
	// Audited whether or not the client is still there: the write is done either way (M4-04).
	factor := "factor=totp" if op.totp_step > 0 else "factor=recovery" if op.recovery_hash != "" else ""
	#partial switch op.err {
	case .None:
		audit_store.append({l.user_id, string(l.name[:l.name_len]), client_id(l.client)}, "accounts.sign_in", {"session", 0}, "", factor)
	case .Constraint:
		// A code taken already, or a recovery code that is none of the account's unused ones.
		count_failure(l.user_id, l.failed + 1)
		audit_store.append({client = client_id(l.client)}, "accounts.sign_in_failed", {"user", l.user_id}, "", factor)
	}
	// A client that left has a session row it never got: it dies idle, or at its next sign-in's sweep.
	res := web.resume(&l.deferred)
	if res == nil { return }
	req := web.request(&l.deferred)
	#partial switch op.err {
	case .None:
		web.set_header(res, "set-cookie", issue(op.token, l.https))
		go(req, res, string(l.next[:l.next_len]))
	case .Constraint:
		web.respond_html(res, html.field_msg(false, "Wrong code, or one used already."), .Unprocessable_Content)
	case:
		web.respond_store_error(req, res, op.err)
	}
	web.finish(&l.deferred, res)
}

// One more wrong password, and the account's door shut a little longer.
@(private)
count_failure :: proc(user_id: i64, failed: int) {
	op := store.new_op(m.Login_Failed, 0)
	op.user_id = user_id
	op.backoff_until = accounts.now_ms() + accounts.backoff_ms(failed)
	op.done = proc(o: ^store.Op) { store.free_op(o) }
	if !accounts.login_failed(op) { store.free_op(op) }
}

// ---- names with no account back off too (M4-05) --------------------------------------------
//
// Without this, the fourth wrong password in a row answered 429 only for a name that exists. A
// name with no account (or a disabled one) counts its wrong passwords here, with an account's
// backoff, for the process's life. The table is fixed, so a flood of names allocates nothing:
// two names in one slot take turns, and the newer one starts again from no failures.

@(private) GHOSTS :: 4096

@(private)
Ghost :: struct {
	key:    u64,
	failed: int,
	until:  i64,
}

@(private)
ghosts: struct {
	mu:    guard.Mutex,
	slots: [GHOSTS]Ghost,
}

// Never 0, which is "a known account" in Login.
@(private)
ghost_key :: proc(name: string) -> u64 {
	lower := strings.to_lower(name, context.temp_allocator) // usernames compare without case
	return hash.fnv64a(transmute([]byte)lower) | 1
}

@(private)
ghost_until :: proc(key: u64) -> i64 {
	guard.lock(&ghosts.mu)
	defer guard.unlock(&ghosts.mu)
	g := &ghosts.slots[key % GHOSTS]
	return g.until if g.key == key else 0
}

@(private)
ghost_failed :: proc(key: u64) {
	guard.lock(&ghosts.mu)
	defer guard.unlock(&ghosts.mu)
	g := &ghosts.slots[key % GHOSTS]
	if g.key != key { g^ = {key = key} }
	g.failed += 1
	g.until = accounts.now_ms() + accounts.backoff_ms(g.failed)
}

// A session seen again, written at most once a minute (load_viewer).
@(private)
touch :: proc(token_hash: string, now: i64) {
	op := store.new_op(m.Touch_Session, len(token_hash))
	op.token_hash = strings.clone(token_hash, store.op_allocator(op))
	op.now = now
	op.done = proc(o: ^store.Op) { store.free_op(o) }
	if !accounts.touch_session(op) { store.free_op(op) }
}

// ---- signing out and the sessions page ----------------------------------------------------

@(private)
sign_out :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	token := web.cookie(req, cookie_name(c.https))
	if c.viewer.id == 0 || len(token) != accounts.TOKEN_TEXT {
		web.set_header(res, "set-cookie", forget(c.https))
		go(req, res, "/")
		return
	}
	closing(req, res, accounts.hash_token(token), "/")
}

@(private)
sessions_page :: proc(req: ^web.Request, res: ^web.Response) {
	list := make([dynamic]m.Session, context.temp_allocator)
	if err := accounts.sessions_of(i64(web.ctx().viewer.id), &list); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Account", "Your sessions", "Every device signed in as you. Revoke one you don't recognise; it is signed out at its next request.")
	views.sessions(&b, list[:], current_hash(req))
	web.render_page(req, res, "Your sessions", "/accounts/sessions", "The devices signed in to your account.", strings.to_string(b))
}

// POST /accounts/sessions/revoke, `session`: one of the member's own (the store checks whose).
// Revoking this one is signing out.
@(private)
revoke :: proc(req: ^web.Request, res: ^web.Response) {
	h := web.form(req)["session"]
	if len(h) != 64 {
		web.respond_html(res, html.field_msg(false, "No such session."), .Unprocessable_Content)
		return
	}
	closing(req, res, h, "/login" if h == current_hash(req) else "")
}

@(private)
Closing :: struct {
	using close: m.Close_Session,
	deferred:    web.Deferred,
	current:     string, // this request's session, for the list's mark
	to:          string, // "" = answer the list again; else the cookie ends and the page goes there
	https:       bool,
	name:        string, // the member's, for the audit
	client:      u64,
}

@(private)
closing :: proc(req: ^web.Request, res: ^web.Response, token_hash, to: string) {
	c := web.ctx()
	current := current_hash(req)
	op := store.new_op(Closing, len(token_hash) + len(current) + len(to) + len(c.viewer.name))
	a := store.op_allocator(op)
	op.token_hash, op.current, op.to = strings.clone(token_hash, a), strings.clone(current, a), strings.clone(to, a)
	op.name = strings.clone(c.viewer.name, a)
	op.user_id, op.https, op.client = i64(c.viewer.id), c.https, web.client_key(c.client)
	op.done = closed
	web.defer_response(req, res, &op.deferred)
	if !accounts.close_session(op) {
		if r := web.resume(&op.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&op.deferred, r)
		}
		store.free_op(op)
	}
}

@(private)
closed :: proc(o: ^store.Op) {
	op := (^Closing)(o)
	defer store.free_op(op)
	// That device's open pages go now, not at their next request (M4-09); its other sessions stay.
	if op.ended { hub.revoke_session(u64(op.user_id), session_key(op.token_hash)) }
	if op.ended && op.to == "" {
		meta: [24]byte
		audit_store.append({op.user_id, op.name, client_id(op.client)}, "accounts.revoke", {"session", 0}, "",
			fmt.bprintf(meta[:], "session=%s", op.token_hash[:min(len(op.token_hash), 8)]))
	}
	res := web.resume(&op.deferred)
	if res == nil { return }
	req := web.request(&op.deferred)
	switch {
	case op.err != .None:
		web.respond_store_error(req, res, op.err)
	case op.to != "":
		web.set_header(res, "set-cookie", forget(op.https))
		go(req, res, op.to)
	case:
		list := make([dynamic]m.Session, context.temp_allocator)
		if err := accounts.sessions_of(op.user_id, &list); err != .None {
			web.respond_store_error(req, res, err)
		} else {
			b := strings.builder_make(context.temp_allocator)
			views.sessions(&b, list[:], op.current)
			web.respond_html(res, strings.to_string(b))
		}
	}
	web.finish(&op.deferred, res)
}

// ---- helpers ------------------------------------------------------------------------------

// The audit's client id: an HMAC of the address's key (web.client_key) under ACCOUNTS_AUDIT_KEY,
// never the address, and not one anyone without the key can hash back (M4-07). In a per-thread
// buffer, not the request's arena, so a continuation can audit before it knows the client is still
// there (M4-04); audit's append copies it at once.
@(private, thread_local)
client_buf: [16]byte

@(private)
client_id :: proc(key: u64) -> string {
	msg := transmute([8]byte)key
	mac: [sha2.DIGEST_SIZE_256]byte
	hmac.sum(.SHA256, mac[:], msg[:], st.audit_key)
	return fmt.bprintf(client_buf[:], "%016x", endian.unchecked_get_u64be(mac[:8]))
}

// The hash of the session this request carries, or "".
@(private)
current_hash :: proc(req: ^web.Request) -> string {
	token := web.cookie(req, cookie_name(web.ctx().https))
	return accounts.hash_token(token) if len(token) == accounts.TOKEN_TEXT else ""
}

// Where an htmx form lands: HX-Redirect; a plain form post: 303.
@(private)
go :: proc(req: ^web.Request, res: ^web.Response, to: string) {
	if web.is_htmx(req) {
		web.set_header(res, "hx-redirect", to)
		web.respond_status(res, .No_Content)
		return
	}
	web.set_header(res, "location", to)
	web.respond_status(res, .See_Other)
}

// A path on this site, or "/": never another origin.
@(private)
safe_next :: proc(next: string) -> string {
	return next if html.site_path(next) else "/"
}
