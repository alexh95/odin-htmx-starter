package markdown

// ---- the markdown campaign (D44, §19.1.3) ------------------------------------------------------
//
// A wiki page is a member's text, rendered once and served to everyone, so what must hold is the output's:
// whatever went in, no tag this renderer doesn't write, every tag closed in order, no href off its list.
// The shapes below are what a recursive renderer dies of, at the input cap.

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:time"

import "../fuzz"

@(private = "file")
ALPHABET :: "abc 123\n\n\n\t>>>---***___```~~~###|||[[]]()()!!<>&\"'\\:/.#=+-  1. - * > ```\n| a | b |\n|---|---|\n[x](http://a.b) ![y](z.png) **b** _i_ `c` <script> javascript: "

@(private = "file")
VOID := [?]string{"br", "hr", "img"}
@(private = "file")
TAGS := [?]string{
	"a", "blockquote", "br", "code", "del", "div", "em", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "img", "li", "ol", "p", "pre", "strong", "table", "tbody", "td", "th", "thead", "tr", "ul",
}

@(private = "file")
has :: proc(list: []string, s: string) -> bool {
	for x in list {
		if x == s { return true }
	}
	return false
}

// Why `out` is wrong, or "". Attribute values are escaped, so a `>` or `<` in one is an entity.
@(private = "file")
inspect :: proc(out: string) -> string {
	open := make([dynamic]string, context.temp_allocator)
	i := 0
	for i < len(out) {
		if out[i] != '<' {
			i += 1
			continue
		}
		end := strings.index_byte(out[i:], '>')
		if end < 0 { return "a < with no >: not escaped" }
		tag := out[i + 1:i + end]
		i += end + 1
		closing := strings.has_prefix(tag, "/")
		if closing { tag = tag[1:] }
		name := tag
		attrs := ""
		if sp := strings.index_byte(tag, ' '); sp >= 0 { name, attrs = tag[:sp], tag[sp:] }
		name = strings.trim_right(name, "/")
		if !has(TAGS[:], name) { return fmt.tprintf("a tag it doesn't write: <%s>", tag) }
		if closing {
			if len(open) == 0 || open[len(open) - 1] != name { return fmt.tprintf("</%s> out of order", name) }
			pop(&open)
		} else if !has(VOID[:], name) && !strings.has_suffix(tag, "/") {
			append(&open, name)
		}
		if strings.contains(strings.to_lower(attrs, context.temp_allocator), " on") { return fmt.tprintf("a handler: <%s>", tag) }
		rest := attrs
		for {
			at := strings.index(rest, `href="`)
			if at < 0 { break }
			rest = rest[at + 6:]
			href := rest[:strings.index_byte(rest, '"')]
			ok := strings.has_prefix(href, "http://") || strings.has_prefix(href, "https://") || strings.has_prefix(href, "mailto:") || strings.has_prefix(href, "#") || strings.has_prefix(href, "/")
			if !ok || strings.has_prefix(href, "//") { return fmt.tprintf("an href off the list: %s", href) }
		}
	}
	if len(open) > 0 { return fmt.tprintf("<%s> left open", open[len(open) - 1]) }
	return ""
}

@(test)
any_text_renders_to_markup_it_means :: proc(t: ^testing.T) {
	d := fuzz.seed(0xC0FFEE_0D1E)
	buf: [2048]byte
	for i in 0 ..< fuzz.rounds(100_000) {
		src := string(fuzz.draw(&d, buf[:], ALPHABET))
		b := strings.builder_make(context.temp_allocator)
		_, ok := render(&b, src, {doc_prefix = "/wiki/"})
		testing.expect(t, ok)
		if problem := inspect(strings.to_string(b)); problem != "" {
			testing.expectf(t, false, "round %d: %s, from %q", i, problem, src)
			break
		}
		_ = plain(src)
		free_all(context.temp_allocator)
	}
}

// Past the cap's worth of what a nested or scanning renderer dies of, each from the first byte. A shape is
// also held to a time: the wiki renders off the loop, but the bot renders on it.
@(test)
the_worst_shapes_at_the_cap_are_bounded :: proc(t: ^testing.T) {
	SHAPES := [?]string{
		"> ", "- ", "* ", "1. ", "  - ", "*", "**", "_", "__", "~~", "`", "``", "[", "](", "[a](", "![", "![a](", "<", "&", "\\", "|", "|a", "#", "\n", "\n\n",
		"[[]]", "*_", "**_", "`*", "[*", "> - ", "- > ", "> 1. ", "```\n", "|---", "a\n", "* a\n", "> a\n", " ", "\t",
	}
	worst := time.Duration(0)
	worst_shape := ""
	for shape in SHAPES {
		src := strings.repeat(shape, MAX_INPUT / len(shape), context.temp_allocator)
		start := time.tick_now()
		b := strings.builder_make(context.temp_allocator)
		_, ok := render(&b, src, {doc_prefix = "/wiki/"})
		took := time.tick_since(start)
		testing.expectf(t, ok, "%q", shape)
		if problem := inspect(strings.to_string(b)); problem != "" { testing.expectf(t, false, "%q: %s", shape, problem) }
		if took > worst { worst, worst_shape = took, shape }
		free_all(context.temp_allocator)
	}
	fmt.printfln("markdown: the slowest shape at %d KiB: %q, %v", MAX_INPUT / 1024, worst_shape, worst)
	testing.expectf(t, worst < 2 * time.Second, "%q took %v", worst_shape, worst)
}

@(test)
past_the_cap_it_writes_nothing :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	_, ok := render(&b, strings.repeat("a", MAX_INPUT + 1, context.temp_allocator))
	testing.expect(t, !ok && strings.builder_len(b) == 0)
	free_all(context.temp_allocator)
}
