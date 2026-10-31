package accounts_models

// ---- accounts: the types and the store contract ------------------------------------------
//
// Below the domain, the identity and the store (PLAN §5.1, §17.1). Accounts need SQLite (D18):
// the store is the SQLite family's alone. Times are unix ms. A session is stored by the SHA-256
// of its token, as 64 hex characters, never the token.

import "../../../platform/authz"
import "../../../platform/store"

User :: struct {
	id:            i64,
	username:      string, // unique, case-insensitive
	display:       string,
	role:          Role,
	pw_hash:       string, // a PHC string (platform/password)
	disabled_at:   i64,    // 0: enabled
	failed_logins: int,
	backoff_until: i64,    // no verify before this (exponential backoff, never a lockout)
	totp_secret:    string, // base32; "" = no second factor
	totp_last_step: i64,    // the last TOTP step a code was taken for: no code is taken twice
}

// How many recovery codes an enrolment hands out (§17.1).
RECOVERY_CODES :: 10

// An invite: a link with a code (stored hashed) that registers up to `max_uses` members with
// `role`, until `expires_at`.
Invite :: struct {
	code_hash:  string,
	role:       Role,
	max_uses:   int,
	uses:       int,
	created_by: i64,
	created_at: i64,
	expires_at: i64,
}

// A registration, and the session it signs the new member in with, in one write. With a code,
// the invite is spent and gives the role (no live invite: .Not_Found); without one, a Member.
// A taken username is .Constraint.
Register :: struct {
	using op:    store.Op,
	username:    string,
	display:     string,
	pw_hash:     string,
	invite_hash: string, // "" in open mode
	token_hash:  string,
	now:         i64,
	expires_at:  i64,
	result:      i64,  // the new id
	role:        Role, // what the invite gave
	audit:       Audit, // written with the change (M4-04)
}

// An admin's change to a member: the role, or disabled (now) or enabled (0). The last enabled
// admin can't be demoted or disabled (.Constraint). Either way the member's sessions end, so the
// change is in force at their next request and a new role needs a new sign-in.
Set_Role :: struct {
	using op: store.Op,
	user_id:  i64,
	role:     Role,
	audit:       Audit, // written with the change (M4-04)
}

Set_Disabled :: struct {
	using op:    store.Op,
	user_id:     i64,
	disabled_at: i64,
	audit:       Audit, // written with the change (M4-04)
}

Create_Invite :: struct {
	using op: store.Op,
	invite:   Invite,
	audit:       Audit, // written with the change (M4-04)
}

Delete_Invite :: struct {
	using op:  store.Op,
	code_hash: string,
	audit:       Audit, // written with the change (M4-04)
}

// A one-time reset code for a member, replacing any they had.
Issue_Reset :: struct {
	using op:   store.Op,
	user_id:    i64,
	code_hash:  string,
	created_by: i64,
	now:        i64,
	expires_at: i64,
	audit:       Audit, // written with the change (M4-04)
}

// A reset code spent on a new password: the failures cleared and every session ended. No live
// code for that member: .Constraint.
Redeem_Reset :: struct {
	using op:  store.Op,
	user_id:   i64,
	code_hash: string,
	pw_hash:   string,
	now:       i64,
	audit:       Audit, // written with the change (M4-04)
}

Set_Display :: struct {
	using op: store.Op,
	user_id:  i64,
	display:  string,
}

// A member's theme, kept in accounts_prefs so every device renders it (PLAN §12): both axes at once.
Theme :: struct {
	style, scheme: string,
}

Set_Theme :: struct {
	using op: store.Op,
	user_id:  i64,
	theme:    Theme,
}

Session :: struct {
	token_hash: string,
	user_id:    i64,
	created_at: i64,
	last_seen:  i64,
	expires_at: i64, // the absolute end (30 days); the idle end (14) is last_seen's
	step_up_at: i64, // the last password or TOTP check; 0: none since sign-in
}

Error :: store.Error

// The audit entry a change writes in its own transaction (M4-04): plain values, since the store
// writes it (stores/sqlite/audit's append_in, the one store-to-store edge). `action` "" writes
// none. An entry with no change of its own (a failed sign-in) is its own op, through store:audit.
Audit :: struct {
	actor_id:    i64,
	actor_name:  string,
	client:      string,
	action:      string,
	target_kind: string,
	target_id:   i64,
	reason:      string,
	meta:        string,
	of_result:   bool, // the actor and the target are the op's result: a registration's new member
}

// The store reads a role through this: it imports no authz.
Role :: authz.Role

// Member, Moderator…: for the views, which import no authz either.
role_label :: proc(r: Role) -> string { return authz.ROLE_LABELS[r] }

// Writes go through the writer task (store.Op): the caller's `done` runs once stored.
Create_User :: struct {
	using op: store.Op,
	username: string,
	display:  string,
	pw_hash:  string,
	role:     Role,
	result:   i64, // the new id
}

// A wrong password: one more failure, and no verify before `backoff_until`.
Login_Failed :: struct {
	using op:      store.Op,
	user_id:       i64,
	backoff_until: i64,
}

// A sign-in: the session row, the user's failures cleared, the session it replaces (the
// cookie the request carried, rotated) closed, and the user's dead sessions swept. A sign-in
// is a password check, so it counts as a step-up.
Open_Session :: struct {
	using op:    store.Op,
	token_hash:  string,
	old_hash:    string, // "" when the request carried none
	user_id:     i64,
	now:         i64,
	expires_at:  i64,
	idle_before: i64, // a session last seen before this is dead
	// The second factor this sign-in used, spent in the same transaction: the TOTP step (0:
	// none), or a recovery code's hash. Already spent, the op fails with .Constraint.
	totp_step:     i64,
	recovery_hash: string,
	audit:       Audit, // written with the change (M4-04)
}

// TOTP on (a secret and the hashes of its recovery codes) or off ("" and none). The user's old
// codes go either way. `last_step` is the step the enrolment's own code was taken for.
Set_Totp :: struct {
	using op:  store.Op,
	user_id:   i64,
	secret:    string,
	last_step: i64,
	codes:     [RECOVERY_CODES]string,
	enrol:     bool, // only over no secret: .Constraint, and nothing written, when one is set (M4-01)
	was:       string, // else, when set: only over this secret, .Constraint when it changed meanwhile
	audit:       Audit, // written with the change (M4-04)
}

// A step-up: the session's step_up_at is now. By code, the step is spent as a sign-in's is.
Step_Up :: struct {
	using op:   store.Op,
	token_hash: string,
	user_id:    i64,
	now:        i64,
	totp_step:  i64,
	audit:       Audit, // written with the change (M4-04)
}

Touch_Session :: struct {
	using op:   store.Op,
	token_hash: string,
	now:        i64,
}

// Sign-out, and a member's revoke of one of their own sessions: only the user's.
Close_Session :: struct {
	using op:   store.Op,
	token_hash: string,
	user_id:    i64,
	ended:      bool, // out: a session of theirs went (a foreign hash ends nothing)
	audit:       Audit, // written with the change (M4-04)
}

Store_User_By_Name :: proc(username: string) -> (User, Error)
Store_User_By_Id :: proc(id: i64) -> (User, Error)
Store_Session :: proc(token_hash: string) -> (Session, Error)
Store_Sessions_Of :: proc(user_id: i64, into: ^[dynamic]Session) -> Error // newest first
Store_Count_Admins :: proc() -> (int, Error)
Store_Recovery_Left :: proc(user_id: i64) -> (int, Error)
Store_Users :: proc(into: ^[dynamic]User) -> Error   // by id, at most 500
Store_Invites :: proc(now: i64, into: ^[dynamic]Invite) -> Error // the live ones, newest first
Store_Invite :: proc(code_hash: string, now: i64) -> (Invite, Error) // a live one
// At boot, before the loops: the first admin, when no enabled one exists.
Store_Bootstrap_Admin :: proc(username, pw_hash: string) -> (created: bool, err: Error)
Store_Create_User :: proc(op: ^Create_User) -> bool // false: the store is busy; `done` won't run
Store_Login_Failed :: proc(op: ^Login_Failed) -> bool
Store_Open_Session :: proc(op: ^Open_Session) -> bool
Store_Touch_Session :: proc(op: ^Touch_Session) -> bool
Store_Close_Session :: proc(op: ^Close_Session) -> bool
Store_Set_Totp :: proc(op: ^Set_Totp) -> bool
Store_Step_Up :: proc(op: ^Step_Up) -> bool
Store_Register :: proc(op: ^Register) -> bool
Store_Set_Role :: proc(op: ^Set_Role) -> bool
Store_Set_Disabled :: proc(op: ^Set_Disabled) -> bool
Store_Create_Invite :: proc(op: ^Create_Invite) -> bool
Store_Delete_Invite :: proc(op: ^Delete_Invite) -> bool
Store_Issue_Reset :: proc(op: ^Issue_Reset) -> bool
Store_Reset_Live :: proc(code_hash: string, user_id, now: i64) -> (bool, Error) // the member's unspent, unexpired code
Store_Redeem_Reset :: proc(op: ^Redeem_Reset) -> bool
Store_Set_Display :: proc(op: ^Set_Display) -> bool
Store_Theme_Of :: proc(user_id: i64) -> (Theme, Error) // {} when the member never chose
Store_Set_Theme :: proc(op: ^Set_Theme) -> bool
