package uploads_store_memory

import m "../../../features/uploads/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Init : init
_ : m.Store_Create : create
_ : m.Store_Upload : upload
_ : m.Store_Advance : advance
_ : m.Store_Close : close
_ : m.Store_Open_Count : open_count
_ : m.Store_Stale : stale
_ : m.Store_Add_Blob : add_blob
_ : m.Store_Blob : blob
