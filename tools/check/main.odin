package main

// ---- check: what the compiler can't hold a profile to (PLAN §6.1, §19.2.1) ----------------
//
//   odin run tools/check -- <check> [<check> …] [--root DIR]
//
//   imports    every app package's imports against PLAN §5.1's table
//   profile    each profile mounts every web package it imports and calls its
//              init, names each mount by its feature, and migrates every SQLite
//              store it reaches; no ROUTES table that no profile mounts
//   routes     per host: each row inside its feature's prefixes (the README
//              exceptions of D9), no router key claimed by two features, one
//              root, written in the profile and never in a package's ROUTES
//   contracts  every proc type of a feature's store contract has its typed
//              constant in that feature's store in each family; every identity
//              checks authz.Load_Viewer
//   topics     each TOPICS family its feature's and declared once, mounted by
//              hub.mount on every host that mounts its package; a literal
//              publish names a declared family
//   exts       every mounted web package declares EXTS; BUNDLE_EXTS and
//              PAGE_BUNDLES name exactly the mounted packages with EXTS or BUNDLES
//   locks      no package names core:sync's locks but the platform packages in
//              RAW_LOCK_OWNERS, each with its reason: a lock a handler takes is a
//              guard.Mutex, so a trap under it is dirty (D15)
//   parity     every route of each built profile reached by the e2e run and by
//              the load run, or waived with a reason in tests/parity-waivers.txt
//              (PLAN §19.1.11)
//   all        imports, profile, routes, contracts, topics, exts and locks (parity needs the runs)
//
// It reads the source with core:odin/parser and builds nothing; parity alone
// asks the built binaries (`--routes --json`) and reads the suites' counter
// files. --root is a repo-shaped tree to check instead of this one: the bad
// fixture in testdata/ trips every check. Exit 1 on any problem.

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:slice"
import "core:strings"

COMMANDS := [?]string{"imports", "profile", "routes", "contracts", "topics", "exts", "locks", "parity"}

main :: proc() {
	root := "."
	cmds := make([dynamic]string)
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		switch a := args[i]; a {
		case "--root":
			if i + 1 >= len(args) { usage() }
			i += 1
			root = args[i]
		case "all":
			append(&cmds, "imports", "profile", "routes", "contracts", "topics", "exts", "locks")
		case:
			if !slice.contains(COMMANDS[:], a) { usage() }
			append(&cmds, a)
		}
	}
	if len(cmds) == 0 { usage() }

	tree := load(root)
	for c in cmds {
		switch c {
		case "imports":   check_imports(&tree)
		case "profile":   check_profiles(&tree)
		case "routes":    check_routes(&tree)
		case "contracts": check_contracts(&tree)
		case "topics":    check_topics(&tree)
		case "exts":      check_exts(&tree)
		case "locks":     check_locks(&tree)
		case "parity":    check_parity(&tree)
		}
	}
	for p in problems { fmt.println(p) }
	if len(problems) > 0 {
		fmt.eprintfln("check: %d problem%s", len(problems), "" if len(problems) == 1 else "s")
		os.exit(1)
	}
}

usage :: proc() {
	fmt.eprintln("usage: odin run tools/check -- <imports|profile|routes|contracts|topics|exts|locks|parity|all> … [--root DIR]")
	os.exit(2)
}

// ---- problems ------------------------------------------------------------------------

problems: [dynamic]string

// Once each: a row two profiles mount is one problem, not two.
problem :: proc(check: string, format: string, args: ..any) {
	msg := fmt.aprintf("%s: %s", check, fmt.tprintf(format, ..args))
	if !slice.contains(problems[:], msg) { append(&problems, msg) }
}

// The tree's root as an absolute path, which the parser's positions start with.
root_abs: string

// "app/cmd/skeleton/routes.odin:17", from the tree's root.
where_ :: proc(pos: tokenizer.Pos) -> string {
	file := strings.trim_prefix(slashed(pos.file), root_abs)
	return fmt.tprintf("%s:%d", strings.trim_left(file, "/"), pos.line)
}

// ---- the tree: every app package, parsed --------------------------------------------

Kind :: enum {
	Other,       // a directory PLAN §5.1 doesn't place
	Entry,       // app/cmd/<p>
	Models,      // app/features/f/models
	Domain,      // app/features/f
	Views,       // app/features/f/views
	Web,         // app/features/f/web
	Impl,        // app/features/f/<axis>_<impl>, a switched implementation
	Identity,    // app/features/accounts/identity_<x>
	Storetest,   // app/features/f/storetest: both families' stores in one test
	Store,       // app/stores/<family>/f
	Family_Root, // app/stores/<family>: the family's NAME
	Platform,    // app/platform/…, with its layer
}

Import :: struct {
	alias:  string, // the name it's used by in the file
	raw:    string, // as written: "../../platform/web", "store:contacts"
	target: string, // app-relative ("platform/web"), a collection ("store:contacts") or "core"
	node:   ^ast.Import_Decl,
}

Pkg :: struct {
	path:    string, // app-relative, "/"-separated: "features/contacts/web"
	name:    string, // the Odin package name
	kind:    Kind,
	feature: string, // f, for feature packages and stores; the profile, for an entry
	family:  string, // a store's family
	layer:   int,    // a platform package's layer, 1–4; 0 = none
	imports: [dynamic]Import,
	ast:     ^ast.Package,
}

Tree :: struct {
	root:    string, // the repo root: app/ and build.sh are under it
	pkgs:    [dynamic]^Pkg,
	by_path: map[string]^Pkg,
}

// Not packages of the app: what the build reads or writes beside them.
SKIP_DIRS := [?]string{"vendor", "bin", "build", "static", "migrations", "testdata", "node_modules"}

load :: proc(root: string) -> Tree {
	t := Tree{root = root}
	abs, _ := os.get_absolute_path(root, context.allocator)
	root_abs = slashed(abs)
	walk_dir(&t, strings.concatenate({root, "/app"}), "")
	for p in t.pkgs { t.by_path[p.path] = p }
	return t
}

@(private = "file")
walk_dir :: proc(t: ^Tree, dir, rel: string) {
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil {
		problem("load", "can't read %s (%v)", dir, err)
		return
	}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool { return a.name < b.name })
	has_odin := false
	for e in entries {
		if e.type == .Directory {
			if slice.contains(SKIP_DIRS[:], e.name) { continue }
			walk_dir(t, strings.concatenate({dir, "/", e.name}), e.name if rel == "" else strings.concatenate({rel, "/", e.name}))
		} else if strings.has_suffix(e.name, ".odin") {
			has_odin = true
		}
	}
	if !has_odin || rel == "" { return }

	pkg, ok := parser.parse_package_from_path(dir)
	if !ok {
		problem("load", "app/%s doesn't parse", rel)
		return
	}
	p := new(Pkg)
	p.path, p.ast = rel, pkg
	classify(p)
	for _, f in pkg.files {
		p.name = f.pkg_name
		for imp in f.imports {
			raw := strings.trim(imp.relpath.text, "\"`")
			alias := imp.name.text
			append(&p.imports, Import{alias, raw, resolve(rel, raw), imp})
		}
	}
	append(&t.pkgs, p)
}

classify :: proc(p: ^Pkg) {
	parts := strings.split(p.path, "/")
	switch parts[0] {
	case "cmd":
		if len(parts) == 2 { p.kind, p.feature = .Entry, parts[1] }
	case "features":
		p.feature = parts[1]
		switch len(parts) {
		case 2: p.kind = .Domain
		case 3:
			switch parts[2] {
			case "models":    p.kind = .Models
			case "views":     p.kind = .Views
			case "web":       p.kind = .Web
			case "storetest": p.kind = .Storetest
			case:             p.kind = .Identity if strings.has_prefix(parts[2], "identity_") else .Impl
			}
		}
	case "stores":
		switch len(parts) {
		case 2: p.kind, p.family = .Family_Root, parts[1]
		case 3: p.kind, p.family, p.feature = .Store, parts[1], parts[2]
		}
	case "platform":
		p.kind, p.layer = .Platform, layer_of(p.path)
		p.feature = "platform"
	}
}

// PLAN §5.1's platform layers. 0: a platform package the table doesn't place.
layer_of :: proc(path: string) -> int {
	switch path {
	case "platform/sys", "platform/sqlite", "platform/ext", "platform/escape":
		return 1
	case "platform/store", "platform/store/sqlite", "platform/store/memory", "platform/env", "platform/workers",
	     "platform/authz", "platform/authz/anonymous", "platform/obs", "platform/guard", "platform/markdown",
	     "platform/password", "platform/totp":
		return 2
	case "platform/web", "platform/html", "platform/hub", "platform/stream", "platform/stream/client":
		return 3
	case "platform/app":
		return 4
	}
	if strings.has_prefix(path, "platform/client/") || strings.has_prefix(path, "platform/theme/") { return 3 }
	return 0
}

// An import as the tree sees it: core and base are "core", a collection stays
// as written, and a relative path becomes app-relative.
resolve :: proc(from, raw: string) -> string {
	if i := strings.index_byte(raw, ':'); i >= 0 {
		switch raw[:i] {
		case "core", "base": return "core"
		}
		return raw
	}
	return clean(strings.concatenate({from, "/", raw}))
}

clean :: proc(path: string) -> string {
	out := make([dynamic]string, context.temp_allocator)
	for s in strings.split(path, "/", context.temp_allocator) {
		switch s {
		case "", ".":
		case "..": if len(out) > 0 { pop(&out) }
		case:      append(&out, s)
		}
	}
	return strings.join(out[:], "/")
}

slashed :: proc(s: string) -> string {
	r, _ := strings.replace_all(s, `\`, "/")
	return r
}

// ---- AST helpers ---------------------------------------------------------------------

// A package-level `name :: value` or `name := value`, in any file.
decl :: proc(p: ^Pkg, name: string) -> (^ast.Value_Decl, bool) {
	for _, f in p.ast.files {
		for d in f.decls {
			vd, ok := d.derived_stmt.(^ast.Value_Decl)
			if !ok { continue }
			for n in vd.names {
				if id, is := n.derived_expr.(^ast.Ident); is && id.name == name { return vd, true }
			}
		}
	}
	return nil, false
}

// Whether `name` is declared as a proc.
declares_proc :: proc(p: ^Pkg, name: string) -> bool {
	vd, ok := decl(p, name)
	if !ok || len(vd.values) == 0 { return false }
	_, is := vd.values[0].derived_expr.(^ast.Proc_Lit)
	return is
}

ident :: proc(e: ^ast.Expr) -> string {
	if e == nil { return "" }
	if id, ok := e.derived_expr.(^ast.Ident); ok { return id.name }
	return ""
}

// `pkg.name` → ("pkg", "name").
selector :: proc(e: ^ast.Expr) -> (string, string) {
	if e == nil { return "", "" }
	if s, ok := e.derived_expr.(^ast.Selector_Expr); ok { return ident(s.expr), s.field.name }
	return "", ""
}

// `"text"` or a raw string, unquoted; "" for anything else.
string_lit :: proc(e: ^ast.Expr) -> (string, bool) {
	if e == nil { return "", false }
	b, ok := e.derived_expr.(^ast.Basic_Lit)
	if !ok || b.tok.kind != .String { return "", false }
	return strings.trim(b.tok.text, "\"`"), true
}

// `X[:]` → X.
sliced :: proc(e: ^ast.Expr) -> ^ast.Expr {
	if e == nil { return nil }
	if s, ok := e.derived_expr.(^ast.Slice_Expr); ok { return s.expr }
	return nil
}

comp_lit :: proc(e: ^ast.Expr) -> (^ast.Comp_Lit, bool) {
	if e == nil { return nil, false }
	return e.derived_expr.(^ast.Comp_Lit)
}

// The element type of `[?]T{…}`: "app.Mount".
comp_elem_type :: proc(c: ^ast.Comp_Lit) -> string {
	if c.type == nil { return "" }
	at, ok := c.type.derived_expr.(^ast.Array_Type)
	if !ok { return "" }
	a, b := selector(at.elem)
	return strings.concatenate({a, ".", b}, context.temp_allocator)
}

// The package an alias names in one of p's files: its import's target.
alias_target :: proc(t: ^Tree, p: ^Pkg, alias: string) -> string {
	for imp in p.imports {
		name := imp.alias
		if name == "" {
			if q, ok := t.by_path[imp.target]; ok { name = q.name }
		}
		if name == alias { return imp.target }
	}
	return ""
}
