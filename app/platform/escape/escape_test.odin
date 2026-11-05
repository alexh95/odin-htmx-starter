package escape

import "core:strings"
import "core:testing"

@(test)
b64_decode_refuses_what_would_trap_the_decoder :: proc(t: ^testing.T) {
	for bad in ([]string{"", "=", "==", "===", "a", "a===", "ab=c", "ab+c", "ab/c"}) {
		_, ok := b64_decode(bad, url = true)
		testing.expectf(t, !ok, "url %q", bad)
	}
	for bad in ([]string{"", "=", "==", "abc", "ab-c", "ab_c"}) {
		_, ok := b64_decode(bad)
		testing.expectf(t, !ok, "std %q", bad)
	}
	out, ok := b64_decode("aGk", url = true)
	testing.expect(t, ok && string(out) == "hi")
	out, ok = b64_decode("dGhlIHNhbXBsZSBub25jZQ==")
	testing.expect(t, ok && len(out) == 16)
}

@(test)
esc_closes_every_way_out_of_text_and_attributes :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	esc(&b, `<script>alert('x')</script> & "q"`)
	testing.expect_value(t, strings.to_string(b), `&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; &amp; &#34;q&#34;`)
}

@(test)
json_esc_keeps_a_string_inside_its_quotes_and_its_script :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	json_esc(&b, "a \"q\" \\ </script> & tab\t\nline end")
	testing.expect_value(t, strings.to_string(b), `a \"q\" \\ \u003c/script\u003e \u0026 tab\t\nline\u2028end`)
}

@(test)
site_path_stays_on_this_site :: proc(t: ^testing.T) {
	testing.expect(t, site_path("/chat/r/lobby#m-1"))
	for bad in ([]string{"", "chat", "//evil.example", "/\\evil.example", "https://evil.example", "/a b", "/a\x7f"}) {
		testing.expectf(t, !site_path(bad), "%q kept", bad)
	}
}

@(test)
url_encode_escapes_the_query_specials :: proc(t: ^testing.T) {
	testing.expect_value(t, url_encode("a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9")
}

@(test)
write_marked_can_never_leave_markup_open :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, text, want: string) {
		b := strings.builder_make(context.temp_allocator)
		write_marked(&b, text)
		testing.expect_value(t, strings.to_string(b), want)
	}
	check(t, "a \uE000b\uE001 <c>", "a <mark>b</mark> &lt;c&gt;")
	check(t, "\uE000a", "<mark>a</mark>")
	check(t, "a\uE001b", "ab")
	check(t, "\uE000a\uE000b\uE001c\uE001", "<mark>ab</mark>c")
	check(t, "\uE002 ok \xEE\x80", "\uE002 ok \xEE\x80")
}
