package main

import "core:slice"
import "core:strings"
import "core:testing"

// Run from the repo root (`odin test tools/init`): every committed profile, composed again from
// its own selection, writes every one of its mount, topic, job and nav lines, and the statements
// of main that name its features. A profile edited by hand into a shape the generator can't
// reproduce shows here first.
@(test)
committed_profiles_compose_again :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	load_catalog(".")
	testing.expect(t, len(problems) == 0, strings.join(problems[:], "; "))
	testing.expect(t, len(catalog.profiles) > 0)
	for &p in catalog.profiles {
		// A second host (full's lab host, PLAN §7.3) is written by hand: the generator composes one.
		if p.hosts > 1 { continue }
		s := select("app", p.name, nil, {})
		testing.expectf(t, len(problems) == 0, "%s: %v", p.name, problems[:])
		text := compose(s)
		testing.expectf(t, slice.equal(s.order, p.features[:]), "%s: mounts %v, composed %v", p.name, p.features[:], s.order)
		for set, file in ([][]Line{p.mounts[:], p.topics[:], p.jobs[:], p.nav[:]}) {
			body := text.routes if file < 3 else text.brand
			for l in set {
				testing.expectf(t, strings.contains(body, l.text), "%s: composed without %q", p.name, l.text)
			}
		}
		for st in p.stmts {
			if st.call == "store_sqlite.migrate" { continue }
			testing.expectf(t, strings.contains(text.main, st.text), "%s: main composed without %q", p.name, strings.trim_space(st.text))
		}
		for l in p.find_rows {
			testing.expectf(t, strings.contains(text.main, l.text), "%s: main composed without %q", p.name, l.text)
		}
		for m in p.members { testing.expect(t, m != "") }
		testing.expectf(t, s.members == p.members, "%s: families %v, composed %v", p.name, p.members, s.members)
	}

	// What a selection can't hold is refused with advice, before anything is planned. (One test:
	// the catalog and the problems are the tool's globals.)
	clear(&problems)
	if feature("contacts") != nil {
		_ = select("app", "", {"contacts"}, #partial [Family]string{.Store = "memory"})
		testing.expect(t, slice.contains(problems[:], "contacts has no memory store; use --store sqlite"), strings.join(problems[:], "; "))
		clear(&problems)
	}
	_ = select("app", "", {"no_such_feature"}, {})
	testing.expect(t, len(problems) > 0)
	clear(&problems)
	_ = select("app", "", {"notes"}, #partial [Family]string{.Client = "nope"})
	testing.expect(t, len(problems) > 0)
	clear(&problems)
}
