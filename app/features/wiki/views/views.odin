package wiki_views

// ---- wiki's pages ---------------------------------------------------------------------------

import "core:strings"

import "../../../platform/html"
import m "../models"

w :: html.w
esc :: html.esc

index :: proc(name: string, pages: []m.Page) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, name, name, "Pages, and the starter's own manual.")
	w(&b, `<section class="block"><ul class="wiki-pages">`)
	for p in pages {
		w(&b, `<li><a href="/wiki/`)
		esc(&b, p.slug)
		w(&b, `">`)
		esc(&b, p.title)
		w(&b, `</a>`)
		if p.manual { w(&b, ` <span class="tag">Manual</span>`) }
		if p.visibility == .Members { w(&b, ` <span class="tag">Members</span>`) }
		w(&b, `</li>`)
	}
	w(&b, `</ul>`)
	if len(pages) == 0 { w(&b, `<p class="muted">Nothing written yet.</p>`) }
	w(&b, `</section>`)
	return strings.to_string(b)
}

// A body lands in hx-ignore: it's a member's words, and D20 keeps htmx and hyperscript off them
// whatever the renderer lets through.
page :: proc(name: string, p: m.Page) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, name, p.title, "Manual" if p.manual else "")
	w(&b, `<section class="block"><article class="wiki-body md" hx-ignore data-disable-scripting>`)
	w(&b, p.html) // platform/markdown's, which escaped everything it was given
	w(&b, `</article></section>`)
	return strings.to_string(b)
}
