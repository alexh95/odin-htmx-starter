package lists_models

// ---- lists: the types and the store contract ---------------------------------------------------

import "../../../platform/store"

Error :: store.Error

Item :: struct {
	id:            i64,
	col:           i64,
	text:          string,
	assignee:      u64,
	assignee_name: string,
	pos:           i64,
}

Column :: struct {
	id:     i64,
	name:   string,
	closes: bool, // done means being here
	items:  []Item,
}

Person :: struct {
	id:   u64,
	name: string,
}

List :: struct {
	id:      i64,
	title:   string,
	columns: []Column,
	people:  []Person,
}

Summary :: struct {
	id:          i64,
	title:       string,
	open, total: int,
}

Actor :: struct {
	id:   u64,
	name: string,
}

// A template: its columns, the last of which closes, and the items it starts with.
Template :: struct {
	key, name: string,
	columns:   []string,
	items:     []string,
}

Store_Summaries :: proc(out: ^[dynamic]Summary) -> Error
// Everything on the list. Strings in the temp allocator.
Store_List :: proc(id: i64) -> (List, Error)
// One column as it is now; `list` holds the item, so a stale id reads as gone.
Store_Column :: proc(list, col: i64) -> (Column, Error)
Store_Create :: proc(title: string, t: Template, by: Actor) -> (id: i64, err: Error)

// These run off the loop, each its own transaction, and answer the columns that changed: `to` is 0
// when only one did. .Constraint: past the list's item cap. .Not_Found: not on this list.
Store_Add :: proc(list: i64, text: string, by: Actor) -> (col: i64, err: Error)
// `after`: the item it goes below; 0 the top; -1 the bottom.
Store_Move :: proc(list, item, col, after: i64, by: Actor) -> (from, to: i64, err: Error)
// Between the closing column and the first.
Store_Toggle :: proc(list, item: i64, by: Actor) -> (from, to: i64, err: Error)
Store_Remove :: proc(list, item: i64) -> (col: i64, err: Error)
// Someone who has used Checklists, `by` among them; 0 takes it off whoever had it. `text`: the item's, for
// the notice.
Store_Assign :: proc(list, item: i64, who: u64, by: Actor) -> (col: i64, text: string, err: Error)

Store_Search :: proc(words: []string, limit: int, out: ^[dynamic]store.Search_Hit) -> Error
