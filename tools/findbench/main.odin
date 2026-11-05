package main

// ---- findbench: FTS5 at 100k messages, through the real query (PLAN §11.8, M8's gate) -----------------
//
//   odin run tools/findbench -collection:store=app/stores/memory -collection:identity=app/platform/authz/anonymous
//     -collection:client=app/platform/client/vanilla -collection:theme=app/platform/theme/lite -o:speed
//
// A file database in WAL, 100k messages of Zipf-distributed words over 40 rooms, half of them private, for
// a member of three. Times the bare MATCH, the store's own search with its membership rows and snippet()
// (a word that's rare, one in half the messages, short prefixes, two words), snippet() alone, and bm25 over every
// hit. Prints p50, p95 and worst in ms, for docs/perf/FIND-BUDGETS.md.

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

import "../../app/platform/guard"
import "../../app/platform/obs"
import "../../app/platform/store"
import db "../../app/platform/store/sqlite"
import m "../../app/features/chat/models"
import sql "../../app/stores/sqlite/chat"

MESSAGES :: 100_000
ROOMS :: 40
VOCABULARY :: 5000
RUNS :: 200

word :: proc(r: int) -> string { return fmt.tprintf("w%d", r) }

// Zipf by the inverse of the cumulative harmonic, close enough for a word list: `w1` is in about half the messages.
zipf :: proc() -> int {
	u := rand.float64()
	return int(math.exp(u * math.ln(f64(VOCABULARY))))
}

fill :: proc() {
	Fill :: proc() -> bool {
		room := db.writer_stmt("INSERT INTO chat_rooms(slug, name, kind, owner, at) VALUES(?, ?, ?, 1, 0)")
		for i in 0 ..< ROOMS {
			db.bind_text(room, 1, fmt.tprintf("r%d", i))
			db.bind_text(room, 2, fmt.tprintf("Room %d", i))
			db.bind_int(room, 3, 1 if i % 2 == 1 else 0)
			if db.step_done(room) != .None { return false }
			db.reset(room)
		}
		who := db.writer_stmt("INSERT INTO chat_members(room, who, name, at) VALUES(?, 7, 'ann', 0)")
		for i in ([]int{2, 4, 6}) {
			db.bind_id(who, 1, i64(i))
			if db.step_done(who) != .None { return false }
			db.reset(who)
		}
		msg := db.writer_stmt("INSERT INTO chat_messages(room, author, name, body, at, ver) VALUES(?, 1, 'x', ?, 0, 1)")
		b := strings.builder_make(context.temp_allocator)
		for i in 0 ..< MESSAGES {
			strings.builder_reset(&b)
			for _ in 0 ..< 12 {
				strings.write_string(&b, word(zipf()))
				strings.write_byte(&b, ' ')
			}
			db.bind_id(msg, 1, i64(i % ROOMS + 1))
			db.bind_text(msg, 2, strings.to_string(b))
			if db.step_done(msg) != .None { return false }
			db.reset(msg)
			if i % 1000 == 0 { free_all(context.temp_allocator) }
		}
		return true
	}
	if !db.write_now(Fill) { fmt.panicf("the fill failed") }
}

Timed :: struct {
	name: string,
	ms:   [RUNS]f64,
}

report :: proc(t: ^Timed) {
	slice.sort(t.ms[:])
	fmt.printfln("%-44s p50 %8.3f  p95 %8.3f  worst %8.3f", t.name, t.ms[RUNS / 2], t.ms[RUNS * 95 / 100], t.ms[RUNS - 1])
}

raw :: proc(name, sql_text, match: string) {
	t := Timed{name = name}
	n := 0
	for i in 0 ..< RUNS {
		start := time.tick_now()
		q := db.read(sql_text)
		db.bind_text(q, 1, match)
		err: store.Error
		n = 0
		for db.next_row(q, &err) { n += 1 }
		db.reset(q)
		t.ms[i] = time.duration_milliseconds(time.tick_since(start))
	}
	report(&t)
	fmt.printfln("    %d rows", n)
}

searched :: proc(name: string, words: ..string) {
	t := Timed{name = name}
	n := 0
	for i in 0 ..< RUNS {
		hits := make([dynamic]m.Hit, context.temp_allocator)
		start := time.tick_now()
		_ = sql.search(7, words, 1, 10, &hits)
		t.ms[i] = time.duration_milliseconds(time.tick_since(start))
		n = len(hits)
		free_all(context.temp_allocator)
	}
	report(&t)
	fmt.printfln("    %d hits", n)
}

main :: proc() {
	obs.init(.Fatal)
	guard.install(proc(_: ^guard.Crash) {})
	path := "findbench.db"
	defer {
		os.remove(path)
		os.remove("findbench.db-wal")
		os.remove("findbench.db-shm")
	}
	if problem := db.open_db(path, .File, "findbench"); problem != "" { fmt.panicf("%s", problem) }
	defer db.close()
	db.migrate("chat", sql.MIGRATIONS[:])
	start := time.tick_now()
	fill()
	fmt.printfln("%d messages in %v", MESSAGES, time.tick_since(start))

	size :: proc(name: string) {
		q := db.read("SELECT sum(length(block)) FROM chat_fts_data")
		err: store.Error
		if db.next_row(q, &err) { fmt.printfln("%s: the index holds %d KB", name, db.column_id(q, 0) / 1024) }
		db.reset(q)
	}
	size("as tested")
	BARE :: "SELECT rowid FROM chat_fts WHERE chat_fts MATCH ? ORDER BY rowid DESC LIMIT 50"
	RANKED :: "SELECT rowid FROM chat_fts WHERE chat_fts MATCH ? ORDER BY bm25(chat_fts) LIMIT 50"
	searched("search, a three-byte prefix", "w12")
	searched("search, a two-byte prefix", "w1")
	raw("MATCH, rare word", BARE, `"w4000"`)
	raw("MATCH, common word", BARE, `"w1"`)
	raw("MATCH, a prefix hitting most", BARE, `"w"*`)
	raw("MATCH, two words", BARE, `"w1" "w2"`)
	searched("search, rare word (room rows + snippet)", "w4000")
	searched("search, common word", "w1")
	searched("search, a prefix hitting most", "w")
	searched("search, two words", "w1", "w2")
	searched("search, word only private rooms hold", "w4999")
	raw("bm25 over every hit, common word", RANKED, `"w1"`)
	raw("bm25 over every hit, prefix", RANKED, `"w"*`)
	raw("snippet alone, 10 hits", "SELECT snippet(chat_fts, 0, char(57344), char(57345), '…', 32) FROM chat_fts WHERE chat_fts MATCH ? ORDER BY rowid DESC LIMIT 10", `"w1"`)
}
