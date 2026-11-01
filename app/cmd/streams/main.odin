package main

// ---- streams: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) -------------------

import "../../platform/app"
import "../../platform/html"
import "../../platform/hub"
import "../../platform/web"
import about_web "../../features/about/web"
import bot_web "../../features/bot/web"
import chat_web "../../features/chat/web"
import home_web "../../features/home/web"
import "../../features/notes"
import notes_web "../../features/notes/web"
import notify_web "../../features/notify/web"
import ops_web "../../features/ops/web"
import status_web "../../features/status/web"
import identity "identity:."

// The home page's cards, in order: a dispatch table, like ROUTES.
HOME_CARDS := [?]html.Home_Card{notify_web.home_card, notes_web.home_card}

// Every extension the main bundle needs (D19). Boot refuses a bundle whose
// header says otherwise.
BUNDLE_EXTS :: notes_web.EXTS + chat_web.EXTS + notify_web.EXTS + bot_web.EXTS + ops_web.EXTS + status_web.EXTS + home_web.EXTS + about_web.EXTS + identity.EXTS

main :: proc() {
	app.boot("streams")
	home_web.init(HOME_CARDS[:], HOME)
	about_web.init(ABOUT)
	hub.init()
	hub.mount("main", ..TOPICS[:])
	chat_web.init()
	bot_web.init()
	ops_web.init()
	status_web.init()
	app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS)

	notes.seed() // the memory store is always new: the sample notes go in

	// The standard set, and browsers' CSP violation reports to /csp-report (§12.2).
	app.serve(HOSTS[:], JOBS[:], &BRAND, web.Header_Set.Reporting)
	app.wait()
	app.shutdown()
	app.exit()
}
