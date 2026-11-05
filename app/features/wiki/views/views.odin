package wiki_views

// ---- wiki's pages ---------------------------------------------------------------------------

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import wiki ".."
import m "../models"

w :: html.w
esc :: html.esc

index :: proc(name: string, pages: []m.Page, may_edit: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, name, name, "Pages, and the starter's own manual.")
	w(&b, `<section class="block">`)
	if may_edit { w(&b, `<p><a class="btn btn-primary" href="/wiki/new">New page</a></p>`) }
	w(&b, `<ul class="wiki-pages">`)
	for p in pages {
		w(&b, `<li><a`)
		w(&b, html.BOOST)
		w(&b, ` hx-preload="mouseover" href="/wiki/`)
		esc(&b, p.slug)
		w(&b, `">`)
		esc(&b, p.title)
		w(&b, `</a>`)
		if p.manual { w(&b, ` <span class="tag">Manual</span>`) }
		if p.visibility == .Members { w(&b, ` <span class="tag">Members</span>`) }
		w(&b, `</li>`)
	}
	w(&b, `</ul>`)
	if len(pages) >= m.INDEX_LIMIT { w(&b, `<p class="muted">Only the first pages are listed. Search finds the rest.</p>`) }
	if len(pages) == 0 { w(&b, `<p class="muted">Nothing written yet.</p>`) }
	w(&b, `</section>`)
	return strings.to_string(b)
}

// A body lands in hx-ignore: it's a member's words, and D20 keeps htmx and hyperscript off them
// whatever the renderer lets through.
page :: proc(name: string, p: m.Page, may_edit: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, name, p.title, "Manual" if p.manual else "")
	w(&b, `<section class="block"><div class="wiki-actions">`)
	if may_edit && !p.manual {
		w(&b, `<a class="btn btn-outline" href="/wiki/`)
		esc(&b, p.slug)
		w(&b, `/edit">Edit</a> <a class="btn btn-outline" href="/wiki/`)
		esc(&b, p.slug)
		w(&b, `/history">History</a> `)
	}
	// hx-download saves the answer (its Content-Disposition is an attachment) instead of swapping it.
	w(&b, `<button class="btn btn-outline" type="button" hx-get="/wiki/`)
	esc(&b, p.slug)
	w(&b, `.md">Download</button></div><article class="wiki-body md" hx-ignore data-disable-scripting>`)
	w(&b, p.html) // platform/markdown's, which escaped everything it was given
	w(&b, `</article></section>`)
	return strings.to_string(b)
}

// New or existing: `p.rev` 0 is a new page, and `p.slug` where it posts.
editor :: proc(name: string, p: m.Page) -> string {
	b := strings.builder_make(context.temp_allocator)
	fresh := p.rev == 0
	html.page_head(&b, name, "New page" if fresh else p.title, "" if fresh else "Editing")
	w(&b, `<section class="block"><form class="wiki-editor" method="post" action="/wiki`)
	if !fresh {
		w(&b, `/`)
		esc(&b, p.slug)
	}
	w(&b, `" hx-post="/wiki`)
	if !fresh {
		w(&b, `/`)
		esc(&b, p.slug)
	}
	w(&b, `" hx-swap="none" hx-status:409="target:#wiki-conflict swap:innerHTML" hx-status:422="target:#wiki-error swap:innerHTML">`)
	rev_input(&b, p.rev, false)
	fmt.sbprintf(&b, `<label>Title <input id="wiki-title" name="title" required maxlength="%d" value="`, wiki.MAX_TITLE)
	esc(&b, p.title)
	w(&b, `"></label><label>Who reads it <select id="wiki-visibility" name="visibility">`)
	option(&b, "members", "Members", p.visibility == .Members || fresh)
	option(&b, "public", "Everyone", p.visibility == .Public && !fresh)
	w(&b, `</select></label><label>Text <textarea id="wiki-md" name="md" required rows="18" hx-post="/wiki/preview" hx-trigger="keyup changed delay:500ms" hx-target="#wiki-preview" hx-swap="innerHTML">`)
	esc(&b, p.md)
	w(&b, `</textarea></label><p class="field-msg form-error" id="wiki-error"></p><div id="wiki-conflict"></div>`)
	w(&b, `<button class="btn btn-primary" type="submit">Save</button></form><div id="wiki-preview" class="wiki-preview"></div></section>`)
	return strings.to_string(b)
}

@(private)
option :: proc(b: ^strings.Builder, value, label: string, selected: bool) {
	w(b, `<option value="`)
	w(b, value)
	w(b, `"`)
	if selected { w(b, ` selected`) }
	w(b, `>`)
	w(b, label)
	w(b, `</option>`)
}

@(private)
rev_input :: proc(b: ^strings.Builder, rev: i64, oob: bool) {
	fmt.sbprintf(b, `<input type="hidden" id="wiki-rev" name="rev" value="%d"%s>`, rev, ` hx-swap-oob="true"` if oob else "")
}

preview :: proc(rendered: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="wiki-body md" hx-ignore data-disable-scripting>`)
	w(&b, rendered)
	w(&b, `</div>`)
	return strings.to_string(b)
}

// Lines this far from a change are shown; the rest go.
DIFF_CONTEXT :: 2

diff_lines :: proc(b: ^strings.Builder, lines: []wiki.Diff_Line) {
	near := make([]bool, len(lines), context.temp_allocator)
	for l, i in lines {
		if l.kind == .Same { continue }
		for j in max(0, i - DIFF_CONTEXT) ..= min(len(lines) - 1, i + DIFF_CONTEXT) { near[j] = true }
	}
	w(b, `<pre class="wiki-diff">`)
	gap := false
	for l, i in lines {
		if !near[i] {
			if !gap { w(b, "<span class=\"muted\">…</span>\n") }
			gap = true
			continue
		}
		gap = false
		switch l.kind {
		case .Same: w(b, `<span>  `)
		case .Drop: w(b, `<del>- `)
		case .Add:  w(b, `<ins>+ `)
		}
		esc(b, l.text)
		switch l.kind {
		case .Same: w(b, "</span>\n")
		case .Drop: w(b, "</del>\n")
		case .Add:  w(b, "</ins>\n")
		}
	}
	w(b, `</pre>`)
}

// Saving over a newer revision: what changed under them, and the form armed to save over it.
conflict :: proc(current: m.Page, lines: []wiki.Diff_Line) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<p class="field-msg form-error">`)
	esc(&b, current.by)
	w(&b, ` saved this page while you were editing. From their text to yours:</p>`)
	diff_lines(&b, lines)
	w(&b, `<p class="muted">Save again to replace theirs.</p>`)
	rev_input(&b, current.rev, true)
	return strings.to_string(b)
}

history :: proc(name: string, p: m.Page, revisions: []m.Revision) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, name, p.title, "History")
	w(&b, `<section class="block"><ul class="wiki-pages"><li>Now: by `)
	esc(&b, p.by)
	fmt.sbprintf(&b, `, %s</li>`, html.time_ago(p.at))
	for r in revisions {
		w(&b, `<li><a href="/wiki/`)
		esc(&b, p.slug)
		fmt.sbprintf(&b, `/history/%d">Revision %d</a> by `, r.rev, r.rev)
		esc(&b, r.by)
		fmt.sbprintf(&b, `, %s</li>`, html.time_ago(r.at))
	}
	w(&b, `</ul>`)
	if len(revisions) == 0 { w(&b, `<p class="muted">Nothing has replaced the first text yet.</p>`) }
	w(&b, `</section>`)
	return strings.to_string(b)
}

revision :: proc(name: string, p: m.Page, r: m.Revision, lines: []wiki.Diff_Line) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, name, r.title, fmt.tprintf("Revision %d, to what followed it", r.rev))
	w(&b, `<section class="block">`)
	diff_lines(&b, lines)
	w(&b, `</section>`)
	return strings.to_string(b)
}
