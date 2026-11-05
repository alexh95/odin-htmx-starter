package wiki_models

// ---- wiki: the types and the store contract -------------------------------------------------

import "../../../platform/store"

Error :: store.Error

Visibility :: enum {
	Public,
	Members,
}

Page :: struct {
	slug:       string,
	title:      string,
	visibility: Visibility,
	manual:     bool,   // the starter's own docs: from the binary, read-only
	md:         string, // what was written
	html:       string, // rendered when written, so a view never parses (§6, 13 §2.1)
	plain:      string, // what search reads
	rev:        i64,
	at:         i64,
	by:         string,
}

Revision :: struct {
	rev:   i64,
	title: string,
	at:    i64,
	by:    string,
	md:    string, // the text this revision had
}

// A save. No base_rev: a new page.
Save :: struct {
	slug, title:      string,
	md, html, plain:  string,
	visibility:       Visibility,
	base_rev:         i64,
	by:               string,
}

// The index shows this many; search finds the rest.
INDEX_LIMIT :: 500

// The page, or .Not_Found. Strings in the temp allocator.
Store_Page :: proc(slug: string) -> (Page, Error)
// The pages, in title order, up to INDEX_LIMIT, with no bodies; `members`: theirs too.
Store_List :: proc(members: bool, out: ^[dynamic]Page) -> Error
// The Manual as this binary has it: what it no longer has goes.
Store_Seed_Manual :: proc(pages: []Page) -> Error
// By relevance. `members`: their pages too.
Store_Search :: proc(words: []string, members: bool, limit: int, out: ^[dynamic]store.Search_Hit) -> Error
// Off the loop. `current`: the page as it is now, the one saved, or the newer one when `conflict`.
// .Constraint: a new page's slug is taken, the page is the Manual's, or `full`, past the store's cap.
Store_Save :: proc(input: Save) -> (current: Page, conflict, full: bool, err: Error)
// Newest first, with no text.
Store_History :: proc(slug: string, out: ^[dynamic]Revision) -> Error
Store_Revision :: proc(slug: string, rev: i64) -> (Revision, Error)
