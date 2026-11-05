package main

// ---- lab's brand: its names, its nav, its copy ------------------------------------------
//
// The starter's own page, on an origin with no sessions (PLAN §7.1, §15.5): the
// landing page (the catalog and the init-command builder), the stream contract pages,
// the nonce class, the compatibility layers and the witness board (status, M3).

import "../../platform/html"
import about_web "../../features/about/web"
import wiki_web "../../features/wiki/web"

BRAND := html.Brand {
	wordmark    = "odin<b>·</b>htmx lab",
	suffix      = "Odin + HTMX lab",
	home_title  = "Odin + HTMX lab — the stream contract in real pages",
	source_name = "odin-htmx-starter",
	repo        = "https://github.com/alexh95/odin-htmx-starter",
	// A placeholder origin until M3 deploys it: SITE_URL overrides it, and the
	// *.fly.dev redirect stays off for a placeholder.
	site_url    = "https://lab.example.com",
	og_image    = "/static/og.png",
}

NAV := [?]html.Nav_Item {
	{"/", "Starter", "grid"},
	{"/lab", "Lab", "layers"},
	{"/lab/streams", "Streams", "bolt"},
	{"/scripting", "Scripting", "code"},
	{"/compat", "Compat", "layers"},
	{"/wiki", "Docs", "edit"},
	{"/status", "Status", "check"},
	{"/about", "About", "info"},
}

WIKI := wiki_web.Copy {
	name        = "Docs",
	description = "The starter's own docs: what it is, how to work in it, how its gates run.",
	repo        = "https://github.com/alexh95/odin-htmx-starter",
}

ABOUT := about_web.Copy {
	subtitle    = "The starter's own page: what its stream substrate does, shown in real pages on an origin with no sessions.",
	description = "About the odin-htmx-starter lab: SSE, WebSocket and multipart from an Odin server to htmx 4, in one self-contained binary.",
	lede        = `<p class="about-lede">The lab is part of <strong>odin-htmx-starter</strong>: an <a href="https://odin-lang.org" target="_blank" rel="noopener">Odin</a> backend that renders HTML, wired up with <a href="https://htmx.org" target="_blank" rel="noopener">HTMX</a>, served as a single statically-linked binary.</p>`,
	repo        = "https://github.com/alexh95/odin-htmx-starter",
}
