package chat_models

// ---- chat: the types and the store contract ---------------------------------------------
//
// Below the domain, the views, the transports and both stores (PLAN §5.1, §14.1). A
// message keeps its author's id and their name as it was when they posted (the
// author_name snapshot: no join into accounts, D6), and the room's version at its last
// change, which the poll transport's tag reads.

import "../../../platform/store"

// Who reads and who posts (D30): a public room and announcements are every member's to read,
// a private room and a DM only their members'; announcements are posted by their owner (and
// moderators). A DM is a two-member room with an opaque slug.
Room_Kind :: enum u8 {
	Public,
	Private,
	Announce,
	Dm,
}

Room :: struct {
	id:    i64,
	slug:  string, // [a-z0-9-], 1 to 40: every room URL is /chat/r/<slug> (X12)
	name:  string, // a DM's: its two members' names when it was made
	at:    i64,
	kind:  Room_Kind,
	owner: u64, // who made it; 0 for the seeded lobby
}

// A member of a private room or a DM, with their name as it was when they joined (D6).
Member :: struct {
	room: i64,
	who:  u64,
	name: string,
	at:   i64,
}

Message :: struct {
	id:     i64,
	room:   i64,
	author: u64,
	name:   string,
	body:   string, // "" once deleted: a tombstone keeps its row and id
	at:     i64,
	edited: i64, // unix seconds of the last edit; 0 = never
	gone:   bool,
	ver:    i64, // the room's version at its last change
}

// An invite to a private room: its link is `/chat/join/<id>.<secret>`, and the store keeps the
// secret's hash only. Open while not revoked, not expired and not used up.
Invite :: struct {
	id:       i64,
	room:     i64,
	hash:     string, // hex SHA-256 of the secret
	by:       u64,
	by_name:  string,
	at:       i64,
	expires:  i64,
	max_uses: int, // 0: any number until it expires
	uses:     int,
	revoked:  i64, // when; 0: not revoked
}

Error :: store.Error

// A post: `done` runs once it is stored, with the message.
Post :: struct {
	using op: store.Op,
	room:     i64,
	author:   u64,
	name:     string,
	body:     string,
	result:   Message,
}

// An edit or a delete of the author's own message, inside `window` seconds of
// posting: .Not_Found for none, .Constraint for someone else's or one too old.
Change :: struct {
	using op: store.Op,
	id:       i64,
	author:   u64,
	body:     string, // the new text; ignored for a delete
	delete:   bool,
	window:   i64,
	result:   Message,
}

Store_Init :: proc(ring_bytes: int)
Store_Rooms :: proc(out: ^[dynamic]Room) -> Error // every room, every kind
Store_Rooms_For :: proc(who: u64, out: ^[dynamic]Room) -> Error // the public ones, announcements, and the private rooms and DMs `who` is in
Store_Room :: proc(slug: string) -> (Room, Error)
// .Constraint: the slug is taken, or the rooms are full. The owner of a private room or a DM is its first member.
Store_Create_Room :: proc(slug, name: string, kind: Room_Kind, owner: u64, owner_name: string) -> (Room, Error)
// The DM of `a` and `b`, made (with `slug` and both as members) when they have none.
Store_Dm :: proc(a: u64, a_name: string, b: u64, b_name: string, slug: string) -> (Room, Error)
Store_Members :: proc(room: i64, out: ^[dynamic]Member) -> Error // in the order they joined
Store_Is_Member :: proc(room: i64, who: u64) -> bool
Store_Join :: proc(room: i64, who: u64, name: string) -> Error // .None when they are in it already
Store_Leave :: proc(room: i64, who: u64) -> Error
Store_Add_Invite :: proc(inv: Invite) -> (id: i64, err: Error) // inv.id and its counts are ignored
Store_Invite :: proc(id: i64) -> (Invite, Error)
Store_Invites :: proc(room: i64, now: i64, out: ^[dynamic]Invite) -> Error // a room's open invites at `now`, newest first
Store_Revoke_Invite :: proc(id, room, at: i64) -> Error // .Not_Found unless an open invite of `room`
// In one write: when invite `id` is still open at `now`, `who` joins its room, and a use is
// counted unless they were in it already. .Not_Found when it isn't open.
Store_Use_Invite :: proc(id, now: i64, who: u64, name: string) -> Error
Store_Recent :: proc(room: i64, limit: int, out: ^[dynamic]Message) -> Error // oldest first
// id > after, oldest first; reached: nothing after `after` was let go, so `out` has no gap
Store_After :: proc(room: i64, after: i64, out: ^[dynamic]Message) -> (reached: bool, err: Error)
Store_Count_After :: proc(room: i64, after: i64) -> int // how many kept messages have id > after
Store_Changed :: proc(room: i64, since: i64, out: ^[dynamic]Message) -> (ver: i64, reached: bool, err: Error) // ver > since; the room's version; false: something changed after `since` has left the room
Store_Message :: proc(id: i64) -> (Message, Error)
Store_Post :: proc(op: ^Post) -> bool // false: the store is busy; `done` won't run
Store_Change :: proc(op: ^Change) -> bool
Store_Seed :: proc()
