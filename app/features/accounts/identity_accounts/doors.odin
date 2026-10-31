package accounts_identity_accounts

// ---- doors: backoffs kept in memory (M4-03, M4-05, M5-17, M5-18) ------------------------------
//
// A wrong password shuts a door a little longer: the first three are free, then 1 s, doubling to
// 5 min (`backoff_ms`). Two tables of doors are kept here, for the process:
//
//   names    every name tried, an account's or not, under one lock and with the count it has
//            just raised: so tries at once, or faster than the writer commits an account's row,
//            meet the same door for both, and the 429 says nothing about whether the name exists.
//            An account's row keeps its own count across a restart (`backoff_until`), which a
//            sign-in meets as well.
//   devices  a client that has signed in to the account before carries a device cookie for it
//            (OWASP's device cookie): it meets its device's door instead of the name's and the
//            row's, so a stranger who holds an account's door shut can't shut it on its owner
//            (M4-03 b).
//
// A table is fixed, so a flood of keys allocates nothing. A slot is a keyed hash (the boot key),
// so no one can aim a key at another's slot; and a slot still shut is never taken over: a key that
// lands on it shares its count, which costs it at worst an early 429.

import "core:crypto"
import "core:crypto/hash"
import "core:crypto/hmac"
import "core:encoding/base64"
import "core:encoding/endian"
import "core:fmt"
import "core:strconv"
import "core:strings"

import "../../../platform/guard"
import "../../../platform/web"
import accounts ".."

@(private) DOORS :: 4096

@(private)
Door :: struct {
	key:    u64,
	failed: int,
	until:  i64,
}

@(private)
Doors :: struct {
	mu:    guard.Mutex,
	slots: [DOORS]Door,
}

@(private) names: Doors
@(private) devices: Doors

// Until when `key`'s door is shut (ms); 0 = open.
@(private)
door_until :: proc(d: ^Doors, key: u64) -> i64 {
	guard.lock(&d.mu)
	defer guard.unlock(&d.mu)
	s := &d.slots[key % DOORS]
	return s.until if s.key == key || s.until > accounts.now_ms() else 0
}

// One more wrong try behind `key`'s door.
@(private)
door_failed :: proc(d: ^Doors, key: u64) {
	now := accounts.now_ms()
	guard.lock(&d.mu)
	defer guard.unlock(&d.mu)
	s := &d.slots[key % DOORS]
	if s.key != key && s.until <= now { s^ = {key = key} }
	s.failed += 1
	s.until = now + accounts.backoff_ms(s.failed)
}

// A right one: the count starts again, as an account's row does.
@(private)
door_cleared :: proc(d: ^Doors, key: u64) {
	guard.lock(&d.mu)
	defer guard.unlock(&d.mu)
	s := &d.slots[key % DOORS]
	if s.key == key { s^ = {} }
}

// A name's key in `names`; never 0.
@(private)
name_key :: proc(name: string) -> u64 {
	lower := strings.to_lower(name, context.temp_allocator) // usernames compare without case
	mac: [32]byte
	hmac.sum(.SHA256, mac[:], transmute([]byte)lower, st.boot_key[:])
	return endian.unchecked_get_u64le(mac[:8]) | 1
}

// ---- the device cookie ----------------------------------------------------------------------
//
// `<user id>.<16 hex digits>.<MAC>`: the digits are the device's key, random at its first
// sign-in to the account, and the MAC (HMAC-SHA256 under st.device_key, cut to 16 bytes) binds
// them to the account. It names a device, not a session: it outlives sign-outs, for
// DEVICE_LIFE, and proves only that this client once knew the account's password.

@(private) DEVICE_COOKIE :: "dev"
@(private) DEVICE_COOKIE_HOST :: "__Host-dev"
@(private) DEVICE_LIFE :: 180 * 24 * 3600 // seconds

@(private)
device_cookie_name :: proc(https: bool) -> string { return DEVICE_COOKIE_HOST if secure(https) else DEVICE_COOKIE }

@(private)
device_mac :: proc(body: string) -> string {
	mac: [32]byte
	hmac.sum(hash.Algorithm.SHA256, mac[:], transmute([]byte)body, st.device_key[:])
	return base64.encode(mac[:16], base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding})
}

// The device key the request's cookie proves for `user_id`; 0 when it carries none for them.
@(private)
device_of :: proc(req: ^web.Request, https: bool, user_id: i64) -> u64 {
	if user_id <= 0 { return 0 }
	value := web.cookie(req, device_cookie_name(https))
	dot := strings.last_index_byte(value, '.')
	if dot <= 0 { return 0 }
	body := value[:dot]
	want := device_mac(body)
	sent := value[dot + 1:]
	if len(sent) != len(want) || crypto.compare_constant_time(transmute([]byte)sent, transmute([]byte)want) != 1 { return 0 }
	id_text, _, key_text := strings.partition(body, ".")
	if len(key_text) != 16 { return 0 }
	key: u64
	for c in transmute([]byte)key_text { // strconv would take a sign and `_` separators
		d: u64
		switch c {
		case '0' ..= '9': d = u64(c - '0')
		case 'a' ..= 'f': d = u64(c - 'a' + 10)
		case:             return 0
		}
		key = key << 4 | d
	}
	id, iok := strconv.parse_i64_of_base(id_text, 10)
	if !iok || id != user_id { return 0 }
	return key | 1
}

// Sets the device cookie after a sign-in: the device's own key again, or a new one.
@(private)
remember_device :: proc(res: ^web.Response, https: bool, user_id: i64, key: u64) {
	k := key
	if k == 0 {
		crypto.rand_bytes(([^]byte)(&k)[:size_of(k)])
		k |= 1
	}
	body := fmt.tprintf("%d.%016x", user_id, k)
	web.add_cookie(res, device_cookie_name(https), strings.concatenate({body, ".", device_mac(body)}, context.temp_allocator), DEVICE_LIFE, secure(https))
}
