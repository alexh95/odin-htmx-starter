package notify_store_sqlite

import m "../../../features/notify/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_List : list
_ : m.Store_Unread : unread
_ : m.Store_Add : add
_ : m.Store_Mark_Read : mark_read
_ : m.Store_Prune : prune
