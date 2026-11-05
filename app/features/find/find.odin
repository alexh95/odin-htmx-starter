package find

// ---- find: one search over a profile's sources (PLAN §6, D6, D36) -------------------------------
//
// It imports no other feature: the profile's FIND_SOURCES hands it each domain's `search`. What a viewer
// may find is the source's to say, past the row's perm. Hits stay grouped by source, because bm25 means
// nothing across two tables and one source's newest isn't another's best.

import "core:slice"
import "core:strings"

import "../../platform/authz"
import "../../platform/env"
import "../../platform/store"
import m "models"

MAX_QUERY :: 200 // bytes
PER_SOURCE :: 10 // hits

Group :: struct {
	source: ^m.Source,
	hits:   []store.Search_Hit,
}

@(private) sources: []m.Source

init :: proc(table: []m.Source) {
	sources = table
	for s in table {
		if s.engine != table[0].engine { env.problem("find: one list can't mix FTS5 and a contains_ci scan (§11.8)") }
	}
}

// What x-impl says.
engine :: proc() -> string {
	if len(sources) == 0 { return "none" }
	return "fts" if sources[0].engine == .Fts else "scan"
}

// Off the loop. A source that fails is left out rather than failing what the others found, and said.
search :: proc(v: authz.Viewer, q: string, out: ^[dynamic]Group) -> (failed: bool) {
	if strings.trim_space(q) == "" { return false }
	for &s in sources {
		if !authz.can(v, s.perm) { continue }
		hits := make([dynamic]store.Search_Hit, context.temp_allocator)
		if err := s.search(v, q, PER_SOURCE, &hits); err != .None {
			failed = true
			continue
		}
		if len(hits) > 0 { append(out, Group{&s, slice.clone(hits[:], context.temp_allocator)}) }
	}
	return
}
