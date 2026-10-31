# audit

The audit log (PLAN §17.7, D35). Writes go through `store:audit`, the one store any domain, web or identity package may
import: `audit_store.append(actor, action, target, reason, meta)` queues one entry and forgets it, for an entry with
no change of its own (a failed sign-in); one a full writer queue refuses is lost and counted (`store.Drops`, which
`/admin/ops` shows). A change's own entry goes in the change's transaction instead: accounts' SQLite ops write it with
`stores/sqlite/audit`'s `append_in`, so the two commit or fail together (M4-04). The SQLite family
keeps `audit_log`, append-only by its triggers (no update; a delete only of an entry older than 400 days); the memory
family writes one `mod=audit` logfmt line per entry and keeps nothing. An entry never carries a message body or a
password: the actor (id, name at the time, and the client id, never the address), a namespaced action
(`accounts.sign_in`), the target (`{"user", 7}`), the actor's reason (HX-Prompt) and a short detail. The client id is
an HMAC of the address under `ACCOUNTS_AUDIT_KEY`, so it can't be hashed back from an export or a backup without
the key; unset, the key is new each boot, and a client's entries group within one run only (M4-07).

| Route | Perm | What |
|---|---|---|
| `GET /admin/audit` | `Admin_Audit`, LAN only | the filter (actor, any case; action prefix) as a plain GET, and the first 50 entries, newest first |
| `GET /admin/audit/rows` | `Admin_Audit`, LAN only | the next 50 before `before` (keyset on the id): a full page ends with a row that asks for the next one when it scrolls into view (`intersect once`) |
| `GET /admin/audit/export` | `Admin_Audit`, LAN only | the filter's entries, up to 10,000, as `audit.csv` (an attachment, so hx-download saves it); a field a spreadsheet would read as a formula gets a leading `'` |

Mounted where the store is SQLite (`full`); on a memory build the page says the log is in the process's output.

What audits today: accounts' sign-ins (`accounts.sign_in`), wrong passwords for an existing account
(`accounts.sign_in_failed`, target the user) and a member's revoke of another session (`accounts.revoke`). Every admin
and moderator action joins as it lands (role changes and invites at slice 6).

## Data

`audit_log(id, at, actor_id, actor_name, action, target_kind, target_id, reason, client_id, meta)`, `INDEX(at)`; the
triggers `audit_log_no_update` and `audit_log_keeps_400_days` (`stores/sqlite/audit`, migration `0001_audit.sql`).
`features/audit/storetest` holds them.

Audited: d136601 2026-10-30 docs/audit/M4.md
