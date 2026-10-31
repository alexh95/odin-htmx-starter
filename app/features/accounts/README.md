# accounts

Who is asking (PLAN §17.1, D35). Two identities live here: `nick` (M2, ANSWERS round 9) and `accounts` (M4: usernames,
passwords and server-side sessions; TOTP, step-up, recovery and invites follow in M4's later slices). The feature has
no web package: a profile reaches it through its identity, whose routes it mounts as `{"accounts", identity.ROUTES[:]}`,
and the generator gives the domain's SQLite need to the identity that reaches it, so `nick` still builds on memory.

## identity_envadmin

`features/accounts/identity_envadmin` (package `accounts_identity_envadmin`), for profiles with no SQLite (D18): one
admin, whose password is `ACCOUNTS_ADMIN_HASH`, signs in at `/login` with the password alone and keeps a stateless
cookie, `admin=<issued>.<expires>.<mac>` (HMAC-SHA256 with `ACCOUNTS_ENVADMIN_KEY`, at least 32 bytes; without one a
key made at boot, so a restart signs the admin out; `ACCOUNTS_ENVADMIN_LIFE`, 7 days). There is no session to
revoke: `/logout` forgets the cookie in that browser, and a new key signs everyone out. The issue time counts as the
last password check, and `/step-up` takes the password and issues a fresh cookie. Sign-ins are limited (5 per 15 min
per client, 40 overall) and audited through `store:audit`. No hosted profile builds it: the nightly generates an
`--identity envadmin` project and runs the e2e suite on it (`envadmin.spec`).

## identity_accounts

`features/accounts/identity_accounts` (package `accounts_identity_accounts`), `full`'s identity, on SQLite. Over the
domain (`features/accounts`, package `accounts`) and its views:

| Route | Perm | What |
|---|---|---|
| `GET /login` | public | the form; signed in, "Signed in as …" with sign-out |
| `POST /login` | public | `username`, `password`, `next`: the verify on `platform/password`'s pool, then the session's write, one deferred response; 303 (or `HX-Redirect`) to `next` with the cookie; 422 wrong, 429 limited or backed off, 503 busy |
| `POST /logout` | public | closes this session, clears the cookie |
| `GET /accounts/sessions` | `Account_Self` | the member's sessions, newest first, this device marked |
| `POST /accounts/sessions/revoke` | `Account_Self` | `session` (its hash): one of the member's own (the store refuses another's); this one is signing out |
| `POST /login/code` | public | the sign-in's second step: `pending` (signed, five minutes), `code` from the app or a recovery code, spent in the session's own write |
| `GET`, `POST /step-up` | `Account_Self` | the password, or a code: `step_up_at` is now; back to `next` (a write's page, from `HX-Current-URL`) |
| `GET`, `POST /accounts/totp` | `Account_Self`; the POST a step-up | two-step sign-in: the key (base32 and `otpauth://` text) and on by a code, only while it is off (a factor in force is replaced by turning it off first, M4-01); the answer is ten recovery codes, shown once |
| `POST /accounts/totp/codes`, `/accounts/totp/off` | `Account_Self`, step-up | new recovery codes (the old ones gone); off |
| `GET`, `POST /register` | public | per `ACCOUNTS_REGISTRATION` (`invite`, the default; `open`; `closed`): username, name to show, password twice, the invite code (`/register?code=…`); one write creates the member, spends the invite (its role) and signs them in |
| `GET`, `POST /reset` | public | username, an admin's one-time reset code, a new password twice; every session of the account ends |
| `GET`, `POST /accounts/profile` | `Account_Self` | the name to show (`clean_name`) |
| `POST /accounts/theme` | `Account_Self` | `style`, `scheme` (one of the style's own): the picker's, kept in `accounts_prefs` and rendered on every device; 204 |
| `GET /admin/accounts` | `Admin_Accounts`, LAN only | members (role, status, two-step), live invites |
| `POST /admin/accounts/<id>/role`, `/disable`, `/enable`, `/reset`, `/two-step-off` | `Admin_Accounts`, LAN only, step-up | with an `HX-Prompt` reason, audited; a role change or a disable ends the member's sessions; the last enabled admin stays; a reset code is shown once; two-step off drops a lost authenticator and its recovery codes |
| `POST /admin/accounts/invites`, `/invites/delete` | `Admin_Accounts`, LAN only, step-up | an invite (role, 1-50 uses, 1-30 days), its link shown once; withdrawn |

- **The cookie**: `sid=<32 random bytes, base64url>; Path=/; Max-Age=<the absolute life>; HttpOnly; SameSite=Lax`,
  no `Domain` (host-only), `Secure` per `COOKIE_SECURE` (`auto`: when the request came as https through a trusted
  proxy; `1`; `0` warns at every boot and the sign-in form says so). A `Secure` cookie is named `__Host-sid`, which a
  browser takes only from this host, so a sibling host under the same site can't plant a session of its own (M4-08);
  a plain `sid` on such a request is no one's. The store keeps only the token's hex SHA-256.
- **Lifetimes**: 14 days idle (`ACCOUNTS_SESSION_IDLE`), 30 days absolute (`ACCOUNTS_SESSION_MAX`). `last_seen` is
  written at most once a minute. A cookie whose session has ended is cleared on its next request.
- **Rotation**: every sign-in makes a new token and closes the session the request carried, in the same transaction
  as the new row, the user's swept dead sessions and the clearing of their failures. A sign-in counts as a step-up.
  Rotation on a privilege change arrives with role changes (slice 6).
- **Limits** (§17.5): 5 sign-ins per 15 min per client (`ACCOUNTS_LOGIN_PER_CLIENT`), 40 from everyone
  (`ACCOUNTS_LOGIN_OVERALL`), right or wrong. Per account, the first three wrong passwords are free, then the
  account waits 1 s, doubling to 5 min: never a lockout. A backed-off account answers 429 without a verify, which
  tells a guesser that the name exists after three misses; the timing of a first miss doesn't (unknown names are
  verified against the dummy).
- **Two-step sign-in** (`platform/totp`, RFC 6238): an account with it gets a code form after its password. A code is
  taken once (`totp_last_step`), a recovery code once (`used_at`), each in the write that opens the session. An Admin
  without it loads as a Member (`ACCOUNTS_ADMIN_TOTP=required`, the default; `optional` for the suites). Step-up asks
  for a check within `ACCOUNTS_STEP_UP_WINDOW` (10 min); a sign-in counts as one.
- **Members**: usernames are 3-32 of letters, digits, `_`, `-` and `.`; display names pass `clean_name` (no control,
  invisible or direction-changing characters, 40 at most). 3 registrations and 10 invite or reset codes an hour per
  client (`ACCOUNTS_REGISTER_PER_HOUR`, `ACCOUNTS_CODES_PER_HOUR`). New passwords are hashed on the pool
  (`password.submit_hash`).
- **Revocation** (X19): a role change or a disable in `/admin/accounts` ends the member's sessions and calls
  `hub.revoke`, which kicks their member topics (`accounts.user`, declared here as `TOPICS`); their pages go to
  `/login`.
- **Argon**: `ACCOUNTS_ARGON_THREADS` workers (0, the default: 1 with two cores or fewer, else 2), each holding
  19 MiB, declared to `--limits` as the pool's memory; a queue of 32, past it 503.
- **The first admin**: `ACCOUNTS_ADMIN_HASH` (a PHC string from `bin --hash-password`, which reads the password from
  stdin and prints the derive time on stderr) and `ACCOUNTS_ADMIN_NAME` (`admin`) make an Admin at boot while no
  enabled one exists. A hash that isn't one of `platform/password`'s refuses to boot; no admin and no hash warns.

Sign-ins (`accounts.sign_in`), wrong passwords for an existing account (`accounts.sign_in_failed`) and a revoke of
another session (`accounts.revoke`) go to the audit log through `store:audit`; that import makes `audit` the identity's
own dependency (the generator brings it with `--identity accounts`), not `nick`'s.

The e2e suite (`e2e/helpers/accounts.ts`) and the load driver boot their servers with one test hash and lift the
limits; the specs that test the limits, the backoff and the lifetimes start servers of their own.

A name with no account backs off as an account does (in memory, a fixed table), so the backoff's 429 doesn't tell
which names exist; `/reset` checks the code before hashing, by the same read whether or not the name exists (M4-05).

## Data (M4)

`accounts_models` holds the types and the store contract; the store is SQLite's alone
(`app/stores/sqlite/accounts`, migration `0001_accounts.sql`):

| Table | What it holds |
|---|---|
| `users` | `username` (unique, case-insensitive), `display`, `pw_hash` (a PHC string from `platform/password`), `role`, `disabled_at`, `totp_secret`, `failed_logins`, `backoff_until`, `created_at` |
| `sessions` | by `token_hash` (hex SHA-256 of the cookie's token): `user_id`, `created_at`, `last_seen`, `expires_at`, `step_up_at`, `client_id` |
| `accounts_invites` | by `code_hash`: `role`, `max_uses`, `uses`, `created_by`, `created_at`, `expires_at` |
| `accounts_recovery_codes` | `user_id`, `code_hash`, `used_at` |
| `accounts_prefs` | `user_id`, `key`, `value`: theme, chat transport, mutes |

Passwords are `platform/password`'s (argon2id on its own pool), shared with `envadmin`.

## identity_nick

`features/accounts/identity_nick` (package `accounts_identity_nick`) is a member of the `identity:` family, chosen by a
profile's `build.*` row (`id=features/accounts/identity_nick`; `streams`). A visitor picks a nickname at `/login` and
keeps it as a signed cookie, `nick=<id>.<name>.<expiry>.<mac>` (HMAC-SHA256, `HttpOnly; SameSite=Lax; Path=/`,
`Secure` over https, 30 days, renewed past half): no account, no password, and a random 53-bit id, so two people may
share a name. What it is worth is decided on each request, from the client's address:

| Client | Role |
|---|---|
| in `ACCOUNTS_NICK_ADMIN_CIDRS` (none by default) | Admin: `/admin/ops` opens |
| in `LAN_CIDRS` (`ACCOUNTS_NICK_FROM=lan`, the default; `all` drops the check) | Member: chat, the bot's members' limits |
| anyone else | Guest, with no `Chat_Read`: chat shows "chat is open on the LAN" |

`ACCOUNTS_NICK_KEY` (or `ACCOUNTS_NICK_KEY_FILE`, at least 32 bytes) signs the cookies; with none, a key is made at
boot and nicknames last until a restart (a warn line says so). `app.boot` calls the identity's `init`. The e2e suite
and the load driver run their servers with `LAN_CIDRS=127.0.0.0/8`, since their browsers and k6 are loopback; e2e
also fixes the key, so a nickname outlives the restarts its specs make.

## Prefixes

| Prefix | Why |
|---|---|
| `/login` | front sends a Guest who lacks a route's perm here (§17.2): the identity's own page, whichever identity runs |
| `/logout` | its pair |
| `/step-up` | front sends a stale session on a `.Step_Up` row here (§17.2), as it sends a Guest to `/login` |
| `/register` | where an invite link lands (`/register?code=…`), so the link is short and says what it is |
| `/reset` | where a member takes an admin's reset code; signed out, they have no `/accounts` page to reach |

Audited: 30988ae 2026-10-30 docs/audit/M4.md (the fixes of M4-01 to M4-04 read in its re-read); cd72870's fixes of M4-17 to M4-19 are audit debt
