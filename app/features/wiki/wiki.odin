package wiki

// ---- wiki: pages, and the starter's docs as its Manual (PLAN §6, D36) ------------------------
//
// Markdown is rendered once, when written or at boot, and the HTML kept, so a view never parses.
// The Manual is the list below and only that: a directory walk would take docs/private into a build
// on any PC that has it. Each entry fits markdown.MAX_INPUT, and the whole list `full`'s size budget,
// so PLAN and DECISIONS stay on GitHub, linked from the docs that name them.

import "core:fmt"
import "core:path/slashpath"
import "core:strings"

import "../../platform/authz"
import "../../platform/escape"
import "../../platform/markdown"
import "../../platform/obs"
import m "models"
import wiki_store "store:wiki"

IMPL :: wiki_store.IMPL

Doc :: struct {
	slug, path, text: string,
}

MANUAL := [?]Doc {
	{"readme", "README.md", #load("../../../README.md", string)},
	{"philosophy", "PHILOSOPHY.md", #load("../../../PHILOSOPHY.md", string)},
	{"guide", "docs/README.md", #load("../../../docs/README.md", string)},
	{"brief", "docs/BRIEF.md", #load("../../../docs/BRIEF.md", string)},
	{"use-cases", "docs/USE_CASES.md", #load("../../../docs/USE_CASES.md", string)},
	{"data", "docs/DATA.md", #load("../../../docs/DATA.md", string)},
	{"parity", "docs/perf/PARITY.md", #load("../../../docs/perf/PARITY.md", string)},
	{"tour", "app/README.md", #load("../../../app/README.md", string)},
	{"working-here", "CLAUDE.md", #load("../../../CLAUDE.md", string)},
	{"e2e", "e2e/README.md", #load("../../../e2e/README.md", string)},
	{"load-tests", "load-tests/README.md", #load("../../../load-tests/README.md", string)},
}

MAX_TITLE :: 120 // runes
MAX_SLUG :: 64 // bytes
// Each row under /wiki that a page can't take the name of.
RESERVED := [?]string{"new", "preview"}

@(private) repo: string

// `repository`: where a link to a file that isn't in the Manual goes.
init :: proc(repository: string) {
	repo = repository
}

// Renders the Manual and hands it to the store: after the migrations.
seed :: proc() {
	pages := make([dynamic]m.Page, 0, len(MANUAL), context.temp_allocator)
	for d in MANUAL {
		if p, ok := manual_page(d); ok { append(&pages, p) } // wiki_test holds that each is
	}
	if err := wiki_store.seed_manual(pages[:]); err != .None {
		if l, ok := obs.begin(.Error, "wiki", "manual"); ok {
			obs.str(&l, "err", fmt.tprint(err))
			obs.end(&l)
		}
	}
}

manual_page :: proc(d: Doc) -> (p: m.Page, ok: bool) {
	r := render(d.text, d.path) or_return
	return {slug = d.slug, title = r.title if r.title != "" else d.slug, manual = true, md = d.text, html = r.html, plain = r.plain}, true
}

Rendered :: struct {
	html, plain, title: string,
}

// A page's table of contents is worth having from this many headings.
TOC_MIN :: 3

// Its strings in the temp allocator. `path`: the Manual doc's, whose links are the repo's; "" for a
// member's page, where `[x](name.md)` is another page. false: past markdown's input cap.
render :: proc(src, path: string) -> (r: Rendered, ok: bool) {
	body := strings.builder_make(context.temp_allocator)
	opts := markdown.Options{doc_prefix = "/wiki/"}
	if path != "" { opts = {link = doc_link, base = path} }
	toc := markdown.render(&body, src, opts) or_return
	b := strings.builder_make(context.temp_allocator)
	if len(toc) >= TOC_MIN {
		escape.w(&b, `<nav class="wiki-toc" aria-label="On this page"><ul>`)
		for e in toc {
			if e.level > 2 { continue }
			fmt.sbprintf(&b, `<li><a href="#%s">`, e.slug)
			escape.esc(&b, e.text)
			escape.w(&b, `</a></li>`)
		}
		escape.w(&b, `</ul></nav>`)
	}
	escape.w(&b, strings.to_string(body))
	r.html = strings.to_string(b)
	r.plain = markdown.plain(src)
	if len(toc) > 0 && toc[0].level == 1 { r.title = toc[0].text }
	return r, true
}

// A repo-relative link in a Manual page: to the page holding that file, or to the file on GitHub.
@(private = "file")
doc_link :: proc(base, url: string) -> (href: string, external: bool) {
	file, frag := url, ""
	if h := strings.index_byte(url, '#'); h >= 0 { file, frag = url[:h], url[h:] }
	dir, _ := slashpath.split(base)
	path := slashpath.join({dir, file}, context.temp_allocator)
	if strings.has_prefix(path, "..") { return "", false } // out of the repo
	for d in MANUAL {
		if d.path == path { return fmt.tprintf("/wiki/%s%s", d.slug, frag), false }
	}
	if repo == "" { return "", false }
	return fmt.tprintf("%s/blob/master/%s%s", repo, path, frag), true
}

// A members' page is no guest's: its existence included.
may_read :: proc(p: m.Page, v: authz.Viewer) -> bool {
	return p.visibility == .Public || v.id != 0
}

page :: proc(slug: string, v: authz.Viewer) -> (m.Page, m.Error) {
	p, err := wiki_store.page(slug)
	if err != .None { return {}, err }
	if !may_read(p, v) { return {}, .Not_Found }
	return p, .None
}

list :: proc(v: authz.Viewer, out: ^[dynamic]m.Page) -> m.Error {
	return wiki_store.list(v.id != 0, out)
}

// Why a page can't be saved as this; "" when it can. `fresh`: a new page, which its title names.
check :: proc(title, md: string, fresh: bool) -> string {
	switch {
	case strings.trim_space(title) == "":
		return "A page needs a title."
	case strings.rune_count(title) > MAX_TITLE:
		return fmt.tprintf("A title is at most %d characters.", MAX_TITLE)
	case strings.trim_space(md) == "":
		return "A page needs something in it."
	case len(md) > markdown.MAX_INPUT:
		return fmt.tprintf("A page is at most %d KiB.", markdown.MAX_INPUT / 1024)
	}
	if fresh {
		slug := slug_of(title)
		if slug == "" { return "A title needs a letter or a digit in it." }
		for r in RESERVED {
			if r == slug { return "That title is taken." }
		}
		for d in MANUAL {
			if d.slug == slug { return "That title is taken." }
		}
	}
	return ""
}

slug_of :: proc(title: string) -> string {
	s := markdown.slugify(title)
	if len(s) > MAX_SLUG { s = strings.trim_right(s[:MAX_SLUG], "-") }
	return s
}

// A save, off the loop: renders, then writes. .Constraint on a new page: its slug is taken.
save :: proc(v: authz.Viewer, slug, title, md: string, visibility: m.Visibility, base_rev: i64) -> (current: m.Page, conflict: bool, err: m.Error) {
	r, ok := render(md, "")
	if !ok { return {}, false, .Constraint }
	return wiki_store.save({
		slug = slug if slug != "" else slug_of(title), title = strings.trim_space(title), md = md, html = r.html, plain = r.plain,
		visibility = visibility, base_rev = base_rev, by = v.name,
	})
}

history :: proc(slug: string, out: ^[dynamic]m.Revision) -> m.Error { return wiki_store.history(slug, out) }
revision :: proc(slug: string, rev: i64) -> (m.Revision, m.Error) { return wiki_store.revision(slug, rev) }
