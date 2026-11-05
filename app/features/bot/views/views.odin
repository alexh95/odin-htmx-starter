package bot_views

// ---- bot: the views (PLAN §14.3, D31) -------------------------------------------------------
//
// A conversation is a live log, #c-log, of <article>s. An answer arrives in four frames,
// whatever carries them (an SSE answer to the form's POST, or a multipart one): the
// question and the answer's shell with its Stop button; the answer's text, escaped, into
// #mb-<mid> a piece at a time; the answer again, rendered as markdown with its stats, in
// place of the shell (outerMorph); the end. A live answer's mid is `g<gen>`, a stored
// one's its turn id.

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import bot ".."
import m "../models"

w :: html.w
esc :: html.esc

// ---- pages ------------------------------------------------------------------------------

// A member's: their conversations and a new one.
index_page :: proc(convs: []m.Conversation, health: m.Bot_Health) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Capcom", "Bot", "Ask the house assistant.")
	w(&b, `<section class="block bot-index"><p>`)
	health_badge(&b, health)
	w(&b, `</p><p class="muted">Nobody reads your conversations through this site. Whoever runs the server can read its database, and with a model behind the bot, what you ask goes to that model's machine.</p>`)
	w(&b, `<form class="bot-new" hx-post="/bot/c"><button class="btn btn-primary" type="submit">New conversation</button></form><ul class="bot-convs">`)
	for c in convs {
		fmt.sbprintf(&b, `<li><a href="/bot/c/%d">`, c.id)
		esc(&b, c.title)
		w(&b, `</a> <small class="muted">`)
		esc(&b, html.time_ago(c.at))
		w(&b, `</small></li>`)
	}
	if len(convs) == 0 { w(&b, `<li class="muted">None yet.</li>`) }
	w(&b, `</ul></section>`)
	return strings.to_string(b)
}

// A guest's: one question at a time, kept by no one, on the mock.
guest_page :: proc(health: m.Bot_Health, per_hour: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Capcom", "Bot", "Ask the house assistant.")
	w(&b, `<section class="block bot-room"><p>`)
	health_badge(&b, health)
	fmt.sbprintf(&b, ` <span class="muted">As a guest you get the mock, %d questions an hour, and nothing is kept. <a href="/login?next=/bot">Sign in</a> to keep conversations.</span></p>`, per_hour)
	w(&b, `<div id="c-log" class="bot-log" role="log" aria-label="Answers"></div>`)
	ask_form(&b, "/bot/ask")
	w(&b, `</section>`)
	return strings.to_string(b)
}

conversation_page :: proc(c: m.Conversation, turns: []m.Turn, health: m.Bot_Health, used, per_hour: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<section class="block bot-room"><header class="bot-head"><h1 id="conv-title">`)
	esc(&b, c.title)
	w(&b, `</h1>`)
	health_badge(&b, health)
	usage(&b, used, per_hour)
	w(&b, `<a class="bot-back" href="/bot">All conversations</a></header><div id="c-log" class="bot-log" role="log" aria-label="Conversation">`)
	for t in turns { turn(&b, t) }
	w(&b, `</div>`)
	ask_form(&b, fmt.tprintf("/bot/c/%d/ask", c.id))
	w(&b, `</section>`)
	return strings.to_string(b)
}

// The form, for either delivery; hx-pending echoes the question at once, and the button
// stays off until the answer's first words (`hx:release`) or its end.
@(private)
ask_form :: proc(b: ^strings.Builder, action: string) {
	w(b, `<form class="bot-ask" hx-post="`)
	esc(b, action)
	w(b, `" hx-target="#c-log" hx-swap="beforeend" hx-pending="#bot-pending" hx-disable="find button[type=submit]" hx-status:422="target:#ask-error swap:innerHTML" hx-status:429="target:#toasts swap:beforeend"`)
	html.behave(b, .Composer)
	fmt.sbprintf(b, `><textarea name="q" rows="2" maxlength="%d" required aria-label="Your question" placeholder="Ask something"></textarea>`, bot.MAX_QUESTION)
	w(b, `<div class="bot-ask-row"><label class="bot-delivery">Delivery <select name="delivery"><option value="sse">Streaming</option><option value="multipart">Multipart</option></select></label><button class="btn btn-primary" type="submit">Ask</button></div><p class="field-msg form-error" id="ask-error"></p></form>`)
	w(b, `<template id="bot-pending"><article class="bot-msg bot-q pending"><p class="bot-body"></p></article></template>`)
}

health_badge :: proc(b: ^strings.Builder, h: m.Bot_Health) {
	label: string
	switch h.state {
	case .Ready:    label = "Ready"
	case .Loading:  label = "Loading"
	case .Sleeping: label = "Sleeping"
	case .Offline:  label = "Offline"
	case .Mock:     label = "Mock"
	}
	fmt.sbprintf(b, `<span id="bot-health" class="badge bot-health bot-%s">`, label)
	esc(b, label)
	w(b, `</span>`)
}

usage :: proc(b: ^strings.Builder, used, per_hour: int) {
	fmt.sbprintf(b, `<span id="usage" class="muted bot-usage">%d of %d this hour</span>`, used, per_hour)
}

// ---- turns and the four frames -------------------------------------------------------------

// A stored turn.
turn :: proc(b: ^strings.Builder, t: m.Turn) {
	if t.role == .User {
		fmt.sbprintf(b, `<article id="m-%d" class="bot-msg bot-q"><p class="bot-body">`, t.id)
		esc(b, t.text)
		w(b, `</p></article>`)
		return
	}
	answer(b, fmt.tprintf("%d", t.id), t.text, t.stats)
}

// Frame 1: the question, and the answer's shell with Stop.
shell :: proc(question: string, mid: string, gen: m.Bot_Gen_Id) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<article class="bot-msg bot-q"><p class="bot-body">`)
	esc(&b, question)
	w(&b, `</p></article><article id="m-`)
	w(&b, mid)
	w(&b, `" class="bot-msg bot-a live"><div id="mb-`)
	w(&b, mid)
	fmt.sbprintf(&b, `" class="bot-body bot-stream"></div><p id="mq-`)
	w(&b, mid)
	fmt.sbprintf(&b, `" class="bot-queued muted"></p><button class="btn btn-ghost bot-stop" type="button" hx-post="/bot/gen/%d/stop" hx-swap="none">Stop</button></article>`, u64(gen))
	return strings.to_string(b)
}

// Frame 2: a piece of the answer, as text.
piece :: proc(mid, text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<hx-partial hx-target="#mb-`)
	w(&b, mid)
	w(&b, `" hx-swap="beforeend">`)
	esc(&b, text)
	w(&b, `</hx-partial>`)
	return strings.to_string(b)
}

// Waiting for a slot: position 0 clears the line.
queued :: proc(mid: string, position: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<hx-partial hx-target="#mq-`)
	w(&b, mid)
	w(&b, `" hx-swap="innerHTML">`)
	if position > 0 { fmt.sbprintf(&b, `Queued (#%d)`, position) }
	w(&b, `</hx-partial>`)
	return strings.to_string(b)
}

// Frame 3: the whole answer, rendered, in place of the shell.
final :: proc(mid, text: string, stats: m.Bot_Done) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<hx-partial hx-target="#m-`)
	w(&b, mid)
	w(&b, `" hx-swap="outerMorph">`)
	answer(&b, mid, text, stats)
	w(&b, `</hx-partial>`)
	return strings.to_string(b)
}

// A refusal or an error, in place of the shell.
failed :: proc(mid, message: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<hx-partial hx-target="#m-`)
	w(&b, mid)
	w(&b, `" hx-swap="outerMorph"><article id="m-`)
	w(&b, mid)
	w(&b, `" class="bot-msg bot-a bot-failed"><p class="bot-body">`)
	esc(&b, message)
	w(&b, `</p></article></hx-partial>`)
	return strings.to_string(b)
}

@(private)
answer :: proc(b: ^strings.Builder, mid, text: string, stats: m.Bot_Done) {
	w(b, `<article id="m-`)
	w(b, mid)
	w(b, `" class="bot-msg bot-a"><div class="bot-body md" hx-ignore data-disable-scripting>`)
	bot.render(b, text)
	w(b, `</div><p class="bot-stats muted">`)
	if stats.stop == .Stopped { w(b, `Stopped · `) }
	if stats.stop == .Error { w(b, `Cut off · `) }
	if stats.stop == .Length { w(b, `At the length limit · `) }
	fmt.sbprintf(b, `%d tokens · first token %d ms · %d ms</p></article>`, stats.tokens, stats.ms_first_token, stats.ms_total)
}
