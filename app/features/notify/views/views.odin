package notify_views

// ---- notify: the views (PLAN §14.2) --------------------------------------------------------
//
// The Inbox is a live log (§9.1): <div role="log"> of <article id="n-<id>">, in the
// page's first markup, which notify.user:<id> on the layout's #live fills from the
// top. Every count on a page is a `.notify-count`, which a push updates all at once
// by an out-of-band swap on the class.

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import m "../models"

w :: html.w
esc :: html.esc

page :: proc(list: []m.Item, unread: int, muted: []string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Inbox", "Notifications", "Mentions, direct messages and replies, as they happen.")
	w(&b, `<section class="block notify"><div class="notify-head"><p><span class="notify-count">`)
	strings.write_int(&b, unread)
	w(&b, `</span> unread</p><form hx-post="/notify/read" hx-target="#notify-list" hx-swap="innerHTML"><button class="btn btn-outline" type="submit">Mark all read</button></form></div>`)
	log(&b, list)
	if len(muted) > 0 {
		w(&b, `<h2>Muted</h2><ul class="notify-muted">`)
		for key in muted {
			w(&b, `<li>`)
			esc(&b, key)
			w(&b, ` `)
			mute_form(&b, key, false, "Unmute")
			w(&b, `</li>`)
		}
		w(&b, `</ul>`)
	}
	w(&b, `</section>`)
	return strings.to_string(b)
}

// Mutes or unmutes `key`, a kind or a producer's scope: its button, wherever a page offers it.
mute_form :: proc(b: ^strings.Builder, key: string, on: bool, label: string) {
	w(b, `<form class="notify-mute" hx-post="/notify/mute" hx-swap="none"><input type="hidden" name="key" value="`)
	esc(b, key)
	fmt.sbprintf(b, `"><input type="hidden" name="on" value="%s"><button class="btn btn-ghost" type="submit">`, "1" if on else "0")
	esc(b, label)
	w(b, `</button></form>`)
}

// The log alone: the page's, and what a resync refetches (hx-trigger on the log).
log :: proc(b: ^strings.Builder, list: []m.Item) {
	w(b, `<div id="notify-list" class="notify-list" role="log" aria-label="Notifications" hx-get="/notify/list" hx-trigger="resync from:body" hx-swap="innerHTML">`)
	items(b, list)
	w(b, `</div>`)
}

items :: proc(b: ^strings.Builder, list: []m.Item) {
	if len(list) == 0 {
		w(b, `<p class="muted notify-empty">Nothing yet.</p>`)
		return
	}
	for it in list { item(b, it) }
}

// One notification. Its line is the producer's escaped fragment; the link is a path
// on this site, which notify.check holds a producer to.
item :: proc(b: ^strings.Builder, it: m.Item) {
	fmt.sbprintf(b, `<article id="n-%d" class="notify-item%s" data-kind="`, it.id, "" if it.read else " unread")
	esc(b, it.kind)
	w(b, `">`)
	if it.ref != "" {
		w(b, `<a class="notify-line" href="`)
		esc(b, it.ref)
		w(b, `">`)
		w(b, it.html)
		w(b, `</a>`)
	} else {
		w(b, `<p class="notify-line">`)
		w(b, it.html)
		w(b, `</p>`)
	}
	w(b, `<small class="muted">`)
	esc(b, html.time_ago(it.at))
	w(b, `</small>`)
	mute_form(b, it.kind, true, "Mute these")
	w(b, `</article>`)
}

// The push for one new item: into the top of the log, and every count (§9.1: OOB
// HTML on unnamed events). The empty-state line goes once there is one.
pushed :: proc(it: m.Item, unread: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div hx-swap-oob="afterbegin:#notify-list">`)
	item(&b, it)
	w(&b, `</div><span hx-swap-oob="innerHTML:.notify-count">`)
	strings.write_int(&b, unread)
	w(&b, `</span><span hx-swap-oob="delete:.notify-empty"></span>`)
	return strings.to_string(b)
}

// The home page's card: the count and the newest few.
card :: proc(b: ^strings.Builder, list: []m.Item, unread: int) {
	w(b, `<section class="block"><article class="card notify-card"><h2><a href="/notify">Inbox</a> <span class="badge notify-count">`)
	strings.write_int(b, unread)
	w(b, `</span></h2>`)
	if len(list) == 0 {
		w(b, `<p class="muted">Nothing yet. Mentions in chat land here.</p>`)
	} else {
		w(b, `<ul class="notify-few">`)
		for it in list[:min(3, len(list))] {
			w(b, `<li>`)
			w(b, it.html)
			w(b, `</li>`)
		}
		w(b, `</ul>`)
	}
	w(b, `</article></section>`)
}
