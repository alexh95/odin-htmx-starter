package main

// ---- compose: a selection's profile, written from its features' donor lines --------------
//
// A selection is features, closed over their imports, plus one root and four family members
// (PLAN §7.4). Its four profile files are written here: the platform's lines for its families
// (the store's open, migrations and close on SQLite, the hub's when a feature has TOPICS), and
// each feature's lines as its donor profile writes them, in dependency order.

import "core:fmt"
import "core:slice"
import "core:strings"

Selection :: struct {
	name:     string,   // the profile it becomes: app/cmd/<name>
	features: []string, // dependencies first: the order main's statements run in
	order:    []string, // the order of the mounts, the nav and the tables: the base's, then the rest
	root:     string,
	members:  [Family]string,
	base:     ^Profile, // --profile's: its brand, platform mounts and serve's header set too
	explicit: bool,     // the base was asked for, not the default (minimal's brand only)
}

// The root a host gets when the selection names none: the first of these selected, else home.
ROOTS := [?]string{"dashboard", "landing", "home"}

// Closes the selection, picks its root and its families, and refuses what can't build, with
// the advice to fix it.
select :: proc(name: string, base_name: string, features: []string, asked: [Family]string) -> Selection {
	s := Selection{name = name}
	if base_name != "" {
		s.base, s.explicit = profile(base_name), true
		if s.base == nil { problem("no profile %q (odin run tools/init -- --list)", base_name) }
	}
	if s.base == nil { s.base, s.explicit = profile("minimal"), false }
	if s.base == nil {
		problem("no minimal profile to take the brand from: name one with --profile")
		return s
	}
	wanted := make([dynamic]string)
	if s.explicit { append(&wanted, ..s.base.features[:]) }
	for f in features {
		if !slice.contains(wanted[:], f) { append(&wanted, f) }
	}
	if len(wanted) == 0 { problem("an empty selection: name features with --features, or a profile with --profile") }

	// The root: the base's own, if it is selected; else the first of ROOTS; else home joins.
	if s.explicit && slice.contains(wanted[:], s.base.root) { s.root = s.base.root }
	for r in ROOTS {
		if s.root == "" && slice.contains(wanted[:], r) { s.root = r }
	}
	if s.root == "" {
		s.root = "home"
		inject_at(&wanted, 0, "home")
	}
	s.features = closure(wanted[:])
	order := make([dynamic]string)
	if s.explicit {
		for f in s.base.features {
			if slice.contains(s.features, f) { append(&order, f) }
		}
	}
	for f in s.features {
		if !slice.contains(order[:], f) { append(&order, f) }
	}
	s.order = order[:]

	for fam in Family {
		s.members[fam] = asked[fam]
		if s.members[fam] == "" && s.explicit { s.members[fam] = s.base.members[fam] }
	}
	if s.members[.Store] == "" {
		s.members[.Store] = "memory"
		for f in s.features {
			if ft := feature(f); ft != nil && sqlite_need(ft^) == "required" { s.members[.Store] = "sqlite" }
		}
		if mb, ok := member(.Identity, s.members[.Identity]); ok && mb.sqlite { s.members[.Store] = "sqlite" }
	}
	if s.members[.Identity] == "" {
		// Lean (§7.4): nick, unless the selection has a page that needs a session-free origin (§7.3).
		session_free := slice.contains(s.features, "scripting") || slice.contains(s.features, "compat")
		s.members[.Identity] = "nick" if has_member(.Identity, "nick") && !session_free else "anonymous"
	}
	// An identity that is a feature's package (features/accounts/identity_nick) brings its feature, whose
	// mount is the identity's own routes (/login), and the features it reaches itself (identity_accounts
	// audits, so it brings audit); a feature that is an identity's needs it.
	if f := identity_feature(s.members[.Identity]); f != "" {
		brought := make([dynamic]string, context.temp_allocator)
		append(&brought, f)
		if mb, ok := member(.Identity, s.members[.Identity]); ok { append(&brought, ..closure(mb.deps[:])) }
		for g in brought {
			if slice.contains(s.features, g) { continue }
			features := make([dynamic]string)
			append(&features, ..s.features)
			append(&features, g)
			s.features = features[:]
			order := make([dynamic]string)
			about := slice.contains(s.order, "about")
			for h in s.order {
				if h == "about" { append(&order, g) }
				append(&order, h)
			}
			if !about { append(&order, g) }
			s.order = order[:]
		}
	}
	for f in s.features {
		if is_identity_feature(f) && identity_feature(s.members[.Identity]) != f {
			problem("%s holds an identity, so it needs that identity: use --identity %s", f, identity_of_feature(f))
		}
	}
	if s.members[.Identity] == "anonymous" {
		for f in s.features {
			if ft := feature(f); ft != nil && ft.gated {
				problem("%s has pages for members or admins, which need an identity; anonymous has none (scripting and compat ask for a session-free origin, so they leave it out)", f)
			}
		}
	}
	if mb, ok := member(.Identity, s.members[.Identity]); ok && mb.sqlite && s.members[.Store] != "sqlite" {
		problem("--identity %s needs SQLite; use --store sqlite", mb.name)
	}
	if s.members[.Client] == "" { s.members[.Client] = "vanilla" }
	if s.members[.Theme] == "" { s.members[.Theme] = "lite" }
	for fam in Family {
		if !has_member(fam, s.members[fam]) {
			names := make([dynamic]string, context.temp_allocator)
			for m in catalog.members[fam] { append(&names, m.name) }
			problem("--%s %s: no such member (%s)", FAMILY_FLAGS[fam], s.members[fam], strings.join(names[:], ", ", context.temp_allocator))
		}
	}
	for f in s.features {
		ft := feature(f)
		if ft == nil { continue }
		need := sqlite_need(ft^)
		if need == "required" && s.members[.Store] != "sqlite" { problem("%s has no %s store; use --store sqlite", f, s.members[.Store]) }
		if need == "never" && s.members[.Store] != "memory" { problem("%s has no %s store; use --store memory", f, s.members[.Store]) }
		if len(ft.profiles) == 0 { problem("%s is mounted by no committed profile, so it has no lines to take", f) }
	}
	if donor_of_root(s.root) == nil { problem("no committed profile serves %s as its root", s.root) }
	return s
}

// The feature an identity member lives in ("accounts" for nick), or "" (anonymous is the platform's).
identity_feature :: proc(name: string) -> string {
	m, ok := member(.Identity, name)
	if !ok || !strings.has_prefix(m.dir, "features/") { return "" }
	rest := strings.trim_prefix(m.dir, "features/")
	return rest[:strings.index_byte(rest, '/')] if strings.index_byte(rest, '/') >= 0 else rest
}

is_identity_feature :: proc(f: string) -> bool { return identity_of_feature(f) != "" }

// The first identity member that lives in feature `f`.
identity_of_feature :: proc(f: string) -> string {
	for m in catalog.members[.Identity] {
		if identity_feature(m.name) == f { return m.name }
	}
	return ""
}

has_member :: proc(fam: Family, name: string) -> bool {
	_, ok := member(fam, name)
	return ok
}

// The profile whose lines a feature's are: the base, if it mounts the feature; else one on
// the same store family; else any.
donor :: proc(s: Selection, f: string) -> ^Profile {
	if s.base != nil && slice.contains(s.base.features[:], f) { return s.base }
	fallback: ^Profile
	for &p in catalog.profiles {
		if !slice.contains(p.features[:], f) { continue }
		if p.members[.Store] == s.members[.Store] { return &p }
		if fallback == nil { fallback = &p }
	}
	return fallback
}

donor_of_root :: proc(root: string) -> ^Profile {
	for &p in catalog.profiles {
		if p.root == root { return &p }
	}
	return nil
}

// A line is f's to write when it names f and every feature it names is selected (a statement
// that names two features is written once, with the later one).
@(private = "file")
takes :: proc(s: Selection, l: Line, f: string) -> bool {
	if !slice.contains(l.features, f) { return false }
	for g in l.features {
		if !slice.contains(s.features, g) { return false }
		if g != f && index_of(s.features, g) > index_of(s.features, f) { return false }
	}
	return true
}

@(private = "file")
index_of :: proc(xs: []string, x: string) -> int {
	for y, i in xs {
		if y == x { return i }
	}
	return -1
}

// ---- the four files ----------------------------------------------------------------------

Profile_Text :: struct {
	main, routes, brand, routes_test: string,
	notes:                            [dynamic]string, // what the plan prints for the developer to check
}

// The topic line for an identity with member topics of its own; its import comes with its routes.
@(private = "file")
IDENTITY_TOPICS :: "\tidentity.TOPICS[:], // the identity's member topics: what a revoke ends"

compose :: proc(s: Selection) -> Profile_Text {
	out: Profile_Text
	topics, jobs, bundles := false, false, false
	home := slice.contains(s.features, "home")
	for f in s.features {
		ft := feature(f)
		if ft == nil { continue }
		topics ||= .Topics in ft.decls
		jobs ||= .Jobs in ft.decls
		bundles ||= .Bundles in ft.decls
	}
	id_member, _ := member(.Identity, s.members[.Identity])
	topics ||= id_member.topics
	sqlite := s.members[.Store] == "sqlite"
	base := s.base
	root_donor := donor_of_root(s.root)

	// ---- routes.odin
	rimports := make([dynamic]string)
	mounts := make([dynamic]string)
	topic_lines, job_lines := make([dynamic]string), make([dynamic]string)
	if s.explicit {
		for m in base.mounts {
			if m.key == "platform" && !strings.contains(m.text, "hub.ROUTES") { append(&mounts, m.text) }
		}
	} else {
		append(&mounts, "\t{\"platform\", web.ROUTES[:]},        // /healthz /livez /readyz /metrics /sitemap.xml …")
		append(&mounts, "\t{\"platform\", web.PUBLIC_ROUTES[:]}, // /static /robots.txt /favicon.ico /licenses")
	}
	if topics { append(&mounts, "\t{\"platform\", hub.ROUTES[:]},        // /events: the topics below") }
	if root_donor != nil {
		for m in root_donor.mounts {
			if m.root { append(&mounts, m.text); take_imports(&rimports, root_donor, m.text) }
		}
	}
	for f in s.order {
		d := donor(s, f)
		ft := feature(f)
		if d == nil || ft == nil { continue }
		for m in d.mounts {
			if m.key != f || m.root { continue }
			append(&mounts, m.text)
			take_imports(&rimports, d, m.text)
		}
		took_topics, took_jobs := false, false
		for l in d.topics {
			if takes(s, l, f) { append(&topic_lines, l.text); take_imports(&rimports, d, l.text); took_topics = true }
		}
		for l in d.jobs {
			if takes(s, l, f) { append(&job_lines, l.text); take_imports(&rimports, d, l.text); took_jobs = true }
		}
		if .Topics in ft.decls && !took_topics { append(&topic_lines, fmt.aprintf("\t%s_web.TOPICS[:],", f)); take_web_import(&rimports, f) }
		if .Jobs in ft.decls && !took_jobs { append(&job_lines, fmt.aprintf("\t%s_web.JOBS[:],", f)); take_web_import(&rimports, f) }
	}
	if id_member.topics { append(&topic_lines, IDENTITY_TOPICS) }
	{
		b := strings.builder_make()
		head := fmt.tprintf("// ---- %s's routes: one host, one line per mounted table ", s.name)
		fmt.sbprintf(&b, "package main\n\n%s%s\n//\n", head, rule(head))
		fmt.sbprintf(&b, "// Written by tools/init for %s (PLAN §7.2, §7.4); yours to edit from here.\n\n", strings.join(s.features, ", ", context.temp_allocator))
		platform := make([dynamic]string, context.temp_allocator)
		append(&platform, "app", "web")
		if topics { append(&platform, "hub") }
		if jobs { append(&platform, "workers") }
		write_imports(&b, platform[:], rimports[:])
		strings.write_string(&b, "\nROUTES := [?]app.Mount {\n")
		for m in mounts { fmt.sbprintln(&b, m) }
		strings.write_string(&b, "}\n")
		if topics {
			strings.write_string(&b, "\n// Mounted by main with hub.mount(\"main\", ..TOPICS[:]).\nTOPICS := [?][]hub.Topic {\n")
			for l in topic_lines { fmt.sbprintln(&b, l) }
			strings.write_string(&b, "}\n")
		}
		// front loads the viewer where an identity gives one: any but anonymous.
		identity := "false" if s.members[.Identity] == "anonymous" else "true"
		fmt.sbprintf(&b, "\nHOSTS := [?]app.Host{{{{\"main\", \"SITE_URL\", %s, ROUTES[:], NAV[:]}}}}\n", identity)
		if jobs {
			strings.write_string(&b, "\nJOBS := [?][]workers.Job {\n")
			for l in job_lines { fmt.sbprintln(&b, l) }
			strings.write_string(&b, "}\n")
		}
		out.routes = strings.to_string(b)
	}

	// ---- main.odin and routes_test.odin
	mimports := make([dynamic]string)
	phase_lines: [Phase][dynamic]string
	used_copies := make([dynamic]string)
	copy_donor := make(map[string]^Profile)
	for f in s.features {
		d := donor(s, f)
		if d == nil { continue }
		for st in d.stmts {
			if !takes(s, st.line, f) || st.call == "store_sqlite.migrate" { continue }
			if !sqlite && strings.contains(st.text, "store_sqlite.") {
				append(&out.notes, fmt.aprintf("%s: left out `%s`, which needs the SQLite store", f, strings.trim_space(st.text)))
				continue
			}
			if st.phase == .Store && d.members[.Store] != s.members[.Store] {
				append(&out.notes, fmt.aprintf("%s: `%s` comes from %s, a %s profile; check it on %s", f, strings.trim_space(st.text), d.name, d.members[.Store], s.members[.Store]))
			}
			append(&phase_lines[st.phase], st.text)
			take_imports(&mimports, d, st.text)
			for c in d.copies {
				if mentions(st.text, c.key) && !slice.contains(used_copies[:], c.key) {
					append(&used_copies, c.key)
					copy_donor[c.key] = d
				}
			}
		}
	}
	exts, page_bundles, home_cards, migrates := make([dynamic]string), make([dynamic]string), make([dynamic]string), make([dynamic]string)
	for f in s.order {
		ft := feature(f)
		if ft == nil { continue }
		if .Exts in ft.decls { append(&exts, fmt.aprintf("%s_web.EXTS", f)); take_web_import(&mimports, f) }
		if f == identity_feature(s.members[.Identity]) {
			// Its routes are the identity's package, which a profile reaches through the family.
			append(&exts, "identity.EXTS")
			if line := "import identity \"identity:.\""; !slice.contains(mimports[:], line) { append(&mimports, line) }
		}
		if .Bundles in ft.decls { append(&page_bundles, fmt.aprintf("%s_web.BUNDLES", f)); take_web_import(&mimports, f) }
		if home && .Home_Card in ft.decls { append(&home_cards, fmt.aprintf("%s_web.home_card", f)); take_web_import(&mimports, f) }
	}
	for f in s.features {
		ft := feature(f)
		if ft == nil { continue }
		if sqlite && ft.migrations {
			append(&migrates, fmt.aprintf("\tstore_sqlite.migrate(%q, %s_store.MIGRATIONS[:])", f, f))
			if line := fmt.aprintf("import %s_store \"store:%s\"", f, f); !slice.contains(mimports[:], line) { append(&mimports, line) }
		}
	}
	// Each source find's table takes is a selected domain's, and find alone has an empty one.
	find_rows := make([dynamic]string)
	has_find := slice.contains(s.features, "find")
	if has_find {
		append(&mimports, `import find_m "../../features/find/models"`)
		for f in s.features {
			d := donor(s, f)
			if d == nil { continue }
			for l in d.find_rows {
				if !slice.contains(l.features, f) { continue }
				append(&find_rows, l.text)
				take_imports(&mimports, d, l.text)
			}
		}
	}
	jobs_arg := "JOBS[:]" if jobs else "nil"
	check_args := fmt.aprintf("HOSTS[:], %s, BUNDLE_EXTS%s", jobs_arg, ", PAGE_BUNDLES" if bundles else "")
	serve_extra := base.serve_extra if s.explicit else ""
	{
		b := strings.builder_make()
		head := fmt.tprintf("// ---- %s: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) ", s.name)
		fmt.sbprintf(&b, "package main\n\n%s%s\n\n", head, rule(head))
		platform := make([dynamic]string, context.temp_allocator)
		append(&platform, "app")
		if home { append(&platform, "html") }
		if topics { append(&platform, "hub") }
		if strings.contains(serve_extra, "web.") || len(exts) == 0 { append(&platform, "web") }
		if sqlite { append(&platform, "store_sqlite") }
		write_imports(&b, platform[:], mimports[:])
		if home {
			fmt.sbprintf(&b, "\n// The home page's cards, in order: a dispatch table, like ROUTES.\nHOME_CARDS := [%d]html.Home_Card{{%s}}\n",
				len(home_cards), strings.join(home_cards[:], ", ", context.temp_allocator))
		}
		if has_find {
			strings.write_string(&b, "\n// What /find searches: a dispatch table too (PLAN §6).\n")
			fmt.sbprintf(&b, "FIND_SOURCES := [%d]find_m.Source {{\n", len(find_rows))
			for r in find_rows { fmt.sbprintf(&b, "\t%s,\n", r) }
			strings.write_string(&b, "}\n")
		}
		strings.write_string(&b, "\n// Every extension the main bundle needs (D19). Boot refuses a bundle whose\n// header says otherwise.\n")
		fmt.sbprintf(&b, "BUNDLE_EXTS :: %s\n", strings.join(exts[:], " + ", context.temp_allocator) if len(exts) > 0 else "web.Exts{}")
		if bundles {
			strings.write_string(&b, "\n// The fixed bundles its pages load besides Main (§12.1); boot refuses a build that\n// didn't embed them.\n")
			fmt.sbprintf(&b, "PAGE_BUNDLES :: %s\n", strings.join(page_bundles[:], " + ", context.temp_allocator))
		}
		fmt.sbprintf(&b, "\nmain :: proc() {{\n\tapp.boot(%q)\n", s.name)
		for l in phase_lines[.Init] { fmt.sbprintln(&b, l) }
		if sqlite { strings.write_string(&b, "\tstore_sqlite.init() // DB_PATH, SEED, MEMMODE: recorded here so --limits prints them\n") }
		if topics { strings.write_string(&b, "\thub.init()\n\thub.mount(\"main\", ..TOPICS[:])\n") }
		fmt.sbprintf(&b, "\tapp.check(%s)\n", check_args)
		if sqlite || len(phase_lines[.Store]) > 0 { strings.write_string(&b, "\n") }
		if sqlite {
			fmt.sbprintf(&b, "\tstore_sqlite.open(%q)\n", s.name)
			for m in migrates { fmt.sbprintln(&b, m) }
		}
		for l in phase_lines[.Store] { fmt.sbprintln(&b, l) }
		fmt.sbprintf(&b, "\n\tapp.serve(HOSTS[:], %s, &BRAND%s)\n", jobs_arg, strings.concatenate({", ", serve_extra}) if serve_extra != "" else "")
		for l in phase_lines[.Start] { fmt.sbprintln(&b, l) }
		strings.write_string(&b, "\tapp.wait()\n")
		for l in phase_lines[.Drain] { fmt.sbprintln(&b, l) }
		strings.write_string(&b, "\tapp.shutdown()\n")
		if sqlite { strings.write_string(&b, "\tstore_sqlite.close() // the writer's last batch, then the checkpoint\n") }
		strings.write_string(&b, "\tapp.exit()\n}\n")
		out.main = strings.to_string(b)
	}
	{
		t := strings.builder_make()
		strings.write_string(&t, "package main\n\nimport \"core:mem/virtual\"\nimport \"core:testing\"\n\nimport \"../../platform/app\"\n")
		fmt.sbprintf(&t, "\n// The boot checks of §6.1 over this profile's tables, as `CMD=test build.sh %s` runs\n// them in CI: a table that would refuse to boot fails here first.\n", s.name)
		strings.write_string(&t, "@(test)\nboot_checks_pass :: proc(t: ^testing.T) {\n")
		strings.write_string(&t, "\t// What boot keeps for the process's life goes in an arena the test destroys, so\n\t// the runner's leak check sees none of it.\n")
		strings.write_string(&t, "\tarena: virtual.Arena\n\t_ = virtual.arena_init_growing(&arena)\n\tdefer virtual.arena_destroy(&arena)\n")
		strings.write_string(&t, "\tcontext.allocator = virtual.arena_allocator(&arena)\n\tcontext.temp_allocator = context.allocator\n")
		fmt.sbprintf(&t, "\tproblems := app.dry_check(%s)\n\tfor p in problems {{ testing.expectf(t, false, \"%%s\", p) }}\n}}\n", check_args)
		out.routes_test = strings.to_string(t)
	}

	// ---- brand.odin
	{
		bimports := make([dynamic]string)
		nav := make([dynamic]string)
		if root_donor != nil {
			for n in root_donor.nav { if n.root { append(&nav, n.text) } }
		}
		for f in s.order {
			d := donor(s, f)
			if d == nil { continue }
			for n in d.nav { if !n.root && takes(s, n, f) { append(&nav, n.text) } }
		}
		copies := make([dynamic]string)
		for key in used_copies {
			d := copy_donor[key]
			for c in d.copies {
				if c.key == key { append(&copies, c.text); take_imports(&bimports, d, c.text) }
			}
		}
		// The base's names and origin; a page's search box from the profile that mounts that
		// page; the overlays when a feature's pages target them.
		fields := make([dynamic]string)
		for fl in base.brand_fields {
			if fl.key != "search" && fl.key != "overlays" { append(&fields, fl.text) }
		}
		search: for f in s.features {
			d := donor(s, f)
			if d == nil { continue }
			for fl in d.brand_fields {
				if fl.key == "search" && takes(s, fl, f) {
					append(&fields, fl.text)
					break search
				}
			}
		}
		for f in s.features {
			if !needs_overlays(f) { continue }
			// Aligned with the base's fields: `\twordmark    = …`.
			width := strings.index_byte(fields[0], '=') - 1 if len(fields) > 0 else 9
			append(&fields, fmt.aprintf("\t%-*s= true, // #overlay and #toasts, for its modals, drawers and toasts", max(width, 9), "overlays"))
			break
		}
		b := strings.builder_make()
		head := fmt.tprintf("// ---- %s's brand: its names, its nav, its copy ", s.name)
		fmt.sbprintf(&b, "package main\n\n%s%s\n//\n", head, rule(head))
		strings.write_string(&b, "// Written by tools/init (PLAN §7.4). Rename here, not across the features.\n\n")
		write_imports(&b, {"html"}, bimports[:])
		strings.write_string(&b, "\nBRAND := html.Brand {\n")
		for fl in fields { fmt.sbprintln(&b, fl) }
		strings.write_string(&b, "}\n\nNAV := [?]html.Nav_Item {\n")
		for n in nav { fmt.sbprintln(&b, n) }
		strings.write_string(&b, "}\n")
		for c in copies { fmt.sbprintf(&b, "\n%s\n", c) }
		out.brand = strings.to_string(b)
	}
	return out
}

// Whether `text` names `word` as a whole word.
mentions :: proc(text, word: string) -> bool {
	if word == "" { return false }
	at := 0
	for {
		i := strings.index(text[at:], word)
		if i < 0 { return false }
		i += at
		before := i == 0 || !is_word(text[i - 1])
		after := i + len(word) >= len(text) || !is_word(text[i + len(word)])
		if before && after { return true }
		at = i + len(word)
	}
}

is_word :: proc(c: u8) -> bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

// The platform's packages, which the generator imports itself by name ("" for any other).
platform_import :: proc(name: string) -> string {
	switch name {
	case "app", "html", "hub", "web", "workers":
		return fmt.tprintf("import \"../../platform/%s\"", name)
	case "store_sqlite":
		return "import store_sqlite \"../../platform/store/sqlite\""
	}
	return ""
}

// The donor's import lines for every package alias the text uses (`alias.` as a word).
take_imports :: proc(into: ^[dynamic]string, d: ^Profile, text: string) {
	for alias, line in d.imports {
		if platform_import(alias) != "" || !mentions(text, alias) { continue }
		if !strings.contains(text, strings.concatenate({alias, "."}, context.temp_allocator)) { continue }
		if !slice.contains(into[:], line) { append(into, line) }
	}
}

take_web_import :: proc(into: ^[dynamic]string, f: string) {
	line := fmt.aprintf("import %s_web \"../../features/%s/web\"", f, f)
	if !slice.contains(into[:], line) { append(into, line) }
}

// The platform's imports, then the features' and the stores', each group sorted by path as the
// committed profiles have them.
write_imports :: proc(b: ^strings.Builder, platform: []string, rest: []string) {
	lines := make([dynamic]string, context.temp_allocator)
	for p in platform { append(&lines, platform_import(p)) }
	slice.sort_by(lines[:], import_less)
	features := slice.clone(rest, context.temp_allocator)
	slice.sort_by(features, import_less)
	for l in lines { fmt.sbprintln(b, l) }
	for l in features { fmt.sbprintln(b, l) }
}

// By path; a collection's (store:f) after the relative ones.
@(private = "file")
import_less :: proc(a, b: string) -> bool {
	pa, pb := import_path(a), import_path(b)
	sa, sb := strings.contains(pa, ":"), strings.contains(pb, ":")
	if sa != sb { return !sa }
	return pa < pb
}

@(private = "file")
import_path :: proc(line: string) -> string {
	i := strings.index_byte(line, '"')
	if i < 0 { return line }
	return line[i:]
}

// The dashes that carry a section divider to column 92, as the committed files have them.
rule :: proc(head: string) -> string {
	return strings.repeat("-", max(4, 92 - strings.rune_count(head)))
}

// A feature whose pages open modals or drawers, or send toasts, needs the layout's #overlay and
// #toasts (html.Brand.overlays): read from its source, which targets them by id.
needs_overlays :: proc(f: string) -> bool {
	for p in catalog.tree.pkgs {
		if p.feature != f || p.family != "" { continue }
		for _, file in p.ast.files {
			if strings.contains(file.src, "#overlay") || strings.contains(file.src, "#toasts") { return true }
		}
	}
	return false
}
