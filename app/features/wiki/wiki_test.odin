package wiki

import "core:strings"
import "core:testing"

import "../../platform/markdown"

// The Manual is a list a person keeps: each entry has to fit, stay out of docs/private, and have
// something in it, or it's gone from every build with no word.
@(test)
the_manual_fits_and_renders :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	init("https://example.com/repo")
	total := 0
	for d in MANUAL {
		testing.expectf(t, d.text != "", "%s is empty", d.path)
		testing.expectf(t, len(d.text) <= markdown.MAX_INPUT, "%s is past the renderer's cap", d.path)
		testing.expectf(t, !strings.contains(d.path, "private"), "%s", d.path)
		p, ok := manual_page(d)
		testing.expectf(t, ok && p.html != "" && p.plain != "", "%s didn't render", d.path)
		testing.expectf(t, p.title != d.slug, "%s has no title", d.path)
		total += len(d.text)
	}
	testing.expectf(t, total <= 200 * 1024, "the Manual is %d bytes: full's size budget pays for it", total)
}

@(test)
a_repo_link_lands_on_its_page_or_on_github :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	init("https://example.com/repo")
	r, ok := render("[a](../PHILOSOPHY.md#why) [b](PLAN.md) [c](../../out.md) [d](DATA.md)", "docs/README.md")
	testing.expect(t, ok)
	testing.expectf(t, strings.contains(r.html, `href="/wiki/philosophy#why"`), "%s", r.html)
	testing.expectf(t, strings.contains(r.html, `href="https://example.com/repo/blob/master/docs/PLAN.md"`), "%s", r.html)
	testing.expectf(t, strings.contains(r.html, `href="/wiki/data"`), "%s", r.html)
	testing.expectf(t, !strings.contains(r.html, "out.md"), "out of the repo: text, %s", r.html)
}
