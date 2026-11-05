package polls_store_sqlite

// ---- polls in SQLite -------------------------------------------------------------------------------
//
// Every poll's bars read `poll_tally`. An anonymous vote bumps its counters and adds a row to `poll_voters`, and
// that's all that's kept, so nothing here can answer what someone chose: the migration says why the two can't
// be lined up. A named vote also keeps a row per choice in `poll_votes`, which is what lets it change. All of a
// vote is one transaction, on the query pool under the writer's lock.

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/polls/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_polls.sql", #load("migrations/0001_polls.sql", string)},
}

DUE_BATCH :: 50

@(private) SQL_SUMMARIES :: "SELECT p.id, p.question, p.anonymous, p.closed_at <> 0 OR p.closes_at <= ?1, (SELECT count(*) FROM poll_voters v WHERE v.poll = p.id) FROM polls p " +
	"ORDER BY p.closed_at <> 0 OR p.closes_at <= ?1, p.id DESC LIMIT 200"
@(private) SQL_POLL :: "SELECT question, multiple, anonymous, closes_at, closed_at, by_id, by_name, (SELECT count(*) FROM poll_voters v WHERE v.poll = polls.id) FROM polls WHERE id = ?"
@(private) SQL_OPTIONS :: "SELECT o.id, o.label, t.n FROM poll_options o JOIN poll_tally t ON t.poll = o.poll AND t.option = o.id WHERE o.poll = ? ORDER BY o.pos"
@(private) SQL_NAMES :: "SELECT name FROM poll_votes WHERE poll = ? AND option = ? ORDER BY name COLLATE NOCASE"
@(private) SQL_VOTED :: "SELECT 1 FROM poll_voters WHERE poll = ? AND who = ?"
@(private) SQL_MINE :: "SELECT option FROM poll_votes WHERE poll = ? AND who = ?"
@(private) SQL_ADD :: "INSERT INTO polls(question, multiple, anonymous, closes_at, by_id, by_name, at) VALUES(?, ?, ?, ?, ?, ?, ?) RETURNING id"
@(private) SQL_ADD_OPTION :: "INSERT INTO poll_options(poll, label, pos) VALUES(?, ?, ?) RETURNING id"
@(private) SQL_ADD_TALLY :: "INSERT INTO poll_tally(poll, option) VALUES(?, ?)"
@(private) SQL_STATE :: "SELECT multiple, anonymous, closes_at, closed_at, by_id, question FROM polls WHERE id = ?"
@(private) SQL_ADD_VOTER :: "INSERT INTO poll_voters(poll, who) VALUES(?, ?) ON CONFLICT DO NOTHING"
@(private) SQL_BUMP :: "UPDATE poll_tally SET n = n + 1 WHERE poll = ? AND option = ?"
@(private) SQL_UNBUMP :: "UPDATE poll_tally SET n = n - 1 WHERE poll = ?1 AND option IN (SELECT option FROM poll_votes WHERE poll = ?1 AND who = ?2)"
@(private) SQL_FORGET :: "DELETE FROM poll_votes WHERE poll = ? AND who = ?"
@(private) SQL_REMEMBER :: "INSERT INTO poll_votes(poll, who, option, name) VALUES(?, ?, ?, ?)"
@(private) SQL_CLOSE :: "UPDATE polls SET closed_at = ? WHERE id = ?"
@(private) SQL_DUE :: "SELECT id, question FROM polls WHERE closed_at = 0 AND closes_at <= ? ORDER BY closes_at LIMIT ?"
@(private) SQL_VOTERS :: "SELECT who FROM poll_voters WHERE poll = ?"

summaries :: proc(now: i64, out: ^[dynamic]m.Summary) -> (err: m.Error) {
	q := db.read(SQL_SUMMARIES)
	defer db.reset(q)
	db.bind_id(q, 1, now)
	for db.next_row(q, &err) {
		append(out, m.Summary{
			id = db.column_id(q, 0), question = db.clone_col(q, 1), anonymous = db.column_int(q, 2) != 0,
			closed = db.column_int(q, 3) != 0, voters = db.column_int(q, 4),
		})
	}
	return
}

@(private)
names_of :: proc(id, option: i64) -> (out: []string, err: m.Error) {
	q := db.read(SQL_NAMES)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	db.bind_id(q, 2, option)
	names := make([dynamic]string, context.temp_allocator)
	for db.next_row(q, &err) { append(&names, db.clone_col(q, 0)) }
	return names[:], err
}

poll :: proc(id: i64, me: u64, now: i64) -> (p: m.Poll, err: m.Error) {
	{
		q := db.read(SQL_POLL)
		defer db.reset(q)
		db.bind_id(q, 1, id)
		if !db.next_row(q, &err) { return {}, .Not_Found if err == .None else err }
		p = {
			id = id, question = db.clone_col(q, 0), multiple = db.column_int(q, 1) != 0, anonymous = db.column_int(q, 2) != 0,
			closed = db.column_id(q, 4) != 0 || db.column_id(q, 3) <= now, by = u64(db.column_id(q, 5)),
			by_name = db.clone_col(q, 6), voters = db.column_int(q, 7),
		}
	}
	options := make([dynamic]m.Option, context.temp_allocator)
	{
		q := db.read(SQL_OPTIONS)
		defer db.reset(q)
		db.bind_id(q, 1, id)
		for db.next_row(q, &err) { append(&options, m.Option{id = db.column_id(q, 0), label = db.clone_col(q, 1), n = db.column_int(q, 2)}) }
		if err != .None { return }
	}
	p.options = options[:]
	{
		q := db.read(SQL_VOTED)
		defer db.reset(q)
		db.bind_id(q, 1, id)
		db.bind_id(q, 2, i64(me))
		p.voted = db.next_row(q, &err)
		if err != .None { return }
	}
	if p.anonymous { return }
	for &o in p.options {
		if o.names, err = names_of(id, o.id); err != .None { return }
	}
	q := db.read(SQL_MINE)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	db.bind_id(q, 2, i64(me))
	mine := make([dynamic]i64, context.temp_allocator)
	for db.next_row(q, &err) { append(&mine, db.column_id(q, 0)) }
	p.mine = mine[:]
	return
}

// What a proc run under write_now reads, which takes no arguments; it runs on the caller's thread.
@(private) @(thread_local) w: struct {
	new:     m.New_Poll,
	poll:    i64,
	options: []i64,
	by:      m.Actor,
	now:     i64,
	result:  m.Vote_Result,
	closed:  [dynamic]m.Closed,
	err:     m.Error,
}

@(private)
done :: proc(ok: bool) -> m.Error {
	if w.err != .None { return w.err }
	return .None if ok else .Failed
}

@(private)
exec :: proc(st: db.Stmt) -> bool {
	w.err = db.step_done(st)
	db.reset(st)
	return w.err == .None
}

@(private)
pair :: proc(sql: string, a, b: i64) -> bool {
	st := db.writer_stmt(sql)
	db.bind_id(st, 1, a)
	db.bind_id(st, 2, b)
	return exec(st)
}

// The new row's id, from a statement with RETURNING.
@(private)
inserted :: proc(st: db.Stmt) -> (id: i64, ok: bool) {
	defer db.reset(st)
	if db.next_row(st, &w.err) { return db.column_id(st, 0), true }
	if w.err == .None { w.err = .Failed }
	return 0, false
}

create :: proc(p: m.New_Poll, by: m.Actor, now: i64) -> (id: i64, err: m.Error) {
	w = {new = p, by = by, now = now}
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_ADD)
		db.bind_text(st, 1, w.new.question)
		db.bind_id(st, 2, 1 if w.new.multiple else 0)
		db.bind_id(st, 3, 1 if w.new.anonymous else 0)
		db.bind_id(st, 4, w.new.closes_at)
		db.bind_id(st, 5, i64(w.by.id))
		db.bind_text(st, 6, w.by.name)
		db.bind_id(st, 7, w.now)
		found: bool
		if w.poll, found = inserted(st); !found { return false }
		for label, i in w.new.options {
			o := db.writer_stmt(SQL_ADD_OPTION)
			db.bind_id(o, 1, w.poll)
			db.bind_text(o, 2, label)
			db.bind_id(o, 3, i64(i))
			option, added := inserted(o)
			if !added || !pair(SQL_ADD_TALLY, w.poll, option) { return false }
		}
		return true
	})
	return w.poll, done(ok)
}

@(private)
Poll_State :: struct {
	multiple, anonymous, closed: bool,
	by:                          u64,
	question:                    string,
}

@(private)
state :: proc(id: i64) -> (s: Poll_State, found: bool) {
	q := db.writer_stmt(SQL_STATE)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	if !db.next_row(q, &w.err) { return }
	return {
		multiple = db.column_int(q, 0) != 0, anonymous = db.column_int(q, 1) != 0,
		closed = db.column_id(q, 3) != 0 || db.column_id(q, 2) <= w.now, by = u64(db.column_id(q, 4)),
		question = db.clone_col(q, 5),
	}, true
}

@(private)
has_voted :: proc() -> bool {
	q := db.writer_stmt(SQL_VOTED)
	defer db.reset(q)
	db.bind_id(q, 1, w.poll)
	db.bind_id(q, 2, i64(w.by.id))
	return db.next_row(q, &w.err)
}

vote :: proc(id: i64, options: []i64, by: m.Actor, now: i64) -> (m.Vote_Result, m.Error) {
	w = {poll = id, options = options, by = by, now = now}
	ok := db.write_now(proc() -> bool {
		p, found := state(w.poll)
		if !found {
			if w.err == .None { w.err = .Not_Found }
			return false
		}
		if p.closed {
			w.result = .Closed
			return true
		}
		if !p.multiple && len(w.options) != 1 {
			w.err = .Not_Found
			return false
		}
		voted := has_voted()
		if w.err != .None { return false }
		if voted && p.anonymous {
			w.result = .Already
			return true
		}
		if voted {
			if !pair(SQL_UNBUMP, w.poll, i64(w.by.id)) || !pair(SQL_FORGET, w.poll, i64(w.by.id)) { return false }
		}
		if !pair(SQL_ADD_VOTER, w.poll, i64(w.by.id)) { return false }
		for option in w.options {
			if !pair(SQL_BUMP, w.poll, option) { return false }
			if db.changes() == 0 {
				w.err = .Not_Found // rolls back whatever it has done
				return false
			}
			if p.anonymous { continue }
			st := db.writer_stmt(SQL_REMEMBER)
			db.bind_id(st, 1, w.poll)
			db.bind_id(st, 2, i64(w.by.id))
			db.bind_id(st, 3, option)
			db.bind_text(st, 4, w.by.name)
			if !exec(st) { return false }
		}
		return true
	})
	return w.result, done(ok)
}

// Closes one, under the writer's lock, and keeps who to tell.
@(private)
shut :: proc(id: i64, question: string) -> bool {
	if !pair(SQL_CLOSE, w.now, id) { return false }
	q := db.writer_stmt(SQL_VOTERS)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	voters := make([dynamic]u64, context.temp_allocator)
	for db.next_row(q, &w.err) { append(&voters, u64(db.column_id(q, 0))) }
	append(&w.closed, m.Closed{id, question, voters[:]})
	return w.err == .None
}

close :: proc(id: i64, by: u64, now: i64) -> (c: m.Closed, err: m.Error) {
	w = {poll = id, by = {id = by}, now = now, closed = make([dynamic]m.Closed, context.temp_allocator)}
	ok := db.write_now(proc() -> bool {
		p, found := state(w.poll)
		if w.err != .None { return false }
		if !found || p.closed || p.by != w.by.id {
			w.err = .Not_Found
			return false
		}
		return shut(w.poll, p.question)
	})
	if err = done(ok); err != .None { return }
	return w.closed[0], .None
}

close_due :: proc(now: i64) -> (out: []m.Closed, err: m.Error) {
	w = {now = now, closed = make([dynamic]m.Closed, context.temp_allocator)}
	ok := db.write_now(proc() -> bool {
		due := make([dynamic]m.Closed, context.temp_allocator)
		{
			q := db.writer_stmt(SQL_DUE)
			defer db.reset(q)
			db.bind_id(q, 1, w.now)
			db.bind_id(q, 2, DUE_BATCH)
			for db.next_row(q, &w.err) { append(&due, m.Closed{id = db.column_id(q, 0), question = db.clone_col(q, 1)}) }
			if w.err != .None { return false }
		}
		for d in due {
			if !shut(d.id, d.question) { return false }
		}
		return true
	})
	if err = done(ok); err != .None { return nil, err }
	return w.closed[:], .None
}
