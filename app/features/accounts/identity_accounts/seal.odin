package accounts_identity_accounts

// ---- sealed TOTP secrets (M4-12) ------------------------------------------------------------
//
// With ACCOUNTS_TOTP_KEY_FILE set (32 bytes, raw or as 64 hex digits), a member's TOTP secret is
// stored sealed: `v1:` and base64url(nonce ‖ ciphertext ‖ tag), XChaCha20-Poly1305 under the key,
// the user's id as associated data, so a row's secret can't be moved to another row. A backup or
// a stolen database file then gives no one a member's second factor. A stored secret without the
// prefix is plaintext (every one before the key was set, a v2.3.0 database): it is read as it is,
// and sealed at boot once a key is there. Without a key, secrets stay plaintext, said at every
// boot; with sealed rows and no key, the server refuses to boot, since no second step could pass.

import "core:crypto"
import "core:crypto/chacha20poly1305"
import "core:crypto/hash"
import "core:crypto/hmac"
import "core:encoding/base64"
import "core:encoding/endian"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strings"

import "../../../platform/env"
import "../../../platform/escape"
import "../../../platform/obs"
import accounts ".."
import m "../models"

@(private) SEALED :: "v1:"
@(private) NONCE :: chacha20poly1305.XIV_SIZE
@(private) TAG :: chacha20poly1305.TAG_SIZE

// At init: the key from its file, or none. A file that is set and isn't a key refuses to boot.
@(private)
load_totp_key :: proc() {
	path := env.str("ACCOUNTS_TOTP_KEY_FILE")
	if path == "" { return }
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	text := strings.trim_space(string(data))
	switch {
	case err != nil:
		fmt.eprintfln("accounts: ACCOUNTS_TOTP_KEY_FILE %q can't be read", path)
		os.exit(78)
	case len(data) == 32:
		copy(st.totp_key[:], data)
	case len(text) == 64:
		raw, ok := hex.decode(transmute([]byte)text, context.temp_allocator)
		if !ok {
			fmt.eprintln("accounts: ACCOUNTS_TOTP_KEY_FILE holds 64 characters that aren't hex digits")
			os.exit(78)
		}
		copy(st.totp_key[:], raw)
	case:
		fmt.eprintln("accounts: ACCOUNTS_TOTP_KEY_FILE must hold 32 bytes, raw or as 64 hex digits")
		os.exit(78)
	}
	st.has_totp_key = true
	// Device cookies outlive a restart when there is a key to derive theirs from (doors.odin).
	hmac.sum(hash.Algorithm.SHA256, st.device_key[:], transmute([]byte)string("accounts device cookies"), st.totp_key[:])
}

// A secret as it is stored: sealed when there is a key; "" stays "".
@(private)
seal_secret :: proc(user_id: i64, text: string) -> string {
	if text == "" || !st.has_totp_key { return text }
	out := make([]byte, NONCE + len(text) + TAG, context.temp_allocator)
	nonce, body, tag := out[:NONCE], out[NONCE:NONCE + len(text)], out[NONCE + len(text):]
	crypto.rand_bytes(nonce)
	ctx: chacha20poly1305.Context
	chacha20poly1305.init_xchacha(&ctx, st.totp_key[:])
	aad := id_bytes(user_id)
	chacha20poly1305.seal(&ctx, body, tag, nonce, aad[:], transmute([]byte)text)
	return strings.concatenate({SEALED, base64.encode(out, base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding})}, context.temp_allocator)
}

// A stored secret as its text: a plaintext one as it is; "" when a sealed one doesn't open.
@(private)
open_secret :: proc(user_id: i64, stored: string) -> string {
	if !strings.has_prefix(stored, SEALED) { return stored }
	if !st.has_totp_key { return "" }
	raw, ok := escape.b64_decode(stored[len(SEALED):], url = true)
	if !ok || len(raw) < NONCE + TAG { return "" }
	nonce, body, tag := raw[:NONCE], raw[NONCE:len(raw) - TAG], raw[len(raw) - TAG:]
	text := make([]byte, len(body), context.temp_allocator)
	ctx: chacha20poly1305.Context
	chacha20poly1305.init_xchacha(&ctx, st.totp_key[:])
	aad := id_bytes(user_id)
	if !chacha20poly1305.open(&ctx, text, nonce, aad[:], body, tag) { return "" }
	return string(text)
}

@(private)
id_bytes :: proc(user_id: i64) -> (b: [8]byte) {
	endian.unchecked_put_u64le(b[:], u64(user_id))
	return
}

// At boot, after the migrations: every plaintext secret sealed when there is a key; a sealed one
// with no key to open it refuses to boot.
@(private)
seal_stored_secrets :: proc() {
	rows := make([dynamic]m.Totp_Row, context.temp_allocator)
	if err := accounts.totp_secrets(&rows); err != .None {
		fmt.eprintln("accounts: the TOTP secrets could not be read")
		os.exit(70)
	}
	plain, sealed := 0, 0
	for &r in rows {
		if strings.has_prefix(r.old, SEALED) { sealed += 1; continue }
		plain += 1
		if st.has_totp_key { r.new = seal_secret(r.user_id, r.old) }
	}
	if sealed > 0 && !st.has_totp_key {
		fmt.eprintfln("accounts: %d TOTP secrets are sealed, and ACCOUNTS_TOTP_KEY_FILE is unset: set it to the key they were sealed with", sealed)
		os.exit(78)
	}
	if !st.has_totp_key {
		if l, ok := obs.begin(.Warning, "accounts", "totp_plaintext"); ok {
			obs.str(&l, "msg", "ACCOUNTS_TOTP_KEY_FILE is unset: TOTP secrets are stored in plaintext")
			obs.num(&l, "secrets", i64(plain))
			obs.end(&l)
		}
		return
	}
	if plain == 0 { return }
	if err := accounts.reseal_totps(rows[:]); err != .None {
		fmt.eprintln("accounts: the TOTP secrets could not be sealed")
		os.exit(70)
	}
	if l, ok := obs.begin(.Info, "accounts", "totp_sealed"); ok {
		obs.num(&l, "secrets", i64(plain))
		obs.end(&l)
	}
}
