package find_models

// ---- find: a row of a profile's FIND_SOURCES (PLAN §6, D6) --------------------------------------

import "../../../platform/authz"
import "../../../platform/store"

// A domain's search. Off the loop: its strings go in the temp allocator.
Search :: proc(v: authz.Viewer, q: string, limit: int, out: ^[dynamic]store.Search_Hit) -> store.Error

Source :: struct {
	name:    string,               // the group's heading
	perm:    authz.Perm,           // no perm, no search: a guest's chat is never asked
	engine:  store.Search_Engine,  // boot refuses a list that mixes them (§11.8)
	search:  Search,
	preload: bool,                 // a hit is a public-ish GET worth fetching early
}
