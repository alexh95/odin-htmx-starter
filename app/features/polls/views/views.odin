package polls_views

// ---- polls' pages ---------------------------------------------------------------------------------
//
// A page has two parts: `#poll-bars-<id>`, which reads the same for everyone and follows the stream, and
// `#poll-act-<id>`, which is the viewer's own and is left alone, so a vote landing elsewhere can't wipe a half-ticked
// form. On an anonymous poll the second never says what the viewer chose: it can't, the store doesn't know.

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import polls ".."
import m "../models"

w :: html.w
esc :: html.esc

// Alex's terms (Q36), and what a reader can check for themself: no more than the store does.
ANONYMOUS_NOTE :: "Votes on this poll aren't stored with names, and a vote can't be changed. With one voter, or where everyone agrees, the bars show how people voted anyway. Whoever changes this server's code could log votes from then on."
NAMED_NOTE :: "Everyone can see who chose what, and you can change your vote until the poll closes."

index :: proc(all: []m.Summary) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Polls", "Go/No-go", "Ask everyone here, and watch the answers land.")
	w(&b, `<section class="block"><form class="polls-new" method="post" action="/polls" hx-post="/polls" hx-swap="none" hx-status:422="target:#poll-error swap:innerHTML" hx-status:429="target:#toasts swap:beforeend">`)
	fmt.sbprintf(&b, `<label for="poll-question">Question</label><input id="poll-question" name="question" required maxlength="%d" autocomplete="off">`, polls.MAX_QUESTION)
	w(&b, `<label for="poll-kind">Answers</label><select id="poll-kind" name="kind"><option value="go">Go or No-go</option><option value="options">These options</option></select>`)
	w(&b, `<label for="poll-options">Options, one a line</label><textarea id="poll-options" name="options" rows="4"></textarea>`)
	w(&b, `<label for="poll-closes">Closes</label><select id="poll-closes" name="closes">`)
	for c in polls.CLOSINGS {
		fmt.sbprintf(&b, `<option value="%s"%s>`, c.key, " selected" if c.key == "1h" else "")
		esc(&b, c.label)
		w(&b, `</option>`)
	}
	w(&b, `</select><label class="polls-check"><input id="poll-multiple" type="checkbox" name="multiple" value="1"> More than one option can be chosen</label>`)
	w(&b, `<label class="polls-check"><input id="poll-anonymous" type="checkbox" name="anonymous" value="1"> Anonymous: votes aren't stored with names and can't be changed. This can't be undone.</label>`)
	w(&b, `<button class="btn btn-primary" type="submit">Ask</button><p class="field-msg form-error" id="poll-error"></p></form>`)
	w(&b, `<ul class="polls-all">`)
	for s in all {
		fmt.sbprintf(&b, `<li><a href="/polls/%d">`, s.id)
		esc(&b, s.question)
		fmt.sbprintf(&b, `</a> <span class="muted">%d voted%s%s</span></li>`, s.voters, ", anonymous" if s.anonymous else "", ", closed" if s.closed else "")
	}
	w(&b, `</ul>`)
	if len(all) == 0 { w(&b, `<p class="muted">No polls yet.</p>`) }
	w(&b, `</section>`)
	return strings.to_string(b)
}

page :: proc(p: m.Poll, me: u64) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Polls", p.question, "")
	w(&b, `<section class="block">`)
	w(&b, `<p class="muted poll-note">`)
	esc(&b, ANONYMOUS_NOTE if p.anonymous else NAMED_NOTE)
	w(&b, `</p>`)
	bars(&b, p)
	act(&b, p, me)
	fmt.sbprintf(&b, `<span id="poll-stale-%d" hidden></span></section>`, p.id)
	return strings.to_string(b)
}

// The stream's frame only says the poll changed, and each page fetches its bars: two votes' frames could
// otherwise pass each other and leave a page a vote behind for good.
changed :: proc(id: i64) -> string {
	return fmt.tprintf(`<hx-partial hx-target="#poll-stale-%d" hx-swap="innerHTML"><i hx-get="/polls/%d/results" hx-trigger="load" hx-swap="none"></i></hx-partial>`, id, id)
}

// What the stream's fetch swaps in: the bars, and once it's closed the form goes.
results :: proc(p: m.Poll, me: u64) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `<hx-partial hx-target="#poll-bars-%d" hx-swap="outerHTML">`, p.id)
	bars(&b, p)
	w(&b, `</hx-partial>`)
	if p.closed { act_partial(&b, p, me) }
	return strings.to_string(b)
}

// What a voter gets back, the stream or no.
voted :: proc(p: m.Poll, me: u64) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `<hx-partial hx-target="#poll-bars-%d" hx-swap="outerHTML">`, p.id)
	bars(&b, p)
	w(&b, `</hx-partial>`)
	act_partial(&b, p, me)
	return strings.to_string(b)
}

@(private)
act_partial :: proc(b: ^strings.Builder, p: m.Poll, me: u64) {
	fmt.sbprintf(b, `<hx-partial hx-target="#poll-act-%d" hx-swap="outerHTML">`, p.id)
	act(b, p, me)
	w(b, `</hx-partial>`)
}

@(private)
bars :: proc(b: ^strings.Builder, p: m.Poll) {
	fmt.sbprintf(b, `<div id="poll-bars-%d" class="poll-bars">`, p.id)
	for o in p.options {
		share := o.n * 100 / p.voters if p.voters > 0 else 0
		fmt.sbprintf(b, `<div class="poll-row" data-option="%d"><span class="poll-label">`, o.id)
		esc(b, o.label)
		fmt.sbprintf(b, `</span><span class="poll-n">%d</span><span class="poll-bar" style="--p:%d%%"></span>`, o.n, share)
		if len(o.names) > 0 {
			w(b, `<span class="poll-names muted">`)
			for name, i in o.names {
				if i > 0 { w(b, `, `) }
				esc(b, name)
			}
			w(b, `</span>`)
		}
		w(b, `</div>`)
	}
	fmt.sbprintf(b, `<p class="muted poll-count">%d voted</p></div>`, p.voters)
}

@(private)
is_mine :: proc(p: m.Poll, option: i64) -> bool {
	for id in p.mine {
		if id == option { return true }
	}
	return false
}

@(private)
act :: proc(b: ^strings.Builder, p: m.Poll, me: u64) {
	fmt.sbprintf(b, `<div id="poll-act-%d" class="poll-act">`, p.id)
	switch {
	case p.closed:
		w(b, `<p class="poll-state">This poll has closed.`)
		if p.voted { w(b, ` You voted.`) }
		w(b, `</p></div>`)
		return
	case p.voted && p.anonymous:
		w(b, `<p class="poll-state">You voted.</p>`)
	case:
		form(b, p)
	}
	if p.by == me {
		fmt.sbprintf(b, `<form class="poll-close" method="post" action="/polls/%d/close" hx-post="/polls/%d/close" hx-swap="none"><button class="btn btn-outline" type="submit">Close now</button></form>`, p.id, p.id)
	}
	w(b, `</div>`)
}

@(private)
form :: proc(b: ^strings.Builder, p: m.Poll) {
	fmt.sbprintf(b, `<form class="poll-vote" method="post" action="/polls/%d/vote" hx-post="/polls/%d/vote" hx-target="#poll-error-%d" hx-swap="none" hx-pending="#poll-pending" hx-status:409="target:#poll-error-%d swap:innerHTML" hx-status:422="target:#poll-error-%d swap:innerHTML" hx-status:429="target:#toasts swap:beforeend">`, p.id, p.id, p.id, p.id, p.id)
	for o in p.options {
		w(b, `<label class="polls-check">`)
		fmt.sbprintf(b, `<input type="%s" name="option" value="%d"%s> `, "checkbox" if p.multiple else "radio", o.id, " checked" if is_mine(p, o.id) else "")
		esc(b, o.label)
		w(b, `</label>`)
	}
	if p.voted { w(b, `<p class="poll-state">You voted.</p>`) }
	fmt.sbprintf(b, `<button class="btn btn-primary" type="submit">%s</button><p class="field-msg form-error" id="poll-error-%d"></p></form>`, "Change vote" if p.voted else "Vote", p.id)
	w(b, `<template id="poll-pending"><p class="muted">Sending…</p></template>`)
}
