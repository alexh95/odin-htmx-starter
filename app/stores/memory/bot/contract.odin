package bot_store_memory

import m "../../../features/bot/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Conversations : conversations
_ : m.Store_Conversation : conversation
_ : m.Store_Turns : turns
_ : m.Store_Usage : usage
_ : m.Store_Start : start
_ : m.Store_Append : append_turn
