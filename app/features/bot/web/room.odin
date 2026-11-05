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
// reload, a poll and the room's search see that one. A failed ask stores nothing and tells its
// asker alone.

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

// A chat message's longest. The bot stops the model here, marked, rather than cutting afterwards:
// nothing else holds the rest of a room's answer, and the bubble mustn't shrink as it lands.
@(private) ROOM_RUNES :: 2000
// A bubble's frames carry the whole text, so they come slower than an asker's own tokens.
@(private) BUBBLE_EVERY :: 250 * time.Millisecond

@(private)
Room_Asking :: struct {
	room:    i64,
	who:     Who,
	gen:     m.Bot_Gen_Id,
	backend: bot.Backend,
	mid:     string, // heap
	answer:  strings.Builder,
	runes:   int,
	cut:     bool, // it reached ROOM_RUNES, and the model was stopped
	spoke:   i64,  // when the last bubble went
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
	a.room, a.who, a.backend = room, who, backend
	a.answer = strings.builder_make(heap())
	guard.lock(&gens.mu)
	gens.seq += 1
	a.gen = m.Bot_Gen_Id(gens.seq)
	guard.unlock(&gens.mu)
	a.mid = fmt.aprintf("g%d", u64(a.gen), allocator = heap())
	bubble(a)
	sink := m.Bot_Sink{user = a, loop = nbio.current_thread_event_loop(), gen = a.gen, on_event = room_event}
	generate(backend, bot.room_request(who.key, question), sink)
}

// The backend's events, on the poster's loop.
@(private)
room_event :: proc(user: rawptr, _: m.Bot_Gen_Id, ev: m.Bot_Event) {
	a := (^Room_Asking)(user)
	switch e in ev {
	case m.Bot_Token:
		for r in e.text {
			if a.cut { break }
			if a.runes == ROOM_RUNES - 1 {
				strings.write_string(&a.answer, "…")
				a.cut = true
				bubble(a)
				cancel(a.backend, a.gen)
				break
			}
			strings.write_rune(&a.answer, r)
			a.runes += 1
		}
		if !a.cut && sys.mono_ns() - a.spoke >= i64(BUBBLE_EVERY) { bubble(a) }
	case m.Bot_Queued:
		if e.position > 0 { bubble(a, e.position) }
	case m.Bot_Error:
		tell(a.who.key, e.message)
		room_done(a, "")
	case m.Bot_Done:
		if e.stop == .Length && !a.cut && a.runes > 0 { // the model ran out of tokens: marked, as a cut is
			strings.write_string(&a.answer, "…")
			a.cut = true
		}
		text := strings.trim_space(strings.to_string(a.answer))
		switch {
		case a.cut:
			room_done(a, text) // what the bubble already shows, whatever ended the model after it
		case e.stop == .Error:
			tell(a.who.key, "The answer was cut off.")
			room_done(a, "")
		case e.stop == .Stopped && !a.cut: // the server is going
			room_done(a, "")
		case text == "":
			tell(a.who.key, "The model had nothing to say.")
			room_done(a, "")
		case:
			room_done(a, text)
		}
	}
}

@(private)
bubble :: proc(a: ^Room_Asking, queued := 0) {
	a.spoke = sys.mono_ns()
	text := strings.trim_space(strings.to_string(a.answer))
	hub.publish(fmt.tprintf("chat.typing:%d", a.room), bot_views.bubble(a.room, a.mid, text, queued), 0, a.mid)
}

// chat stores the answer, the bubble's own last words, and the bubble goes as that arrives. A failed
// ask (""), stores nothing: only its asker heard of it.
@(private)
room_done :: proc(a: ^Room_Asking, text: string) {
	leave(a.who)
	if text != "" {
		bubble(a)
		hub.publish(fmt.tprintf("chat.reply:%d", a.room), text)
	}
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

