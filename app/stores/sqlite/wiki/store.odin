package wiki_store_sqlite

// ---- the wiki in SQLite -------------------------------------------------------------------------
//
// Editable pages with their revisions, and the Manual, which boot replaces with the binary's. A save
// runs on the query pool, which already renders it, so it takes the writer's lock itself (write_now)
// and answers in line; a conflict is an answer, not an error.

import "core:strings"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/wiki/models"

IMPL :: "sqlite"
SEARCH_ENGINE :: store.Search_Engine.Fts

MIGRATIONS := [?]store.Migration {
	{1, "0001_wiki.sql", #load("migrations/0001_wiki.sql", string)},
}

// A page's history keeps this many.
KEEP_REVISIONS :: 50
MAX_PAGES :: 5000 // the rate limit alone would let one member fill the disk

@(private) COLS :: "slug, title, visibility, manual, md, html, plain, rev, at, by_name"
@(private) SQL_PAGE :: "SELECT " + COLS + " FROM wiki_pages WHERE slug = ?"
@(private) SQL_LIST :: "SELECT slug, title, visibility, manual FROM wiki_pages WHERE visibility = 0 OR ?1 ORDER BY manual, title COLLATE NOCASE LIMIT ?2"
@(private) SQL_ADD :: "INSERT INTO wiki_pages(slug, title, visibility, md, html, plain, at, by_name) VALUES(?, ?, ?, ?, ?, ?, ?, ?)"
@(private) SQL_KEEP :: "INSERT INTO wiki_revisions(page, rev, title, md, at, by_name) SELECT id, rev, title, md, at, by_name FROM wiki_pages WHERE slug = ?"
@(private) SQL_SET :: "UPDATE wiki_pages SET title = ?, visibility = ?, md = ?, html = ?, plain = ?, rev = rev + 1, at = ?, by_name = ? WHERE slug = ? AND manual = 0"
@(private) SQL_TRIM :: "DELETE FROM wiki_revisions WHERE page = (SELECT id FROM wiki_pages WHERE slug = ?1) AND rev <= (SELECT rev FROM wiki_pages WHERE slug = ?1) - ?2"
@(private) SQL_HISTORY :: "SELECT r.rev, r.title, r.at, r.by_name FROM wiki_revisions r JOIN wiki_pages p ON p.id = r.page WHERE p.slug = ? ORDER BY r.rev DESC"
@(private) SQL_REVISION :: "SELECT r.rev, r.title, r.at, r.by_name, r.md FROM wiki_revisions r JOIN wiki_pages p ON p.id = r.page WHERE p.slug = ? AND r.rev = ?"
@(private) SQL_MANUAL_SET :: "INSERT INTO wiki_pages(slug, title, visibility, manual, md, html, plain, at, by_name) VALUES(?1, ?2, 0, 1, ?3, ?4, ?5, ?6, '') " +
	"ON CONFLICT(slug) DO UPDATE SET title = ?2, md = ?3, html = ?4, plain = ?5, at = ?6 WHERE manual = 1 AND (title <> ?2 OR md <> ?3 OR html <> ?4)"
// bm25 reads every match, on the query pool; the visibility is the query's own, so a guest's snippet can't
// come from a members' page. 57344 and 57345 are escape.MARK_ON and MARK_OFF.
SQL_SEARCH :: "SELECT p.slug, p.title, snippet(wiki_fts, -1, char(57344), char(57345), '…', 32) FROM wiki_fts f JOIN wiki_pages p ON p.id = f.rowid " +
	"WHERE wiki_fts MATCH ?1 AND (p.visibility = 0 OR ?2) ORDER BY bm25(wiki_fts, 8.0, 1.0) LIMIT ?3"
@(private) SQL_COUNT :: "SELECT count(*) FROM wiki_pages"
@(private) SQL_MANUAL_ALL :: "SELECT slug FROM wiki_pages WHERE manual = 1"
@(private) SQL_DROP :: "DELETE FROM wiki_pages WHERE slug = ? AND manual = 1"

page :: proc(slug: string) -> (p: m.Page, err: m.Error) {
	q := db.read(SQL_PAGE)
	defer db.reset(q)
	db.bind_text(q, 1, slug)
	if !db.next_row(q, &err) { return {}, .Not_Found if err == .None else err }
	return one(q), .None
}

@(private)
one :: proc(q: db.Stmt, a := context.temp_allocator) -> m.Page {
	vis, _ := store.enum_from_int(m.Visibility, db.column_int(q, 2))
	return {
		slug = db.clone_col(q, 0, a), title = db.clone_col(q, 1, a), visibility = vis, manual = db.column_int(q, 3) != 0,
		md = db.clone_col(q, 4, a), html = db.clone_col(q, 5, a), plain = db.clone_col(q, 6, a),
		rev = db.column_id(q, 7), at = db.column_id(q, 8), by = db.clone_col(q, 9, a),
	}
}

list :: proc(members: bool, out: ^[dynamic]m.Page) -> (err: m.Error) {
	q := db.read(SQL_LIST)
	defer db.reset(q)
	db.bind_int(q, 1, 1 if members else 0)
	db.bind_int(q, 2, m.INDEX_LIMIT)
	for db.next_row(q, &err) {
		vis, _ := store.enum_from_int(m.Visibility, db.column_int(q, 2))
		append(out, m.Page{slug = db.clone_col(q, 0), title = db.clone_col(q, 1), visibility = vis, manual = db.column_int(q, 3) != 0})
	}
	return
}

search :: proc(words: []string, members: bool, limit: int, out: ^[dynamic]store.Search_Hit) -> (err: m.Error) {
	if len(words) == 0 { return }
	q := db.read(SQL_SEARCH)
	defer db.reset(q)
	db.bind_text(q, 1, db.fts_query(words))
	db.bind_int(q, 2, 1 if members else 0)
	db.bind_int(q, 3, limit)
	for db.next_row(q, &err) {
		append(out, store.Search_Hit{title = db.clone_col(q, 1), snippet = db.clone_col(q, 2), href = strings.concatenate({"/wiki/", db.clone_col(q, 0)}, context.temp_allocator)})
	}
	return
}

// What a proc run under write_now reads, which takes no arguments; it runs on the caller's thread.
@(private) @(thread_local) saving: struct {
	input:    m.Save,
	current:  m.Page,
	conflict: bool,
	full:     bool,
	err:      m.Error,
	manual:   []m.Page,
}

// A page with no base_rev is new, and .Constraint means its slug is taken. `current` is the page as
// it is now: the saved one, or on a conflict the one that's newer.
save :: proc(input: m.Save) -> (current: m.Page, conflict, full: bool, err: m.Error) {
	saving = {input = input}
	ok := db.write_now(proc() -> bool {
		if saving.input.base_rev == 0 { save_new() } else { save_over() }
		return saving.err == .None
	})
	if !ok && saving.err == .None { return {}, false, false, .Failed }
	return saving.current, saving.conflict, saving.full, saving.err
}

@(private)
save_new :: proc() {
	in_ := saving.input
	{
		q := db.writer_stmt(SQL_COUNT)
		defer db.reset(q)
		if db.next_row(q, &saving.err) && db.column_int(q, 0) >= MAX_PAGES {
			saving.full = true
			saving.err = .Constraint
		}
		if saving.err != .None { return }
	}
	st := db.writer_stmt(SQL_ADD)
	defer db.reset(st)
	db.bind_text(st, 1, in_.slug)
	db.bind_text(st, 2, in_.title)
	db.bind_int(st, 3, int(in_.visibility))
	db.bind_text(st, 4, in_.md)
	db.bind_text(st, 5, in_.html)
	db.bind_text(st, 6, in_.plain)
	db.bind_id(st, 7, time.time_to_unix(time.now()))
	db.bind_text(st, 8, in_.by)
	if saving.err = db.step_done(st); saving.err == .None { saving.current = current_page(in_.slug) }
}

@(private)
save_over :: proc() {
	in_ := saving.input
	now := current_page(in_.slug)
	switch {
	case saving.err != .None:
		return
	case now.manual:
		saving.err = .Constraint
		return
	case now.rev != in_.base_rev:
		saving.current, saving.conflict = now, true
		return
	}
	keep := db.writer_stmt(SQL_KEEP)
	db.bind_text(keep, 1, in_.slug)
	saving.err = db.step_done(keep)
	db.reset(keep)
	if saving.err != .None { return }

	st := db.writer_stmt(SQL_SET)
	db.bind_text(st, 1, in_.title)
	db.bind_int(st, 2, int(in_.visibility))
	db.bind_text(st, 3, in_.md)
	db.bind_text(st, 4, in_.html)
	db.bind_text(st, 5, in_.plain)
	db.bind_id(st, 6, time.time_to_unix(time.now()))
	db.bind_text(st, 7, in_.by)
	db.bind_text(st, 8, in_.slug)
	saving.err = db.step_done(st)
	db.reset(st)
	if saving.err != .None { return }

	trim := db.writer_stmt(SQL_TRIM)
	db.bind_text(trim, 1, in_.slug)
	db.bind_int(trim, 2, KEEP_REVISIONS + 1)
	saving.err = db.step_done(trim)
	db.reset(trim)
	if saving.err == .None { saving.current = current_page(in_.slug) }
}

// On the writer's connection, inside the save: a reader's snapshot wouldn't have it.
@(private)
current_page :: proc(slug: string) -> (p: m.Page) {
	q := db.writer_stmt(SQL_PAGE)
	defer db.reset(q)
	db.bind_text(q, 1, slug)
	err: store.Error
	if db.next_row(q, &err) { return one(q) }
	saving.err = .Not_Found if err == .None else err
	return
}

history :: proc(slug: string, out: ^[dynamic]m.Revision) -> (err: m.Error) {
	q := db.read(SQL_HISTORY)
	defer db.reset(q)
	db.bind_text(q, 1, slug)
	for db.next_row(q, &err) {
		append(out, m.Revision{rev = db.column_id(q, 0), title = db.clone_col(q, 1), at = db.column_id(q, 2), by = db.clone_col(q, 3)})
	}
	return
}

revision :: proc(slug: string, rev: i64) -> (r: m.Revision, err: m.Error) {
	q := db.read(SQL_REVISION)
	defer db.reset(q)
	db.bind_text(q, 1, slug)
	db.bind_id(q, 2, rev)
	if !db.next_row(q, &err) { return {}, .Not_Found if err == .None else err }
	return {rev = db.column_id(q, 0), title = db.clone_col(q, 1), at = db.column_id(q, 2), by = db.clone_col(q, 3), md = db.clone_col(q, 4)}, .None
}

// A member's page that already has a Manual slug keeps it: the Manual's row is what's skipped. Only a
// doc that changed is written, so a boot costs the index nothing.
seed_manual :: proc(pages: []m.Page) -> m.Error {
	saving.manual = pages
	ok := db.write_now(proc() -> bool {
		now := time.time_to_unix(time.now())
		for p in saving.manual {
			st := db.writer_stmt(SQL_MANUAL_SET)
			db.bind_text(st, 1, p.slug)
			db.bind_text(st, 2, p.title)
			db.bind_text(st, 3, p.md)
			db.bind_text(st, 4, p.html)
			db.bind_text(st, 5, p.plain)
			db.bind_id(st, 6, now)
			err := db.step_done(st)
			db.reset(st)
			if err != .None { return false }
		}
		gone := make([dynamic]string, context.temp_allocator)
		q := db.writer_stmt(SQL_MANUAL_ALL)
		err: store.Error
		for db.next_row(q, &err) {
			slug := db.clone_col(q, 0)
			kept := false
			for p in saving.manual {
				if p.slug == slug { kept = true }
			}
			if !kept { append(&gone, slug) }
		}
		db.reset(q)
		if err != .None { return false }
		for slug in gone {
			st := db.writer_stmt(SQL_DROP)
			db.bind_text(st, 1, slug)
			e := db.step_done(st)
			db.reset(st)
			if e != .None { return false }
		}
		return true
	})
	return .None if ok else .Failed
}
