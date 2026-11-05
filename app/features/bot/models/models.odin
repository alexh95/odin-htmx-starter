package bot_models

// ---- bot: the types, the backend contract and the store contract (PLAN §14.3, D31) -------
//
// Below the domain, the views, the backends and the store. The backend contract is the
// one D31 fixes, so the mock (M2) and llama.cpp's binding (M7) answer the same events,
// with llama's stats; `bot_web`'s switch picks one per request (D8).

import "core:nbio"

import "../../../platform/store"

Error :: store.Error

// ---- the backends' contract ----------------------------------------------------------------

Bot_Role :: enum u8 {
	User,
	Assistant,
}

Bot_Turn :: struct {
	role: Bot_Role,
	text: string,
}

// Its strings live in the asking request's arena, which goes back once the answer's stream has
// begun (the fork's F-17): a backend's `start` copies whatever it keeps.
Bot_Request :: struct {
	conv_id:     i64,
	user_id:     u64,
	system:      string,
	history:     []Bot_Turn, // the question last
	max_tokens:  int,
	temperature: f32,
	stop:        []string,
}

Bot_Token :: struct {
	text: string,
}

Bot_Stop :: enum u8 {
	Eos,     // the model was done
	Length,  // max_tokens
	Stopped, // Stop, or the browser went away
	Error,
}

// llama.cpp's timings' shape, so the page shows the same stats for both backends.
Bot_Done :: struct {
	stop:           Bot_Stop,
	tokens:         int,
	ms_first_token: int,
	ms_total:       int,
}

Bot_Error :: struct {
	message: string,
}

// Waiting for a slot: the shell says "Queued (#n)" until one frees.
Bot_Queued :: struct {
	position: int,
}

// Tokens coalesced to at most 20 Hz by the backend.
Bot_Event :: union {
	Bot_Token,
	Bot_Done,
	Bot_Error,
	Bot_Queued,
}

Bot_Health_State :: enum u8 {
	Ready,
	Loading,
	Sleeping,
	Offline,
	Mock,
}

Bot_Health :: struct {
	state:       Bot_Health_State,
	slots_total: int,
	slots_busy:  int,
	queued:      int,
	model:       string,
}

Bot_Gen_Id :: distinct u64

// Where a generation's events go: `on_event` runs on `loop` (the stream's), never on
// another thread; `gen` names the generation the event is for. Strings in an event live
// until `on_event` returns.
Bot_Sink :: struct {
	user:     rawptr,
	loop:     ^nbio.Event_Loop,
	gen:      Bot_Gen_Id,
	on_event: proc(user: rawptr, gen: Bot_Gen_Id, ev: Bot_Event),
}

// ---- conversations ----------------------------------------------------------------------------

Conversation :: struct {
	id:    i64,
	owner: u64,
	title: string, // the first question, cut
	at:    i64,
	turns: int,
}

Turn :: struct {
	id:    i64,
	conv:  i64,
	role:  Bot_Role,
	text:  string,
	at:    i64,
	stats: Bot_Done, // an answer's
}

// What an admin sees of everyone's conversations (Q20): counts and timings, never their text.
Usage :: struct {
	conversations: int,
	answers:       int,
	tokens:        int,
	avg_first_ms:  int,
	avg_total_ms:  int,
}

// A new conversation for `owner`: `done` runs once it is stored, with it.
Start :: struct {
	using op: store.Op,
	owner:    u64,
	title:    string,
	result:   Conversation,
}

// A turn added to the owner's conversation (.Not_Found for anyone else's); a `title`
// renames the conversation too (its first question).
Append :: struct {
	using op: store.Op,
	owner:    u64,
	turn:     Turn,
	title:    string,
	result:   Turn,
}

Store_Conversations :: proc(owner: u64, limit: int, out: ^[dynamic]Conversation) -> Error // newest first
Store_Conversation :: proc(owner: u64, id: i64) -> (Conversation, Error) // .Not_Found unless theirs
Store_Turns :: proc(owner: u64, conv: i64, out: ^[dynamic]Turn) -> Error // oldest first
Store_Usage :: proc() -> (Usage, Error)
Store_Start :: proc(op: ^Start) -> bool // false: the store is busy; `done` won't run
Store_Append :: proc(op: ^Append) -> bool
