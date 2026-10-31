package audit_models

// ---- audit: the types and the store contract ---------------------------------------------
//
// PLAN §17.7, §6.2 (3). `store:audit` is the one store any domain, web or identity package may
// import: an append-only log has no rules for a domain to add. The SQLite family keeps
// `audit_log` (append-only by triggers; a row may go only past 400 days), the memory family
// writes one `mod=audit` log line and lists nothing. Times are unix ms. Never a message body
// or a password: an entry names who did what to which, and why.

import "../../../platform/store"

Error :: store.Error

// Who did it: a member (id and the name at the time), or nobody yet (id 0, a failed sign-in),
// and the hashed client id, never the address.
Actor :: struct {
	id:     i64,
	name:   string,
	client: string,
}

// What it was done to: `{"user", 7}`, `{"session", 0}`.
Target :: struct {
	kind: string,
	id:   i64,
}

Entry :: struct {
	id:     i64,
	at:     i64,
	actor:  Actor,
	action: string, // namespaced by its feature: "accounts.sign_in"
	target: Target,
	reason: string, // the actor's own words (HX-Prompt), or ""
	meta:   string, // a short key=value detail, or ""
}

// A page of the log, newest first: entries before `before` (0: from the newest), by an actor
// whose name is `actor` (any case; "" any) and an action starting with `action` ("" any).
Filter :: struct {
	actor:  string,
	action: string,
	before: i64,
	limit:  int,
}

// Queued and forgotten: false only when the store is busy (the entry is lost). From a loop
// thread: the SQLite family's write answers back on the loop that queued it.
Store_Append :: proc(actor: Actor, action: string, target: Target, reason, meta: string) -> bool
Store_List :: proc(f: Filter, into: ^[dynamic]Entry) -> Error
// Entries a full writer queue refused since boot: each is lost, and counted here (M4-04).
Store_Dropped :: proc() -> u64
