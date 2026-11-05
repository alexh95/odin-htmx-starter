package html

// ---- platform/html: the page shell and the shared components (L3) ----------
//
// HTML is written into a strings.Builder; a component is a proc that appends
// markup. Raw string literals keep attribute quotes as they are, and every
// dynamic value passes through esc, url_encode or json_esc, re-exported here
// from platform/escape (the injection boundary, one definition of each).
//
// The shell is the skeleton's layout (SK/app/src/views/views.odin), with what a
// profile chooses passed in as data: its Brand (brand.odin), its host's nav, and
// the fingerprinted asset hrefs. It imports the build's `theme:` member, whose
// tables the picker renders, and nothing above L3.

import "core:fmt"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"

import "../authz"
import "../escape"
import "../ext"
import client "client:."
import theme "theme:."

// The build's members of the two families html reads (--features reports them).
CLIENT :: client.NAME
THEME :: theme.NAME

w :: escape.w
esc :: escape.esc
url_encode :: escape.url_encode
site_path :: escape.site_path
json_esc :: escape.json_esc
write_marked :: escape.write_marked

// What a profile's brand.odin declares: its names, its origin, and the parts of
// the shell it uses. Read-only after boot.
Brand :: struct {
	wordmark:       string, // the topbar wordmark: developer-authored inline markup, rendered raw
	suffix:         string, // after every page title, "<page> · <suffix>"; plain text
	home_title:     string, // the root page's <title>, standing alone (about 60 characters)
	source_name:    string, // the JSON-LD SoftwareSourceCode name
	repo:           string, // the source repository, linked from the About page
	site_url:       string, // the canonical origin, no trailing slash; SITE_URL overrides it
	og_image:       string, // unfingerprinted on purpose: social platforms cache a preview against its URL
	bing_site_auth: string, // public by design; "" answers 404
	indexnow_key:   string, // public by design; "" mounts no route
	search:         Search_Box, // the topbar's active search; href "" = none
	overlays:       bool, // #overlay and #toasts after <main>, for modals, drawers and toasts
	style, scheme:  string, // the server-rendered theme; "" = the theme member's default
}

Search_Box :: struct {
	href, placeholder, label: string,
}

Nav_Item :: struct {
	href, label, icon: string,
}

// A home-page card (`home` shows the profile's HOME_CARDS in order): a dispatch
// table's row, as a route's handler is.
Home_Card :: #type proc(b: ^strings.Builder, v: authz.Viewer)

// One page: the brand and origin of the host it is served on, that host's nav,
// the asset hrefs, and the page's own text. A page on a bundle other than Main
// (the lab's scripting and compat pages) links out with full navigations, since a
// boosted swap keeps the old document's CSP and scripts (§12.1; boosting into one
// is web.render_page's to refuse); `nonce` is set on a `.Nonce_Csp` route (§12.2).
Page :: struct {
	brand:                      ^Brand,
	origin:                     string,
	nav:                        []Nav_Item,
	css, htmx, js:              string,
	hs, behaviours:             string, // the hyperscript client's runtime and behaviours ("" on vanilla)
	title, active, description: string,
	bundle:                     ext.Bundle,
	nonce:                      string,
	history_cache:              bool, // this page may be kept in sessionStorage (§12): its own opt-in
	canonical:                  string, // a path, when it isn't `active`: a page under a nav item
	live:                       string, // the page's one SSE stream, #live (§9.1): the hub's markup, or ""
	kept_style, kept_scheme:    string, // a member's kept theme: rendered, and the pre-paint leaves it alone
	theme_href:                 string, // where the picker posts a member's choice; "" = localStorage only
}

// Views write this where a nonce goes (hx-nonce="<%N%>" on an hx-* element of a
// `.Nonce_Csp` page); the response writer puts the response's nonce in its place.
// It holds `<`, so escaped text can't forge it (§12.2).
NONCE_MARK :: "<%N%>"

// Restores the saved theme before first paint, so the page never flashes the
// default palette. It has to be inline (it must run before the stylesheet
// applies), so the Content-Security-Policy admits it by its hash, computed from
// this constant at boot: edit it here and the header follows. Every other script
// is a file.
// A member's kept theme (data-kept) wins over the browser's.
THEME_PREPAINT_JS :: `try{var d=document.documentElement,s=localStorage.getItem('style'),c=localStorage.getItem('scheme');if(!d.hasAttribute('data-kept')){if(s)d.dataset.style=s;if(c)d.dataset.scheme=c;}}catch(e){}`

// ---- icons --------------------------------------------------------------------
//
// A closed set of inline SVGs, 24x24, stroked with currentColor so they take the
// colour of whatever they sit in. One proc, one switch: adding an icon is a case.

icon :: proc(b: ^strings.Builder, name: string) {
	w(b, `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">`)
	switch name {
	case "grid":    w(b, `<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/>`)
	case "layers":  w(b, `<path d="M12 3 2 8l10 5 10-5-10-5Z"/><path d="m2 16 10 5 10-5"/><path d="m2 12 10 5 10-5"/>`)
	case "edit":    w(b, `<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>`)
	case "table":   w(b, `<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18"/>`)
	case "search":  w(b, `<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>`)
	case "sun":     w(b, `<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>`)
	case "moon":    w(b, `<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/>`)
	case "plus":    w(b, `<path d="M12 5v14M5 12h14"/>`)
	case "trash":   w(b, `<path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m2 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/>`)
	case "cycle":   w(b, `<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>`)
	case "bolt":    w(b, `<path d="M13 2 3 14h7l-1 8 10-12h-7l1-8Z"/>`)
	case "code":    w(b, `<path d="m16 18 6-6-6-6"/><path d="m8 6-6 6 6 6"/>`)
	case "bell":    w(b, `<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>`)
	case "check":   w(b, `<path d="M20 6 9 17l-5-5"/>`)
	case "arrow":   w(b, `<path d="M12 19V5M5 12l7-7 7 7"/>`)
	case "users":   w(b, `<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9"/>`)
	case "palette": w(b, `<path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.9 0 1.6-.7 1.6-1.6 0-.4-.2-.8-.4-1.1-.3-.3-.4-.6-.4-1.1a1.6 1.6 0 0 1 1.6-1.6h2c3 0 5.6-2.5 5.6-5.5C22 6 17.5 2 12 2Z"/><circle cx="6.5" cy="11.5" r="1" fill="currentColor" stroke="none"/><circle cx="9.5" cy="7.5" r="1" fill="currentColor" stroke="none"/><circle cx="14.5" cy="7.5" r="1" fill="currentColor" stroke="none"/><circle cx="17.5" cy="11.5" r="1" fill="currentColor" stroke="none"/>`)
	case "info":    w(b, `<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/>`)
	// The GitHub mark is a solid glyph: filled with currentColor, no stroke.
	case "github":  w(b, `<path fill="currentColor" stroke="none" d="M12 2A10 10 0 0 0 8.84 21.5c.5.08.66-.22.66-.48l-.01-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.9-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.9 1.52 2.34 1.08 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.26-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.38.2 2.39.1 2.65.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.69-4.57 4.94.36.31.68.92.68 1.85l-.01 2.74c0 .27.16.57.67.48A10 10 0 0 0 12 2Z"/>`)
	}
	w(b, `</svg>`)
}

// ---- the theme picker: the build's theme member supplies the tables ----------
//
// Two orthogonal axes carried as data-attributes on <html>: data-style (the
// treatment) and data-scheme (the palette within it). Static HTML whose buttons
// app.js handles by their data-pick-* attributes (no inline handlers: the CSP
// forbids them), applying and persisting the choice; the pre-paint script
// restores it before first paint.

theme_picker :: proc(b: ^strings.Builder) {
	w(
		b,
		`<details class="picker"><summary class="icon-btn" aria-label="Theme and style" title="Theme & style">`,
	)
	icon(b, "palette")
	w(b, `</summary><div class="picker-panel"><p class="picker-head">Style</p><div class="picker-styles">`)
	for s in theme.STYLES {
		fmt.sbprintf(
			b,
			`<button class="chip" type="button" data-pick-style="%s" aria-pressed="false">%s</button>`,
			s.id,
			s.label,
		)
	}
	w(b, `</div><p class="picker-head">Scheme</p>`)
	for s in theme.STYLES {
		fmt.sbprintf(b, `<div class="picker-schemes" data-for="%s">`, s.id)
		for sc in theme.SCHEMES {
			if sc.style != s.id {continue}
			fmt.sbprintf(
				b,
				`<button class="swatch" type="button" data-pick-scheme="%s" aria-pressed="false" title="%s" style="--sw:%s"></button>`,
				sc.id,
				sc.label,
				sc.swatch,
			)
		}
		w(b, `</div>`)
	}
	w(b, `</div></details>`)
}

// A style and one of its schemes, as the build's theme member has them: what a kept theme
// must be before it is stored or rendered.
theme_known :: proc(style, scheme: string) -> bool {
	for sc in theme.SCHEMES {
		if sc.style == style && sc.id == scheme { return true }
	}
	return false
}

// Every style and scheme at once, each swatch a one-click jump to that style and
// scheme (the gallery's showroom; app.js reads data-sw-*).
theme_showroom :: proc(b: ^strings.Builder) {
	fmt.sbprintf(
		b,
		`<section class="block"><div class="block-head"><h2>Style showroom</h2><p class="muted">Flip the whole interface — every component below re-skins live. %d styles, %d schemes; click any swatch.</p></div><div class="showroom-grid">`,
		len(theme.STYLES),
		len(theme.SCHEMES),
	)
	for s in theme.STYLES {
		fmt.sbprintf(b, `<div class="showroom-row"><span class="showroom-name">%s</span><div class="showroom-swatches">`, s.label)
		for sc in theme.SCHEMES {
			if sc.style != s.id {continue}
			fmt.sbprintf(
				b,
				`<button class="swatch" type="button" style="--sw:%s" title="%s · %s" aria-label="%s %s" data-sw-style="%s" data-sw-scheme="%s"></button>`,
				sc.swatch,
				s.label,
				sc.label,
				s.label,
				sc.label,
				s.id,
				sc.id,
			)
		}
		w(b, `</div></div>`)
	}
	w(b, `</div></section>`)
}

// ---- the shell ----------------------------------------------------------------

// One resolution for the <title> and og:title alike: a page that answers "what is
// this" with two different names gets neither weighed. The root page carries the
// brand's home title rather than "<nav item> · <brand>": it is the result shown
// for the site as a whole.
@(private = "file")
head_title :: proc(b: ^strings.Builder, p: Page) {
	if p.active == "/" {
		esc(b, p.brand.home_title)
		return
	}
	esc(b, p.title)
	w(b, " · ")
	esc(b, p.brand.suffix)
}

// Each bundle's htmx-config meta JSON: tools/bundle writes it beside the bundle at
// prepare, from the same set (§12.1), and without it (a build before prepare, or
// Main with no extensions) it is the skeleton's own. Folded into constants, so the
// head costs what it did.
@(private = "file")
BUILD_DIR :: #config(BUILD_DIR, "../../build/none")
@(private = "file")
SKELETON_CONFIG :: `{"defaultSwap":"innerHTML"}`
when #exists(BUILD_DIR + "/main.config.json") { @(private = "file") MAIN_CONFIG :: #load(BUILD_DIR + "/main.config.json", string) } else { @(private = "file") MAIN_CONFIG :: SKELETON_CONFIG }
when #exists(BUILD_DIR + "/scripting.config.json") { @(private = "file") SCRIPTING_CONFIG :: #load(BUILD_DIR + "/scripting.config.json", string) } else { @(private = "file") SCRIPTING_CONFIG :: SKELETON_CONFIG }
when #exists(BUILD_DIR + "/compat_htmx2.config.json") { @(private = "file") COMPAT_HTMX2_CONFIG :: #load(BUILD_DIR + "/compat_htmx2.config.json", string) } else { @(private = "file") COMPAT_HTMX2_CONFIG :: SKELETON_CONFIG }
when #exists(BUILD_DIR + "/compat_alpine.config.json") { @(private = "file") COMPAT_ALPINE_CONFIG :: #load(BUILD_DIR + "/compat_alpine.config.json", string) } else { @(private = "file") COMPAT_ALPINE_CONFIG :: SKELETON_CONFIG }

@(private = "file")
HEAD_A :: `">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="htmx-config" content='`
@(private = "file")
HEAD_B :: `'>
<title>`
@(private = "file", rodata)
HEAD_OPEN := [ext.Bundle]string {
	.Main          = HEAD_A + MAIN_CONFIG + HEAD_B,
	.Scripting     = HEAD_A + SCRIPTING_CONFIG + HEAD_B,
	.Compat_Htmx2  = HEAD_A + COMPAT_HTMX2_CONFIG + HEAD_B,
	.Compat_Alpine = HEAD_A + COMPAT_ALPINE_CONFIG + HEAD_B,
}

// The one page shell. p.active is the href of the current page, so the nav can
// mark it; the inline head script sets the theme before first paint.
layout :: proc(p: Page, content: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	// The head carries literal { } (htmx-config JSON, the theme script), and Odin's
	// fmt treats braces as directives, so it is written raw with w() and the
	// dynamic values spliced in between. htmx-config leaves `transitions` off on
	// purpose: the boosted links below are the only swaps that opt in.
	style, scheme := theme.DEFAULT_STYLE, theme.DEFAULT_SCHEME
	if p.brand.style != "" { style, scheme = p.brand.style, p.brand.scheme }
	kept := p.kept_style != "" && p.kept_scheme != "" && theme_known(p.kept_style, p.kept_scheme)
	if kept { style, scheme = p.kept_style, p.kept_scheme }
	w(&b, `<!doctype html>
<html lang="en" `)
	if kept { w(&b, `data-kept `) }
	if p.theme_href != "" {
		w(&b, `data-theme-href="`)
		esc(&b, p.theme_href)
		w(&b, `" `)
	}
	w(&b, `data-style="`)
	esc(&b, style)
	w(&b, `" data-scheme="`)
	esc(&b, scheme)
	w(&b, HEAD_OPEN[p.bundle])
	head_title(&b, p)
	w(&b, `</title>
<meta name="description" content="`)
	esc(&b, p.description)
	w(&b, `">
<meta property="og:type" content="website">
<meta property="og:title" content="`)
	head_title(&b, p)
	w(&b, `">
<meta property="og:description" content="`)
	esc(&b, p.description)
	canonical := p.canonical if p.canonical != "" else p.active
	// canonical and og:url must be absolute, so they carry the origin. The origin
	// and `active` are developer constants (brand.odin, SITE_URL and the nav table),
	// never user input, so they go in raw: url_encode would mangle the scheme.
	w(&b, `">
<meta property="og:site_name" content="`)
	esc(&b, p.brand.suffix)
	w(&b, `">
<meta property="og:url" content="`)
	w(&b, p.origin)
	esc(&b, canonical)
	w(&b, `">
<meta property="og:image" content="`)
	w(&b, p.origin)
	w(&b, p.brand.og_image)
	w(&b, `">
<meta name="twitter:card" content="summary_large_image">
<link rel="canonical" href="`)
	w(&b, p.origin)
	esc(&b, canonical)
	w(&b, `">
<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">
<link rel="stylesheet" href="`)
	w(&b, p.css)
	w(&b, `">
<script>`)
	w(&b, THEME_PREPAINT_JS)
	w(&b, `</script>
<script src="`)
	w(&b, p.htmx)
	nonce_attr(&b, p.nonce)
	w(&b, `" defer></script>
<script src="`)
	w(&b, p.js)
	nonce_attr(&b, p.nonce)
	w(&b, `" defer></script>
`)
	// After app.js, whose gate must be listening before hyperscript initialises
	// anything; after htmx, whose after-process hook hyperscript installs only if
	// htmx is there (05 §3). The behaviours are text hyperscript fetches. None on a
	// Trusted Types page, whose policy hyperscript's `put` can't pass (11 §2.3).
	when CLIENT == "hyperscript" {
		if p.hs != "" {
			w(&b, `<script src="`)
			w(&b, p.hs)
			nonce_attr(&b, p.nonce)
			w(&b, `" defer></script>
<script type="text/hyperscript" src="`)
			w(&b, p.behaviours)
			w(&b, `"></script>
`)
		}
	}
	// The site name a search engine prints above the result; without it the name is
	// derived from the hostname. Google reads WebSite only from the home page, hence
	// the guard, and `name` matches og:site_name on purpose: agreeing signals are
	// what make it pick ours. Values in JSON-LD go through json_esc, not esc:
	// entities aren't decoded inside <script>.
	if p.active == "/" {
		w(&b, `<script type="application/ld+json">
{"@context":"https://schema.org","@type":"WebSite","name":"`)
		json_esc(&b, p.brand.suffix)
		w(&b, `","url":"`)
		json_esc(&b, p.origin)
		w(&b, `/"}
</script>
`)
	}
	w(&b, `<script type="application/ld+json">
{"@context":"https://schema.org","@type":"SoftwareSourceCode","name":"`)
	json_esc(&b, p.brand.source_name)
	w(&b, `","description":"`)
	json_esc(&b, p.description)
	w(&b, `","codeRepository":"`)
	json_esc(&b, p.brand.repo)
	w(&b, `","url":"`)
	json_esc(&b, p.origin)
	w(&b, `/","programmingLanguage":["Odin","HTML","CSS","JavaScript"]}
</script>
</head>
<body`)
	w(&b, `>
<header class="topbar">`)
	// hx-boost turns the brand and nav links into body swaps that push history:
	// no asset re-parse, no theme flash; the server still renders whole pages. On
	// each link, not the <nav>: htmx 4 doesn't inherit it the way htmx 2 did.
	// `transition:true` crossfades these swaps and only these: while a view
	// transition runs, Chromium hit-tests the whole page to <html> and drops
	// clicks, which a fragment swap (the rest of the page live) can't afford.
	w(&b, `
  <a class="brand" href="/"`)
	if p.bundle == .Main { w(&b, BOOST) }
	w(&b, `><span class="brand-mark">`)
	icon(&b, "bolt")
	w(&b, `</span><span class="brand-name">`)
	w(&b, p.brand.wordmark)
	w(&b, `</span></a>
  <nav class="nav" aria-label="Primary">`)
	for item in p.nav {
		cur := item.href == p.active ? ` aria-current="page"` : ""
		boost := BOOST if p.bundle == .Main else ""
		fmt.sbprintf(&b, `<a class="nav-link" href="%s"%s%s>`, item.href, cur, boost)
		icon(&b, item.icon)
		fmt.sbprintf(&b, `<span>%s</span></a>`, item.label)
	}
	w(&b, `</nav>
  `)
	if s := p.brand.search; s.href != "" {
		w(&b, `<form class="search" role="search"`)
		behave(&b, .Search_Box)
		w(&b, `>`)
		icon(&b, "search")
		w(&b, `<input type="search" name="q" placeholder="`)
		esc(&b, s.placeholder)
		w(&b, `" autocomplete="off" aria-label="`)
		esc(&b, s.label)
		w(&b, `"
       hx-get="`)
		w(&b, s.href)
		w(&b, `" hx-trigger="keyup changed delay:250ms, search, focus" hx-target="#search-results" hx-swap="innerHTML"`)
		// On a .Nonce_Csp page hx-csp strips an htmx element without the response's nonce.
		if p.nonce != "" { w(&b, ` hx-nonce="` + NONCE_MARK + `"`) }
		w(&b, `>
    <div id="search-results" class="search-results" tabindex="-1"`)
		behave(&b, .Dismiss)
		w(&b, `></div>
  </form>
  `)
	}
	theme_picker(&b)
	w(&b, `
</header>
<main class="container"`)
	// htmx's history snapshot writes page HTML to sessionStorage, and asks the document for this mark as
	// it saves. So it's on every page but one that opts in, and on <main>: a boost replaces the body's
	// children, and a mark on <body> would stay behind or never arrive (§12).
	if !p.history_cache { w(&b, ` hx-history="false"`) }
	w(&b, `>`)
	w(&b, content)
	w(&b, `</main>
`)
	// Outside <main>, so a fragment swap never takes it; a boosted navigation swaps
	// the body and so opens it again, with the new page's topics (D14).
	w(&b, p.live)
	if p.brand.overlays {
		w(&b, `<div id="overlay"></div>
<!-- hx-preserve keeps this node (and any live toast) across a boosted body swap,
     so navigating to another page doesn't wipe a toast mid-flight. -->
<div id="toasts" class="toasts" aria-live="polite" aria-atomic="false" hx-preserve="true"></div>
`)
	}
	w(&b, `</body>
</html>`)
	return strings.to_string(b)
}

BOOST :: ` hx-boost="true" hx-swap="innerHTML transition:true"`

// ` nonce="…"` on a script tag of a `.Nonce_Csp` page, whose CSP admits scripts by
// nonce alone; nothing elsewhere.
@(private = "file")
nonce_attr :: proc(b: ^strings.Builder, nonce: string) {
	if nonce == "" { return }
	w(b, `" nonce="`)
	w(b, nonce)
}

// The header at the top of every page body. All three are text, escaped here.
page_head :: proc(b: ^strings.Builder, eyebrow, title, subtitle: string) {
	w(b, `<header class="page-head"><p class="eyebrow">`)
	esc(b, eyebrow)
	w(b, `</p><h1>`)
	esc(b, title)
	w(b, `</h1><p class="lede">`)
	esc(b, subtitle)
	w(b, `</p></header>`)
}

// The body of the page a person sees when a full-page request fails (a 404, a
// store error). `title` and `message` are text, escaped here.
error_body :: proc(title, message: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<header class="page-head"><p class="eyebrow">Error</p><h1>`)
	esc(&b, title)
	w(&b, `</h1><p class="lede">`)
	esc(&b, message)
	w(&b, `</p></header><p><a class="btn btn-primary" href="/">Back to the home page</a></p>`)
	return strings.to_string(b)
}

// A toast. `oob` makes it an out-of-band swap, so a handler whose main target is
// elsewhere (a new table row, say) can still drop a toast into #toasts.
toast :: proc(kind, message: string, oob: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	ic, cls: string
	switch kind {
	case "error": ic, cls = "bell", "toast-error"
	case "info":  ic, cls = "bell", "toast-info"
	case:         ic, cls = "check", "toast-success"
	}
	// For an out-of-band toast, htmx's positional swap (beforeend:#toasts) appends
	// the OOB element's *children*, so a throwaway carrier holds the one .toast.
	if oob {
		w(&b, `<div hx-swap-oob="beforeend:#toasts">`)
	}
	fmt.sbprintf(&b, `<div class="toast %s" role="status"`, cls)
	behave(&b, .Toast)
	w(&b, `><span class="toast-icon">`)
	icon(&b, ic)
	w(&b, `</span><p>`)
	esc(&b, message)
	w(&b, `</p><button class="toast-x" type="button" aria-label="Dismiss">×</button></div>`)
	if oob {
		w(&b, `</div>`)
	}
	return strings.to_string(b)
}

// Initials on a stable per-identity hue (the hue from the id, so a person keeps
// their colour across re-renders). The initials are the first character of the
// first two words, whole runes (the É of "Émile" is two bytes), escaped like any
// other text: a name is input.
avatar :: proc(b: ^strings.Builder, id: i64, name: string) {
	fmt.sbprintf(b, `<span class="avatar" style="--h:%d">`, (id % 360) * 47 % 360)
	n := 0
	word_start := true
	for r in name {
		if r == ' ' {
			word_start = true
			continue
		}
		if word_start && n < 2 {
			enc, size := utf8.encode_rune(r) // an invalid byte comes back as a valid U+FFFD
			esc(b, string(enc[:size]))
			n += 1
		}
		word_start = false
	}
	w(b, `</span>`)
}

// A relative time for a log line: "just now", minutes, hours, then days.
time_ago :: proc(at: i64) -> string {
	secs := time.time_to_unix(time.now()) - at
	switch {
	case secs < 60:    return "just now"
	case secs < 3600:  return fmt.tprintf("%d min ago", secs / 60)
	case secs < 86400: return fmt.tprintf("%d h ago", secs / 3600)
	}
	return fmt.tprintf("%d d ago", secs / 86400)
}

// A field's verdict, as the forms and the inline add forms show it.
field_msg :: proc(ok: bool, message: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `<span class="msg msg-%s">`, "ok" if ok else "err")
	esc(&b, message)
	w(&b, `</span>`)
	return strings.to_string(b)
}

// Escapes text while wrapping each case-insensitive occurrence of q in <mark>,
// matching rune by rune as store.contains_ci does, so it marks exactly what the
// search matched. It walks `text` itself: lowering a copy can change its byte
// length (İ → i, ẞ → ß), so an offset found in the copy wouldn't fit the original.
write_highlighted :: proc(b: ^strings.Builder, text, q: string) {
	if q == "" {
		esc(b, text)
		return
	}
	start, i := 0, 0
	for i < len(text) {
		if n, ok := match_ci(text[i:], q); ok {
			esc(b, text[start:i])
			w(b, "<mark>")
			esc(b, text[i:i + n])
			w(b, "</mark>")
			i += n
			start = i
			continue
		}
		_, width := utf8.decode_rune_in_string(text[i:])
		i += width
	}
	esc(b, text[start:])
}

// Byte length of the prefix of s that equals q case-insensitively, if any.
@(private = "file")
match_ci :: proc(s, q: string) -> (n: int, ok: bool) {
	j := 0
	for j < len(q) {
		if n >= len(s) {
			return 0, false
		}
		a, aw := utf8.decode_rune_in_string(s[n:])
		c, cw := utf8.decode_rune_in_string(q[j:])
		if unicode.to_lower(a) != unicode.to_lower(c) {
			return 0, false
		}
		n += aw
		j += cw
	}
	return n, true
}
