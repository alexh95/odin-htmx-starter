package uploads_models

// ---- uploads: the types and the store contract ------------------------------------------
//
// Below the domain and both stores (PLAN §14.2, §17.6, X13). An upload is a session: its bytes
// grow in a part file, its row says how far they got, and a finished one becomes a blob, named
// by its content's sha256. The rows here, the bytes on disk (uploads.odin).

import "../../../platform/store"

Error :: store.Error

Upload_State :: enum u8 {
	Open,
	Done,
	Gone, // given up or refused: its part file is deleted
}

Upload :: struct {
	id:       i64,
	user:     u64,
	size:     int, // what it said it would be
	received: int,
	state:    Upload_State,
	at:       i64, // unix seconds
}

Blob :: struct {
	sha256: string, // 64 hex digits
	mime:   string,
	bytes:  int,
	width:  int,
	height: int,
	user:   u64, // who uploaded it first
	at:     i64,
}

Store_Init :: proc()
Store_Create :: proc(user: u64, size: int, at: i64) -> (id: i64, err: Error)
Store_Upload :: proc(id: i64) -> (Upload, Error)
Store_Advance :: proc(id: i64, received: int) -> Error
Store_Close :: proc(id: i64, state: Upload_State) -> Error
Store_Open_Count :: proc(user: u64, since: i64) -> int // their open uploads made at or after `since`
Store_Stale :: proc(before: i64, out: ^[dynamic]i64) -> Error // open uploads made before `before`
Store_Add_Blob :: proc(b: Blob) -> Error // .None when the content is here already
Store_Blob :: proc(sha256: string) -> (Blob, Error)
Store_Blobs :: proc(before: i64, out: ^[dynamic]string) -> Error // the addresses of those made before `before`
Store_Drop_Blob :: proc(sha256: string, before: i64) -> (dropped: bool, err: Error) // only if made before `before`
// What `user` has started since `since`, and what all the blobs hold.
Store_Bytes_Held :: proc(user: u64, since: i64) -> (member, all: int)
