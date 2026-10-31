package accounts_storetest

// ---- the accounts store contract (SQLite: accounts have no memory member, D18) ------------
//
// A user is found by name whatever its case, a second one of the same name is refused, a
// failed login counts and backs off, a sign-in opens the session (a step-up), clears the
// failures, closes the session it rotates and sweeps the dead ones, a session is touched and
// closed by its token's hash and only by its user, and the boot's admin is made only once.

import "base:runtime"
import "core:fmt"
import "core:nbio"
import "core:strings"
import "core:testing"
import "core:time"

import "../../../platform/authz"
import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import sql "../../../stores/sqlite/accounts"

@(private = "file")
answered: int

@(private = "file")
last_err: store.Error

@(private = "file")
settle :: proc(t: ^testing.T, want: int) {
	deadline := time.tick_now()
	for answered < want && time.tick_since(deadline) < 5 * time.Second { nbio.tick(10 * time.Millisecond) }
	testing.expectf(t, answered == want, "%d of %d writes answered", answered, want)
}

@(private = "file")
DONE :: proc(o: ^store.Op) {
	answered += 1
	last_err = o.err
	store.free_op(o)
}

@(private = "file")
create :: proc(t: ^testing.T, name: string, role: authz.Role) -> store.Error {
	op := store.new_op(m.Create_User, 3 * len(name) + 64)
	a := store.op_allocator(op)
	op.username = strings.clone(name, a)
	op.display = strings.clone(name, a)
	op.pw_hash = strings.clone("$argon2id$v=19$m=19456,t=2,p=1$x$y", a)
	op.role = role
	op.done = DONE
	before := answered
	testing.expect(t, sql.create_user(op))
	settle(t, before + 1)
	return last_err
}

@(test)
the_store_keeps_users_and_sessions :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("accounts", sql.MIGRATIONS[:])
	// Audit's table, for the entries accounts' changes write with themselves (M4-04).
	db.migrate("audit", {{1, "0001_audit.sql", #load("../../../stores/sqlite/audit/migrations/0001_audit.sql", string)}})

	// A member who registered before the admin existed holds the name: boot refuses it (M4-11).
	testing.expect_value(t, create(t, "taken", .User), store.Error.None)
	made, berr := sql.bootstrap_admin("Taken", "$argon2id$v=19$m=19456,t=2,p=1$x$y")
	testing.expect(t, berr == .Constraint && !made)
	made, berr = sql.bootstrap_admin("root", "$argon2id$v=19$m=19456,t=2,p=1$x$y")
	testing.expect(t, berr == .None && made)
	made, berr = sql.bootstrap_admin("root2", "$argon2id$v=19$m=19456,t=2,p=1$x$y")
	testing.expect(t, berr == .None && !made) // an enabled admin exists
	root, rerr := sql.user_by_name("root")
	testing.expect(t, rerr == .None && root.role == .Admin)

	testing.expect_value(t, create(t, "Alex", .Admin), store.Error.None)
	testing.expect_value(t, create(t, "alex", .User), store.Error.Constraint) // unique whatever the case
	testing.expect_value(t, create(t, "sam", .User), store.Error.None)

	u, err := sql.user_by_name("ALEX")
	testing.expect_value(t, err, store.Error.None)
	testing.expect(t, u.username == "Alex" && u.role == .Admin && u.failed_logins == 0)
	_, err = sql.user_by_name("nobody")
	testing.expect_value(t, err, store.Error.Not_Found)
	n, _ := sql.count_admins()
	testing.expect_value(t, n, 2) // root and Alex

	failed := store.new_op(m.Login_Failed, 0)
	failed.user_id, failed.backoff_until, failed.done = u.id, 5000, DONE
	testing.expect(t, sql.login_failed(failed))
	settle(t, answered + 1)
	u, _ = sql.user_by_id(u.id)
	testing.expect(t, u.failed_logins == 1 && u.backoff_until == 5000)

	OLD :: "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
	DEAD :: "1111111111111111111111111111111111111111111111111111111111111111"
	HASH :: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
	open_at(t, OLD, "", u.id, 500, 9000, 0)
	open_at(t, DEAD, "", u.id, 100, 9000, 0)
	open_at(t, HASH, OLD, u.id, 1000, 9000, 200) // rotates OLD; DEAD, last seen at 100, is swept
	s, serr := sql.session(HASH)
	testing.expect_value(t, serr, store.Error.None)
	testing.expect(t, s.user_id == u.id && s.created_at == 1000 && s.last_seen == 1000 && s.expires_at == 9000 && s.step_up_at == 1000)
	_, serr = sql.session(OLD)
	testing.expect_value(t, serr, store.Error.Not_Found)
	_, serr = sql.session(DEAD)
	testing.expect_value(t, serr, store.Error.Not_Found)
	all := make([dynamic]m.Session, context.temp_allocator)
	testing.expect_value(t, sql.sessions_of(u.id, &all), store.Error.None)
	testing.expect(t, len(all) == 1 && all[0].token_hash == HASH)
	u, _ = sql.user_by_id(u.id)
	testing.expect(t, u.failed_logins == 0 && u.backoff_until == 0) // a sign-in clears them

	touch := store.new_op(m.Touch_Session, len(HASH))
	touch.token_hash = strings.clone(HASH, store.op_allocator(touch))
	touch.now, touch.done = 2000, DONE
	testing.expect(t, sql.touch_session(touch))
	settle(t, answered + 1)
	s, _ = sql.session(HASH)
	testing.expect_value(t, s.last_seen, 2000)

	// TOTP on with its recovery codes; a step and a code each spent once, in the sign-in's own write.
	totp := store.new_op(m.Set_Totp, 64 + 64 * m.RECOVERY_CODES)
	ta := store.op_allocator(totp)
	totp.user_id, totp.secret, totp.enrol, totp.done = u.id, strings.clone("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", ta), true, DONE
	for &c, i in totp.codes { c = fmt.aprintf("c%d", i, allocator = ta) }
	testing.expect(t, sql.set_totp(totp))
	settle(t, answered + 1)
	testing.expect_value(t, last_err, store.Error.None)
	u, _ = sql.user_by_id(u.id)
	testing.expect(t, u.totp_secret == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" && u.totp_last_step == 0)
	left, _ := sql.recovery_left(u.id)
	testing.expect_value(t, left, m.RECOVERY_CODES)

	// An enrolment over a second factor in force changes nothing (M4-01).
	again := store.new_op(m.Set_Totp, 64)
	again.user_id, again.secret, again.enrol, again.done = u.id, strings.clone("JBSWY3DPEHPK3PXP", store.op_allocator(again)), true, DONE
	testing.expect(t, sql.set_totp(again))
	settle(t, answered + 1)
	testing.expect_value(t, last_err, store.Error.Constraint)
	u, _ = sql.user_by_id(u.id)
	testing.expect_value(t, u.totp_secret, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
	left, _ = sql.recovery_left(u.id)
	testing.expect_value(t, left, m.RECOVERY_CODES)

	S2 :: "2222222222222222222222222222222222222222222222222222222222222222"
	second :: proc(t: ^testing.T, hash: string, user, step: i64, code: string) -> store.Error {
		op := store.new_op(m.Open_Session, len(hash) + len(code))
		a := store.op_allocator(op)
		op.token_hash, op.recovery_hash = strings.clone(hash, a), strings.clone(code, a)
		op.user_id, op.now, op.expires_at, op.idle_before, op.totp_step, op.done = user, 3000, 9000, 0, step, DONE
		before := answered
		testing.expect(t, sql.open_session(op))
		settle(t, before + 1)
		return last_err
	}
	testing.expect_value(t, second(t, S2, u.id, 55, ""), store.Error.None)
	testing.expect_value(t, second(t, "3" + S2[1:], u.id, 55, ""), store.Error.Constraint) // the same step again
	testing.expect_value(t, second(t, "4" + S2[1:], u.id, 54, ""), store.Error.Constraint) // an older one
	testing.expect_value(t, second(t, "5" + S2[1:], u.id, 0, "c1"), store.Error.None)
	testing.expect_value(t, second(t, "6" + S2[1:], u.id, 0, "c1"), store.Error.Constraint) // a used code
	left, _ = sql.recovery_left(u.id)
	testing.expect_value(t, left, m.RECOVERY_CODES - 1)
	_, serr = sql.session("3" + S2[1:])
	testing.expect_value(t, serr, store.Error.Not_Found) // a refused second factor opened nothing

	up := store.new_op(m.Step_Up, len(S2))
	up.token_hash = strings.clone(S2, store.op_allocator(up))
	up.user_id, up.now, up.totp_step, up.done = u.id, 7000, 56, DONE
	testing.expect(t, sql.step_up(up))
	settle(t, answered + 1)
	testing.expect_value(t, last_err, store.Error.None)
	s, _ = sql.session(S2)
	testing.expect_value(t, s.step_up_at, 7000)

	sam, _ := sql.user_by_name("sam")
	close_as(t, HASH, sam.id) // another user's revoke closes nothing
	_, serr = sql.session(HASH)
	testing.expect_value(t, serr, store.Error.None)
	close_as(t, HASH, u.id)
	_, serr = sql.session(HASH)
	testing.expect_value(t, serr, store.Error.Not_Found)

	members(t)
}

// Registration, invites, roles, disabling, reset codes and display names (slice 6).
@(private = "file")
members :: proc(t: ^testing.T) {
	PHC :: "$argon2id$v=19$m=19456,t=2,p=1$x$y"
	reg :: proc(t: ^testing.T, name, invite, token: string, now: i64) -> (^m.Register, store.Error) {
		op := store.new_op(m.Register, 3 * len(name) + len(PHC) + len(invite) + len(token))
		a := store.op_allocator(op)
		op.username, op.display, op.pw_hash = strings.clone(name, a), strings.clone(name, a), strings.clone(PHC, a)
		op.invite_hash, op.token_hash, op.now, op.expires_at = strings.clone(invite, a), strings.clone(token, a), now, now + 1000
		op.done = proc(o: ^store.Op) { answered += 1; last_err = o.err } // kept: the test reads its result
		before := answered
		testing.expect(t, sql.register(op))
		settle(t, before + 1)
		return op, last_err
	}
	write :: proc(t: ^testing.T, op: ^store.Op, queued: bool) -> store.Error {
		before := answered
		testing.expect(t, queued)
		settle(t, before + 1)
		return last_err
	}

	open, err := reg(t, "Robin", "", "a1", 100)
	testing.expect(t, err == .None && open.role == .User && open.result > 0)
	s, serr := sql.session("a1")
	testing.expect(t, serr == .None && s.user_id == open.result) // signed in by the same write
	_, err = reg(t, "robin", "", "a2", 100)
	testing.expect_value(t, err, store.Error.Constraint) // the name is taken, any case

	inv := store.new_op(m.Create_Invite, 8)
	inv.invite = {code_hash = strings.clone("inv1", store.op_allocator(inv)), role = .Mod, max_uses = 1, created_by = 1, created_at = 100, expires_at = 5000}
	inv.done = DONE
	testing.expect_value(t, write(t, inv, sql.create_invite(inv)), store.Error.None)
	live := make([dynamic]m.Invite, context.temp_allocator)
	sql.invites(200, &live)
	testing.expect(t, len(live) == 1 && live[0].role == .Mod)
	_, ierr := sql.invite("inv1", 6000)
	testing.expect_value(t, ierr, store.Error.Not_Found) // expired by then
	// A name someone holds fails the whole op: the invite's one use isn't spent by it (M4-06).
	_, err = reg(t, "ROBIN", "inv1", "a5", 200)
	testing.expect_value(t, err, store.Error.Constraint)
	mod, merr := reg(t, "Kim", "inv1", "a3", 200)
	testing.expect(t, merr == .None && mod.role == .Mod)
	_, err = reg(t, "Lee", "inv1", "a4", 200)
	testing.expect_value(t, err, store.Error.Not_Found) // its one use is spent
	_, err = sql.user_by_name("Lee")
	testing.expect_value(t, err, store.Error.Not_Found) // and nothing was written

	all := make([dynamic]m.User, context.temp_allocator)
	testing.expect_value(t, sql.users(&all), store.Error.None)
	testing.expect(t, len(all) >= 4)

	// root and Alex are the admins: Alex can go, then root is the last and can't.
	alex, _ := sql.user_by_name("alex")
	root, _ := sql.user_by_name("root")
	demote := store.new_op(m.Set_Role, 0)
	demote.user_id, demote.role, demote.done = alex.id, .User, DONE
	testing.expect_value(t, write(t, demote, sql.set_role(demote)), store.Error.None)
	last := store.new_op(m.Set_Role, 0)
	last.user_id, last.role, last.done = root.id, .Mod, DONE
	testing.expect_value(t, write(t, last, sql.set_role(last)), store.Error.Constraint)

	// A change writes its entry in its own unit (M4-04), through the writer its identity hands over
	// (audit's append_in in a build; a stand-in on audit's table here): one for the change that
	// went in, none for the refused one.
	sql.set_audit_writer(proc(actor_id: i64, actor_name, client, action, target_kind: string, target_id: i64, reason, meta: string) -> store.Error {
		st := db.writer_stmt("INSERT INTO audit_log(at, actor_id, actor_name, action, target_kind, target_id, reason, client_id, meta) VALUES(0, ?, ?, ?, ?, ?, ?, ?, ?)")
		defer db.reset(st)
		db.bind_id(st, 1, actor_id)
		db.bind_text(st, 2, actor_name)
		db.bind_text(st, 3, action)
		db.bind_text(st, 4, target_kind)
		db.bind_id(st, 5, target_id)
		db.bind_text(st, 6, reason)
		db.bind_text(st, 7, client)
		db.bind_text(st, 8, meta)
		return db.step_done(st)
	})
	defer sql.set_audit_writer(nil)
	entries :: proc(action: string) -> int {
		q := db.read("SELECT count(*) FROM audit_log WHERE action = ?")
		defer db.reset(q)
		db.bind_text(q, 1, action)
		err: store.Error
		return db.column_int(q, 0) if db.next_row(q, &err) else -1
	}
	back := store.new_op(m.Set_Role, 0)
	back.user_id, back.role, back.done = alex.id, .Mod, DONE
	back.audit = {actor_id = root.id, actor_name = "root", action = "accounts.role", target_kind = "user", target_id = alex.id, meta = "role=Moderator"}
	testing.expect_value(t, write(t, back, sql.set_role(back)), store.Error.None)
	refused := store.new_op(m.Set_Role, 0)
	refused.user_id, refused.role, refused.done = root.id, .Mod, DONE
	refused.audit = {actor_id = root.id, actor_name = "root", action = "accounts.role_refused", target_kind = "user", target_id = root.id}
	testing.expect_value(t, write(t, refused, sql.set_role(refused)), store.Error.Constraint)
	testing.expect_value(t, entries("accounts.role"), 1)
	testing.expect_value(t, entries("accounts.role_refused"), 0)
	off := store.new_op(m.Set_Disabled, 0)
	off.user_id, off.disabled_at, off.done = root.id, 999, DONE
	testing.expect_value(t, write(t, off, sql.set_disabled(off)), store.Error.Constraint)
	robin_off := store.new_op(m.Set_Disabled, 0)
	robin_off.user_id, robin_off.disabled_at, robin_off.done = open.result, 999, DONE
	testing.expect_value(t, write(t, robin_off, sql.set_disabled(robin_off)), store.Error.None)
	_, serr = sql.session("a1")
	testing.expect_value(t, serr, store.Error.Not_Found) // a disabled member's sessions end
	n, _ := sql.count_admins()
	testing.expect_value(t, n, 1)

	issue := store.new_op(m.Issue_Reset, 8)
	issue.code_hash = strings.clone("r1", store.op_allocator(issue))
	issue.user_id, issue.created_by, issue.now, issue.expires_at, issue.done = mod.result, root.id, 300, 9000, DONE
	testing.expect_value(t, write(t, issue, sql.issue_reset(issue)), store.Error.None)
	redeem :: proc(t: ^testing.T, user: i64, code: string) -> store.Error {
		op := store.new_op(m.Redeem_Reset, len(code) + 16)
		a := store.op_allocator(op)
		op.code_hash, op.pw_hash, op.user_id, op.now, op.done = strings.clone(code, a), strings.clone("$new", a), user, 400, DONE
		before := answered
		testing.expect(t, sql.redeem_reset(op))
		settle(t, before + 1)
		return last_err
	}
	code_live :: proc(code: string, user, now: i64) -> bool { ok, _ := sql.reset_live(code, user, now); return ok }
	testing.expect(t, code_live("r1", mod.result, 400))
	testing.expect(t, !code_live("r1", open.result, 400)) // another member's code
	testing.expect(t, !code_live("r1", 0, 400))           // a name with no account
	testing.expect(t, !code_live("r1", mod.result, 9000)) // expired
	testing.expect_value(t, redeem(t, open.result, "r1"), store.Error.Constraint) // another member's code
	testing.expect_value(t, redeem(t, mod.result, "r1"), store.Error.None)
	testing.expect_value(t, redeem(t, mod.result, "r1"), store.Error.Constraint) // once
	testing.expect(t, !code_live("r1", mod.result, 400)) // spent
	kim, _ := sql.user_by_id(mod.result)
	testing.expect_value(t, kim.pw_hash, "$new")
	_, serr = sql.session("a3")
	testing.expect_value(t, serr, store.Error.Not_Found) // a reset ends every session

	disp := store.new_op(m.Set_Display, 16)
	disp.display = strings.clone("Kim L.", store.op_allocator(disp))
	disp.user_id, disp.done = mod.result, DONE
	testing.expect_value(t, write(t, disp, sql.set_display(disp)), store.Error.None)
	kim, _ = sql.user_by_id(mod.result)
	testing.expect_value(t, kim.display, "Kim L.")

	none, _ := sql.theme_of(mod.result)
	testing.expect_value(t, none, m.Theme{})
	for scheme in ([]string{"aqua", "brass"}) { // the second replaces the first
		th := store.new_op(m.Set_Theme, 16)
		th.theme = {strings.clone("skeuo", store.op_allocator(th)), strings.clone(scheme, store.op_allocator(th))}
		th.user_id, th.done = mod.result, DONE
		testing.expect_value(t, write(t, th, sql.set_theme(th)), store.Error.None)
	}
	kept, _ := sql.theme_of(mod.result)
	testing.expect_value(t, kept, m.Theme{"skeuo", "brass"})

	drop := store.new_op(m.Delete_Invite, 8)
	drop.code_hash = strings.clone("inv1", store.op_allocator(drop))
	drop.done = DONE
	testing.expect_value(t, write(t, drop, sql.delete_invite(drop)), store.Error.None)

	store.free_op(open)
	store.free_op(mod)
}

@(private = "file")
open_at :: proc(t: ^testing.T, hash, old: string, user: i64, now, expires, idle_before: i64) {
	op := store.new_op(m.Open_Session, len(hash) + len(old))
	a := store.op_allocator(op)
	op.token_hash, op.old_hash = strings.clone(hash, a), strings.clone(old, a)
	op.user_id, op.now, op.expires_at, op.idle_before, op.done = user, now, expires, idle_before, DONE
	before := answered
	testing.expect(t, sql.open_session(op))
	settle(t, before + 1)
	testing.expect_value(t, last_err, store.Error.None)
}

@(private = "file")
close_as :: proc(t: ^testing.T, hash: string, user: i64) {
	op := store.new_op(m.Close_Session, len(hash))
	op.token_hash = strings.clone(hash, store.op_allocator(op))
	op.user_id, op.done = user, DONE
	before := answered
	testing.expect(t, sql.close_session(op))
	settle(t, before + 1)
}
