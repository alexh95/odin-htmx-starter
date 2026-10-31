package accounts_identity_accounts

// ---- becoming a member, and getting back in: /register, /reset, the profile (§17.1, Q10) ----
//
// /register follows ACCOUNTS_REGISTRATION: with an invite (the link /register?code=… an admin
// made; the default), anyone, or no one. The new password is hashed on the argon pool, then
// one write creates the member, spends the invite (whose role it takes) and signs them in.
// /reset takes a one-time code an admin issued (no email: §17.1) and a new password, and ends
// every session of the account. Both are limited per client (§17.5).

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"

import "../../../platform/authz"
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

@(private)
registers := web.Limit{n = 3, window = time.Hour}
@(private)
codes_tried := web.Limit{n = 10, window = time.Hour}
// Every reset's new password is hashed on the argon pool: per account, at most these (M4-03). Keyed
// by the account a well-formed code names, not by everyone, so a stranger can't shut /reset (re-read).
@(private)
resets_per_account := web.Limit{n = 5, window = time.Hour}

// A new password on its way through the pool to the write that uses it.
@(private)
Hashing :: struct {
	using hash:  password.Hash,
	deferred:    web.Deferred,
	reset:       bool, // a reset, not a registration
	user_id:     i64,  // a reset's member
	https:       bool,
	client:      u64,
	username:    [accounts.MAX_USERNAME]byte,
	username_n:  int,
	display:     [4 * accounts.MAX_DISPLAY]byte,
	display_n:   int,
	code_hash:   [64]byte, // an invite's, or the reset code's; "" for an open registration
	code_hash_n: int,
}

@(private)
refuse :: proc(res: ^web.Response, why: string) {
	web.respond_html(res, html.field_msg(false, why), .Unprocessable_Content)
}

// ---- /register ----------------------------------------------------------------------------

@(private)
register_page :: proc(req: ^web.Request, res: ^web.Response) {
	b := strings.builder_make(context.temp_allocator)
	code := web.query_get(req, "code")
	switch accounts.registration {
	case .Closed:
		html.page_head(&b, "Account", "Registration is closed", "New members are added by an admin.")
	case .Invite, .Open:
		role := authz.Role.User
		invited := false
		if h := accounts.hash_code(code, accounts.INVITE_GROUPS); h != "" {
			if inv, err := accounts.invite(h, accounts.now_ms()); err == .None { role, invited = inv.role, true }
		}
		lede := "Pick a username, a name to show and a password."
		if accounts.registration == .Invite && !invited { lede = "Registration is by invite: paste the code from your invite link." }
		html.page_head(&b, "Account", fmt.tprintf("Join as %s", authz.ROLE_LABELS[role]) if invited else "Join", lede)
		views.register_form(&b, code, accounts.registration == .Invite)
	}
	web.render_page(req, res, "Join", "/register", "Become a member.", strings.to_string(b))
}

// POST /register: username, display, password, again, code.
@(private)
register :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	if accounts.registration == .Closed {
		web.respond_html(res, html.field_msg(false, "Registration is closed."), .Forbidden)
		return
	}
	key := web.client_key(c.client)
	if ok, retry := web.limit_hit(&registers, key); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many registrations from here: try again later."))
		return
	}
	f := web.form(req)
	code := strings.trim_space(f["code"])
	if code != "" || accounts.registration == .Invite {
		if ok, retry := web.limit_hit(&codes_tried, key); !ok {
			web.respond_limited(res, retry, html.field_msg(false, "Too many codes from here: try again later."))
			return
		}
	}
	name, problem := accounts.check_username(f["username"])
	if problem != "" { refuse(res, problem); return }
	display_raw := f["display"]
	if strings.trim_space(display_raw) == "" { display_raw = name }
	display, dproblem := accounts.clean_name(display_raw)
	if dproblem != "" { refuse(res, dproblem); return }
	if p := accounts.check_new_password(f["password"], f["again"]); p != "" { refuse(res, p); return }
	invite_hash := ""
	if code != "" || accounts.registration == .Invite {
		invite_hash = accounts.hash_code(code, accounts.INVITE_GROUPS)
		if _, err := accounts.invite(invite_hash, accounts.now_ms()); invite_hash == "" || err != .None {
			refuse(res, "That invite isn't valid: it may have been used, or expired.")
			return
		}
	}
	if _, err := accounts.user_by_name(name); err == .None {
		refuse(res, "That username is taken.")
		return
	}

	h := new(Hashing, runtime.heap_allocator())
	h.https, h.client = c.https, key
	h.username_n = copy(h.username[:], name)
	h.display_n = copy(h.display[:], display)
	h.code_hash_n = copy(h.code_hash[:], invite_hash)
	web.defer_response(req, res, &h.deferred)
	if !password.submit_hash(&h.hash, f["password"], hashed) { hashing_done(h, "Busy: try again in a moment.", .Service_Unavailable) }
}

@(private)
hashing_done :: proc(h: ^Hashing, why: string, status: web.Status) {
	if r := web.resume(&h.deferred); r != nil {
		web.respond_html(r, html.field_msg(false, why), status)
		web.finish(&h.deferred, r)
	}
	free(h, runtime.heap_allocator())
}

@(private)
Registering :: struct {
	using reg: m.Register,
	hashing:   ^Hashing,
	token:     string,
}

@(private)
Resetting :: struct {
	using red: m.Redeem_Reset,
	hashing:   ^Hashing,
}

// Back from the pool with the PHC string: the write.
@(private)
hashed :: proc(t: ^workers.Task) {
	h := (^Hashing)(t)
	if !h.ran || h.phc_len == 0 {
		hashing_done(h, "Busy: try again in a moment.", .Service_Unavailable)
		return
	}
	phc := string(h.phc[:h.phc_len])
	code := string(h.code_hash[:h.code_hash_n])
	now := accounts.now_ms()
	if h.reset {
		op := store.new_op(Resetting, len(phc) + len(code))
		a := store.op_allocator(op)
		op.hashing, op.user_id, op.now = h, h.user_id, now
		op.pw_hash, op.code_hash = strings.clone(phc, a), strings.clone(code, a)
		op.done = reset_done
		if !accounts.redeem_reset(op) {
			store.free_op(op)
			hashing_done(h, "Busy: try again in a moment.", .Service_Unavailable)
		}
		return
	}
	token, token_hash := accounts.new_token()
	name, display := string(h.username[:h.username_n]), string(h.display[:h.display_n])
	op := store.new_op(Registering, len(name) + len(display) + len(phc) + len(code) + len(token) + len(token_hash))
	a := store.op_allocator(op)
	op.hashing = h
	op.username, op.display, op.pw_hash = strings.clone(name, a), strings.clone(display, a), strings.clone(phc, a)
	op.invite_hash, op.token, op.token_hash = strings.clone(code, a), strings.clone(token, a), strings.clone(token_hash, a)
	op.now, op.expires_at = now, now + accounts.lifetimes.max_ms
	op.done = registered
	if !accounts.register(op) {
		store.free_op(op)
		hashing_done(h, "Busy: try again in a moment.", .Service_Unavailable)
	}
}

@(private)
registered :: proc(o: ^store.Op) {
	op := (^Registering)(o)
	h := op.hashing
	defer {
		store.free_op(op)
		free(h, runtime.heap_allocator())
	}
	if op.err == .None { // audited before the client is known to be there (M4-04)
		meta: [48]byte
		audit_store.append({op.result, op.display, client_id(h.client)}, "accounts.register", {"user", op.result}, "",
			fmt.bprintf(meta[:], "role=%s invite=%s", authz.ROLE_LABELS[op.role], op.invite_hash[:8] if len(op.invite_hash) >= 8 else "none"))
	}
	res := web.resume(&h.deferred)
	if res == nil { return }
	req := web.request(&h.deferred)
	#partial switch op.err {
	case .None:
		web.set_header(res, "set-cookie", issue(op.token, h.https))
		go(req, res, "/")
	case .Constraint:
		web.respond_html(res, html.field_msg(false, "That username is taken."), .Unprocessable_Content)
	case .Not_Found:
		web.respond_html(res, html.field_msg(false, "That invite isn't valid: it may have been used, or expired."), .Unprocessable_Content)
	case:
		web.respond_store_error(req, res, op.err)
	}
	web.finish(&h.deferred, res)
}

// ---- /reset -------------------------------------------------------------------------------

@(private)
reset_page :: proc(req: ^web.Request, res: ^web.Response) {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Account", "Reset your password", "With the one-time code an admin gave you. Every device signed in as you is signed out.")
	views.reset_form(&b)
	web.render_page(req, res, "Reset your password", "/reset", "Reset your password.", strings.to_string(b))
}

// POST /reset: username, code, password, again.
@(private)
reset :: proc(req: ^web.Request, res: ^web.Response) {
	c := web.ctx()
	key := web.client_key(c.client)
	if ok, retry := web.limit_hit(&codes_tried, key); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many codes from here: try again later."))
		return
	}
	f := web.form(req)
	if p := accounts.check_new_password(f["password"], f["again"]); p != "" { refuse(res, p); return }
	u, err := accounts.user_by_name(strings.trim_space(f["username"]))
	if err != .None && err != .Not_Found {
		web.respond_store_error(req, res, err)
		return
	}
	// The code is checked before anything is hashed, by the same read for a name with no account
	// (user 0): a wrong code answers alike, and as quickly, whether or not the name exists (M4-05).
	code_hash := accounts.hash_code(f["code"], accounts.RESET_GROUPS)
	live := false
	if code_hash != "" {
		ok, rerr := accounts.reset_live(code_hash, u.id if err == .None else 0, accounts.now_ms())
		if rerr != .None {
			web.respond_store_error(req, res, rerr)
			return
		}
		live = ok && err == .None
	}
	if !live {
		refuse(res, "That code doesn't match, or was used.")
		return
	}
	if ok, retry := web.limit_hit(&resets_per_account, u64(u.id)); !ok {
		web.respond_limited(res, retry, html.field_msg(false, "Too many resets for this account: try again later."))
		return
	}
	h := new(Hashing, runtime.heap_allocator())
	h.reset, h.user_id, h.https, h.client = true, u.id, c.https, key
	h.display_n = copy(h.display[:], u.display)
	h.code_hash_n = copy(h.code_hash[:], code_hash)
	web.defer_response(req, res, &h.deferred)
	if !password.submit_hash(&h.hash, f["password"], hashed) { hashing_done(h, "Busy: try again in a moment.", .Service_Unavailable) }
}

@(private)
reset_done :: proc(o: ^store.Op) {
	op := (^Resetting)(o)
	h := op.hashing
	defer {
		store.free_op(op)
		free(h, runtime.heap_allocator())
	}
	if op.err == .None {
		audit_store.append({op.user_id, string(h.display[:h.display_n]), client_id(h.client)}, "accounts.reset", {"user", op.user_id}, "", "")
		// The reset ended every session in the write; an intruder's open pages go now too (M4-09).
		hub.revoke(u64(op.user_id))
	}
	res := web.resume(&h.deferred)
	if res == nil { return }
	req := web.request(&h.deferred)
	#partial switch op.err {
	case .None:
		go(req, res, "/login")
	case .Constraint:
		web.respond_html(res, html.field_msg(false, "That code doesn't match, or was used."), .Unprocessable_Content)
	case:
		web.respond_store_error(req, res, op.err)
	}
	web.finish(&h.deferred, res)
}

// ---- /accounts/profile --------------------------------------------------------------------

@(private)
profile_page :: proc(req: ^web.Request, res: ^web.Response) {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Account", "Your profile", "The name other members see.")
	views.profile_form(&b, web.ctx().viewer.name)
	web.render_page(req, res, "Your profile", "/accounts/profile", "Your profile.", strings.to_string(b))
}

// POST /accounts/profile: display.
@(private)
profile :: proc(req: ^web.Request, res: ^web.Response) {
	display, problem := accounts.clean_name(web.form(req)["display"])
	if problem != "" { refuse(res, problem); return }
	op := store.new_op(Profiling, len(display))
	op.display = strings.clone(display, store.op_allocator(op))
	op.user_id = i64(web.ctx().viewer.id)
	op.done = proc(o: ^store.Op) {
		op := (^Profiling)(o)
		defer store.free_op(op)
		res := web.resume(&op.deferred)
		if res == nil { return }
		if op.err != .None {
			web.respond_store_error(web.request(&op.deferred), res, op.err)
		} else {
			web.respond_html(res, html.field_msg(true, "Saved."))
		}
		web.finish(&op.deferred, res)
	}
	web.defer_response(req, res, &op.deferred)
	if !accounts.set_display(op) {
		if r := web.resume(&op.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&op.deferred, r)
		}
		store.free_op(op)
	}
}

@(private)
Profiling :: struct {
	using set: m.Set_Display,
	deferred:  web.Deferred,
}

// ---- /accounts/theme ----------------------------------------------------------------------

// POST /accounts/theme: style, scheme. The picker's own request (core.js, after it applied the
// choice), so it answers 204: there is nothing to swap.
@(private)
keep_theme :: proc(req: ^web.Request, res: ^web.Response) {
	f := web.form(req)
	style, scheme := f["style"], f["scheme"]
	if !html.theme_known(style, scheme) { refuse(res, "That isn't one of the themes."); return }
	op := store.new_op(Theming, len(style) + len(scheme))
	op.theme = {strings.clone(style, store.op_allocator(op)), strings.clone(scheme, store.op_allocator(op))}
	op.user_id = i64(web.ctx().viewer.id)
	op.done = proc(o: ^store.Op) {
		op := (^Theming)(o)
		defer store.free_op(op)
		res := web.resume(&op.deferred)
		if res == nil { return }
		if op.err != .None {
			web.respond_store_error(web.request(&op.deferred), res, op.err)
		} else {
			web.respond_status(res, .No_Content)
		}
		web.finish(&op.deferred, res)
	}
	web.defer_response(req, res, &op.deferred)
	if !accounts.set_theme(op) {
		if r := web.resume(&op.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&op.deferred, r)
		}
		store.free_op(op)
	}
}

@(private)
Theming :: struct {
	using set: m.Set_Theme,
	deferred:  web.Deferred,
}
