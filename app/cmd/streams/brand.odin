package main

// ---- streams' brand: its names, its nav, its copy ---------------------------------------
//
// The stream substrate's witness (PLAN §7.1): chat over four transports, the Inbox,
// the notes card and about, on a memory store, the lite theme and the nick identity,
// with no SQLite library. Rename here, not across the features.

import "../../platform/html"
import about_web "../../features/about/web"
import home_web "../../features/home/web"
import wiki_web "../../features/wiki/web"

BRAND := html.Brand {
	// Rendered raw so it can carry inline markup (the accent dot is a <b> that
	// .brand-name b styles); developer-authored, never user input.
	wordmark    = "odin<b>·</b>streams",
	suffix      = "Odin + HTMX streams",
	home_title  = "Odin + HTMX streams: chat and live pages from one binary",
	source_name = "Odin + HTMX",
	repo        = "https://github.com/alexh95/odin-htmx-starter",
	// A placeholder origin until the profile has a domain: SITE_URL overrides it,
	// and the *.fly.dev redirect stays off for a placeholder.
	site_url    = "https://streams.example.com",
	og_image    = "/static/og.png",
	overlays    = true, // #toasts: chat's 429s and a socket's refusals land there
}

NAV := [?]html.Nav_Item {
	{"/", "Home", "grid"},
	{"/chat", "Chat", "users"},
	{"/notify", "Inbox", "bell"},
	{"/bot", "Bot", "bolt"},
	{"/wiki", "Docs", "edit"},
	{"/find", "Search", "search"},
	{"/status", "Status", "check"},
	{"/about", "About", "info"},
}

WIKI := wiki_web.Copy {
	name        = "Docs",
	description = "The starter's own docs: what it is, how to work in it, how its gates run.",
	repo        = "https://github.com/alexh95/odin-htmx-starter",
}

HOME := home_web.Copy {
	title       = "Home",
	eyebrow     = "Streams",
	heading     = "Live on the LAN",
	lede        = "Chat over a WebSocket, an SSE stream, polling or one long multipart response, and an Inbox that follows you from page to page. Pick a nickname to post.",
	description = "An Odin + HTMX starter for live pages: chat on four transports and a live Inbox, in one self-contained binary.",
}

ABOUT := about_web.Copy {
	subtitle    = "The stream substrate of an Odin + HTMX starter: server-sent events, WebSockets and multipart, from one binary.",
	description = "About this project: an Odin backend rendering HTML with HTMX, streaming to the page over SSE, WebSockets and multipart.",
	lede        = `<p class="about-lede">Built on a <strong>starter</strong>: an <a href="https://odin-lang.org" target="_blank" rel="noopener">Odin</a> backend that renders HTML, wired up with <a href="https://htmx.org" target="_blank" rel="noopener">HTMX</a>, its live parts streamed by the server, served as a single statically-linked binary.</p>`,
	repo        = "https://github.com/alexh95/odin-htmx-starter",
}
