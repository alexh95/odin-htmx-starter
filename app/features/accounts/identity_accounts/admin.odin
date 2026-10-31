package accounts_identity_accounts

// ---- /admin/accounts: members, invites and reset codes (§17.1, §17.7) ----------------------
//
// Admins only, from the LAN, and every write asks for a step-up and a reason (hx-prompt sends
// it as HX-Prompt), which goes to the audit log with the change. A role change or a disable
// ends the member's sessions, so it is in force at their next request; the last enabled admin
// can be neither demoted nor disabled. Invite and reset codes are shown once, to the admin who
// made them, and stored hashed.

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:strings"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/store"
import "../../../platform/web"
import accounts ".."
import m "../models"
import views "../views"

// How long a reset code and an invite live.
@(private)
RESET_LIFE_MS :: 24 * 3_600_000
@(private)
MAX_INVITE_DAYS :: 30
@(private)
MAX_INVITE_USES :: 50

@(private)
admin_page :: proc(req: ^web.Request, res: ^web.Response) {
	users := make([dynamic]m.User, context.temp_allocator)
	invites := make([dynamic]m.Invite, context.temp_allocator)
	err := accounts.users(&users)
	if err == .None { err = accounts.invites(accounts.now_ms(), &invites) }
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Admin", "Accounts", "Members, their roles, invites and reset codes. Each change asks why, and goes to the audit log.")
	views.admin_accounts(&b, users[:], invites[:], i64(web.ctx().viewer.id))
	web.render_page(req, res, "Accounts", "/admin/accounts", "Accounts.", strings.to_string(b))
}

// ---- the one shape every write takes ------------------------------------------------------

// Who asked, why, and what to say when the store has answered.
@(private)
Act :: struct {
	deferred:  web.Deferred,
	actor_id:  i64,
	actor:     string,
	client:    u64,
	reason:    string,
	action:    string,
	target:    m.User, // id only, unless named
	meta:      string,
	show:      string, // a fragment to answer with; "" = back to /admin/accounts
	revoke:    bool,   // the member's streams end too: a role change, a disable
}

// Fills the act's own strings into the op's arena, and the entry the change writes with itself
// (M4-04) from them.
@(private)
act_init :: proc(act: ^Act, audit: ^m.Audit, a: runtime.Allocator, reason, action, meta: string, target: i64) {
	c := web.ctx()
	act.actor_id, act.client = i64(c.viewer.id), web.client_key(c.client)
	act.actor = strings.clone(c.viewer.name, a)
	act.reason, act.action, act.meta = strings.clone(reason, a), strings.clone(action, a), strings.clone(meta, a)
	act.target.id = target
	audit^ = {
		actor_id = act.actor_id, actor_name = act.actor, client = strings.clone(client_id(act.client), a),
		action = act.action, target_kind = "user" if target != 0 else "invite", target_id = target,
		reason = act.reason, meta = act.meta,
	}
}

@(private)
ACT_BYTES :: 4 * web.MAX_REASON + 256 + 16

// After the write, which wrote its entry too (M4-04): the revoke, then the answer.
@(private)
acted :: proc(o: ^store.Op, act: ^Act, refused: string) {
	defer store.free_op(o)
	// Their sessions ended in the write; their open pages go now (X19), whether or not the admin's
	// client is still there.
	if o.err == .None && act.revoke { hub.revoke(u64(act.target.id)) }
	res := web.resume(&act.deferred)
	if res == nil { return }
	req := web.request(&act.deferred)
	#partial switch o.err {
	case .None:
		if act.show != "" {
			web.respond_html(res, act.show)
		} else {
			go(req, res, "/admin/accounts")
		}
	case .Constraint:
		web.respond_html(res, html.toast("error", refused, true), .Conflict)
	case:
		web.respond_store_error(req, res, o.err)
	}
	web.finish(&act.deferred, res)
}

// Queues the op, or answers 503 at once.
@(private)
queue :: proc(req: ^web.Request, res: ^web.Response, o: ^store.Op, act: ^Act, queued: proc(op: ^store.Op) -> bool) {
	web.defer_response(req, res, &act.deferred)
	if !queued(o) {
		if r := web.resume(&act.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&act.deferred, r)
		}
		store.free_op(o)
	}
}

@(private)
member_of :: proc(req: ^web.Request, res: ^web.Response) -> (id: i64, ok: bool) {
	if id, ok = web.parse_id(req.url_params[0]); !ok { web.not_found(req, res) }
	return
}

// ---- role, disable, enable ------------------------------------------------------------------

@(private)
Roling :: struct {
	using set: m.Set_Role,
	act:       Act,
}

@(private)
admin_role :: proc(req: ^web.Request, res: ^web.Response) {
	id, id_ok := member_of(req, res)
	if !id_ok { return }
	role: authz.Role
	found := false
	want := web.form(req)["role"]
	for label, r in authz.ROLE_LABELS {
		if label == want && r != .Guest { role, found = r, true }
	}
	if !found {
		web.respond_html(res, html.toast("error", "No such role.", true), .Unprocessable_Content)
		return
	}
	reason, reason_ok := web.prompt_reason(req, res)
	if !reason_ok { return }
	op := store.new_op(Roling, ACT_BYTES)
	act_init(&op.act, &op.audit, store.op_allocator(op), reason, "accounts.role", fmt.tprintf("role=%s", authz.ROLE_LABELS[role]), id)
	op.user_id, op.role, op.act.revoke = id, role, true
	op.done = proc(o: ^store.Op) { acted(o, &(^Roling)(o).act, "That is the last admin: make another one first.") }
	queue(req, res, op, &op.act, proc(o: ^store.Op) -> bool { return accounts.set_role((^Roling)(o)) })
}

@(private)
Disabling :: struct {
	using set: m.Set_Disabled,
	act:       Act,
}

@(private)
admin_disable :: proc(req: ^web.Request, res: ^web.Response) { disable(req, res, true) }
@(private)
admin_enable :: proc(req: ^web.Request, res: ^web.Response) { disable(req, res, false) }

@(private)
disable :: proc(req: ^web.Request, res: ^web.Response, off: bool) {
	id, id_ok := member_of(req, res)
	if !id_ok { return }
	reason, reason_ok := web.prompt_reason(req, res)
	if !reason_ok { return }
	op := store.new_op(Disabling, ACT_BYTES)
	act_init(&op.act, &op.audit, store.op_allocator(op), reason, "accounts.disable" if off else "accounts.enable", "", id)
	op.user_id, op.disabled_at, op.act.revoke = id, accounts.now_ms() if off else 0, off
	op.done = proc(o: ^store.Op) { acted(o, &(^Disabling)(o).act, "That is the last admin: make another one first.") }
	queue(req, res, op, &op.act, proc(o: ^store.Op) -> bool { return accounts.set_disabled((^Disabling)(o)) })
}

// A member who lost their authenticator and their recovery codes has no way back but this: the
// factor and its codes go, and the next sign-in is the password's alone (M4-10).
@(private)
Unpairing :: struct {
	using set: m.Set_Totp,
	act:       Act,
}

@(private)
admin_totp_off :: proc(req: ^web.Request, res: ^web.Response) {
	id, id_ok := member_of(req, res)
	if !id_ok { return }
	u, err := accounts.user_by_id(id)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	if u.totp_secret == "" {
		web.respond_html(res, html.toast("error", "They have no two-step sign-in to turn off.", true), .Unprocessable_Content)
		return
	}
	reason, reason_ok := web.prompt_reason(req, res)
	if !reason_ok { return }
	op := store.new_op(Unpairing, ACT_BYTES)
	act_init(&op.act, &op.audit, store.op_allocator(op), reason, "accounts.totp_off", "", id)
	op.user_id = id
	op.done = proc(o: ^store.Op) { acted(o, &(^Unpairing)(o).act, "") }
	queue(req, res, op, &op.act, proc(o: ^store.Op) -> bool { return accounts.set_totp((^Unpairing)(o)) })
}

// ---- reset codes and invites ----------------------------------------------------------------

@(private)
Issuing :: struct {
	using set: m.Issue_Reset,
	act:       Act,
}

@(private)
admin_reset :: proc(req: ^web.Request, res: ^web.Response) {
	id, id_ok := member_of(req, res)
	if !id_ok { return }
	u, err := accounts.user_by_id(id)
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	reason, reason_ok := web.prompt_reason(req, res)
	if !reason_ok { return }
	code := accounts.new_code(accounts.RESET_GROUPS)
	b := strings.builder_make(context.temp_allocator)
	views.reset_issued(&b, u.username, code)
	show := strings.to_string(b)
	op := store.new_op(Issuing, ACT_BYTES + len(show) + 64)
	a := store.op_allocator(op)
	act_init(&op.act, &op.audit, a, reason, "accounts.reset_issued", "", id)
	op.act.show = strings.clone(show, a)
	now := accounts.now_ms()
	op.user_id, op.created_by, op.now, op.expires_at = id, i64(web.ctx().viewer.id), now, now + RESET_LIFE_MS
	op.code_hash = strings.clone(accounts.hash_code(code, accounts.RESET_GROUPS), a)
	op.done = proc(o: ^store.Op) { acted(o, &(^Issuing)(o).act, "") }
	queue(req, res, op, &op.act, proc(o: ^store.Op) -> bool { return accounts.issue_reset((^Issuing)(o)) })
}

@(private)
Inviting :: struct {
	using set: m.Create_Invite,
	act:       Act,
}

// POST /admin/accounts/invites: role, uses (1-50), days (1-30).
@(private)
admin_invite :: proc(req: ^web.Request, res: ^web.Response) {
	f := web.form(req)
	role: authz.Role
	found := false
	for label, r in authz.ROLE_LABELS {
		if label == f["role"] && r != .Guest { role, found = r, true }
	}
	uses, uok := strconv.parse_int(f["uses"], 10)
	days, dok := strconv.parse_int(f["days"], 10)
	if !found || !uok || !dok || uses < 1 || uses > MAX_INVITE_USES || days < 1 || days > MAX_INVITE_DAYS {
		web.respond_html(res, html.toast("error", "An invite is a role, 1 to 50 uses and 1 to 30 days.", true), .Unprocessable_Content)
		return
	}
	reason, reason_ok := web.prompt_reason(req, res)
	if !reason_ok { return }
	code := accounts.new_code(accounts.INVITE_GROUPS)
	b := strings.builder_make(context.temp_allocator)
	views.invite_made(&b, invite_link(req, code), authz.ROLE_LABELS[role], uses, days)
	show := strings.to_string(b)
	op := store.new_op(Inviting, ACT_BYTES + len(show) + 128)
	a := store.op_allocator(op)
	code_hash := strings.clone(accounts.hash_code(code, accounts.INVITE_GROUPS), a)
	// The hash's first 8 hex name the invite in its creation, its withdrawal and each use (M4-16).
	act_init(&op.act, &op.audit, a, reason, "accounts.invite_created", fmt.tprintf("invite=%s role=%s uses=%d days=%d", code_hash[:8], authz.ROLE_LABELS[role], uses, days), 0)
	op.act.show = strings.clone(show, a)
	now := accounts.now_ms()
	op.invite = {
		code_hash = code_hash,
		role = role, max_uses = uses, created_by = i64(web.ctx().viewer.id), created_at = now,
		expires_at = now + i64(days) * 86_400_000,
	}
	op.done = proc(o: ^store.Op) { acted(o, &(^Inviting)(o).act, "") }
	queue(req, res, op, &op.act, proc(o: ^store.Op) -> bool { return accounts.create_invite((^Inviting)(o)) })
}

// The link an invitee follows: this site, as the admin's request reached it (its port too).
@(private)
invite_link :: proc(req: ^web.Request, code: string) -> string {
	c := web.ctx()
	host, _ := web.header(req, "host")
	for ch in transmute([]byte)host {
		switch ch {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '-', ':', '[', ']':
		case: host = web.host_of(req) // nothing a link can't carry
		}
	}
	return fmt.tprintf("%s://%s/register?code=%s", "https" if c.https else "http", host, code)
}

@(private)
Uninviting :: struct {
	using set: m.Delete_Invite,
	act:       Act,
}

// POST /admin/accounts/invites/delete: invite (its hash, from the list).
@(private)
admin_uninvite :: proc(req: ^web.Request, res: ^web.Response) {
	h := web.form(req)["invite"]
	if len(h) != 64 {
		web.respond_html(res, html.toast("error", "No such invite.", true), .Unprocessable_Content)
		return
	}
	reason, reason_ok := web.prompt_reason(req, res)
	if !reason_ok { return }
	op := store.new_op(Uninviting, ACT_BYTES + len(h))
	a := store.op_allocator(op)
	act_init(&op.act, &op.audit, a, reason, "accounts.invite_deleted", fmt.tprintf("invite=%s", h[:8]), 0)
	op.code_hash = strings.clone(h, a)
	op.done = proc(o: ^store.Op) { acted(o, &(^Uninviting)(o).act, "") }
	queue(req, res, op, &op.act, proc(o: ^store.Op) -> bool { return accounts.delete_invite((^Uninviting)(o)) })
}
