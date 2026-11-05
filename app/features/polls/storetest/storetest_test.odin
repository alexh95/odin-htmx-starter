package polls_storetest

// ---- the polls store: votes, finality, closing, and what an anonymous vote leaves --------------------------

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:testing"

import "../../../platform/guard"
import "../../../platform/obs"
import db "../../../platform/store/sqlite"
import m "../models"
import sql "../../../stores/sqlite/polls"

@(private = "file")
ANN :: m.Actor{1, "ann"}
@(private = "file")
BOB :: m.Actor{2, "bob"}
@(private = "file")
NOW :: i64(1_000_000)

@(private = "file")
make_poll :: proc(t: ^testing.T, anonymous, multiple: bool) -> (m.Poll, []i64) {
	id, err := sql.create({"Picnic?", {"Sat", "Sun", "Never"}, multiple, anonymous, NOW + 600}, ANN, NOW)
	testing.expect_value(t, err, m.Error.None)
	p, perr := sql.poll(id, ANN.id, NOW)
	testing.expect_value(t, perr, m.Error.None)
	ids := make([]i64, len(p.options), context.temp_allocator)
	for o, i in p.options { ids[i] = o.id }
	return p, ids
}

// One row's one text.
@(private = "file")
one :: proc(sql: string) -> string {
	q := db.read(sql)
	defer db.reset(q)
	err: m.Error
	if db.next_row(q, &err) { return db.clone_col(q, 0) }
	return ""
}

@(private = "file")
a_named_vote_can_change :: proc(t: ^testing.T) {
	p, o := make_poll(t, false, false)
	r, err := sql.vote(p.id, {o[0]}, ANN, NOW)
	testing.expect_value(t, err, m.Error.None)
	testing.expect_value(t, r, m.Vote_Result.Recorded)
	sql.vote(p.id, {o[0]}, BOB, NOW)
	r, err = sql.vote(p.id, {o[1]}, ANN, NOW)
	testing.expect_value(t, r, m.Vote_Result.Recorded)

	now, _ := sql.poll(p.id, ANN.id, NOW)
	testing.expect_value(t, now.voters, 2)
	testing.expect_value(t, now.options[0].n, 1)
	testing.expect_value(t, now.options[1].n, 1)
	testing.expect_value(t, strings.join(now.options[0].names, ","), "bob")
	testing.expect_value(t, strings.join(now.options[1].names, ","), "ann")
	testing.expect(t, now.voted && len(now.mine) == 1 && now.mine[0] == o[1])

	// A single choice takes one, and an option off another poll isn't one.
	_, err = sql.vote(p.id, {o[0], o[1]}, ANN, NOW)
	testing.expect_value(t, err, m.Error.Not_Found)
	other, oo := make_poll(t, false, true)
	_, err = sql.vote(other.id, {oo[0], o[0]}, BOB, NOW)
	testing.expect_value(t, err, m.Error.Not_Found)
	after, _ := sql.poll(other.id, BOB.id, NOW)
	testing.expect_value(t, after.voters, 0) // and the half that went in is rolled back
	testing.expect_value(t, after.options[0].n, 0)
}

@(private = "file")
an_anonymous_vote_is_final_and_leaves_no_link :: proc(t: ^testing.T) {
	p, o := make_poll(t, true, true)
	r, err := sql.vote(p.id, {o[0], o[2]}, ANN, NOW)
	testing.expect_value(t, err, m.Error.None)
	testing.expect_value(t, r, m.Vote_Result.Recorded)
	r, err = sql.vote(p.id, {o[1]}, ANN, NOW)
	testing.expect_value(t, err, m.Error.None)
	testing.expect_value(t, r, m.Vote_Result.Already)

	now, _ := sql.poll(p.id, ANN.id, NOW)
	testing.expect_value(t, now.voters, 1) // several choices are still one voter
	testing.expect_value(t, now.options[0].n, 1)
	testing.expect_value(t, now.options[1].n, 0)
	testing.expect_value(t, now.options[2].n, 1)
	testing.expect(t, now.voted)
	testing.expect_value(t, len(now.mine), 0) // not even to the voter
	for option in now.options { testing.expect_value(t, len(option.names), 0) }

	// All there is: counters, and who, with no time and no order but their ids'.
	testing.expect_value(t, one("SELECT group_concat(name) FROM pragma_table_info('poll_voters')"), "poll,who")
	testing.expect_value(t, one("SELECT group_concat(name) FROM pragma_table_info('poll_tally')"), "poll,option,n")
	testing.expect_value(t, one(fmt.tprintf("SELECT count(*) FROM poll_votes WHERE poll = %d", p.id)), "0")
	testing.expect_value(t, one("SELECT sum(wr) FROM pragma_table_list WHERE name IN ('poll_voters', 'poll_tally')"), "2") // a rowid would keep the order they came in
	// Any table holding a voter beside an option would have both columns, and only the named polls' does.
	testing.expect_value(t, one("SELECT group_concat(m.name) FROM sqlite_master m, pragma_table_info(m.name) a, pragma_table_info(m.name) b WHERE m.type = 'table' AND a.name = 'who' AND b.name = 'option'"), "poll_votes")
}

@(private = "file")
the_flag_stays :: proc(t: ^testing.T) {
	make_poll(t, false, false)
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt("UPDATE polls SET anonymous = 1")
		err := db.step_done(st)
		db.reset(st)
		return err == .None
	})
	testing.expect(t, !ok, "a poll stays as it was made")
}

// A closed poll newer than an open one still comes after it, or a flood of polls would hide what's open.
@(private = "file")
open_polls_come_first :: proc(t: ^testing.T) {
	open, _ := make_poll(t, false, false)
	shut, _ := make_poll(t, false, false)
	_, err := sql.close(shut.id, ANN.id, NOW)
	testing.expect_value(t, err, m.Error.None)
	all := make([dynamic]m.Summary, context.temp_allocator)
	testing.expect_value(t, sql.summaries(NOW, &all), m.Error.None)
	testing.expect_value(t, all[0].id, open.id)
	testing.expect(t, !all[0].closed)
}

@(private = "file")
closing_tells_the_voters :: proc(t: ^testing.T) {
	p, o := make_poll(t, true, false)
	sql.vote(p.id, {o[0]}, ANN, NOW)
	sql.vote(p.id, {o[1]}, BOB, NOW)
	r, err := sql.vote(p.id, {o[1]}, m.Actor{3, "cy"}, NOW + 600)
	testing.expect_value(t, err, m.Error.None)
	testing.expect_value(t, r, m.Vote_Result.Closed) // past its time, job or no job

	_, err = sql.close(p.id, BOB.id, NOW)
	testing.expect_value(t, err, m.Error.Not_Found) // only its maker

	due, derr := sql.close_due(NOW + 600)
	testing.expect_value(t, derr, m.Error.None)
	told := 0
	for d in due {
		if d.id == p.id { told = len(d.voters) }
	}
	testing.expect_value(t, told, 2)
	again, _ := sql.close_due(NOW + 600)
	testing.expect_value(t, len(again), 0)

	third, to := make_poll(t, false, false)
	sql.vote(third.id, {to[0]}, BOB, NOW)
	c, cerr := sql.close(third.id, ANN.id, NOW)
	testing.expect_value(t, cerr, m.Error.None)
	testing.expect_value(t, len(c.voters), 1)
	testing.expect_value(t, c.voters[0], BOB.id)
	r, _ = sql.vote(third.id, {to[1]}, BOB, NOW)
	testing.expect_value(t, r, m.Vote_Result.Closed)
}

// One test: the store is the process's, and tests run side by side.
@(test)
polls_store :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	testing.expect_value(t, db.open_db(":memory:", .Ephemeral, "storetest"), "")
	defer db.close()
	db.migrate("polls", sql.MIGRATIONS[:])
	context.allocator = context.temp_allocator
	a_named_vote_can_change(t)
	an_anonymous_vote_is_final_and_leaves_no_link(t)
	the_flag_stays(t)
	open_polls_come_first(t)
	closing_tells_the_voters(t)
}
