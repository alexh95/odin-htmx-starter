package main

// ---- full: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) ----------------------

import "../../platform/app"
import "../../platform/html"
import "../../platform/hub"
import "../../platform/web"
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
import accounts_store "store:accounts"
import audit_store "store:audit"
import contacts_store "store:contacts"
import jobs_store "store:jobs"
import identity "identity:."

// The home page's cards, in order: a dispatch table, like ROUTES.
HOME_CARDS := [?]html.Home_Card{}

// Every extension the main bundle needs (D19), both hosts' pages. Boot refuses a bundle whose
// header says otherwise.
BUNDLE_EXTS :: home_web.EXTS + about_web.EXTS + audit_web.EXTS + modules_web.EXTS + ops_web.EXTS + jobs_web.EXTS + dbview_web.EXTS + status_web.EXTS + identity.EXTS +
	landing_web.EXTS + dashboard_web.EXTS + gallery_web.EXTS + contacts_web.EXTS + lab_web.EXTS +
	scripting_web.EXTS + compat_web.EXTS

// The fixed bundles the lab host's pages load besides Main (§12.1); boot refuses a build that
// didn't embed them.
PAGE_BUNDLES :: scripting_web.BUNDLES + compat_web.BUNDLES

main :: proc() {
	app.boot("full")
	identity.cli() // --hash-password
	home_web.init(HOME_CARDS[:], HOME)
	about_web.init(ABOUT)
	landing_web.init()
	ops_web.init()
	status_web.init()
	lab_web.init()
	contacts_web.demo_init() // CONTACTS_CAP and its nightly reset: the lab host's demo
	store_sqlite.init() // DB_PATH, SEED, MEMMODE: recorded here so --limits prints them
	hub.init()
	hub.mount("main", ..TOPICS[:])
	hub.mount("lab", ..LAB_TOPICS[:])
	app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS, PAGE_BUNDLES)

	store_sqlite.open("full")
	store_sqlite.migrate("accounts", accounts_store.MIGRATIONS[:])
	store_sqlite.migrate("audit", audit_store.MIGRATIONS[:])
	store_sqlite.migrate("contacts", contacts_store.MIGRATIONS[:])
	store_sqlite.migrate("jobs", jobs_store.MIGRATIONS[:])
	identity.bootstrap() // the first admin, from ACCOUNTS_ADMIN_HASH
	jobs_web.init()      // this boot's id; the runs an earlier boot left queued or running
	if store_sqlite.unowned() { contacts_web.seed() } // :memory:, or SEED=1: the lab host's demo rows

	// The standard set, and browsers' CSP violation reports to /csp-report (§12.2). Each host
	// has its own brand: the lab host's says what it is.
	app.serve(HOSTS[:], JOBS[:], &BRAND, web.Header_Set.Reporting, {&BRAND, &LAB_BRAND})
	app.wait()
	app.shutdown()
	store_sqlite.close() // the writer's last batch, then the checkpoint
	app.exit()
}
