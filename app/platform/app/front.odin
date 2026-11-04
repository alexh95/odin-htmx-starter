package app

// ---- front: what every request passes through (§8.4) ----------------------------------
//
// The skeleton's order (SK/app/src/controllers/middleware.odin:38-87), with the
// host picked first and the route found before anything answers, so its flags
// set the headers and its perm is checked before the body is read:
//
//   1. the host by Host (an unknown one is the main host), the route, the request
//      id, the security headers by the route's flags;
//   2. a malformed Content-Length gets 400 and a closed connection, first;
//   3. the *.fly.dev → canonical origin 301;
//   4. the cross-site write guard, for every write, routed or not, before its body;
//   5. no route: the body capped at MAX_BODY (413), then 405 with Allow when
//      another method serves the path, else 404, as the skeleton answered;
//   6. the viewer, by the build's identity on a host that runs one, and the route's
//      perm (401 or 403), .Lan_Only (404 off the LAN);
//   7. the body, capped by the route (413 past it), then the handler;
//   8. one access-log line, unless the handler deferred its response: its
//      continuation logs it when it answers.

import "core:strings"
import "core:time"

import "../authz"
import "../escape"
import "../obs"
import "../store"
import "../sys"
import "../web"
import identity "identity:."

@(private)
front :: proc(req: ^web.Request, res: ^web.Response) {
	start := sys.mono_ns()
	web.mark_start(start)
	c := new(web.Req_Ctx, context.temp_allocator)
	c.req, c.res, c.start = req, res, start
	c.site = pick_site(req)
	trusted: bool
	c.client, c.https, trusted = web.client_of(req)
	c.id = web.request_id(req, res, trusted)
	m, params, allow := web.router_find(&c.site.router, web.method_of(req), req.url.path)
	c.route = m
	obs.set_request(c.id, m.obs if m != nil else obs.NO_ROUTE)
	c.nonce = web.security_headers(res, m.flags if m != nil else {}, req.url.path)
	web.set_ctx(c)
	defer web.set_ctx(nil)

	switch {
	case !web.content_length_ok(req):
		web.refuse_length(res)
	case web.canonical_redirect(c.site, req, res):
	case !web.same_origin(req):
		web.respond_plain(res, "Cross-site request refused.", .Forbidden)
	case m != nil && .Stream in m.flags && req.is_head:
		// A HEAD is served as a GET whose body is dropped, but a stream's body is written on
		// and never ends: a client that trusts HEAD to have none read it as its next response
		// (M2-14).
		web.set_header(res, "allow", "GET")
		web.respond_plain(res, "Method not allowed.", .Method_Not_Allowed)
	case m == nil:
		c.allow = allow
		if !web.has_body(req) {
			unrouted(c)
			break
		}
		web.read_body(req, res, web.MAX_BODY, c, proc(user: rawptr, body: string, ok: bool) {
			c := (^web.Req_Ctx)(user)
			if ok { unrouted(c) }
			done(c)
		})
		return
	case:
		req.url_params = params
		if !admit(c, req, res) { break }
		if !web.has_body(req) {
			call(c)
			return
		}
		// Before a byte of it: a connection's buffer holds a large body until its handler runs.
		c.large = m.body_cap >= web.LARGE_BODY && web.declares_large(req)
		if c.large && !web.large_begin(c.viewer.id) {
			c.large = false
			web.set_header(res, "connection", "close")
			web.respond_plain(res, "Busy: try again in a moment.", .Service_Unavailable)
			break
		}
		web.read_body(req, res, m.body_cap if m.body_cap > 0 else web.MAX_BODY, c, proc(user: rawptr, body: string, ok: bool) {
			c := (^web.Req_Ctx)(user)
			if c.large {
				c.large = false
				web.large_end(c.viewer.id)
			}
			if !ok {
				done(c)
				return
			}
			// A stream's begin frees the buffer the body is a slice of (the fork's F-17): its
			// handler gets a copy in the request arena (M2-09).
			c.body = strings.clone(body, context.temp_allocator) if .Stream in c.route.flags else body
			call(c)
		})
		return
	}
	done(c)
}

// No row answers: 405 with Allow when another method serves the path, else the
// site's 404 (SK/app/src/routes.odin:67-69).
@(private)
unrouted :: proc(c: ^web.Req_Ctx) {
	web.set_ctx(c)
	if len(c.allow) > 0 {
		web.set_header(c.res, "allow", strings.join(c.allow, ", ", context.temp_allocator))
		web.respond_plain(c.res, "Method not allowed.", .Method_Not_Allowed)
	} else {
		web.not_found(c.req, c.res)
	}
}

// The host whose origin's hostname is Host's; the main host (the first) otherwise,
// where the canonical-host redirect still applies.
@(private)
pick_site :: proc(req: ^web.Request) -> ^web.Site {
	if len(st.sites) > 1 {
		h := web.host_of(req)
		for &s in st.sites[1:] {
			if s.hostname == h { return &s }
		}
	}
	return &st.sites[0]
}

// The viewer and the route's access rules, before a byte of the body is read.
@(private)
admit :: proc(c: ^web.Req_Ctx, req: ^web.Request, res: ^web.Response) -> bool {
	c.viewer = authz.GUEST
	if c.site.identity {
		v, cookie := identity.load_viewer({cookies = web.cookies_of(req), client = c.client, https = c.https})
		c.viewer = v
		if cookie != "" { web.set_header(res, "set-cookie", cookie) }
	}
	m := c.route
	rule := authz.Rule{perm = m.perm, lan_only = .Lan_Only in m.flags, step_up = .Step_Up in m.flags}
	switch authz.refusal(c.viewer, rule, is_lan(c.client), time.time_to_unix(time.now())) {
	case .None:
	case .Not_Found:
		web.not_found(req, res)
		return false
	case .Sign_In:
		send_to(req, res, "/login", "Sign in first.")
		return false
	case .Step_Up:
		send_to(req, res, strings.concatenate({"/step-up?next=", escape.url_encode(return_to(req))}, context.temp_allocator), "Confirm it's you first.")
		return false
	case .Forbidden:
		web.respond_plain(res, "Not allowed.", .Forbidden)
		return false
	}
	return true
}

// Where a step-up sends the member back to: a page they asked for, or, for a write (whose URL a
// browser can't GET), the page htmx says they were on; a path on this site, else "/".
@(private)
return_to :: proc(req: ^web.Request) -> string {
	if web.method_name(req) == "GET" { return req.url.path }
	from, _ := web.header(req, "hx-current-url")
	if at := strings.index(from, "://"); at >= 0 {
		rest := from[at + 3:]
		slash := strings.index_byte(rest, '/')
		from = rest[slash:] if slash >= 0 else "/"
	}
	if q := strings.index_any(from, "?#"); q >= 0 { from = from[:q] }
	return from if escape.site_path(from) else "/"
}

// A guest to sign in, a stale session to step up (§17.2): htmx follows HX-Redirect on a 401,
// a page load a 302.
@(private)
send_to :: proc(req: ^web.Request, res: ^web.Response, to, why: string) {
	if web.is_htmx(req) {
		web.set_header(res, "hx-redirect", to)
		web.respond_plain(res, why, .Unauthorized)
	} else {
		web.set_header(res, "location", to)
		web.respond_status(res, .Found)
	}
}

@(private)
call :: proc(c: ^web.Req_Ctx) {
	web.set_ctx(c)
	store.handler_begin()
	c.route.handler(c.req, c.res)
	store.handler_end()
	web.set_ctx(nil)
	if !c.deferred { done(c) }
}

@(private)
done :: proc(c: ^web.Req_Ctx) {
	us := (sys.mono_ns() - c.start) / 1000
	route := ""
	if c.route != nil {
		obs.count_request(c.route.obs, us)
		route = c.route.id
	}
	web.access_log(web.method_name(c.req), route, c.req.url.path, int(c.res.status), us, c.id, c.client, c.impl)
	obs.clear_request()
}
