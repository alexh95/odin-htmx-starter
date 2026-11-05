package main

// ---- the committed profiles, read as donors ------------------------------------------------
//
// Each profile's four files, parsed, with every line a feature owns kept as written: its
// mount lines, its TOPICS and JOBS lines, its nav entries, the copy its init takes, and the
// statements of `main` that name it, each with its phase (§7.2: init before app.check, the
// store's work between check and serve, start after serve, drain after wait). The platform's
// own lines (app.boot … app.exit, the store's open and close, hub.init) are not taken: the
// generator writes them for the selection's families.

import "core:fmt"
import "core:odin/ast"
import "core:os"
import "core:slice"
import "core:strings"

Profile :: struct {
	name:          string,
	members:       [Family]string, // member names
	pkg:           ^Pkg,
	features:      [dynamic]string, // mounted on the main host, in mount order; the platform's not
	root:          string,          // the feature whose own row serves "/"
	files:         map[string]Src,  // "main", "routes", "brand", "routes_test"
	imports:       map[string]string, // an alias (or package name) → its import line, over the files
	mounts:        [dynamic]Line,
	topics:        [dynamic]Line,
	jobs:          [dynamic]Line,
	nav:           [dynamic]Line,   // key: the href
	copies:        [dynamic]Line,   // brand.odin's other decls (ABOUT, HOME); key: the name
	brand_fields:  [dynamic]Line,   // BRAND's fields; key: the field
	stmts:         [dynamic]Stmt,
	find_rows:     [dynamic]Line,   // FIND_SOURCES' rows, each its feature's
	serve_extra:   string,          // what app.serve takes after &BRAND, as written ("" for none)
	host_identity: string,          // HOSTS' third field, as written
	hosts:         int,             // HOSTS' rows: tools/init writes and edits one-host profiles only
}

Src :: struct {
	path:  string,
	file:  ^ast.File,
	lines: []string,
}

Line :: struct {
	features: []string, // the features its package aliases name; none for the platform's
	key:      string,
	text:     string,
	root:     bool,
}

Phase :: enum {
	Init,  // before app.check
	Store, // between app.check and app.serve, after the store's open and migrations
	Start, // after app.serve
	Drain, // after app.wait
}

Stmt :: struct {
	using line: Line,
	phase:      Phase,
	call:       string, // the statement's call, "store_sqlite.migrate"; "" for none
}

PROFILE_FILES := [?]string{"main", "routes", "brand", "routes_test"}

read_profiles :: proc(root: string) {
	data, err := os.read_entire_file(join(root, "build.sh"), context.allocator)
	if err != nil {
		problem("build.sh: not found (the profiles' families live there)")
		return
	}
	// `  skeleton) store=sqlite id=platform/authz/anonymous client=vanilla theme=full ;;`
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		l := strings.trim_space(line)
		paren := strings.index_byte(l, ')')
		if paren <= 0 || !strings.contains(l, "store=") { continue }
		// A build of another profile's files (full-vanilla) composes nothing of its own.
		if strings.contains(l, " src=") { continue }
		p := Profile{name = l[:paren]}
		for kv in strings.fields(l[paren + 1:]) {
			k, _, v := strings.partition(kv, "=")
			switch k {
			case "store":  p.members[.Store] = v
			case "id":     p.members[.Identity] = member_by_dir(.Identity, v).name
			case "client": p.members[.Client] = v
			case "theme":  p.members[.Theme] = v
			}
		}
		p.pkg = catalog.tree.by_path[join("cmd", p.name)]
		if p.pkg == nil {
			problem("build.sh names %s, but there's no app/cmd/%s", p.name, p.name)
			continue
		}
		read_profile(&p)
		append(&catalog.profiles, p)
	}
}

profile :: proc(name: string) -> ^Profile {
	for &p in catalog.profiles {
		if p.name == name { return &p }
	}
	return nil
}

@(private = "file")
read_profile :: proc(p: ^Profile) {
	for _, f in p.pkg.ast.files {
		base := strings.trim_suffix(slashed_base(f.fullpath), ".odin")
		lines := strings.split_lines(f.src)
		p.files[base] = Src{fmt.aprintf("app/cmd/%s/%s.odin", p.name, base), f, lines}
		for imp in f.imports {
			alias := imp.name.text
			if alias == "" {
				if q, ok := catalog.tree.by_path[resolve(join("cmd", p.name), strings.trim(imp.relpath.text, "\"`"))]; ok { alias = q.name }
			}
			p.imports[alias] = lines[imp.pos.line - 1]
		}
	}
	routes, has_routes := p.files["routes"]
	if has_routes { read_routes(p, routes) }
	if brand, ok := p.files["brand"]; ok { read_brand(p, brand) }
	if main, ok := p.files["main"]; ok { read_main(p, main) }
}

// The features a node's package aliases name, through the profile's imports.
features_of :: proc(p: ^Profile, n: ^ast.Node) -> []string {
	out := make([dynamic]string)
	for a in aliases_in(n) {
		g := feature_of_target(alias_target(&catalog.tree, p.pkg, a))
		if g != "" && !slice.contains(out[:], g) { append(&out, g) }
	}
	return out[:]
}

text_of :: proc(src: Src, n: ^ast.Node) -> string {
	return strings.join(src.lines[n.pos.line - 1:n.end.line], "\n")
}

@(private = "file")
read_routes :: proc(p: ^Profile, src: Src) {
	host_table := ""
	for d in src.file.decls {
		vd, ok := d.derived_stmt.(^ast.Value_Decl)
		if !ok || len(vd.values) != 1 { continue }
		cl, is := comp_lit(vd.values[0])
		if !is || comp_elem_type(cl) != "app.Host" { continue }
		p.hosts = len(cl.elems)
		for e in cl.elems {
			h, hc := comp_lit(e)
			if !hc || len(h.elems) < 4 { continue }
			if name, _ := string_lit(h.elems[0]); name == "main" {
				host_table = ident(sliced(h.elems[3]))
				p.host_identity = src.file.src[h.elems[2].pos.offset:h.elems[2].end.offset]
			}
		}
	}
	for d in src.file.decls {
		vd, ok := d.derived_stmt.(^ast.Value_Decl)
		if !ok || len(vd.values) != 1 || len(vd.names) != 1 { continue }
		cl, is := comp_lit(vd.values[0])
		if !is { continue }
		switch comp_elem_type(cl) {
		case "app.Mount":
			if ident(vd.names[0]) != host_table { continue }
			for e in cl.elems {
				m, mc := comp_lit(e)
				if !mc || len(m.elems) != 2 { continue }
				name, _ := string_lit(m.elems[0])
				line := Line{key = name, text = text_of(src, e)}
				if name != "platform" {
					line.features = slice.clone([]string{name})
					if !slice.contains(p.features[:], name) { append(&p.features, name) }
				}
				if rows, inline := comp_lit(m.elems[1]); inline {
					for r in rows.elems {
						rc, rok := comp_lit(r)
						if !rok || len(rc.elems) < 2 { continue }
						if pat, _ := string_lit(rc.elems[1]); pat == "/" {
							line.root = true
							p.root = name
						}
					}
				}
				append(&p.mounts, line)
			}
		case "[]hub.Topic", "[]workers.Job":
			for e in cl.elems {
				line := Line{features = features_of(p, e), text = text_of(src, e)}
				append(&p.topics if comp_elem_type(cl) == "[]hub.Topic" else &p.jobs, line)
			}
		}
	}
}

@(private = "file")
read_brand :: proc(p: ^Profile, src: Src) {
	for d in src.file.decls {
		vd, ok := d.derived_stmt.(^ast.Value_Decl)
		if !ok || len(vd.values) != 1 || len(vd.names) != 1 { continue }
		name := ident(vd.names[0])
		cl, is := comp_lit(vd.values[0])
		switch {
		case name == "BRAND" && is:
			for e in cl.elems {
				fv, fok := e.derived_expr.(^ast.Field_Value)
				if !fok { continue }
				line := Line{key = ident(fv.field), text = text_of(src, e)}
				// A field that links a page (search = {href = "/search", …}) is that page's feature's.
				if inner, ic := comp_lit(fv.value); ic {
					for ie in inner.elems {
						ifv, ifok := ie.derived_expr.(^ast.Field_Value)
						if !ifok || ident(ifv.field) != "href" { continue }
						if href, _ := string_lit(ifv.value); href != "" {
							if owner := route_owner(href); owner != "" { line.features = slice.clone([]string{owner}) }
						}
					}
				}
				append(&p.brand_fields, line)
			}
		case name == "NAV" && is:
			for e in cl.elems {
				item, iok := comp_lit(e)
				if !iok || len(item.elems) == 0 { continue }
				href, _ := string_lit(item.elems[0])
				append(&p.nav, Line{key = href, text = text_of(src, e)})
			}
		case:
			append(&p.copies, Line{features = features_of(p, vd), key = name, text = text_of(src, vd)})
		}
	}
	// A nav entry is the feature's whose GET row serves its href (the root's is "/").
	for &n in p.nav {
		if n.key == "/" {
			n.root = true
			if p.root != "" { n.features = slice.clone([]string{p.root}) }
			continue
		}
		if owner := route_owner(n.key); owner != "" { n.features = slice.clone([]string{owner}) }
	}
}

// The feature whose web package's ROUTES has a row of this method with exactly this pattern;
// an identity member's ROUTES are its feature's (/login is accounts').
route_owner :: proc(path: string, want := "Get") -> string {
	for f in catalog.features {
		if has_row(f.web, path, want) { return f.name }
	}
	for mb in catalog.members[.Identity] {
		if has_row(catalog.tree.by_path[mb.dir], path, want) { return identity_feature(mb.name) }
	}
	return ""
}

@(private = "file")
has_row :: proc(p: ^Pkg, path, want: string) -> bool {
	vd, ok := decl(p, "ROUTES")
	if !ok || len(vd.values) != 1 { return false }
	rows, is := comp_lit(vd.values[0])
	if !is { return false }
	for r in rows.elems {
		rc, rok := comp_lit(r)
		if !rok || len(rc.elems) < 2 { continue }
		method, iok := rc.elems[0].derived_expr.(^ast.Implicit_Selector_Expr)
		pat, _ := string_lit(rc.elems[1])
		if iok && method.field.name == want && pat == path { return true }
	}
	return false
}

// A row of main's FIND_SOURCES, as written. Its feature is the domain its `search` names.
@(private = "file")
read_find_sources :: proc(p: ^Profile, src: Src) {
	for d in src.file.decls {
		vd, ok := d.derived_stmt.(^ast.Value_Decl)
		if !ok || len(vd.values) != 1 || ident(vd.names[0]) != "FIND_SOURCES" { continue }
		lit, is := vd.values[0].derived_expr.(^ast.Comp_Lit)
		if !is { continue }
		for e in lit.elems {
			text := src.file.src[e.pos.offset:e.end.offset]
			for f in p.features {
				if strings.contains(text, strings.concatenate({f, ".find,"})) {
					owners := make([dynamic]string)
					append(&owners, f)
					append(&p.find_rows, Line{features = owners[:], text = text})
				}
			}
		}
	}
}

@(private = "file")
read_main :: proc(p: ^Profile, src: Src) {
	read_find_sources(p, src)
	for d in src.file.decls {
		vd, ok := d.derived_stmt.(^ast.Value_Decl)
		if !ok || len(vd.values) != 1 || ident(vd.names[0]) != "main" { continue }
		pl, is := vd.values[0].derived_expr.(^ast.Proc_Lit)
		if !is { continue }
		body, bok := pl.body.derived_stmt.(^ast.Block_Stmt)
		if !bok { continue }
		phase := Phase.Init
		for s in body.stmts {
			call := ""
			if es, eok := s.derived_stmt.(^ast.Expr_Stmt); eok {
				if c, cok := es.expr.derived_expr.(^ast.Call_Expr); cok {
					a, n := selector(c.expr)
					call = strings.concatenate({a, ".", n})
					if call == "app.serve" && len(c.args) > 3 {
						p.serve_extra = src.file.src[c.args[3].pos.offset:c.args[len(c.args) - 1].end.offset]
					}
				}
			}
			switch call {
			case "app.check":    phase = .Store
			case "app.serve":    phase = .Start
			case "app.wait":     phase = .Drain
			}
			owners := features_of(p, s)
			if len(owners) == 0 { continue }
			append(&p.stmts, Stmt{line = {features = owners, text = text_of(src, s)}, phase = phase, call = call})
		}
	}
}

@(private = "file")
slashed_base :: proc(path: string) -> string {
	s, _ := strings.replace_all(path, `\`, "/")
	if i := strings.last_index_byte(s, '/'); i >= 0 { return s[i + 1:] }
	return s
}
