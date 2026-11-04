package chat_store_sqlite

import m "../../../features/chat/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Init : init
_ : m.Store_Rooms : rooms
_ : m.Store_Rooms_For : rooms_for
_ : m.Store_Room : room
_ : m.Store_Create_Room : create_room
_ : m.Store_Dm : dm
_ : m.Store_Members : members
_ : m.Store_Is_Member : is_member
_ : m.Store_Join : join
_ : m.Store_Leave : leave
_ : m.Store_Sweep : sweep
_ : m.Store_Search : search
_ : m.Store_Set_Audit_Writer : set_audit_writer
_ : m.Store_Set_Room : set_room
_ : m.Store_Ban : ban
_ : m.Store_Banned : banned
_ : m.Store_Report : report
_ : m.Store_Reports : reports
_ : m.Store_Report_Of : report_of
_ : m.Store_Resolve : resolve
_ : m.Store_Add_Invite : add_invite
_ : m.Store_Invite : invite
_ : m.Store_Invites : invites
_ : m.Store_Revoke_Invite : revoke_invite
_ : m.Store_Use_Invite : use_invite
_ : m.Store_Recent : recent
_ : m.Store_After : after
_ : m.Store_Count_After : count_after
_ : m.Store_Changed : changed
_ : m.Store_Message : message
_ : m.Store_Post : post
_ : m.Store_Change : change
_ : m.Store_Seed : seed
_ : m.Store_Open_Reports : open_reports
_ : m.Store_Removed : removed
_ : m.Store_Room_Of : room_of
_ : m.Store_Rooms_Owned : rooms_owned
_ : m.Store_Blob_Held : blob_held
_ : m.Store_Purge_Blob : purge_blob
_ : m.Store_Block : block
_ : m.Store_Unblock : unblock
_ : m.Store_Blocking : blocking
_ : m.Store_Blocks : blocks
