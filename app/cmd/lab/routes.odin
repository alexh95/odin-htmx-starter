package main

// ---- lab's routes and topics: one host --------------------------------------------------

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import "../../platform/workers"
import about_web "../../features/about/web"
import compat_web "../../features/compat/web"
import landing_web "../../features/landing/web"
import lab_web "../../features/lab/web"
import scripting_web "../../features/scripting/web"
import status_web "../../features/status/web"
import wiki_web "../../features/wiki/web"

ROUTES := [?]app.Mount {
	{"platform", web.ROUTES[:]},        // /healthz /livez /readyz /metrics /sitemap.xml …
	{"platform", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses
	{"platform", hub.ROUTES[:]},        // /events: the topics below
	{"platform", web.REPORT_ROUTES[:]}, // /csp-report
	{"landing", {{.Get, "/", landing_web.page, .Public, {}, 0}}}, // the root: the catalog and the builder
	{"landing", landing_web.ROUTES[:]}, // /landing/command
	{"lab", lab_web.ROUTES[:]},         // /lab/streams and the contract endpoints
	{"scripting", scripting_web.ROUTES[:]}, // /scripting: the nonce class
	{"compat", compat_web.ROUTES[:]},   // /compat: htmx-2-compat and hx-alpine-compat
	{"status", status_web.ROUTES[:]},   // /status: the witness board (STATUS_PROBES)
	{"wiki", wiki_web.ROUTES[:]},       // /wiki: the starter's docs
	{"about", about_web.ROUTES[:]},     // /about
}

// Mounted by main with hub.mount("main", ..TOPICS[:]).
TOPICS := [?][]hub.Topic {
	lab_web.TOPICS[:], // lab.bus, lab.feed, lab.room
}

HOSTS := [?]app.Host{{"main", "SITE_URL", false, ROUTES[:], NAV[:]}}

JOBS := [?][]workers.Job {
	lab_web.JOBS[:], // lab.bus: the producer's beat
}
