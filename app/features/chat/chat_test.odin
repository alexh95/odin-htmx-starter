package chat

import "core:strings"
import "core:testing"

@(private = "file")
reset :: proc() {
	for _, name in st.names { delete(name, heap()) }
	delete(st.names)
	for _, r in st.read { delete(r) }
	delete(st.read)
	for _, &r in st.here {
		for _, p in r { delete(p.name, heap()) }
		delete(r)
	}
	delete(st.here)
	st = {}
}

// One test: the domain's state is the package's.
@(test)
the_room_knows_who_is_there :: proc(t: ^testing.T) {
	defer reset()
	defer free_all(context.temp_allocator)

	// Presence: nothing, then online once however many streams, away after the last.
	here := make([dynamic]Presence_Change, context.temp_allocator)
	present(1, &here)
	testing.expect_value(t, len(here), 0)
	c, show := join(1, 7, "ann")
	testing.expect(t, show)
	testing.expect_value(t, c.state, Presence_State.Online)
	_, show = join(1, 7, "ann")
	testing.expect(t, !show)
	leave(1, 7)
	leave(1, 7)
	present(1, &here)
	testing.expect_value(t, len(here), 1)
	changes := make([dynamic]Presence_Change, context.temp_allocator)
	sweep_presence(&changes) // inside the debounce: still online
	testing.expect_value(t, len(changes), 0)

	// The bot: `@bot` as its own word, without case, taken out of the question.
	for c in ([][3]string{{"@bot why?", "why?", "y"}, {"hey @BOT, why?", "hey , why?", "y"}, {"why @bot", "why", "y"}, {"@bot.", ".", "y"},
		{"me@bot.example", "", ""}, {"@bottom", "", ""}, {"@bot-x", "", ""}, {"no one", "", ""}}) {
		q, asked := asks_bot(c[0])
		testing.expectf(t, q == c[1] && asked == (c[2] != ""), "%q: %q %v", c[0], q, asked)
	}
	testing.expect_value(t, cut_body("  short  "), "short")
	long := cut_body(strings.repeat("é", 3 * MAX_BODY, context.temp_allocator))
	testing.expect_value(t, strings.rune_count(long), MAX_BODY)

	// Mentions: by the name a member last used, without case, never the author.
	seen(7, "ann")
	seen(8, "Bob")
	seen(8, "bob.b")
	who := make([dynamic]u64, context.temp_allocator)
	mentioned("hi @BOB.B and @ann, and @nobody.", 7, &who)
	testing.expect_value(t, len(who), 1)
	if len(who) == 1 { testing.expect_value(t, who[0], u64(8)) }

	// Read cursors only move forward.
	testing.expect(t, mark_read(1, 7, 10))
	testing.expect(t, !mark_read(1, 7, 9))
	readers_of := make([dynamic]u64, context.temp_allocator)
	readers(1, &readers_of)
	testing.expect_value(t, len(readers_of), 1)

	// Readers: at most MAX_READERS a room, one forgotten past it (M2-08).
	for id in 0 ..< MAX_READERS + 8 { mark_read(3, u64(1000 + id), 1) }
	clear(&readers_of)
	readers(3, &readers_of)
	testing.expect_value(t, len(readers_of), MAX_READERS)

	// A leave from a room nobody joined makes no map, and a room everyone has left keeps none
	// once the sweep has seen them away and gone (M2-05).
	leave(99, 7)
	testing.expect(t, 99 not_in st.here)
	_, _ = join(2, 9, "cy")
	leave(2, 9)
	if r, ok := &st.here[2]; ok {
		if p, pok := &r[9]; pok { p.closed_ns -= i64(PRESENCE_DEBOUNCE + AWAY_FOR) }
	}
	sweep_presence(&changes) // away
	sweep_presence(&changes) // gone
	testing.expect(t, 2 not_in st.here)

	// Room names and slugs.
	name, slug, problem := check_room("  Off Topic!  ")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, name, "Off Topic!")
	testing.expect_value(t, slug, "off-topic")
	_, _, problem = check_room("!!!")
	testing.expect(t, problem != "")
}
