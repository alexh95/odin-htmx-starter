package lists_storetest

// ---- the lists store: positions, the closing column, the cap, the index ---------------------------------

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:testing"

import "../../../platform/guard"
import "../../../platform/obs"
import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../models"
import sql "../../../stores/sqlite/lists"

@(private = "file")
ANN :: m.Actor{1, "ann"}
@(private = "file")
BOB :: m.Actor{2, "bob"}
@(private = "file")
PLAIN :: m.Template{"plain", "Plain", {"To do", "Doing", "Done"}, nil}

@(private = "file")
texts :: proc(c: m.Column) -> string {
	b := strings.builder_make(context.temp_allocator)
	for it, i in c.items {
		if i > 0 { strings.write_byte(&b, ',') }
		strings.write_string(&b, it.text)
	}
	return strings.to_string(b)
}

@(private = "file")
item_id :: proc(c: m.Column, text: string) -> i64 {
	for it in c.items {
		if it.text == text { return it.id }
	}
	return 0
}

@(test)
lists_keep_their_order :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("lists", sql.MIGRATIONS[:])
	context.allocator = context.temp_allocator

	id, err := sql.create("Trip", PLAIN, ANN)
	testing.expect_value(t, err, m.Error.None)
	for text in ([]string{"a", "b", "c"}) {
		_, err = sql.add(id, text, ANN)
		testing.expect_value(t, err, m.Error.None)
	}
	l, _ := sql.list(id)
	testing.expect_value(t, len(l.columns), 3)
	first, doing, done := l.columns[0], l.columns[1], l.columns[2]
	testing.expect(t, !first.closes && done.closes)
	testing.expect_value(t, texts(first), "a,b,c")

	a, b, c := item_id(first, "a"), item_id(first, "b"), item_id(first, "c")
	from, to, merr := sql.move(id, c, first.id, 0, BOB)
	testing.expectf(t, merr == .None && from == first.id && to == 0, "within a column, one changed: %v %v %v", from, to, merr)
	col, _ := sql.column(id, first.id)
	testing.expect_value(t, texts(col), "c,a,b")
	_, _, _ = sql.move(id, c, first.id, a, BOB)
	col, _ = sql.column(id, first.id)
	testing.expect_value(t, texts(col), "a,c,b")

	from, to, merr = sql.move(id, b, doing.id, -1, BOB)
	testing.expectf(t, merr == .None && from == first.id && to == doing.id, "across, both: %v %v %v", from, to, merr)
	l, _ = sql.list(id)
	testing.expect_value(t, len(l.people), 2)

	// Ticking is the closing column, and unticking the first.
	from, to, merr = sql.toggle(id, a, ANN)
	testing.expectf(t, merr == .None && from == first.id && to == done.id, "%v %v %v", from, to, merr)
	from, to, merr = sql.toggle(id, a, ANN)
	testing.expectf(t, merr == .None && from == done.id && to == first.id, "%v %v %v", from, to, merr)

	// A gap runs out, and the column renumbers: always just below the same item, the order stays right.

	for i in 0 ..< 14 {
		text := fmt.tprintf("n%d", i)
		cl, _ := sql.add(id, text, ANN)
		cur, _ := sql.column(id, cl)
		from, to, merr = sql.move(id, item_id(cur, text), cl, 0, ANN)
		testing.expect_value(t, merr, m.Error.None)
		other, _ := sql.column(id, cl)
		_, _, merr = sql.move(id, other.items[1].id, cl, other.items[0].id, ANN)
		testing.expect_value(t, merr, m.Error.None)
		settled, _ := sql.column(id, cl)
		for k in 1 ..< len(settled.items) {
			testing.expectf(t, settled.items[k - 1].pos < settled.items[k].pos, "positions are strict: %v", settled.items)
		}
	}

	// Another list's item and column are "not found".
	other, _ := sql.create("Other", PLAIN, ANN)
	_, _, merr = sql.move(other, a, first.id, 0, ANN)
	testing.expect_value(t, merr, m.Error.Not_Found)
	_, _, merr = sql.move(id, a, doing.id + 100, 0, ANN)
	testing.expect_value(t, merr, m.Error.Not_Found)
	_, _, merr = sql.toggle(other, a, ANN)
	testing.expect_value(t, merr, m.Error.Not_Found)

	// Only someone who worked on it can be given an item.
	_, _, aerr := sql.assign(id, a, 99)
	testing.expect_value(t, aerr, m.Error.Not_Found)
	_, text, aerr2 := sql.assign(id, a, 2)
	testing.expectf(t, aerr2 == .None && text == "a", "%v %v", text, aerr2)
	cur, _ := sql.column(id, first.id)
	for it in cur.items {
		if it.id == a { testing.expect_value(t, it.assignee_name, "bob") }
	}

	// The index follows, and a removed item leaves it.
	hits := make([dynamic]store.Search_Hit, context.temp_allocator)
	words := []string{"n13"}
	testing.expect_value(t, sql.search(words, 5, &hits), m.Error.None)
	testing.expectf(t, len(hits) == 1 && hits[0].title == "Trip" && strings.contains(hits[0].href, "#li-") && strings.contains(hits[0].snippet, "n13"), "%v", hits[:])
	cur, _ = sql.column(id, first.id)
	_, rerr := sql.remove(id, item_id(cur, "n13"))
	testing.expect_value(t, rerr, m.Error.None)
	clear(&hits)
	_ = sql.search(words, 5, &hits)
	testing.expectf(t, len(hits) == 0, "%v", hits[:])

	// The cap.
	full, _ := sql.create("Full", PLAIN, ANN)
	for _ in 0 ..< sql.MAX_ITEMS { _, _ = sql.add(full, "x", ANN) }
	_, err = sql.add(full, "one more", ANN)
	testing.expect_value(t, err, m.Error.Constraint)

	all := make([dynamic]m.Summary, context.temp_allocator)
	testing.expect_value(t, sql.summaries(&all), m.Error.None)
	testing.expectf(t, len(all) == 3 && all[0].title == "Full" && all[0].total == sql.MAX_ITEMS, "%v", all[:])

	plan := db.read("EXPLAIN QUERY PLAN " + sql.SQL_SEARCH)
	defer db.reset(plan)
	perr: store.Error
	for db.next_row(plan, &perr) {
		testing.expectf(t, !strings.contains(db.clone_col(plan, 3), "TEMP B-TREE"), "a search sorts: %s", db.clone_col(plan, 3))
	}
	free_all(context.temp_allocator)
}
