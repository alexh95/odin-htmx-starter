package main

// ---- lab: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) -----------------------

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import about_web "../../features/about/web"
import compat_web "../../features/compat/web"
import landing_web "../../features/landing/web"
import lab_web "../../features/lab/web"
import scripting_web "../../features/scripting/web"
import status_web "../../features/status/web"
import wiki_web "../../features/wiki/web"

// Every extension the main bundle needs (D19). Boot refuses a bundle whose
// header says otherwise.
BUNDLE_EXTS :: landing_web.EXTS + lab_web.EXTS + scripting_web.EXTS + compat_web.EXTS + status_web.EXTS + wiki_web.EXTS + about_web.EXTS

// The fixed bundles its pages load besides Main (§12.1); boot refuses a build
// that didn't embed them.
PAGE_BUNDLES :: scripting_web.BUNDLES + compat_web.BUNDLES

main :: proc() {
	app.boot("lab")
	about_web.init(ABOUT)
	landing_web.init()
	status_web.init()
	lab_web.init()
	wiki_web.init(WIKI)
	hub.init()
	hub.mount("main", ..TOPICS[:])
	app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS, PAGE_BUNDLES)
	wiki_web.seed() // the memory store is always new: the docs go in

	// The standard set, and browsers' CSP violation reports to /csp-report (§12.2).
	app.serve(HOSTS[:], JOBS[:], &BRAND, web.Header_Set.Reporting)
	app.wait()
	app.shutdown()
	app.exit()
}
