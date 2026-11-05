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
}

// The page, or .Not_Found. Strings in the temp allocator.
Store_Page :: proc(slug: string) -> (Page, Error)
// Every page, in title order, with no bodies; `members`: theirs too.
Store_List :: proc(members: bool, out: ^[dynamic]Page) -> Error
// The Manual as this binary has it: what it no longer has goes.
Store_Seed_Manual :: proc(pages: []Page) -> Error
