package lists_views

// ---- lists' pages ---------------------------------------------------------------------------------
//
// One markup for both views: the columns, which CSS stacks for the checklist and sets side by side for the
// board, so a column fetched after a change fits either. Every move is a button with a form: dragging is the
// same POST, from the hidden form each column has.

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import lists ".."
import m "../models"

w :: html.w
esc :: html.esc

index :: proc(summaries: []m.Summary) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Lists", "Checklists", "Shared with everyone here, live.")
	w(&b, `<section class="block"><form class="lists-new" method="post" action="/lists"`)
	html.behave(&b, .Reset_On_Success)
	fmt.sbprintf(&b, `><input id="list-title" name="title" required maxlength="%d" aria-label="List title" placeholder="A new list"><select id="list-template" name="template" aria-label="Template">`, lists.MAX_TITLE)
	for t in lists.TEMPLATES {
		w(&b, `<option value="`)
		esc(&b, t.key)
		w(&b, `">`)
		esc(&b, t.name)
		w(&b, `</option>`)
	}
	w(&b, `</select><button class="btn btn-primary" type="submit">Create</button></form><ul class="lists-all">`)
	for s in summaries {
		fmt.sbprintf(&b, `<li><a href="/lists/%d">`, s.id)
		esc(&b, s.title)
		fmt.sbprintf(&b, `</a> <span class="muted">%d of %d open</span></li>`, s.open, s.total)
	}
	w(&b, `</ul>`)
	if len(summaries) == 0 { w(&b, `<p class="muted">No lists yet.</p>`) }
	w(&b, `</section>`)
	return strings.to_string(b)
}

page :: proc(l: m.List, board: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Lists", l.title, "")
	fmt.sbprintf(&b, `<section class="block"><p class="lists-views"><a class="btn btn-outline" href="/lists/%d">Checklist</a> <a class="btn btn-outline" href="/lists/%d?view=board">Board</a></p>`, l.id, l.id)
	first := l.columns[0].id if len(l.columns) > 0 else 0
	fmt.sbprintf(&b, `<form class="lists-add" method="post" action="/lists/%d/items" hx-post="/lists/%d/items" hx-target="#col-%d" hx-swap="none" hx-pending="#list-pending" hx-status:422="target:#list-error swap:innerHTML" hx-status:429="target:#toasts swap:beforeend"`, l.id, l.id, first)
	html.behave(&b, .Reset_On_Success)
	fmt.sbprintf(&b, `><input id="list-item" name="text" required maxlength="%d" autocomplete="off" aria-label="New item" placeholder="Add an item"><button class="btn btn-primary" type="submit">Add</button><p class="field-msg form-error" id="list-error"></p></form>`, lists.MAX_TEXT)
	w(&b, `<template id="list-pending"><li class="list-item muted">Adding…</li></template>`)
	fmt.sbprintf(&b, `<div class="list-columns%s">`, " list-board" if board else "")
	for c in l.columns { column_box(&b, l, c, board) }
	w(&b, `</div></section>`)
	return strings.to_string(b)
}

// The stream's frame only says a column changed: a whole one can pass the hub's 64 KiB, and each reader
// fetching it costs a household nothing. `#stale-<col>` sits beside the column, so the swap doesn't remove the
// element doing the fetching mid-request.
changed :: proc(list_id, col: i64) -> string {
	return fmt.tprintf(`<hx-partial hx-target="#stale-%d" hx-swap="innerHTML"><i hx-get="/lists/%d/columns/%d" hx-trigger="load" hx-target="#col-%d" hx-swap="outerHTML"></i></hx-partial>`, col, list_id, col, col)
}

// A column, as a partial for whoever acted: what they did shows at once, the stream or no.
column_partial :: proc(b: ^strings.Builder, l: m.List, c: m.Column) {
	fmt.sbprintf(b, `<hx-partial hx-target="#col-%d" hx-swap="outerHTML">`, c.id)
	column(b, l, c)
	w(b, `</hx-partial>`)
}

@(private)
column_box :: proc(b: ^strings.Builder, l: m.List, c: m.Column, board: bool) {
	w(b, `<section class="list-column`)
	if c.closes { w(b, ` list-closing`) }
	w(b, `"`)
	if board { html.behave(b, .Drop_Zone) }
	w(b, `><h2>`)
	esc(b, c.name)
	fmt.sbprintf(b, `</h2><span id="stale-%d" hidden></span>`, c.id)
	if board {
		// What a drop fills in and submits: the same POST as the buttons.
		fmt.sbprintf(b, `<form class="list-drop" hidden hx-post="/lists/%d/move" hx-swap="none"><input type="hidden" name="item"><input type="hidden" name="col" value="%d"><input type="hidden" name="after"></form>`, l.id, c.id)
	}
	column(b, l, c)
	w(b, `</section>`)
}

column :: proc(b: ^strings.Builder, l: m.List, c: m.Column) {
	fmt.sbprintf(b, `<ul id="col-%d" class="list-items" data-col="%d">`, c.id, c.id)
	for it, i in c.items { item(b, l, c, it, i) }
	w(b, `</ul>`)
}

@(private)
act :: proc(b: ^strings.Builder, l: m.List, path: string, label, text: string, fields: string = "") {
	fmt.sbprintf(b, `<form class="list-act" method="post" action="/lists/%d%s" hx-post="/lists/%d%s" hx-swap="none">%s<button class="btn btn-outline btn-sm" type="submit" aria-label="`, l.id, path, l.id, path, fields)
	esc(b, label)
	w(b, `">`)
	w(b, text)
	w(b, `</button></form>`)
}

@(private)
move_fields :: proc(it: m.Item, col, after: i64) -> string {
	return fmt.tprintf(`<input type="hidden" name="item" value="%d"><input type="hidden" name="col" value="%d"><input type="hidden" name="after" value="%d">`, it.id, col, after)
}

@(private)
item :: proc(b: ^strings.Builder, l: m.List, c: m.Column, it: m.Item, i: int) {
	fmt.sbprintf(b, `<li id="li-%d" class="list-item" data-item="%d" data-pos="%012d" draggable="true"`, it.id, it.id, it.pos)
	html.behave(b, .Draggable)
	w(b, `><span class="list-text">`)
	esc(b, it.text)
	w(b, `</span>`)
	if it.assignee_name != "" {
		w(b, ` <span class="tag">`)
		esc(b, it.assignee_name)
		w(b, `</span>`)
	}
	w(b, `<span class="list-acts">`)
	act(b, l, fmt.tprintf("/items/%d/toggle", it.id), "Reopen" if c.closes else "Done", "↩" if c.closes else "✓")
	if i > 0 {
		above: i64 = c.items[i - 2].id if i > 1 else 0
		act(b, l, "/move", "Up", "↑", move_fields(it, c.id, above))
	}
	if i < len(c.items) - 1 { act(b, l, "/move", "Down", "↓", move_fields(it, c.id, c.items[i + 1].id)) }
	for other, k in l.columns {
		if other.id != c.id { continue }
		if k > 0 { act(b, l, "/move", "Left", "←", move_fields(it, l.columns[k - 1].id, -1)) }
		if k < len(l.columns) - 1 { act(b, l, "/move", "Right", "→", move_fields(it, l.columns[k + 1].id, -1)) }
	}
	fmt.sbprintf(b, `<form class="list-act" method="post" action="/lists/%d/items/%d/assign" hx-post="/lists/%d/items/%d/assign" hx-trigger="change" hx-swap="none"><select name="who" aria-label="Who has it"><option value="0">Nobody</option>`, l.id, it.id, l.id, it.id)
	for p in l.people {
		fmt.sbprintf(b, `<option value="%d"%s>`, p.id, " selected" if p.id == it.assignee else "")
		esc(b, p.name)
		w(b, `</option>`)
	}
	w(b, `</select></form>`)
	act(b, l, fmt.tprintf("/items/%d/delete", it.id), "Delete", "×")
	w(b, `</span></li>`)
}
