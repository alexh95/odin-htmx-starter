package modules_web

// ---- modules: /admin/modules, what this build is (PLAN §15.4, Q28) ---------------------------
//
// Read-only: there is no runtime disabling (Q28), so the page says what the binary was built
// with and is running with. The profile and its family members, the mounted features, every
// route per host with its permission and flags, the main bundle's htmx extensions, the env
// rows (secrets shown only as set), the declared limits, each module's health and the
// migrations in force. It imports no feature: what it shows comes from the platform
// (web.build, which platform/app fills at boot), so it can sit in any profile.

import "core:fmt"
import "core:strings"

import "../../../platform/env"
import "../../../platform/ext"
import "../../../platform/html"
import "../../../platform/obs"
import "../../../platform/store"
import "../../../platform/web"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/admin/modules", page, .Admin_Modules, {.Private, .Lan_Only}, 0},
}

w :: html.w
esc :: html.esc

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	bi := web.build
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Admin", "Modules", "What this build is: its families, features, routes, settings, limits, health and migrations. Nothing here switches at runtime.")

	section(&b, "Build", "modules-build")
	w(&b, `<table class="table"><tbody>`)
	row :: proc(b: ^strings.Builder, k, v: string) {
		w(b, `<tr><th scope="row">`)
		esc(b, k)
		w(b, `</th><td><code>`)
		esc(b, v)
		w(b, `</code></td></tr>`)
	}
	row(&b, "profile", bi.profile)
	row(&b, "store", bi.store)
	row(&b, "identity", bi.identity)
	row(&b, "client", bi.client)
	row(&b, "theme", bi.theme)
	row(&b, "features", strings.join(bi.features, ", ", context.temp_allocator))
	names := make([dynamic]string, context.temp_allocator)
	for e in bi.exts { append(&names, ext.NAMES[e]) }
	row(&b, "htmx extensions", strings.join(names[:], ", ", context.temp_allocator) if len(names) > 0 else "none")
	w(&b, `</tbody></table></section>`)

	section(&b, "Routes", "modules-routes")
	w(&b, `<table class="table"><thead><tr><th>Host</th><th>Feature</th><th>Route</th><th>Permission</th><th>Flags</th></tr></thead><tbody>`)
	for r in bi.routes {
		w(&b, `<tr class="module-route"><td>`)
		esc(&b, r.host)
		w(&b, `</td><td>`)
		esc(&b, r.feature)
		w(&b, `</td><td><code>`)
		esc(&b, r.id)
		w(&b, `</code></td><td>`)
		esc(&b, r.perm)
		w(&b, `</td><td>`)
		flags := make([dynamic]string, context.temp_allocator)
		for f in r.flags { append(&flags, fmt.tprint(f)) }
		esc(&b, strings.join(flags[:], " ", context.temp_allocator))
		w(&b, `</td></tr>`)
	}
	w(&b, `</tbody></table></section>`)

	section(&b, "Settings", "modules-env")
	w(&b, `<table class="table"><thead><tr><th>Variable</th><th>Value</th><th>What it does</th></tr></thead><tbody>`)
	for v in env.values() {
		value := v.text
		if v.row.kind == .Secret { value = "set" if v.text != "" else "unset" } // never the secret
		fmt.sbprintf(&b, `<tr class="module-env%s"><td><code>`, " module-env-set" if v.set else "")
		esc(&b, v.row.name)
		w(&b, `</code></td><td><code>`)
		esc(&b, value)
		w(&b, `</code></td><td>`)
		esc(&b, v.row.doc)
		w(&b, `</td></tr>`)
	}
	w(&b, `</tbody></table></section>`)

	section(&b, "Limits", "modules-limits")
	w(&b, `<table class="table"><tbody>`)
	for l in obs.declared_limits() {
		w(&b, `<tr><td>`)
		esc(&b, l.module)
		w(&b, `</td><td>`)
		esc(&b, l.name)
		fmt.sbprintf(&b, `</td><td>%d `, l.value)
		esc(&b, l.unit)
		w(&b, `</td></tr>`)
	}
	w(&b, `</tbody></table></section>`)

	section(&b, "Health", "modules-health")
	w(&b, `<table class="table"><tbody>`)
	for m in obs.modules() {
		w(&b, `<tr><td>`)
		esc(&b, m.module)
		fmt.sbprintf(&b, `</td><td>%s%s</td><td>`, obs.STATE_NAMES[m.state], " (critical)" if m.critical else "")
		esc(&b, m.message)
		if m.link != "" {
			w(&b, ` <a href="`)
			esc(&b, m.link)
			w(&b, `">Change</a>`)
		}
		w(&b, `</td></tr>`)
	}
	w(&b, `</tbody></table></section>`)

	section(&b, "Migrations", "modules-migrations")
	if len(store.in_force) == 0 {
		w(&b, `<p class="muted">None: this build's store keeps no schema.</p>`)
	} else {
		w(&b, `<table class="table"><tbody>`)
		for mg in store.in_force {
			w(&b, `<tr class="module-migration"><td>`)
			esc(&b, mg.feature)
			fmt.sbprintf(&b, `</td><td>%d</td><td><code>`, mg.seq)
			esc(&b, mg.name)
			w(&b, `</code></td></tr>`)
		}
		w(&b, `</tbody></table>`)
	}
	w(&b, `</section>`)
	web.render_page(req, res, "Modules", "/admin/modules", "What this build is.", strings.to_string(b))
}

@(private)
section :: proc(b: ^strings.Builder, title, id: string) {
	fmt.sbprintf(b, `<section class="block" id="%s"><h2>%s</h2>`, id, title)
}
