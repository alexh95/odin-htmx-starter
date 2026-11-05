package main

// ---- the in-place commands: --add, --without, and a family swap ---------------------------
//
// Each edits a committed profile's files where they stand (PLAN §7.4): every change is the
// insertion or the deletion of whole lines, found through the parsed file (a table's closing
// brace, main's calls), with the lines taken from a donor profile as compose takes them. A
// file without the shape a change needs (no `app.check(` call, a table written on one line)
// stops the run, naming the file to edit by hand.

import "core:fmt"
import "core:odin/ast"
import "core:os"
import "core:slice"
import "core:strings"

// Line edits on one file, all against its lines as read: applied together, bottom up.
@(private = "file")
Ops :: struct {
	src:  Src,
	ops:  [dynamic]Line_Op,
	used: bool,
}

edit_profile :: proc(opt: Options) {
	p := target_profile(opt)
	adding := opt.add != ""
	f := opt.add if adding else opt.without
	ft := feature(f)
	if ft == nil { problem("no feature %q (odin run tools/init -- --list)", f) }
	check(selection = true)

	files: map[string]Ops
	for name in PROFILE_FILES {
		if src, ok := p.files[name]; ok { files[name] = Ops{src = src} }
	}
	if adding {
		if slice.contains(p.features[:], f) { fatal(fmt.tprintf("%s already mounts %s", p.name, f)) }
		wanted := make([dynamic]string)
		append(&wanted, ..p.features[:])
		append(&wanted, f)
		s := Selection{name = p.name, features = closure(wanted[:]), root = p.root, members = p.members, base = p, explicit = true}
		check(selection = true)
		added := make([dynamic]string)
		for g in s.features {
			if !slice.contains(p.features[:], g) { append(&added, g) }
		}
		for g in added {
			gf := feature(g)
			need := sqlite_need(gf^)
			if need == "required" && p.members[.Store] != "sqlite" { problem("%s has no %s store: swap %s's store first (--store sqlite --profile %s)", g, p.members[.Store], p.name, p.name) }
			if need == "never" && p.members[.Store] != "memory" { problem("%s has no %s store", g, p.members[.Store]) }
		}
		check(selection = true)
		for g in added { plan_add(&files, p, s, g) }
		fmt.printfln("--add %s to %s: %s", f, p.name, strings.join(added[:], ", "))
	} else {
		if !slice.contains(p.features[:], f) { fatal(fmt.tprintf("%s doesn't mount %s", p.name, f)) }
		if f == p.root { problem("%s is %s's root: a host keeps one root (add another root feature, then edit the root row by hand)", f, p.name) }
		for g in p.features {
			if gf := feature(g); gf != nil && slice.contains(gf.deps[:], f) { problem("%s needs %s (its imports); drop it first", g, f) }
		}
		check(selection = true)
		plan_without(&files, p, f)
		// The feature's own files go when no other profile mounts it.
		others := 0
		for q in catalog.profiles {
			if q.name != p.name && slice.contains(q.features[:], f) { others += 1 }
		}
		if others == 0 {
			remove_tree(join("app/features", f))
			for fam in ft.stores { remove_tree(fmt.aprintf("app/stores/%s/%s", fam, f)) }
			remove_tree_if_present(join("e2e/tests", f))
			remove_tree_if_present(join("load-tests/scenarios", f))
		}
		fmt.printfln("--without %s from %s%s", f, p.name, "" if others == 0 else " (its files stay: another profile mounts it)")
	}
	for _, &o in files {
		if o.used { apply_lines(o.src.path, o.ops[:]) }
	}
	check()
	finish(opt, p)
}

// The profile an in-place command edits: --profile's, else the project's `app`.
@(private = "file")
target_profile :: proc(opt: Options) -> ^Profile {
	name := opt.profile if opt.profile != "" else "app"
	p := profile(name)
	if p == nil {
		fatal(fmt.tprintf("no profile %q to edit: name one with --profile (odin run tools/init -- --list)", name))
	}
	if p.hosts > 1 {
		fatal(fmt.tprintf("%s serves %d hosts, and tools/init edits one-host profiles: edit its files by hand (PLAN §7.3)", name, p.hosts))
	}
	return p
}

// Print the plan, verify, ask, write.
@(private = "file")
finish :: proc(opt: Options, p: ^Profile) {
	print_changes()
	if opt.dry_run {
		fmt.println("Dry run: nothing changed.")
		return
	}
	if opt.verify { verify_profile(p.name) }
	if !opt.yes && !confirm("Apply? [y/N] ") {
		fmt.println("Aborted — nothing changed.")
		os.exit(0)
	}
	commit()
	fmt.printfln("Done: CMD=test ./build.sh %s, then the suites.", p.name)
}

// ---- --add -----------------------------------------------------------------------------------

@(private = "file")
plan_add :: proc(files: ^map[string]Ops, p: ^Profile, s: Selection, g: string) {
	d := donor(s, g)
	gf := feature(g)
	if d == nil || gf == nil { return }
	routes, main, brand := &files["routes"], &files["main"], &files["brand"]

	// routes.odin: its mount lines before ROUTES' closing brace; TOPICS and JOBS lines.
	for m in d.mounts {
		if m.key == g && !m.root { insert_before_close(routes, table_of(p, "routes", "app.Mount"), m.text, "ROUTES") }
	}
	for l in d.topics {
		if slice.contains(l.features, g) { insert_before_close(routes, table_of(p, "routes", "[]hub.Topic"), l.text, "TOPICS") }
	}
	for l in d.jobs {
		if slice.contains(l.features, g) { insert_before_close(routes, table_of(p, "routes", "[]workers.Job"), l.text, "JOBS") }
	}
	add_imports(routes, p, d, d.mounts[:], d.topics[:], d.jobs[:], g)

	// main.odin: BUNDLE_EXTS, PAGE_BUNDLES, HOME_CARDS, the statements by phase, the migration.
	if .Exts in gf.decls { append_term(main, p, "BUNDLE_EXTS", fmt.tprintf("%s_web.EXTS", g)) }
	if .Bundles in gf.decls { append_term(main, p, "PAGE_BUNDLES", fmt.tprintf("%s_web.BUNDLES", g)) }
	if .Home_Card in gf.decls && slice.contains(p.features[:], "home") { append_elem(main, p, "HOME_CARDS", fmt.tprintf("%s_web.home_card", g)) }
	if slice.contains(p.features[:], "find") {
		for l in d.find_rows {
			if slice.contains(l.features, g) { insert_before_close(main, table_of(p, "main", "find_m.Source"), strings.concatenate({"\t", l.text, ","}), "FIND_SOURCES") }
		}
	}
	for st in d.stmts {
		if !slice.contains(st.features, g) || st.call == "store_sqlite.migrate" || !all_in(st.features, s.features) { continue }
		at := phase_anchor(main, st.phase)
		if at >= 0 { insert_at(main, at, st.text) }
	}
	if p.members[.Store] == "sqlite" && gf.migrations {
		at := after_last_call(main, "store_sqlite.migrate", "store_sqlite.open")
		if at >= 0 { insert_at(main, at, fmt.tprintf("\tstore_sqlite.migrate(%q, %s_store.MIGRATIONS[:])", g, g)) }
		add_import_line(main, fmt.tprintf("import %s_store \"store:%s\"", g, g))
	}
	main_lines := make([dynamic]Line, context.temp_allocator)
	for st in d.stmts { append(&main_lines, st.line) }
	add_imports(main, p, d, main_lines[:], nil, nil, g)
	if .Exts in gf.decls || .Bundles in gf.decls || .Home_Card in gf.decls { add_import_line(main, fmt.tprintf("import %s_web \"../../features/%s/web\"", g, g)) }

	// brand.odin: its nav entries before NAV's closing brace; the copy its statements take.
	for n in d.nav {
		if !n.root && slice.contains(n.features, g) { insert_before_close(brand, table_of(p, "brand", "html.Nav_Item"), n.text, "NAV") }
	}
	for c in d.copies {
		used := false
		for st in d.stmts { used ||= slice.contains(st.features, g) && mentions(st.text, c.key) }
		if !used { continue }
		if _, has := decl(p.pkg, c.key); has { continue }
		append(&brand.ops, Line_Op{at = len(brand.src.lines), insert = slice.clone([]string{"", c.text})})
		brand.used = true
		add_imports(brand, p, d, []Line{c}, nil, nil, g)
	}
}

// ---- --without -----------------------------------------------------------------------------

@(private = "file")
plan_without :: proc(files: ^map[string]Ops, p: ^Profile, f: string) {
	routes, main, brand := &files["routes"], &files["main"], &files["brand"]
	for m in p.mounts {
		if m.key == f { delete_text(routes, m.text) }
	}
	for l in p.topics {
		if slice.contains(l.features, f) { delete_text(routes, l.text) }
	}
	for l in p.jobs {
		if slice.contains(l.features, f) { delete_text(routes, l.text) }
	}
	for st in p.stmts {
		if slice.contains(st.features, f) { delete_text(main, st.text) }
	}
	drop_term(main, p, "BUNDLE_EXTS", fmt.tprintf("%s_web.EXTS", f))
	drop_term(main, p, "PAGE_BUNDLES", fmt.tprintf("%s_web.BUNDLES", f))
	drop_term(main, p, "HOME_CARDS", fmt.tprintf("%s_web.home_card", f))
	for l in p.find_rows {
		if slice.contains(l.features, f) { delete_text(main, strings.concatenate({"\t", l.text, ","})) }
	}
	for n in p.nav {
		if !n.root && slice.contains(n.features, f) { delete_text(brand, n.text) }
	}
	for c in p.copies {
		if len(c.features) == 1 && c.features[0] == f { delete_text(brand, c.text) }
	}
	// Its packages' imports, in every file.
	for name in PROFILE_FILES {
		o := &files[name]
		if o.src.file == nil { continue }
		for imp in o.src.file.imports {
			target := resolve(join("cmd", p.name), strings.trim(imp.relpath.text, "\"`"))
			if feature_of_target(target) == f { delete_line(o, imp.pos.line - 1) }
		}
	}
}

// ---- a family swap -------------------------------------------------------------------------

family_command :: proc(opt: Options) {
	if opt.profile == "" { fatal("a family swap edits one profile: name it with --profile") }
	p := target_profile(opt)
	for fam in Family {
		want := opt.members[fam]
		if want == "" || want == p.members[fam] { continue }
		if !has_member(fam, want) { problem("--%s %s: no such member", FAMILY_FLAGS[fam], want) }
	}
	store, id := p.members[.Store], p.members[.Identity]
	if opt.members[.Store] != "" { store = opt.members[.Store] }
	if opt.members[.Identity] != "" { id = opt.members[.Identity] }
	if mb, ok := member(.Identity, id); ok && mb.sqlite && store != "sqlite" {
		problem("--identity %s needs SQLite: %s's store would be %s", id, p.name, store)
	}
	if want := opt.members[.Store]; want != "" && want != p.members[.Store] {
		for g in p.features {
			gf := feature(g)
			if gf == nil { continue }
			if need := sqlite_need(gf^); (need == "required" && want != "sqlite") || (need == "never" && want != "memory") {
				problem("%s has no %s store", g, want)
			}
		}
	}
	check(selection = true)

	// build.sh's row and build.bat's block for the profile: a member by name, the identity by
	// its directory.
	sh_repls, bat_repls := make([dynamic]Repl), make([dynamic]Repl)
	for fam in Family {
		want := opt.members[fam]
		if want == "" || want == p.members[fam] { continue }
		old_v, new_v := p.members[fam], want
		if fam == .Identity { old_v, new_v = member_dir(fam, old_v), member_dir(fam, new_v) }
		append(&sh_repls, Repl{strings.concatenate({BUILD_SH_KEYS[fam], old_v, " "}), strings.concatenate({BUILD_SH_KEYS[fam], new_v, " "})})
		append(&bat_repls, Repl{fmt.aprintf("set \"%s%s\"", BUILD_BAT_KEYS[fam], old_v), fmt.aprintf("set \"%s%s\"", BUILD_BAT_KEYS[fam], new_v)})
	}
	edit_row("build.sh", fmt.tprintf("  %s)", p.name), sh_repls[:])
	edit_block("build.bat", fmt.tprintf("\"%%P%%\"==\"%s\" (", p.name), bat_repls[:])

	// A store swap moves main's store lines: the SQLite store's open, migrations and close.
	if want := opt.members[.Store]; want != "" && want != p.members[.Store] {
		files: map[string]Ops
		files["main"] = Ops{src = p.files["main"]}
		main := &files["main"]
		if want == "sqlite" {
			add_import_line(main, "import store_sqlite \"../../platform/store/sqlite\"")
			if at := call_line(main, "app.check"); at >= 0 {
				insert_at(main, at, "\tstore_sqlite.init() // DB_PATH, SEED, MEMMODE: recorded here so --limits prints them")
				lines := make([dynamic]string, context.temp_allocator)
				append(&lines, fmt.tprintf("\tstore_sqlite.open(%q)", p.name))
				for g in p.features {
					if gf := feature(g); gf != nil && gf.migrations {
						append(&lines, fmt.tprintf("\tstore_sqlite.migrate(%q, %s_store.MIGRATIONS[:])", g, g))
						add_import_line(main, fmt.tprintf("import %s_store \"store:%s\"", g, g))
					}
				}
				insert_at(main, at + 1, ..lines[:])
			}
			if at := call_line(main, "app.exit"); at >= 0 { insert_at(main, at, "\tstore_sqlite.close() // the writer's last batch, then the checkpoint") }
		} else {
			for name in ([]string{"store_sqlite.init", "store_sqlite.open", "store_sqlite.migrate", "store_sqlite.close"}) {
				for at in call_lines(main, name) { delete_line(main, at) }
			}
			for imp in main.src.file.imports {
				raw := strings.trim(imp.relpath.text, "\"`")
				if raw == "../../platform/store/sqlite" || strings.has_prefix(raw, "store:") { delete_line(main, imp.pos.line - 1) }
			}
		}
		apply_lines(main.src.path, main.ops[:])
		// What a feature does with its store at boot was written for the old one.
		for st in p.stmts {
			if st.phase == .Store && st.call != "store_sqlite.migrate" {
				fmt.printfln("  check    `%s`: written for %s, kept as it is", strings.trim_space(st.text), p.members[.Store])
			}
		}
	}
	check()
	finish(opt, p)
}

@(private = "file")
BUILD_SH_KEYS := [Family]string{.Store = "store=", .Identity = "id=", .Client = "client=", .Theme = "theme="}
@(private = "file")
BUILD_BAT_KEYS := [Family]string{.Store = "STORE=", .Identity = "ID=", .Client = "CLIENT=", .Theme = "THEME="}

@(private = "file")
all_in :: proc(xs, set: []string) -> bool {
	for x in xs {
		if !slice.contains(set, x) { return false }
	}
	return true
}

// The line of a file that starts with `prefix` (build.sh's row for a profile).
@(private = "file")
edit_row :: proc(path, prefix: string, repls: []Repl) {
	if len(repls) == 0 { return }
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		problem("%s: not found", path)
		return
	}
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		if !strings.has_prefix(line, prefix) { continue }
		s := line
		for r in repls {
			if !strings.contains(s, r.old) { problem("%s: the %s row has no %q", path, prefix, r.old) }
			s, _ = strings.replace_all(s, r.old, r.new)
		}
		edit(path, {{line, s}})
		return
	}
	problem("%s: no row starting %q", path, prefix)
}

// build.bat's block for one profile: from its test to the next `)`.
@(private = "file")
edit_block :: proc(path, test: string, repls: []Repl) {
	if len(repls) == 0 { return }
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		problem("%s: not found", path)
		return
	}
	text := string(data)
	at := strings.index(text, test)
	if at < 0 {
		problem("%s: no %s block", path, test)
		return
	}
	end := strings.index(text[at + len(test):], ")")
	if end < 0 { end = len(text) - at - len(test) }
	block := text[at:at + len(test) + end]
	s := block
	for r in repls {
		if !strings.contains(s, r.old) { problem("%s: the %s block has no %q", path, test, r.old) }
		s, _ = strings.replace_all(s, r.old, r.new)
	}
	edit(path, {{block, s}})
}

// ---- line ops -------------------------------------------------------------------------------

@(private = "file")
insert_at :: proc(o: ^Ops, at: int, lines: ..string) {
	append(&o.ops, Line_Op{at = at, insert = slice.clone(lines)})
	o.used = true
}

@(private = "file")
delete_line :: proc(o: ^Ops, at: int) {
	for op in o.ops {
		if op.delete && op.at == at { return }
	}
	append(&o.ops, Line_Op{at = at, delete = true})
	o.used = true
}

// Deletes the lines `text` spans, found as written.
@(private = "file")
delete_text :: proc(o: ^Ops, text: string) {
	first := strings.split_lines(text)
	for i := 0; i + len(first) <= len(o.src.lines); i += 1 {
		match := true
		for l, k in first { match = match && o.src.lines[i + k] == l }
		if !match { continue }
		for k in 0 ..< len(first) { delete_line(o, i + k) }
		return
	}
	problem("%s: can't find %q to remove; edit it by hand", o.src.path, first[0])
}

// The closing line of a package-level table whose elements are `elem_type`.
@(private = "file")
table_of :: proc(p: ^Profile, file, elem_type: string) -> ^ast.Comp_Lit {
	src, ok := p.files[file]
	if !ok { return nil }
	for d in src.file.decls {
		vd, vok := d.derived_stmt.(^ast.Value_Decl)
		if !vok || len(vd.values) != 1 { continue }
		if cl, is := comp_lit(vd.values[0]); is && comp_elem_type(cl) == elem_type { return cl }
	}
	return nil
}

@(private = "file")
insert_before_close :: proc(o: ^Ops, cl: ^ast.Comp_Lit, text: string, table: string) {
	if cl == nil {
		problem("%s: no %s table for %q; add the table by hand first", o.src.path, table, strings.trim_space(text))
		return
	}
	if cl.close.line == cl.open.line {
		problem("%s: %s is on one line; break it over lines to add to it", o.src.path, table)
		return
	}
	insert_at(o, cl.close.line - 1, text)
}

// The line of main's statement calling `name` ("app.check"); -1 (and a problem) if none.
@(private = "file")
call_line :: proc(o: ^Ops, name: string) -> int {
	lines := call_lines(o, name)
	if len(lines) == 0 {
		problem("%s: no `%s(` call to anchor on", o.src.path, name)
		return -1
	}
	return lines[0]
}

@(private = "file")
call_lines :: proc(o: ^Ops, name: string) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	for line, i in o.src.lines {
		if strings.has_prefix(strings.trim_space(line), strings.concatenate({name, "("}, context.temp_allocator)) { append(&out, i) }
	}
	return out[:]
}

// After the last call to `name`, else after the first call to `fallback`.
@(private = "file")
after_last_call :: proc(o: ^Ops, name, fallback: string) -> int {
	if lines := call_lines(o, name); len(lines) > 0 { return lines[len(lines) - 1] + 1 }
	if at := call_line(o, fallback); at >= 0 { return at + 1 }
	return -1
}

// Where a phase's statement goes: an init before app.check; the store's work before the blank
// line above app.serve; a start after app.serve; a drain after app.wait.
@(private = "file")
phase_anchor :: proc(o: ^Ops, phase: Phase) -> int {
	switch phase {
	case .Init:  return call_line(o, "app.check")
	case .Store:
		// Above app.serve's comment and the blank line before it: the store's work ends there.
		at := call_line(o, "app.serve")
		for at > 0 && strings.has_prefix(strings.trim_space(o.src.lines[at - 1]), "//") { at -= 1 }
		if at > 0 && strings.trim_space(o.src.lines[at - 1]) == "" { at -= 1 }
		return at
	case .Start:
		at := call_line(o, "app.serve")
		return at + 1 if at >= 0 else -1
	case .Drain:
		at := call_line(o, "app.wait")
		return at + 1 if at >= 0 else -1
	}
	return -1
}

// `NAME :: a + b` gets ` + term`; a missing table is a problem (it takes more than one line).
@(private = "file")
append_term :: proc(o: ^Ops, p: ^Profile, name, term: string) {
	at := decl_line(o, name)
	if at < 0 {
		problem("%s: no %s to add %s to; add `%s :: %s` by hand", o.src.path, name, term, name, term)
		return
	}
	line := o.src.lines[at]
	if mentions(line, term) { return }
	delete_line(o, at)
	insert_at(o, at, strings.concatenate({strings.trim_right_space(line), " + ", term}))
}

// `NAME := [n]T{a, b}` gets `, elem` (and n+1).
@(private = "file")
append_elem :: proc(o: ^Ops, p: ^Profile, name, elem: string) {
	at := decl_line(o, name)
	if at < 0 { return }
	line := o.src.lines[at]
	close := strings.last_index_byte(line, '}')
	open := strings.index_byte(line, '{')
	if close < 0 || open < 0 || close < open {
		problem("%s: %s isn't on one line; add %s by hand", o.src.path, name, elem)
		return
	}
	inner := strings.trim_space(line[open + 1:close])
	out := strings.concatenate({line[:open + 1], inner, ", " if inner != "" else "", elem, line[close:]})
	out = bump_count(out)
	delete_line(o, at)
	insert_at(o, at, out)
}

// The term or element out of a one-line decl, wherever it sits.
@(private = "file")
drop_term :: proc(o: ^Ops, p: ^Profile, name, term: string) {
	at := decl_line(o, name)
	if at < 0 { return }
	line := o.src.lines[at]
	if !mentions(line, term) { return }
	out := line
	for sep in ([]string{" + ", ", "}) {
		out, _ = strings.replace_all(out, strings.concatenate({sep, term}, context.temp_allocator), "")
		out, _ = strings.replace_all(out, strings.concatenate({term, sep}, context.temp_allocator), "")
	}
	if mentions(out, term) {
		// The only one: BUNDLE_EXTS goes to an empty set; a table to none.
		out, _ = strings.replace_all(out, term, "web.Exts{}" if name == "BUNDLE_EXTS" else "")
	}
	out = bump_count(out, -1) if name == "HOME_CARDS" else out
	delete_line(o, at)
	insert_at(o, at, out)
}

// `[2]html.Home_Card{…}` → `[3]…` (or `[1]`).
@(private = "file")
bump_count :: proc(line: string, by := 1) -> string {
	open := strings.index(line, "[")
	close := strings.index(line, "]")
	if open < 0 || close <= open + 1 { return line }
	n, ok := parse_small(line[open + 1:close])
	if !ok { return line }
	return fmt.tprintf("%s[%d]%s", line[:open], n + by, line[close + 1:])
}

@(private = "file")
parse_small :: proc(s: string) -> (int, bool) {
	n := 0
	if len(s) == 0 { return 0, false }
	for c in transmute([]byte)s {
		if c < '0' || c > '9' { return 0, false }
		n = n * 10 + int(c - '0')
	}
	return n, true
}

@(private = "file")
decl_line :: proc(o: ^Ops, name: string) -> int {
	for line, i in o.src.lines {
		t := strings.trim_space(line)
		if strings.has_prefix(t, strings.concatenate({name, " ::"}, context.temp_allocator)) || strings.has_prefix(t, strings.concatenate({name, " :="}, context.temp_allocator)) { return i }
	}
	return -1
}

// The donor's imports for the aliases of `g`'s lines; none the file has already.
@(private = "file")
add_imports :: proc(o: ^Ops, p: ^Profile, d: ^Profile, a, b, c: []Line, g: string) {
	want := make([dynamic]string, context.temp_allocator)
	for set in ([][]Line{a, b, c}) {
		for l in set {
			if slice.contains(l.features, g) { take_imports(&want, d, l.text) }
		}
	}
	for line in want { add_import_line(o, line) }
}

@(private = "file")
add_import_line :: proc(o: ^Ops, line: string) {
	if o.src.file == nil { return }
	last := -1
	for imp in o.src.file.imports {
		if o.src.lines[imp.pos.line - 1] == line { return }
		last = max(last, imp.pos.line - 1)
	}
	for op in o.ops {
		if !op.delete && len(op.insert) == 1 && op.insert[0] == line { return }
	}
	if last < 0 {
		problem("%s: no import block to add %q to", o.src.path, line)
		return
	}
	insert_at(o, last + 1, line)
}
