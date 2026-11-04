package main

// ---- streams' routes and topics: one host ------------------------------------------------

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import "../../platform/workers"
import about_web "../../features/about/web"
import audit_web "../../features/audit/web"
import bot_web "../../features/bot/web"
import chat_web "../../features/chat/web"
import home_web "../../features/home/web"
import notes_web "../../features/notes/web"
import notify_web "../../features/notify/web"
import ops_web "../../features/ops/web"
import status_web "../../features/status/web"
import identity "identity:."

ROUTES := [?]app.Mount {
	{"platform", web.ROUTES[:]},        // /healthz /livez /readyz /metrics /sitemap.xml …
	{"platform", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses
	{"platform", hub.ROUTES[:]},        // /events: the topics below
	{"platform", web.REPORT_ROUTES[:]}, // /csp-report
	{"home", {{.Get, "/", home_web.page, .Public, {}, 0}}}, // the root: a card per feature
	{"notes", notes_web.ROUTES[:]},     // POST /notes
	{"chat", chat_web.ROUTES[:]},       // /chat: rooms, four transports
	{"notify", notify_web.ROUTES[:]},   // /notify: the Inbox
	{"bot", bot_web.ROUTES[:]},         // /bot: the assistant, on the mock
	{"ops", ops_web.ROUTES[:]},         // /admin/ops: the 1 Hz panel
	{"status", status_web.ROUTES[:]},   // /status: is everything up
	{"accounts", identity.ROUTES[:]},   // /login /logout: the nickname form
	{"about", about_web.ROUTES[:]},     // /about
	{"audit", audit_web.ROUTES[:]},     // /admin/audit: chat's moderation (the memory store's log has no rows)
}

// Mounted by main with hub.mount("main", ..TOPICS[:]).
TOPICS := [?][]hub.Topic {
	chat_web.TOPICS[:],   // chat.room, chat.presence, chat.typing
	notify_web.TOPICS[:], // notify.user
	bot_web.TOPICS[:],    // bot.health
	ops_web.TOPICS[:],    // ops.panel
}

HOSTS := [?]app.Host{{"main", "SITE_URL", true, ROUTES[:], NAV[:]}}

JOBS := [?][]workers.Job {
	chat_web.JOBS[:],   // chat.presence: away after the debounce, gone after 5 min; chat.retention: past the age
	notify_web.JOBS[:], // notify.prune: read items after 30 days
	ops_web.JOBS[:],    // ops.sample: the panel, once a second
}
