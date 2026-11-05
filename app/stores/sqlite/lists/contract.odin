package lists_store_sqlite

import m "../../../features/lists/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Summaries : summaries
_ : m.Store_List : list
_ : m.Store_Column : column
_ : m.Store_Create : create
_ : m.Store_Add : add
_ : m.Store_Move : move
_ : m.Store_Toggle : toggle
_ : m.Store_Remove : remove
_ : m.Store_Assign : assign
_ : m.Store_Search : search
