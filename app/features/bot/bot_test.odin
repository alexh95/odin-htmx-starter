package bot

import "core:strings"
import "core:testing"

import m "models"

@(private = "file")
roles :: proc(r: m.Bot_Request) -> string {
	b := strings.builder_make(context.temp_allocator)
	for t in r.history { strings.write_byte(&b, 'u' if t.role == .User else 'a') }
	return strings.to_string(b)
}

// Roles alternate whatever failed: many templates refuse two in a row, and a conversation that
// stays refused can't get out by itself (M7-09).
@(test)
a_failed_turn_leaves_roles_alternating :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	turns := []m.Turn{{role = .User, text = "one"}, {role = .User, text = "two"}, {role = .Assistant, text = ""}, {role = .User, text = "three"}}
	r := request(1, 2, turns, "four")
	testing.expect_value(t, roles(r), "u")
	testing.expect_value(t, r.history[0].text, "four")

	turns = {{role = .User, text = "one"}, {role = .Assistant, text = "two"}, {role = .User, text = "failed"}}
	r = request(1, 2, turns, "again")
	testing.expect_value(t, roles(r), "uau")
	testing.expect_value(t, r.history[2].text, "again")

	// The window may open on an answer: the template wants a question first (M7-R5).
	turns = {{role = .Assistant, text = "two"}, {role = .User, text = "three"}, {role = .Assistant, text = "four"}}
	testing.expect_value(t, roles(request(1, 2, turns, "five")), "uau")
}

// A prompt stops at PROMPT_BYTES of the newest turns, the question always in.
@(test)
a_prompt_stops_at_its_size :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	big := strings.repeat("x", PROMPT_BYTES / 2, context.temp_allocator)
	turns := []m.Turn{{role = .User, text = big}, {role = .Assistant, text = big}, {role = .User, text = "q"}, {role = .Assistant, text = big}}
	r := request(1, 2, turns, "now")
	size := 0
	for h in r.history { size += len(h.text) }
	testing.expectf(t, size <= PROMPT_BYTES && r.history[len(r.history) - 1].text == "now", "%d bytes, %s", size, roles(r))
}

@(test)
a_room_asks_briefly :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	r := room_request(7, "why?")
	testing.expect_value(t, r.max_tokens, ROOM_TOKENS)
	testing.expect_value(t, len(r.history), 1)
	testing.expect_value(t, r.history[0].text, "why?")
}
