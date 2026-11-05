package polls

// ---- polls: Go/No-go (PLAN §15.1, D36, Q36) --------------------------------------------------------
//
// A named poll keeps who chose what, and a vote can change. An anonymous one keeps counters and who has
// voted, nothing in one copy of the file that joins them, and a vote is final: Alex's "Unlinked, votes final". So the chosen option
// stops at the store's counters: it's in no log, no audit row and no notice, and only the form body carries it.
// What a poll is doesn't change after creation, and neither does `anonymous`.

import "core:slice"
import "core:strings"
import "core:time"

import "../../platform/authz"
import m "models"
import polls_store "store:polls"

MAX_QUESTION :: 200 // runes
MAX_OPTION :: 100 // runes
MAX_OPTIONS :: 10
GO_NOGO := [?]string{"Go", "No-go"}

Closing :: struct {
	key, label: string,
	after:      time.Duration,
}

CLOSINGS := [?]Closing {
	{"10m", "In 10 minutes", 10 * time.Minute},
	{"1h", "In an hour", time.Hour},
	{"1d", "In a day", 24 * time.Hour},
	{"1w", "In a week", 7 * 24 * time.Hour},
}

@(private)
now :: proc() -> i64 { return time.to_unix_seconds(time.now()) }

closes_at :: proc(key: string) -> i64 {
	after := CLOSINGS[1].after
	for c in CLOSINGS {
		if c.key == key { after = c.after }
	}
	return now() + i64(after / time.Second)
}

// One a line, the blanks dropped. In the temp allocator.
split_options :: proc(text: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	s := text
	for line in strings.split_lines_iterator(&s) {
		if t := strings.trim_space(line); t != "" { append(&out, t) }
	}
	return out[:]
}

check :: proc(question: string, options: []string) -> string {
	if strings.trim_space(question) == "" { return "A poll needs a question." }
	if strings.rune_count(question) > MAX_QUESTION { return "A question is at most 200 characters." }
	if len(options) < 2 { return "A poll needs at least two options." }
	if len(options) > MAX_OPTIONS { return "A poll has at most 10 options." }
	for o in options {
		if strings.rune_count(o) > MAX_OPTION { return "An option is at most 100 characters." }
	}
	return ""
}

actor :: proc(v: authz.Viewer) -> m.Actor { return {v.id, v.name} }

summaries :: proc(out: ^[dynamic]m.Summary) -> m.Error { return polls_store.summaries(now(), out) }
poll :: proc(id: i64, v: authz.Viewer) -> (m.Poll, m.Error) { return polls_store.poll(id, v.id, now()) }

create :: proc(p: m.New_Poll, v: authz.Viewer) -> (i64, m.Error) {
	return polls_store.create(p, actor(v), now())
}

// A choice sent twice counts once: a repeat in the form would otherwise bump its counter twice.
vote :: proc(id: i64, options: []i64, v: authz.Viewer) -> (m.Vote_Result, m.Error) {
	slice.sort(options)
	return polls_store.vote(id, slice.unique(options), actor(v), now())
}

close :: proc(id: i64, v: authz.Viewer) -> (m.Closed, m.Error) { return polls_store.close(id, v.id, now()) }
close_due :: proc() -> ([]m.Closed, m.Error) { return polls_store.close_due(now()) }
