package fakellama_suite

// ---- the llama binding against fakellama (PLAN §14.3) ------------------------------------------
//
// The binding on a real loop and a real socket: chunk boundaries inside `data:` lines and inside a
// rune, [DONE], an OAI error, 503 "Loading model", a refused key, a stall before the first token
// and between tokens, a dropped connection, Stop reaching the server as a close, the queue at one
// slot. No GPU: fakellama's faults, chosen by the question's first word.

import "base:runtime"
import "core:fmt"
import "core:nbio"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "../../../app/platform/guard"
import "../../../app/platform/obs"
import llama "../../../app/features/bot/backend_llama"
import m "../../../app/features/bot/models"
import fake "../fake"

@(private = "file")
Answer :: struct {
	text:     strings.Builder,
	done:     m.Bot_Done,
	error:    string,
	finished: bool,
	places:   [dynamic]int,
	events:   int,
}

@(private = "file")
hear :: proc(user: rawptr, _: m.Bot_Gen_Id, ev: m.Bot_Event) {
	a := (^Answer)(user)
	a.events += 1
	switch e in ev {
	case m.Bot_Token:  strings.write_string(&a.text, e.text)
	case m.Bot_Queued: append(&a.places, e.position)
	case m.Bot_Done:   a.done, a.finished = e, true
	case m.Bot_Error:  a.error, a.finished = strings.clone(e.message), true
	}
}

@(private = "file")
next_gen: u64

@(private = "file")
begin :: proc(a: ^Answer, question: string) -> m.Bot_Gen_Id {
	a^ = {}
	a.text = strings.builder_make()
	next_gen += 1
	id := m.Bot_Gen_Id(next_gen)
	req := m.Bot_Request{system = "Be brief.", history = {{.User, question}}, max_tokens = 64, temperature = 0.7}
	llama.start(req, {user = a, loop = nbio.current_thread_event_loop(), gen = id, on_event = hear})
	return id
}

@(private = "file")
settle :: proc(t: ^testing.T, a: ^Answer, within := 5 * time.Second, loc := #caller_location) {
	began := time.tick_now()
	for !a.finished && time.tick_since(began) < within { nbio.tick(5 * time.Millisecond) }
	testing.expect(t, a.finished, "the generation ended", loc = loc)
	for _ in 0 ..< 3 { nbio.tick(time.Millisecond) } // its free, and the next one's slot
}

@(private = "file")
ask :: proc(t: ^testing.T, question: string, loc := #caller_location) -> ^Answer {
	a := new(Answer)
	begin(a, question)
	settle(t, a, loc = loc)
	return a
}

@(private = "file")
wait_for :: proc(check: proc() -> bool, within := 3 * time.Second) -> bool {
	began := time.tick_now()
	for !check() && time.tick_since(began) < within { nbio.tick(5 * time.Millisecond) }
	return check()
}

@(test)
deltas_parse :: proc(t: ^testing.T) {
	d, ok := llama.parse_delta(`{"choices":[{"finish_reason":null,"index":0,"delta":{"content":"héllo \"x\"\n"}}]}`)
	testing.expectf(t, ok && d.content == "héllo \"x\"\n" && d.finish == "", "%v", d)
	d, ok = llama.parse_delta(`{"choices":[{"finish_reason":"length","delta":{}}],"timings":{"predicted_n":12,"predicted_ms":30.5}}`)
	testing.expectf(t, ok && d.finish == "length" && d.predicted == 12 && d.content == "", "%v", d)
	d, ok = llama.parse_delta(`{"choices":[{"delta":{"role":"assistant","content":null}}]}`)
	testing.expectf(t, ok && d.content == "", "%v", d)
	d, ok = llama.parse_delta(`{"choices":[],"usage":{"completion_tokens":3}}`)
	testing.expect(t, ok)
	d, ok = llama.parse_delta(`{"error":{"code":500,"message":"too long","type":"x"}}`)
	testing.expectf(t, ok && d.error == "too long", "%v", d)
	_, ok = llama.parse_delta(`{not json`)
	testing.expect(t, !ok)
	_, ok = llama.parse_delta(`[1,2]`)
	testing.expect(t, !ok)
	_, ok = llama.parse_delta(strings.repeat("[", 5000, context.temp_allocator))
	testing.expect(t, !ok, "a nesting bomb is refused before the parser recurses")
}

@(test)
urls_parse :: proc(t: ^testing.T) {
	h, p, ok := llama.parse_url("http://10.0.0.9:8088/")
	testing.expect(t, ok && h == "10.0.0.9" && p == 8088)
	h, p, ok = llama.parse_url("http://llama.lan:9000")
	testing.expect(t, ok && h == "llama.lan" && p == 9000)
	for bad in ([]string{"", "https://x:1", "http://x", "http://x:0", "http://x:99999", "http://x:1/v1", "ftp://x:1", "http://u@x:1"}) {
		_, _, ok = llama.parse_url(bad)
		testing.expectf(t, !ok, "%q is refused", bad)
	}
}

@(test)
props_parse :: proc(t: ^testing.T) {
	slots, sleeping, model := llama.read_props(`{"total_slots":4,"is_sleeping":true,"model_path":"/models/a/b.gguf"}`)
	testing.expect(t, slots == 4 && sleeping && model == "b.gguf")
	slots, sleeping, model = llama.read_props(`{"model_path":"c.gguf"}`)
	testing.expect(t, slots == 0 && !sleeping && model == "c.gguf")
	slots, _, _ = llama.read_props(`nonsense`)
	testing.expect_value(t, slots, 0)
}

@(test)
the_body_is_what_llama_reads :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	body := llama.body_of({system = `say "hi"`, history = {{.User, "a\nb"}, {.Assistant, "c"}, {.User, "d"}}, max_tokens = 7, temperature = 0.5, stop = {"END"}})
	defer delete(body, runtime.heap_allocator())
	want := `{"messages":[{"role":"system","content":"say \"hi\""},{"role":"user","content":"a\nb"},{"role":"assistant","content":"c"},{"role":"user","content":"d"}],"stream":true,"max_tokens":7,"temperature":0.50,"stop":["END"]}`
	testing.expect_value(t, body, want)
}

// One test: the fake, the binding and the slots are one process's state.
@(test)
against_fakellama :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, and the fake's threads
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, nbio.acquire_thread_event_loop(), nil)
	defer nbio.release_thread_event_loop()

	port, err := fake.start({key = "sekrit", slots = 1, delay = 2 * time.Millisecond})
	testing.expect_value(t, err, nil)
	defer fake.stop()
	os.set_env("BOT_LLAMA_URL", fmt.tprintf("http://127.0.0.1:%d", port))
	os.set_env("BOT_LLAMA_KEY", "sekrit")
	os.set_env("BOT_CONCURRENCY", "1")
	os.set_env("BOT_QUEUE", "2")
	os.set_env("BOT_LLAMA_FIRST_TOKEN", "300ms")
	os.set_env("BOT_LLAMA_IDLE", "300ms")
	llama.init()
	testing.expect(t, llama.configured())

	// An answer, its tokens coalesced, its stats llama's, its key sent and the question in the body.
	a := ask(t, "what is up")
	testing.expectf(t, a.error == "" && strings.to_string(a.text) == "You asked: what is up ", "%q %q", strings.to_string(a.text), a.error)
	testing.expectf(t, a.done.stop == .Eos && a.done.tokens == 5 && a.done.ms_total >= 0, "%v", a.done)
	testing.expect(t, strings.contains(fake.last_body(), `"content":"what is up"`))
	testing.expect_value(t, fake.stats().refused, 0)

	// Boundaries inside `data:` lines and inside a rune.
	a = ask(t, "fake:split rune")
	testing.expectf(t, a.done.stop == .Eos && strings.has_suffix(strings.to_string(a.text), "héllo wörld 🚀"), "%q", strings.to_string(a.text))

	a = ask(t, "fake:length x")
	testing.expect_value(t, a.done.stop, m.Bot_Stop.Length)

	// An error inside the stream, after words: what was said stands, marked.
	a = ask(t, "fake:error x")
	testing.expectf(t, a.done.stop == .Error && strings.to_string(a.text) == "You asked: ", "%v %q", a.done, strings.to_string(a.text))
	a = ask(t, "fake:garbage x")
	testing.expect_value(t, a.done.stop, m.Bot_Stop.Error)
	a = ask(t, "fake:drop x")
	testing.expect_value(t, a.done.stop, m.Bot_Stop.Error)

	// The deadlines, and the server hears each as a close.
	before := fake.stats().closed
	a = ask(t, "fake:stall x")
	testing.expectf(t, a.error == "The model didn't start answering in time.", "%q", a.error)
	a = ask(t, "fake:stall-mid x")
	testing.expectf(t, a.done.stop == .Error && strings.to_string(a.text) == "You asked: ", "%v", a.done)
	@(static) closed_at_least: i32
	closed_at_least = before + 2
	testing.expect(t, wait_for(proc() -> bool { return fake.stats().closed >= closed_at_least }), "both closes reached the server")

	// Loading: the question is refused, in words.
	fake.set_mode(.Loading)
	a = ask(t, "hello?")
	testing.expectf(t, a.error == "The model is still loading. Try again in a minute.", "%q", a.error)
	fake.set_mode(.Ready)

	// Stop: the answer ends with Stopped within the budget, keeps what it had, and the server
	// sees the socket go, which is what stops a real generation.
	b := new(Answer)
	id := begin(b, "fake:long x")
	for strings.builder_len(b.text) == 0 { nbio.tick(5 * time.Millisecond) }
	before = fake.stats().closed
	sent := time.tick_now()
	llama.cancel(id)
	settle(t, b)
	took := time.tick_since(sent)
	testing.expectf(t, b.done.stop == .Stopped && took < 100 * time.Millisecond, "%v in %v", b.done, took)
	closed_at_least = before + 1
	testing.expect(t, wait_for(proc() -> bool { return fake.stats().closed >= closed_at_least }), "Stop reached the server as a close")
	llama.cancel(id) // idempotent
	nbio.tick(time.Millisecond)

	// One slot: a second waits at #1, a third at #2, a fourth is refused; when the first
	// is stopped the second runs and the third hears #1; a queued one stops without running.
	testing.expect(t, wait_for(proc() -> bool { return fake.stats().busy == 0 }), "the slot came back")
	one, two, three, four := new(Answer), new(Answer), new(Answer), new(Answer)
	first := begin(one, "fake:long a")
	for strings.builder_len(one.text) == 0 { nbio.tick(5 * time.Millisecond) }
	begin(two, "second")
	third := begin(three, "third")
	begin(four, "fourth")
	testing.expectf(t, len(two.places) == 1 && two.places[0] == 1, "%v", two.places[:])
	testing.expectf(t, len(three.places) == 1 && three.places[0] == 2, "%v", three.places[:])
	testing.expectf(t, four.error == "The bot is busy. Try again in a minute.", "%q", four.error)
	h := llama.health()
	testing.expect(t, h.slots_busy == 1 && h.queued == 2)
	asked := fake.stats().requests
	llama.cancel(third)
	settle(t, three)
	testing.expectf(t, three.done.stop == .Stopped && three.done.tokens == 0, "%v", three.done)
	llama.cancel(first)
	settle(t, one)
	settle(t, two)
	testing.expectf(t, strings.to_string(two.text) == "You asked: second ", "%q", strings.to_string(two.text))
	testing.expectf(t, two.places[len(two.places) - 1] == 0, "a freed slot clears the line: %v", two.places[:])
	testing.expect_value(t, fake.stats().requests, asked + 1) // the second's; the third never ran
	testing.expect_value(t, fake.stats().peak, 1)
	h = llama.health()
	testing.expect(t, h.slots_busy == 0 && h.queued == 0)
}
