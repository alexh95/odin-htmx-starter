package chat_store_sqlite

import m "../../../features/chat/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Init : init
_ : m.Store_Rooms : rooms
_ : m.Store_Room : room
_ : m.Store_Create_Room : create_room
_ : m.Store_Recent : recent
_ : m.Store_After : after
_ : m.Store_Count_After : count_after
_ : m.Store_Changed : changed
_ : m.Store_Message : message
_ : m.Store_Post : post
_ : m.Store_Change : change
_ : m.Store_Seed : seed
