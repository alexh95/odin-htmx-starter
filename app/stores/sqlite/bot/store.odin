package bot_store_sqlite

// ---- the bot's conversations in SQLite (PLAN §14.3, M7) ---------------------------------------
//
// Each member's newest KEEP conversations, each with its last TURNS turns, kept across restarts.
// A conversation is its owner's alone (Q20): every read and write names the owner, and another
// member's id answers .Not_Found. Reads on the loop's reader; a new conversation or turn goes
// through the writer task, which trims in the same batch.

import "core:strings"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/bot/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_bot.sql", #load("migrations/0001_bot.sql", string)},
}

// The memory store's numbers: the domain can't name them, since it imports the store.
KEEP :: 50   // conversations per member
TURNS :: 200 // turns per conversation

@(private) SQL_CONVERSATIONS :: "SELECT id, title, at, turns FROM bot_conversations WHERE owner = ? ORDER BY id DESC LIMIT ?"
@(private) SQL_CONVERSATION :: "SELECT title, at, turns FROM bot_conversations WHERE id = ? AND owner = ?"
@(private) SQL_TURNS :: "SELECT id, role, text, at, stop, tokens, ms_first, ms_total FROM bot_turns WHERE conv = ? ORDER BY id"
@(private) SQL_USAGE_CONVS :: "SELECT count(*) FROM bot_conversations"
@(private) SQL_USAGE_ANSWERS :: "SELECT count(*), coalesce(sum(tokens), 0), coalesce(avg(ms_first), 0), coalesce(avg(ms_total), 0) FROM bot_turns WHERE role = 1"
@(private) SQL_START :: "INSERT INTO bot_conversations(owner, title, at) VALUES(?, ?, ?)"
@(private) SQL_DROP_TURNS :: "DELETE FROM bot_turns WHERE conv IN (SELECT id FROM bot_conversations WHERE owner = ?1 ORDER BY id DESC LIMIT -1 OFFSET ?2)"
@(private) SQL_DROP_CONVS :: "DELETE FROM bot_conversations WHERE id IN (SELECT id FROM bot_conversations WHERE owner = ?1 ORDER BY id DESC LIMIT -1 OFFSET ?2)"
@(private) SQL_OWNED :: "SELECT 1 FROM bot_conversations WHERE id = ? AND owner = ?"
@(private) SQL_APPEND :: "INSERT INTO bot_turns(conv, role, text, at, stop, tokens, ms_first, ms_total) VALUES(?, ?, ?, ?, ?, ?, ?, ?)"
@(private) SQL_COUNT :: "UPDATE bot_conversations SET turns = turns + 1, title = CASE ?2 WHEN '' THEN title ELSE ?2 END WHERE id = ?1"
@(private) SQL_TRIM :: "DELETE FROM bot_turns WHERE conv = ?1 AND id <= (SELECT id FROM bot_turns WHERE conv = ?1 ORDER BY id DESC LIMIT 1 OFFSET ?2)"

conversations :: proc(owner: u64, limit: int, out: ^[dynamic]m.Conversation) -> (err: m.Error) {
	q := db.read(SQL_CONVERSATIONS)
	defer db.reset(q)
	db.bind_id(q, 1, i64(owner))
	db.bind_int(q, 2, limit)
	for db.next_row(q, &err) {
		append(out, m.Conversation {
			id = db.column_id(q, 0), owner = owner, title = db.clone_col(q, 1), at = db.column_id(q, 2), turns = db.column_int(q, 3),
		})
	}
	return
}

conversation :: proc(owner: u64, id: i64) -> (c: m.Conversation, err: m.Error) {
	q := db.read(SQL_CONVERSATION)
	defer db.reset(q)
	db.bind_id(q, 1, id)
	db.bind_id(q, 2, i64(owner))
	if !db.next_row(q, &err) { return {}, err if err != .None else .Not_Found }
	return {id = id, owner = owner, title = db.clone_col(q, 0), at = db.column_id(q, 1), turns = db.column_int(q, 2)}, .None
}

turns :: proc(owner: u64, conv: i64, out: ^[dynamic]m.Turn) -> (err: m.Error) {
	if _, e := conversation(owner, conv); e != .None { return e }
	q := db.read(SQL_TURNS)
	defer db.reset(q)
	db.bind_id(q, 1, conv)
	for db.next_row(q, &err) {
		role, _ := store.enum_from_int(m.Bot_Role, db.column_int(q, 1))
		stop, _ := store.enum_from_int(m.Bot_Stop, db.column_int(q, 4))
		append(out, m.Turn {
			id = db.column_id(q, 0), conv = conv, role = role, text = db.clone_col(q, 2), at = db.column_id(q, 3),
			stats = {stop = stop, tokens = db.column_int(q, 5), ms_first_token = db.column_int(q, 6), ms_total = db.column_int(q, 7)},
		})
	}
	return
}

usage :: proc() -> (u: m.Usage, err: m.Error) {
	q := db.read(SQL_USAGE_CONVS)
	if db.next_row(q, &err) { u.conversations = db.column_int(q, 0) }
	db.reset(q)
	if err != .None { return }
	a := db.read(SQL_USAGE_ANSWERS)
	defer db.reset(a)
	if db.next_row(a, &err) {
		u.answers, u.tokens = db.column_int(a, 0), db.column_int(a, 1)
		u.avg_first_ms, u.avg_total_ms = db.column_int(a, 2), db.column_int(a, 3)
	}
	return
}

start :: proc(op: ^m.Start) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Start)(o)
		at := now()
		st := db.writer_stmt(SQL_START)
		db.bind_id(st, 1, i64(op.owner))
		db.bind_text(st, 2, op.title)
		db.bind_id(st, 3, at)
		o.err = db.step_done(st)
		db.reset(st)
		if o.err != .None { return }
		op.result = {id = db.last_insert_id(), owner = op.owner, title = strings.clone(op.title, store.op_allocator(o)), at = at}
		for sql in ([]string{SQL_DROP_TURNS, SQL_DROP_CONVS}) {
			tr := db.writer_stmt(sql)
			db.bind_id(tr, 1, i64(op.owner))
			db.bind_int(tr, 2, KEEP)
			o.err = db.step_done(tr)
			db.reset(tr)
			if o.err != .None { return }
		}
	}
	return db.write(op)
}

append_turn :: proc(op: ^m.Append) -> bool {
	op.run = proc(o: ^store.Op) {
		op := (^m.Append)(o)
		c := db.writer_stmt(SQL_OWNED)
		db.bind_id(c, 1, op.turn.conv)
		db.bind_id(c, 2, i64(op.owner))
		owned := db.next_row(c, &o.err)
		db.reset(c)
		if o.err != .None { return }
		if !owned {
			o.err = .Not_Found
			return
		}
		t := op.turn
		t.at = now()
		st := db.writer_stmt(SQL_APPEND)
		db.bind_id(st, 1, t.conv)
		db.bind_int(st, 2, int(t.role))
		db.bind_text(st, 3, t.text)
		db.bind_id(st, 4, t.at)
		db.bind_int(st, 5, int(t.stats.stop))
		db.bind_int(st, 6, t.stats.tokens)
		db.bind_int(st, 7, t.stats.ms_first_token)
		db.bind_int(st, 8, t.stats.ms_total)
		o.err = db.step_done(st)
		db.reset(st)
		if o.err != .None { return }
		t.id = db.last_insert_id()
		n := db.writer_stmt(SQL_COUNT)
		db.bind_id(n, 1, t.conv)
		db.bind_text(n, 2, op.title)
		o.err = db.step_done(n)
		db.reset(n)
		if o.err != .None { return }
		tr := db.writer_stmt(SQL_TRIM)
		db.bind_id(tr, 1, t.conv)
		db.bind_int(tr, 2, TURNS)
		o.err = db.step_done(tr)
		db.reset(tr)
		if o.err != .None { return }
		t.text = strings.clone(t.text, store.op_allocator(o))
		op.result = t
	}
	return db.write(op)
}

@(private)
now :: proc() -> i64 { return time.time_to_unix(time.now()) }
