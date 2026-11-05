package bot_web

// ---- room mode: `@bot` in a chat room (PLAN §6.2, §14.3, X37) ---------------------------------
//
// Two static topic rows, one each way, so neither feature imports the other. chat publishes a
// message that asks the bot on bot.ask:<room>, and `room_ask` below is that row's `deliver`, on the
// poster's loop. The answer is the backend's, under the asker's own limits, and the model sees the
// question alone: a private room's talk leaves the room only when someone asks.
//
// While it comes, a bubble in the room, on chat.typing: every room page reads that topic whatever
// its transport, it isn't persisted, and `.Latest` keeps each bubble's newest, so a frame holds the
// whole text so far and a late reader gets it at once. The finished answer goes back on
// chat.reply:<room>, chat's row, which stores it as a message from the bot and publishes it; a
// reload, a poll and the room's search see that one.

import "core:fmt"
import "core:nbio"
import "core:strconv"
import "core:strings"
import "core:time"

import "../../../platform/guard"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/sys"
import "../../../platform/web"
import bot ".."
import m "../models"
import bot_views "../views"

// A room's answer past this is cut: chat keeps 2,000 runes of it anyway.
@(private) ROOM_ANSWER :: 16 * 1024
// A bubble's frames carry the whole text, so they come slower than an asker's own tokens.
@(private) BUBBLE_EVERY :: 250 * time.Millisecond

@(private)
Room_Asking :: struct {
	room:    i64,
	who:     Who,
	gen:     m.Bot_Gen_Id,
	mid:     string, // heap
	answer:  strings.Builder,
	spoke:   i64, // when the last bubble went
}

@(private)
room_ask :: proc(topic, payload: string, rowid: i64) {
	_, key := hub.split_topic(topic)
	room, ok := strconv.parse_i64(key, 10)
	if !ok { return }
	// "<asker's id>\n<the question>": what a topic can carry.
	rest := payload
	id_text, _ := strings.split_iterator(&rest, "\n")
	asker, parsed := strconv.parse_u64(id_text, 10)
	if !parsed || asker == 0 { return }
	question, problem := bot.check_question(rest)
	if problem != "" {
		tell(asker, problem)
		return
	}
	who := Who{member = true, key = asker}
	if !admit(who) {
		tell(asker, "One answer at a time: wait for this one.")
		return
	}
	if allowed, retry := web.limit_hit(&members_hour, who.key); !allowed {
		leave(who)
		tell(asker, fmt.tprintf("That's %d questions this hour; the next one opens in %d minutes.", members_hour.n, max(1, int(retry / time.Minute))))
		return
	}
	backend := bot.default_backend()
	if !healthy(backend) { backend = .Mock }

	a := new(Room_Asking, heap())
	a.room, a.who = room, who
	a.answer = strings.builder_make(heap())
	guard.lock(&gens.mu)
	gens.seq += 1
	a.gen = m.Bot_Gen_Id(gens.seq)
	guard.unlock(&gens.mu)
	a.mid = fmt.aprintf("g%d", u64(a.gen), allocator = heap())
	bubble(a)
	sink := m.Bot_Sink{user = a, loop = nbio.current_thread_event_loop(), gen = a.gen, on_event = room_event}
	generate(backend, bot.request(0, who.key, nil, question), sink)
}

// The backend's events, on the poster's loop.
@(private)
room_event :: proc(user: rawptr, _: m.Bot_Gen_Id, ev: m.Bot_Event) {
	a := (^Room_Asking)(user)
	switch e in ev {
	case m.Bot_Token:
		if strings.builder_len(a.answer) + len(e.text) <= ROOM_ANSWER { strings.write_string(&a.answer, e.text) }
		if sys.mono_ns() - a.spoke >= i64(BUBBLE_EVERY) { bubble(a) }
	case m.Bot_Queued:
		if e.position > 0 { bubble(a, e.position) }
	case m.Bot_Error:
		room_done(a, e.message)
	case m.Bot_Done:
		text := strings.to_string(a.answer)
		room_done(a, text if text != "" else "I have nothing to say to that.")
	}
}

@(private)
bubble :: proc(a: ^Room_Asking, queued := 0) {
	a.spoke = sys.mono_ns()
	hub.publish(fmt.tprintf("chat.typing:%d", a.room), bot_views.bubble(a.room, a.mid, strings.to_string(a.answer), queued), 0, a.mid)
}

// chat stores the answer; the bubble goes as the stored message arrives.
@(private)
room_done :: proc(a: ^Room_Asking, text: string) {
	leave(a.who)
	hub.publish(fmt.tprintf("chat.reply:%d", a.room), text)
	hub.publish(fmt.tprintf("chat.typing:%d", a.room), bot_views.bubble_gone(a.mid), 0, a.mid)
	delete(a.mid, heap())
	strings.builder_destroy(&a.answer)
	free(a, heap())
}

// What a room's page can't be told in the room: to the asker alone, on their own topic.
@(private)
tell :: proc(member: u64, text: string) {
	hub.publish(strings.concatenate({"notify.user:", hub.member_key({id = member})}, context.temp_allocator), html.toast("error", text, true))
}

