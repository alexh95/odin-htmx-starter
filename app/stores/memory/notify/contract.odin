package notify_store_memory

import m "../../../features/notify/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_List : list
_ : m.Store_Unread : unread
_ : m.Store_Add : add
_ : m.Store_Mark_Read : mark_read
_ : m.Store_Prune : prune
_ : m.Store_Add_Now : add_now
_ : m.Store_Mute : mute
_ : m.Store_Muted : muted
_ : m.Store_Mutes : mutes
_ : m.Store_Retract : retract
