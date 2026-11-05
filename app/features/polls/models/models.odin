package polls_models

// ---- polls: the types and the store contract ---------------------------------------------------

import "../../../platform/store"

Error :: store.Error

Option :: struct {
	id:    i64,
	label: string,
	n:     int,
	names: []string, // a named poll's; an anonymous poll has none to give
}

Poll :: struct {
	id:        i64,
	question:  string,
	multiple:  bool,
	anonymous: bool,
	closed:    bool,
	by:        u64,
	by_name:   string,
	voters:    int,
	options:   []Option,
	voted:     bool,
	mine:      []i64, // the viewer's own choices, on a named poll only
}

Summary :: struct {
	id:        i64,
	question:  string,
	voters:    int,
	anonymous: bool,
	closed:    bool,
}

Actor :: struct {
	id:   u64,
	name: string,
}

New_Poll :: struct {
	question:            string,
	options:             []string,
	multiple, anonymous: bool,
	closes_at:           i64,
}

Vote_Result :: enum {
	Recorded,
	Already, // an anonymous poll: a vote is final
	Closed,
}

// A poll that has just closed, and who to tell.
Closed :: struct {
	id:       i64,
	question: string,
	voters:   []u64,
}

// `now` is unix seconds: a poll past its closing time is closed whether or not the job has run.
Store_Summaries :: proc(now: i64, out: ^[dynamic]Summary) -> Error
// Strings in the temp allocator. `me` is who's asking, for `voted` and `mine`.
Store_Poll :: proc(id: i64, me: u64, now: i64) -> (Poll, Error)
Store_Create :: proc(p: New_Poll, by: Actor, now: i64) -> (id: i64, err: Error)

// These run off the loop, each its own transaction. .Not_Found: no such poll, an option not on it, or more
// than one option on a single-choice poll. `options` holds no repeats.
Store_Vote :: proc(poll: i64, options: []i64, by: Actor, now: i64) -> (Vote_Result, Error)
// The poll's maker only: anyone else's, or one already closed, is .Not_Found.
Store_Close :: proc(poll: i64, by: u64, now: i64) -> (Closed, Error)
// Marks what's past its time closed, a batch at a time.
Store_Close_Due :: proc(now: i64) -> ([]Closed, Error)
