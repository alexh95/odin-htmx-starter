package main

// ---- imports: PLAN §5.1's table, package by package --------------------------------------
//
// A layer imports its own layer and the ones below; a feature is a set of
// packages with one row each (models, store, domain, views, switched impl, web,
// identity); only platform/web imports odin-http; a collection is imported only
// where §5.1 says (store:f by f's domain, store:audit by any domain, web or
// identity, identity: and store:. by platform/app, client: and theme: by
// platform/html). The entry packages, cmd/*, import anything.

import "core:fmt"
import "core:strings"

ODIN_HTTP :: "vendor/odin-http"

check_imports :: proc(t: ^Tree) {
	for p in t.pkgs {
		if p.kind == .Other {
			problem("imports", "app/%s: not a package PLAN §5.1 places (cmd, features, stores or a platform layer)", p.path)
			continue
		}
		if p.kind == .Platform && p.layer == 0 {
			problem("imports", "app/%s: a platform package with no layer in PLAN §5.1", p.path)
			continue
		}
		for imp in p.imports {
			if ok, why := allowed(t, p, imp.target); !ok {
				problem("imports", "%s: %s imports %q: %s", where_(imp.node.pos), p.path, imp.raw, why)
			}
		}
	}
}

// A platform package of layer ≤ max.
@(private = "file")
plat :: proc(t: ^Tree, target: string, max: int) -> bool {
	q, ok := t.by_path[target]
	return ok && q.kind == .Platform && q.layer > 0 && q.layer <= max
}

@(private = "file")
of_feature :: proc(t: ^Tree, target: string, kind: Kind, f: string) -> bool {
	q, ok := t.by_path[target]
	return ok && q.kind == kind && q.feature == f
}

allowed :: proc(t: ^Tree, p: ^Pkg, target: string) -> (bool, string) {
	if target == "core" || p.kind == .Entry { return true, "" }
	if target == ODIN_HTTP {
		return p.path == "platform/web", "only platform/web imports odin-http (it re-exports web.Request and web.Response)"
	}
	q, in_tree := t.by_path[target]
	f := p.feature

	switch p.kind {
	case .Platform:
		switch {
		case strings.has_prefix(target, "identity:"):
			return p.path == "platform/app", "only platform/app imports the identity: family"
		case target == "store:.":
			return p.path == "platform/app", "only platform/app imports store:., for the family's NAME"
		case strings.has_prefix(target, "client:"), strings.has_prefix(target, "theme:"):
			return p.path == "platform/html", "only platform/html imports the client: and theme: families"
		case strings.has_prefix(target, "store:"):
			return false, "the platform reaches a feature's store only through main"
		case !in_tree || q.kind != .Platform:
			return false, "the platform imports a feature only through a family"
		case target == "platform/html" && (strings.has_prefix(p.path, "platform/client/") || strings.has_prefix(p.path, "platform/theme/")):
			return false, "a client or theme member never imports platform/html, which imports them"
		case q.layer > p.layer:
			return false, fmt.tprintf("L%d imports L%d: a layer imports its own and the ones below", p.layer, q.layer)
		}
		return true, ""

	case .Family_Root:
		return false, "a family's root holds its NAME and imports nothing"

	case .Models:
		if plat(t, target, 2) { return true, "" }
		return false, "models import core and platform L1–L2 only"

	case .Store:
		switch {
		case of_feature(t, target, .Models, f),
		     target == "platform/store",
		     target == strings.concatenate({"platform/store/", p.family}, context.temp_allocator),
		     target == "platform/sqlite" && p.family == "sqlite",
		     target == "platform/workers",
		     // The memory family's audit log is the process's log: one `mod=audit` line an entry (§17.7).
		     target == "platform/obs" && p.feature == "audit" && p.family == "memory":
			return true, ""
		}
		return false, "a store imports its models, platform/store and its family's store kit, platform/sqlite (SQLite family) and platform/workers only (and the memory audit store, platform/obs)"

	case .Domain:
		switch {
		case of_feature(t, target, .Models, f),
		     target == strings.concatenate({"store:", f}, context.temp_allocator),
		     target == "store:audit",
		     in_tree && q.kind == .Domain && q.feature != f,
		     plat(t, target, 2):
			return true, ""
		case strings.has_prefix(target, "store:"):
			return false, "a domain imports its own store (and store:audit), never another feature's"
		case in_tree && q.kind == .Platform:
			return false, "a domain returns plain values and errors: platform L1–L2 only, never web, html or hub"
		}
		return false, "a domain imports its models, its store, the domains it depends on and platform L1–L2"

	case .Views:
		switch {
		case of_feature(t, target, .Models, f), of_feature(t, target, .Domain, f), target == "platform/html":
			return true, ""
		}
		return false, "views import their models, their domain and platform/html only"

	case .Web:
		// /admin/modules shows the platform's own record of the build, so any profile may mount it (§15.4).
		if f == "modules" && (strings.has_prefix(target, "store:") || in_tree && q.kind != .Platform) {
			return false, "modules imports no feature and no store: what it shows is the platform's"
		}
		switch {
		case of_feature(t, target, .Domain, f),
		     of_feature(t, target, .Models, f),
		     of_feature(t, target, .Views, f),
		     of_feature(t, target, .Impl, f),
		     target == "features/notify/web",
		     target == "store:audit",
		     in_tree && q.kind == .Domain,
		     plat(t, target, 3):
			return true, ""
		case target == "platform/app":
			return false, "features never import platform/app"
		case in_tree && q.kind == .Web:
			return false, "a web package imports no other web package but notify_web: another feature is reached through its domain"
		case strings.has_prefix(target, "store:"):
			return false, "only the domain imports its store"
		}
		return false, "a web package imports its domain, models, views and impls, other features' domains, notify_web, store:audit and platform L1–L3"

	case .Impl:
		switch {
		case of_feature(t, target, .Domain, f),
		     of_feature(t, target, .Models, f),
		     of_feature(t, target, .Views, f),
		     plat(t, target, 3):
			return true, ""
		}
		return false, "a switched implementation imports its domain, models and views and platform L1–L3 only"

	case .Identity:
		switch {
		case target == "features/accounts/models", target == "store:audit", plat(t, target, 3):
			return true, ""
		case p.path == "features/accounts/identity_accounts" && (target == "features/accounts" || target == "features/accounts/views"):
			return true, ""
		}
		return false, "an identity imports accounts_models, store:audit and platform L1–L3"

	case .Storetest:
		switch {
		case of_feature(t, target, .Models, f), of_feature(t, target, .Store, f), plat(t, target, 2):
			return true, ""
		}
		return false, "a store conformance suite imports its models, its stores in each family and platform L1–L2"

	case .Entry, .Other:
	}
	return true, ""
}
