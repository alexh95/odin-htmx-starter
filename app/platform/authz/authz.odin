package authz

// ---- platform/authz: who may do what (L2) ----------------------------------
//
// D35, PLAN §17.1. One closed Perm enum, grouped by feature, one ROLE_PERMS
// table, no per-user grants. A route row names the perm it needs (`.Public` for
// none) and `front` checks it before a byte of the body is read; services check
// per item (own message, room moderator). The build's identity, a member of the
// `identity:` family, loads the Viewer through the contract below.

import "core:net"
import "core:strings"

Role :: enum u8 {
	Guest,
	User,
	Mod,
	Admin,
}

ROLE_LABELS := [Role]string {
	.Guest = "Guest",
	.User  = "Member",
	.Mod   = "Moderator",
	.Admin = "Admin",
}

Perm :: enum u8 {
	Public, // no check (D5); never granted, never required
	Account_Self,
	Chat_Read, Chat_Post, Chat_Dm, Chat_Create_Room, Chat_Attach, Chat_Moderate,
	Bot_Use, Bot_Llama,
	Video_Watch, Video_Upload, Video_Moderate,
	Wiki_Read, Wiki_Edit,
	Lists_Edit,
	Polls_Create, Polls_Vote,
	Calendar_Edit,
	Guestbook_Moderate,
	C4_Play,
	Term_Watch, Term_Write,
	Admin_Accounts, Admin_Audit, Admin_Ops, Admin_Jobs, Admin_Modules, Admin_Db, Admin_Term,
}

Perms :: bit_set[Perm; u64]

@(private = "file")
EVERYONE :: Perms{.Bot_Use, .Video_Watch, .Wiki_Read}
@(private = "file")
MEMBERS :: EVERYONE + Perms{
	.Account_Self, .Chat_Read, .Chat_Post, .Chat_Dm, .Chat_Create_Room, .Chat_Attach, .Bot_Llama,
	.Wiki_Edit, .Lists_Edit, .Polls_Create, .Polls_Vote, .Calendar_Edit, .C4_Play,
}
@(private = "file")
MODS :: MEMBERS + Perms{.Chat_Moderate, .Video_Upload, .Video_Moderate, .Guestbook_Moderate, .Term_Watch}

// The plan's default table; Term_Watch, Video_Upload and Admin_Audit are Q31's
// judgement calls, and rbac.spec freezes the whole table at M4.
ROLE_PERMS := [Role]Perms {
	.Guest = EVERYONE,
	.User  = MEMBERS,
	.Mod   = MODS,
	.Admin = MODS + Perms{.Term_Write, .Admin_Accounts, .Admin_Audit, .Admin_Ops, .Admin_Jobs, .Admin_Modules, .Admin_Db, .Admin_Term},
}

// Who is asking, as the build's identity loaded them. Views get it only to hide
// controls; enforcement is front's and the services'.
Viewer :: struct {
	id:         u64, // 0 = no account
	name:       string,
	role:       Role,
	step_up_at: i64, // unix seconds of the session's last password or TOTP check; 0 = never
	style:      string, // the member's kept theme (an identity that keeps one); "" = the brand's, or the browser's
	scheme:     string,
	connection: string, // the member's kept chat connection (an identity that keeps one); "" = none
	session:    u64, // the session's key, for the hub: a sign-out ends that device's streams alone; 0 = none
}

GUEST :: Viewer{role = .Guest}

// Where the theme picker posts a member's choice, set by an identity that keeps it; "" = the
// browser keeps it (localStorage), as for every guest.
theme_href: string

// Keeps a member's chat connection on their account, set by an identity that can; nil = the
// browser keeps it (a cookie), as for every guest. chat reaches accounts through this, not an import.
keep_connection: proc(user: u64, setting: string) -> bool

can :: proc(v: Viewer, p: Perm) -> bool {
	return p == .Public || p in ROLE_PERMS[v.role]
}

// How recent a password or TOTP check a `.Step_Up` row asks for (§17.1).
// An identity may shorten it at boot (ACCOUNTS_STEP_UP_WINDOW, so the suites can make a
// session stale); seconds.
step_up_window: i64 = 10 * 60

stepped_up :: proc(v: Viewer, now: i64) -> bool {
	return v.step_up_at > 0 && now - v.step_up_at <= step_up_window && v.step_up_at <= now
}

// What front answers a route's rules with, decided before a byte of the body is read
// (§17.2): off the LAN a `.Lan_Only` row isn't there; a guest without the perm signs in;
// anyone else without it is refused; a stale session on a `.Step_Up` row steps up.
Refusal :: enum u8 {
	None,
	Not_Found,
	Sign_In,
	Forbidden,
	Step_Up,
}

Rule :: struct {
	perm:     Perm,
	lan_only: bool,
	step_up:  bool,
}

refusal :: proc(v: Viewer, r: Rule, on_lan: bool, now: i64) -> Refusal {
	switch {
	case r.lan_only && !on_lan:         return .Not_Found
	case !can(v, r.perm):               return .Sign_In if v.role == .Guest else .Forbidden
	case r.step_up && !stepped_up(v, now): return .Sign_In if v.role == .Guest else .Step_Up
	}
	return .None
}

// What front hands the identity, before the body is read: only platform/web
// touches odin-http's types, so the contract carries the parts an identity reads.
Ask :: struct {
	cookies: string,      // the Cookie header, as sent
	client:  net.Address, // the trusted client address (§17.8)
	https:   bool,        // arrived as https through a trusted proxy (COOKIE_SECURE=auto)
}

// One cookie's value from a Cookie header ("" when absent): an identity's, and
// web.cookie's for a handler.
cookie :: proc(header, name: string) -> string {
	rest := header
	for part in strings.split_iterator(&rest, ";") {
		k, _, v := strings.partition(strings.trim_space(part), "=")
		if k == name { return v }
	}
	return ""
}

// The identity contract: each member of the `identity:` family declares
// `_ : authz.Load_Viewer : load_viewer` in its contract.odin. `set_cookie` is a
// Set-Cookie value for front to send (a rotated session), or "".
Load_Viewer :: #type proc(ask: Ask) -> (v: Viewer, set_cookie: string)

// Names a member can't take: the bot's, which its chat messages go under and `@bot` calls. Asked of a
// new username and a new nickname; an account that already has one keeps working (identity warns at boot).
reserved_name :: proc(name: string) -> bool {
	return strings.equal_fold(name, "bot") || strings.equal_fold(name, "capcom")
}
