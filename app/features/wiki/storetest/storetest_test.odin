package wiki_storetest

// ---- the wiki store contract, run against both families (D37) -----------------------------------
//
// What both have: the Manual, its boot replacing what the binary no longer holds, and reads. What
// only SQLite has: saving, and a conflict as an answer.

import "base:runtime"
import "core:strings"
import "core:testing"

import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import mem "../../../stores/memory/wiki"
import sql "../../../stores/sqlite/wiki"

@(private = "file")
Family :: struct {
	name: string,
	page: m.Store_Page,
	list: m.Store_List,
	seed: m.Store_Seed_Manual,
	search: m.Store_Search,
}

@(private = "file")
doc :: proc(slug, title: string) -> m.Page {
	return {slug = slug, title = title, manual = true, md = "# text", html = "<h1>text</h1>", plain = "text"}
}

@(private = "file")
conforms :: proc(t: ^testing.T, f: Family) {
	testing.expect_value(t, f.seed({doc("b", "Bravo"), doc("a", "Alpha")}), m.Error.None)
	p, err := f.page("a")
	testing.expectf(t, err == .None && p.title == "Alpha" && p.manual && p.html == "<h1>text</h1>" && p.visibility == .Public, "%s: %v %v", f.name, p, err)
	_, err = f.page("nothing")
	testing.expect_value(t, err, m.Error.Not_Found)
	all := make([dynamic]m.Page, context.temp_allocator)
	testing.expect_value(t, f.list(false, &all), m.Error.None)
	testing.expectf(t, len(all) == 2 && all[0].title == "Alpha", "%s: title order: %v", f.name, all[:])
	testing.expectf(t, all[0].html == "", "%s: a listing holds no bodies", f.name)

	hits := make([dynamic]store.Search_Hit, context.temp_allocator)
	words := []string{"bravo"}
	testing.expect_value(t, f.search(words, false, 5, &hits), m.Error.None)
	testing.expectf(t, len(hits) == 1 && hits[0].href == "/wiki/b" && hits[0].title == "Bravo", "%s: by its title: %v", f.name, hits[:])
}

@(private = "file")
writing :: proc(t: ^testing.T) {
	testing.expect_value(t, sql.seed_manual({doc("a", "Alpha"), doc("gone", "Gone")}), m.Error.None)
	testing.expect_value(t, sql.seed_manual({doc("a", "Alpha 2")}), m.Error.None)
	p, err := sql.page("a")
	testing.expectf(t, err == .None && p.title == "Alpha 2", "a new binary's doc: %v %v", p, err)
	_, err = sql.page("gone")
	testing.expect_value(t, err, m.Error.Not_Found)

	input := m.Save{slug = "mine", title = "Mine", md = "one", html = "<p>one</p>", plain = "one", visibility = .Members, by = "ann"}
	saved, conflict, serr := sql.save(input)
	testing.expectf(t, serr == .None && !conflict && saved.rev == 1 && saved.by == "ann" && saved.visibility == .Members, "%v %v %v", saved, conflict, serr)
	_, _, serr = sql.save(input)
	testing.expect_value(t, serr, m.Error.Constraint) // the slug's taken

	over := input
	over.md, over.base_rev, over.by = "two", 1, "bob"
	saved, conflict, serr = sql.save(over)
	testing.expectf(t, serr == .None && !conflict && saved.rev == 2 && saved.md == "two", "%v %v %v", saved, conflict, serr)

	stale := over
	stale.md = "three"
	saved, conflict, serr = sql.save(stale) // rev 1 again
	testing.expectf(t, serr == .None && conflict && saved.rev == 2 && saved.md == "two", "a conflict answers with the newer page: %v %v %v", saved, conflict, serr)
	p, _ = sql.page("mine")
	testing.expect_value(t, p.md, "two")

	revisions := make([dynamic]m.Revision, context.temp_allocator)
	testing.expect_value(t, sql.history("mine", &revisions), m.Error.None)
	testing.expectf(t, len(revisions) == 1 && revisions[0].rev == 1 && revisions[0].by == "ann", "%v", revisions[:])
	r, rerr := sql.revision("mine", 1)
	testing.expectf(t, rerr == .None && r.md == "one", "%v %v", r, rerr)

	for i in 0 ..< sql.KEEP_REVISIONS + 5 {
		over.base_rev, over.md = i64(i + 2), "more"
		_, conflict, serr = sql.save(over)
		testing.expectf(t, serr == .None && !conflict, "%d: %v %v", i, conflict, serr)
	}
	clear(&revisions)
	_ = sql.history("mine", &revisions)
	testing.expectf(t, len(revisions) == sql.KEEP_REVISIONS, "a history is capped: %d", len(revisions))

	found := make([dynamic]store.Search_Hit, context.temp_allocator)
	marked := []string{"more"}
	_ = sql.search(marked, false, 5, &found)
	testing.expectf(t, len(found) == 0, "a guest finds no members' page: %v", found[:])
	_ = sql.search(marked, true, 5, &found)
	testing.expectf(t, len(found) == 1 && strings.contains(found[0].snippet, "more"), "a member does, marked: %v", found[:])

	all := make([dynamic]m.Page, context.temp_allocator)
	_ = sql.list(false, &all)
	testing.expectf(t, len(all) == 1 && all[0].slug == "a", "a guest's list: %v", all[:])
	clear(&all)
	_ = sql.list(true, &all)
	testing.expectf(t, len(all) == 2, "a member's: %v", all[:])

	manual := m.Save{slug = "a", title = "x", md = "x", html = "x", plain = "x", base_rev = 1}
	_, _, serr = sql.save(manual)
	testing.expect_value(t, serr, m.Error.Constraint)

	// A page already holding a slug the Manual comes to want keeps it.
	testing.expect_value(t, sql.seed_manual({doc("a", "Alpha 2"), doc("mine", "Theirs")}), m.Error.None)
	p, _ = sql.page("mine")
	testing.expectf(t, !p.manual && p.md == "more", "%v", p)
}

@(test)
both_families :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	conforms(t, {"memory", mem.page, mem.list, mem.seed_manual, mem.search})
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("wiki", sql.MIGRATIONS[:])
	conforms(t, {"sqlite", sql.page, sql.list, sql.seed_manual, sql.search})
	writing(t)
	free_all(context.temp_allocator)
}
