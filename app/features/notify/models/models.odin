package notify_models

// ---- notify: the types and the store contract -----------------------------------------
//
// Below the domain, the views and both stores (PLAN §5.1, §14.2). A notification is
// a producer's fragment for one member: `kind` is the producer's namespaced name
// ("chat.mention"), `ref` what it points at (a room's URL), `html` its line, already
// escaped by the producer, which builds it from its own fixed markup.

import "../../../platform/store"

Item :: struct {
	id:   i64,
	user: u64, // the member's id, as the identity gives it
	kind: string,
	ref:  string,
	html: string,
	at:   i64, // unix seconds
	read: bool,
}

Error :: store.Error

// Adding one is a write: `done` runs once it is stored, with the item and the
// member's unread count after it.
Add :: struct {
	using op: store.Op,
	user:     u64,
	kind:     string,
	ref:      string,
	html:     string,
	result:   Item,
	unread:   int,
}

Store_List :: proc(user: u64, limit: int, out: ^[dynamic]Item) -> Error
Store_Unread :: proc(user: u64) -> int
Store_Add :: proc(op: ^Add) -> bool // false: the store is busy; `done` won't run
Store_Mark_Read :: proc(user: u64) -> Error
Store_Prune :: proc(read_before: i64) -> int // read items older than this go; how many did
// From a thread with no loop to answer on (a job): stored at once.
Store_Add_Now :: proc(user: u64, kind, ref, html: string) -> (it: Item, unread: int, err: Error)
Store_Mute :: proc(user: u64, key: string, on: bool) -> Error
Store_Muted :: proc(user: u64, key: string) -> bool
Store_Mutes :: proc(user: u64, out: ^[dynamic]string) -> Error // sorted
Store_Retract :: proc(ref: string) -> Error // every member's items naming `ref` go
