# CLAUDE.md

Guidance for working in this repo. Read it before changing anything; it captures decisions
and gotchas that aren't obvious from the source and that are expensive to rediscover.

## What this is

A **starter** for server-rendered web apps: an **Odin** backend rendering HTML, **HTMX** on the
front end, a SQLite or in-memory store, in one binary. A site is a **profile** (`app/cmd/<p>/`): a
selection of **features** (`app/features/<f>/`) composed on a shared **platform**
(`app/platform/`). Five profiles ship: `skeleton`, the 1.2.x contacts console rebuilt from features
at its exact URLs (the worked example and the performance witness), `minimal`, the one-page
notes starter, `lab`, the starter's own page (the catalog and the init-command builder at `/`) and the stream
contract pages (SSE, WebSocket and multipart), `streams`, the
stream substrate's witness (chat on four transports, the Inbox, the `nick` identity), and `full`,
Houston (accounts with passwords and server-side sessions on SQLite; growing through M4). CI also
builds `full-vanilla`: `full`'s own files on the vanilla client (`src=full` in `build.sh`, no directory of its
own), so the two clients run the same specs and can't drift apart.
**Read [`PHILOSOPHY.md`](PHILOSOPHY.md) first**, then [`docs/PLAN.md`](docs/PLAN.md) (the plan:
layers, features, milestones) and [`docs/design/DECISIONS.md`](docs/design/DECISIONS.md);
[`docs/DATA.md`](docs/DATA.md) covers backups.

```
odin-htmx-starter/
  app/          the platform, features, stores and profiles: app/README.md is the tour
  e2e/          Playwright specs per feature (e2e/README.md)
  load-tests/   k6 scenarios per feature and the parity gate (load-tests/README.md)
  tools/        check, bundle, drills, baseline, init, og, streamload, profile
  tests/        parity-waivers.txt
  docs/         PLAN.md, design/, spikes/, perf/, audit/
  build.sh build.bat   the one place a profile's build flags live
  CLAUDE.md TODO.md CHANGELOG.md   <- you are here
```

## Standing policy (do this every session)

1. **Keep `CHANGELOG.md` current.** Every change that touches behaviour, structure, or build
   goes under `## [Unreleased]` (Keep a Changelog format: Added / Changed / Fixed / Removed).
   No silent changes.
2. **Keep `TODO.md` current.** Pick items from it; check off what you finish; add follow-ups
   you discover. It is the source of truth for what's left.
3. **Keep e2e and load-tests in sync.** Every user-facing feature or endpoint is represented in
   *both* suites — e2e asserts its behaviour, load-tests measures its cost. Adding `/foo` means a
   spec in `e2e/tests/<f>/` *and* a scenario in `load-tests/scenarios/<f>/` in the same change;
   `tools/check parity` fails a route either suite never reached (or needs a waiver with a reason
   in `tests/parity-waivers.txt`).
4. **Update docs you invalidate.** If you change the API, layout, or a convention here, fix
   `CLAUDE.md`, `app/README.md`, and `docs/PLAN.md` (and `docs/design/DECISIONS.md` for a design
   change) in the same pass.
5. **Commit with Conventional Commits** (see below). One logical change per commit.

## Commits — Conventional Commits

Every commit follows the [Conventional Commits](https://www.conventionalcommits.org) spec:

```
type(scope): imperative subject
```

- **Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
- **Scope** (encouraged): the area touched — a platform package (`web`, `store`, `guard`, `obs`…),
  a feature (`contacts`, `notes`…), a profile (`skeleton`, `minimal`), or `css`, `js`, `e2e`,
  `load`, `check`, `drills`, `ci`, `infra`, `deps`, `docs`.
- **Subject**: imperative mood, lower-case, no trailing period, ≤ ~72 chars.
- **Breaking changes**: `type(scope)!: …` and/or a `BREAKING CHANGE:` footer.
- Body explains *why* when it isn't obvious; wrap ~72.
- AI-authored commits end with `Co-Authored-By: Claude <…>`.

**Changelog mapping**: `feat`→Added, `fix`→Fixed, `refactor`/`perf`/`style`→Changed, removals
→Removed. Keep `CHANGELOG.md` `[Unreleased]` in step with the commits as you go.

Commits are GPG-signed (configured in git). If signing isn't available in an automated
environment, an explicit `--no-gpg-sign` on that one commit is acceptable.

## Build / run / verify

From the repo root:

```sh
app/prepare.sh              # once: htmx, SQLite, each profile's bundled assets  (app\prepare.bat)
./build.sh skeleton         # build app/bin/skeleton; -o:speed etc. pass through (build.bat)
CMD=check ./build.sh minimal    # odin check on the profile's families; CMD=test runs its tests
app/run.sh                  # build and serve skeleton on :8080 (PROFILE=minimal for minimal)
odin run tools/check -- all # imports, profile, routes, contracts, topics, exts, locks (parity after both suites ran)
sh .github/scripts/unit-tests.sh   # every package with tests, leaks fatal
node tools/drills/drills.mjs skeleton   # crash, shutdown, restart, fd and budget drills
sh tools/profile/profile.sh skeleton pages   # Linux: perf samples and top functions (--spall: every call)
```

A clean build is **zero warnings**: `build.sh` passes `-vet -strict-style -warnings-as-errors` and the further vet
flags (`-vet-cast -vet-semicolon -vet-tabs -vet-using-param -disallow-do`; PLAN §19.2.4). A
profile is built only through `build.sh`/`build.bat`, never `odin build` by hand: each needs its four
family collections (`store:`, `identity:`, `client:`, `theme:`) and its asset directory. The two
scripts hold the same table; change both together. `prepare` writes each profile's bundled assets
to `app/build/<p>/`, so after editing CSS or JS run `prepare` again, then build.

The binary reads its configuration from the environment; `bin --limits` prints every row with its
default and meaning, `--features --json` what the build mounts, `--routes --json` its routes. The
common ones:

| Variable | Default | What it does |
|---|---|---|
| `PORT` | first argument, else `8080` | listen port |
| `BIND_ALL` | unset (loopback) | any value listens on `0.0.0.0`: containers only |
| `THREADS` | one per core | event loops |
| `SITE_URL` | the brand's `site_url` | canonical origin: tags, sitemap, the fly.dev redirect |
| `LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error`; `warn` silences the access log |
| `DB_PATH` | `:memory:` | SQLite profiles: the file to persist to |
| `SEED` | unset | `1` seeds the demo rows into an empty file DB (`:memory:` always is) |
| `MEMMODE` | `ephemeral` | how `:memory:` is served (PLAN §11.3) |
| `METRICS_TOKEN_FILE` | unset | a file with the bearer `/metrics` accepts |
| `CRASH_FILE` | `last-crash.txt` | where a dirty crash or a watchdog exit writes its reason |

The build version is `-define:VERSION=…` (`VERSION=` for `build.sh`; default `dev`), sent as
`x-version`.

Verify with curl for contracts and a browser (pointed at `127.0.0.1`: the server binds IPv4 loopback
only, and `localhost` can stall on `::1`) for anything HTMX swaps or animates.

## Dependencies — the line we hold

The shipped app's runtime dependencies are deliberately few: **HTMX** and the extensions a profile
loads (front end), **odin-http** (backend HTTP, our fork, a stand-in for the core module Odin is
expected to grow), optionally **SQLite** (the store — bound as the amalgamation and *statically
linked in*, the most-deployed database on earth, not a framework or a server), and optionally
**_hyperscript** (the `client:` family's hyperscript member, core only). Each is pinned and
vendored/compiled into the one binary, and counted in `PHILOSOPHY.md`'s ledger. That's it.

- No NPM, no bundler, no build system beyond `odin` through `build.sh` (+ `prepare` compiling
  SQLite and bundling each profile's assets with `tools/bundle`, itself Odin).
- No CSS/JS frameworks. CSS is hand-written; JS is vanilla and tiny, or a behaviour named by
  `html.behave`.
- No template engine — HTML is generated by Odin procedures.
- **Every** static asset (htmx, `app.css`, `app.js`, `_hyperscript` and `behaviours._hs` where the
  client is hyperscript, `favicon.svg`, `og.png`) is **embedded into
  the binary** (`#load` in `platform/web/assets.odin`, with its `.br` and `.gz`) and served from
  memory — the binary is fully self-contained, nothing is read from disk at runtime. Editing CSS/JS
  needs `prepare` and a rebuild.
- Before reaching for a library, ask whether ~30 lines of Odin or CSS does it. They usually
  do. New runtime dependencies in `app/` need a real justification.
- Test tooling is exempt: `e2e/` and `load-tests/` may use external tools (Playwright, k6)
  because they're dev-time and never shipped. Prefer single-binary tools. The product itself
  stays JS-free; `e2e/` uses npm (it runs in Playwright's Docker image on CI, which ships
  node/npm, so there's nothing extra to install).

## Architecture — layers, features, families

The layering is PLAN §5.1, enforced by `tools/check imports`. An arrow means "may import":

```
app/cmd/<p>/      brand.odin main.odin routes.odin routes_test.odin  ->  everything
  f_web           features/f/web/     -> f, f_models, f_views, f's impls, other features' domains,
                                         notify_web, store:audit, platform L1-L3
  f_views         features/f/views/   -> f_models, f, platform/html
  f               features/f/         -> f_models, store:f, store:audit, other domains, platform L1-L2
  f_store_<fam>   stores/<fam>/f/     -> f_models, platform/store*, platform/sqlite, platform/workers
                                         (the memory audit store also platform/obs: its log is the process's)
  f_models        features/f/models/  -> core, platform L1-L2

platform  L4 app        -> identity:., store:. (the family's NAME), L1-L3; only cmd/* imports it
          L3 web stream hub html client/* theme/*   (html -> client:., theme:.)
          L2 store store/sqlite store/memory env authz authz/anonymous obs guard workers markdown password totp
          L1 sys sqlite ext escape signed fuzz jpeg
```

- **A feature reaches another only through its domain** (dashboard -> contacts). No web package
  imports another web package; no feature imports `platform/app` or odin-http.
- **Only the domain imports its store** (`store:<f>`, resolved by the family collection), and a store
  never imports its domain: the shared types and the store contract's proc types live in `f_models`,
  and each store states them in its `contract.odin` (`_ : m.Store_X : x`), so a drifted signature
  fails in the store itself (`tools/check contracts` holds every store to it).
- **Only `platform/web` imports odin-http**; it re-exports `web.Request` and `web.Response`.
- **A family is a build-time choice** made by `build.sh`'s collection flags: `store:` (sqlite or
  memory), `identity:` (anonymous, `features/accounts/identity_nick`: `streams`,
  `features/accounts/identity_accounts`: `full`, which needs SQLite, or `identity_envadmin`, one admin from the
  environment, which no hosted profile builds), `client:`
  (vanilla or hyperscript; `lab` is on hyperscript), `theme:` (full or lite). The
  members expose the same names (`NAME`, the stores' procs), so the code above them doesn't change.
- **A profile is four hand-written files.** `routes.odin` mounts tables, one line each, as
  `app.Mount{"<feature>", <pkg>.ROUTES[:]}` (the root row is written there, never inside a
  package's table); `main.odin` is the boot sequence as plain calls (`app.boot`, each feature's
  `init` and `store_sqlite.init`, `app.check`, `store_sqlite.open` and one `migrate` per store, `app.serve`, `app.wait`,
  `app.shutdown`, `store_sqlite.close`, `app.exit`); `brand.odin` holds the names, the nav and the
  pages' copy; `routes_test.odin` runs the boot checks under `CMD=test`.
- **Prefixes**: a feature owns `/<f>`, `/admin/<f>` and `/api/<f>`; anything else is listed with a
  reason in a `## Prefixes` table in its README (the skeleton features keep the skeleton's URLs).
  `tools/check routes` holds every row to it.

The server runs **N nbio event loops** (one per core; `THREADS` overrides), so handlers run
concurrently. **SQLite (store v3)**: each loop reads through its own read-only connection, and a
handler's reads share one read transaction (one snapshot, committed when the handler returns; a
deferred request's continuation reads outside it); writes
are `store.Op`s queued to one **writer task**, which commits whatever is queued, up to 100, in one
transaction, then runs each op's `done` back on the loop that queued it. A write handler therefore
answers later, through a **deferred response** (`web.defer_response` / `web.resume` /
`web.finish`). The memory family runs the same ops at once under a lock.

**Store procs return failures as values** (`store.Error`: `.None/.Not_Found/.Constraint/.Busy/
.Failed`). Read with `db.read(sql)` + `db.next_row(q, &err)` and `defer db.reset(q)`; write in an
op's `run` with `db.writer_stmt` + `db.step_done`. Bind with the helpers: `bind_text` stores `""`
as `""`, never NULL; ids are 64-bit (`bind_id`/`column_id`); an enum read from a column goes
through `store.enum_from_int`. Strings a read returns are `clone_col`'d into the request arena;
strings an op answers with live in the op's own arena (`store.op_allocator`). A handler answers a
store error with `web.respond_store_error` (404 / 409 / 503 for Busy / 500).

**Crashes** (D15): `guard` turns a trap in a handler into a recovery. A crash that touched nothing
shared answers 500 and serving goes on; one that held a `guard.Mutex`, posted an nbio op or was
inside SQLite is dirty: the server drains and exits 70. A loop that stops ticking, or a lock held
too long, trips the watchdog (exit 70, naming the route and request). Take locks only through
`guard.lock`/`guard.unlock`, and call `guard.posted()` after posting an op from a handler. A thread
that isn't a loop (the writer, a pool, a publisher) posts to a loop only through `workers.post`, which sends
nothing to a loop that has left at shutdown: nbio zeroes a released loop, and a post into it crashed or spun
(M1-05).

## Streams and the hub (M2; PLAN §8.2, §9)

- **`platform/stream`** holds the protocols over the fork's F-1: `stream.sse_begin`, `stream.ws_upgrade`,
  `stream.multipart_begin`, each returning a `^stream.Conn` (or nil: admission answered 503 or 429). A stream
  answers only from a row flagged `.Stream` (front sends `no-cache, no-transform` and `X-Accel-Buffering: no`).
  Its state lives on the heap, freed a tick after its `on_close`; never in the request arena.
- **`platform/hub`** fans events out: `hub.publish(topic, html, rowid, key)` from any thread. A package declares
  its topic families in a `TOPICS` table (`hub.Topic{family = "chat.room", policy = .Queue, perm = …, allow = …,
  replay = …}`; `lan_only` for the topic of a `.Lan_Only` page), and a profile that streams calls `hub.init()` and `hub.mount("<host>", ..TOPICS[:])` in `main`
  and mounts `{"platform", hub.ROUTES[:]}` (`/events`) on that host. A page opens one `#live` stream, which
  the layout writes: `web.render_page(…, live = {topics})` adds the page's topics to the viewer's own (a row with
  `member = true`, `notify.user:<id>`), and `/events?t=<topic>[@rowid],…&after=<cursor>` resumes them; a `resync`
  event asks the page to refetch. A row's `watch` hears its keys' streams open and close (chat's presence).
- Published HTML is the server's own fragment around escaped text: never markup from a request.
- **A live log upserts.** A message travels as `<hx-partial hx-target="#log-…" hx-swap="upsert sort">` around
  elements with stable ids, so a replay, a snapshot after a reconnect and the author's own answer never double it.
- **Rate limits** are a `web.Limit{n, window}` per concern, `web.limit_hit(&l, key)` keyed by a member's id or
  `web.client_key`, and `web.respond_limited` (429, `Retry-After`, a toast for the form's `hx-status:429`).

## Code aesthetics (Odin)

Write it the way Casey Muratori or Jonathan Blow would write C — but in Odin. Compression-
oriented: solve the problem simply, once, and let small reusable procs do the work.

- **Comments say *why*, not *what*.** If the code is obvious, no comment. When there is a
  comment, it explains a decision, a constraint, or a non-obvious mechanism. No narration, no
  AI slop, no restating the line below it.
- **Section dividers**: `// ---- name ----------------------------------------------------`.
- **One definition per concept.** Enum→label is one table (`ROLE_NAMES`); a sort comparator is
  one proc per key, reversed for `_desc` rather than duplicated per direction. Find the seam
  that collapses N cases into one.
- **Naming**: `snake_case` procs/vars, `Pascal_Case`... actually `Ada_Case` types (`Contact`,
  `Field_Error`), `SCREAMING_CASE` constants. Match the surrounding file.
- **Visibility**: `@(private="file")` for true file-locals only. A proc used across files must
  be package-scoped — don't mark it file-private (it won't compile).
- Match the existing density and idiom. The reference for taste is the existing code.

## Views / HTML conventions

- **Raw string literals** (backticks) for all HTML so attribute quotes stand as-is. Reserve
  `fmt.sbprintf` for interpolation: Odin uses `%` verbs (`%d`, `%s`; `%%` is a literal percent).
  **`fmt` also treats `{` and `}` as directive characters** — a format string containing literal
  braces (JSON in `htmx-config`, `hx-vals`, an inline `<script>{…}`) emits `%!(MISSING …)` into
  the output. So never route brace-bearing HTML through `sbprintf`: write it with `w()` and
  splice the dynamic bits around it. (This silently broke the page `<head>` once — see CHANGELOG.)
- **`w(b, s)`** writes a string; **`esc(b, s)`** HTML-escapes. Every dynamic value that lands
  in text passes through `esc`; every value in an `href`/query passes through `url_encode`; every
  value inside JSON (the ld+json blocks) through **`json_esc`** — entities aren't decoded inside
  `<script>`, so `esc` there is wrong. This is the injection boundary — no exceptions. All three
  live in **`platform/escape`**, re-exported by `platform/html`.
- **Helpers take text, not markup.** The layout's and the views' helpers (`page_head`, `toast`,
  `field_msg`, `stat_card`, `link_tile`…) escape their string arguments themselves, so a value from the database is safe to pass
  and nothing is pre-escaped at the call site (write `"Data & CRUD"`, not `"Data &amp; CRUD"`).
  Markup only ever enters through `w()`. Developer-authored inline HTML (the brand's `wordmark`, the about page's
  `lede`) is the deliberate exception, and says so where it is defined. Text cut from user input is cut by rune,
  never by byte (`avatar`).
- **Semantic HTML**: `<header><nav><main><section><article><aside><footer>`, `<form>/<label>/
  <fieldset>`, `<dialog>`-style modals, `<details>/<summary>` accordions, real `<table>`,
  real `<button>`. No div soup.
- A page handler builds its content and calls `web.render_page(req, res, title, active,
  description, content)`, which wraps it in the layout. Fragments answer bare HTML (no layout).

## The request path (`platform/app/front.odin`)

Every request goes through **`front`**, in this order (PLAN §8.4):

1. **The host, the route, the request id, the security headers.** The host by `Host` (an unknown
   one is the main host); the route found before anything answers, so its flags set the headers
   and its permission is checked before the body is read. Every response carries a strict
   Content-Security-Policy (scripts from this origin plus the hashed pre-paint script; no inline
   handlers; `style-src-attr 'unsafe-inline'` only for `style="--x:…"`; `frame-ancestors 'none'`),
   `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, an
   `x-request-id` and `x-version`. A fork that needs a third-party origin widens one directive in
   `web.security_init`.
2. **A malformed `Content-Length`** (anything but plain digits within `int`) gets 400 and a closed
   connection, before anything else can answer: odin-http's own parse took a sign and wrapped, and a
   negative length aborted the process.
3. **The canonical host**: the `*.fly.dev` → `SITE_URL` 301 (see Crawlers).
4. **The cross-site write guard** (`same_origin`), for every write, routed or not: a POST/PUT/PATCH/
   DELETE whose `Sec-Fetch-Site` is anything but `same-origin`/`none`, or whose `Origin` isn't this
   host, gets 403 before its body is read. No header at all means not a browser (curl, k6) and passes.
   When a fork adds a session cookie, mark it `SameSite=Lax`.
5. **No route**: the body capped at `MAX_BODY` (413), then 405 with `Allow` when another method
   serves the path, else the site's 404 (a bare one for htmx).
6. **The viewer and the route's rules**: the build's identity loads the viewer; the row's `perm`
   (401/302 for a guest, 403 otherwise) and `.Lan_Only` (404 off the LAN) are checked.
7. **The body**, capped by the route's `body_cap` (`MAX_BODY`, 64 KiB, when 0), then the handler,
   inside the crash guard. Handlers read a form with `web.form(req)` (`+`- and percent-decoded).
8. **One logfmt access-log line** (`ev=req id=… m=GET route="GET /data" st=200 us=183 …`, never the
   query), unless the handler deferred its response: then `web.finish` logs it when it answers.

Log with `obs` (`obs.begin(.Info, "mod", "ev")`, `obs.str`, `obs.num`, `obs.end`): logfmt in
per-thread buffers, never `fmt.println` and never `core:log`. `/healthz` answers exactly `ok` while
every critical module (the store's `SELECT 1`) is up; `/livez` while every loop ticks; `/readyz`
while ready and not draining (`?detail` lists the modules); `/metrics` serves Prometheus text to the
`METRICS_TOKEN_FILE` bearer, with a request counter per route.

A new cross-cutting rule (auth, a rate limit) belongs in `front`, not in each handler.

## Allocator model (the #1 gotcha — get this right)

odin-http gives each connection a growing arena as **`context.temp_allocator`**, freed *after* the
response is flushed.

- **Build all response HTML in the temp allocator** (`strings.builder_make(context.temp_allocator)`,
  `fmt.tprintf`). It lives exactly long enough and costs nothing to free.
- **Nothing per request touches `context.allocator`.** What a store read returns is cloned into the
  request arena (`clone_col`); never keep it past the request (in a global, a cache) without cloning
  it into `context.allocator`, which is for what lives as long as the process: the ETags, the CSP,
  the fingerprinted asset names, the route table, computed once at boot.
- **A deferred response outlives its handler**: everything its continuation needs goes in the op
  (`store.new_op(T, bytes)`, whose tail is an arena: `store.op_allocator(op)`), and the continuation
  calls `web.resume(&op.deferred)` first: `nil` means the client left, so it frees the op and
  returns; otherwise it answers and calls `web.finish`. Between the two the response is the
  continuation's: a crash there answers 500 and names the request, as a handler's does (the
  guard's unwind, which `resume` sets and `finish` clears). Never touch the request arena of a
  deferred request after the handler returns.
- **Handlers never read the body themselves**: `front` reads it, capped, before calling them.

## odin-http (vendored fork, `app/vendor/odin-http`)

Vendored in-tree with the fork's changes F-1…F-24, each listed with its reason in `UPSTREAM.md`
(streams, the `invoke` hook the crash guard uses, idle/header/body timeouts, a connection cap that
answers 503, a bounded shutdown, SIGTERM, a per-thread date header, a bind retry, deferred
responses). Features never import it: `platform/web` wraps it.

- Routes are `web.Route` rows, `{.Get, "/contacts/(%d+)", handler, .Public, {.Fragment}, 0}`, in a
  package-level `ROUTES := [?]web.Route{…}` table. Patterns are Lua patterns, anchored; captures are
  `req.url_params[i]`; escape a literal `.` as `%.` and a literal `-` as `%-` (a bare one after a
  character is Lua's lazy quantifier; `tools/check routes` refuses it). The router keys rows by their first one or two
  literal segments, so dispatch is a map lookup, then the feature's few patterns.
- Responses: `web.respond_html(res, html, status)`, `web.respond_plain`, `web.respond_json`,
  `web.render_page`, `web.not_found(req, res)`, `web.respond_store_error`; they add
  `; charset=utf-8`.
- Query strings: `web.query_get(req, key)`, `web.query_int(req, key, fallback)`; path ids:
  `web.parse_id`.

## Crawlers / SEO

- **One canonical origin.** The brand's `site_url` (`SITE_URL` overrides) is the single source for
  `<link rel="canonical">`, `og:url`, the `/sitemap.xml` entries, and the redirect target. The
  app answers on both the custom domain and its `*.fly.dev` hostname, and 301s the latter onto the
  former — **unless the origin is a placeholder** (`*.example.com`, `.test`, …), when it serves
  instead of sending visitors nowhere. **`/healthz` is exempt.**
- **Derived, never duplicated.** `/sitemap.xml` walks the host's nav; the canonical URL is the
  origin plus the page's nav href; `robots.txt` disallows the literal start of every `.Fragment`
  row (a family of rows under one first segment collapses to it, `/ui/`, unless a page lives under
  that segment too, as `/lab/streams` does beside `/lab/feed`). Mark a fragment route `.Fragment` and
  robots.txt follows.
- **`og.png` is deliberately unfingerprinted** (`/static/og.png`): social platforms cache a preview
  against its URL. Its source is **`tools/og/og.html`** (the command to re-render is in the file).
- `<script type="application/ld+json">` is **all literal braces** — write it with `w()`, never
  `sbprintf`, and splice values with `json_esc`.
- Bing's and IndexNow's ownership proofs come from the brand (`bing_site_auth`, `indexnow_key`);
  blank, their routes 404.

## HTMX conventions / gotchas

- **htmx 4 events** are colon-namespaced (`htmx:after:request`, `htmx:after:swap`,
  `htmx:after:process`) and carry `event.detail.ctx` (`sourceElement`, `target`, `response`, …).
  Form auto-reset is the `Reset_On_Success` behaviour (`html.behave`; not `hx-on`): it resets its form after a
  2xx, **scoped by `ctx.sourceElement`** so a child field's
  validation request can't reset the form (the email field on /forms validates as you type — an
  unscoped reset wiped what the user typed; this bit us once).
- **Out-of-band toasts**: return `<div class="toast" hx-swap-oob="beforeend:#toasts">…</div>`
  from any handler; `html.toast(kind, msg, true)` does this.
- **OOB a *table row* with `<hx-partial>`, not `hx-swap-oob`.** htmx 4 collects OOB via
  `querySelectorAll("[hx-swap-oob]")`, which doesn't descend into `<template>`; and a response that
  *starts* with a non-table element is body-parsed, which drops a trailing bare `<tr>`. So to
  refresh `#contact-<id>` alongside a drawer swap, wrap the row in
  `<hx-partial hx-target="#contact-N" hx-swap="outerHTML">…</hx-partial>` (htmx turns it into a
  `<template>` it processes). See contacts' `updated`. (A row-only response that *starts* with `<tr>`,
  like delete-from-drawer, is fine bare.)
- **An OOB swap suppresses an *empty* main swap** (htmx 4.0.0 changed this; in beta6 only
  `hx-partial` did). So a response that is nothing but OOB no longer clears its target. Where the
  empty swap is the point — delete-from-drawer sends an empty body plus one OOB `<tr>`, and closing
  the drawer *is* that empty swap into `#overlay` — opt back out per element with the `swapEmpty:true`
  swap modifier (see the drawer's Delete button in contacts' views). Prefer that over the
  global `allowEmptySwapAfterOOB` config, so the safer default still holds everywhere else.
- **Form bodies arrive `+`-encoded.** htmx 4 sends spaces as `+` (the form-encoding standard);
  odin-http's `body_url_encoded` only percent-decodes, so POST bodies go through `web.form(req)`
  (it `+`→space-decodes via `form_decode`, like `query_get`).
- **Exit animations**: `hx-swap="outerHTML swap:220ms"` keeps the node around long enough for
  the `.htmx-swapping` CSS to play.
- **Overlays** (modal/drawer) load into `#overlay` and close via `GET /ui/clear` (empty body).
  The modal backdrop intentionally has **no** close handler — an outside click must not
  discard a half-typed field. The drawer backdrop may close (no field to lose).
- **View Transitions are for boosted navigation only — never set `transitions` in `htmx-config`.**
  While a view transition runs (~250ms, the default crossfade), Chromium hit-tests the whole page to
  `<html>`, so a click whose mouse-up lands in one is dropped, and `pointer-events: none` on
  `::view-transition` does **not** change that (Firefox/WebKit unchecked — the rule doesn't depend on
  them). A page swap can afford it. A
  fragment swap can't, because the rest of the page stays live: with the global flag on, the `/forms`
  email field's blur validation swallowed the very click that blurred it (issue #8). The brand + nav
  links opt in per element with the `transition:true` swap modifier; a fragment wants its own CSS
  entrance animation instead (`.msg`, `.toast`, `.modal`, `.row-new` all have one). Consequence:
  back/forward restores don't crossfade — htmx 4 takes their transition from the global flag alone.
- **Boosted navigation**: the brand + primary-nav links carry
  `hx-boost="true" hx-swap="innerHTML transition:true"` (on **each link** —
  htmx 4 doesn't inherit it from a parent `<nav>` the way htmx 2 did). Clicking swaps the `<body>`
  and pushes history instead of a full document load — SPA-like, no asset re-parse, no theme flash,
  and the `<title>` updates from the response. Boost only internal HTML links; leave the JSON-API
  tile and the no-action search/filter forms alone. Server work and bytes are unchanged (whole pages
  are still rendered) — it's a client-side win. A body swap re-creates `#toasts` / `#overlay` / the
  picker, so keep per-node JS state swap-safe (see the JS conventions).

## Validation errors (422)

A submit the server refuses answers **422 Unprocessable Content** with the reason as HTML, never a
200. Two things follow, and together they keep the user's input:

- **`Reset_On_Success` resets its form only after a 2xx**, so a 422 leaves every field as
  typed (and a success also empties the form's `.form-error` slot).
- **htmx 4 swaps 4xx responses by default** (`noSwap` is only `[204, 304]`). If the error belongs where
  a success would land (`/forms` → `#form-result`), nothing more is needed. If it belongs elsewhere,
  route it with **`hx-status:422="target:#slot swap:innerHTML"`** on the form (the `/data` add form
  and the minimal note form use a `<p class="field-msg form-error" id="…">` slot inside the form;
  `hx-status:5xx` works the same for server errors). Status keys match exactly, then `42x`, then
  `4xx`.
- A form that re-renders itself (the drawer edit) answers 422 with **itself, filled with what was
  typed**, plus the reason (contacts' `edit_rejected`).

Validation lives in the domain (contacts' `check_create`/`check_update`, notes' `check`), returns
plain messages, and caps every text field; the inputs carry the same `maxlength` and `required` so
the browser stops first. Store failures are separate: `web.respond_store_error` (404 / 409 / 503 /
500).

## CSS conventions (`app/platform/static/app.css`, features' `static/<f>.css`)

- **Token-driven, two orthogonal axes.** `data-style` × `data-scheme` on `<html>` (the full theme
  has 6 styles and 24 schemes, the lite one `modern` with `midnight` and `daylight`; SSR default
  `modern`/`midnight` or the brand's `style`/`scheme` (Houston's `houston`), restored pre-paint from
  localStorage to avoid a flash; a member's kept theme, `data-kept`, is rendered and left alone). The lite stylesheet is
  the full one with every `/* full-only: … */ … /* /full-only */` region cut by `tools/bundle`, so
  mark a style or scheme block that way and the two never drift. A feature's own CSS goes in
  `app/features/<f>/static/<f>.css`, appended when a profile reaches the feature.
  Structural tokens live on `:root`; each `[data-style=x][data-scheme=y]` block sets the palette;
  `--on-accent` flips button text dark on light-accent schemes. Components read tokens
  (`var(--accent)`, `var(--surface)`), never raw colours — so a new scheme is one palette block and
  a new style is one `[data-style]` block over untouched component HTML.
- One `.btn` + modifiers (`.btn-primary`, `.btn-outline`, …). Same pattern for badges/chips.
  Don't fork a new base class when a modifier will do.
- **Vibrant but disciplined**: violet→indigo→cyan gradient accents, `color-mix()` for tints.
- **Snappy**: transitions 120–220ms, ease-out / spring curves (`--ease`, `--spring`).
  Always honour `prefers-reduced-motion` (there's a global override at the bottom).
- Dynamic values driven by CSS custom properties set from JS (e.g. slider `--fill`, ring
  `--p`, avatar `--h`), not by rewriting styles in JS.

## JS conventions (`app/platform/client/`)

- HTMX drives interactions; client code only does what the server can't: theme persistence, toast
  lifecycle, tab selection state, slider fill, count-up. A profile's `app.js` is `client/core.js`
  (shared: the theme picker, count-up, the overlay's Escape) followed by its `client:` member's
  `app.js`, concatenated by `tools/bundle`.
- **Behaviours go through `html.behave(&b, .Name)`, never hand-written** (PLAN §12.4, D22). It writes
  `_="install Name"` on the hyperscript client and `data-behave="name"` on the vanilla one, from the
  one `BEHAVIOURS` table in `platform/html/behave.odin`. A twinned behaviour has a definition in
  `client/hyperscript/behaviours._hs` (or a feature's `static/<f>._hs`) *and* a twin in
  `client/vanilla/app.js`'s dispatcher; a hyperscript-only one (`""` in the table) is an
  enhancement the feature's core flow works without. `escaping.spec` holds every page to it.
- **A feature's `static/*.js`** is appended to `app.js` after the member's (tools/bundle; wrap it in
  its own function, it shares the file): only for code that is no behaviour and must run under
  either client (the scripting lab's plain-JS widget, the compat page's event counter).
- **Markup never carries code.** On the hyperscript client the gate in its `app.js` initialises an
  element only when its `_` is a lone `install <Name>`; data reaches a behaviour only through
  `data-*`. hyperscript's `socket`, `eventsource`, `worker`, `component` and `js` are banned.
- **No inline handlers, ever** (`onclick=`, `oninput=`, `onsubmit=` …): the Content-Security-Policy
  refuses them, so they silently do nothing. Markup says what a click means with `html.behave`, a
  `data-*` attribute or a role (`data-pick-style`, `data-sw-style`, `.toast-x`), and one **delegated
  listener** on `document` routes it — which also covers content swapped in later. Re-init swapped
  content on `htmx:after:process` (htmx 4's "content wired up" event). The files run `defer` (DOM is
  ready). A click that must not bubble to a closer behind it is a `hx-trigger="click from:self"` on
  the closer, not `stopPropagation()`.
- **No new inline `<script>`.** The only one is `html.THEME_PREPAINT_JS`, admitted by its hash
  (computed at boot, so editing the constant keeps the header right), and on a `.Nonce_Csp` page
  the layout's scripts by nonce; anything else goes in app.js or a behaviour.
- **The nonce class** (`/scripting/*`, `.Nonce_Csp`): every htmx element carries
  `hx-nonce="<%N%>"` (`html.NONCE_MARK`, which the response writer turns into the response's
  nonce), or hx-csp strips its attributes; only such an element may carry code (`hx-on`, a trigger
  filter, `js:`, hx-live). `.Trusted_Types` adds Trusted Types there and drops hyperscript. Clear
  an element with `replaceChildren()`, never `innerHTML = ""`, which Trusted Types refuses.
- **Keep per-node state swap-safe** — a boosted nav swaps the whole `<body>`. Make on-load init
  idempotent so `htmx:after:process` can re-run it after a swap (a toast's timer flags `data-armed`,
  the count-up `data-counted`; `markPicker` just re-sets aria state), and listen on `document`, never
  on a node a swap replaces.

## Odin gotchas (discovered here)

- `strconv.atoi` is deprecated → `strconv.parse_int(s, 10)`. But `parse_int` wraps silently past 64
  bits (`"18446744073709551617"` → `1`, ok=true) and takes a sign and `_` separators: parse
  anything that names a row with `parse_id` (digits only, overflow-checked, via `parse_digits`).
- `*_test.odin` files compile into every `odin build` too (only `odin test` runs them), so a test
  file must build under every profile that reaches its package. The test runner fails a test that logs at
  `.Error`; silence an expected one with `context.logger = log.nil_logger()`.
- `len(EnumType)` is valid (member count). Iterate enumerated arrays as `for value, key in ARR`.
- `make([dynamic]T, context.temp_allocator)` is valid (allocator as the 2nd arg).
- Ternary `cond ? a : b` exists; use it for small attribute choices.
- `strings.split_by_byte_iterator(&s, '&')` mutates `s` (pass a local copy of `req.url.query`).
- `@(thread_local)` variables can't have initialisers; a package-level `[?]T` constant (`::`) can't
  be sliced (`X[:]` needs `:=`); `@(init)` procs must be contextless.
- `ast.inspect` calls its callback with `nil` after a node's children: check for it.
- `for x in m[k]` traps when `m` itself is a nil map (dev-2026-10); `r := m[k]` and `v, ok := m[k]` read a nil
  map fine, so range over the local (`r := m[k]; for x in r`).
- Shell heredocs in the tooling eat backslashes: write files with escapes through an editor, not
  `cat <<EOF`.

## Recipes

- **New feature** `f`:
  1. `app/features/f/models/` (package `f_models`): the types and the store contract's proc types
     (`Store_List :: proc(...) -> Error`). No logic.
  2. A store per family it supports, `app/stores/<family>/f/`: the procs, and `contract.odin` with
     one `_ : m.Store_X : x` line per contract type. In SQLite, `migrations/0001_<name>.sql` (plain
     SQL; the runner wraps it) listed in its `MIGRATIONS`; never edit a migration that has shipped,
     add the next one (boot refuses a changed hash).
  3. `app/features/f/` (package `f`): validation (a length cap on every text field) and the calls,
     importing `store:f`.
  4. `views/` (HTML builders over `^strings.Builder`) and `web/`: handlers, `ROUTES` under `/f`
     (anything else goes in a `## Prefixes` table in `app/features/f/README.md`, with its reason),
     `EXTS` (htmx extensions it needs; `web.Exts{}` for none), and `init` if it reads env rows.
  5. Mount it in a profile's `routes.odin` (`{"f", f_web.ROUTES[:]}`), call its `init` in `main.odin`,
     and in a SQLite profile add `store_sqlite.migrate("f", f_store.MIGRATIONS[:])`.
  6. Tests: a spec in `e2e/tests/f/` tagged `@f` (and `@<g>` for every other feature it touches), and
     a scenario in `load-tests/scenarios/f/` with a `// tags: @f` line, copying an existing one.
  7. `odin run tools/check -- all`, both suites, `tools/check parity`; CHANGELOG.
- **New page**: a view proc, a handler calling `web.render_page`, a `.Get` row in the feature's
  `ROUTES`, and a nav entry in the profile's `brand.odin` if it's top-level (the nav entry puts it in
  the sitemap and makes its canonical URL). e2e + load. Changelog.
- **New fragment/endpoint**: a view returning bare HTML, a handler, a row marked `.Fragment` (so
  robots.txt disallows it). A write goes through the domain to the store as an op, answered through a
  deferred response; refused input answers 422; parse path ids with `web.parse_id`; escape all input.
  e2e + load. Changelog.
- **New profile** `p`: `app/cmd/p/` with the four files (copy `minimal`'s), and a line in both
  `build.sh` and `build.bat` naming its four families (`tools/init` reads the profiles from
  `build.sh`). Run `prepare` (it bundles every `app/cmd/*` with a `main.odin`), then
  `odin run tools/check -- all` and `odin test tools/init` (the generator composes every committed
  profile again from its lines; a profile it can't reproduce fails there).
- **The generator** (`tools/init`, PLAN §7.4): a feature's profile lines are taken from a committed
  profile that mounts it, so a new feature needs a profile that mounts it before `--add` can place
  it anywhere else. After adding or renaming a feature, refresh the catalog:
  `odin run tools/init -- --list --json > docs/catalog.json` (CI holds it current).
- **New component**: a proc writing into `^strings.Builder` + a token-driven CSS block. Reuse
  `html.icon`, `esc`, `w`. Add it to the `/components` gallery.
