package main

// ---- streams: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) -------------------

import "../../platform/app"
import "../../platform/html"
import "../../platform/hub"
import "../../platform/web"
import about_web "../../features/about/web"
import audit_web "../../features/audit/web"
import bot_web "../../features/bot/web"
import "../../features/chat"
import chat_web "../../features/chat/web"
import find_m "../../features/find/models"
import find_web "../../features/find/web"
import uploads_web "../../features/uploads/web"
import home_web "../../features/home/web"
import "../../features/notes"
import notes_web "../../features/notes/web"
import notify_web "../../features/notify/web"
import ops_web "../../features/ops/web"
import status_web "../../features/status/web"
import "../../features/wiki"
import wiki_web "../../features/wiki/web"
import identity "identity:."

// The home page's cards, in order: a dispatch table, like ROUTES.
HOME_CARDS := [?]html.Home_Card{notify_web.home_card, notes_web.home_card}

// What /find searches: a dispatch table too (PLAN §6).
FIND_SOURCES := [?]find_m.Source {
	{"Chat", .Chat_Read, chat.SEARCH_ENGINE, chat.find, false},
	{"Docs", .Wiki_Read, wiki.SEARCH_ENGINE, wiki.find, true},
}

// Every extension the main bundle needs (D19). Boot refuses a bundle whose
// header says otherwise.
BUNDLE_EXTS :: uploads_web.EXTS + notes_web.EXTS + audit_web.EXTS + chat_web.EXTS + notify_web.EXTS + bot_web.EXTS + ops_web.EXTS + status_web.EXTS + wiki_web.EXTS + find_web.EXTS + home_web.EXTS + about_web.EXTS + identity.EXTS

main :: proc() {
	app.boot("streams")
	home_web.init(HOME_CARDS[:], HOME)
	about_web.init(ABOUT)
	hub.init()
	hub.mount("main", ..TOPICS[:])
	chat_web.init()
	notify_web.init()
	uploads_web.init()
	bot_web.init()
	ops_web.init()
	status_web.init()
	wiki_web.init(WIKI)
	find_web.init(FIND_SOURCES[:])
	app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS)

	notes.seed() // the memory store is always new: the sample notes go in
	chat_web.seed() // and the lobby
	wiki_web.seed() // and the docs

	// The standard set, and browsers' CSP violation reports to /csp-report (§12.2).
	app.serve(HOSTS[:], JOBS[:], &BRAND, web.Header_Set.Reporting)
	bot_web.start()
	app.wait()
	bot_web.drain()
	app.shutdown()
	app.exit()
}
