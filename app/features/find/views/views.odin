package find_views

// ---- find's page and its results ------------------------------------------------------------------

import "core:strings"

import "../../../platform/html"
import find ".."

w :: html.w
esc :: html.esc

page :: proc(q: string, groups: []find.Group, failed: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Search", "Search", "Everything you can read here.")
	w(&b, `<section class="block"><form class="find-form" method="get" action="/find" role="search">`)
	box(&b, q, "find-results")
	w(&b, `<button class="btn btn-outline" type="submit">Search</button></form><div id="find-results">`)
	results(&b, q, groups, failed)
	w(&b, `</div></section>`)
	return strings.to_string(b)
}

// The search box: each keystroke replaces the last one's request. With no client it's a plain GET form.
box :: proc(b: ^strings.Builder, q, target: string) {
	w(b, `<input id="`)
	w(b, target)
	w(b, `-q" name="q" type="search" maxlength="200" autocomplete="off" aria-label="Search" placeholder="Search" value="`)
	esc(b, q)
	w(b, `" hx-get="/find/results" hx-trigger="input changed delay:200ms, search" hx-target="#`)
	w(b, target)
	w(b, `" hx-swap="innerHTML" hx-sync="this:replace">`)
}

results :: proc(b: ^strings.Builder, q: string, groups: []find.Group, failed: bool, pages: []html.Nav_Item = nil) {
	if failed { w(b, `<p class="field-msg form-error">Some of it can't be searched right now.</p>`) }
	if q != "" && len(groups) == 0 && len(pages) == 0 && !failed { w(b, `<p class="muted find-none">Nothing found.</p>`) }
	if len(pages) > 0 {
		w(b, `<section class="find-group"><h2>Go to</h2><ul class="find-hits">`)
		for p in pages {
			w(b, `<li><a`)
			w(b, html.BOOST)
			w(b, ` href="`)
			esc(b, p.href)
			w(b, `">`)
			esc(b, p.label)
			w(b, `</a></li>`)
		}
		w(b, `</ul></section>`)
	}
	for g in groups {
		w(b, `<section class="find-group"><h2>`)
		esc(b, g.source.name)
		w(b, `</h2><ul class="find-hits">`)
		for hit in g.hits {
			w(b, `<li><a href="`)
			esc(b, hit.href)
			w(b, `"`)
			if g.source.preload {
				w(b, html.BOOST)
				w(b, ` hx-preload="mouseover"`)
			}
			w(b, `>`)
			esc(b, hit.title)
			w(b, `</a><div class="find-snippet" hx-ignore data-disable-scripting>`)
			html.write_marked(b, hit.snippet)
			w(b, `</div></li>`)
		}
		w(b, `</ul></section>`)
	}
}
