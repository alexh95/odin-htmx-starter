package main

// ---- full's routes: Houston on SITE_URL, its lab host on SITE_URL_LAB -------------------
//
// Two hosts from one binary (PLAN §7.3, ANSWERS F2): Houston's own pages, with sessions, on the
// main host; every starter demo and lab page on the lab host, where no identity runs and
// nothing sets a cookie, so an eval-capable page never shares an origin with a session. A row
// answers only on the host whose table mounts it. (tools/init composes the main host's tables,
// ROUTES, TOPICS, JOBS and NAV; the lab host's are LAB_*.)

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import "../../platform/workers"
import store_sqlite "../../platform/store/sqlite"
import about_web "../../features/about/web"
import audit_web "../../features/audit/web"
import compat_web "../../features/compat/web"
import contacts_web "../../features/contacts/web"
import dashboard_web "../../features/dashboard/web"
import dbview_web "../../features/dbview/web"
import gallery_web "../../features/gallery/web"
import home_web "../../features/home/web"
import jobs_web "../../features/jobs/web"
import lab_web "../../features/lab/web"
import landing_web "../../features/landing/web"
import modules_web "../../features/modules/web"
import ops_web "../../features/ops/web"
import scripting_web "../../features/scripting/web"
import status_web "../../features/status/web"
import identity "identity:."

ROUTES := [?]app.Mount {
	{"platform", web.ROUTES[:]},        // /healthz /livez /readyz /metrics /sitemap.xml …
	{"platform", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses
	{"platform", web.REPORT_ROUTES[:]}, // /csp-report
	{"platform", hub.ROUTES[:]},        // /events: the topics below
	{"home", {{.Get, "/", home_web.page, .Public, {}, 0}}}, // the root: a card per feature
	{"accounts", identity.ROUTES[:]},   // /login /logout /accounts/sessions
	{"audit", audit_web.ROUTES[:]},     // /admin/audit: the log, LAN only
	{"modules", modules_web.ROUTES[:]}, // /admin/modules: what this build is
	{"ops", ops_web.ROUTES[:]},         // /admin/ops: the 1 Hz panel
	{"jobs", jobs_web.ROUTES[:]},       // /admin/jobs: the jobs and their runs
	{"dbview", dbview_web.ROUTES[:]},   // /admin/dbview: read-only SQL
	{"status", status_web.ROUTES[:]},   // /status: is everything up
	{"about", about_web.ROUTES[:]},     // /about
}

// Mounted by main with hub.mount("main", ..TOPICS[:]).
TOPICS := [?][]hub.Topic {
	identity.TOPICS[:], // the identity's member topics: what a revoke ends
	ops_web.TOPICS[:],  // ops.panel
	jobs_web.TOPICS[:], // jobs.runs
}

// houston-lab: no identity runs here, every row is .Public; every starter demo and lab page.
LAB_ROUTES := [?]app.Mount {
	{"platform", web.ROUTES[:]},        // /healthz … : each host answers them for its own origin
	{"platform", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses
	{"platform", web.REPORT_ROUTES[:]}, // /csp-report
	{"platform", hub.ROUTES[:]},        // /events: LAB_TOPICS
	{"landing", {{.Get, "/", landing_web.page, .Public, {}, 0}}},        // the root: the catalog and the builder
	{"landing", landing_web.ROUTES[:]}, // /landing/command
	{"dashboard", {{.Get, "/dashboard", dashboard_web.page, .Public, {}, 0}}}, // the page skeleton mounts at /
	{"dashboard", dashboard_web.ROUTES[:]}, // /ui/ping
	{"gallery", gallery_web.ROUTES[:]},     // /components /forms /forms/submit /validate/email /ui/*
	{"contacts", contacts_web.ROUTES[:]},   // /data /contacts… /search /api/search
	{"lab", lab_web.ROUTES[:]},         // /lab/streams and the contract endpoints
	{"scripting", scripting_web.ROUTES[:]}, // /scripting: the nonce class (.Lab_Host)
	{"compat", compat_web.ROUTES[:]},   // /compat: htmx-2-compat and hx-alpine-compat (.Lab_Host)
	{"about", about_web.ROUTES[:]},     // /about
}

// Mounted by main with hub.mount("lab", ..LAB_TOPICS[:]).
LAB_TOPICS := [?][]hub.Topic {
	lab_web.TOPICS[:], // lab.bus, lab.feed, lab.room
}

HOSTS := [?]app.Host {
	{"main", "SITE_URL", true, ROUTES[:], NAV[:]},
	{"lab", "SITE_URL_LAB", false, LAB_ROUTES[:], LAB_NAV[:]},
}

// Both hosts' jobs: one scheduler runs them.
JOBS := [?][]workers.Job {
	ops_web.JOBS[:],           // ops.sample: the panel, once a second
	jobs_web.JOBS[:],          // jobs.sync: the runs into the store and the live page
	store_sqlite.JOBS[:],      // store.backup: nightly, the newest 7 kept
	lab_web.JOBS[:],           // lab.bus: the producer's beat
	contacts_web.DEMO_JOBS[:], // contacts.reset: the demo's rows start over each night
}
