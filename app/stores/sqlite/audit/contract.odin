package audit_store_sqlite

import m "../../../features/audit/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Append : append
_ : m.Store_List : list
_ : m.Store_Dropped : dropped
