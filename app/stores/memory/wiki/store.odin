package wiki_store_memory

// ---- wiki in memory: `source_files` (PLAN §11.4) ----------------------------------------------
//
// The Manual alone, read-only: seeded once at boot and never touched again, so a reader needs no lock
// and no copy.

import "core:slice"
import "core:strings"

import m "../../../features/wiki/models"

IMPL :: "source_files"

@(private) pages: []m.Page

seed_manual :: proc(from: []m.Page) -> m.Error {
	pages = make([]m.Page, len(from))
	for p, i in from {
		pages[i] = p
		pages[i].slug = strings.clone(p.slug)
		pages[i].title = strings.clone(p.title)
		pages[i].md = strings.clone(p.md)
		pages[i].html = strings.clone(p.html)
		pages[i].plain = strings.clone(p.plain)
	}
	slice.sort_by(pages, proc(a, b: m.Page) -> bool { return a.title < b.title })
	return .None
}

page :: proc(slug: string) -> (m.Page, m.Error) {
	for p in pages {
		if p.slug == slug { return p, .None }
	}
	return {}, .Not_Found
}

// Nothing here can be written: `source_files` is the Manual. No route reaches it.
save :: proc(_: m.Save) -> (m.Page, bool, m.Error) { return {}, false, .Constraint }
history :: proc(_: string, _: ^[dynamic]m.Revision) -> m.Error { return .None }
revision :: proc(_: string, _: i64) -> (m.Revision, m.Error) { return {}, .Not_Found }

list :: proc(_: bool, out: ^[dynamic]m.Page) -> m.Error {
	for p in pages { append(out, m.Page{slug = p.slug, title = p.title, manual = p.manual, visibility = p.visibility}) }
	return .None
}
