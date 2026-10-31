package signed

// ---- signed text: `<body>.<MAC>` (M4-13) -----------------------------------------------------
//
// A value the server hands out and reads back (a pending sign-in, envadmin's cookie) carries its
// body and HMAC-SHA256(key, body) in base64url without padding. `open` is the one parser of the
// untrusted text: a body comes back only when its MAC is the key's, compared in constant time, so
// what a caller parses after it is the server's own text. Its fuzz test feeds it anything.

import "core:crypto"
import "core:crypto/hash"
import "core:crypto/hmac"
import "core:encoding/base64"
import "core:strings"

import "../escape"

MAC_TEXT :: 43 // 32 bytes in base64url, no padding

// `body` and its MAC, in `allocator`.
sign :: proc(body: string, key: []byte, allocator := context.temp_allocator) -> string {
	mac: [32]byte
	hmac.sum(hash.Algorithm.SHA256, mac[:], transmute([]byte)body, key)
	return strings.concatenate({body, ".", base64.encode(mac[:], base64.ENC_URL_TABLE, context.temp_allocator, {.No_Padding})}, allocator)
}

// The body, when the text ends in its MAC under `key`.
open :: proc(text: string, key: []byte) -> (body: string, ok: bool) {
	dot := strings.last_index_byte(text, '.')
	if dot <= 0 || len(text) - dot - 1 != MAC_TEXT { return }
	body = text[:dot]
	mac: [32]byte
	hmac.sum(hash.Algorithm.SHA256, mac[:], transmute([]byte)body, key)
	sent, sok := escape.b64_decode(text[dot + 1:], url = true)
	if !sok || len(sent) != len(mac) || crypto.compare_constant_time(sent, mac[:]) != 1 { return "", false }
	return body, true
}
