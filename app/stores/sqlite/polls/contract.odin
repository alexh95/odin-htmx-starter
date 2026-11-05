package polls_store_sqlite

import m "../../../features/polls/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Summaries : summaries
_ : m.Store_Poll : poll
_ : m.Store_Create : create
_ : m.Store_Vote : vote
_ : m.Store_Close : close
_ : m.Store_Close_Due : close_due
