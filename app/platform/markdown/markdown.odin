package markdown

// ---- platform/markdown: Markdown, a safe subset (L2) -----------------------
//
// spark's renderer (portal/src/views/markdown.odin), generalised from its game
// docs: domains render at write time and store the HTML (chat messages, the
// wiki), so it sits in L2 and escapes through platform/escape (S6, PLAN §5.2).
// Everything is escaped and raw HTML shows as text; links go only to http(s),
// mailto or this site; images come only from the one prefix the caller names.
// A pure zone (D15 rule 7): no lock, no I/O, no SQLite, so a trap here is pure,
// and the input and nesting caps keep remote input from making one.
//
// Blocks: ATX headings (with anchor ids), paragraphs, fenced code, ">" quotes,
// "---" rules, "-"/"*"/"+" and "1." lists (nested by indentation), GFM pipe
// tables. Inline: `code`, **strong**, *em*, ~~del~~, [links](...),
// ![images](...), <https://autolinks>, backslash escapes, and a hard break where
// a line ends in two spaces or a backslash.

import "core:fmt"
import "core:strings"

import "../escape"

MAX_INPUT :: 64 * 1024 // bytes; render refuses more (13 §2.1)
MAX_DEPTH :: 32 // nested quotes, lists and emphasis; deeper text is escaped as is

Options :: struct {
	doc_prefix:    string, // "name.md#x" links to doc_prefix + "name#x"; "" makes them text
	image_prefix:  string, // "file.png" shows image_prefix + "file.png"; "" shows the alt text
	heading_shift: int,    // added to every heading level
}

Toc_Entry :: struct {
	level:      int,
	text, slug: string,
}

@(private = "file")
Md :: struct {
	using opts: Options,
	slugs:      map[string]int, // heading anchors already used
	toc:        [dynamic]Toc_Entry,
	links:      int, // > 0 while inside a link's text: no links within links
	depth:      int, // block and inline nesting
}

// Renders src into b and returns the headings (for a table of contents). Past
// MAX_INPUT it writes nothing and returns false: the caller caps the field first.
render :: proc(b: ^strings.Builder, src: string, opts := Options{}) -> (toc: []Toc_Entry, ok: bool) {
	if len(src) > MAX_INPUT { return nil, false }
	md := Md {
		opts  = opts,
		slugs = make(map[string]int, context.temp_allocator),
		toc   = make([dynamic]Toc_Entry, context.temp_allocator),
	}
	raw := strings.split_lines(src, context.temp_allocator)
	lines := make([]string, len(raw), context.temp_allocator)
	for l, i in raw {
		lines[i] = expand_tabs(strings.trim_right(l, "\r"))
	}
	md_blocks(&md, b, lines)
	return md.toc[:], true
}

// ---- blocks ---------------------------------------------------------------

@(private = "file")
md_blocks :: proc(md: ^Md, b: ^strings.Builder, lines: []string) {
	md.depth += 1
	defer md.depth -= 1
	if md.depth > MAX_DEPTH {
		escape.w(b, "<p>")
		for l, i in lines {
			if i > 0 { escape.w(b, " ") }
			escape.esc(b, strings.trim_space(l))
		}
		escape.w(b, "</p>\n")
		return
	}
	i := 0
	for i < len(lines) {
		t := strings.trim_space(lines[i])
		switch {
		case t == "":
			i += 1
		case is_fence(t):
			i = md_code(b, lines, i)
		case heading_level(t) > 0:
			md_heading(md, b, t)
			i += 1
		case is_rule(t):
			escape.w(b, "<hr>\n")
			i += 1
		case strings.has_prefix(t, ">"):
			quote := make([dynamic]string, context.temp_allocator)
			for i < len(lines) && strings.has_prefix(strings.trim_space(lines[i]), ">") {
				q := strings.trim_space(lines[i])[1:]
				append(&quote, strings.has_prefix(q, " ") ? q[1:] : q)
				i += 1
			}
			escape.w(b, "<blockquote>")
			md_blocks(md, b, quote[:])
			escape.w(b, "</blockquote>\n")
		case list_marker(lines[i]).kind != .None:
			i = md_list(md, b, lines, i)
		case i + 1 < len(lines) && is_table_start(lines[i], lines[i + 1]):
			i = md_table(md, b, lines, i)
		case:
			i = md_paragraph(md, b, lines, i)
		}
	}
}

// Whether lines[i] starts a block that ends a paragraph.
@(private = "file")
starts_block :: proc(lines: []string, i: int) -> bool {
	t := strings.trim_space(lines[i])
	return(
		t == "" ||
		is_fence(t) ||
		heading_level(t) > 0 ||
		is_rule(t) ||
		strings.has_prefix(t, ">") ||
		list_marker(lines[i]).kind != .None ||
		(i + 1 < len(lines) && is_table_start(lines[i], lines[i + 1])) \
	)
}

@(private = "file")
md_paragraph :: proc(md: ^Md, b: ^strings.Builder, lines: []string, start: int) -> int {
	escape.w(b, "<p>")
	i := start
	for i < len(lines) && (i == start || !starts_block(lines, i)) {
		if i > start {
			prev := lines[i - 1]
			escape.w(b, strings.has_suffix(prev, "  ") || strings.has_suffix(prev, "\\") ? "<br>" : " ")
		}
		md_inline(md, b, strings.trim_right(strings.trim_space(lines[i]), "\\"))
		i += 1
	}
	escape.w(b, "</p>\n")
	return i
}

@(private = "file")
is_fence :: proc(t: string) -> bool {
	return strings.has_prefix(t, "```") || strings.has_prefix(t, "~~~")
}

@(private = "file")
md_code :: proc(b: ^strings.Builder, lines: []string, start: int) -> int {
	fence := strings.trim_space(lines[start])[:3]
	escape.w(b, "<pre><code>")
	i := start + 1
	for i < len(lines) && !strings.has_prefix(strings.trim_space(lines[i]), fence) {
		if i > start + 1 {
			escape.w(b, "\n")
		}
		escape.esc(b, lines[i])
		i += 1
	}
	escape.w(b, "</code></pre>\n")
	return min(i + 1, len(lines))
}

@(private = "file")
heading_level :: proc(t: string) -> int {
	n := 0
	for n < len(t) && t[n] == '#' {
		n += 1
	}
	if n == 0 || n > 6 || (n < len(t) && t[n] != ' ') {
		return 0
	}
	return n
}

@(private = "file")
md_heading :: proc(md: ^Md, b: ^strings.Builder, t: string) {
	level := heading_level(t)
	text := strings.trim_space(t[level:])
	// An optional closing run of '#' ("## Title ##") isn't part of the title.
	if trimmed := strings.trim_right(text, "#"); len(trimmed) < len(text) && (trimmed == "" || strings.has_suffix(trimmed, " ")) {
		text = strings.trim_space(trimmed)
	}
	slug := unique_slug(md, slugify(text))
	shown := clamp(level + md.heading_shift, 1, 6)
	fmt.sbprintf(b, `<h%d id="%s">`, shown, slug)
	md_inline(md, b, text)
	fmt.sbprintf(b, "</h%d>\n", shown)
	append(&md.toc, Toc_Entry{shown, plain_text(text), slug})
}

@(private = "file")
is_rule :: proc(t: string) -> bool {
	if len(t) < 3 || (t[0] != '-' && t[0] != '*' && t[0] != '_') {
		return false
	}
	n := 0
	for i in 0 ..< len(t) {
		switch t[i] {
		case t[0]:
			n += 1
		case ' ':
		case:
			return false
		}
	}
	return n >= 3
}

// ---- lists ------------------------------------------------------------------

@(private = "file")
List_Kind :: enum {
	None,
	Bullet,
	Ordered,
}

@(private = "file")
Marker :: struct {
	kind:   List_Kind,
	indent: int, // spaces before the marker
	offset: int, // where the item's text starts
	number: int, // an ordered item's number
}

@(private = "file")
list_marker :: proc(line: string) -> Marker {
	indent := 0
	for indent < len(line) && line[indent] == ' ' {
		indent += 1
	}
	rest := line[indent:]
	if len(rest) >= 2 && (rest[0] == '-' || rest[0] == '*' || rest[0] == '+') && rest[1] == ' ' {
		if is_rule(strings.trim_space(rest)) {
			return {}
		}
		return {.Bullet, indent, indent + 2, 0}
	}
	n, digits := 0, 0
	for digits < len(rest) && digits < 9 && rest[digits] >= '0' && rest[digits] <= '9' {
		n = n * 10 + int(rest[digits] - '0')
		digits += 1
	}
	if digits > 0 && digits + 1 < len(rest) && (rest[digits] == '.' || rest[digits] == ')') && rest[digits + 1] == ' ' {
		return {.Ordered, indent, indent + digits + 2, n}
	}
	return {}
}

@(private = "file")
md_list :: proc(md: ^Md, b: ^strings.Builder, lines: []string, start: int) -> int {
	first := list_marker(lines[start])
	if first.kind == .Bullet {
		escape.w(b, "<ul>")
	} else if first.number != 1 {
		fmt.sbprintf(b, `<ol start="%d">`, first.number)
	} else {
		escape.w(b, "<ol>")
	}
	i := start
	for i < len(lines) {
		m := list_marker(lines[i])
		if m.kind != first.kind || m.indent != first.indent {
			break
		}
		item := make([dynamic]string, context.temp_allocator)
		append(&item, lines[i][m.offset:])
		i += 1
		for i < len(lines) {
			l := lines[i]
			if strings.trim_space(l) == "" {
				// A blank line continues the item only if what follows is indented under it.
				if i + 1 < len(lines) && leading_spaces(lines[i + 1]) >= m.offset && strings.trim_space(lines[i + 1]) != "" {
					append(&item, "")
					i += 1
					continue
				}
				break
			}
			if n := list_marker(l); n.kind != .None && n.indent <= first.indent {
				break
			}
			if leading_spaces(l) == 0 && starts_block(lines, i) {
				break
			}
			append(&item, strip_spaces(l, m.offset))
			i += 1
		}
		escape.w(b, "<li>")
		// The item's first lines are its text; anything after a blank line or a nested list renders as blocks.
		k := 0
		for k < len(item) && (k == 0 || !starts_block(item[:], k)) {
			if k > 0 {
				escape.w(b, " ")
			}
			md_inline(md, b, strings.trim_space(item[k]))
			k += 1
		}
		if k < len(item) {
			md_blocks(md, b, item[k:])
		}
		escape.w(b, "</li>")
		// Items separated by a blank line still make one list.
		if i + 1 < len(lines) && strings.trim_space(lines[i]) == "" {
			if n := list_marker(lines[i + 1]); n.kind == first.kind && n.indent == first.indent {
				i += 1
			}
		}
	}
	escape.w(b, first.kind == .Bullet ? "</ul>\n" : "</ol>\n")
	return i
}

// ---- tables -----------------------------------------------------------------

@(private = "file")
Align :: enum {
	None,
	Left,
	Center,
	Right,
}

@(private = "file")
is_table_start :: proc(head, sep: string) -> bool {
	if !strings.contains_rune(head, '|') {
		return false
	}
	cells := split_row(sep)
	if len(cells) == 0 {
		return false
	}
	for c in cells {
		t := strings.trim(strings.trim_space(c), ":")
		if len(t) == 0 || strings.trim_left(t, "-") != "" {
			return false
		}
	}
	return true
}

@(private = "file")
md_table :: proc(md: ^Md, b: ^strings.Builder, lines: []string, start: int) -> int {
	head := split_row(lines[start])
	seps := split_row(lines[start + 1])
	aligns := make([]Align, len(head), context.temp_allocator)
	for &a, i in aligns {
		if i < len(seps) {
			s := strings.trim_space(seps[i])
			l, r := strings.has_prefix(s, ":"), strings.has_suffix(s, ":")
			a = l && r ? .Center : r ? .Right : l ? .Left : .None
		}
	}
	cell :: proc(md: ^Md, b: ^strings.Builder, tag: string, text: string, a: Align) {
		CLASS := [Align]string{.None = "", .Left = "", .Center = ` class="al-c"`, .Right = ` class="al-r"`}
		fmt.sbprintf(b, "<%s%s>", tag, CLASS[a])
		md_inline(md, b, strings.trim_space(text))
		fmt.sbprintf(b, "</%s>", tag)
	}
	escape.w(b, `<div class="table-scroll"><table class="md-table"><thead><tr>`)
	for h, i in head {
		cell(md, b, "th", h, aligns[i])
	}
	escape.w(b, "</tr></thead><tbody>")
	i := start + 2
	for i < len(lines) && strings.trim_space(lines[i]) != "" && strings.contains_rune(lines[i], '|') {
		row := split_row(lines[i])
		escape.w(b, "<tr>")
		for col in 0 ..< len(head) {
			cell(md, b, "td", col < len(row) ? row[col] : "", aligns[col])
		}
		escape.w(b, "</tr>")
		i += 1
	}
	escape.w(b, "</tbody></table></div>\n")
	return i
}

// The cells of a "| a | b |" row; "\|" is a literal bar, and so is a bar inside `code`.
@(private = "file")
split_row :: proc(line: string) -> []string {
	t := strings.trim_space(line)
	if strings.has_prefix(t, "|") {
		t = t[1:]
	}
	if strings.has_suffix(t, "|") && !strings.has_suffix(t, "\\|") {
		t = t[:len(t) - 1]
	}
	out := make([dynamic]string, context.temp_allocator)
	from := 0
	in_code := false
	for i := 0; i < len(t); i += 1 {
		switch t[i] {
		case '\\':
			i += 1
		case '`':
			in_code = !in_code
		case '|':
			if !in_code {
				append(&out, t[from:i])
				from = i + 1
			}
		}
	}
	append(&out, t[from:])
	return out[:]
}

// ---- inline -----------------------------------------------------------------

@(private = "file")
md_inline :: proc(md: ^Md, b: ^strings.Builder, s: string) {
	md.depth += 1
	defer md.depth -= 1
	if md.depth > MAX_DEPTH {
		escape.esc(b, s)
		return
	}
	i := 0
	for i < len(s) {
		c := s[i]
		switch {
		case c == '\\' && i + 1 < len(s) && is_md_punct(s[i + 1]):
			escape.esc(b, s[i + 1:i + 2])
			i += 2
		case c == '`':
			n := run_of(s, i, '`')
			ticks := s[i:i + n]
			end := strings.index(s[i + n:], ticks)
			if end < 0 {
				escape.esc(b, ticks)
				i += n
				continue
			}
			escape.w(b, "<code>")
			escape.esc(b, s[i + n:i + n + end])
			escape.w(b, "</code>")
			i += n + end + n
		case c == '!' && i + 1 < len(s) && s[i + 1] == '[':
			if text, url, end, ok := link_at(s, i + 1); ok {
				md_image(md, b, text, url)
				i = end
			} else {
				escape.esc(b, "!")
				i += 1
			}
		case c == '[' && md.links == 0:
			if text, url, end, ok := link_at(s, i); ok {
				md_link(md, b, text, url)
				i = end
			} else {
				escape.esc(b, "[")
				i += 1
			}
		case c == '<' && md.links == 0:
			end := strings.index_byte(s[i:min(len(s), i + MAX_LINK)], '>')
			if end > 1 && is_web_url(s[i + 1:i + end]) {
				url := s[i + 1:i + end]
				escape.w(b, `<a href="`)
				escape.esc(b, url)
				escape.w(b, `" rel="nofollow noopener" target="_blank">`)
				escape.esc(b, url)
				escape.w(b, "</a>")
				i += end + 1
			} else {
				escape.esc(b, "<")
				i += 1
			}
		case c == '*' || c == '_' || c == '~':
			i = md_emphasis(md, b, s, i)
		case:
			escape.esc(b, s[i:i + 1])
			i += 1
		}
	}
}

// **strong**, *em*, __strong__, _em_ (not inside_words), ~~del~~. An unmatched marker is plain text.
@(private = "file")
md_emphasis :: proc(md: ^Md, b: ^strings.Builder, s: string, i: int) -> int {
	c := s[i]
	n := min(run_of(s, i, c), 2)
	if c == '~' && n < 2 {
		escape.esc(b, "~")
		return i + 1
	}
	if c == '_' && i > 0 && is_word(s[i - 1]) {
		escape.esc(b, s[i:i + n])
		return i + n
	}
	marker := s[i:i + n]
	from := i + n
	if from >= len(s) || s[from] == ' ' {
		escape.esc(b, marker)
		return from
	}
	end := strings.index(s[from:], marker)
	// A single marker mustn't close on half of a double one ("*a **b** c*" still pairs the outer stars).
	for end >= 0 && n == 1 && from + end + 1 < len(s) && s[from + end + 1] == c {
		next := strings.index(s[from + end + 2:], marker)
		end = next < 0 ? -1 : end + 2 + next
	}
	if end <= 0 || s[from + end - 1] == ' ' || (c == '_' && from + end + n < len(s) && is_word(s[from + end + n])) {
		escape.esc(b, marker)
		return from
	}
	tag := c == '~' ? "del" : n == 2 ? "strong" : "em"
	fmt.sbprintf(b, "<%s>", tag)
	md_inline(md, b, s[from:from + end])
	fmt.sbprintf(b, "</%s>", tag)
	return from + end + n
}

// A link's text and a link's target each: past this it's text, not a link.
@(private = "file")
MAX_LINK :: 2048
@(private = "file")
MAX_LINK_NESTING :: 8

// "[text](url)" starting at s[i] == '['. Brackets in the text may nest, and so may parentheses in the url
// ("javascript:alert(1)" is one url, rejected whole); a space ends the url (a "title" after it is dropped).
@(private = "file")
link_at :: proc(s: string, i: int) -> (text, url: string, end: int, ok: bool) {
	depth := 0
	close := -1
	// Bounded, or text of nothing but `[` costs a scan of the rest at each (M7-07).
	for j := i; j < min(len(s), i + MAX_LINK); j += 1 {
		switch s[j] {
		case '\\':
			j += 1
		case '[':
			depth += 1
			if depth > MAX_LINK_NESTING {
				return
			}
		case ']':
			depth -= 1
			if depth == 0 {
				close = j
			}
		}
		if close >= 0 {
			break
		}
	}
	if close < 0 || close + 1 >= len(s) || s[close + 1] != '(' {
		return
	}
	paren := -1
	parens := 0
	for j := close + 2; j < min(len(s), close + 2 + MAX_LINK); j += 1 {
		if s[j] == '(' {
			parens += 1
			if parens > MAX_LINK_NESTING {
				return
			}
		} else if s[j] == ')' {
			if parens == 0 {
				paren = j - (close + 2)
				break
			}
			parens -= 1
		}
	}
	if paren < 0 {
		return
	}
	target := strings.trim_space(s[close + 2:close + 2 + paren])
	if sp := strings.index_byte(target, ' '); sp >= 0 {
		target = target[:sp] // a "title" after the url is dropped
	}
	return s[i + 1:close], target, close + 2 + paren + 1, true
}

@(private = "file")
md_link :: proc(md: ^Md, b: ^strings.Builder, text, url: string) {
	href, external, ok := resolve_link(md, url)
	if !ok {
		md.links += 1
		md_inline(md, b, text)
		md.links -= 1
		return
	}
	escape.w(b, `<a href="`)
	escape.esc(b, href)
	escape.w(b, external ? `" rel="nofollow noopener" target="_blank">` : `">`)
	md.links += 1
	md_inline(md, b, text)
	md.links -= 1
	escape.w(b, "</a>")
}

// Where a link may go:
// - http(s) and mailto (external, a new tab);
// - "#anchor", and "/path" on this site;
// - "name.md" or "name.md#anchor": another doc, under doc_prefix;
// - "file.png": an image, under image_prefix.
// Anything else, javascript: and data: included, isn't a link at all.
@(private = "file")
resolve_link :: proc(md: ^Md, url: string) -> (href: string, external, ok: bool) {
	switch {
	case url == "":
		return "", false, false
	case is_web_url(url), strings.has_prefix(url, "mailto:"):
		return url, true, true
	case strings.has_prefix(url, "#"):
		return url, false, true
	case strings.has_prefix(url, "/") && !strings.has_prefix(url, "//"):
		return url, false, true
	}
	path, frag := url, ""
	if h := strings.index_byte(url, '#'); h >= 0 {
		path, frag = url[:h], url[h:]
	}
	path = strings.to_lower(path, context.temp_allocator)
	if md.doc_prefix != "" && strings.has_suffix(path, ".md") && safe_name(path[:len(path) - 3]) {
		return fmt.tprintf("%s%s%s", md.doc_prefix, path[:len(path) - 3], frag), false, true
	}
	if md.image_prefix != "" && is_image_name(path) {
		return fmt.tprintf("%s%s", md.image_prefix, path), false, true
	}
	return "", false, false
}

// Only images under image_prefix (a docs folder the site serves); anything else shows its alt text.
@(private = "file")
md_image :: proc(md: ^Md, b: ^strings.Builder, alt, url: string) {
	name := strings.to_lower(url, context.temp_allocator)
	if md.image_prefix == "" || !is_image_name(name) {
		escape.esc(b, alt)
		return
	}
	escape.w(b, `<img class="md-img" src="`)
	escape.esc(b, md.image_prefix)
	escape.esc(b, name)
	escape.w(b, `" alt="`)
	escape.esc(b, alt)
	escape.w(b, `" loading="lazy" decoding="async">`)
}

// ---- helpers ----------------------------------------------------------------

@(private = "file")
is_web_url :: proc(s: string) -> bool {
	return (strings.has_prefix(s, "https://") || strings.has_prefix(s, "http://")) && !strings.contains_any(s, " \"'<>")
}

@(private = "file")
is_image_name :: proc(s: string) -> bool {
	dot := strings.last_index_byte(s, '.')
	if dot <= 0 {
		return false
	}
	ext := s[dot:]
	return (ext == ".png" || ext == ".jpg" || ext == ".jpeg") && safe_name(s[:dot])
}

// A doc or image name: lower-case letters, digits, '-' and '_', at most 40.
@(private = "file")
safe_name :: proc(s: string) -> bool {
	if s == "" || len(s) > 40 {
		return false
	}
	for c in s {
		switch c {
		case 'a' ..= 'z', '0' ..= '9', '-', '_':
		case:
			return false
		}
	}
	return true
}

@(private = "file")
is_md_punct :: proc(c: u8) -> bool {
	return strings.index_byte("\\`*_{}[]()#+-.!|~<>", c) >= 0
}

@(private = "file")
is_word :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c >= 0x80
}

@(private = "file")
run_of :: proc(s: string, i: int, c: u8) -> int {
	n := 0
	for i + n < len(s) && s[i + n] == c {
		n += 1
	}
	return n
}

@(private = "file")
leading_spaces :: proc(s: string) -> int {
	n := 0
	for n < len(s) && s[n] == ' ' {
		n += 1
	}
	return n
}

@(private = "file")
strip_spaces :: proc(s: string, n: int) -> string {
	return s[min(n, leading_spaces(s)):]
}

@(private = "file")
expand_tabs :: proc(s: string) -> string {
	if strings.index_byte(s, '\t') < 0 {
		return s
	}
	out, _ := strings.replace_all(s, "\t", "    ", context.temp_allocator)
	return out
}

// A heading's text without Markdown punctuation, for the table of contents and its anchor.
@(private = "file")
plain_text :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< len(s) {
		switch s[i] {
		case '*', '_', '`', '~', '[', ']', '\\':
		case:
			strings.write_byte(&b, s[i])
		}
	}
	return strings.to_string(b)
}

// "CL32 · Playtest round 4" -> "cl32-playtest-round-4".
slugify :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	dash := false
	for r in plain_text(s) {
		switch r {
		case 'a' ..= 'z', '0' ..= '9':
			if dash && strings.builder_len(b) > 0 {
				strings.write_byte(&b, '-')
			}
			dash = false
			strings.write_rune(&b, r)
		case 'A' ..= 'Z':
			if dash && strings.builder_len(b) > 0 {
				strings.write_byte(&b, '-')
			}
			dash = false
			strings.write_rune(&b, r + ('a' - 'A'))
		case:
			dash = true
		}
	}
	out := strings.to_string(b)
	return out != "" ? out : "section"
}

@(private = "file")
unique_slug :: proc(md: ^Md, slug: string) -> string {
	n := md.slugs[slug]
	md.slugs[slug] = n + 1
	return n == 0 ? slug : fmt.tprintf("%s-%d", slug, n + 1)
}
