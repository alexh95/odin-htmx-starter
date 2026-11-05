package lists_store_sqlite

// ---- lists in SQLite -------------------------------------------------------------------------------
//
// A change is a few statements that read as they write, so each runs on the query pool under the writer's
// lock (write_now), and answers which columns changed. Positions keep gaps of 1024 and only this file
// knows: a column runs out of room, it's renumbered, and the caller sees the column as usual.

import "core:fmt"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/lists/models"

IMPL :: "sqlite"
SEARCH_ENGINE :: store.Search_Engine.Fts

MIGRATIONS := [?]store.Migration {
	{1, "0001_lists.sql", #load("migrations/0001_lists.sql", string)},
}

GAP :: 1024
MAX_ITEMS :: 500 // a list's

@(private) SQL_SUMMARIES :: "SELECT l.id, l.title, count(i.id), coalesce(sum(CASE WHEN c.closes = 0 THEN 1 ELSE 0 END), 0) FROM lists l " +
	"LEFT JOIN list_items i ON i.list = l.id LEFT JOIN list_columns c ON c.id = i.col GROUP BY l.id ORDER BY l.id DESC LIMIT 200"
@(private) SQL_LIST :: "SELECT title FROM lists WHERE id = ?"
@(private) SQL_COLUMNS :: "SELECT id, name, closes FROM list_columns WHERE list = ? ORDER BY pos"
@(private) SQL_COLUMN :: "SELECT id, name, closes FROM list_columns WHERE list = ? AND id = ?"
@(private) SQL_ITEMS :: "SELECT i.id, i.col, i.body, i.assignee, i.pos, coalesce(p.name, '') FROM list_items i LEFT JOIN list_people p ON p.who = i.assignee WHERE i.col = ? ORDER BY i.pos, i.id"
@(private) SQL_PEOPLE :: "SELECT who, name FROM list_people ORDER BY name COLLATE NOCASE LIMIT 500"
@(private) SQL_ADD_LIST :: "INSERT INTO lists(title, by_name, at) VALUES(?, ?, ?)"
@(private) SQL_ADD_COLUMN :: "INSERT INTO list_columns(list, name, pos, closes) VALUES(?, ?, ?, ?)"
@(private) SQL_ADD_ITEM :: "INSERT INTO list_items(list, col, body, pos) VALUES(?, ?, ?, ?)"
@(private) SQL_PERSON :: "INSERT INTO list_people(who, name) VALUES(?, ?) ON CONFLICT(who) DO UPDATE SET name = excluded.name"
@(private) SQL_COUNT :: "SELECT count(*) FROM list_items WHERE list = ?"
@(private) SQL_FIRST :: "SELECT id FROM list_columns WHERE list = ? ORDER BY pos LIMIT 1"
@(private) SQL_CLOSING :: "SELECT id FROM list_columns WHERE list = ? AND closes = 1 LIMIT 1"
@(private) SQL_ITEM :: "SELECT col, pos, body FROM list_items WHERE list = ? AND id = ?"
@(private) SQL_IS_COLUMN :: "SELECT 1 FROM list_columns WHERE list = ? AND id = ?"
@(private) SQL_LAST :: "SELECT coalesce(max(pos), 0) FROM list_items WHERE col = ? AND id <> ?"
@(private) SQL_ABOVE :: "SELECT pos FROM list_items WHERE col = ? AND id = ?"
@(private) SQL_BELOW :: "SELECT min(pos) FROM list_items WHERE col = ? AND pos > ? AND id <> ?"
@(private) SQL_PLACE :: "UPDATE list_items SET col = ?, pos = ? WHERE id = ?"
@(private) SQL_RENUMBER :: "UPDATE list_items SET pos = (SELECT r.n * 1024 FROM (SELECT id, row_number() OVER (ORDER BY pos, id) AS n FROM list_items WHERE col = ?1) r WHERE r.id = list_items.id) WHERE col = ?1"
@(private) SQL_REMOVE :: "DELETE FROM list_items WHERE id = ?"
@(private) SQL_ASSIGN :: "UPDATE list_items SET assignee = ? WHERE id = ?"
@(private) SQL_KNOWN :: "SELECT 1 FROM list_people WHERE who = ?"
// By the index's order, newest first, as chat's: it sorts nothing. 57344 and 57345 are escape.MARK_ON and MARK_OFF.
SQL_SEARCH :: "SELECT i.id, l.id, l.title, snippet(lists_fts, 0, char(57344), char(57345), '…', 32) FROM lists_fts f JOIN list_items i ON i.id = f.rowid JOIN lists l ON l.id = i.list " +
	"WHERE lists_fts MATCH ?1 ORDER BY f.rowid DESC LIMIT ?2"

summaries :: proc(out: ^[dynamic]m.Summary) -> (err: m.Error) {
	q := db.read(SQL_SUMMARIES)
	defer db.reset(q)
	for db.next_row(q, &err) {
		total := db.column_int(q, 2)
		append(out, m.Summary{id = db.column_id(q, 0), title = db.clone_col(q, 1), total = total, open = db.column_int(q, 3)})
	}
	return
}

@(private)
items_of :: proc(col: i64) -> (out: []m.Item, err: m.Error) {
	q := db.read(SQL_ITEMS)
	defer db.reset(q)
	db.bind_id(q, 1, col)
	items := make([dynamic]m.Item, context.temp_allocator)
	for db.next_row(q, &err) {
		append(&items, m.Item{
			id = db.column_id(q, 0), col = db.column_id(q, 1), text = db.clone_col(q, 2), assignee = u64(db.column_id(q, 3)),
			pos = db.column_id(q, 4), assignee_name = db.clone_col(q, 5),
		})
	}
	return items[:], err
}

list :: proc(id: i64) -> (l: m.List, err: m.Error) {
	{
		q := db.read(SQL_LIST)
		defer db.reset(q)
		db.bind_id(q, 1, id)
		if !db.next_row(q, &err) { return {}, .Not_Found if err == .None else err }
		l = {id = id, title = db.clone_col(q, 0)}
	}
	columns := make([dynamic]m.Column, context.temp_allocator)
	{
		q := db.read(SQL_COLUMNS)
		defer db.reset(q)
		db.bind_id(q, 1, id)
		for db.next_row(q, &err) {
			append(&columns, m.Column{id = db.column_id(q, 0), name = db.clone_col(q, 1), closes = db.column_int(q, 2) != 0})
		}
		if err != .None { return }
	}
	for &c in columns {
		if c.items, err = items_of(c.id); err != .None { return }
	}
	l.columns = columns[:]
	l.people, err = people_of()
	return
}

@(private)
people_of :: proc() -> (out: []m.Person, err: m.Error) {
	q := db.read(SQL_PEOPLE)
	defer db.reset(q)
	people := make([dynamic]m.Person, context.temp_allocator)
	for db.next_row(q, &err) { append(&people, m.Person{u64(db.column_id(q, 0)), db.clone_col(q, 1)}) }
	return people[:], err
}

column :: proc(list_id, col: i64) -> (c: m.Column, err: m.Error) {
	{
		q := db.read(SQL_COLUMN)
		defer db.reset(q)
		db.bind_id(q, 1, list_id)
		db.bind_id(q, 2, col)
		if !db.next_row(q, &err) { return {}, .Not_Found if err == .None else err }
		c = {id = db.column_id(q, 0), name = db.clone_col(q, 1), closes = db.column_int(q, 2) != 0}
	}
	c.items, err = items_of(col)
	return
}

// What a proc run under write_now reads, which takes no arguments; it runs on the caller's thread.
@(private) @(thread_local) w: struct {
	list, item, col, after: i64,
	title, text:            string,
	by:                     m.Actor,
	who:                    u64,
	template:               m.Template,
	from, to:               i64,
	err:                    m.Error,
}

@(private)
done :: proc(ok: bool) -> m.Error {
	if w.err != .None { return w.err }
	return .None if ok else .Failed
}

// One row's first column, on the writer: this transaction's own view. 0 when there's no row.
@(private)
scalar :: proc(sql: string, a: i64, b: i64 = 0, two := false) -> (v: i64, found: bool) {
	q := db.writer_stmt(sql)
	defer db.reset(q)
	db.bind_id(q, 1, a)
	if two { db.bind_id(q, 2, b) }
	if db.next_row(q, &w.err) { return db.column_id(q, 0), true }
	return 0, false
}

@(private)
exec :: proc(st: db.Stmt) -> bool {
	w.err = db.step_done(st)
	db.reset(st)
	return w.err == .None
}

@(private)
touch :: proc() -> bool {
	st := db.writer_stmt(SQL_PERSON)
	db.bind_id(st, 1, i64(w.by.id))
	db.bind_text(st, 2, w.by.name)
	return exec(st)
}

create :: proc(title: string, t: m.Template, by: m.Actor) -> (id: i64, err: m.Error) {
	w = {title = title, template = t, by = by}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_ADD_LIST)
		db.bind_text(st, 1, w.title)
		db.bind_text(st, 2, w.by.name)
		db.bind_id(st, 3, time.time_to_unix(time.now()))
		if !exec(st) { return false }
		w.list = db.last_insert_id()
		for name, i in w.template.columns {
			c := db.writer_stmt(SQL_ADD_COLUMN)
			db.bind_id(c, 1, w.list)
			db.bind_text(c, 2, name)
			db.bind_int(c, 3, i)
			db.bind_int(c, 4, 1 if i == len(w.template.columns) - 1 else 0)
			if !exec(c) { return false }
			if i == 0 { w.col = db.last_insert_id() }
		}
		for text, i in w.template.items {
			it := db.writer_stmt(SQL_ADD_ITEM)
			db.bind_id(it, 1, w.list)
			db.bind_id(it, 2, w.col)
			db.bind_text(it, 3, text)
			db.bind_id(it, 4, i64(i + 1) * GAP)
			if !exec(it) { return false }
		}
		return touch()
	})
	return w.list, done(ok)
}

add :: proc(list_id: i64, text: string, by: m.Actor) -> (col: i64, err: m.Error) {
	w = {list = list_id, text = text, by = by}
	ok := db.write_now(proc() -> bool {
		n, _ := scalar(SQL_COUNT, w.list)
		if n >= MAX_ITEMS {
			w.err = .Constraint
			return false
		}
		first, found := scalar(SQL_FIRST, w.list)
		if !found {
			w.err = .Not_Found
			return false
		}
		w.from = first
		last, _ := scalar(SQL_LAST, first, 0, true)
		st := db.writer_stmt(SQL_ADD_ITEM)
		db.bind_id(st, 1, w.list)
		db.bind_id(st, 2, first)
		db.bind_text(st, 3, w.text)
		db.bind_id(st, 4, last + GAP)
		return exec(st) && touch()
	})
	return w.from, done(ok)
}

// The item's place in `col`, below `after` (0 the top, -1 the bottom), renumbering when the gap has run out.
@(private)
place :: proc() -> bool {
	prev, next: i64
	for round in 0 ..< 2 {
		prev = 0
		switch {
		case w.after == -1:
			prev, _ = scalar(SQL_LAST, w.col, w.item, true)
		case w.after > 0:
			p, found := scalar(SQL_ABOVE, w.col, w.after, true)
			if found { prev = p } else { prev, _ = scalar(SQL_LAST, w.col, w.item, true) }
		}
		q := db.writer_stmt(SQL_BELOW)
		db.bind_id(q, 1, w.col)
		db.bind_id(q, 2, prev)
		db.bind_id(q, 3, w.item)
		next = 0
		if db.next_row(q, &w.err) { next = db.column_id(q, 0) }
		db.reset(q)
		if next == 0 || next - prev >= 2 || round == 1 { break }
		r := db.writer_stmt(SQL_RENUMBER)
		db.bind_id(r, 1, w.col)
		if !exec(r) { return false }
	}
	st := db.writer_stmt(SQL_PLACE)
	db.bind_id(st, 1, w.col)
	db.bind_id(st, 2, prev + GAP if next == 0 else (prev + next) / 2)
	db.bind_id(st, 3, w.item)
	return exec(st)
}

@(private)
find_item :: proc() -> bool {
	q := db.writer_stmt(SQL_ITEM)
	defer db.reset(q)
	db.bind_id(q, 1, w.list)
	db.bind_id(q, 2, w.item)
	if db.next_row(q, &w.err) {
		w.from = db.column_id(q, 0)
		w.text = db.clone_col(q, 2)
		return true
	}
	if w.err == .None { w.err = .Not_Found }
	return false
}

@(private)
changed :: proc() -> (from, to: i64, err: m.Error) {
	return w.from, w.to if w.to != w.from else 0, .None
}

move :: proc(list_id, item, col, after: i64, by: m.Actor) -> (from, to: i64, err: m.Error) {
	w = {list = list_id, item = item, col = col, after = after, by = by}
	ok := db.write_now(proc() -> bool {
		if !find_item() { return false }
		if _, found := scalar(SQL_IS_COLUMN, w.list, w.col, true); !found {
			if w.err == .None { w.err = .Not_Found }
			return false
		}
		w.to = w.col
		return place() && touch()
	})
	if err = done(ok); err != .None { return 0, 0, err }
	return changed()
}

toggle :: proc(list_id, item: i64, by: m.Actor) -> (from, to: i64, err: m.Error) {
	w = {list = list_id, item = item, by = by, after = -1}
	ok := db.write_now(proc() -> bool {
		if !find_item() { return false }
		closing, _ := scalar(SQL_CLOSING, w.list)
		first, _ := scalar(SQL_FIRST, w.list)
		w.col = first if w.from == closing else closing
		w.to = w.col
		return place() && touch()
	})
	if err = done(ok); err != .None { return 0, 0, err }
	return changed()
}

remove :: proc(list_id, item: i64) -> (col: i64, err: m.Error) {
	w = {list = list_id, item = item}
	ok := db.write_now(proc() -> bool {
		if !find_item() { return false }
		st := db.writer_stmt(SQL_REMOVE)
		db.bind_id(st, 1, w.item)
		return exec(st)
	})
	return w.from, done(ok)
}

assign :: proc(list_id, item: i64, who: u64, by: m.Actor) -> (col: i64, text: string, err: m.Error) {
	w = {list = list_id, item = item, who = who, by = by}
	ok := db.write_now(proc() -> bool {
		if !find_item() { return false }
		if !touch() { return false } // they're someone now, so `who == by` is known too
		if w.who != 0 {
			if _, found := scalar(SQL_KNOWN, i64(w.who)); !found {
				if w.err == .None { w.err = .Not_Found }
				return false
			}
		}
		st := db.writer_stmt(SQL_ASSIGN)
		db.bind_id(st, 1, i64(w.who))
		db.bind_id(st, 2, w.item)
		return exec(st)
	})
	return w.from, w.text, done(ok)
}

search :: proc(words: []string, limit: int, out: ^[dynamic]store.Search_Hit) -> (err: m.Error) {
	if len(words) == 0 { return }
	q := db.read(SQL_SEARCH)
	defer db.reset(q)
	db.bind_text(q, 1, db.fts_query(words))
	db.bind_int(q, 2, limit)
	for db.next_row(q, &err) {
		append(out, store.Search_Hit{
			title = db.clone_col(q, 2), snippet = db.clone_col(q, 3), href = fmt.tprintf("/lists/%d#li-%d", db.column_id(q, 1), db.column_id(q, 0)),
		})
	}
	return
}
