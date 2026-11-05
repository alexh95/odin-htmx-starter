package bot

// ---- bot: the domain (PLAN §14.3, D31; Q20) -----------------------------------------------
//
// Questions, conversations and what a backend is asked. Conversations are their owner's
// alone and kept by the store; a guest's question is answered and kept by no one. Plain
// values and errors, never HTTP.

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:unicode/utf8"

import "../../platform/env"
import "../../platform/escape"
import "../../platform/markdown"
import m "models"
import bot_store "store:bot"

IMPL :: bot_store.IMPL

// A question's longest, in runes; the input carries the same maxlength.
MAX_QUESTION :: 4000
// An answer is kept, and rendered, up to markdown's input cap.
MAX_ANSWER :: 64 * 1024
// A conversation's title: its first question, cut by rune.
TITLE_RUNES :: 60
// What a backend is given of a conversation: its last turns, the question last, and at most
// PROMPT_BYTES of them: about 5k tokens, of the 8k context the host is sized for (§14.3), with
// room for the answer. Past that llama.cpp refuses the question rather than cutting it.
HISTORY :: 20
PROMPT_BYTES :: 16 * 1024
// How many conversations the page lists.
SHOWN :: 50

// What every request tells the model; the mock ignores it.
SYSTEM :: "You are the house assistant on a home LAN. Answer briefly and plainly."

Backend :: enum u8 {
	Mock,
	Llama,
}

BACKENDS := [Backend]string {
	.Mock = "mock",
	.Llama = "llama",
}

ENV := [?]env.Row {
	{name = "BOT_BACKEND", kind = .Enum, def = "mock", choices = "mock|llama", doc = "the bot's default backend; llama needs BOT_LLAMA_URL"},
	{name = "BOT_MEMBER_PER_HOUR", kind = .Int, def = "30", doc = "questions a member may ask an hour (§17.5)"},
	{name = "BOT_GUEST_PER_HOUR", kind = .Int, def = "5", doc = "questions one guest client may ask an hour, mock only (§17.5)"},
}

@(private)
st: struct {
	backend:          Backend,
	member_per_hour:  int,
	guest_per_hour:   int,
}

init :: proc() {
	env.record("BOT_", ENV[:])
	st.backend = .Llama if env.str("BOT_BACKEND") == "llama" else .Mock
	st.member_per_hour = max(1, env.int_("BOT_MEMBER_PER_HOUR"))
	st.guest_per_hour = max(1, env.int_("BOT_GUEST_PER_HOUR"))
}

default_backend :: proc() -> Backend { return sync.atomic_load(&st.backend) }
// In memory only: a restart goes back to BOT_BACKEND (D8).
set_default_backend :: proc(b: Backend) { sync.atomic_store(&st.backend, b) }
member_per_hour :: proc() -> int { return st.member_per_hour }
guest_per_hour :: proc() -> int { return st.guest_per_hour }

// The trimmed question, or why it was refused (the asker's to fix).
check_question :: proc(q: string) -> (trimmed, problem: string) {
	trimmed = strings.trim_space(q)
	switch {
	case trimmed == "":
		return "", "Ask something first."
	case utf8.rune_count_in_string(trimmed) > MAX_QUESTION:
		return "", fmt.tprintf("A question is at most %d characters.", MAX_QUESTION)
	}
	return trimmed, ""
}

// A conversation's title from its first question.
title_of :: proc(q: string) -> string {
	n := 0
	for _, i in q {
		if n == TITLE_RUNES { return strings.concatenate({q[:i], "…"}, context.temp_allocator) }
		n += 1
	}
	return q
}

// A room's answer: short, since it lands in everyone's log, and with no conversation behind it.
ROOM_TOKENS :: 600
ROOM_SYSTEM :: "You are the house assistant, answering in a chat room. Answer in a few sentences."

// The request for a question in a room: the question alone (§14.3).
room_request :: proc(user: u64, question: string) -> m.Bot_Request {
	history := make([]m.Bot_Turn, 1, context.temp_allocator)
	history[0] = {.User, question}
	return {user_id = user, system = ROOM_SYSTEM, history = history, max_tokens = ROOM_TOKENS, temperature = 0.7}
}

// The request for a question in a conversation (`turns` oldest first; none for a guest's).
request :: proc(conv: i64, user: u64, turns: []m.Turn, question: string) -> m.Bot_Request {
	from := max(0, len(turns) - (HISTORY - 1))
	size := len(question)
	for i := len(turns) - 1; i >= from; i -= 1 {
		size += len(turns[i].text)
		if size > PROMPT_BYTES {
			from = i + 1
			break
		}
	}
	history := make([dynamic]m.Bot_Turn, 0, len(turns) - from + 1, context.temp_allocator)
	for t in turns[from:] { append(&history, m.Bot_Turn{t.role, t.text}) }
	append(&history, m.Bot_Turn{.User, question})
	return {conv_id = conv, user_id = user, system = SYSTEM, history = history[:], max_tokens = 512, temperature = 0.7}
}

// An answer as the page shows it: markdown, escaped by construction and depth-capped
// (platform/markdown); past its input cap, plain escaped text.
render :: proc(b: ^strings.Builder, text: string) {
	if _, ok := markdown.render(b, text); !ok { escape.esc(b, text) }
}

// ---- conversations ------------------------------------------------------------------------

conversations :: proc(owner: u64, out: ^[dynamic]m.Conversation) -> m.Error { return bot_store.conversations(owner, SHOWN, out) }
conversation :: proc(owner: u64, id: i64) -> (m.Conversation, m.Error) { return bot_store.conversation(owner, id) }
turns :: proc(owner: u64, conv: i64, out: ^[dynamic]m.Turn) -> m.Error { return bot_store.turns(owner, conv, out) }
usage :: proc() -> (m.Usage, m.Error) { return bot_store.usage() }

// Stores op's conversation; op.done runs once it is. false: the store is busy.
start :: proc(op: ^m.Start) -> bool { return bot_store.start(op) }
append_turn :: proc(op: ^m.Append) -> bool { return bot_store.append_turn(op) }
