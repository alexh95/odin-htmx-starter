package authz_anonymous

// ---- the default identity: everyone is the Guest ---------------------------
//
// A member of the `identity:` family (D35, LC §3): `minimal`, `skeleton` and
// `lab` build with it. Nothing reads or sets a cookie, its CLI answers nothing,
// and it has no routes, so its profiles mount no identity table.

import "../../authz"

NAME :: "anonymous"
SETS_COOKIE :: false

load_viewer :: proc(ask: authz.Ask) -> (v: authz.Viewer, set_cookie: string) {
	return authz.GUEST, ""
}

// At boot, from app.boot: an identity's env rows and keys. The anonymous one has none.
init :: proc() {}

// The identity's own CLI flags (--hash-password in the hashing identities).
cli :: proc() {}

// Nobody here is an admin.
admin_ids :: proc(out: ^[dynamic]u64) {}
