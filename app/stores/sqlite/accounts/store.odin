package accounts_store_sqlite

// ---- accounts in SQLite -------------------------------------------------------------------
//
// Reads on the loop's reader, their strings cloned into the request arena; every write is an
// op through the writer task but the boot's first admin. A sign-in's session row, the session
// it replaces, the user's dead sessions and the clearing of their failures commit together.

import "core:fmt"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/accounts/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_accounts.sql", #load("migrations/0001_accounts.sql", string)},
	{2, "0002_totp.sql", #load("migrations/0002_totp.sql", string)},
	{3, "0003_reset_codes.sql", #load("migrations/0003_reset_codes.sql", string)},
}

@(private) USER_COLS :: "id, username, display, role, pw_hash, disabled_at, failed_logins, backoff_until, totp_secret, totp_last_step"
@(private) SQL_BY_NAME :: "SELECT " + USER_COLS + " FROM users WHERE username = ?"
@(private) SQL_BY_ID :: "SELECT " + USER_COLS + " FROM users WHERE id = ?"
@(private) SESSION_COLS :: "token_hash, user_id, created_at, last_seen, expires_at, step_up_at"
@(private) SQL_SESSION :: "SELECT " + SESSION_COLS + " FROM sessions WHERE token_hash = ?"
@(private) SQL_SESSIONS_OF :: "SELECT " + SESSION_COLS + " FROM sessions WHERE user_id = ? ORDER BY last_seen DESC LIMIT 100"
@(private) SQL_ADMINS :: "SELECT count(*) FROM users WHERE role = 3 AND disabled_at = 0"
@(private) SQL_CREATE :: "INSERT INTO users(username, display, pw_hash, role, created_at) VALUES(?, ?, ?, ?, ?)"
@(private) SQL_FAILED :: "UPDATE users SET failed_logins = failed_logins + 1, backoff_until = ? WHERE id = ?"
@(private) SQL_CLEAR :: "UPDATE users SET failed_logins = 0, backoff_until = 0 WHERE id = ?"
@(private) SQL_OPEN :: "INSERT INTO sessions(token_hash, user_id, created_at, last_seen, expires_at, step_up_at) VALUES(?, ?, ?, ?, ?, ?)"
@(private) SQL_RECOVERY_LEFT :: "SELECT count(*) FROM accounts_recovery_codes WHERE user_id = ? AND used_at = 0"
@(private) SQL_SPEND_STEP :: "UPDATE users SET totp_last_step = ?1 WHERE id = ?2 AND totp_last_step < ?1"
@(private) SQL_SPEND_CODE :: "UPDATE accounts_recovery_codes SET used_at = ? WHERE user_id = ? AND code_hash = ? AND used_at = 0"
@(private) SQL_TOTP_SECRETS :: "SELECT id, totp_secret FROM users WHERE totp_secret <> ''"
@(private) SQL_RESEAL_TOTP :: "UPDATE users SET totp_secret = ?1 WHERE id = ?2 AND totp_secret = ?3"
@(private) SQL_SET_TOTP :: "UPDATE users SET totp_secret = ?, totp_last_step = ? WHERE id = ?"
@(private) SQL_ENROL_TOTP :: "UPDATE users SET totp_secret = ?, totp_last_step = ? WHERE id = ? AND totp_secret = ''"
@(private) SQL_KEEP_TOTP :: "UPDATE users SET totp_secret = ?, totp_last_step = ? WHERE id = ? AND totp_secret = ?"
@(private) SQL_DROP_CODES :: "DELETE FROM accounts_recovery_codes WHERE user_id = ?"
@(private) SQL_ADD_CODE :: "INSERT INTO accounts_recovery_codes(user_id, code_hash) VALUES(?, ?)"
@(private) SQL_STEP_UP :: "UPDATE sessions SET step_up_at = ? WHERE token_hash = ? AND user_id = ?"
@(private) SQL_USERS :: "SELECT " + USER_COLS + " FROM users ORDER BY id LIMIT 500"
@(private) INVITE_COLS :: "code_hash, role, max_uses, uses, created_by, created_at, expires_at"
@(private) SQL_INVITES :: "SELECT " + INVITE_COLS + " FROM accounts_invites WHERE uses < max_uses AND expires_at > ? ORDER BY created_at DESC LIMIT 200"
@(private) SQL_INVITE :: "SELECT " + INVITE_COLS + " FROM accounts_invites WHERE code_hash = ? AND uses < max_uses AND expires_at > ?"
@(private) SQL_SPEND_INVITE :: "UPDATE accounts_invites SET uses = uses + 1 WHERE code_hash = ? AND uses < max_uses AND expires_at > ? RETURNING role"
@(private) SQL_SAVE :: "SAVEPOINT op"
@(private) SQL_UNDO :: "ROLLBACK TO op"
@(private) SQL_RELEASE :: "RELEASE op"
@(private) SQL_REGISTER :: "INSERT INTO users(username, display, pw_hash, role, created_at) VALUES(?, ?, ?, ?, ?)"
@(private) SQL_ROLE_OF :: "SELECT role, disabled_at FROM users WHERE id = ?"
@(private) SQL_OTHER_ADMINS :: "SELECT count(*) FROM users WHERE role = 3 AND disabled_at = 0 AND id != ?"
@(private) SQL_SET_ROLE :: "UPDATE users SET role = ? WHERE id = ?"
@(private) SQL_SET_DISABLED :: "UPDATE users SET disabled_at = ? WHERE id = ?"
@(private) SQL_END_SESSIONS :: "DELETE FROM sessions WHERE user_id = ?"
@(private) SQL_ADD_INVITE :: "INSERT INTO accounts_invites(" + INVITE_COLS + ") VALUES(?, ?, ?, 0, ?, ?, ?)"
@(private) SQL_DROP_INVITE :: "DELETE FROM accounts_invites WHERE code_hash = ?"
@(private) SQL_DROP_RESETS :: "DELETE FROM accounts_reset_codes WHERE user_id = ? AND used_at = 0"
@(private) SQL_ADD_RESET :: "INSERT INTO accounts_reset_codes(code_hash, user_id, created_by, created_at, expires_at) VALUES(?, ?, ?, ?, ?)"
@(private) SQL_RESET_LIVE :: "SELECT 1 FROM accounts_reset_codes WHERE code_hash = ?1 AND user_id = ?2 AND used_at = 0 AND expires_at > ?3"
@(private) SQL_SPEND_RESET :: "UPDATE accounts_reset_codes SET used_at = ?1 WHERE code_hash = ?2 AND user_id = ?3 AND used_at = 0 AND expires_at > ?1"
@(private) SQL_SET_PASSWORD :: "UPDATE users SET pw_hash = ?, failed_logins = 0, backoff_until = 0 WHERE id = ?"
@(private) SQL_SET_DISPLAY :: "UPDATE users SET display = ? WHERE id = ?"
@(private) SQL_SWEEP :: "DELETE FROM sessions WHERE user_id = ? AND (expires_at <= ? OR last_seen < ?)"
@(private) SQL_TOUCH :: "UPDATE sessions SET last_seen = ? WHERE token_hash = ?"
@(private) SQL_CLOSE :: "DELETE FROM sessions WHERE token_hash = ? AND user_id = ?"
@(private) SQL_CLOSE_ANY :: "DELETE FROM sessions WHERE token_hash = ?" // the cookie a sign-in replaces, whoever's
@(private) SQL_THEME :: "SELECT key, value FROM accounts_prefs WHERE user_id = ? AND key IN ('style', 'scheme')"
@(private) SQL_SET_PREF :: "INSERT INTO accounts_prefs(user_id, key, value) VALUES(?, ?, ?) ON CONFLICT(user_id, key) DO UPDATE SET value = excluded.value"

user_by_name :: proc(username: string) -> (m.User, m.Error) {
	q := db.read(SQL_BY_NAME)
	defer db.reset(q)
	db.bind_text(q, 1, username)
	return one_user(q)
}

user_by_id :: proc(id: i64) -> (m.User, m.Error) {
	q := db.read(SQL_BY_ID)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	return one_user(q)
}

@(private)
one_user :: proc(q: db.Stmt) -> (u: m.User, err: m.Error) {
	return next_user(q)
}

// The next row as a user; .Not_Found past the last.
@(private)
next_user :: proc(q: db.Stmt) -> (u: m.User, err: m.Error) {
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	role, ok := store.enum_from_int(m.Role, db.column_int(q, 3))
	if !ok { return {}, .Failed }
	return m.User {
		id = db.column_id(q, 0),
		username = db.clone_col(q, 1),
		display = db.clone_col(q, 2),
		role = role,
		pw_hash = db.clone_col(q, 4),
		disabled_at = db.column_id(q, 5),
		failed_logins = db.column_int(q, 6),
		backoff_until = db.column_id(q, 7),
		totp_secret = db.clone_col(q, 8),
		totp_last_step = db.column_id(q, 9),
	}, .None
}

session :: proc(token_hash: string) -> (s: m.Session, err: m.Error) {
	q := db.read(SQL_SESSION)
	defer db.reset(q)
	db.bind_text(q, 1, token_hash)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return one_session(q), .None
}

sessions_of :: proc(user_id: i64, into: ^[dynamic]m.Session) -> (err: m.Error) {
	q := db.read(SQL_SESSIONS_OF)
	defer db.reset(q)
	db.bind_id(q, 1, user_id)
	for db.next_row(q, &err) { append(into, one_session(q)) }
	return
}

@(private)
one_session :: proc(q: db.Stmt) -> m.Session {
	return m.Session {
		token_hash = db.clone_col(q, 0),
		user_id = db.column_id(q, 1),
		created_at = db.column_id(q, 2),
		last_seen = db.column_id(q, 3),
		expires_at = db.column_id(q, 4),
		step_up_at = db.column_id(q, 5),
	}
}

count_admins :: proc() -> (n: int, err: m.Error) {
	q := db.read(SQL_ADMINS)
	defer db.reset(q)
	if db.next_row(q, &err) { n = db.column_int(q, 0) }
	return
}

recovery_left :: proc(user_id: i64) -> (n: int, err: m.Error) {
	q := db.read(SQL_RECOVERY_LEFT)
	defer db.reset(q)
	db.bind_id(q, 1, user_id)
	if db.next_row(q, &err) { n = db.column_int(q, 0) }
	return
}

theme_of :: proc(user_id: i64) -> (t: m.Theme, err: m.Error) {
	q := db.read(SQL_THEME)
	defer db.reset(q)
	db.bind_id(q, 1, user_id)
	for db.next_row(q, &err) {
		switch db.clone_col(q, 0) {
		case "style": t.style = db.clone_col(q, 1)
		case "scheme": t.scheme = db.clone_col(q, 1)
		}
	}
	return
}

users :: proc(into: ^[dynamic]m.User) -> (err: m.Error) {
	q := db.read(SQL_USERS)
	defer db.reset(q)
	for {
		u, e := next_user(q)
		if e == .Not_Found { break }
		if e != .None { return e }
		append(into, u)
	}
	return .None
}

invites :: proc(now: i64, into: ^[dynamic]m.Invite) -> (err: m.Error) {
	q := db.read(SQL_INVITES)
	defer db.reset(q)
	db.bind_id(q, 1, now)
	for db.next_row(q, &err) {
		inv, ok := one_invite(q)
		if ok { append(into, inv) }
	}
	return
}

invite :: proc(code_hash: string, now: i64) -> (inv: m.Invite, err: m.Error) {
	q := db.read(SQL_INVITE)
	defer db.reset(q)
	db.bind_text(q, 1, code_hash)
	db.bind_id(q, 2, now)
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	ok: bool
	if inv, ok = one_invite(q); !ok { return {}, .Failed }
	return
}

@(private)
one_invite :: proc(q: db.Stmt) -> (inv: m.Invite, ok: bool) {
	role: m.Role
	if role, ok = store.enum_from_int(m.Role, db.column_int(q, 1)); !ok { return }
	return m.Invite {
		code_hash = db.clone_col(q, 0),
		role = role,
		max_uses = db.column_int(q, 2),
		uses = db.column_int(q, 3),
		created_by = db.column_id(q, 4),
		created_at = db.column_id(q, 5),
		expires_at = db.column_id(q, 6),
	}, true
}

// write_now takes no data, so the boot's one write reads it from here.
@(private = "file")
boot: struct {
	username, pw_hash: string,
	created:           bool,
	err:               m.Error,
}

totp_secrets :: proc(into: ^[dynamic]m.Totp_Row) -> (err: m.Error) {
	q := db.read(SQL_TOTP_SECRETS)
	defer db.reset(q)
	for db.next_row(q, &err) { append(into, m.Totp_Row{user_id = db.column_id(q, 0), old = db.clone_col(q, 1)}) }
	return
}

@(private) SQL_SECURE_ON :: "PRAGMA secure_delete = ON"
@(private) SQL_SECURE_OFF :: "PRAGMA secure_delete = OFF"

@(private = "file")
pragma :: proc(sql: string) {
	st := db.writer_stmt(sql)
	e: m.Error
	_ = db.next_row(st, &e)
	db.reset(st)
}

@(private) resealing: struct {
	rows: []m.Totp_Row,
	err:  m.Error,
}

reseal_totps :: proc(rows: []m.Totp_Row) -> m.Error {
	resealing.rows, resealing.err = rows, .None
	ok := db.write_now(proc() -> bool {
		// The old text's bytes are zeroed where it stood, not left in the page beside the new (M4-12).
		pragma(SQL_SECURE_ON)
		defer pragma(SQL_SECURE_OFF)
		for r in resealing.rows {
			if r.new == "" { continue }
			st := db.writer_stmt(SQL_RESEAL_TOTP)
			db.bind_text(st, 1, r.new)
			db.bind_id(st, 2, r.user_id)
			db.bind_text(st, 3, r.old)
			resealing.err = db.step_done(st)
			db.reset(st)
			if resealing.err != .None { return false }
		}
		return true
	})
	if !ok { return resealing.err if resealing.err != .None else .Failed }
	// And no frame of the WAL keeps the plaintext either.
	_ = db.checkpoint_truncate()
	return .None
}

bootstrap_admin :: proc(username, pw_hash: string) -> (created: bool, err: m.Error) {
	boot.username, boot.pw_hash, boot.created, boot.err = username, pw_hash, false, .None
	ok := db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_ADMINS)
		e: m.Error
		n := db.column_int(q, 0) if db.next_row(q, &e) else -1
		db.reset(q)
		if n != 0 { return n > 0 }
		st := db.writer_stmt(SQL_CREATE)
		defer db.reset(st)
		db.bind_text(st, 1, boot.username)
		db.bind_text(st, 2, boot.username)
		db.bind_text(st, 3, boot.pw_hash)
		db.bind_int(st, 4, int(m.Role.Admin))
		db.bind_id(st, 5, now_ms())
		boot.err = db.step_done(st)
		boot.created = boot.err == .None
		return boot.created
	})
	if ok { return boot.created, .None }
	// .Constraint: the name is someone else's, a member who registered before the admin existed.
	return false, boot.err if boot.err != .None else .Failed
}

create_user :: proc(op: ^m.Create_User) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Create_User)(o)
		st := db.writer_stmt(SQL_CREATE)
		defer db.reset(st)
		db.bind_text(st, 1, op.username)
		db.bind_text(st, 2, op.display)
		db.bind_text(st, 3, op.pw_hash)
		db.bind_int(st, 4, int(op.role))
		db.bind_id(st, 5, now_ms())
		if o.err = db.step_done(st); o.err == .None { op.result = db.last_insert_id() }
	}
	return db.write(op)
}

login_failed :: proc(op: ^m.Login_Failed) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Login_Failed)(o)
		st := db.writer_stmt(SQL_FAILED)
		defer db.reset(st)
		db.bind_id(st, 1, op.backoff_until)
		db.bind_id(st, 2, op.user_id)
		o.err = db.step_done(st)
	}
	return db.write(op)
}

open_session :: proc(op: ^m.Open_Session) -> bool {
	op.run = proc(o: ^store.Op) { unit(o, open_session_run) }
	return db.write(op)
}

@(private = "file")
open_session_run :: proc(o: ^store.Op) {
	{
		op := (^m.Open_Session)(o)
		if o.err = spend(op.user_id, op.totp_step, op.recovery_hash, op.now); o.err != .None { return }
		sw := db.writer_stmt(SQL_SWEEP)
		db.bind_id(sw, 1, op.user_id)
		db.bind_id(sw, 2, op.now)
		db.bind_id(sw, 3, op.idle_before)
		o.err = db.step_done(sw)
		db.reset(sw)
		if o.err != .None { return }
		if op.old_hash != "" {
			old := db.writer_stmt(SQL_CLOSE_ANY)
			db.bind_text(old, 1, op.old_hash)
			o.err = db.step_done(old)
			db.reset(old)
			if o.err != .None { return }
		}
		st := db.writer_stmt(SQL_OPEN)
		db.bind_text(st, 1, op.token_hash)
		db.bind_id(st, 2, op.user_id)
		db.bind_id(st, 3, op.now)
		db.bind_id(st, 4, op.now)
		db.bind_id(st, 5, op.expires_at)
		db.bind_id(st, 6, op.now)
		o.err = db.step_done(st)
		db.reset(st)
		if o.err != .None { return }
		cl := db.writer_stmt(SQL_CLEAR)
		db.bind_id(cl, 1, op.user_id)
		o.err = db.step_done(cl)
		db.reset(cl)
		if o.err == .None { o.err = note(op.audit, 0) }
	}
}

touch_session :: proc(op: ^m.Touch_Session) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Touch_Session)(o)
		st := db.writer_stmt(SQL_TOUCH)
		defer db.reset(st)
		db.bind_id(st, 1, op.now)
		db.bind_text(st, 2, op.token_hash)
		o.err = db.step_done(st)
	}
	return db.write(op)
}

close_session :: proc(op: ^m.Close_Session) -> bool {
	op.run = proc(o: ^store.Op) {
		unit(o, proc(o: ^store.Op) {
			op := (^m.Close_Session)(o)
			st := db.writer_stmt(SQL_CLOSE)
			db.bind_text(st, 1, op.token_hash)
			db.bind_id(st, 2, op.user_id)
			o.err = db.step_done(st)
			op.ended = o.err == .None && db.changes() > 0
			db.reset(st)
			if op.ended { o.err = note(op.audit, 0) } // a foreign hash ended nothing, and says nothing
		})
	}
	return db.write(op)
}

set_totp :: proc(op: ^m.Set_Totp) -> bool {
	op.run = proc(o: ^store.Op) { unit(o, set_totp_run) }
	return db.write(op)
}

@(private = "file")
set_totp_run :: proc(o: ^store.Op) {
	op := (^m.Set_Totp)(o)
	conditional := op.enrol || op.was != ""
	st := db.writer_stmt(SQL_ENROL_TOTP if op.enrol else SQL_KEEP_TOTP if op.was != "" else SQL_SET_TOTP)
	db.bind_text(st, 1, op.secret)
	db.bind_id(st, 2, op.last_step)
	db.bind_id(st, 3, op.user_id)
	if op.was != "" && !op.enrol { db.bind_text(st, 4, op.was) }
	o.err = db.step_done(st)
	db.reset(st)
	if o.err != .None { return }
	// A second factor already set is replaced only by turning it off first, behind a step-up; new
	// codes go only with the factor they were asked for.
	if conditional && db.changes() == 0 {
		o.err = .Constraint
		return
	}
	dr := db.writer_stmt(SQL_DROP_CODES)
	db.bind_id(dr, 1, op.user_id)
	o.err = db.step_done(dr)
	db.reset(dr)
	for code in op.codes {
		if o.err != .None || code == "" { continue }
		add := db.writer_stmt(SQL_ADD_CODE)
		db.bind_id(add, 1, op.user_id)
		db.bind_text(add, 2, code)
		o.err = db.step_done(add)
		db.reset(add)
	}
	if o.err == .None { o.err = note(op.audit, 0) }
}

step_up :: proc(op: ^m.Step_Up) -> bool {
	op.run = proc(o: ^store.Op) {
		unit(o, proc(o: ^store.Op) {
			op := (^m.Step_Up)(o)
			if o.err = spend(op.user_id, op.totp_step, "", op.now); o.err != .None { return }
			st := db.writer_stmt(SQL_STEP_UP)
			db.bind_id(st, 1, op.now)
			db.bind_text(st, 2, op.token_hash)
			db.bind_id(st, 3, op.user_id)
			o.err = db.step_done(st)
			if o.err == .None && db.changes() == 0 { o.err = .Not_Found }
			db.reset(st)
			if o.err == .None { o.err = note(op.audit, 0) }
		})
	}
	return db.write(op)
}

// An op of several statements fails as one (M4-06): SQLite undoes only the failing statement, and
// the batch's transaction commits the rest, so a register that lost its name kept its spent invite.
@(private = "file")
unit :: proc(o: ^store.Op, run: proc(o: ^store.Op)) {
	exec(SQL_SAVE)
	run(o)
	if o.err != .None { exec(SQL_UNDO) }
	exec(SQL_RELEASE)
}

@(private) audit_writer: m.Audit_Writer

set_audit_writer :: proc(w: m.Audit_Writer) { audit_writer = w }
has_audit_writer :: proc() -> bool { return audit_writer != nil }

// The op's audit entry, as one more statement of its unit: a failure here undoes the change.
@(private = "file")
note :: proc(a: m.Audit, result: i64) -> m.Error {
	if a.action == "" || audit_writer == nil { return .None }
	actor, target := a.actor_id, a.target_id
	if a.of_result { actor, target = result, result }
	return audit_writer(actor, a.actor_name, a.client, a.action, a.target_kind, target, a.reason, a.meta)
}

@(private = "file")
exec :: proc(sql: string) {
	st := db.writer_stmt(sql)
	_ = db.step_done(st)
	db.reset(st)
}

register :: proc(op: ^m.Register) -> bool {
	op.run = proc(o: ^store.Op) { unit(o, register_run) }
	return db.write(op)
}

@(private = "file")
register_run :: proc(o: ^store.Op) {
	op := (^m.Register)(o)
	op.role = .User
	if op.invite_hash != "" {
		sp := db.writer_stmt(SQL_SPEND_INVITE)
		db.bind_text(sp, 1, op.invite_hash)
		db.bind_id(sp, 2, op.now)
		found := db.next_row(sp, &o.err)
		if found {
			role, ok := store.enum_from_int(m.Role, db.column_int(sp, 0))
			if ok { op.role = role } else { o.err = .Failed }
		}
		db.reset(sp)
		if o.err != .None { return }
		if !found {
			o.err = .Not_Found
			return
		}
	}
	st := db.writer_stmt(SQL_REGISTER)
	db.bind_text(st, 1, op.username)
	db.bind_text(st, 2, op.display)
	db.bind_text(st, 3, op.pw_hash)
	db.bind_int(st, 4, int(op.role))
	db.bind_id(st, 5, op.now)
	o.err = db.step_done(st)
	db.reset(st)
	if o.err != .None { return }
	op.result = db.last_insert_id()
	se := db.writer_stmt(SQL_OPEN)
	defer db.reset(se)
	db.bind_text(se, 1, op.token_hash)
	db.bind_id(se, 2, op.result)
	db.bind_id(se, 3, op.now)
	db.bind_id(se, 4, op.now)
	db.bind_id(se, 5, op.expires_at)
	db.bind_id(se, 6, op.now)
	o.err = db.step_done(se)
	if o.err != .None { return }
	// The role is the invite's, known only here.
	if op.audit.action != "" {
		meta: [48]byte
		op.audit.meta = fmt.bprintf(meta[:], "role=%s invite=%s", m.role_label(op.role), op.invite_hash[:8] if len(op.invite_hash) >= 8 else "none")
		o.err = note(op.audit, op.result)
	}
}

set_role :: proc(op: ^m.Set_Role) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Set_Role)(o)
		if op.role != .Admin { if o.err = keep_an_admin(op.user_id); o.err != .None { return } }
		unit(o, proc(o: ^store.Op) {
			op := (^m.Set_Role)(o)
			o.err = by_id(SQL_SET_ROLE, i64(op.role), op.user_id)
			if o.err == .None { o.err = end_sessions(op.user_id) }
			if o.err == .None { o.err = note(op.audit, 0) }
		})
	}
	return db.write(op)
}

set_disabled :: proc(op: ^m.Set_Disabled) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Set_Disabled)(o)
		if op.disabled_at != 0 { if o.err = keep_an_admin(op.user_id); o.err != .None { return } }
		unit(o, proc(o: ^store.Op) {
			op := (^m.Set_Disabled)(o)
			o.err = by_id(SQL_SET_DISABLED, op.disabled_at, op.user_id)
			if o.err == .None { o.err = end_sessions(op.user_id) }
			if o.err == .None { o.err = note(op.audit, 0) }
		})
	}
	return db.write(op)
}

// .Constraint when the user is the last enabled admin; .Not_Found when there is no such user.
@(private)
keep_an_admin :: proc(user_id: i64) -> (err: m.Error) {
	q := db.writer_stmt(SQL_ROLE_OF)
	db.bind_id(q, 1, user_id)
	if !db.next_row(q, &err) {
		db.reset(q)
		return err if err != .None else .Not_Found
	}
	admin := db.column_int(q, 0) == int(m.Role.Admin) && db.column_id(q, 1) == 0
	db.reset(q)
	if !admin { return .None }
	c := db.writer_stmt(SQL_OTHER_ADMINS)
	defer db.reset(c)
	db.bind_id(c, 1, user_id)
	if db.next_row(c, &err) && db.column_int(c, 0) == 0 { return .Constraint }
	return
}

// An UPDATE … SET x = ?1 WHERE id = ?2 that must find its row.
@(private)
by_id :: proc(sql: string, value, id: i64) -> m.Error {
	st := db.writer_stmt(sql)
	defer db.reset(st)
	db.bind_id(st, 1, value)
	db.bind_id(st, 2, id)
	err := db.step_done(st)
	if err == .None && db.changes() == 0 { return .Not_Found }
	return err
}

@(private)
end_sessions :: proc(user_id: i64) -> m.Error {
	st := db.writer_stmt(SQL_END_SESSIONS)
	defer db.reset(st)
	db.bind_id(st, 1, user_id)
	return db.step_done(st)
}

create_invite :: proc(op: ^m.Create_Invite) -> bool {
	op.run = proc(o: ^store.Op) {
		unit(o, proc(o: ^store.Op) {
			op := (^m.Create_Invite)(o)
			inv := op.invite
			st := db.writer_stmt(SQL_ADD_INVITE)
			db.bind_text(st, 1, inv.code_hash)
			db.bind_int(st, 2, int(inv.role))
			db.bind_int(st, 3, inv.max_uses)
			db.bind_id(st, 4, inv.created_by)
			db.bind_id(st, 5, inv.created_at)
			db.bind_id(st, 6, inv.expires_at)
			o.err = db.step_done(st)
			db.reset(st)
			if o.err == .None { o.err = note(op.audit, 0) }
		})
	}
	return db.write(op)
}

delete_invite :: proc(op: ^m.Delete_Invite) -> bool {
	op.run = proc(o: ^store.Op) {
		unit(o, proc(o: ^store.Op) {
			op := (^m.Delete_Invite)(o)
			st := db.writer_stmt(SQL_DROP_INVITE)
			db.bind_text(st, 1, op.code_hash)
			o.err = db.step_done(st)
			if o.err == .None && db.changes() == 0 { o.err = .Not_Found }
			db.reset(st)
			if o.err == .None { o.err = note(op.audit, 0) }
		})
	}
	return db.write(op)
}

issue_reset :: proc(op: ^m.Issue_Reset) -> bool {
	op.run = proc(o: ^store.Op) {
		unit(o, proc(o: ^store.Op) {
			op := (^m.Issue_Reset)(o)
			dr := db.writer_stmt(SQL_DROP_RESETS)
			db.bind_id(dr, 1, op.user_id)
			o.err = db.step_done(dr)
			db.reset(dr)
			if o.err != .None { return }
			st := db.writer_stmt(SQL_ADD_RESET)
			db.bind_text(st, 1, op.code_hash)
			db.bind_id(st, 2, op.user_id)
			db.bind_id(st, 3, op.created_by)
			db.bind_id(st, 4, op.now)
			db.bind_id(st, 5, op.expires_at)
			o.err = db.step_done(st)
			db.reset(st)
			if o.err == .None { o.err = note(op.audit, 0) }
		})
	}
	return db.write(op)
}

// A read before the reset's hash (M4-05): a wrong code answers as quickly for a member as for
// a name with no account, which `user_id` 0 is.
reset_live :: proc(code_hash: string, user_id, now: i64) -> (live: bool, err: m.Error) {
	q := db.read(SQL_RESET_LIVE)
	defer db.reset(q)
	db.bind_text(q, 1, code_hash)
	db.bind_id(q, 2, user_id)
	db.bind_id(q, 3, now)
	return db.next_row(q, &err), err
}

redeem_reset :: proc(op: ^m.Redeem_Reset) -> bool {
	op.run = proc(o: ^store.Op) { unit(o, redeem_reset_run) }
	return db.write(op)
}

@(private = "file")
redeem_reset_run :: proc(o: ^store.Op) {
	op := (^m.Redeem_Reset)(o)
	sp := db.writer_stmt(SQL_SPEND_RESET)
	db.bind_id(sp, 1, op.now)
	db.bind_text(sp, 2, op.code_hash)
	db.bind_id(sp, 3, op.user_id)
	o.err = db.step_done(sp)
	db.reset(sp)
	if o.err == .None && db.changes() == 0 { o.err = .Constraint }
	if o.err != .None { return }
	pw := db.writer_stmt(SQL_SET_PASSWORD)
	db.bind_text(pw, 1, op.pw_hash)
	db.bind_id(pw, 2, op.user_id)
	o.err = db.step_done(pw)
	db.reset(pw)
	if o.err == .None { o.err = end_sessions(op.user_id) }
	if o.err == .None { o.err = note(op.audit, 0) }
}

set_display :: proc(op: ^m.Set_Display) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Set_Display)(o)
		st := db.writer_stmt(SQL_SET_DISPLAY)
		defer db.reset(st)
		db.bind_text(st, 1, op.display)
		db.bind_id(st, 2, op.user_id)
		o.err = db.step_done(st)
	}
	return db.write(op)
}

set_theme :: proc(op: ^m.Set_Theme) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Set_Theme)(o)
		pairs := [2][2]string{{"style", op.theme.style}, {"scheme", op.theme.scheme}}
		for p in pairs {
			st := db.writer_stmt(SQL_SET_PREF)
			db.bind_id(st, 1, op.user_id)
			db.bind_text(st, 2, p[0])
			db.bind_text(st, 3, p[1])
			o.err = db.step_done(st)
			db.reset(st)
			if o.err != .None { return }
		}
	}
	return db.write(op)
}

// On the writer: a second factor spent, or .Constraint when it already was (a replayed code, a
// used recovery code). Nothing to spend is .None.
@(private)
spend :: proc(user_id, step: i64, recovery_hash: string, now: i64) -> (err: m.Error) {
	switch {
	case step > 0:
		st := db.writer_stmt(SQL_SPEND_STEP)
		defer db.reset(st)
		db.bind_id(st, 1, step)
		db.bind_id(st, 2, user_id)
		err = db.step_done(st)
	case recovery_hash != "":
		st := db.writer_stmt(SQL_SPEND_CODE)
		defer db.reset(st)
		db.bind_id(st, 1, now)
		db.bind_id(st, 2, user_id)
		db.bind_text(st, 3, recovery_hash)
		err = db.step_done(st)
	case:
		return .None
	}
	if err == .None && db.changes() == 0 { err = .Constraint }
	return
}

@(private)
now_ms :: proc() -> i64 { return time.to_unix_nanoseconds(time.now()) / 1e6 }
