package accounts_identity_accounts

// ---- the second factor: the code step, step-up and enrolment (PLAN §17.1, Q11) ------------
//
// A sign-in to an account with TOTP stops after the password: the answer is a code form that
// carries a pending token (the user id and five minutes, signed with a key made at boot), and
// /login/code opens the session with a code from the app or a recovery code, spending it in
// the session's own write so it is never taken twice. A `.Step_Up` row sends a session whose
// last check is older than ACCOUNTS_STEP_UP_WINDOW to /step-up, which takes the password or a
// code. /accounts/totp turns it on (the secret shown once, in base32 and as `otpauth://` text,
// confirmed by a code) and hands out ten recovery codes, shown once and stored hashed.

import "base:runtime"
import "core:crypto"
import "core:crypto/hash"
import "core:crypto/hmac"
import "core:encoding/base64"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/escape"
import "../../../platform/html"
import "../../../platform/password"
import "../../../platform/store"
import "../../../platform/totp"
import "../../../platform/web"
import accounts ".."
import m "../models"
import views "../views"
import audit_store "store:audit"

// How long a password-verified sign-in waits for its code.
@(private)
PENDING_LIFE :: 5 * 60

// ---- the pending token ------------------------------------------------------------------

@(private)
pending :: proc(user_id: i64) -> string {
	body := fmt.tprintf("%d.%d", user_id, time.time_to_unix(time.now()) + PENDING_LIFE)
	mac: [32]byte
	hmac.sum(hash.Algorithm.SHA256, mac[:], transmute([]byte)body, st.pending_key[:])
	return strings.concatenate({body, ".", base64.encode(mac[:], base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding})}, context.temp_allocator)
}

@(private)
read_pending :: proc(token: string) -> (user_id: i64, ok: bool) {
	dot := strings.last_index_byte(token, '.')
	if dot <= 0 { return }
	body := token[:dot]
	mac: [32]byte
	hmac.sum(hash.Algorithm.SHA256, mac[:], transmute([]byte)body, st.pending_key[:])
	sent, sok := escape.b64_decode(token[dot + 1:], url = true)
	if !sok || len(sent) != len(mac) || crypto.compare_constant_time(sent, mac[:]) != 1 { return }
	id_text, _, until_text := strings.partition(body, ".")
	id, iok := strconv.parse_i64_of_base(id_text, 10)
	until, uok := strconv.parse_i64_of_base(until_text, 10)
	if !iok || !uok || until < time.time_to_unix(time.now()) { return }
	return id, true
}

// A code from the app (the step it matched), or else a recovery code's hash; both zero: neither.
@(private)
read_code :: proc(u: m.User, text: string) -> (step: i64, recovery_hash: string) {
	secret, ok := totp.decode(open_secret(u.id, u.totp_secret))
	if !ok { return }
	if s, vok := totp.verify(secret[:], text, totp.now()); vok { return s, "" }
	return 0, accounts.hash_recovery(text)
}

// ---- POST /login/code ---------------------------------------------------------------------

@(private)
second_factor :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	if !admit_attempt(res, c) { return }
	f := web.form(req)
	id, ok := read_pending(f["pending"])
	u: m.User
	err := m.Error.Not_Found
	if ok { u, err = accounts.user_by_id(id) }
	if err != .None || u.disabled_at != 0 || u.totp_secret == "" {
		web.respond_html(res, html.field_msg(false, "That sign-in took too long: start again."), .Unprocessable_Content)
		return
	}
	device := device_of(req, c.https, u.id)
	if shut_out(res, door(u, 0, device), "Too many wrong codes: wait a little, then try again.") { return }
	step, recovery := read_code(u, strings.trim_space(f["code"]))
	if step == 0 && recovery == "" {
		wrong(u.id, u.failed_logins, device)
		audit_store.append({client = client_id(web.client_key(c.client))}, "accounts.sign_in_failed", {"user", u.id}, "", "factor=totp")
		web.respond_html(res, html.field_msg(false, "Wrong code, or one used already."), .Unprocessable_Content)
		return
	}
	l := new_login(req, u, true, safe_next(f["next"]), .Sign_In)
	l.device = device
	web.defer_response(req, res, &l.deferred)
	open_session(l, step, recovery)
}

// The sign-in limits (§17.5), for every attempt at a password or a code.
@(private)
admit_attempt :: proc(res: ^web.Response, c: ^web.Req_Ctx) -> bool {
	if ok, retry := web.limit_hit(&logins_client, web.client_key(c.client)); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many sign-ins from here: wait a little, then try again."))
		return false
	}
	if ok, retry := web.limit_hit(&logins_net, web.net_key(c.client)); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many sign-ins from your network: wait a little, then try again."))
		return false
	}
	return true
}

// ---- step-up --------------------------------------------------------------------------------

@(private)
step_up_page :: proc(req: ^web.Request, res: ^web.Response) {
	u, err := accounts.user_by_id(i64(web.ctx().viewer.id))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Account", "Confirm it's you", "This needs a recent check: your password, or a code from your app.")
	views.step_up_form(&b, safe_next(web.query_get(req, "next")), u.totp_secret != "")
	web.render_page(req, res, "Confirm it's you", "/step-up", "Confirm it's you.", strings.to_string(b))
}

// A member's own step-ups, by their id: never the sign-in's buckets, which a stranger can fill from
// outside and so lock every admin out of their writes (M4-03).
@(private)
step_ups := web.Limit{n = 10, window = WINDOW}

// POST /step-up, `secret` (the password, or six digits from the app) and `next`.
@(private)
step_up :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	if ok, retry := web.limit_hit(&step_ups, c.viewer.id); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many tries: wait a little, then try again."))
		return
	}
	u, err := accounts.user_by_id(i64(c.viewer.id))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	// A device the account trusts meets its own door, not the account's, which a stranger may be
	// holding shut (M4-03 b).
	device := device_of(req, c.https, u.id)
	if shut_out(res, door(u, 0, device), "Too many wrong tries: wait a little, then try again.") { return }
	f := web.form(req)
	secret := f["secret"]
	l := new_login(req, u, true, safe_next(f["next"]), .Step_Up)
	l.device = device
	web.defer_response(req, res, &l.deferred)
	// Six digits are a code (a password is at least ten bytes); anything else, the password.
	if code := strings.trim_space(secret); u.totp_secret != "" && len(code) == totp.DIGITS {
		step, _ := read_code(u, code)
		if step == 0 {
			wrong(u.id, u.failed_logins, device)
			answer(l, html.field_msg(false, "Wrong code, or one used already."), .Unprocessable_Content)
			return
		}
		step_up_write(l, step)
		return
	}
	if !password.submit(&l.verify, secret, u.pw_hash, verified) {
		answer(l, html.field_msg(false, "Busy: try again in a moment."), .Service_Unavailable)
	}
}

@(private)
Stepping :: struct {
	using up: m.Step_Up,
	login:    ^Login,
}

// The session's step_up_at is now; by code, the step is spent in the same write.
@(private)
step_up_write :: proc(l: ^Login, step: i64) {
	name := string(l.name[:l.name_len])
	op := store.new_op(Stepping, l.old_len + len(name))
	a := store.op_allocator(op)
	op.login = l
	op.token_hash = strings.clone(string(l.old[:l.old_len]), a)
	op.user_id, op.now, op.totp_step = l.user_id, accounts.now_ms(), step
	op.audit = {
		actor_id = l.user_id, actor_name = strings.clone(name, a), client = strings.clone(client_id(l.client), a),
		action = "accounts.step_up", target_kind = "session", meta = "factor=totp" if step > 0 else "factor=password",
	}
	op.done = proc(o: ^store.Op) {
		op := (^Stepping)(o)
		l := op.login
		defer {
			store.free_op(op)
			free(l, runtime.heap_allocator())
		}
		res := web.resume(&l.deferred)
		if res == nil { return }
		req := web.request(&l.deferred)
		#partial switch op.err {
		case .None:
			go(req, res, string(l.next[:l.next_len]))
		case .Constraint:
			web.respond_html(res, html.field_msg(false, "Wrong code, or one used already."), .Unprocessable_Content)
		case:
			web.respond_store_error(req, res, op.err)
		}
		web.finish(&l.deferred, res)
	}
	if !accounts.step_up(op) {
		store.free_op(op)
		answer(l, html.field_msg(false, "Busy: try again in a moment."), .Service_Unavailable)
	}
}

// ---- /accounts/totp -----------------------------------------------------------------------

@(private)
totp_page :: proc(req: ^web.Request, res: ^web.Response) {
	u, err := accounts.user_by_id(i64(web.ctx().viewer.id))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Account", "Two-step sign-in", "A code from an authenticator app after your password.")
	if u.totp_secret != "" {
		left, _ := accounts.recovery_left(u.id)
		views.totp_on(&b, left)
	} else {
		secret := totp.new_secret()
		text := totp.encode(secret[:])
		host := web.host_of(req)
		views.totp_setup(&b, text, totp.uri(host if host != "" else "houston", u.username, text), u.role == .Admin && st.admin_totp)
	}
	web.render_page(req, res, "Two-step sign-in", "/accounts/totp", "Two-step sign-in.", strings.to_string(b))
}

// POST /accounts/totp (a step-up), `secret` (as the page showed it) and `code`: on, if the code is
// the secret's and none is set yet; the answer is the recovery codes, shown this once. Replacing a
// second factor would let whoever holds a session step up with their own (M4-01): it goes off
// first, which is a step-up of the factor in force.
@(private)
totp_on :: proc(req: ^web.Request, res: ^web.Response) {
	u, err := accounts.user_by_id(i64(web.ctx().viewer.id))
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if u.totp_secret != "" {
		refuse(res, "Two-step sign-in is already on: turn it off first.")
		return
	}
	f := web.form(req)
	secret, ok := totp.decode(f["secret"])
	step: i64
	if ok { step, ok = totp.verify(secret[:], strings.trim_space(f["code"]), totp.now()) }
	if !ok {
		web.respond_html(res, html.field_msg(false, "That code doesn't match: check the app's clock, and try the next one."), .Unprocessable_Content)
		return
	}
	set_totp(req, res, seal_secret(u.id, totp.encode(secret[:])), step, "accounts.totp_on", enrol = true)
}

// POST /accounts/totp/codes (a step-up): ten new recovery codes, the old ones gone.
@(private)
totp_codes :: proc(req: ^web.Request, res: ^web.Response) {
	u, err := accounts.user_by_id(i64(web.ctx().viewer.id))
	if err != .None || u.totp_secret == "" {
		web.respond_html(res, html.field_msg(false, "Two-step sign-in is off."), .Unprocessable_Content)
		return
	}
	// Only over the factor read here: an off (or an off and a new one) between the read and the write
	// isn't undone (the M4 re-read).
	set_totp(req, res, u.totp_secret, u.totp_last_step, "accounts.recovery_codes", was = u.totp_secret)
}

// POST /accounts/totp/off (a step-up).
@(private)
totp_off :: proc(req: ^web.Request, res: ^web.Response) {
	set_totp(req, res, "", 0, "accounts.totp_off")
}

@(private)
Setting :: struct {
	using set: m.Set_Totp,
	deferred:  web.Deferred,
	shown:     [m.RECOVERY_CODES]string, // the codes as the member reads them, this once
	action:    string,
	name:      string,
	client:    u64,
}

@(private)
set_totp :: proc(req: ^web.Request, res: ^web.Response, secret: string, last_step: i64, action: string, enrol := false, was := "") {
	c := web.ctx()
	codes := accounts.new_recovery_codes() if secret != "" else {}
	op := store.new_op(Setting, len(secret) + len(was) + len(action) + len(c.viewer.name) + 2 * m.RECOVERY_CODES * 80)
	a := store.op_allocator(op)
	op.was = strings.clone(was, a)
	op.user_id, op.secret, op.last_step, op.enrol = i64(c.viewer.id), strings.clone(secret, a), last_step, enrol
	op.action, op.name, op.client = strings.clone(action, a), strings.clone(c.viewer.name, a), web.client_key(c.client)
	op.audit = {actor_id = op.user_id, actor_name = op.name, client = strings.clone(client_id(op.client), a), action = op.action, target_kind = "user", target_id = op.user_id}
	for code, i in codes {
		if code == "" { continue }
		op.shown[i] = strings.clone(code, a)
		op.codes[i] = strings.clone(accounts.hash_recovery(code), a)
	}
	op.done = proc(o: ^store.Op) {
		op := (^Setting)(o)
		defer store.free_op(op)
		res := web.resume(&op.deferred)
		if res == nil { return }
		req := web.request(&op.deferred)
		switch {
		case op.enrol && op.err == .Constraint:
			refuse(res, "Two-step sign-in is already on: turn it off first.")
		case op.was != "" && op.err == .Constraint:
			refuse(res, "Two-step sign-in changed meanwhile: look again.")
		case op.err != .None:
			web.respond_store_error(req, res, op.err)
		case op.secret == "":
			go(req, res, "/accounts/totp")
		case:
			b := strings.builder_make(context.temp_allocator)
			views.recovery_codes(&b, op.shown[:])
			web.respond_html(res, strings.to_string(b))
		}
		web.finish(&op.deferred, res)
	}
	web.defer_response(req, res, &op.deferred)
	if !accounts.set_totp(op) {
		if r := web.resume(&op.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&op.deferred, r)
		}
		store.free_op(op)
	}
}
