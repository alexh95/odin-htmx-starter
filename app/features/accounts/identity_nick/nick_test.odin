package accounts_identity_nick

import "core:net"
import "core:strings"
import "core:testing"

import "../../../platform/authz"
import "../../../platform/env"

// The identity's state is the package's, so the tests that use it are one test: the
// runner would run them at once.
@(private = "file")
setup :: proc() {
	for i in 0 ..< len(st.key) { st.key[i] = u8(i) }
	st.lan, _ = env.parse_cidrs("192.168.0.0/16")
	st.admins, _ = env.parse_cidrs("127.0.0.1/32")
	st.anyone = false
}

// The cookie's value, as a browser sends it back.
@(private = "file")
value_of :: proc(set_cookie: string) -> string {
	v := strings.trim_prefix(set_cookie, "nick=")
	return v[:strings.index_byte(v, ';')]
}

@(private = "file")
ask :: proc(cookie, ip: string) -> authz.Ask {
	a, _ := net.parse_ip4_address(ip)
	return {cookies = strings.concatenate({"theme=x; nick=", cookie}, context.temp_allocator), client = a}
}

@(test)
nicknames_are_checked :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	name, problem := check("  Ada   Lovelace ")
	testing.expect_value(t, name, "Ada Lovelace")
	testing.expect_value(t, problem, "")
	for bad in ([]string{"", "   ", "<b>", "a\x00b", "a/b", "abcdefghijklmnopqrstuvwxy", "bot", "CapCom"}) {
		_, p := check(bad)
		testing.expectf(t, p != "", "%q passed", bad)
	}
	name, _ = check("Zoë_9-x.y")
	testing.expect_value(t, name, "Zoë_9-x.y")
}

@(test)
the_cookie_says_who_and_where_says_what :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	setup()
	set := pick("Ada", false)
	testing.expect(t, strings.contains(set, "HttpOnly") && strings.contains(set, "SameSite=Lax") && !strings.contains(set, "Secure"))
	testing.expect(t, strings.contains(pick("Ada", true), "; Secure"))
	c := value_of(set)

	v, renew := load_viewer(ask(c, "192.168.1.5"))
	testing.expect_value(t, v.role, authz.Role.User)
	testing.expect_value(t, v.name, "Ada")
	testing.expect(t, v.id != 0)
	testing.expect_value(t, renew, "") // fresh: nothing to renew

	admin, _ := load_viewer(ask(c, "127.0.0.1"))
	testing.expect_value(t, admin.role, authz.Role.Admin)
	testing.expect_value(t, admin.id, v.id)

	outside, _ := load_viewer(ask(c, "8.8.8.8"))
	testing.expect_value(t, outside, authz.GUEST) // off the LAN: a Guest, with no id

	st.anyone = true
	anyone, _ := load_viewer(ask(c, "8.8.8.8"))
	testing.expect_value(t, anyone.role, authz.Role.User)
	st.anyone = false

	none, _ := load_viewer(ask("", "192.168.1.5"))
	testing.expect_value(t, none, authz.GUEST)

	// The same id through a rename.
	again := value_of(pick("Ada L", false, v.id))
	renamed, _ := load_viewer(ask(again, "192.168.1.5"))
	testing.expect_value(t, renamed.id, v.id)
	testing.expect_value(t, renamed.name, "Ada L")

	a_forged_cookie_is_a_guest(t, c)
}

@(private = "file")
a_forged_cookie_is_a_guest :: proc(t: ^testing.T, c: string) {
	// Another name under the same MAC; another key; a cut-off MAC.
	parts := strings.split(c, ".", context.temp_allocator)
	forged := strings.join({parts[0], "Qm9i", parts[2], parts[3]}, ".", context.temp_allocator) // "Bob"
	for bad in ([]string{forged, c[:len(c) - 2], "1.QWRh.99999999999.AAAA", "garbage", "...."}) {
		v, _ := load_viewer(ask(bad, "192.168.1.5"))
		testing.expectf(t, v == authz.GUEST, "%q was taken", bad)
	}
	st.key[0] ~= 0xff
	v, _ := load_viewer(ask(c, "192.168.1.5"))
	testing.expect_value(t, v, authz.GUEST)
}

@(test)
next_stays_on_this_site :: proc(t: ^testing.T) {
	testing.expect_value(t, safe_next("/chat/r/lobby"), "/chat/r/lobby")
	for bad in ([]string{"", "chat", "//evil.example", "/\\evil.example", "https://evil.example", "/a b"}) {
		testing.expectf(t, safe_next(bad) == "/", "%q kept", bad)
	}
}
