package chat_views

// ---- chat: the views (PLAN §14.1, §9.1) ----------------------------------------------------
//
// A room is a live log, <div role="log" id="log-<room>"> of <article id="m-<id>">, in the
// page's first markup. Every message travels as one fragment whatever the transport,
// `<hx-partial hx-target="#log-<room>" hx-swap="upsert sort">`: upsert replaces an article
// it already has (an edit, a tombstone, a replay's duplicate) and sorts a new one in by
// its id, so a reconnect, a resync and the author's own reply never double a message.
// A message is rendered once for every reader; what differs per viewer is asked for
// (the menu) or marked by AutoScroll against the log's data-me. Only the body is
// ignored by htmx and hyperscript, so the message's own controls keep working.

import "core:fmt"
import "core:strings"
import "core:time"

import "../../../platform/html"
import chat ".."
import m "../models"

w :: html.w
esc :: html.esc

Room_Row :: struct {
	room:   m.Room,
	unread: int, // -1: never read
}

// What a room page shows its viewer beyond the log: a private room's and a DM's members, and
// what they may do there.
Room_View :: struct {
	members:      []m.Member, // a private room's or a DM's; empty for the rest
	invites:      []m.Invite, // a private room's open invites, for whoever may hand them out
	cannot_post:  string, // why the viewer may not post; "": they may
	may_invite:   bool,
	may_leave:    bool,
	may_moderate: bool, // the room's lock and slow mode
	may_attach:   bool, // the composer's image
	peer:         Dm_Peer, // a DM's other member
	may_remove:   bool, // the owner of a private room: its members' Remove
	removed:      []m.Ban, // who they've kept out
	mute_button:  string, // notify's: this room in the viewer's Inbox, markup of its own
}

Dm_Peer :: struct {
	id:      u64,
	blocked: bool, // by the viewer
}

// What a message's menu offers its viewer.
Menu :: struct {
	may_change:   bool, // their own, in the edit window
	may_dm:       bool, // a DM with its author
	may_moderate: bool, // remove it
	may_discipline: bool, // mute or kick its author: the bot has none to mute
	may_report:   bool, // someone else's
	may_block:    bool, // its author
	blocked:      bool, // ... already
}

Report_Row :: struct {
	report: m.Report,
	room:   m.Room, // zero when the room is gone
}

// A room's name as its lists and its page say it: `#name`, or a DM's two names.
@(private)
room_title :: proc(b: ^strings.Builder, r: m.Room) {
	if r.kind != .Dm { w(b, `<span class="chat-hash">#</span>`) }
	esc(b, r.name)
	switch r.kind {
	case .Public:
	case .Private:
		w(b, ` <span class="badge chat-kind">private</span>`)
	case .Announce:
		w(b, ` <span class="badge chat-kind">announcements</span>`)
	case .Dm:
		w(b, ` <span class="badge chat-kind">direct</span>`)
	}
}

// What a transport adds to a room page (chat_web's switch asks the chosen one): the
// attributes of the pane that holds the log, of the composer's form, and of the form
// that holds the page's version (#ver-<room>), which a socket sends as it opens.
Wiring :: struct {
	pane:     string,
	composer: string,
	version:  string,
}

// ---- the rooms ---------------------------------------------------------------------------

// `reports`: how many wait for a moderator; -1 for anyone else.
index_page :: proc(rows: []Room_Row, setting: string, may_create, may_announce: bool, reports: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Comms", "Chat", "Rooms on the LAN." if chat.PERSISTED else "Rooms on the LAN. They are kept in memory, so a restart empties them.")
	w(&b, `<section class="block chat-index">`)
	search_form(&b, "")
	if reports >= 0 { fmt.sbprintf(&b, `<p class="chat-reports-link"><a href="/chat/reports">Reports</a> <span class="badge">%d</span></p>`, reports) }
	w(&b, `<ul class="chat-rooms">`)
	for r in rows {
		w(&b, `<li><a class="chat-room-link" href="/chat/r/`)
		esc(&b, r.room.slug)
		w(&b, `">`)
		room_title(&b, r.room)
		w(&b, `</a> <span class="badge chat-unread unread-`)
		esc(&b, r.room.slug)
		w(&b, `">`)
		if r.unread > 0 { strings.write_int(&b, r.unread) }
		w(&b, `</span></li>`)
	}
	w(&b, `</ul>`)
	if may_create {
		w(&b, `<form class="chat-new" hx-post="/chat/rooms" hx-status:422="target:#room-error swap:innerHTML"><label for="room-name">New room</label><div class="chat-new-row"><input id="room-name" name="name" maxlength="40" required placeholder="Name"><select id="room-kind" name="kind" aria-label="Who reads it"><option value="public">Public</option><option value="private">Private: by invite</option>`)
		if may_announce { w(&b, `<option value="announce">Announcements</option>`) }
		w(&b, `</select><button class="btn btn-primary" type="submit">Create</button></div><p class="field-msg form-error" id="room-error"></p></form>`)
	}
	connection(&b, setting)
	w(&b, `<p class="chat-blocks-link"><a href="/chat/blocks">Blocked members</a></p></section>`)
	return strings.to_string(b)
}

@(private)
search_form :: proc(b: ^strings.Builder, q: string) {
	w(b, `<form class="chat-search" method="get" action="/chat/search" role="search"><input id="chat-q" name="q" type="search" maxlength="200" aria-label="Search the rooms" placeholder="Search the rooms" value="`)
	esc(b, q)
	w(b, `"><button class="btn btn-outline" type="submit">Search</button></form>`)
}

// What a search found, newest first, each a link to its message.
search_page :: proc(q: string, hits: []m.Hit) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Comms", "Search", "The rooms you can read.")
	w(&b, `<section class="block">`)
	search_form(&b, q)
	if q != "" && len(hits) == 0 { w(&b, `<p class="muted chat-search-none">Nothing found.</p>`) }
	w(&b, `<ul class="chat-hits">`)
	for hit in hits {
		w(&b, `<li class="chat-hit"><a href="/chat/r/`)
		esc(&b, hit.room.slug)
		fmt.sbprintf(&b, `#m-%d">`, hit.msg.id)
		room_title(&b, hit.room)
		w(&b, `</a> <b class="chat-name">`)
		esc(&b, hit.msg.name)
		w(&b, `</b><div class="chat-body" hx-ignore data-disable-scripting>`)
		esc(&b, hit.msg.body)
		w(&b, `</div></li>`)
	}
	w(&b, `</ul></section>`)
	return strings.to_string(b)
}

// The "Connection" setting (§14.1): a compatibility mode for networks whose proxies
// kill WebSockets. A plain form, so it works with no script at all.
connection :: proc(b: ^strings.Builder, setting: string) {
	option :: proc(b: ^strings.Builder, name, label, setting: string) {
		w(b, `<option value="`)
		w(b, name)
		w(b, `"`)
		if name == setting { w(b, ` selected`) }
		w(b, `>`)
		w(b, label)
		w(b, `</option>`)
	}
	w(b, `<form class="chat-conn" method="post" action="/chat/transport"><label for="transport">Connection</label><select id="transport" name="transport">`)
	option(b, chat.AUTO, "Auto", setting)
	for row in chat.TRANSPORTS { option(b, row.name, row.label, setting) }
	w(b, `</select><button class="btn btn-outline" type="submit">Use</button></form>`)
}

// What a Guest sees at /chat: chat is the LAN's (ANSWERS round 9; §14.1).
lan_notice_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Comms", "Chat", "Chat is open on the LAN.")
	w(&b, `<section class="block"><article class="card chat-lan"><p>Chat is for the people on this network. On it? <a href="/login?next=/chat">Pick a nickname</a> and the rooms open.</p></article></section>`)
	return strings.to_string(b)
}

// ---- a room ------------------------------------------------------------------------------

// The composer of the three transports that post over HTTP (sse, poll, multipart):
// the message comes back in the response, and to everyone else on the room's
// stream; hx-pending shows it at once, a 422 goes to the form's error slot and a
// 429 to the toasts.
post_composer :: proc(r: m.Room) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, ` hx-post="/chat/r/`)
	esc(&b, r.slug)
	fmt.sbprintf(&b, `" hx-target="#log-%d" hx-swap="beforeend" hx-pending="#chat-pending" hx-status:422="target:#err-%d swap:innerHTML" hx-status:403="target:#err-%d swap:innerHTML" hx-status:429="target:#toasts swap:beforeend"`, r.id, r.id, r.id)
	return strings.to_string(b)
}

room_page :: proc(r: m.Room, msgs: []m.Message, ver: i64, here: []chat.Presence_Change, me: u64, t: chat.Transport, wiring: Wiring, rv: Room_View) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<section class="chat-room" data-room="`)
	esc(&b, r.slug)
	w(&b, `"><header class="chat-head"><h1>`)
	room_title(&b, r)
	w(&b, `</h1>`)
	if !chat.PERSISTED { w(&b, `<span class="badge" title="Kept in memory: a restart empties it">ephemeral</span>`) }
	w(&b, `<span class="chat-via muted">`)
	w(&b, chat.TRANSPORTS[t].label)
	w(&b, `</span><a class="chat-back" href="/chat">All rooms</a></header>`)
	if rv.may_moderate { room_controls(&b, r) }
	w(&b, `<div class="chat-main">`)

	fmt.sbprintf(&b, `<div class="chat-pane" id="pane-%d"%s>`, r.id, wiring.pane)
	// The marker (§14.1): what the log starts with is all the room still has, and it let older go.
	if r.dropped > 0 && len(msgs) < chat.SNAPSHOT {
		cap, days := chat.keeps(r.kind)
		fmt.sbprintf(&b, `<p class="chat-marker muted">Older messages were removed (this room keeps the last %d messages or %d days).</p>`, cap, days)
	}
	fmt.sbprintf(&b, `<div id="log-%d" class="chat-log" role="log" aria-label="Messages" data-me="%d"`, r.id, me)
	html.behave(&b, .Auto_Scroll)
	w(&b, `>`)
	for msg, i in msgs { message(&b, msg, r.slug, i == len(msgs) - 1) }
	fmt.sbprintf(&b, `</div><div id="typing-%d" class="chat-typing" aria-live="polite" data-me="%d"`, r.id, me)
	html.behave(&b, .Auto_Scroll) // marks the reader's own "is typing", which CSS hides
	w(&b, `></div>`)
	fmt.sbprintf(&b, `<form class="chat-ver" hidden%s>`, wiring.version)
	version(&b, r.id, ver)
	w(&b, `</form>`)

	if rv.cannot_post == "" {
		fmt.sbprintf(&b, `<form class="chat-composer" id="say-%d"%s`, r.id, wiring.composer)
		html.behave(&b, .Composer)
		fmt.sbprintf(&b, `><textarea id="body-%d" name="body" rows="1" maxlength="%d" required aria-label="Message" placeholder="Message #`, r.id, chat.MAX_BODY)
		esc(&b, r.slug)
		w(&b, `" hx-post="/chat/r/`)
		esc(&b, r.slug)
		fmt.sbprintf(&b, `/typing" hx-trigger="input changed throttle:2s" hx-swap="none"></textarea>`)
		if rv.may_attach { attach(&b, r.id) }
		fmt.sbprintf(&b, `<button class="btn btn-primary" type="submit">Send</button><p class="field-msg form-error" id="err-%d"></p></form></div>`, r.id)
	} else {
		w(&b, `<p class="chat-readonly muted">`)
		esc(&b, rv.cannot_post)
		w(&b, `</p></div>`)
	}

	fmt.sbprintf(&b, `<aside class="chat-side"><h2>Here</h2><div id="who-%d" class="chat-who">`, r.id)
	for p in here { who(&b, p) }
	w(&b, `</div>`)
	if r.kind == .Private || r.kind == .Dm { members(&b, r, rv) }
	w(&b, rv.mute_button)
	if r.kind == .Dm { dm_block(&b, r, rv.peer) }
	// What hx-pending shows while a post is on its way; the typed text arrives as data-body.
	w(&b, `</aside></div><template id="chat-pending"><article class="chat-msg pending"><p class="chat-body muted">Sending…</p></article></template></section>`)
	return strings.to_string(b)
}

// A DM's Block or Unblock: it can't be left, so this is how one ends.
@(private)
dm_block :: proc(b: ^strings.Builder, r: m.Room, peer: Dm_Peer) {
	if peer.id == 0 { return }
	if peer.blocked {
		fmt.sbprintf(b, `<button class="btn btn-outline" type="button" hx-post="/chat/unblock/%d" hx-swap="none">Unblock</button>`, peer.id)
		return
	}
	w(b, `<button class="btn btn-outline" type="button" hx-post="/chat/r/`)
	esc(b, r.slug)
	w(b, `/block" hx-swap="none">Block</button>`)
}

// The members a viewer has blocked, each with its Unblock.
blocks_page :: proc(list: []m.Block) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Comms", "Blocked members", "A member you've blocked can't message you or reach your Inbox, and you can't message them. Public rooms stay as they are.")
	w(&b, `<section class="block"><ul class="chat-blocks">`)
	if len(list) == 0 { w(&b, `<li class="muted">You haven't blocked anyone.</li>`) }
	for row in list {
		w(&b, `<li><b>`)
		esc(&b, row.name)
		fmt.sbprintf(&b, `</b> <button class="btn btn-outline" type="button" hx-post="/chat/unblock/%d" hx-swap="none">Unblock</button></li>`, row.other)
	}
	w(&b, `</ul><p><a href="/chat">All rooms</a></p></section>`)
	return strings.to_string(b)
}

// The composer's image: uploads' shim fills the hidden field, which is all the form sends.
@(private)
attach :: proc(b: ^strings.Builder, room: i64) {
	fmt.sbprintf(b, `<input type="hidden" name="attachment" id="att-%d" value=""><label class="btn btn-outline chat-attach">Image<input type="file" accept="image/png,image/jpeg" data-upload="#att-%d" data-status="#att-say-%d"></label><span class="chat-attach-say muted" id="att-say-%d" role="status"></span>`, room, room, room, room)
}

// A moderator's controls for a room: its lock and its slow mode, each asking why (the audit log's).
@(private)
room_controls :: proc(b: ^strings.Builder, r: m.Room) {
	w(b, `<div class="chat-mod"><form hx-post="/chat/r/`)
	esc(b, r.slug)
	fmt.sbprintf(b, `/lock" hx-prompt="Why %s the room?" hx-swap="none"><input type="hidden" name="locked" value="%s"><button class="btn btn-outline" type="submit">%s</button></form>`,
		"unlock" if r.locked else "lock", "0" if r.locked else "1", "Unlock" if r.locked else "Lock")
	w(b, `<form hx-post="/chat/r/`)
	esc(b, r.slug)
	w(b, `/slow" hx-prompt="Why change slow mode?" hx-swap="none"><select name="seconds" aria-label="Slow mode">`)
	for s in ([]int{0, 10, 30, 60, 300}) {
		fmt.sbprintf(b, `<option value="%d"%s>%s</option>`, s, " selected" if s == r.slow else "", "Slow mode off" if s == 0 else fmt.tprintf("One message every %d s", s))
	}
	w(b, `</select><button class="btn btn-outline" type="submit">Set</button></form></div>`)
}

// A private room's or a DM's members, with the invite link and Leave where the viewer has them.
@(private)
members :: proc(b: ^strings.Builder, r: m.Room, rv: Room_View) {
	fmt.sbprintf(b, `<h2>Members</h2><ul class="chat-members" id="members-%d">`, r.id)
	for mem in rv.members {
		fmt.sbprintf(b, `<li data-member="%d">`, mem.who)
		esc(b, mem.name)
		if mem.who == r.owner && r.kind == .Private { w(b, ` <small class="muted">owner</small>`) }
		if rv.may_remove && mem.who != r.owner { member_button(b, r, mem.who, "remove", "Remove") }
		w(b, `</li>`)
	}
	w(b, `</ul>`)
	if len(rv.removed) > 0 {
		w(b, `<h3>Removed</h3><ul class="chat-removed">`)
		for row in rv.removed {
			w(b, `<li>`)
			esc(b, row.name)
			member_button(b, r, row.who, "allow", "Allow back")
			w(b, `</li>`)
		}
		w(b, `</ul>`)
	}
	if rv.may_invite {
		for once in ([]bool{false, true}) {
			w(b, `<form class="chat-invite-new" hx-post="/chat/r/`)
			esc(b, r.slug)
			fmt.sbprintf(b, `/invite" hx-target="#invites-%d"><input type="hidden" name="once" value="%s"><button class="btn btn-outline" type="submit">%s</button></form>`,
				r.id, "1" if once else "0", "One-use link" if once else "Invite link")
		}
		fmt.sbprintf(b, `<div class="chat-invites" id="invites-%d">`, r.id)
		invites_list(b, r, rv.invites, "")
		w(b, `</div>`)
	}
	if rv.may_leave {
		w(b, `<form class="chat-leave" hx-post="/chat/r/`)
		esc(b, r.slug)
		w(b, `/leave"><button class="btn btn-ghost" type="submit">Leave the room</button></form>`)
	}
}

@(private)
member_button :: proc(b: ^strings.Builder, r: m.Room, who: u64, action, label: string) {
	w(b, ` <button class="btn btn-ghost" type="button" hx-post="/chat/r/`)
	esc(b, r.slug)
	fmt.sbprintf(b, `/%s/%d" hx-swap="none">%s</button>`, action, who, label)
}

// A private room's open invites, and a new one's link (`token`), shown this once: the store keeps
// only its hash. The answer to making one (POST /chat/r/<slug>/invite) and to revoking one.
invites :: proc(r: m.Room, list: []m.Invite, token: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	invites_list(&b, r, list, token)
	return strings.to_string(b)
}

@(private)
invites_list :: proc(b: ^strings.Builder, r: m.Room, list: []m.Invite, token: string) {
	if token != "" {
		w(b, `<p class="muted">Anyone on the LAN with this link can join until it expires or is revoked. It is shown once:</p><a class="chat-invite-link" href="/chat/join/`)
		w(b, token) // the server's own text: digits, '.', and base64url
		w(b, `">/chat/join/`)
		w(b, token)
		w(b, `</a>`)
	}
	if len(list) == 0 { return }
	w(b, `<ul class="chat-invite-list">`)
	for inv in list {
		fmt.sbprintf(b, `<li id="inv-%d">`, inv.id)
		esc(b, inv.by_name)
		w(b, `'s link, `)
		if inv.max_uses > 0 {
			fmt.sbprintf(b, `used %d of %d`, inv.uses, inv.max_uses)
		} else {
			fmt.sbprintf(b, `used %d`, inv.uses)
		}
		w(b, `, until <time datetime="`)
		w(b, iso(inv.expires))
		w(b, `">`)
		w(b, iso(inv.expires)[:10])
		w(b, `</time> <button class="btn btn-ghost" type="button" hx-post="/chat/r/`)
		esc(b, r.slug)
		fmt.sbprintf(b, `/invites/%d/revoke" hx-target="#invites-%d">Revoke</button></li>`, inv.id, r.id)
	}
	w(b, `</ul>`)
}

// GET /chat/join/<token>: the room it names, and a plain form to join it, so the link works with
// no script at all.
join_page :: proc(r: m.Room, token: string, already: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Comms", "Join a room", "You were invited to a private room.")
	w(&b, `<section class="block"><article class="card chat-join"><h2>`)
	room_title(&b, r)
	w(&b, `</h2>`)
	if already {
		w(&b, `<p>You are in this room already.</p><a class="btn btn-primary" href="/chat/r/`)
		esc(&b, r.slug)
		w(&b, `">Open it</a>`)
	} else {
		w(&b, `<form method="post" action="/chat/join/`)
		w(&b, token)
		w(&b, `"><button class="btn btn-primary" type="submit">Join the room</button></form>`)
	}
	w(&b, `</article></section>`)
	return strings.to_string(b)
}

// One message. The newest a reader has carries the read receipt: a POST when it
// scrolls into view, never a GET a preload could fire (§14.1).
message :: proc(b: ^strings.Builder, msg: m.Message, slug: string, newest: bool) {
	fmt.sbprintf(b, `<article id="m-%d" class="chat-msg%s" data-author="%d"`, msg.id, " gone" if msg.gone else "", msg.author)
	if newest {
		w(b, ` hx-post="/chat/r/`)
		esc(b, slug)
		fmt.sbprintf(b, `/read?upto=%d" hx-trigger="intersect once" hx-swap="none"`, msg.id)
	}
	w(b, `><header>`)
	html.avatar(b, i64(msg.author % (1 << 53)), msg.name)
	w(b, `<b class="chat-name">`)
	esc(b, msg.name)
	w(b, `</b> `)
	// A mark no name can fake: names are free, and letters that look like the bot's aren't refused.
	if msg.author == 0 { w(b, `<span class="badge chat-bot">bot</span> `) }
	w(b, `<time datetime="`)
	w(b, iso(msg.at))
	w(b, `">`)
	esc(b, html.time_ago(msg.at))
	w(b, `</time>`)
	if msg.edited != 0 && !msg.gone { w(b, ` <small class="muted">(edited)</small>`) }
	if !msg.gone {
		fmt.sbprintf(b, `<button class="chat-more" type="button" aria-label="Message actions" hx-get="/chat/m/%d/menu" hx-target="#mm-%d">⋯</button>`, msg.id, msg.id)
	}
	w(b, `</header>`)
	if msg.gone {
		w(b, `<p class="chat-body muted">Message deleted.</p>`)
	} else {
		if msg.body != "" {
			w(b, `<div class="chat-body" hx-ignore data-disable-scripting>`)
			esc(b, msg.body)
			w(b, `</div>`)
		}
		if msg.blob != "" {
			image(b, msg)
		} else if msg.body == "" {
			w(b, `<p class="chat-body muted">Image removed.</p>`) // a moderator's, and it was all there was
		}
	}
	// The menu's slot: a click outside the message, or Escape, empties it. hx-preserve keeps the
	// slot, and the menu or edit form open in it, when the message is rendered again (its echo,
	// a poll, an edit from another tab), which had wiped a half-typed edit; a tombstone's isn't
	// kept, so a deleted message drops its menu.
	fmt.sbprintf(b, `<div class="chat-menu" id="mm-%d"%s`, msg.id, "" if msg.gone else " hx-preserve")
	html.behave(b, .Dismiss)
	w(b, `></div></article>`)
}

// Its address is hex the store checked on the way in; esc all the same, it's a column.
@(private)
image :: proc(b: ^strings.Builder, msg: m.Message) {
	w(b, `<a class="chat-img" href="/uploads/blob/`)
	esc(b, msg.blob)
	w(b, `"><img src="/uploads/blob/`)
	esc(b, msg.blob)
	w(b, `" loading="lazy" alt="An image from `)
	esc(b, msg.name)
	w(b, `"></a>`)
}

// Messages as one fragment for the room's log (every transport sends this), and the
// newest version among them for the page's #ver-<room>.
partial :: proc(b: ^strings.Builder, room: i64, slug: string, msgs: []m.Message, newest_last := true, swap := "upsert sort") {
	if len(msgs) == 0 { return }
	fmt.sbprintf(b, `<hx-partial hx-target="#log-%d" hx-swap="%s">`, room, swap)
	ver: i64
	for msg, i in msgs {
		message(b, msg, slug, newest_last && i == len(msgs) - 1)
		ver = max(ver, msg.ver)
	}
	fmt.sbprintf(b, `</hx-partial><hx-partial hx-target="#ver-%d" hx-swap="outerHTML">`, room)
	version(b, room, ver)
	w(b, `</hx-partial>`)
}

// The room's version the page has seen, which a reconnect sends back (a socket's first
// frame, SSE's resync): with it the server tells a gap the room let go, where the page's
// log is replaced, from a restart, where it keeps what it had (M2-31, M2-35, D37).
version :: proc(b: ^strings.Builder, room, ver: i64) {
	fmt.sbprintf(b, `<input type="hidden" id="ver-%d" name="ver" value="%d">`, room, ver)
}

// A snapshot within `budget` bytes, as a stream writes it at once: the newest messages that
// fit, oldest dropped first. 50 long messages ran past a stream's queue cap, and every
// reconnect to the room was closed the same way (M2-03). One that dropped any, or that the
// caller knows has a gap before it (`whole`), replaces the log instead of upserting into it,
// which kept what the page had with a silent gap before these (M2-26, M2-31).
snapshot :: proc(room: i64, slug: string, msgs: []m.Message, budget: int, whole := false) -> (html: string, newest: i64) {
	if len(msgs) == 0 { return "", 0 }
	from := 0
	for {
		b := strings.builder_make(context.temp_allocator)
		partial(&b, room, slug, msgs[from:], swap = "innerHTML" if whole || from > 0 else "upsert sort")
		if strings.builder_len(b) <= budget || from == len(msgs) - 1 { return strings.to_string(b), msgs[len(msgs) - 1].id }
		from += max(1, (len(msgs) - from) / 4)
	}
}

one :: proc(room: i64, slug: string, msg: m.Message) -> string {
	b := strings.builder_make(context.temp_allocator)
	partial(&b, room, slug, {msg})
	return strings.to_string(b)
}

// ---- a message's menu and its edit form ----------------------------------------------------
//
// Asked for when wanted (GET /chat/m/<id>/menu), so it is rendered for its viewer.

menu :: proc(msg: m.Message, slug: string, acts: Menu) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="chat-actions"><a href="/chat/r/`)
	esc(&b, slug)
	fmt.sbprintf(&b, `#m-%d">Link</a>`, msg.id)
	may_change := acts.may_change
	if acts.may_dm {
		fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-post="/chat/dm/%d">Message `, msg.author)
		esc(&b, msg.name)
		w(&b, `</button>`)
	}
	if may_change {
		fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-get="/chat/m/%d/edit" hx-target="#mm-%d">Edit</button>`, msg.id, msg.id)
		fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-post="/chat/m/%d/delete" hx-target="#mm-%d">Delete</button>`, msg.id, msg.id)
	}
	if acts.may_report {
		fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-post="/chat/m/%d/report" hx-prompt="What is wrong with this message?" hx-swap="none">Report</button>`, msg.id)
	}
	if acts.may_block {
		if acts.blocked {
			fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-post="/chat/unblock/%d" hx-swap="none">Unblock</button>`, msg.author)
		} else {
			fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-post="/chat/m/%d/block" hx-swap="none">Block</button>`, msg.id)
		}
	}
	if acts.may_moderate {
		fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-post="/chat/m/%d/remove" hx-prompt="Why remove it?" hx-target="#mm-%d">Remove</button>`, msg.id, msg.id)
	}
	if acts.may_discipline {
		for kind in ([]string{"mute", "kick"}) {
			w(&b, `<form hx-post="/chat/r/`)
			esc(&b, slug)
			fmt.sbprintf(&b, `/%s/%d" hx-prompt="Why %s `, kind, msg.author, kind)
			esc(&b, msg.name)
			fmt.sbprintf(&b, `?" hx-swap="none"><input type="hidden" name="minutes" value="60"><button class="btn btn-ghost" type="submit">%s for an hour</button></form>`, "Mute" if kind == "mute" else "Kick")
		}
	}
	w(&b, `</div>`)
	return strings.to_string(b)
}

// The open reports, oldest first, each with its copy of the message (a moderator reads a private
// room's or a DM's message here only), and Remove or Dismiss, each asking why.
reports_page :: proc(rows: []Report_Row) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Comms", "Reports", "Reported messages. Removing one deletes it from its room; either way the report closes.")
	w(&b, `<section class="block"><ul class="chat-report-list">`)
	if len(rows) == 0 { w(&b, `<li class="muted">Nothing is reported.</li>`) }
	if len(rows) == chat.REPORTS_SHOWN { fmt.sbprintf(&b, `<li class="muted">The oldest %d: more wait behind them.</li>`, len(rows)) }
	for row in rows {
		rep := row.report
		fmt.sbprintf(&b, `<li class="card chat-report" id="report-%d"><p><b>`, rep.id)
		esc(&b, rep.author_name)
		w(&b, `</b> in `)
		if row.room.id != 0 { room_title(&b, row.room) } else { w(&b, `a room that is gone`) }
		w(&b, `</p><blockquote class="chat-report-body">`)
		esc(&b, rep.body)
		w(&b, `</blockquote>`)
		if rep.blob != "" {
			w(&b, `<a class="chat-img" href="/uploads/blob/`)
			esc(&b, rep.blob)
			w(&b, `"><img src="/uploads/blob/`)
			esc(&b, rep.blob)
			w(&b, `" loading="lazy" alt="The reported image"></a>`)
		}
		w(&b, `<p class="muted">Reported by `)
		esc(&b, rep.by_name)
		w(&b, `: `)
		esc(&b, rep.reason)
		w(&b, `</p>`)
		for act in ([]string{"remove", "dismiss"}) {
			fmt.sbprintf(&b, `<button class="btn %s" type="button" hx-post="/chat/reports/%d/%s" hx-prompt="Why %s it?" hx-swap="none">%s</button> `,
				"btn-primary" if act == "remove" else "btn-outline", rep.id, act, act, "Remove the message" if act == "remove" else "Dismiss")
		}
		w(&b, `</li>`)
	}
	w(&b, `</ul></section>`)
	return strings.to_string(b)
}

// The edit form, filled with `body` (what was typed, after a refusal) and its reason. A saved
// edit answers only the message, whose re-render keeps the slot, so the answer's empty main
// swap (swapEmpty) is what closes the form.
edit_form :: proc(id: i64, body, problem: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `<form class="chat-edit" hx-post="/chat/m/%d/edit" hx-target="#mm-%d" hx-swap="innerHTML swapEmpty:true"><textarea id="edit-%d" name="body" rows="2" maxlength="%d" required aria-label="Edit the message">`, id, id, id, chat.MAX_BODY)
	esc(&b, body)
	w(&b, `</textarea><button class="btn btn-primary" type="submit">Save</button>`)
	if problem != "" {
		w(&b, `<p class="field-msg form-error">`)
		esc(&b, problem)
		w(&b, `</p>`)
	}
	w(&b, `</form>`)
	return strings.to_string(b)
}

// ---- presence, typing and unread counts -------------------------------------------------------

who :: proc(b: ^strings.Builder, p: chat.Presence_Change) {
	fmt.sbprintf(b, `<span id="p-%d-%d" class="who who-%s">`, p.room, p.who, "away" if p.state == .Away else "online")
	esc(b, p.name)
	w(b, `</span>`)
}

// A presence change for chat.presence:<room>: upserted into the list, or deleted.
presence :: proc(p: chat.Presence_Change) -> string {
	b := strings.builder_make(context.temp_allocator)
	if p.state == .Gone {
		fmt.sbprintf(&b, `<span hx-swap-oob="delete:#p-%d-%d"></span>`, p.room, p.who)
	} else {
		fmt.sbprintf(&b, `<hx-partial hx-target="#who-%d" hx-swap="upsert sort">`, p.room)
		who(&b, p)
		w(&b, `</hx-partial>`)
	}
	return strings.to_string(b)
}

// "<name> is typing": a re-upsert replaces it, which restarts its CSS fade; Expire
// removes it on the hyperscript client.
typing :: proc(room: i64, id: u64, name: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `<hx-partial hx-target="#typing-%d" hx-swap="upsert"><span id="t-%d-%d" class="typing-who" data-author="%d"`, room, room, id, id)
	html.behave(&b, .Expire)
	w(&b, `>`)
	esc(&b, name)
	w(&b, ` is typing…</span></hx-partial>`)
	return strings.to_string(b)
}

// A member's unread count for a room, into every `.unread-<slug>` of theirs.
unread :: proc(slug: string, n: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<span hx-swap-oob="innerHTML:.unread-`)
	esc(&b, slug)
	w(&b, `">`)
	if n > 0 { strings.write_int(&b, n) }
	w(&b, `</span>`)
	return strings.to_string(b)
}

// A mention, for the member's Inbox.
mention_line :: proc(by, room, body: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<b>`)
	esc(&b, by)
	w(&b, `</b> mentioned you in <b>#`)
	esc(&b, room)
	w(&b, `</b>: `)
	excerpt(&b, body)
	return strings.to_string(b)
}

// A direct message, for the other member's Inbox.
dm_line :: proc(by, body: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<b>`)
	esc(&b, by)
	w(&b, `</b> wrote to you: `)
	excerpt(&b, body if body != "" else "an image")
	return strings.to_string(b)
}

// The first 80 runes, escaped.
@(private)
excerpt :: proc(b: ^strings.Builder, body: string) {
	n := 0
	for _, i in body {
		if n == 80 {
			esc(b, body[:i])
			w(b, `…`)
			return
		}
		n += 1
	}
	esc(b, body)
}

@(private)
iso :: proc(at: i64) -> string {
	s, _ := time.time_to_rfc3339(time.unix(at, 0), 0, false, context.temp_allocator)
	return s
}
