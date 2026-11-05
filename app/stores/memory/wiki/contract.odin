package wiki_store_memory

import m "../../../features/wiki/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Page : page
_ : m.Store_List : list
_ : m.Store_Seed_Manual : seed_manual
