package contacts_store_sqlite

// ---- contacts in SQLite --------------------------------------------------------------------
//
// Every list is filtered, sorted, paged and counted by SQLite, and only the rows
// asked for are copied out: a request's cost follows the page size, not the
// table (loading a 20k-row table into Odin took 100-260 ms a request). Reads run
// on the loop's reader; every write goes through the writer task, batched with
// the others, and reads its row back inside the batch, so the caller answers
// with exactly what was stored (S0.4's candidate C).

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/contacts/models"

IMPL :: "sqlite"

// The skeleton's three keep their names and hashes, so a skeleton database is
// adopted, not re-run (PLAN §11.7); 0004 adds the sort indexes (D36).
MIGRATIONS := [?]store.Migration {
	{1, "0001_init.sql", #load("migrations/0001_init.sql", string)},
	{2, "0002_events.sql", #load("migrations/0002_events.sql", string)},
	{3, "0003_contact_notes.sql", #load("migrations/0003_contact_notes.sql", string)},
	{4, "0004_sort_indexes.sql", #load("migrations/0004_sort_indexes.sql", string)},
}

@(private) COLUMNS :: "id,name,email,role,status,score,notes,notify"
@(private) SQL_GET :: "SELECT " + COLUMNS + " FROM contacts WHERE id=? LIMIT 1"
@(private) SQL_CREATE :: "INSERT INTO contacts(name,email,role,status,score,notes,notify) VALUES(?,?,?,?,?,?,?)"
@(private) SQL_UPDATE :: "UPDATE contacts SET name=?,email=?,role=?,status=?,score=? WHERE id=?"
// One statement, so two clicks at once advance the status twice instead of both
// reading the same value and writing the same next one. ?2 is len(m.Status).
@(private) SQL_CYCLE :: "UPDATE contacts SET status=(status+1)%?2 WHERE id=?1"
@(private) SQL_DELETE :: "DELETE FROM contacts WHERE id=?"
@(private) SQL_COUNT :: "SELECT count(*) FROM contacts"
// At most |Status| × |Role| × SCORE_BANDS rows, however big the table is.
@(private) SQL_STATS :: "SELECT status, role, score*?1/101, count(*), sum(score) FROM contacts GROUP BY 1, 2, 3"
@(private) SQL_RELATED :: "SELECT " + COLUMNS + " FROM contacts WHERE role=?1 AND id<>?2 ORDER BY id LIMIT ?3"

// The filter, the same in every list query: one status (?4), or -1 for any; and
// q (?1) in a role (?2) or status (?3) label, as bitmasks, or in the name or the
// email (contains_ci, registered on every connection). The cheap tests come
// first: SQLite evaluates them left to right.
@(private) WHERE :: `WHERE (?4 < 0 OR status = ?4) AND (?1 = '' OR (?2 >> role) & 1 OR (?3 >> status) & 1 OR contains_ci(name, ?1) OR contains_ci(email, ?1))`
@(private) SQL_MATCH :: "SELECT " + COLUMNS + " FROM contacts " + WHERE + " ORDER BY id LIMIT ?5"
@(private) SQL_FILTER_COUNT :: "SELECT count(*) FROM contacts " + WHERE

// Every event touching ?1 (as actor or target), newest first, joined to the OTHER
// contact (o). The trailing column is 1 when ?1 was the actor (outgoing).
@(private) SQL_TIMELINE :: `
	SELECT e.id, e.kind, e.at, e.note, o.id, o.name, (e.actor_id = ?1)
	FROM events e
	JOIN contacts o ON o.id = (CASE WHEN e.actor_id = ?1 THEN e.target_id ELSE e.actor_id END)
	WHERE e.actor_id = ?1 OR e.target_id = ?1
	ORDER BY e.at DESC, e.id DESC`
@(private) SQL_EVENT_CREATE :: "INSERT INTO events(actor_id,target_id,kind,at,note) VALUES(?,?,?,?,?)"
@(private) SQL_IDS :: "SELECT id FROM contacts ORDER BY id"

// One page statement per sort key and direction (ORDER BY can't be bound), built
// once, before main: the statement cache keys a statement by its SQL's address, so
// each must be built exactly once (at init, not under a sync.Once: M5-20).
@(private) page_sql: [m.Sort][2]string

@(private, init)
build_page_sql :: proc "contextless" () {
	context = runtime.default_context()
	for &by_dir, key in page_sql {
		for &sql, desc in by_dir {
			// id breaks ties, so a page boundary never splits equal rows unpredictably.
			dir := "DESC" if desc == 1 else "ASC"
			sql = fmt.aprintf("SELECT %s FROM contacts %s ORDER BY %s %s, id %s LIMIT ?5 OFFSET ?6", COLUMNS, WHERE, order_by(key), dir, dir)
		}
	}
}

// The ORDER BY expression for a key. Role and status are stored as their enum
// value but shown by label, so they sort by the label's A→Z rank: a CASE derived
// from the label tables, which 0004's indexes repeat.
order_by :: proc(key: m.Sort) -> string {
	rank :: proc(column: string, labels: []string) -> string {
		b := strings.builder_make()
		fmt.sbprintf(&b, "CASE %s", column)
		for v, i in labels {
			r := 0 // the label's place in A→Z order: how many labels sort before it
			for other in labels {
				if other < v { r += 1 }
			}
			fmt.sbprintf(&b, " WHEN %d THEN %d", i, r)
		}
		strings.write_string(&b, " END")
		return strings.to_string(b)
	}
	switch key {
	case .Name:   return "name"
	case .Email:  return "email"
	case .Score:  return "score"
	case .Role:   return rank("role", slice.enumerated_array(&m.ROLE_NAMES))
	case .Status: return rank("status", slice.enumerated_array(&m.STATUS_NAMES))
	}
	return "id"
}

// ---- reads --------------------------------------------------------------------------------

page :: proc(f: m.Filter, key: m.Sort, desc: bool, limit, offset: int, out: ^[dynamic]m.Contact) -> m.Error {
	q := db.read(page_sql[key][1 if desc else 0])
	defer db.reset(q)
	bind_filter(q, f)
	db.bind_int(q, 5, limit)
	db.bind_int(q, 6, offset)
	return collect(q, out)
}

filter_count :: proc(f: m.Filter) -> (int, m.Error) {
	q := db.read(SQL_FILTER_COUNT)
	defer db.reset(q)
	bind_filter(q, f)
	err: m.Error
	if db.next_row(q, &err) { return db.column_int(q, 0), .None }
	return 0, err
}

// The first `limit` matches in id order: the search dropdown and the JSON API.
match :: proc(f: m.Filter, limit: int, out: ^[dynamic]m.Contact) -> m.Error {
	q := db.read(SQL_MATCH)
	defer db.reset(q)
	bind_filter(q, f)
	db.bind_int(q, 5, limit)
	return collect(q, out)
}

// Others with the same role as contact `id`, in id order.
related :: proc(id: i64, role: m.Role, limit: int, out: ^[dynamic]m.Contact) -> m.Error {
	q := db.read(SQL_RELATED)
	defer db.reset(q)
	db.bind_int(q, 1, int(role))
	db.bind_id(q, 2, id)
	db.bind_int(q, 3, limit)
	return collect(q, out)
}

get :: proc(id: i64) -> (m.Contact, m.Error) {
	q := db.read(SQL_GET)
	defer db.reset(q)
	return get_on(q, id, context.temp_allocator)
}

// Counts by status and role, the score spread per status, and the score sum.
stats :: proc() -> (out: m.Contact_Stats, err: m.Error) {
	q := db.read(SQL_STATS)
	defer db.reset(q)
	db.bind_int(q, 1, m.SCORE_BANDS)
	for db.next_row(q, &err) {
		status, sok := store.enum_from_int(m.Status, db.column_int(q, 0))
		role, rok := store.enum_from_int(m.Role, db.column_int(q, 1))
		if !sok || !rok { continue } // a row from a newer enum than this binary: skip it, never index past the end
		band := clamp(db.column_int(q, 2), 0, m.SCORE_BANDS - 1)
		n := db.column_int(q, 3)
		out.by_status[status] += n
		out.by_role[role] += n
		out.by_score[status][band] += n
		out.score_sum += db.column_int(q, 4)
	}
	return
}

// The detail drawer's activity feed: real interactions, the other party resolved.
timeline :: proc(id: i64, out: ^[dynamic]m.Interaction) -> (err: m.Error) {
	q := db.read(SQL_TIMELINE)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	for db.next_row(q, &err) {
		kind, ok := store.enum_from_int(m.Event_Kind, db.column_int(q, 1))
		if !ok { continue }
		append(out, m.Interaction {
			id         = db.column_id(q, 0),
			kind       = kind,
			at         = db.column_id(q, 2),
			note       = db.clone_col(q, 3),
			other_id   = db.column_id(q, 4),
			other_name = db.clone_col(q, 5),
			outgoing   = db.column_bool(q, 6),
		})
	}
	return
}

// ---- writes, on the writer task ------------------------------------------------------------

write :: proc(w: ^m.Write) -> bool {
	w.run = run_write
	return db.write(w)
}

@(private)
run_write :: proc(op: ^store.Op) {
	w := (^m.Write)(op)
	a := store.op_allocator(op)
	switch w.kind {
	case .Create:
		st := db.writer_stmt(SQL_CREATE)
		c := w.input
		db.bind_text(st, 1, c.name)
		db.bind_text(st, 2, c.email)
		db.bind_int(st, 3, int(c.role))
		db.bind_int(st, 4, int(c.status))
		db.bind_int(st, 5, c.score)
		db.bind_text(st, 6, c.notes)
		db.bind_bool(st, 7, c.notify)
		op.err = db.step_done(st)
		db.reset(st)
		if op.err == .None { w.result, op.err = read_back(db.last_insert_id(), a) }
	case .Update:
		st := db.writer_stmt(SQL_UPDATE)
		c := w.input
		db.bind_text(st, 1, c.name)
		db.bind_text(st, 2, c.email)
		db.bind_int(st, 3, int(c.role))
		db.bind_int(st, 4, int(c.status))
		db.bind_int(st, 5, c.score)
		db.bind_id(st, 6, w.id)
		op.err = changed(st)
		if op.err == .None { w.result, op.err = read_back(w.id, a) }
	case .Cycle:
		st := db.writer_stmt(SQL_CYCLE)
		db.bind_id(st, 1, w.id)
		db.bind_int(st, 2, len(m.Status))
		op.err = changed(st)
		if op.err == .None { w.result, op.err = read_back(w.id, a) }
	case .Delete:
		// Deleting a contact cascades to its events (events.*_id ON DELETE CASCADE).
		st := db.writer_stmt(SQL_DELETE)
		db.bind_id(st, 1, w.id)
		op.err = changed(st)
	}
}

// A write that must touch a row: .Not_Found when none matched.
@(private)
changed :: proc(st: db.Stmt) -> m.Error {
	defer db.reset(st)
	if err := db.step_done(st); err != .None { return err }
	return .None if db.changes() > 0 else .Not_Found
}

@(private)
read_back :: proc(id: i64, a: mem.Allocator) -> (m.Contact, m.Error) {
	q := db.writer_stmt(SQL_GET)
	defer db.reset(q)
	return get_on(q, id, a)
}

// ---- the seed -------------------------------------------------------------------------------

// Deterministic demo rows, into empty tables only: twenty contacts, then three
// interactions each among them, spread over the past ~200 days.
seed :: proc() {
	db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_COUNT)
		err: m.Error
		n := db.column_int(q, 0) if db.next_row(q, &err) else -1
		db.reset(q)
		if n != 0 { return n > 0 }
		return seed_contacts() && seed_events()
	})
}

reset :: proc() -> bool {
	return db.write_now(proc() -> bool {
		for sql in ([]string{"DELETE FROM events", "DELETE FROM contacts"}) {
			st := db.writer_stmt(sql)
			ok := db.step_done(st) == .None
			db.reset(st)
			if !ok { return false }
		}
		return seed_contacts() && seed_events()
	})
}

@(private)
seed_contacts :: proc() -> bool {
	firsts := []string {
		"Ada", "Linus", "Grace", "Dennis", "Margaret", "Alan", "Katherine",
		"Edsger", "Barbara", "Donald", "Radia", "Ken", "Hedy", "Tim",
		"Anita", "John", "Carol", "Vint", "Shafi", "Niklaus",
	}
	lasts := []string {
		"Lovelace", "Torvalds", "Hopper", "Ritchie", "Hamilton", "Turing",
		"Johnson", "Dijkstra", "Liskov", "Knuth", "Perlman", "Thompson",
		"Lamarr", "Berners-Lee", "Borg", "Carmack", "Shaw", "Cerf",
		"Goldwasser", "Wirth",
	}
	for i in 0 ..< len(firsts) {
		first, last := firsts[i], lasts[i % len(lasts)]
		st := db.writer_stmt(SQL_CREATE)
		db.bind_text(st, 1, strings.concatenate({first, " ", last}, context.temp_allocator))
		db.bind_text(st, 2, strings.to_lower(strings.concatenate({first, ".", last, "@example.dev"}, context.temp_allocator), context.temp_allocator))
		db.bind_int(st, 3, (i * 7 + 3) % len(m.Role))
		db.bind_int(st, 4, i % len(m.Status))
		db.bind_int(st, 5, 35 + (i * 53) % 64)
		db.bind_text(st, 6, "")
		db.bind_bool(st, 7, false)
		ok := db.step_done(st) == .None
		db.reset(st)
		if !ok { return false }
	}
	return true
}

// Over whatever contacts exist, so it also backfills a contacts-only database
// migrated to add the events table. Each contact acts on three others.
@(private)
seed_events :: proc() -> bool {
	ids := make([dynamic]i64, context.temp_allocator)
	{
		q := db.writer_stmt(SQL_IDS)
		err: m.Error
		for db.next_row(q, &err) { append(&ids, db.column_id(q, 0)) }
		db.reset(q)
	}
	n := len(ids)
	if n < 2 { return true }
	now := time.time_to_unix(time.now())
	kinds := [?]m.Event_Kind{.Introduced, .Mentioned, .Reviewed, .Messaged}
	notes := [?]string{"after the planning sync", "on the platform thread", "during code review", "re: the incident retro", "about the Q3 roadmap"}
	DAY :: i64(86400)
	for i in 0 ..< n {
		for k in 0 ..< 3 {
			tgt := ids[(i + 3 + k * 5) % n]
			if tgt == ids[i] { continue }
			st := db.writer_stmt(SQL_EVENT_CREATE)
			db.bind_id(st, 1, ids[i])
			db.bind_id(st, 2, tgt)
			db.bind_int(st, 3, int(kinds[(i + k) % len(kinds)]))
			db.bind_id(st, 4, now - i64(2 + (i * 7 + k * 13) % 200) * DAY)
			db.bind_text(st, 5, notes[(i + k) % len(notes)])
			ok := db.step_done(st) == .None
			db.reset(st)
			if !ok { return false }
		}
	}
	return true
}

// ---- internals --------------------------------------------------------------------------------

@(private)
bind_filter :: proc(st: db.Stmt, f: m.Filter) {
	db.bind_text(st, 1, f.q)
	db.bind_id(st, 2, i64(f.role_mask))
	db.bind_id(st, 3, i64(f.status_mask))
	db.bind_int(st, 4, f.status)
}

@(private)
collect :: proc(st: db.Stmt, out: ^[dynamic]m.Contact) -> (err: m.Error) {
	for db.next_row(st, &err) {
		c, ok := scan(st, context.temp_allocator)
		if !ok { return .Failed }
		append(out, c)
	}
	return
}

// An out-of-range enum is an error, never an index (02 F3).
@(private)
scan :: proc(st: db.Stmt, a: mem.Allocator) -> (c: m.Contact, ok: bool) {
	role, rok := store.enum_from_int(m.Role, db.column_int(st, 3))
	status, sok := store.enum_from_int(m.Status, db.column_int(st, 4))
	c = m.Contact {
		id     = db.column_id(st, 0),
		name   = db.clone_col(st, 1, a),
		email  = db.clone_col(st, 2, a),
		role   = role,
		status = status,
		score  = db.column_int(st, 5),
		notes  = db.clone_col(st, 6, a),
		notify = db.column_bool(st, 7),
	}
	return c, rok && sok
}

@(private)
get_on :: proc(q: db.Stmt, id: i64, a: mem.Allocator) -> (m.Contact, m.Error) {
	db.bind_id(q, 1, id)
	err: m.Error
	if db.next_row(q, &err) {
		c, ok := scan(q, a)
		return c, .None if ok else .Failed
	}
	return {}, .Not_Found if err == .None else err
}
