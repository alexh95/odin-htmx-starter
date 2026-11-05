package lists

// ---- lists: shared checklists, and a board of the same items (PLAN §6, D36) ------------------------
//
// An item has a column, and one column of a list closes: done means being in it, so a ticked card can't sit
// in the wrong place. Ticking moves it there, unticking to the first column. Columns come from the template
// and don't change after. Every member reads and edits every list.

import "core:strings"

import "../../platform/authz"
import "../../platform/store"
import m "models"
import lists_store "store:lists"

MAX_TEXT :: 200 // runes
MAX_TITLE :: 80 // runes
SEARCH_ENGINE :: lists_store.SEARCH_ENGINE

TEMPLATES := [?]m.Template {
	{"plain", "Plain", {"To do", "Doing", "Done"}, nil},
	{"groceries", "Groceries", {"To buy", "Bought"}, {"Milk", "Eggs", "Bread"}},
	{"packing", "Packing", {"To pack", "Packed"}, {"Clothes", "Chargers", "Documents"}},
}

template :: proc(key: string) -> m.Template {
	for t in TEMPLATES {
		if t.key == key { return t }
	}
	return TEMPLATES[0]
}

check_text :: proc(text: string) -> string {
	if strings.trim_space(text) == "" { return "An item needs some text." }
	if strings.rune_count(text) > MAX_TEXT { return "An item is at most 200 characters." }
	return ""
}

check_title :: proc(title: string) -> string {
	if strings.trim_space(title) == "" { return "A list needs a title." }
	if strings.rune_count(title) > MAX_TITLE { return "A title is at most 80 characters." }
	return ""
}

actor :: proc(v: authz.Viewer) -> m.Actor { return {v.id, v.name} }

summaries :: proc(out: ^[dynamic]m.Summary) -> m.Error { return lists_store.summaries(out) }
list :: proc(id: i64) -> (m.List, m.Error) { return lists_store.list(id) }
column :: proc(list_id, col: i64) -> (m.Column, m.Error) { return lists_store.column(list_id, col) }

create :: proc(title, key: string, v: authz.Viewer) -> (i64, m.Error) {
	return lists_store.create(strings.trim_space(title), template(key), actor(v))
}

add :: proc(list_id: i64, text: string, v: authz.Viewer) -> (i64, m.Error) {
	return lists_store.add(list_id, strings.trim_space(text), actor(v))
}

move :: proc(list_id, item, col, after: i64, v: authz.Viewer) -> (from, to: i64, err: m.Error) {
	return lists_store.move(list_id, item, col, after, actor(v))
}

toggle :: proc(list_id, item: i64, v: authz.Viewer) -> (from, to: i64, err: m.Error) {
	return lists_store.toggle(list_id, item, actor(v))
}

remove :: proc(list_id, item: i64) -> (i64, m.Error) { return lists_store.remove(list_id, item) }
assign :: proc(list_id, item: i64, who: u64, v: authz.Viewer) -> (col: i64, text: string, err: m.Error) {
	return lists_store.assign(list_id, item, who, actor(v))
}

// A row of find's table. Lists are every member's, so its perm is the whole rule.
find :: proc(_: authz.Viewer, q: string, limit: int, out: ^[dynamic]store.Search_Hit) -> m.Error {
	return lists_store.search(store.search_words(q), limit, out)
}
