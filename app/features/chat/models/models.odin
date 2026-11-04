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
	kind:    Room_Kind,
	owner:   u64, // who made it; 0 for the seeded lobby
	dropped: i64, // the newest message retention let go; 0: none yet (the marker, §14.1)
	locked:  bool, // only moderators post
	slow:    int, // seconds between a member's posts; 0: off
}

// A member kept from a room for a while by a moderator: muted (reads, doesn't post) or kicked
// (neither).
Ban_Kind :: enum u8 {
	Mute,
	Kick,
}

Ban :: struct {
	room:  i64,
	who:   u64,
	kind:  Ban_Kind,
	until: i64, // unix seconds; at or before now: lifted
	by:    u64,
}

// A member's report of a message, with a copy of it: what a moderator sees, private rooms and DMs
// included, which they don't read otherwise.
Report :: struct {
	id:          i64,
	room:        i64,
	msg:         i64,
	author:      u64,
	author_name: string,
	body:        string,
	blob:        string, // the message's image, kept for the report: an author's delete leaves it
	by:          u64,
	by_name:     string,
	reason:      string,
	at:          i64,
	resolved:    i64, // when; 0: open
	outcome:     string, // "removed" or "dismissed"
}

// The audit entry a moderation writes in its own transaction (M4-04): plain values, through the
// store's Audit_Writer, which chat hands it at init (store:audit's append_in; no store imports
// another, D18). `action` "" writes none. The body of a message is never in one (07 §1.5).
Audit :: struct {
	actor_id:    i64,
	actor_name:  string,
	client:      string,
	action:      string,
	target_kind: string,
	target_id:   i64,
	reason:      string,
	meta:        string,
}

Audit_Writer :: proc(actor_id: i64, actor_name, client, action, target_kind: string, target_id: i64, reason, meta: string) -> Error

// What a room of each kind keeps (§14.1, Q19): its newest `cap` messages, none older than `age`
// seconds; a pinned message is exempt from both.
Retention :: struct {
	cap: [Room_Kind]int,
	age: [Room_Kind]i64,
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
	blob:   string, // the image it carries, by its sha256; "" for none, and once deleted
	at:     i64,
	edited: i64, // unix seconds of the last edit; 0 = never
	gone:   bool,
	ver:    i64, // the room's version at its last change
}

// A member `who` blocked, and their name as it was.
Block :: struct {
	other: u64,
	name:  string,
	at:    i64,
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

// A search's match: the message, and its room's for the link.
Hit :: struct {
	msg:  Message,
	room: Room,
}

Error :: store.Error

// A post: `done` runs once it is stored, with the message.
Post :: struct {
	using op: store.Op,
	room:     i64,
	author:   u64,
	name:     string,
	body:     string,
	blob:     string,
	result:   Message,
}

// An edit or a delete of the author's own message, inside `window` seconds of
// posting: .Not_Found for none, .Constraint for someone else's or one too old. A moderator's
// delete (`moderated`) takes anyone's, at any age, and writes `audit` in the same batch.
Change :: struct {
	using op:  store.Op,
	id:        i64,
	author:    u64,
	body:      string, // the new text; ignored for a delete
	delete:    bool,
	window:    i64,
	moderated: bool,
	audit:     Audit,
	result:    Message,
	released:  string, // a delete: the image it carried, now maybe no one's
}

Store_Init :: proc(ring_bytes: int, keep: Retention)
// Every room's messages older than its kind's age at `now`, let go in chunks: how many.
Store_Sweep :: proc(now: i64) -> (removed: int, err: Error)
Store_Rooms :: proc(out: ^[dynamic]Room) -> Error // every room, every kind
Store_Rooms_For :: proc(who: u64, out: ^[dynamic]Room) -> Error // the public ones, announcements, and the private rooms and DMs `who` is in
Store_Room :: proc(slug: string) -> (Room, Error)
// .Constraint: the slug is taken, or the rooms are full. The owner of a private room or a DM is its first member.
Store_Create_Room :: proc(slug, name: string, kind: Room_Kind, owner: u64, owner_name: string) -> (Room, Error)
// The DM of `a` and `b`, made (with `slug` and both as members) when they have none.
Store_Dm :: proc(a: u64, a_name: string, b: u64, b_name: string, slug: string) -> (Room, Error)
Store_Members :: proc(room: i64, out: ^[dynamic]Member) -> Error // the owner first, then as they joined
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
// Moderation: each writes its `audit` in its own transaction.
Store_Set_Audit_Writer :: proc(w: Audit_Writer) // at init
Store_Set_Room :: proc(room: i64, locked: bool, slow: int, audit: Audit) -> Error
Store_Ban :: proc(b: Ban, audit: Audit) -> Error // until <= now lifts it
Store_Banned :: proc(room: i64, who: u64, kind: Ban_Kind, now: i64) -> (until: i64) // 0: not
// r.id, resolved and outcome are ignored; 0: this member has it open already
Store_Report :: proc(r: Report) -> (id: i64, err: Error)
Store_Reports :: proc(limit: int, out: ^[dynamic]Report) -> Error // the oldest open ones
Store_Open_Reports :: proc(by: u64) -> (theirs, all: int)
Store_Room_Of :: proc(id: i64) -> (Room, Error)
Store_Rooms_Owned :: proc(owner: u64) -> int // DMs aside
Store_Report_Of :: proc(id: i64) -> (Report, Error)
Store_Resolve :: proc(id: i64, at: i64, outcome: string, audit: Audit) -> Error // .Not_Found unless open
Store_Recent :: proc(room: i64, limit: int, out: ^[dynamic]Message) -> Error // oldest first
// id > after, oldest first; reached: nothing after `after` was let go, so `out` has no gap
Store_After :: proc(room: i64, after: i64, out: ^[dynamic]Message) -> (reached: bool, err: Error)
Store_Count_After :: proc(room: i64, after: i64) -> int // how many kept messages have id > after
Store_Changed :: proc(room: i64, since: i64, out: ^[dynamic]Message) -> (ver: i64, reached: bool, err: Error) // ver > since; the room's version; false: something changed after `since` has left the room
Store_Message :: proc(id: i64) -> (Message, Error)
// The newest `limit` live messages holding `words` (each, whole; the last also as a prefix), in the
// rooms `who` may read at `now`: public rooms and announcements they aren't kicked from, and the
// private rooms and DMs they are in.
Store_Search :: proc(who: u64, words: []string, now: i64, limit: int, out: ^[dynamic]Hit) -> Error
Store_Post :: proc(op: ^Post) -> bool // false: the store is busy; `done` won't run
Store_Change :: proc(op: ^Change) -> bool
Store_Seed :: proc()
// A live message or an open report carries it. True when the store can't tell.
Store_Blob_Held :: proc(sha256: string) -> bool
// Clears an image from every message and report, audited, each message's room version bumped so
// open pages lose it. `out`: the messages as they are now.
Store_Purge_Blob :: proc(sha256: string, audit: Audit, out: ^[dynamic]Message) -> Error
Store_Block :: proc(who, other: u64, name: string, at: i64) -> Error // again: nothing changes
Store_Unblock :: proc(who, other: u64) -> Error
Store_Blocking :: proc(who, other: u64) -> bool
Store_Blocks :: proc(who: u64, out: ^[dynamic]Block) -> Error // the newest first
