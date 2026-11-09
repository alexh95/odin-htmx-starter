package markdown

import "core:strings"
import "core:testing"
import "core:time"

// From spark's suite, with the game-docs paths now the caller's two prefixes.

@(private = "file")
OPTS :: Options{doc_prefix = "/wiki/", image_prefix = "/media/wiki/"}

@(private = "file")
md :: proc(src: string, shift := 0) -> string {
	b := strings.builder_make(context.temp_allocator)
	opts := OPTS
	opts.heading_shift = shift
	_, ok := render(&b, src, opts)
	assert(ok)
	return strings.to_string(b)
}

@(private = "file")
has :: proc(t: ^testing.T, out, want: string, loc := #caller_location) {
	testing.expectf(t, strings.contains(out, want), "missing %q in:\n%s", want, out, loc = loc)
}

@(private = "file")
lacks :: proc(t: ^testing.T, out, bad: string, loc := #caller_location) {
	testing.expectf(t, !strings.contains(out, bad), "unexpected %q in:\n%s", bad, out, loc = loc)
}

@(test)
headings_get_anchors_and_a_toc :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	toc, _ := render(&b, "# backpulse changelog\n\n## CL32 · 2026-10-19 · Playtest round 4\n\n## Weapons ##\n\n### Weapons\n", OPTS)
	out := strings.to_string(b)
	has(t, out, `<h1 id="backpulse-changelog">backpulse changelog</h1>`)
	has(t, out, `<h2 id="cl32-2026-10-19-playtest-round-4">`)
	has(t, out, `<h2 id="weapons">Weapons</h2>`)
	has(t, out, `<h3 id="weapons-2">Weapons</h3>`)
	testing.expect_value(t, len(toc), 4)
	testing.expect_value(t, toc[1].slug, "cl32-2026-10-19-playtest-round-4")
	// The game page shows a changelog entry one level down.
	has(t, md("## CL1\n- first", 1), `<h3 id="cl1">CL1</h3>`)
	// "#tag" without a space is a paragraph.
	has(t, md("#notaheading"), "<p>#notaheading</p>")
}

@(test)
paragraphs_emphasis_and_breaks :: proc(t: ^testing.T) {
	out := md("Some **bold** and *em* and _em too_, ~~old~~,\nsame paragraph  \nafter a break.\n\nNew one with snake_case_words and 2 * 3 * 4.")
	has(t, out, "<p>Some <strong>bold</strong> and <em>em</em> and <em>em too</em>, <del>old</del>, same paragraph<br>after a break.</p>")
	has(t, out, "<p>New one with snake_case_words and 2 * 3 * 4.</p>")
	has(t, md("*a **b** c*"), "<em>a <strong>b</strong> c</em>")
	has(t, md(`not \*em\*`), "not *em*")
}

@(test)
code_is_escaped_and_left_alone :: proc(t: ^testing.T) {
	out := md("Use `<b>**x**</b>` here.\n\n```odin\nif a < b && c {\n\t*p = 1\n}\n```\n")
	has(t, out, "<code>&lt;b&gt;**x**&lt;/b&gt;</code>")
	has(t, out, "<pre><code>if a &lt; b &amp;&amp; c {\n    *p = 1\n}</code></pre>")
}

@(test)
lists_nest_and_number :: proc(t: ^testing.T) {
	out := md("- one\n- two\n  - two a\n  - two b\n- three\n\n3. third\n4. fourth\n")
	has(t, out, "<ul><li>one</li><li>two<ul><li>two a</li><li>two b</li></ul>\n</li><li>three</li></ul>")
	has(t, out, `<ol start="3"><li>third</li><li>fourth</li></ol>`)
	// A rule isn't a list, and a list item can carry inline Markdown.
	has(t, md("---"), "<hr>")
	has(t, md("* **Siege cannon**: breaks walls"), "<ul><li><strong>Siege cannon</strong>: breaks walls</li></ul>")
}

@(test)
tables_align_and_escape :: proc(t: ^testing.T) {
	out := md("| Weapon | Damage | Notes |\n|:--|--:|:-:|\n| Cannon | 40 | `a|b` and \\| bar |\n| <i>x</i> | 5 |\n")
	has(t, out, `<table class="md-table"><thead><tr><th>Weapon</th><th class="al-r">Damage</th><th class="al-c">Notes</th></tr></thead>`)
	has(t, out, `<td>Cannon</td><td class="al-r">40</td><td class="al-c"><code>a|b</code> and | bar</td>`)
	has(t, out, `<td>&lt;i&gt;x&lt;/i&gt;</td><td class="al-r">5</td><td class="al-c"></td>`)
	// Without a separator row it's just text.
	has(t, md("a | b\nc | d"), "<p>a | b c | d</p>")
}

@(test)
links_go_only_where_they_may :: proc(t: ^testing.T) {
	has(t, md("[site](https://odin-lang.org/docs)"), `<a href="https://odin-lang.org/docs" rel="nofollow noopener" target="_blank">site</a>`)
	has(t, md("[weapons](weapons.md#cannon)"), `<a href="/wiki/weapons#cannon">weapons</a>`)
	has(t, md("[up](#top) and [home](/about)"), `<a href="#top">up</a> and <a href="/about">home</a>`)
	has(t, md("<https://example.org/a>"), `<a href="https://example.org/a" rel="nofollow noopener" target="_blank">https://example.org/a</a>`)
	for bad in ([]string{"javascript:alert(1)", "data:text/html,x", "//evil.example/x", "vbscript:x", "../../etc/passwd"}) {
		out := md(strings.concatenate({"[click](", bad, ")"}, context.temp_allocator))
		lacks(t, out, "<a ")
		has(t, out, "click")
	}
	// A url with parentheses is one url, kept or dropped whole.
	out := md("[a bad link](javascript:alert(1)) then [wiki](https://en.wikipedia.org/wiki/Tank_(disambiguation)).")
	has(t, out, "a bad link then ")
	lacks(t, out, "link) then")
	has(t, out, `href="https://en.wikipedia.org/wiki/Tank_(disambiguation)"`)
	// No links inside a link's text.
	lacks(t, md("[a [b](https://x.org) c](https://y.org)"), `href="https://x.org"`)
}

@(test)
images_only_from_the_image_prefix :: proc(t: ^testing.T) {
	has(t, md("![The Cannon](Cannon.PNG)"), `<img class="md-img" src="/media/wiki/cannon.png" alt="The Cannon" loading="lazy" decoding="async">`)
	for bad in ([]string{"https://evil.example/x.png", "../x.png", "x.svg", "data:image/png;base64,AAAA"}) {
		out := md(strings.concatenate({"![alt](", bad, ")"}, context.temp_allocator))
		lacks(t, out, "<img")
		has(t, out, "alt")
	}
}

@(test)
raw_html_is_text :: proc(t: ^testing.T) {
	out := md("<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\n> <b>quote</b>")
	lacks(t, out, "<script>")
	lacks(t, out, "<img src=x")
	has(t, out, "&lt;script&gt;alert(1)&lt;/script&gt;")
	has(t, out, "<blockquote><p>&lt;b&gt;quote&lt;/b&gt;</p>\n</blockquote>")
	// Attributes can't be broken out of either.
	lacks(t, md(`[x](https://a.org/"onmouseover="alert(1))`), `onmouseover="`)
}

@(test)
slugs_are_plain :: proc(t: ^testing.T) {
	testing.expect_value(t, slugify("CL32 · Playtest round 4"), "cl32-playtest-round-4")
	testing.expect_value(t, slugify("**Siege** cannon!"), "siege-cannon")
	testing.expect_value(t, slugify("···"), "section")
}

@(test)
without_prefixes_relative_links_and_images_are_text :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	render(&b, "[w](weapons.md) ![i](x.png) [a](/about)")
	out := strings.to_string(b)
	lacks(t, out, "/wiki/")
	lacks(t, out, "<img")
	has(t, out, `<p>w i <a href="/about">a</a></p>`)
}

@(test)
caps_hold :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	_, ok := render(&b, strings.repeat("x", MAX_INPUT + 1, context.temp_allocator))
	testing.expect(t, !ok)
	testing.expect_value(t, strings.builder_len(b), 0)
	// 200 nested quotes and 200 nested emphasis markers: escaped past the cap, no deep recursion.
	deep := strings.concatenate({strings.repeat("> ", 200, context.temp_allocator), "bottom"}, context.temp_allocator)
	out := md(deep)
	testing.expect_value(t, strings.count(out, "<blockquote>"), MAX_DEPTH)
	has(t, out, "bottom")
	stars := strings.concatenate({strings.repeat("*a ", 200, context.temp_allocator), "z", strings.repeat(" a*", 200, context.temp_allocator)}, context.temp_allocator)
	testing.expect(t, strings.count(md(stars), "<em>") < MAX_DEPTH)
}

// A model's text can be 64 KiB of anything, rendered on a loop on every page of the conversation
// (M7-07): no delimiter may cost a scan of the rest at each one. A wall that isn't quick outright
// must at least grow as its length: four times the text, four times the time, where a scan at each
// delimiter would take sixteen. The ratio holds on a slow runner under ASan beside the fuzz, where
// the clock alone didn't (a4c0b5a's nightly: "<" in 250 ms, and in 22 ms here without ASan).
@(test)
a_wall_of_delimiters_stays_linear :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for d in ([]string{"[", "![", "<", "*", "_", "~", "`", "](", "**", "[a](", "\\", ">"}) {
		small, large := wall_time(d, 16 * 1024), wall_time(d, 64 * 1024)
		ratio := f64(large) / max(f64(small), 1)
		testing.expectf(t, large < 200 * time.Millisecond || ratio <= 8, "%q took %v, %.1fx its quarter's %v", d, large, ratio, small)
	}
}

// The best of three, so a stall elsewhere in the process isn't the wall's.
@(private = "file")
wall_time :: proc(d: string, size: int) -> time.Duration {
	wall := strings.repeat(d, size / len(d), context.temp_allocator)
	best := max(time.Duration)
	for _ in 0 ..< 3 {
		b := strings.builder_make(context.temp_allocator)
		began := time.tick_now()
		render(&b, wall)
		best = min(best, time.tick_since(began))
	}
	return best
}
