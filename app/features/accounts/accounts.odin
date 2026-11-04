package accounts

// ---- accounts: users and their sessions (PLAN §17.1, D35) ---------------------------------
//
// The domain under `identity_accounts`, which is how a profile reaches it: the feature has no
// web package of its own. A session is an opaque 32-byte token in the `sid` cookie; the store
// keeps only its SHA-256. A session ends 14 days after it was last seen or 30 after it began,
// whichever is first (ACCOUNTS_SESSION_IDLE and ACCOUNTS_SESSION_MAX shorten them for tests).
// Wrong passwords back an account off exponentially, never lock it.

import "core:crypto"
import "core:crypto/hash"
import "core:encoding/base64"
import "core:encoding/hex"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"

import "../../platform/password"
import m "models"
import accounts_store "store:accounts"

// The token's bytes; as unpadded base64url it is TOKEN_TEXT characters.
TOKEN_LEN :: 32
TOKEN_TEXT :: 43

// A username longer than this names no one (the login form's cap).
MAX_USERNAME :: 64
MAX_PASSWORD :: password.MAX_LEN

// A session's last_seen is written at most this often: a page view isn't a write.
TOUCH_EVERY_MS :: 60_000

Lifetimes :: struct {
	idle_ms, max_ms: i64,
}

// Set by the identity at boot, from its env rows.
lifetimes := Lifetimes{idle_ms = 14 * 86_400_000, max_ms = 30 * 86_400_000}

now_ms :: proc() -> i64 { return time.to_unix_nanoseconds(time.now()) / 1e6 }

// A new token for the cookie, and the hash the store keeps, both in the temp allocator.
new_token :: proc() -> (token, token_hash: string) {
	raw: [TOKEN_LEN]byte
	crypto.rand_bytes(raw[:])
	token = base64.encode(raw[:], base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding})
	return token, hash_token(token)
}

// The hex SHA-256 of a cookie's token.
hash_token :: proc(token: string) -> string {
	sum: [32]byte
	hash.hash_string_to_buffer(.SHA256, token, sum[:])
	return string(hex.encode(sum[:], context.temp_allocator))
}

// Whether a session is still good at `now`: before its absolute end and seen within the idle one.
live :: proc(s: m.Session, now: i64) -> bool {
	return now < s.expires_at && now - s.last_seen < lifetimes.idle_ms
}

// The live session a cookie's token names, and its enabled user.
// .Not_Found: no such session, or it ended, or its user is disabled; any other error is the
// store's, and says nothing about the session.
signed_in :: proc(token: string, now: i64) -> (u: m.User, s: m.Session, err: m.Error) {
	if len(token) != TOKEN_TEXT { return {}, {}, .Not_Found }
	s, err = accounts_store.session(hash_token(token))
	if err != .None { return }
	if !live(s, now) { return {}, {}, .Not_Found }
	u, err = accounts_store.user_by_id(s.user_id)
	if err != .None { return }
	if u.disabled_at != 0 { return {}, {}, .Not_Found }
	return u, s, .None
}

// How long a wrong password shuts an account's door: the first three are free, then 1 s,
// doubling, at most 5 min. Slow enough to stop guessing, never a lockout (07 §5.2).
backoff_ms :: proc(failed: int) -> i64 {
	if failed < 3 { return 0 }
	return min(i64(1000) << uint(min(failed - 3, 20)), 300_000)
}

user_by_id :: proc(id: i64) -> (m.User, m.Error) {
	return accounts_store.user_by_id(id)
}

user_by_name :: proc(username: string) -> (m.User, m.Error) {
	if len(username) > MAX_USERNAME { return {}, .Not_Found }
	return accounts_store.user_by_name(username)
}

sessions_of :: proc(user_id: i64, into: ^[dynamic]m.Session) -> m.Error {
	return accounts_store.sessions_of(user_id, into)
}

admin_ids :: proc(out: ^[dynamic]u64) { accounts_store.admin_ids(out) }

count_admins :: proc() -> (int, m.Error) {
	return accounts_store.count_admins()
}

// At boot, after the migrations: the first admin from ACCOUNTS_ADMIN_HASH.
set_audit_writer :: proc(w: m.Audit_Writer) { accounts_store.set_audit_writer(w) }
has_audit_writer :: proc() -> bool { return accounts_store.has_audit_writer() }
totp_secrets :: proc(into: ^[dynamic]m.Totp_Row) -> m.Error { return accounts_store.totp_secrets(into) }
reseal_totps :: proc(rows: []m.Totp_Row) -> m.Error { return accounts_store.reseal_totps(rows) }

bootstrap_admin :: proc(username, pw_hash: string) -> (created: bool, err: m.Error) {
	return accounts_store.bootstrap_admin(username, pw_hash)
}

recovery_left :: proc(user_id: i64) -> (int, m.Error) {
	return accounts_store.recovery_left(user_id)
}

// ---- names ------------------------------------------------------------------------------

// Who may register (§17.1, Q10): with an invite (the default), anyone, or no one. Set at boot.
Registration :: enum u8 {
	Invite,
	Open,
	Closed,
}

registration := Registration.Invite

MIN_USERNAME :: 3
MAX_USERNAME_NEW :: 32
MAX_DISPLAY :: 40

// A new username: 3 to 32 of letters, digits, `_`, `-` and `.`, starting with a letter or a digit
// (it lands in URLs, CSV and the log as it is).
check_username :: proc(raw: string) -> (name, problem: string) {
	name = strings.trim_space(raw)
	if len(name) < MIN_USERNAME || len(name) > MAX_USERNAME_NEW {
		return "", fmt.tprintf("A username is %d to %d characters.", MIN_USERNAME, MAX_USERNAME_NEW)
	}
	for c, i in transmute([]byte)name {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
		case '_', '-', '.': if i == 0 { return "", "A username starts with a letter or a digit." }
		case: return "", "A username is letters, digits, _, - and ."
		}
	}
	return name, ""
}

// A display name: trimmed, runs of spaces kept to one, 1 to MAX_DISPLAY runes, and no control,
// invisible or direction-changing characters (a bidi override would garble every page that
// shows it). spark's clean_name (06 §3.1).
clean_name :: proc(raw: string) -> (name, problem: string) {
	b := strings.builder_make(context.temp_allocator)
	space := false
	n := 0
	for r in strings.trim_space(raw) {
		switch {
		// Invisible and direction-changing characters first: core:unicode counts U+200B as a space.
		case r == utf8.RUNE_ERROR, r >= 0x200b && r <= 0x200f, r >= 0x202a && r <= 0x202e, r >= 0x2066 && r <= 0x2069, r == 0xfeff:
			return "", "That name has characters the pages can't show."
		case unicode.is_space(r):
			space = true
			continue
		case unicode.is_control(r):
			return "", "That name has characters the pages can't show."
		}
		if space {
			strings.write_byte(&b, ' ')
			n += 1
			space = false
		}
		strings.write_rune(&b, r)
		n += 1
	}
	switch {
	case n == 0:          return "", "Pick a name to show."
	case n > MAX_DISPLAY: return "", fmt.tprintf("A name is at most %d characters.", MAX_DISPLAY)
	}
	return strings.to_string(b), ""
}

// A new password and its repeat.
check_new_password :: proc(pw, again: string) -> (problem: string) {
	switch password.check(pw) {
	case .Too_Short: return fmt.tprintf("A password is at least %d characters.", password.MIN_LEN)
	case .Too_Long:  return fmt.tprintf("A password is at most %d characters.", password.MAX_LEN)
	case .Ok:
	}
	if pw != again { return "The two passwords differ." }
	return ""
}

// ---- recovery codes ---------------------------------------------------------------------

// Ten codes like `k7mq-x2rf`: 40 random bits each, from an alphabet with no look-alikes. Shown
// once, at enrolment; the store keeps their hashes.
@(private)
CODE_ALPHABET :: "abcdefghjkmnpqrstuvwxyz023456789" // 32: no i, l, o or 1

new_recovery_codes :: proc() -> (codes: [m.RECOVERY_CODES]string) {
	for &c in codes { c = new_code(2) }
	return
}

// The hash of a typed recovery code; "" when it can't be one.
hash_recovery :: proc(text: string) -> string { return hash_code(text, 2) }

// A code of `groups` groups of four, `k7mq-x2rf-…`, 20 random bits a group, in the temp allocator.
new_code :: proc(groups: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	alphabet := CODE_ALPHABET
	for g in 0 ..< groups {
		if g > 0 { strings.write_byte(&b, '-') }
		raw: [4]byte
		crypto.rand_bytes(raw[:])
		for x in raw { strings.write_byte(&b, alphabet[x & 31]) }
	}
	return strings.to_string(b)
}

// The hash of a typed code of `groups` groups: any case, dashes and spaces ignored; "" when
// it can't be one.
hash_code :: proc(text: string, groups: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	for c in transmute([]byte)text {
		switch c {
		case '-', ' ':
		case 'A' ..= 'Z': strings.write_byte(&b, c + 32)
		case: strings.write_byte(&b, c)
		}
	}
	norm := strings.to_string(b)
	if len(norm) != 4 * groups { return "" }
	return hash_token(norm)
}

// Invites carry 100 bits (five groups) in a link; a reset code 60 (three), read out by an admin.
INVITE_GROUPS :: 5
RESET_GROUPS :: 3

// ---- members, invites and resets ----------------------------------------------------------

users :: proc(into: ^[dynamic]m.User) -> m.Error { return accounts_store.users(into) }
invites :: proc(now: i64, into: ^[dynamic]m.Invite) -> m.Error { return accounts_store.invites(now, into) }
invite :: proc(code_hash: string, now: i64) -> (m.Invite, m.Error) { return accounts_store.invite(code_hash, now) }
register :: proc(op: ^m.Register) -> bool { return accounts_store.register(op) }
set_role :: proc(op: ^m.Set_Role) -> bool { return accounts_store.set_role(op) }
set_disabled :: proc(op: ^m.Set_Disabled) -> bool { return accounts_store.set_disabled(op) }
create_invite :: proc(op: ^m.Create_Invite) -> bool { return accounts_store.create_invite(op) }
delete_invite :: proc(op: ^m.Delete_Invite) -> bool { return accounts_store.delete_invite(op) }
issue_reset :: proc(op: ^m.Issue_Reset) -> bool { return accounts_store.issue_reset(op) }
redeem_reset :: proc(op: ^m.Redeem_Reset) -> bool { return accounts_store.redeem_reset(op) }
reset_live :: proc(code_hash: string, user_id, now: i64) -> (bool, m.Error) { return accounts_store.reset_live(code_hash, user_id, now) }
set_display :: proc(op: ^m.Set_Display) -> bool { return accounts_store.set_display(op) }
theme_of :: proc(user_id: i64) -> (m.Theme, m.Error) { return accounts_store.theme_of(user_id) }
set_theme :: proc(op: ^m.Set_Theme) -> bool { return accounts_store.set_theme(op) }
set_connection :: proc(user_id: i64, setting: string) -> m.Error { return accounts_store.set_pref_now(user_id, "connection", setting) }

// The writes: each queued to the writer, false when the store is busy (`done` won't run).
login_failed :: proc(op: ^m.Login_Failed) -> bool { return accounts_store.login_failed(op) }
open_session :: proc(op: ^m.Open_Session) -> bool { return accounts_store.open_session(op) }
touch_session :: proc(op: ^m.Touch_Session) -> bool { return accounts_store.touch_session(op) }
close_session :: proc(op: ^m.Close_Session) -> bool { return accounts_store.close_session(op) }
set_totp :: proc(op: ^m.Set_Totp) -> bool { return accounts_store.set_totp(op) }
step_up :: proc(op: ^m.Step_Up) -> bool { return accounts_store.step_up(op) }
