package accounts_store_sqlite

import m "../../../features/accounts/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_User_By_Name : user_by_name
_ : m.Store_Set_Audit_Writer : set_audit_writer
_ : m.Store_Has_Audit_Writer : has_audit_writer
_ : m.Store_Totp_Secrets : totp_secrets
_ : m.Store_Reseal_Totps : reseal_totps
_ : m.Store_User_By_Id : user_by_id
_ : m.Store_Session : session
_ : m.Store_Sessions_Of : sessions_of
_ : m.Store_Count_Admins : count_admins
_ : m.Store_Bootstrap_Admin : bootstrap_admin
_ : m.Store_Create_User : create_user
_ : m.Store_Login_Failed : login_failed
_ : m.Store_Open_Session : open_session
_ : m.Store_Touch_Session : touch_session
_ : m.Store_Close_Session : close_session
_ : m.Store_Set_Totp : set_totp
_ : m.Store_Step_Up : step_up
_ : m.Store_Recovery_Left : recovery_left
_ : m.Store_Users : users
_ : m.Store_Invites : invites
_ : m.Store_Invite : invite
_ : m.Store_Register : register
_ : m.Store_Set_Role : set_role
_ : m.Store_Set_Disabled : set_disabled
_ : m.Store_Create_Invite : create_invite
_ : m.Store_Delete_Invite : delete_invite
_ : m.Store_Issue_Reset : issue_reset
_ : m.Store_Reset_Live : reset_live
_ : m.Store_Redeem_Reset : redeem_reset
_ : m.Store_Set_Display : set_display
_ : m.Store_Theme_Of : theme_of
_ : m.Store_Set_Theme : set_theme
