# Changelog

All notable changes to this project are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/); releases are tagged from **1.0.0** on. **Every
behaviour/structure/build change gets an entry under `[Unreleased]`** — see `CLAUDE.md`. Entries
track [Conventional Commits](https://www.conventionalcommits.org): `feat`→Added, `fix`→Fixed,
`refactor`/`perf`/`style`→Changed, removals→Removed.

## [Unreleased]

## [2.2.0] - 2026-10-31

The starter's third milestone, M3: the pipeline and apollo's LAN. A `v*` tag builds each hosted profile's image on
distroless, natively on amd64 and arm64, publishes one multi-arch list per profile to GHCR (`vX.Y.Z` and `sha-<7>`,
never `latest`) with provenance, and makes the GitHub Release (a pre-release for `-rc.N`); `deploy/promote.ps1` moves
apollo's stack to it one service at a time behind the stack Caddy, smoke-tested and rolled back by itself on a failed
smoke. The four witnesses (minimal, streams, skeleton, lab) run at v2.2.0-rc.1 on apollo's LAN (stage 1a), where a
broken tag rolled back by itself, 50 VUs through a promote saw no 5xx, and two-host k6 failed nothing. `landing`, the
starter's own page, shows the catalog and builds the init command; the lab's witness board probes the others. Chat's
reconnects replace the log across a gap on every transport. An independent audit (`docs/audit/M3.md`) found 1 HIGH,
fixed and re-read; the parity gate passes on both legs (`docs/perf/PARITY.md`). Stage 1b, through NPM, passes:
every witness answers over HTTP/2 and renders with no error or CSP violation, http and the alias host 301 to the
canonical https origin, an SSE stream gets its first frame unbuffered (21 ms) and a WebSocket upgrades (the
smoke, 15 of 15), and 1000 SSE streams held for an hour through NPM with no early end and no quiet minute, the lab
flat at 7 MiB (the smoke and the hold are on master, as `deploy/npm-smoke.mjs` and `deploy/npm-hold.mjs`).

### Fixed

- **The lab no longer grows until it is OOM-killed**: the witness board's probe thread never freed its temp
  allocator, so every probe's request line and resolver lookups stayed (M3-01).
- **A chat socket answers the page's version once**: every frame carrying one bought a snapshot render, up to 20 a
  second per socket (M3-02).
- **`tools/init` keeps `docs/catalog.json` in a project with `landing`**, which embeds it; a project without landing
  drops the file and the Dockerfile's copy of it, which failed its image build.
- **The landing builder never echoes a refused name** into the command it offers to copy (M3-05); its boot failure
  logs through obs (M3-12).
- **The release publishes only a release-shaped tag on a commit CI passed** (`vX.Y.Z`, `vX.Y.Z-rc.N`); the registry
  token goes through `env`, and the Dockerfile quotes `VERSION` and `PROFILE` (M3-06).
- **`promote.ps1` takes only `vX.Y.Z`, `-rc.N` or `sha-<7>`**, never `latest`, and checks a previous tag from the host
  before a rollback uses it (M3-08); **the stack's containers drop every capability** and can't gain privileges, the
  Caddy keeping `NET_BIND_SERVICE` under a memory limit (M3-07).
- **The release image builds on arm64**: the Dockerfile's build stage declared `ARG TARGETARCH=amd64`, and that
  default won over BuildKit's value, so an arm64 build fetched amd64's Odin (its checksum matched, being amd64's) and
  `prepare` failed with "Exec format error"; the release workflow's first dry run caught it. The ARG is declared bare
  now, and the build falls back to amd64 only when no builder sets it.
- **Firefox e2e no longer stalls on a page load now and then**: Playwright's Firefox driver sometimes lost a page's
  first navigation across the browsing-context-group swap our `Cross-Origin-Opener-Policy: same-origin` causes, so
  `page.goto` timed out on a page that had loaded. The test browser turns COOP's enforcement off
  (`browser.tabs.remote.useCrossOriginOpenerPolicy`); the server still sends the header and `headers.spec` holds it.
- **A chat poll from before what the room let go replaces the log** (M2-35): the store's `changed` says whether it
  still reached the poll's version, and when it didn't the answer is the room's snapshot with `innerHTML`; an upsert
  had kept what the page had with a silent gap before the newest.
- **A chat socket's reconnect and SSE's resync replace the log across a gap, and keep it across a restart** (M2-31's
  socket part, M2-35's SSE part): a room page now holds the newest room version it has seen (`#ver-<room>`, which
  every message fragment keeps current), and a reconnect sends it back: a socket's first frame (`{"ver": …}`, sent
  from the field's form on hx-ws's `after:connection`), SSE's resync by `hx-include` (`/since?ver=`, read before
  `HX-PTag`, which hx-ptag leaves at the pane's last resync). The answer is what changed since, or the last 50 with
  `innerHTML` when the room let some of it go. A version from before a restart is reached, so the page keeps what it
  had (D37). A socket no longer gets the last 50 on every connect, only what its page hasn't seen.
- **A POST stream gives its request arena back** (M2-21, the fork's F-17): a handler called from a body's
  callback (the bot's asks, `POST /lab/sse/tick`) began its stream after the headers' path had looked, so it kept up
  to 64 KiB of form until the stream ended; `body` now gives the arena back where that callback returns
  (`body_test`'s `post_stream_gives_its_arena_back`).
- **Ops' panel stream is LAN-only, like its page** (M2-18): a hub topic can be `lan_only`, which `/events` refuses
  (403) to a client outside `LAN_CIDRS`; before, an admin by `ACCOUNTS_NICK_ADMIN_CIDRS` off the LAN got the 1 Hz
  panel on `/events?t=ops.panel` while the page answered 404.
- **A chat message full of brackets posts over the socket** (M2-36, with M2-33): `stream.ws_field` reads hx-ws's
  field by hand, in one pass, recursing only per real container up to 16 deep, so brackets inside a string are
  text. Before, a scan counted every `[` and `{` against a bound that guarded core:encoding/json (which `alloca`d
  stack per key), and refused a pasted message after the composer had cleared it.
- **A HEAD no longer sends the page's body** (the fork's F-24): odin-http runs a HEAD as a GET and meant to
  answer it without the body, but changed a copy of the request line, so the body went out and a keep-alive
  client read it as the next response. Found by M3's stack test behind Caddy.

### Added

- **The release workflow** (`.github/workflows/release.yml`, M3, PLAN §20.1-20.2): a `v*` tag builds
  `minimal`, `streams`, `skeleton` and `lab` on amd64 and arm64 runners and publishes each as one manifest list,
  `ghcr.io/alexh95/odin-htmx-starter-<profile>:vX.Y.Z` and `:sha-<7>`, with a provenance attestation, then
  a GitHub Release from the tag's CHANGELOG section. Run by hand it is a dry run.
- **apollo's stack** (`deploy/compose.yaml`, M3, PLAN §20.4): the stack Caddy on `8120:80` at a fixed address on
  the pinned `172.31.120.0/24` network, in front of the four witnesses (read-only, UID 10001, the io_uring seccomp
  profile staged beside it, `init`, log rotation, `--healthcheck`, half a core and 64 MB each, no published
  port), each trusting `X-Real-IP` from the Caddy alone; `deploy/.env.example` holds a tag per service. CI's
  `stack` job runs `deploy/stack-test.sh`: each host through the Caddy, the 421 catch-all, the trusted chain,
  the hardening and a restart behind the Caddy.
- **`landing`, the starter's own page** (M3, PLAN §15.5): the lab's `/` shows the profiles running now, the
  catalog (`docs/catalog.json`, embedded at build time) as a table of profiles and one of features, and the
  init-command builder, whose fragment (`GET /landing/command`) is the `odin run tools/init -- …` line with what it
  pulls in, or why the generator would refuse it. The lab's index moved to `/lab`; e2e and k6 cover both routes.
- **The witness board** (M3, PLAN §15.4): `status` takes `STATUS_PROBES` (`name=host:port,…`), each probed at
  `/healthz` every 10 s by a thread of its own with a 2 s timeout, and shows each one's state, version and time on
  `/status`. The lab mounts it; on apollo it watches the other three witnesses.
- **`deploy/promote.ps1`** (M3, PLAN §20.5, D42): promotes a release's images to apollo's stack from the dev PC,
  one service at a time: stage the compose file, Caddyfile and seccomp profile, pull, snapshot a service with a
  database, `up -d --no-deps` with no Caddy reload, smoke through the Caddy (`/readyz`, `x-version`, an SSE first
  line, a WebSocket upgrade), `deployed.json`, and the previous tag again on a failed smoke. `-Status` is a
  read-only inventory, `-WhatIf` the plan, `-Target local` the same against WSL's Docker. The SSH alias, the
  directory and the address come from the git-ignored `deploy/promote.local.psd1`.
- **A new project leaves the starter's apollo hosting behind** (`tools/init`): `deploy/compose.yaml`, `.env.example`,
  `promote.ps1` and the two stack tests go, with CI's `stack` and `proxy-config` jobs, and `release.yml` publishes
  the project's one profile. The docker job's old step name it still edited is gone.
- **proxy-config** (CI, M3, PLAN §20.1, X26): `deploy/proxy-config-test.sh` runs `caddy validate` on
  `deploy/Caddyfile` and every Caddyfile snippet in the docs, `nginx -t` on NPM's rendering, and asserts every
  redirect alias bare and deep, the `htmx-odin-starter` 301, the catch-all's 421 and the `8120:80` publish.

### Changed

- **`scale`'s budget is store v3's** (#14): p95 < 1 s and p99 < 2 s at 20 VUs over 20k contacts, about five times what
  CI's runner measures (198/300 ms; 70/97 ms on the dev PC), down from 3 s / 6 s set when every request queued on one lock.
- **Fly deploys on a tag**: the dormant Fly job moved from `ci.yml` to `release.yml` as `deploy-fly`, so with
  `FLY_DEPLOY` on a release redeploys the skeleton witness, never a push to `master` (PLAN §20.3, X2).
- **A pre-release tag makes a pre-release**: a `vX.Y.Z-rc.N` tag publishes its images as a release does, and its
  GitHub Release is marked pre-release and never latest, its notes taken from `[Unreleased]`, so an rc needs no
  CHANGELOG section of its own and the final tag's section still holds everything since the last release.
- **The image is the release image** (M3, PLAN §20.2): the binary at `/app/bin` on distroless
  `base-nossl-debian13` (both bases pinned by digest), stopped by SIGTERM, health-checked by its own
  `--healthcheck`, with `/app/SOURCES.md` naming the base's Debian source packages; Odin's arm64 asset is picked
  by `TARGETARCH`. CI's `docker` job builds and runs `minimal`, `streams`, `skeleton` and `lab` on a read-only
  rootfs, and checks the UID, the libraries (glibc only), the 25 MB compressed budget, the stop and, for
  `skeleton`, a backup on a fresh `/data`. `compose.yaml` takes `PROFILE` and `HOST_PORT`.

## [2.1.0] - 2026-10-28

The starter's second milestone, M2: the stream substrate. `platform/stream` speaks SSE,
WebSocket and multipart on the fork's streams (F-1, with M2's F-17 to F-22), under admission caps, heartbeats and a
slow-consumer cut; `platform/hub` fans events out to one `#live` stream per page, with cursors that resume or resync.
Two profiles witness it: `lab`, the stream contract pages, and `streams`, with chat on four transports, the Inbox,
the bot on its mock, ops' 1 Hz panel, the status board and the `nick` identity. Around them: page bundles and route
flags in the CSP, the hyperscript client behind `html.behave`, `tools/init`'s compose mode (generator v1),
`tools/check topics` and `exts`, the stream drills, the TSan gate, the soak, Autobahn, and the lab and `streams`
through Caddy and NPM in CI. An independent audit and three re-reads of its fixes (`docs/audit/M2.md`) found 4 HIGH,
all fixed, and the parity gate passes on both legs (`docs/perf/PARITY-M2.md`).

**For a fork of 2.0.0:** markup names its client behaviours through `html.behave` (a hand-written `_=` or
`data-behave` should move to it; `escaping.spec` holds every page to that); the htmx-config files are per bundle
(`app/build/<p>/<bundle>.config.json`, Main's was `htmx-config.json`); `web.render_page` takes a page's bundle and
live topics as defaulted parameters, so existing calls stand.

### Added
- **`platform/stream`** (PLAN §8.2): SSE, WebSocket and multipart on the fork's streams. The SSE encoder splits user
  text on CR, LF and CRLF alike; the WebSocket handshake checks `Origin` against the host's own origin (a request
  without one passes) and the codec is strict RFC 6455 (1002, 1007, 1009 at 64 KiB; 1013 to a slow consumer with a
  2 s deadline, 1012 on drain, 1011 after a pure crash, 1008 past a route's frame rate); the multipart writer frames
  with CRLF and a `Content-Length` per part. Each stream writes its first bytes with its headers, and one timer per
  loop sends heartbeats every 20 s and closes a socket silent for 45 s. A `.Stream` route gets
  `Cache-Control: no-cache, no-transform` and `X-Accel-Buffering: no`. Unit tests cover the encoder, the codec
  (frame errors, fragments, UTF-8 across fragments, close codes) and the part framing.
- **Stream admission** (§9.4): 503 past `STREAMS_TOTAL` (8192), `STREAMS_PER_CLIENT` (16), `STREAMS_PER_USER` (8) or
  `STREAM_QUEUED_TOTAL` (64 MiB queued to all streams), and 429 with `Retry-After` past `STREAM_CONNECTS` (20 a
  minute from one client); `STREAM_HEARTBEAT_S` and `STREAM_MAX_QUEUED` set the heartbeat and the per-stream cap.
- **`platform/hub`** (PLAN §9, D13): `hub.publish` from any thread, with one wakeup per loop per burst and the
  encoding done once per transport on each loop; a ring per topic following its row's policy (`.Queue`, `.Latest`
  per publish key, `.Sample`), at most `HUB_RING` (256) messages and `HUB_RING_BYTES` (1 MiB); `<epoch ms>-<seq>`
  ids; `/events` (`hub.ROUTES`) with each topic's perm and `allow`, then D13's resume: `Last-Event-ID`, then `after`,
  then the topic's keyset replay from its store, else `event: resync`; `hub.kick` (SSE `kicked`, a socket's close
  code). A profile mounts its `TOPICS` with `hub.mount` in `main`, so one that doesn't stream links no hub code.

- **The `lab` profile** (`app/cmd/lab/`, PLAN §7.1, §15.5): the stream contract pages, on an origin with no
  sessions. The `lab` feature's `/lab/streams` pages use hx-sse, hx-ws and hx-multipart the way a real page does
  (one layout SSE stream, one socket inside the swapped region, parts into their own targets), beside the endpoints
  spike S0.3's checks drive: a ticking SSE answer, the WebSocket echo, a room through the hub, multipart parts and a
  resumable multipart feed, publish and close for a `lab.feed` or `lab.room` topic, and `/lab/stats`. Published text
  is escaped into a fixed fragment and every key is plain, since the lab is public. `./build.sh lab`, on the
  hyperscript client.
- **The stream contract in e2e** (`e2e/tests/lab/`): S0.3's 29 contract checks, its plan checks and its 20 browser
  checks, ported onto `platform/stream` and `platform/hub` (Chromium and WebKit locally, Firefox in CI), with
  checks of the hub's per-topic rings; and load scenarios for every lab route (`load-tests/scenarios/lab/`).
- **Every htmx 4.0.0 extension is pinned** (`app/vendor/htmx/PINS`, one SHA-256 per file, read by both prepare
  scripts) and fetched by prepare, and the htmx-config meta's `extensions` allowlist comes from the profile's bundle
  (`tools/bundle` writes it beside the bundle; a profile with none keeps the skeleton's exact head).
- **Stream counters**: `app_streams_opened_total` and `app_streams_ended_total{why}` on `/metrics`.
- **`platform/stream/client`** (PLAN §8.2): the one non-blocking HTTP, SSE and WebSocket client, on core:nbio, with
  incremental parsers for the response head, chunked bodies, SSE and the server's frames. **`tools/streamload`**
  (§19.1.7) drives it: thousands of SSE and WebSocket clients over a few event-loop threads, a publisher whose stamped
  messages give delivery percentiles, a restart mode that counts clients back and how SSE resumed, and a hold mode for
  RSS per stream. `docs/perf/STREAMS.md` records §18.4's fan-out, restart and per-stream budgets on the Linux leg:
  all met (3000 SSE subscribers p99 about 10 ms; 4000 clients back 1.7 s after a `kill -9`).

- **Page bundles and route flags in the CSP** (PLAN §12.1-12.2): the fixed Scripting, Compat_Htmx2 and Compat_Alpine
  bundles are embedded when a profile's packages name them, each with its own htmx-config (Scripting's with
  `safeEval`); a page names its bundle in `web.render_page`, and a boosted request for a page on a fixed bundle gets
  `HX-Redirect`, since a boosted swap would keep the old document's CSP and scripts. A `.Nonce_Csp` route's response
  gets a fresh nonce: scripts by nonce or the pre-paint hash only, `no-store`, the nonce on the layout's scripts and
  in place of the views' `hx-nonce` markers. A `.Private` page carries `hx-history="false"`. Boot check 6 covers
  the page bundles.
- **CSP violation reports** for `streams`, `lab` and `full` (`web.Header_Set.Reporting`): `Reporting-Endpoints` and
  `report-to csp`, and `/csp-report` (`web.REPORT_ROUTES`) logs each at warn, 10 a minute per client.
- **`headers.spec`** (e2e, api): each profile's exact header set, no COEP, no HSTS over http, `/csp-report` where
  mounted.
- **The hyperscript client** (`platform/client/hyperscript`, D22, PLAN §12.4): the `client:` family's second member,
  _hyperscript 0.9.94 core only (pinned in `app/vendor/hyperscript/PINS` and fetched by prepare). The platform's
  core behaviours are in its `behaviours._hs` (Tabs, Toast, ResetOnSuccess, Dismiss, SearchBox, RangeFill, RelTime,
  CopyText), which tools/bundle ships with each reached feature's `static/*._hs`; its `app.js` is the gate, which
  initialises an element only when its `_` is a lone `install <Name>`, so an injected `_` or `text/hyperscript`
  script never runs.
- **`html.behave`** (`platform/html/behave.odin`): the one seam between markup and the client. `behave(&b, .Tabs)`
  writes `_="install Tabs"` or `data-behave="tabs"` from one table of twenty-one behaviours, the eight twinned ones
  with a vanilla name.
- **`escaping.spec`** (e2e): on every sitemap page each `_` is a lone install and each `data-behave` a twin's name
  from the table; on a hyperscript build, an injected `_` and an injected hyperscript script stay inert beside a
  working `install`.
- **The notices** carry _hyperscript's licence and the MIT notice of multipart-parser, which htmx's hx-multipart
  ports and whose minified file drops it (owed since the lab began loading hx-multipart); `ops.spec` checks it.
- **The `scripting` feature** (`/scripting`, PLAN §12.2-12.3, §15.5), on the Scripting bundle under the nonce class:
  a nonced `hx-get` whose answer's own nonce hx-csp rewrites, `hx-on`, a trigger filter and a `js:` value;
  `/scripting/live`, one password-rules widget in plain JavaScript, a hyperscript behaviour (`PasswordRules`, with
  hs-include sending its score to the server) and hx-live bindings; `/scripting/streams`, research 11 §2.2's
  matrix on SSE, a WebSocket and multipart; `/scripting/tt`, with Trusted Types. Every row is `.Nonce_Csp` and
  `.Lab_Host`.
- **The `compat` feature** (`/compat`): `/compat/htmx2` runs htmx 2-era markup on htmx 4 with htmx-2-compat (a 422
  left unswapped, implicit inheritance, htmx 2's event names), and `/compat/alpine` loads hx-alpine-compat with no
  Alpine and changes nothing; each on its own bundle. The lab mounts both, with nav entries.
- **`.Trusted_Types`**, a route flag: with `.Nonce_Csp`, `require-trusted-types-for 'script'; trusted-types htmx`,
  and the page loads no hyperscript (its `put` has no policy). Boot refuses it without `.Nonce_Csp`.
- **Boot check 6 covers the page bundles a profile's pages load**: `app.check`'s `page_bundles` (main's
  `PAGE_BUNDLES`, the scripting and compat packages' `BUNDLES` lines) must be embedded.
- **A feature's `static/*.js`** is appended to the profile's `app.js` (after `client/core.js` and the member's), as
  its CSS is to `app.css`: code that is no behaviour and runs under either client.
- **The stream drills** (PLAN §19.1.10): the `wsdata` kind (a socket whose `on_data` crashes closes 1011, through
  `guard.register_drill_handler`), `streamdrain` (500 SSE + 500 WebSocket clients and the slow, half-sent and idle
  peers: exit 0 within 6 s, 1012 and `retry:` for each) and `streamfd` (Linux: 3000 SSE streams under `ulimit -n
  4096`, `/livez` within 100 ms).
- **The TSan gate** (`sh tools/drills/tsan.sh`, Linux; PLAN §19.2.1): a `-sanitize:thread` build of the hub's,
  stream's, workers' and store/sqlite's tests, of lab under 200 SSE + 200 WebSocket clients and 200 publishes, and of
  skeleton under k6's `write` and `pages`, each through its drain; any report fails it. One suppression, core:nbio's
  mpsc assert (`tools/drills/tsan.supp`, S0.9). 0 reports.
- **The soak** (`sh tools/drills/soak.sh`, Linux; PLAN §19.1.8): lab for an hour with 2000 streams, k6's lab
  scenario at 10 VUs and a redeploy at half time; RSS and the open fds plateau in each half, the streams' queued
  bytes stay under 64 MiB, and all 2000 are back within 5 s. Lab's `/lab/stats` reports `queued` for it. Nightly,
  with the TSan gate (`nightly.yml`).
- **The lab through apollo's proxies, in CI** (`e2e-proxy`; PLAN §20.1, X26, X40): the lab's specs in chromium
  through the stack Caddy running the new `deploy/Caddyfile` (PLAN §20.4's block whole: the hosts, the redirect
  aliases, the 421 catch-all, the trusted gateway of the stack subnet 172.31.120.0/24), and through NPM's nginx in
  front of it (`tests/proxy/npm.conf`, as the NPM version apollo runs renders its proxy host). The e2e suite's proxy
  mode (`E2E_PROXY`, `E2E_UPSTREAM_PORT`) refuses to run unless the proxy's host resolves to the machine, and
  `proxy.spec` checks streams arrive as written, uncompressed, and a socket echoes. 84 passed through each, in WSL.
- **Autobahn|Testsuite, nightly** (PLAN §19.1.9, X24): its fuzzing client against the lab's WebSocket echo, sections
  1–7 and 10 (`tests/autobahn/fuzzingclient.json`); 247 cases, none failed (4 NON-STRICT: invalid UTF-8 in a
  fragmented message is refused at the message's end).
- **The generator, v1** (`tools/init` compose mode; PLAN §7.4, D26): `--list [--json]` (committed as
  `docs/catalog.json`, held current by CI), `--explain`, a new project from `--profile` and `--features` with the
  family flags (`--store`, `--identity`, `--client`, `--theme`), `--add` and `--without` on a profile in place, a
  family swap (`--store sqlite --profile lab`), `--dry-run`, and `--verify`, on by default: the plan built, tested and
  held to `tools/check` in a scratch copy before anything here changes. Features close over their imports and get
  one root; each feature's lines are taken from a committed profile that mounts it, and the platform's are written
  for the families. A refusal says what to do ("contacts has no memory store; use --store sqlite"). CI's
  `generator` job checks the catalog, composes every committed profile again (`odin test tools/init`), refuses a
  bad selection with nothing changed, and makes and verifies one feature alone, rotating with the run.
- **`tools/profile`** (M1's profile follow-up): `sh tools/profile/profile.sh <profile> <scenario> [--spall]` on
  Linux records the server under k6 with perf and writes the samples, folded stacks and the 30 heaviest functions
  (an SVG too, with FlameGraph's scripts), and with `--spall` builds a scratch copy with an instrumentation hook
  whose trace counts every call. The milestone exits' profiles come from it.
- **`tools/check topics` and `exts`** (PLAN §6.1, §19.2.1), in `all`: each TOPICS family is its feature's and
  declared once, every host's packages with TOPICS are named by its `hub.mount` and nothing it doesn't mount is, a
  profile with topics calls `hub.init`, and a literal `hub.publish` names a declared family; every mounted web package
  declares `EXTS`, and `BUNDLE_EXTS` and `PAGE_BUNDLES` name exactly the mounted packages with `EXTS` or `BUNDLES`.
  `routes` refuses a bare `-` after a literal in a pattern (Lua's lazy quantifier). The bad fixture trips each.
- **The client-stack specs** (PLAN §19): `csp-clean.spec` (every sitemap page, the picker, the gallery, the streams,
  the behaviours and the scripting and compat pages, with no violation; it takes over `security.spec`'s sitemap
  walk), `csp-enforced.spec` (an injected `hx-on` refused under the hash CSP; an injected, unnonced `hx-get` stripped
  in the nonce class), `harness-csp.spec` (what Playwright's own calls do under the CSP), `bundle-race.spec` (assets
  held 400 ms: the streams wire, `hx-ws:send` never navigates, hs-include arrives) and `streams-hxcsp.spec`; with
  `scripting.spec` and `compat.spec`, and load scenarios for every new route.

- **The `nick` identity** (`features/accounts/identity_nick`, PLAN §17.1, D35; ANSWERS round 9): a member of the
  `identity:` family. A visitor picks a nickname at `/login` and keeps it as a signed cookie
  (`nick=<id>.<name>.<expiry>.<mac>`, HMAC-SHA256, `HttpOnly; SameSite=Lax`, 30 days, renewed past half), with no
  account behind it. Clients in `LAN_CIDRS` are members (`ACCOUNTS_NICK_FROM=all` drops the check), clients in
  `ACCOUNTS_NICK_ADMIN_CIDRS` (none by default) are admins, anyone else a guest; `ACCOUNTS_NICK_KEY` signs (a boot key
  without it, which a warn line names). `/logout` forgets it. The identity contract gains `init`, which `app.boot` calls.
- **The layout's one `#live`** (§9.1, D14): `web.render_page(…, live = topics)` adds a page's topics to the viewer's own
  member rows (`hub.Topic.member`), and the hub writes the stream element; `/events` refuses a member row to anyone else.
- **`notify`** (`/notify`, PLAN §14.2, D36): the Inbox, live on every page of a member's over `notify.user:<id>`
  (the item into `#notify-list`, the count into every `.notify-count`), with `notify_web.send(user, kind, ref, html)`
  for producers, mark all read, and the hourly prune of read items past 30 days; the memory store keeps the newest
  200 per member.
- **`chat`** (`/chat`, PLAN §14.1, D30): public rooms on the memory store over four transports, chosen per request by
  `?transport=`, the member's Connection setting or `CHAT_TRANSPORT` (`x-impl: chat.transport=<t>`): a WebSocket
  (JSON in, a snapshot of the last 50 on each connect), the page's SSE stream with a POSTing composer, polling with
  hx-ptag (304 when nothing changed) and one long multipart response resumed by `HX-Last-Part-ID`. Every message is
  one escaped `<article>` swapped by upsert, so reconnects, snapshots and the author's own answer never double one.
  Presence (online, away after 10 s, gone after 5 minutes), typing (faded by CSS), edit and delete of one's own
  within 10 minutes (a tombstone), the message menu asked for per viewer, read receipts by POST when the newest
  message scrolls into view, unread counts per room on the rooms page, mentions into the Inbox, rooms made by members
  (100 in memory), 5 posts per 10 s per member (429 and a toast), and the lobby seeded. Off the LAN, `/chat` says chat
  is open there.
- **`bot`** (`/bot`, PLAN §14.3, D31): the house assistant on its mock. An answer streams on the asker's connection in
  four frames (the shell with Stop, the words, the markdown render with llama-shaped stats, the end), as an SSE answer
  to the form's POST (`hx:release` after the first words) or a multipart one (with `#usage` and `#conv-title`). The
  mock answers canned "under construction" lines word by word, seeded by `BOT_SEED` and paced by `BOT_DELAY_MS`.
  Stop ends an answer in well under 100 ms. Members keep conversations (50, each 200 turns), ask one at a time and 30
  an hour; guests get the mock, 5 an hour, kept by no one. e2e `bot.spec` and k6 `bot/bot.js`.
- **`ops`** (`/admin/ops`, PLAN §15.4): a 1 Hz panel for admins on the LAN: requests, streams, the hub and the process
  (resident memory, the loops' ticks), each with a server-drawn SVG sparkline of the minute, the modules' health, the
  limits and the last run's crash file. Rendered once a second and shared by every viewer, refreshed per request by
  SSE, by a poll with hx-ptag (304 while it has the render) or by multipart. `obs.requests_total`, `sys.rss_bytes`, and
  the hub's counters in `hub.numbers`; the hub and the bot report their health to obs.
- **`status`** (`/status`): a card per probe (each module's health, the loops, the process), filled by one
  `multipart/parallel` response, or every 30 s by a poll with hx-ptag; the details are an admin's.
- **`streams` through the proxies** (`e2e-proxy`): the job runs `lab` and `streams`, each through the stack Caddy and
  NPM's model (one proxy host with both domains); behind them the suite lets anyone take a nickname, since the server
  sees the proxy's container. 79 passed through each, in WSL.
- **The `streams` profile** (`app/cmd/streams/`, PLAN §7.1): home, notes, chat, notify, bot, ops, status, the nick identity and about,
  on the memory store, the vanilla client and the lite theme, with no SQLite library; in CI's check, build (four
  platforms, and without SQLite), e2e (chromium and webkit), k6 and drills jobs.
- **`Composer` and `AutoScroll`**, twinned behaviours (vanilla and hyperscript): Enter sends and a sent message clears
  the form, for a POST or a socket's send; a live log stays at its newest while its reader is there, and marks the
  reader's own messages. **`Expire`** (hyperscript only) removes a typing indicator after 5 s.
- **`web.Limit`** (§17.5): spark's fixed-window limiter, `web.limit_hit` and `web.respond_limited` (429, `Retry-After`,
  a toast), its keys bounded; chat and `/csp-report` use it. **`web.cookie`** reads one cookie (the parse is
  `authz.cookie`, which identities use too).
- **The hub**: a row's `watch` hears its keys' `/events` streams open and close (chat's presence), and a stream that
  subscribes on its own (`hub.subscribe`) gets multipart parts whose `HX-Part-ID` is the published rowid.
- **e2e and load for nick, notify and chat**: `e2e/tests/accounts/nick.spec.ts`, `chat/chat.spec.ts` (each transport:
  delivery once and escaped, edit and delete, and a server restart that costs a page nothing and doubles nothing),
  `notify/notify.spec.ts` (a mention live in the Inbox, unread counts, mark all read), with members in browser
  contexts of their own (`e2e/helpers/members.ts`); k6's `accounts/nick.js`, `chat/chat.js`, `chat/chat_streams.js`
  and `notify/notify.js`.

### Changed
- **The skeleton's binary budget is 3 MiB** (ANSWERS round 10; D38, PLAN §18.4), in CI's Windows size check and the
  drills: the fork's F-17 and M2's shared client code (`client/core.js`, the twins' dispatcher, `html.behave`) had put
  it 11 KB past 2.75 MiB. No SQLite OMIT flags, no re-encode.
- **CI covers lab** (PLAN §20.1): checked on its families, built on the four platforms (and without SQLite on Linux and
  Windows; no size budget of its own), its e2e specs in all three engines, its k6 quick run in the route coverage, and
  its drills in `linux-ops`.
- **An open stream holds 3 KiB, not 16** (the fork's F-17): its receive buffer is sized by kind, the scanner's buffer
  goes back at `stream_begin`, and the connection's arena once the handler returns. 4000 idle SSE streams took 68 MB
  over idle; now 12 MB (WS 20 MB), inside §18.4's 6 KiB a stream.
- **A ThreadSanitizer build gives each connection a heap-backed arena** (the fork's F-22): TSan doesn't see
  core:mem/virtual's raw `mmap`/`munmap`, so pages unmapped by one loop and mapped again by another read as a race
  on every reuse (about a hundred false reports a run). Every other build keeps `virtual.Arena`.
- **A WebSocket handshake under a placeholder origin** (a dev run with no `SITE_URL`) accepts an `Origin` naming
  the request's own `Host`, so a local run's pages can open their sockets; a deployment keeps the strict
  comparison with `SITE_URL` (D12 as built).
- **A job that runs every minute or more often logs its runs at debug** (the lab's 500 ms beat), not at info.
- **The lab sends the reporting header set** and mounts `/csp-report`.
- **The htmx-config files are per bundle** (`app/build/<p>/<bundle>.config.json`; Main's was `htmx-config.json`).
- **The test harnesses lift the per-client stream caps** for their servers (`e2e/helpers/server.ts`,
  `load-tests/run.sh`): one client opening hundreds of streams a minute is the suite, not a visitor.
- **The markup names its behaviours through `html.behave`**: the tab list, toasts, the search and filter boxes,
  range inputs and the forms that reset on success carry `data-behave="…"` (vanilla) where they had
  `data-reset-on-success`, `role="tablist"` handlers and class selectors. The vanilla `app.js` dispatches by that
  name, and the code both clients keep (the theme picker, count-up, the overlay's Escape) moved to `client/core.js`,
  which tools/bundle puts first in every profile's `app.js`. A toast now arms its own timer on
  `htmx:after:process` instead of a body-wide observer.
- **The lab runs on the hyperscript client.**
- **A handler's reads share one SQLite read transaction** (M1's profile follow-up): one WAL read lock a handler where
  every statement took its own, which the profile put at 13 % of a page; +2.1 % on `pages` on the Linux leg. A
  continuation reads outside it, and one left open by a crashed handler is rolled back at the next.
- **The header maps are reserved up front** (the fork's F-20): 16 each, so a request's and a response's usual headers
  fit without the map regrowing (3.7 regrowths a request before).
- **A response's nonce is base64url** (still 16 random bytes), so a page can send it in a connect URL as it is.
- **`core.js` and the vanilla twins clear an element with `replaceChildren()`**, not `innerHTML = ""`, which a
  Trusted Types page refuses.
- **The CSP sitemap walk moved from `security.spec` to `csp-clean.spec`.**
- **PHILOSOPHY.md's line and ledger** follow PLAN §3.3: htmx with its extensions, the odin-http fork, optional SQLite
  and optional _hyperscript; the ledger counts app.js, SQLite, _hyperscript, the fork, tools/bundle and the crash
  guard.
- **The unit tests build on `minimal`'s four families** (`.github/scripts/unit-tests.sh`): `platform/stream` reaches
  the family collections through `platform/web`.

- **`html.time_ago`** is the platform's ("just now", minutes, hours, days), shared by notes, notify and chat.
- **The sitemap leaves out a nav page a guest can't see or a crawler shouldn't index** (a route with a perm, or
  `.Private`): a member's Inbox, chat's rooms.
- **`--routes`, `--features` and `--limits` print only their answer**: boot's warnings (nick's boot key) are silenced
  for a listing, which scripts parse.
- **`tools/check`** reads a profile's family imports (`identity:.`, `store:…`) as `build.sh`'s line builds them, for
  mounts, inits, topic tables and `BUNDLE_EXTS`, and a TOPICS row's family may be a constant of its own package.
- **The test harnesses' servers count loopback as the LAN** (`LAN_CIDRS=127.0.0.0/8`), so a nick build's members can
  be made; e2e also fixes `ACCOUNTS_NICK_KEY`, so a nickname outlives a spec's restart. k6's summary reads a scenario's
  `held:no` submetrics where it gates only the requests that end on their own.
- **`minimal`'s root row's comment** reads "a card per feature", as the generator copies it into every profile with home.
- **The generator's identities** (PLAN §7.4): a new project is on `nick` unless it selects `scripting` or `compat`
  (then `anonymous`); nick brings `accounts` with its `/login` mount, `identity.EXTS` and the host's identity flag;
  `accounts` without its identity is refused with advice. The plan's bundle line follows composed `EXTS`, and its
  topics line a family named by a constant. `docs/catalog.json` lists chat, notify, accounts, nick and streams.

### Fixed
- **M2's audit** (`docs/audit/M2.md`, by an agent that didn't write the code: 0 CRITICAL, 2 HIGH, 9 MEDIUM, 5 LOW,
  5 NIT) is resolved but for two NITs (M2-18, M2-21: `TODO.md`); its Resolution section maps each fix to what holds it.
  A re-read of the fixes by a second such agent found eight more (M2-22 to M2-29: 1 HIGH, 2 MEDIUM, 3 LOW, 2 NIT), all
  fixed, and a second re-read three (M2-30 HIGH, M2-31 and M2-32 LOW), fixed but for a socket's part of M2-31. A
  third re-read found them sound, with nothing CRITICAL or HIGH open, and four more for M3 (M2-33 to M2-36: two LOW,
  two NIT, one fixed); every package M2's audit read carries its `Audited:` line (`5395ae0` or `5c5ebf2`), and those
  M2 changed outside its scope (the skeleton's and minimal's features, their profiles) say they are audit debt.
- **A WebSocket frame holds at most 256 `[` and `{`** (M2-30, HIGH): a raw line feed in a key ended the strict
  tokenizer's string but not the depth scan's, and the brackets after it overflowed a loop's stack. The scan refuses a
  raw control byte in a string, and the frame's brackets are bounded whatever a string is taken to be, since the parse
  can't nest deeper than that. Chat's socket answers a refused frame with a toast.
- **A chat cursor the room can't serve whole says so** (M2-31): a multipart resume past what the room let go replaces
  the log, and the SSE keyset replay resyncs, instead of looking continuous across the gap. **A held hub message costs
  192 B besides its HTML** against the rings' budgets (M2-32).
- **A WebSocket frame's JSON is parsed strictly** (M2-22, HIGH): core:encoding/json defaults to JSON5, whose comments
  and single-quoted strings hid brackets from M2-01's depth scan (one frame of `/*"*/` and 65,000 `[` still overflowed
  a loop's stack) and whose tokenizer recursed once per comment. The drills' `wsdata` sends all three kinds.
- **Budgets count what a stream is sent** (M2-23): `stream.sse_size` is what `sse_event` writes, and a line costs
  "data: " and a newline on top of its text, so a replay counts SSE frames and `hub.publish` refuses a message whose
  frame passes the backlog budget. One publish of 60,000 line feeds (420 KB as SSE) had closed every subscriber of its
  topic, and every reconnect again.
- **The hub's rings are kept in order of their last publish** (M2-24): the total budget takes the oldest at once and
  the sweep walks only the idle, where both walked every ring under the hub's lock; each ring costs 512 B against
  `HUB_RINGS_BYTES` besides its messages, or a million one-byte rings fit it.
- **Smaller edges** (M2-25 to M2-28): an IPv4 client a proxy reports as `::ffff:a.b.c.d` is keyed by its IPv4
  address, not a /64 every such client shared; a chat snapshot that had to drop messages replaces the log instead of
  leaving a gap behind what the page had; a handler that crashed before its loop opened a SQLite reader no longer
  leaves a read transaction for a continuation to begin; a crashed connection's 500 has a send deadline.
- **A WebSocket frame of deeply nested JSON no longer overflows a loop's stack** (M2-01, HIGH): `stream.ws_json`
  refuses nesting past 16 before `core:encoding/json` parses it; chat's socket and the lab's room decode through it.
  The drills' `wsdata` phase sends 60,000 `[`.
- **Two publishers racing no longer lose a live message** (M2-02, HIGH): the hub appends to the inboxes under its lock,
  in sequence order, so `deliver` never takes a message for one it has already passed.
- **A backlog no longer trips a stream's slow-consumer cap** (M2-03): a replay past half `STREAM_MAX_QUEUED` answers
  `resync`, and chat's socket and multipart snapshots keep their newest messages within it. A room of long messages
  had closed every socket to it.
- **The hub's memory is bounded** (M2-04, M2-07): a ring made again after the idle sweep starts at the hub's floor, so
  an old cursor gets `resync`, not a silent gap; `HUB_RINGS_BYTES` (64 MiB) bounds every ring together, the ring
  published to longest ago going first; `/lab/publish` and `/lab/close` are limited (`LAB_PUBLISH_PER_MINUTE`, 1,200
  a client; the harnesses lift it).
- **Per-member state is bounded** (M2-05, M2-06, M2-08, M2-11): presence and typing accept only a room that exists
  and drop a room's empty map; the memory stores' rings grow to their cap instead of starting there, and notify's and
  the bot's keep 4,096 members; `POST /bot/c` is limited to 10 a minute; a room keeps 256 read cursors; stream
  admission sweeps its clients once a minute at most, tracks 65,536, and keys an IPv6 client by its /64.
- **A POST stream's handler reads its own copy of the body** (M2-09): the fork's stream begin frees the buffer a body
  is a slice of, and a malformed `%` in a bot ask handed the handler that memory. Front copies a `.Stream` row's body
  into the request arena, and `form_decode` never returns a slice of its input.
- **A crashed handler's SQLite read transaction ends at the pulled reset** (M2-10): it had stayed open until the
  loop's next handler, so a continuation read a stale snapshot and the WAL could not checkpoint past it.
- **Crash and shutdown edges** (M2-12, M2-13): a continuation run inside its handler that crashes keeps its 500 (the
  fork's second crash call closed the connection under it); chat's continuations resume before they publish; the
  bot's last event releases the member's slot before it renders, so a crash there no longer locks them out.
- **Protocol edges** (M2-14, M2-15, M2-16): a HEAD to a stream route gets 405 and `Allow: GET` instead of a stream; a
  WebSocket handshake that admission refuses is a plain 429 or 503, without the 101's headers; the lab's `after` goes
  into its stream URL through `url_encode`.
- **One rule for "a path on this site"** (M2-17): `escape.site_path`, used by nick's `next` and notify's refs (which
  had admitted `//host`). Request numbers go through `parse_digits` (M2-19), and `tools/init`'s verify runs check's
  `imports` and `contracts` too (M2-20).
- **The drills' `streamfd` phase runs natively on Linux** (CI's `linux-ops`): it spawned `curl` from the repo root, which
  only worked when Windows drove WSL. Every profile's drills pass on both legs: Windows minimal 26/26, skeleton 28/28,
  lab 28/28, streams 25/25; Linux 24/24, 26/26, 28/28, 24/24, every budget met.
- **The hub's idle-ring sweep no longer aborts the server** (`free(): invalid pointer`, found by the 1 h soak and
  caught under gdb in `sweep_rings`). The sweep deleted from the rings map while iterating it, which can visit a ring
  it has already freed, and the map was keyed by the first message's topic string, which went with that message
  once the ring let it go, so lookups compared against freed memory and could add a second ring for the topic. Each
  ring now keeps its own copy of its topic as the key, and the sweep collects the idle rings before it deletes any
  (`ring_for`, `ring_sweep`; `rings_keep_their_own_topics` tests both).
- **`tools/init <name>` renames again.** Its token pass required the old live-demo URL somewhere, and the README's
  live-demo line, the last place that held it, is cut first, so every run stopped with nothing changed; no CI job
  ran init since the skeleton's `--minimal` one. The canonical origin is the brands' alone now, and the generator
  job runs init on every push.
- **An SSE stream gets its `retry:` event at a drain** (PLAN §8.7 step 3): `retry: 500–3000` (per client), as a named
  event, so the reconnects after a deploy spread out. The platform sent nothing there; the drills' `streamdrain` phase
  found it.
- **A shutdown never wakes a loop that has gone** (the fork's F-21). `server_shutdown` woke each loop from the main
  thread while the loops shut themselves down: it could write to a released loop's eventfd (freed, the descriptor maybe
  reused), and `serve` could free the threads under it. Now a loop about to release, and `serve` about to free, wait
  out the calls in progress, without a lock (it may run in a signal handler). store/sqlite's group-commit test released
  its loop before joining the writer that was still waking it. ThreadSanitizer found both (M2's gate).
- **A request that follows a stream on its keep-alive connection is read whole** (the fork's F-18). The stream's read,
  kept to notice the peer leaving, could take the start of the next request, which a client sends the moment the last
  chunk lands, and drop it: the server read that request from its middle (a 501) or waited for one already gone.
  About 1 in 300 rounds on a raw socket and 0.01-0.1 % of the requests after a stream under k6; 0 in 12,600 rounds
  since. `protocol.spec` keeps the check.
- **A shutdown no longer posts replies into loops that have left, and is bounded to the end** (M1-05): a write still
  on the writer when the loops released their event loops posted its reply into a zeroed loop (a SIGSEGV on Linux, a
  spin for good on Windows), and nothing bounded the store's close. The writer refuses writes once the drain starts
  (503), a loop marks itself leaving before it releases (the fork's `on_thread_release`), every cross-thread post goes
  through `workers.post`, which skips such a loop, and `app.shutdown` arms an exit at `DRAIN_DEADLINE_MS` + 1.5 s (70).
  The drills' `latewrite` phase checks both.
- **A SQLite reader that can't open fails its read, not the process** (M1-07): out of descriptors at the connection
  cap, a loop's first read called the store's boot-time `fatal` and exited 1; it answers `.Failed` (500) now. (Opening
  every loop's reader at boot instead cost 1.65 MB idle, past the budget, so readers still open on first read.)
- **A stalled log pipe no longer hangs the exits meant to end a hang** (M1-03): the watchdog and a dirty crash wrote
  their lines through the lock a blocked stderr write held, so a log reader that stopped hung the process for good.
  Both now write the crash file and arm their exit before they log, and their writes give up on the lock after
  250 ms. The drills' `logstall` phase stops reading the server's output: exit 70 about 8 s after the stall.
- **A client that stops reading is cut at `SEND_TIMEOUT_MS`** (30 s; M1-02): a send still in flight past it cuts the
  connection, as the drain does, where nothing had bounded it, so such a client held its descriptor and a copy of its
  response for good. The drills' `slowread` phase pipelines 100 requests for og.png and reads nothing.
- **Windows: `shutdown()` works on accepted sockets** (the fork's F-19). core:nbio set `SO_UPDATE_ACCEPT_CONTEXT`
  with no value, which Windows rejects, so the drain's cut of a stuck connection (F-9) did nothing there; the fork
  repeats the call with the listening socket.
- **A crash in a deferred response's continuation answers 500** (M1-04): a write's reply or a pool's result that
  trapped after `web.resume` had left the connection unanswered and open for good. `web.resume` now gives the guard
  an unwind, which a crash before `web.finish` runs: the fork's `response_crashed` answers 500 and closes, and the
  crash line names the request. The drills crash a continuation (`continuation`).
- **A crash in the request served after a stream ends is that connection's** (M1-26): 500 and a close, not a wedged
  connection; the drills' `streamcrash` phase checks it.
- **robots.txt no longer hides a page beside a family of fragments**: the lab's `/lab/feed`, `/lab/publish`, … had
  collapsed to `Disallow: /lab/`, which also covered `/lab/streams`. A family collapses to its first segment only when
  no page lives under it; `seo.spec` checks that no Disallow covers a sitemap page.
- **M2's first CI run**: three jobs failed. `docs/catalog.json` was behind the tree (accounts' and chat's line
  counts, lab's `init`); the `generator` job holds it current. The lab's close-code specs failed on WebKit on Linux,
  whose libsoup takes 1012–1014 for protocol errors and hands the page 1006 (hx-ws reconnects on that as well); the
  specs expect 1006 there. The bot's Stop spec read 123 ms on CI's WebKit, against 5–9 ms idle: four workers on a
  4-vCPU runner put the page's clock behind. It now holds the best of up to three Stops to 100 ms, and every Stop to
  ending its answer.
- **Chat: an open edit form survives its message being rendered again.** The menu and edit form open in a slot inside
  the message, and every re-render (the author's own echo, the poll transport's next answer up to 2 s later, an edit
  from another tab) replaced the whole message, slot and half-typed edit with it: CI's WebKit lost the form to the
  poll's answer on both tries. The slot is now `hx-preserve` (a tombstone's isn't, so a deleted message drops its
  menu), and a saved edit closes its form with its answer's empty main swap. `chat.spec` edits a message from a
  second tab while the first has its form open, on every transport.
- **Linux: work a loop queues for itself no longer waits for an unrelated event** (the fork's F-23). core:nbio's
  Linux tick ran the callbacks queued before it began and then waited on the kernel with no timeout, even when they
  had queued more (a next_tick, a 0 ms timeout): that work ran only after the loop's next unrelated event, on a quiet
  loop the next 1 s timer. The bot's mock at `BOT_DELAY_MS=0` took about 460 ms a word, which failed CI's first k6
  coverage run; Stop on its generation's own loop, the hub's delivery to the publisher's own loop and a stream's
  first buffered bytes took the same path. The serving loop now ticks with 0 while work is queued, as nbio's
  Windows and posix ticks already do; `queued_work_runs_without_waiting` took 4.9 s on Linux before, 1 ms after.

## [2.0.0] - 2026-10-26

The repo becomes **odin-htmx-starter** (the plan: `docs/PLAN.md`; its M0 spikes: `docs/spikes/`), and this is
its first milestone, M1: the request path rebuilt as a platform (`app/platform/`),
features (`app/features/`) with a store per family (`app/stores/`), and two profiles (`app/cmd/`): `skeleton`, the
1.2.x console at its exact URLs, and `minimal`, the one-page notes starter. Behind them: the vendored odin-http fork
(F-1 to F-16), a crash guard, logfmt and metrics, store v3 (per-loop readers, a group-committing writer task),
`tools/check`, CI through `build.sh`, crash drills and the parity gate (`docs/perf/PARITY-M1.md`: PASS on both legs, 20
of 20 cells each, against v1.2.0 and v1.1.1).

**Breaking, for a fork of 1.2.x:** `app/src` is gone (its code lives on as the `skeleton` profile's features); a
profile is built through `build.sh`/`build.bat <profile>`, never `odin build` directly; `tools/init --minimal` is
gone (the `minimal` profile replaces it); the access log is logfmt; the Docker image takes `--build-arg PROFILE` and
ships `/app/server`; a crash that touched shared state exits 70, a boot problem 2. A 1.2.x database is adopted in
place by the skeleton's contacts store (its first three migrations keep their hashes).

### Added
- **The fork's changes to odin-http** (`app/vendor/odin-http/UPSTREAM.md` lists each, F-1 to F-16;
  F-3 waits for video): streams for SSE, WebSocket and multipart on the HTTP port; an `invoke` hook
  every server-owned callback runs through, so a crash guard can contain a crash in a handler, a stream
  or odin-http itself; idle, header and body timeouts, enforced by one 1 s sweep per thread rather than
  a timer on every read (per-read timers cost 2–4 % on the lightest route); a connection cap that
  answers 503 instead of stalling at the open-file limit; a shutdown bounded at about 5.6 s with
  streams, slow and stuck peers open; SIGTERM as well as SIGINT; a per-thread `date` header (the shared
  one tore under readers); a 3 s bind retry; and deferred responses, whose generation check drops a
  worker's reply to a connection that has gone. The skeleton app takes the new defaults through
  `Default_Server_Opts`. Spikes S0.2, S0.3, S0.5, S0.6 and S0.7 measure and drill them.
- **`THIRD_PARTY_NOTICES`**: the notices of what the binaries contain (odin-http's MIT, Odin's zlib, the
  Unicode data tables' licence) and credits for htmx and SQLite.
- **`tools/bundle`** (prototype, spike S0.10): builds a profile's htmx bundles, with br and gzip, from
  the extensions its packages declare. **`tools/baseline`** (spike S0.1): rebuilds a skeleton release
  from git for the parity gate.

- **The starter's platform packages** (`app/platform/`, milestone M1), each checked alone on Windows,
  Linux and macOS and unit-tested on both legs: `sys` (the OS layer under the crash guard, the
  open-file limit, a fast clock), `ext` (the htmx extension table, moved from `tools/bundle`'s
  fixture), `escape` (the injection boundary: `w esc url_encode json_esc`), `sqlite` (the binding;
  every call marks the thread as inside SQLite), `guard` (crash containment: a crash that touched
  nothing shared answers 500 and serving goes on, any other drains and exits 70; a watchdog turns a
  stalled loop or a stuck lock into an exit), `obs` (logfmt lines in per-thread buffers, request ids,
  per-thread counters, module health and declared limits), `env` (the typed environment table),
  `authz` (roles, permissions and the identity contract, with the default anonymous identity),
  `store` (what every store shares), `markdown` (a safe Markdown subset from spark, with input and
  nesting caps) and `workers` (bounded pools that answer on the submitting loop, and a job
  scheduler); and the two store families: `store/sqlite` (store v3: a writer task that commits every
  loop's queued writes in one transaction, a read-only connection per loop, `MEMMODE`, `--backup`,
  and a migration runner per feature that adopts a skeleton database, 709bc94's or v1.1.1's, without
  re-running anything) and `store/memory`.
- **The `skeleton` profile** (`app/cmd/skeleton/`): the skeleton's console rebuilt from features on
  the starter's platform, at its exact URLs. `contacts` (the table, the drawer, search, the JSON API,
  on SQLite: store v3, whose writes commit on the writer task in batches and answer through a
  deferred response), `dashboard` (its root page and the ping), `gallery` (components, forms, the
  /ui fragments) and `about`. Every page answers as 1.2.x's did, byte for byte but for the asset
  hashes; the 1.2.x e2e suite passes against it. `./build.sh skeleton` after prepare.
- **The `minimal` profile** (`app/cmd/minimal/`, its four hand-written files): the smallest
  starter, with the features `home` (the root page, showing the profile's home cards), `notes` (its
  models, domain, views and web packages, a store in each family, and a conformance suite that runs
  both) and `about`, on the memory store, the lite theme and the vanilla client. No SQLite reaches
  its build. `./build.sh minimal` after prepare.
- **`perf-floor` waivers** in `tests/parity-waivers.txt`: a cell Alex accepts below the parity gate's 0.97 at its
  measured level passes at the line's bar, with its reason; the other two rules stand. The first is Linux
  `write@mem` at 0.93 of HEAD (ANSWERS round 6).
- **`build.sh` / `build.bat <profile>`** at the repo root: the one place a profile's build flags
  live (its store, identity, client and theme collections, `-vet -strict-style
  -warnings-as-errors`, `VERSION`), with `CMD=check|test|run`. The starter's profiles (`minimal`,
  `skeleton` first) build only through it. `ols.json` moves to the root and names the four
  collections, on `skeleton`'s families for now.
- **The test suites follow the profile.** e2e specs live per feature (`e2e/tests/<f>/`) and load
  scenarios too (`load-tests/scenarios/<f>/`), each tagged with every feature it touches (`@contacts`,
  or `@contacts-sqlite` for one family member). Both drivers build the profile through `build.*`, ask
  the binary what it mounts (`--features --json`, which now names the store family too) and run what
  fits: `E2E_PROFILE=minimal npm test`, `PROFILE=minimal ./run.sh`. The skeleton's 23 specs are ported
  (`skeleton` runs them in three engines and the `api` project, `minimal` in chromium), with the
  minimal starter's home and about specs and a notes spec beside them.
- **Route coverage from request counters.** Every server either suite starts leaves its per-route
  request counts (`app_http_requests_total`, read through a per-run `/metrics` bearer) in
  `app/build/coverage/{e2e,load}/<profile>/`; every route of both profiles is reached by both suites.
  `tests/parity-waivers.txt` holds the waivers of either parity rule, each with its reason: today the
  three `:memory:` cells S0.4 gates against HEAD.
- **e2e and load coverage for every route**: `ops.spec` checks `/livez`, `/readyz` (with `?detail`),
  `/metrics` (the bearer, the per-route counter) and `/licenses`, and an unset ownership token's 404;
  new load scenarios `ops`, `ping`, `gallery`, `home` and `about` reach the routes the skeleton never
  load-tested (14 of its 26).
- **`load-tests/run.sh --parity`**: the parity gate's procedure (PLAN §18.2) in the load harness,
  from spike S0.1's loop: it builds the baselines into `perf/baseline/`, writes
  `perf/results/<version>-<leg>.csv`, and `lib/parity.mjs` applies the pass rule with each cell's
  reference (HEAD on the light routes and on a waived cell, max(HEAD, v1.1.1) elsewhere).

- **`tools/check`**: what the compiler can't hold a profile to, read from the source with no build
  (`odin run tools/check -- all`): `imports` (PLAN §5.1's table: layers, the feature package shapes, the
  collections, odin-http only in `platform/web`), `profile` (every imported web package mounted and its `init`
  called, mounts named by their feature, a `migrate` line for every SQLite store the build reaches, no unmounted
  `ROUTES`), `routes` (per host: rows inside their feature's prefixes, no router key claimed twice, one root,
  written in the profile), `contracts` (every store states its feature's contract, every identity
  `authz.Load_Viewer`) and `parity` (every route reached by both suites, or waived with a reason). A bad fixture
  trips each. Feature READMEs list their prefix exceptions (D9), the skeleton's exact URLs among them.

- **CI for the profiles** (PLAN §20.1): `pins` (Odin, htmx, SQLite, odin-http and Playwright agree
  wherever they're pinned), `check` (`tools/check`, every profile on its own families, every store
  alone, the unit tests with bad memory fatal), `build` (`minimal` and `skeleton` × Linux amd64 and
  arm64, macOS, Windows, `-o:speed`, tests, smoke, Windows size budgets; `minimal` with no SQLite
  library), `e2e` (`skeleton` in three engines, `minimal` in chromium, with `E2E_PROFILE`),
  `coverage` (a k6 quick run per profile, then `tools/check parity`) and `docker`. One
  `setup-odin` action installs the pinned Odin per runner. `prepare.*` take `NO_SQLITE=1`.

- **The request-path drills** (`tools/drills/drills.mjs <profile>`): a `-define:TEST_ROUTES=true`
  build mounts `/__test/crash/<kind>` (panic, bounds, div, nil, stack, lock, async, hang, and
  `sqlite` where the store is SQLite) and `/__test/shutdown`; the driver checks pure crashes answer
  500 with 20/20 bystanders served, dirty ones exit 70 within 6 s, the recovery burst, the watchdog
  (exit 70 in 10 s, naming the route and request), 10k malformed requests, the shutdown bound with
  slow, half-sent and idle peers (exit 0 in 5.6 s), restart after `kill -9`, the fd ceiling under a
  ulimit, and the budgets; the release build answers 404 there. CI's `linux-ops` job runs it per
  profile, and a nightly workflow runs e2e and a k6 quick run against an ASan build. `E2E_BUILD_FLAGS`
  and `run.sh`'s `BUILD_FLAGS` pass extra odin flags.

### Fixed
- **One client could stop the server with a chunked body of tiny chunks** (CRITICAL, M1-17, found by the M1
  audit's re-read and confirmed: 12,000 one-byte chunks overflowed a Windows loop's stack). odin-http scanned
  each buffered token one call deeper than the last; a scan asked for from a scan callback now waits for the
  callback to return (the fork's F-16). Chunk framing also counts against the body cap, chunk lines are at most
  4 KiB and end in CRLF only, and a broken trailer is an error, not the end of the body (M1-18..M1-21, M1-24).
- **A client's malformed request no longer logs at warn or error** (M1-22): the fork's parse and send failures log
  at info, and a log value's control bytes (C0, DEL, C1) and bytes that aren't UTF-8 are written as `\xNN`, so
  nothing a client sends reaches a terminal as an escape sequence (M1-29).
- **`CMD=test build.sh <p>` fails on a leak**, as the unit tests do (M1-28).
- **One client could stop the server with chunked request bodies** (CRITICAL, found by the M1 audit,
  `docs/audit/M1.md` M1-01). odin-http's chunked decoder asserted on chunk data not followed by CRLF
  and on any trailer field, on every route (a response drains an unread body); the guard contained
  each as a crash, so about 101 a minute tripped the burst rule and the server exited. The fork's
  F-14 answers 400 instead, discards trailers under a cap and parses chunk sizes strictly; the drills'
  malformed set carries those requests now.
- **A write batch that crashed was answered as committed** (M1-06): its ops now answer 500 while the
  process drains.
- **odin-http's own log lines were discarded** (M1-08): the server's threads log through `obs` now,
  F-8's accept errors and F-12's io_uring hint included.
- **Boot takes 12–17 ms again on Windows, not 170–180.** The ephemeral store's sweep for files a dead
  process left listed the whole temp directory (3,900 entries here); the files now live in an
  `odin-htmx-starter/` directory of their own. The sweep also asks the OS whether each file's process
  still runs (`sys.process_alive`): on Windows it had assumed a live server's files can't be deleted,
  and two servers booting at once proved otherwise (`disk I/O error` at `journal_mode=WAL`).
- **`--limits` prints the store's rows** (`DB_PATH`, `SEED`, `MEMMODE`): `store_sqlite.init()`
  records them before `app.check` answers the CLI. A bad value there now stops boot with the other
  boot problems (exit 2) instead of at the store's open (exit 1).
- **`CMD=test build.sh <p>` reports no leaks**: the boot checks' tables, which a server keeps for
  its life, now live in an arena the test destroys (about 150 leak lines per run before). The
  skeleton's tests also cover the router.
- **A watchdog exit's crash file names the stalled request**: it was written from the watchdog's
  thread, which has no request of its own, so it said `route "", request` with nothing after.
- **`OPTIONS *` with a negative `Content-Length` no longer aborts the process.** 1.2.1 refused a bad
  `Content-Length` in `front`, but odin-http answers `OPTIONS *` itself; the fork's `_body_length`
  now takes plain digits within `int` only (F-6), for every request.
- **A request body cut off part way closes its connection.** odin-http marked the body read before
  scanning it, so after the 400 the connection stayed alive with the rest of the body unread on the
  wire; a body-phase timeout now closes it (found by spike S0.7's timeouts phase).

### Changed
- **Faster responses** (the fork's F-15, from a profile of the write path behind the parity gate):
  header values are written whole rather than rune by rune, header lookups skip a lowercased copy
  of a key that's already lower case, the platform sets its own headers without one, and a store
  write's deferred response no longer polls its socket while it waits for the batch (F-13's watch is
  now optional, for work that takes seconds). `write@mem` went from about 32.7k to 37.2k rps on the
  dev PC, level with v1.1.1.
- **The size and memory budgets** (PLAN §18.4; ANSWERS round 7): binaries are budgeted in MiB, as CI's size check
  reads them (`skeleton` ≤ 2.75 MiB, `minimal` ≤ 1.5 MiB, up from 1.0 MB), and idle memory as 6 MB plus 0.4 MB per
  event loop (12.4 MB at the default 16). The drills check the same figures; the idle budget is measured at 16
  loops and gated on the dev PC, while a CI runner reports its figure and its makeup (ANSWERS round 8).
- **Stricter builds**: `build.{sh,bat}`, CI's store checks and the unit tests add `-vet-cast
  -vet-semicolon -vet-tabs -vet-using-param -disallow-do` to `-vet -strict-style
  -warnings-as-errors` (PLAN §19.2.4); the tree passes them with no change.
- **Less work per request** (the same profile, on the Linux leg): the request id is formatted by
  hand instead of through `fmt`, the access log's hashed client id is computed only when the line is
  written (it was computed at `LOG_LEVEL=warn` too), and the router tries only the rows of the
  request's method, comparing a literal row's path instead of running its pattern; the other
  methods' rows are tried only on a miss, for the 405's `Allow`. The writer task runs `BEGIN
  IMMEDIATE` and `COMMIT` from its statement cache instead of parsing them for every batch.
- **The access log is logfmt**, one line per request with a request id, the route as registered,
  the status, the time in µs and a hashed client id (`ev=req id=… m=GET route="GET /data" st=200
  us=183 …`); still never the query. Every response carries `x-request-id`.
- **robots.txt is derived** from the routes marked as fragments: the same paths are disallowed,
  with a single route kept exact (`/api/search`, `/forms/submit`).
- **SQLite is built with the starter's flags** (`prepare.*`, spike S0.11): no double-quoted string
  literals, foreign keys on by default, multi-thread mode, no global memory statistics (a sorting
  query on 16 connections ran 4.1× faster without its mutex), no extension loading, no shared cache,
  and FTS5. `vendor/sqlite/.flags` records them, so changing them rebuilds the library. On Windows
  prepare falls back to clang with llvm-lib when MSVC's `cl` isn't on PATH.
- **The template is `alexh95/odin-htmx-starter` now** (the repo was renamed; the old URL redirects).
  `BRAND_REPO` points there, and `tools/init` reads the template's repo from one file, `tools/init/UPSTREAM`,
  instead of a literal of its own: a future rename is that line plus `brand.odin`'s, in one commit.
- **odin-http is vendored in-tree** at `app/vendor/odin-http/`, replacing the `app/odin-http` git
  submodule: laytan/odin-http `fac113f` as published, package files only, with an `UPSTREAM.md` that
  names the base commit and will list every local change (decision D11 of the starter's plan,
  `docs/PLAN.md` §8.1). A plain clone now builds; `prepare.*` no longer touches git, CI checks out
  without submodules, and `.dockerignore` keeps `app/vendor/odin-http` in the build context (it now
  leaves out only `app/vendor/sqlite/`). Imports read `"../vendor/odin-http"` from `src/` and
  `"../../vendor/odin-http"` from `src/controllers/`, in the `--minimal` starter's files too.
- **`run.*`, the Dockerfile and `tools/init` build through `build.*`.** `app/run.sh`/`run.bat` build
  and serve a profile (`PROFILE`, `skeleton` by default; `DB_PATH=data.db` only for a SQLite build).
  The image builds one profile (`--build-arg PROFILE=…`) and ships it as `/app/server`. `tools/init`
  renames every profile's brand (`app/cmd/<profile>/brand.odin`) instead of `app/src`'s.
- **`load-tests/run.sh` skips a port something already listens on**: on Windows a second server
  binds it without an error, and k6 measured WSL's relay instead (a 100 % failed `notes` run).

- **The docs describe the starter**: CLAUDE.md (the layers, features, families, the request path,
  store v3, the crash zones, recipes for a feature, page, endpoint and profile), README, app/README,
  docs/DATA.md (the store families and the backup runbook), and the e2e and load-tests design notes.

### Removed
- **Three procedures with no caller** (`web.count_and_log`, `store_sqlite.query_drain`, `app.profile`), found by
  the M1 audit's `-vet-unused-procedures` triage.
- **docs/STRIP.md and docs/DATA_IMPL.md**: stripping the demo is choosing a profile now, and the
  skeleton's SQLite implementation plan is done and superseded by PLAN §11.
- **CI's `minimal` job**, which ran `init --minimal`: the `minimal` profile builds and tests in `build`
  and `e2e` instead.
- **`app/src`**, the skeleton's single-binary app: the `skeleton` profile serves it now, at the
  same URLs, and the `minimal` profile replaces `init --minimal`, so the `--minimal` overlay
  (`tools/init/minimal/`, `strip.odin`) is gone too.
- **`load-tests/parity.sh`**, the grep for route paths, replaced by the request counters.

## [1.2.1] - 2026-10-25

The skeleton's last release (tagged on 2026-10-26; branch `skeleton-1.x` carries it): one fix for a
request that could abort the whole server.

### Fixed
- **One request with a bad `Content-Length` no longer takes the whole server down.** odin-http
  reads the header with `strconv.parse_int`, which takes a sign and `_` separators and wraps past
  64 bits, and checks it only against the cap. So `-5`, or `9223372036854775808` (it wraps
  negative), reached an `assert(n >= 0)` in its scanner and aborted the process, with every
  connection on every thread, from one unauthenticated request. `front` now answers any value
  that isn't plain digits within `int` with 400 and closes the connection. The check runs before
  anything else can answer: after *any* response on a keep-alive connection odin-http drains the
  unread body itself, so a GET, a HEAD, the `*.fly.dev` 301 and the cross-site 403 crashed too.
  `parse_id` and the new check share one overflow-checked `parse_digits`. nginx (and
  nginx-proxy-manager's build of it) and Caddy refuse such a header with 400 themselves, so the
  exposure was a port reached without one: `deploy/docker-host`'s `HOST_PORT`, a LAN.
  - **`Expect: 100-continue` goes through `front` too** (`auto_expect_continue = false` in
    `main.odin`). odin-http's own handling read the body unchecked, and it never ran the handler
    either: the client got the 100 and then nothing. curl sends the body after its one-second
    wait instead.
  - **Still open:** odin-http answers `OPTIONS *` itself, so that request never reaches `front`,
    and a negative length on it still aborts the process. Only a fix in odin-http closes it
    (`TODO.md`).
  - **e2e:** `limits.spec.ts` sends the raw headers over a socket (`raw` in `helpers/server.ts`)
    to a server of its own, and checks `/healthz` still answers after each.

## [1.2.0] - 2026-10-15

The skeleton's last feature release, tagged at `709bc94` with no code change on 2026-10-26, so that
it stays exactly the build the starter's parity gate measures (with 1.1.1). Since 1.1.1: the
2026-10-07 review fixes (#46–#49) joined up, security headers and a strict CSP, cross-site writes
refused, body caps, 405s and a 404 page, a request log, `--backup`, migrations checked by hash, 422s
that keep the form, an init that plans every edit and aborts on any miss, lists filtered, sorted,
paged and counted in SQL, and CI that pins and verifies Odin.

### Changed
- **The review fixes, joined up.** The fixes for #13–#44 landed as four PRs (#46–#49) that each
  owned different files, and these are the seams between them:
  - **e2e:** the new `backup`, `canonical` and `ops` specs start their servers through
    `helpers/server.ts`'s `startServer`. That's OS-assigned ports with a pinned env; no fixed port
    bases are left. `Server` gains `output()`, so a spec can read the start-up banner.
  - **The `api` project:** it now takes every browser-less spec (`backup`, `canonical`,
    `dashboard`, `events`, `ids`, `limits`, `ops`, `persistence`, `routing`, `seo`, `writes`), and
    the `minimal` job runs it too. The specs shared by the demo and the starter keep running
    against the starter.
  - **The `minimal` job** verifies the Odin tarball's SHA-256 and shares the e2e shards' cache of
    `prepare`'s outputs. `init` now removes the job by structure, so it no longer has to stay
    byte-identical.
  - **`deploy` waits for the Docker job**, so an image that builds but won't run never ships.
  - **Builds name themselves:** CI, the Dockerfile and the Fly deploy pass `-define:VERSION=<commit>`,
    which the `x-version` header and `/healthz` report; a local build says `dev`. The Dockerfile
    declares `VERSION` after `prepare`, so a new commit doesn't re-run it. CI also runs the new unit
    tests (`odin test src/repository`, `src/views`) on all three OSes.
  - **`init --minimal`** also deletes the demo's `0003_contact_notes.sql`, and its `scale` load
    scenario, which grows the contacts table and so 404s in the starter. init also drops
    `fixtures.ts` and `helpers/server.ts` from its rename list, since neither names the project
    any more.
  - **Load runs** set `PORT` explicitly (the server prefers it over argv) and default to
    `LOG_LEVEL=warn`, so the new access log doesn't skew comparisons with older results.
  - **`scale` has its own latency budget** (`SCALE_P95`/`SCALE_P99`, default 3 s/6 s). At 20k rows
    it is bound by the one store lock (p95 ≈ 0.7–1.2 s under 20 VUs), so the suite's 50 ms budget
    failed every run and would have made `run.sh --strict` unusable.
  - **`fly.toml`:** its `SITE_URL` comment points at `canonical_host`'s new home in
    `controllers/middleware.odin`.
  - **`TODO.md`:** gains the review's leftovers, grouped by area.

### Added
- **CI builds and runs the Docker image on every PR** ([#37](https://github.com/alexh95/odin-htmx-skeleton/issues/37)).
  Until now only Fly's builder built it, after the merge. The new `docker` job (host runner) starts
  it through `compose.yaml` under the io_uring seccomp profile and waits for its `HEALTHCHECK`. It
  then curls `/healthz` and `/`, checks it runs as UID 10001, and requires `docker stop` to exit 0 in
  under 3 s. Last, it creates a DB on a fresh `/data` volume as that user.
- **CI checks that the version pins agree** (part of
  [#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44)). `.github/scripts/check-pins.sh`,
  run first in the build job's Linux leg, fails if the `Dockerfile`'s `ODIN_VERSION`/`ODIN_SHA256`,
  `ci.yml`'s env, the three matrix asset names and the linux digest disagree. It also fails if a
  Playwright image tag differs from `@playwright/test` in `e2e/package-lock.json`. Sweeps used to
  check these by hand.

### Changed
- **CI's apt step switches to HTTPS mirrors when the runner's mirror won't answer** (part of
  [#36](https://github.com/alexh95/odin-htmx-skeleton/issues/36)). The 1.1.1 retry loop wasn't enough:
  both master runs after it timed out in the same step. Two attempts against
  `azure.archive.ubuntu.com` used up the 10-minute budget, so neither run deployed.
  - **Why another mirror:** every failure that day was a plain-HTTP (port 80) fetch from a
    Playwright container. HTTPS downloads in the same jobs (npm, the Odin tarball) worked, and the
    azure mirror has no HTTPS.
  - **What the script does now:** `apt-install.sh` tries the configured mirror once, then rewrites
    every Ubuntu source (both the one-line and the deb822 format) to HTTPS. Canonical's own
    `archive`/`security.ubuntu.com` comes first, then `mirrors.edge.kernel.org`.
  - **Faster attempts:** in-apt timeouts are 15 s with one retry, so a dead mirror fails an attempt
    quickly.
  - **Timeouts:** apt steps now get 15 min and jobs 25.
  - **Tested** locally against stub `apt-get`s that accept only one of the two fallback mirrors,
    through the `APT_SOURCES` override.
- **CI runs with a read-only token, and a new push to a PR cancels the old run** (rest of
  [#36](https://github.com/alexh95/odin-htmx-skeleton/issues/36)). `permissions: contents: read` is set
  for the whole workflow; no job needs more, the deploy included (it uses `FLY_API_TOKEN`). Branch
  pushes get a concurrency group per run, so they are never cancelled or queued.
- **CI runs on `main` as well as `master`, and deploys from the repo's default branch** (part of
  [#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44)). A fork that renamed its default
  branch used to lose CI and its deploy without a word.
- **The Odin download is checked against its SHA-256** in CI and the `Dockerfile` (part of
  [#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44)), like htmx and SQLite already were.
  The release's published digests sit next to `ODIN_VERSION`: `ODIN_SHA256` in `ci.yml`'s env and
  the `Dockerfile`, and one `odin_sha256` per build-matrix asset. The build job's Odin cache key now
  includes the digest.
- **Browser-less e2e specs run once, not once per engine** (part of
  [#42](https://github.com/alexh95/odin-htmx-skeleton/issues/42)). `events` and `persistence` never
  open a page, so they're now the `api` project in `playwright.config.ts`, which CI runs on the
  chromium shard. A full local run is 215 tests (71 per engine + 2), down from 219.
- **e2e shards no longer compile SQLite on every run** (part of
  [#43](https://github.com/alexh95/odin-htmx-skeleton/issues/43)). They cache `prepare`'s outputs
  (`htmx.min.js`, `app/vendor/sqlite`), keyed on `prepare.sh` (the pins and compile flags) and the
  image's distro, and `global-setup` skips `prepare` on a hit. That saves about a minute per shard.
  The build job still runs `prepare` from scratch on all three OSes. The Odin cache keys stay as
  they are: the containers write gzip archives and the host zstd, so one entry can't serve both.
  `ci.yml` also notes how a private fork can drop the macOS (10×) or Windows (2×) leg.

### Fixed
- **`docker compose up` can start the server** ([#38](https://github.com/alexh95/odin-htmx-skeleton/issues/38)).
  odin-http's event loop needs io_uring, which Docker's default seccomp profile has blocked since 25.0,
  so the root `compose.yaml` aborted at startup. New `docker/seccomp-io-uring.json` is Docker's default
  profile plus `io_uring_setup`/`_enter`/`_register`, and `compose.yaml` runs under it. The requirement
  is noted in the `Dockerfile` and `compose.yaml`.
- **The container stops cleanly, runs as non-root and reports its health**
  ([#39](https://github.com/alexh95/odin-htmx-skeleton/issues/39)).
  - **`STOPSIGNAL SIGINT`:** the server only handles SIGINT, so `docker stop`'s SIGTERM was ignored
    by PID 1 and every stop waited 10 s for a SIGKILL, skipping `repo_close`.
  - **`USER 10001`:** `/data` is created owned by it, so a fresh volume there is writable.
    **Upgrading:** a volume that already holds root-owned files (apollo-11's `odin-htmx-data`), or a
    Fly volume, needs a one-time `chown -R 10001:10001` on it before the new image can open the DB.
  - **`HEALTHCHECK`** on `/healthz`, through bash's `/dev/tcp`, so it adds no package.
- **e2e servers can't pick up the wrong port or your `data.db`**
  ([#41](https://github.com/alexh95/odin-htmx-skeleton/issues/41)). Every server the suite starts
  now goes through `helpers/server.ts`. It takes a port the OS picks, not a fixed base, which two
  runs at once could share; on Windows the second server binds a taken port silently, so a stale
  build got tested. It also pins the env (`PORT`, `DB_PATH=:memory:`, an empty `BIND_ALL` and
  `SITE_URL`), and fails fast with the server's own output if it exits. `persistence.spec.ts`
  restarts on a fresh port. Checked by running the suite with `PORT`, `DB_PATH`, `SITE_URL` and
  `BIND_ALL` exported: it passed, and the exported `DB_PATH` was never created.
- **e2e's `global-setup` no longer hides a failed `prepare`** (part of
  [#42](https://github.com/alexh95/odin-htmx-skeleton/issues/42)). It used to warn and carry on, so
  the build could link a stale SQLite or fail later with a less useful error. It now skips `prepare`
  when htmx, the SQLite stamp and a newer library already match `prepare.sh`'s pins, so a re-run on
  Windows needs no MSVC prompt. When `prepare` does run, its failure stops the suite.
- **Stale notes in the e2e docs, `ci.yml` and the `Dockerfile`** (part of
  [#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). `e2e/PLAN.md` described 31 tests in
  six files run by a `serve.mjs` launcher, and its CI section described a browser install the CI
  doesn't do. `e2e/README.md` left out `seo` and `responsive`. Both said CSS is served from disk.
  The `Dockerfile` header spoke of on-disk static assets, and `ci.yml` of "the planned SQLite layer".
- **The minimal starter covers every endpoint in both suites**
- **The minimal starter's write path and `/about` are in both suites**
  ([#27](https://github.com/alexh95/odin-htmx-skeleton/issues/27)). `init --minimal` now also installs
  a `POST /notes` load scenario (`notes.js`) and an `/about` e2e spec. The spec checks that the page
  renders as the current nav item, that the nav reaches it with a boosted swap, and that its repository
  link matches the JSON-LD. The starter's `pages.js` now loads `/about` as well as `/`.
- **The social card has a source: `tools/og/og.html`**
  ([#28](https://github.com/alexh95/odin-htmx-skeleton/issues/28)). `og.png` was a bare image showing
  the upstream's name and domain, with no way to redraw it. The 1200×630 HTML recreates it, and its
  header has the one-line re-render through the Playwright the e2e suite already installs
  (`npx playwright screenshot`), so there's no new dependency. `init` writes the fork's wordmark,
  name and domain into it.
- **`init --minimal` starts the fork's own CHANGELOG and TODO**
  ([#29](https://github.com/alexh95/odin-htmx-skeleton/issues/29)). The 700-line upstream changelog
  and 260-line backlog were left in place, and `CLAUDE.md` tells an agent to work from that backlog.
  They're replaced with short starters (`tools/init/minimal/`). The changelog records the template
  release the fork started from, read from the upstream changelog. The TODO lists the remaining
  make-it-yours steps.
- **`load-tests/run.sh --strict`**
  ([#40](https://github.com/alexh95/odin-htmx-skeleton/issues/40)). Without it the driver still records
  a breached threshold and carries on (a sweep exists to find the knee). With it, the run lists the
  failed `scenario@VUs` and exits 1, so it can gate. Checked: `P95=0.001 ./run.sh --quick --strict
  static` exits 1, and exits 0 without `--strict`.
- **`load-tests/parity.sh`** ([#40](https://github.com/alexh95/odin-htmx-skeleton/issues/40)) lists
  every route in `routes.odin` and whether `e2e/tests/` and `load-tests/scenarios/` mention its path,
  so the "both suites" rule can be checked rather than just stated. It's a text search, not coverage.
  It reports and exits 0; `--strict` exits 1 on a gap, for when it can gate. Today it finds 26
  literal routes: 6 with no e2e mention (the `/ui/*` fragments, reached by clicks), 14 with no load
  scenario. On the minimal starter, 0 and 2 (`/healthz`, `/favicon.ico`).

### Changed
- **The README says what the test suites enforce**
  ([#40](https://github.com/alexh95/odin-htmx-skeleton/issues/40)). It claimed both suites "gate CI".
  CI runs e2e only; the load suite is local, so it says that now and points at `--strict`. The e2e
  line gains `npx playwright install`.
- **README and `docs/STRIP.md` match the code**
  ([#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). The README listed "three brand
  constants" for `init` (it's five, plus two blanked tokens, the favicon and the card). It now shows
  `--site` in the example and lists every option. It gains a **Deploy** section linking
  `infra/PLAN.md` and `deploy/docker-host`, with the io_uring requirement, and the layout block lists
  `infra/`, `deploy/` and `tools/`. `init`'s usage text now lists `--site`. `docs/STRIP.md`'s
  keep-lists cover the 1.1.0 crawler contract: the SEO handlers and routes, `robots_txt`'s
  demo-specific `Disallow` list, `og.png` and its source, `BRAND_HOME_TITLE`, and the generic
  `seo.spec.ts`/`seo.js`. It also covers the CI `minimal` job and the stale `data.db`.
- **Per-id load-test URLs are tagged with a route `name`**
  ([#40](https://github.com/alexh95/odin-htmx-skeleton/issues/40)): `POST`/`DELETE /contacts/:id` in
  `write.js` and `mixed.js`, and `GET /contacts/:id` in `detail.js`. Untagged, each id was its own k6
  time series (100k–200k over a full run), and k6's memory grew on the machine the server shares.
- **`deploy/apollo-11` is now `deploy/docker-host`, a generic self-host example**
  ([#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44)). It was the only deploy with
  persistence, and it was wired to one home server: an ssh alias, `/mnt/fast-storage`, and an
  external `npm` network. `deploy.sh` now takes `HOST` (required), plus `NAME`, `REMOTE_DIR`,
  `HOST_PORT`, `VOLUME` and `PROXY_NET`, and writes them to an `.env` beside `compose.yaml`. The
  reverse-proxy network is an opt-in overlay (`compose.proxy.yaml`). The container now stops on
  SIGINT, the only signal the server shuts down cleanly on; as PID 1 it ignored Docker's SIGTERM
  until the SIGKILL, skipping the WAL checkpoint. The README covers backups. `init` renames the
  defaults. To keep an existing deployment's container and data, set `NAME`, `REMOTE_DIR`,
  `PROXY_NET` and `VOLUME`. Compose named the old volume `<project>_<volume>`, so check
  `docker volume ls`.
- **Deploy docs cover the io_uring seccomp profile and a non-root image**
  ([#44](https://github.com/alexh95/odin-htmx-skeleton/issues/44),
  [#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). `deploy/docker-host` ships
  `docker/seccomp-io-uring.json` (Docker's default profile plus io_uring) when the repo has it and runs
  the container under it, falling back to `seccomp=unconfined`. The README and `infra/PLAN.md` name
  the profile. For an image that runs as UID 10001, `fly.toml`, `infra/PLAN.md` and the docker-host
  README give the one-time `chown -R 10001:10001 /data` for a root-owned volume. On Fly, that's a
  first deploy with the mount but no `DB_PATH`, then `fly ssh console`.
- **`infra/PLAN.md` describes the repo as it is**
  ([#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). Gone: the on-disk `static/`, the
  bookworm Dockerfile sketch, "prepare clones odin-http at latest", the stale odin-http/Odin pins,
  and "CI smoke stands in for e2e". The operator steps use the name `init` sets and the current
  repo instead of the upstream's. The deploy token gets a 90-day expiry (`-x 2160h`) and a rotation
  note, instead of `-x 999999h`. New sections: the **io_uring platform requirement**, **Persistence
  on Fly** (a volume is one machine's, so `fly scale count 2` means two databases; a deploy restarts
  the machine), and rollback. `fly.toml` gains a commented `SITE_URL` and points at the volume
  caveats.

### Fixed
- **A fork's e2e no longer fails on the blanked ownership tokens**
  ([#24](https://github.com/alexh95/odin-htmx-skeleton/issues/24)). The `BingSiteAuth.xml` and
  IndexNow tests decided whether to run by looking for `/data` in the sitemap, so after `init` blanked
  both tokens they still ran and got 404. They now read `BING_SITE_AUTH` / `INDEXNOW_KEY` from
  `brand.odin` and skip only when the token is empty; when one is set they also check the served
  value against it. The `*.fly.dev` redirect test skips while `SITE_URL` is still an
  `*.example.com` placeholder, the case #25 changes.
- **`init` leaves almost nothing of the upstream's identity behind**
  ([#28](https://github.com/alexh95/odin-htmx-skeleton/issues/28)). It now also rewrites
  `BRAND_HOME_TITLE` (a "<name> — built with Odin + HTMX" stand-in), the JSON-LD code name, the
  favicon's label, the social card source, the README's live-demo line (removed), the upstream's
  canonical URL wherever the docs quote it, `app.css`'s header, `infra/PLAN.md`,
  `load-tests/README.md` and the docker-host deploy. It rejects a backslash in the brand values (they
  land in Odin string literals). The "Next" list names what only the fork can do: the home title, a
  real `SITE_URL`, re-rendering `og.png`, the favicon artwork, the ownership tokens, the first deploy,
  and the LICENSE notice. A closing read-only scan lists every file that still names the upstream.
  `grep -rE 'odin-htmx|alexh95|apollo-11'` outside CHANGELOG/TODO/LICENSE/`tools/` after
  `init acme-site` went from 39 lines in 12 files to 3 in 3; after `--minimal`, from 38 in 11 to 2
  in 2. What's left is one measurement record in `RESULTS.md` and two lines in files this change
  doesn't touch.
- **`init` removes the template-only `minimal` CI job from the fork**
  ([#24](https://github.com/alexh95/odin-htmx-skeleton/issues/24)). The job runs `tools/init` on the
  checkout to keep the `--minimal` templates honest, so in a fork it failed as soon as `tools/init`
  was deleted (as the README says to), or overwrote a minimal fork's own code. `deploy` needs every
  job, so the deploy was blocked too. Both variants now delete the job and its comment block and drop
  it from `deploy`'s `needs`. `init` fails, changing nothing, if it can't find the job or if
  `ci.yml` still runs `tools/init` afterwards.
- **A minimal fork's CI build job passes its smoke test**
  ([#24](https://github.com/alexh95/odin-htmx-skeleton/issues/24)). The step curls `/api/search` and
  `POST /contacts`, which the starter doesn't have, so every leg failed with "api/search returned
  404". `init --minimal` swaps those lines for the starter's `/about` and `POST /notes`.
- **The README's order of steps no longer crashes a minimal fork**
  ([#26](https://github.com/alexh95/odin-htmx-skeleton/issues/26)). The Quick start's `run` creates
  `app/data.db` with the demo's schema; after `init --minimal` the starter's migration runner counted
  it as up to date and the app exited with `no such table: notes`. `init --minimal` now deletes
  `app/data.db` and its `-wal`/`-shm` files (a dev store, reseeded on the next run) and says so before
  asking to proceed. A database elsewhere (`DB_PATH`) is named in the "Next" list. The migration
  check that would catch this at boot is #21.
- **`./run.sh --quick` works in a minimal fork again**
  ([#27](https://github.com/alexh95/odin-htmx-skeleton/issues/27)). The load driver kept a hard-coded
  scenario list that `init --minimal` was meant to trim, but the line it matched had changed in 1.1.0,
  so the trim silently missed and the run died at the first deleted scenario. `run.sh` now runs every
  `scenarios/*.js` by default, so there is no list to keep in step.
- **`init` fails loudly instead of skipping an edit that no longer applies**
  ([#27](https://github.com/alexh95/odin-htmx-skeleton/issues/27)). It now plans every change in
  memory (`tools/init/plan.odin`) and writes only if all of them apply; otherwise it lists each miss
  and changes nothing. A targeted replacement must match. In the name-token pass, every listed file
  must exist and every token must hit somewhere; a file left with nothing to rename is only noted. A
  second run says the checkout is already renamed. An audit of every existing replacement found two misses: the `run.sh` scenario list
  (above) and `app/README.md`, which was in the rename list with nothing to rename.
- **`<bin> --backup <file>`: a safe online backup, and a restore runbook**
  ([#34](https://github.com/alexh95/odin-htmx-skeleton/issues/34)). A fork with a persistent
  `DB_PATH` had no backup path, and the docs advised "a file copy", which can lose committed
  transactions still in `data.db-wal`. `DB_PATH=<live db> <bin> --backup <file>` writes a consistent
  copy with `VACUUM INTO` from its own connection, beside the running server, and refuses to
  overwrite a file. `docs/DATA.md` gains the backup and restore runbook (Fly and Docker commands,
  scheduling, deleting the stale `-wal`/`-shm` on restore, the one-machine-per-volume limit), and
  `DATA_IMPL.md` drops the file-copy advice. e2e: `backup.spec.ts` backs up under a live server, and
  restores by booting on the copy.
- **Logging, an access log and a build version**
  ([#20](https://github.com/alexh95/odin-htmx-skeleton/issues/20)). `context.logger` was never set, so
  Odin's no-op default swallowed every one of odin-http's warnings and errors, and nothing recorded a
  request. `main` now installs a console logger (`LOG_LEVEL=debug|info|warn|error`, default `info`)
  before anything runs, and the server threads inherit it. The middleware writes one line per request
  (`GET /about 200 0.19ms`: method, path without the query, status, time). Every response carries
  `x-version` from `-define:VERSION=…` (default `dev`), also logged at boot. `/healthz` now checks the
  store with a `SELECT 1` and answers 503 when it fails; its body is still exactly `ok`. Measured with
  `./run.sh --quick pages static`: about 21.3k rps on `pages` with the access log against 23.5k with
  `LOG_LEVEL=warn` (k6 at 20 VUs; `static` within noise). e2e: `ops.spec.ts`.
- **Cross-site writes are refused** ([#18](https://github.com/alexh95/odin-htmx-skeleton/issues/18)).
  A POST from any site could edit a contact; the first fork to add a cookie session would have
  inherited forgeable writes. `controllers.front` now answers 403 to a write whose `Sec-Fetch-Site`
  isn't `same-origin`/`none`, or, from a browser too old to send it, whose `Origin` isn't this host.
  A request with neither header isn't a browser and passes, so curl, k6 and the e2e API calls keep
  working; for that reason the guard doesn't require `HX-Request`. `CLAUDE.md` says how a fork
  extends it once it has sessions. e2e: three cases in `security.spec.ts`.
- **Security headers and a strict Content-Security-Policy on every response**
  ([#19](https://github.com/alexh95/odin-htmx-skeleton/issues/19)). Responses carried only `date`,
  `content-length` and `content-type`. `controllers.front` now sets `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin` and a CSP whose
  `script-src` is `'self'` plus the sha256 of the theme pre-paint script, with no `'unsafe-inline'`
  (`style-src-attr` keeps it, for the components' `style="--x:…"` custom properties). The hash is
  computed at boot from `views.THEME_PREPAINT_JS`, so editing the script keeps the header right. To
  make that possible, the 56 inline `on*=` handlers on `/components` (theme picker, showroom, tabs,
  toast dismiss, range outputs, search-form submits, drawer `stopPropagation`) are gone: app.js routes
  clicks by `data-*` attribute or role from one delegated listener, the drawers' backdrops close on
  `hx-trigger="click from:self"`, and slider outputs are `<output>` elements app.js keeps in step.
  Both variants. e2e: `security.spec.ts` checks the headers on a page, an asset, `/healthz` and a 404,
  that no page has an inline handler, that the hashed script runs, and that using the pages raises no
  CSP violation.

### Changed
- **`CLAUDE.md` matches the code, and covers what a fork does first** (part of
  [#32](https://github.com/alexh95/odin-htmx-skeleton/issues/32) and
  [#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). New: a "New table / entity"
  recipe (migration, statements in four places, seed, tests), a "Validation errors (422)" section,
  the middleware, escaping, store-error and backup rules, a table of every environment variable, and
  pointers to where a new e2e spec and k6 scenario go. Corrected: the allocator section described
  the old in-memory store (`repo_delete` frees); "boundaries enforced by the compiler" (it only
  forbids cycles); the "flagship admin console" framing (it's a starter); stale comments in
  `main.odin` ("repository.odin") and `routes.odin` ("on-disk" static files). `app/README.md` and
  `docs/DATA_IMPL.md` follow.
- **The repository's SQLite plumbing is one shared file.** `repository/db.odin` holds the
  connection, lock, migration runner and bind/scan helpers, unchanged between the demo and the
  `--minimal` starter; `repo.odin` keeps only the app's wiring (migrations, statements, seed). A fix
  to the plumbing now lands in both variants at once.
- **Controllers and views reach the store only through services** (part of
  [#33](https://github.com/alexh95/odin-htmx-skeleton/issues/33)). `CLAUDE.md` said "never touch
  the store from a controller" while `controllers.odin` made ten `repository.*` calls and the
  dashboard view read the table itself. `services` gains `get_contact`, `create_contact`,
  `update_contact` (both validate), `cycle_status`, `delete_contact`, `search_all` and
  `dashboard_stats`; `view_dashboard` takes its numbers as a parameter.

### Fixed
- **Lists are filtered, sorted, paged and counted in SQL**
  ([#14](https://github.com/alexh95/odin-htmx-skeleton/issues/14), partly). Every list request loaded
  the whole table into Odin under the store's lock, so latency and response size grew with the
  table. The table, the search dropdown, `/api/search` and the related list now run as SQL with
  `WHERE`/`ORDER BY`/`LIMIT`/`OFFSET` and a `count(*)`: one prepared statement per sort key, and a
  `contains_ci` SQL function written in Odin, so search keeps its per-rune Unicode matching (`LIKE`
  folds ASCII only). The pager shows a window (1 2 3 … 12) instead of a button per page, and
  `/api/search` returns at most 100 rows. The starter's note list is capped at the newest 50. With one
  client at 20k contacts: `/data` 63 → 2 ms, a deep filtered page 107 → 16 ms, a search miss 259 →
  18 ms, `/api/search` 213 → 1 ms. Still open: search is a scan (~1 µs a row), and everything runs
  under one exclusive lock, so at 20 concurrent users on 20k rows the new `scale` k6 scenario still
  shows p95 1.2 s (1.7 s before). Role/status sorts now break ties by id. e2e: `paging.spec.ts`; load:
  `scenarios/scale.js`.
- **Windows dev-loop papercuts** (part of
  [#35](https://github.com/alexh95/odin-htmx-skeleton/issues/35)). The server printed (and `run.bat`
  opened) `http://localhost`, but listens on IPv4 loopback only, so each request first tried `::1`:
  about 200 ms against 1.6 ms for `127.0.0.1`. The banner, the run scripts and the docs now say
  `127.0.0.1`. `run.bat` and `run.sh` no longer open a browser tab on every run (`OPEN=1` asks for
  one). And `run.bat` checks whether `bin\demo.exe` is held by a server still running from an
  earlier run, saying so instead of letting the linker fail with "don't have access to write".
- **`prepare.bat` re-runs cleanly outside the MSVC dev shell**
  ([#31](https://github.com/alexh95/odin-htmx-skeleton/issues/31)). It looked for `cl` before checking
  whether anything needed compiling, so every re-run from a plain shell failed with the Build Tools
  banner even with `sqlite3.lib` built (and e2e's global-setup printed it on every run). `cl` is now
  looked for only when the lib is missing or stale, and `prepare.sh` does the same for clang/gcc. A
  failing `cl` or `lib` now stops the script: the old `( popd ^& goto :fail )` escaped the `&`, so
  the `goto` never ran.
- **Visual defaults: bare checkboxes, the starter's note list**
  ([#30](https://github.com/alexh95/odin-htmx-skeleton/issues/30)). The global
  `input, select, textarea { width: 100% }` stretched a bare checkbox to about 815 px; it now skips
  checkboxes and radios, inside `:where()` so `input[type="range"]` still wins. In the `--minimal`
  starter the note list lost its 40 px browser indent, and the seed now runs oldest to newest and the
  list orders by time, so "Welcome…" (the newest) is on top instead of at the bottom. e2e:
  `styles.spec.ts`.
- **`/forms` stores the notes and the email-updates switch it posts** (part of
  [#23](https://github.com/alexh95/odin-htmx-skeleton/issues/23); the e2e half of
  [#15](https://github.com/alexh95/odin-htmx-skeleton/issues/15)). `forms_submit` silently dropped
  both. Migration `0003_contact_notes.sql` adds `notes TEXT NOT NULL DEFAULT ''` and `notify`;
  `create_contact` stores them (notes capped at 1000 characters, `maxlength` to match), the drawer
  shows them, and `/api/search` returns them. Empty notes are the optional text field #15 was about:
  `writes.spec.ts` submits one and reads it back as `""`.
- **The dashboard shows only what the store says** (part of
  [#23](https://github.com/alexh95/odin-htmx-skeleton/issues/23) and
  [#14](https://github.com/alexh95/odin-htmx-skeleton/issues/14)). "+4 this week" and "82% of base"
  sat beside live counts, over made-up sparklines. The cards now come from one aggregate query
  (`repo_contact_stats`: a `GROUP BY` of status, role and score band, so its cost doesn't grow with
  the table) instead of loading every contact: shares are computed ("35% of all"), and each sparkline
  is a real distribution (contacts per role; engagement scores, low to high), with the misleading
  up-arrow gone. e2e: `dashboard.spec.ts`.
- **Cycling a status can't lose a step** (part of
  [#23](https://github.com/alexh95/odin-htmx-skeleton/issues/23)). It read the status and wrote the
  next one under two separate lock acquisitions, so two clicks at once could both write the same
  value. It is now one statement, `UPDATE contacts SET status=(status+1)%?2 WHERE id=?1`
  (`repo_cycle_status`, replacing `repo_set_status`). e2e: `writes.spec.ts` cycles one contact 31
  times at once.
- **A wrong method is a 405, an unknown page a real 404 page, and text says it's UTF-8** (part of
  [#23](https://github.com/alexh95/odin-htmx-skeleton/issues/23)). `PUT /contacts/1` was a 404, an
  unknown URL an empty 404, and `content-type: text/html` named no charset. A last-resort route
  (`controllers.fallback`, registered by both variants' `routes.odin`) answers 405 with an `Allow`
  header when another method serves the path, and otherwise `not_found`: the site's 404 page in the
  layout for a browser, a bare 404 for htmx (whose body would be swapped into a fragment). Missing
  contacts and unparsable ids use the same `not_found`. HTML and plain-text responses go through
  `respond_html`/`respond_plain`, which add `; charset=utf-8`. The error-page body, `view_error`, is
  shared by both variants (`views/errors.odin`). e2e: `routing.spec.ts`.
- **A fork on `*.fly.dev` is served instead of redirected to a placeholder domain**
  ([#25](https://github.com/alexh95/odin-htmx-skeleton/issues/25)). `canonical_host` 301'd every
  `*.fly.dev` request to `SITE_URL`, which `init` sets to `https://<name>.example.com` until the fork
  has a domain, so a fresh deploy sent every visitor to a site that doesn't exist while the exempt
  health check kept the deploy green. The redirect is now off while `SITE_URL` is a reserved example
  or test name (RFC 2606/6761: `example.com/.net/.org`, `.example`, `.test`, `.invalid`,
  `.localhost`). `canonical_host` moves into `controllers/middleware.odin`. e2e: `canonical.spec.ts`
  boots servers with a real and two placeholder origins.
- **Escaping gaps closed** ([#22](https://github.com/alexh95/odin-htmx-skeleton/issues/22)). Avatar
  initials were cut byte by byte and written raw: a name starting with `<` broke the row's DOM, and
  every non-ASCII initial (the `É` of "Émile") rendered as half a character. They are now whole runes,
  escaped. `page_head`, `section_open`, `acc_item`, `link_tile` and `stat_card` (and the starter's
  `page_head`) wrote their text arguments raw, so the first fork to pass a stored value to a heading
  had stored XSS; they now escape them, and the one pre-escaped caller (`"Data &amp; CRUD"`) passes
  plain text. JSON-LD used the HTML escaper; it now uses a JSON string escaper, `json_esc`. `w`, `esc`,
  `url_encode` and `json_esc` live in one shared file, `views/html.odin`. Tests: `escaping.spec.ts`
  (avatars) and `views/html_test.odin` (`page_head` with hostile text, `json_esc`).
- **A refused form keeps what the user typed**
  ([#17](https://github.com/alexh95/odin-htmx-skeleton/issues/17)). Validation errors came back as
  200, so app.js's reset-on-success wiped every field of a rejected `/forms` submit. They are now
  **422**: app.js still resets only after a 2xx, and htmx 4 swaps the 422 body where it belongs.
  `/forms` shows the errors in `#form-result` as before; the `/data` add form routes them into an
  inline slot with `hx-status:422`; a refused drawer edit comes back filled with what was typed, plus
  the reason. The minimal starter's note form gets the same pattern (an error slot for 422 and 5xx)
  instead of its silent empty 200. A success clears the slot. The `/forms` email field is now
  `required` like the server's check, and a drawer edit with a blank name is refused instead of
  silently ignored. `CLAUDE.md` documents the pattern. e2e: `validation.spec.ts` (demo and starter).
- **Migrations are transactional and checked by name and hash, and demo rows only seed a store
  nobody owns** ([#21](https://github.com/alexh95/odin-htmx-skeleton/issues/21); also stops the
  [#26](https://github.com/alexh95/odin-htmx-skeleton/issues/26) crash from the runner side). Each
  migration now runs in one transaction with the `schema_version` row that records it, so a failure
  halfway leaves the schema untouched and the boot names the file. `schema_version` gains `name`
  and `hash` (sha256), checked against the binary's list at every boot: an edited, renamed or unknown
  migration stops the boot with a message saying what to do, where the old count-only runner skipped
  it. That is what crashed the `--minimal` starter on a demo `data.db` with "no such table: notes".
  Databases from 1.1 are adopted in place. `MIGRATIONS` entries are now `{name, sql}` pairs. Demo rows
  seed only `:memory:`, or a file DB when `SEED=1` (`run.*` sets it for local dev), so an emptied
  production table stays empty. Tested in `db_test.odin`: rollback, an edited and an unknown
  migration, and adopting a 1.1 database.
- **Ids are 64-bit, and a bad id is a 404**
  ([#16](https://github.com/alexh95/odin-htmx-skeleton/issues/16)). Ids were bound and read as
  32-bit `c.int`, and `to_int` ignored parse failures, so `GET /contacts/4294967297` returned
  contact #1 and `DELETE /contacts/4294967298` deleted #2. The repository binds and reads ids with
  `bind_id`/`column_id` (int64), and the controllers parse path ids with `parse_id`, which rejects
  zero, non-digits and anything past 64 bits (`strconv.parse_int` wraps silently). e2e:
  `ids.spec.ts`.
- **Store errors are no longer ignored, and empty strings are stored as `""`**
  ([#15](https://github.com/alexh95/odin-htmx-skeleton/issues/15)). `bind_text` passed a nil pointer
  for `""`, which SQLite binds as NULL, so a `NOT NULL` text column rejected it; and no `step()`
  result was checked, so a failed insert returned the *previous* row's id as if it were the new one.
  `bind_text` now points at a real zero-length buffer. Writes go through `step_done` and reads
  through `next_row`, which log SQLite's message and return a `repository.Error`
  (`Not_Found`/`Constraint`/`Failed`). It travels up through `services` (re-exported as
  `Store_Error`) to the controllers, where `respond_store_error` answers 404, 409 or 500: an
  out-of-band toast for htmx, an error page otherwise. The minimal starter does the same with a plain
  500. The binding gains `bind_null`, `bind_double`, `column_double` and `column_type`. Tested by
  `app/src/repository/db_test.odin` (`odin test src/repository`): `""` round-trips as text, and a
  failed write returns `Constraint`, not a stale row.
- **Request bodies and text fields are size-limited**
  ([#13](https://github.com/alexh95/odin-htmx-skeleton/issues/13)). A 50 MB `name` used to be
  stored and then re-sent by every page that listed it. A new `controllers.front` middleware
  (`middleware.odin`, shared with `--minimal`) reads every body before routing, capped at 64 KiB:
  past that it answers 413 without reading it. Handlers get the parsed form from `request_form()`,
  so they are plain synchronous code. `validate_contact` caps names at 100 characters and emails at
  254, the minimal starter caps a note at 500, and each input carries the same `maxlength`. e2e:
  `limits.spec.ts`.
- **The `--minimal` starter passes `odin check -vet`** (part of
  [#29](https://github.com/alexh95/odin-htmx-skeleton/issues/29)): `notes.odin` dropped an unused
  `import "core:c"`.

## [1.1.1] - 2026-10-07

A patch release with two changes:
- **Search highlighting** now marks exactly what the search matched, including text whose lowercase
  form has a different byte length (`İ`, `ẞ`, invalid UTF-8).
- **CI** retries flaky Ubuntu mirror fetches and puts a timeout on every job.

Nothing else changed since 1.1.0. A fork started from 1.1.0 or earlier should take the new
`write_highlighted` in `app/src/views/views.odin` (it replaces the old one, with its file-private
`match_ci` helper). The CI change is optional: `.github/scripts/apt-install.sh` plus the matching
`ci.yml` edits.

### Changed
- **CI survives Ubuntu mirror outages, and no job can run for hours** (part of
  [#36](https://github.com/alexh95/odin-htmx-skeleton/issues/36)). The three `apt-get install clang …`
  steps failed CI three times on 2026-10-07, each before a single test ran. One hung for 4 min until it
  was cancelled by hand; twice `azure.archive.ubuntu.com` (and once `security.ubuntu.com`) timed out
  from the runner. They now go through one script, `.github/scripts/apt-install.sh`. It retries the
  whole update+install up to 5 times with 20–100 s backoff, because `Acquire::Retries` alone only
  retries one fetch within seconds. It uses `sudo` only when not root, so the host runner and the
  Playwright containers share it. Every job also gets a `timeout-minutes` (20; 30 for the Fly deploy,
  whose remote builder has stalled for about 10 min before), and each apt step gets 10. A hang now
  fails in minutes instead of running to GitHub's 6 h default. Tested locally with stub
  `apt-get`/`sudo`: an install that fails once is retried and succeeds, both as root and through sudo.

### Fixed
- **Search highlighting could mark the wrong characters.** `write_highlighted` found matches in a
  lowercased copy of the text, then cut the original with that copy's offsets. Lowercasing can change
  a string's byte length: `İ` lowers to `i`, `ẞ` to `ß`, and an invalid UTF-8 byte to the 3-byte
  U+FFFD. So searching `İ` marked `in`, and a stored `Straẞe` found by `straße` was marked as
  `Straẞ`. It now walks the original text rune by rune, applying the same per-rune
  `unicode.to_lower` that `services.contains_ci` matches with, so the marks cover exactly what the
  search matched. e2e: two request-level cases in `search.spec.ts` cover a query and stored text whose
  lowercase changes length; both failed before the fix. No load-test change: the endpoint and its cost
  are the same.

## [1.1.0] - 2026-10-07

The skeleton now ships the **crawler contract** every new site needs, so a fork can be found:
one canonical origin (`SITE_URL`, set by `init --site`), `robots.txt`, a `sitemap.xml` derived from
the nav, canonical and social-card tags, JSON-LD, a root `favicon.ico`, and opt-in Bing/IndexNow
verification. All of it is ported into the `--minimal` starter and covered by both the e2e and the
load suites. The project is now licensed **zlib**. Two fixes: clicks are no longer lost while an
htmx swap runs ([#8](https://github.com/alexh95/odin-htmx-skeleton/issues/8)), and the home page's
`<title>` and `og:title` now agree. Every pin is current: Odin `dev-2026-10`, htmx `4.0.0` final,
Debian 13 `trixie`, SQLite `3.53.4`, Playwright `1.63.0`, and the GitHub Actions on their Node 24
majors. Nothing breaking for a fork: the additions are opt-in or derived from what's already there.

### Changed
- **Dependency sweep — every pin checked against upstream; one moved.**
  - **Odin `dev-2026-09` → `dev-2026-10`** (`ci.yml`'s `ODIN_VERSION` and all three matrix asset
    names, the `Dockerfile`). The assets were downloaded before landing: every name resolves, every
    SHA-256 matches the release's published digest, and the layouts are unchanged (the Windows zip
    still unpacks to `dist/`; each tarball still has one top-level dir for `--strip-components=1`).
    The release drops macOS *Intel* builds, which doesn't touch the matrix — its macOS leg is arm64.
    No source change was needed. On Windows it does change the linker: Odin now links with its own
    bundled `radlink` instead of MSVC's `link.exe`. It links the `/MT` `sqlite3.lib` cleanly, and the
    three comments that named `link.exe` (`ci.yml`, `app/README.md`, `run.bat`) were corrected. The
    MSVC Build Tools are still required, for `cl` and for the CRT/SDK libraries Odin links against.
    The release's compiler work also shows up here: a debug build of `app/src` went from 0.48 s to
    0.27 s on the same machine, and the `-o:speed` binary shrank by ~10 KB.
  - **Checked and already current:** odin-http `fac113f` (upstream `main`), htmx `4.0.0` (the newest
    4.x), SQLite `3.53.4`, Playwright `1.63.0` (and its `v1.63.0-jammy` image), `actions/checkout@v7`
    (7.0.1), `actions/cache@v6` (6.1.0), `actions/upload-artifact@v7` (7.0.2 came out today; the
    major tag already picks it up), `ilammy/msvc-dev-cmd@v1.13.0`, and `setup-flyctl` at SHA
    `ed8efb33` (still tag 1.6 and upstream `master`). The Debian base floats on `trixie-slim`.
  - Verified on Windows 11 (MSVC 14.51) with the `dev-2026-10` release: a fresh `prepare.bat` (the
    pinned htmx and SQLite downloads still match their SHA-256s), clean `-warnings-as-errors` builds
    (debug and `-o:speed`), all 213 e2e tests (71 each on chromium, firefox and webkit), and the
    `tools/init --minimal` starter built and run through its own e2e (19 passed; the 3 skips are by
    design: the two per-deployment verification files `init` blanks, and a demo-copy check). Linux
    and macOS are CI's.

### Changed
- **Dependency sweep — every pin checked against upstream; one moved.**
  - **Playwright `1.62.1` → `1.63.0`** (`e2e/package.json` + lockfile, and both CI container image
    tags — `mcr.microsoft.com/playwright:v1.63.0-jammy` is published, so the npm package and the
    image move together as they must). The lockfile also loses its `fsevents` entry: `playwright`
    1.63.0 no longer declares that optional dependency, so the drop is upstream's, not npm pruning a
    macOS-only package on a Windows install. Nothing in the release affects this suite — its new APIs
    (test locks, `locator.visible()`, frame-agnostic `frameLocator()`) are additive, and its one
    removal, Ubuntu 20.04 support, doesn't touch the `jammy` image.
  - **Checked and already current:** Odin `dev-2026-09` (still the latest release), odin-http
    `fac113f` (upstream `main`), htmx `4.0.0` (the newest 4.x; npm's `latest` tag is the 2.x line),
    SQLite `3.53.4` (no newer release), `actions/checkout@v7` (7.0.1), `actions/cache@v6` (6.1.0),
    `actions/upload-artifact@v7` (7.0.1), `ilammy/msvc-dev-cmd@v1.13.0`, and `setup-flyctl` at SHA
    `ed8efb33` (still tag 1.6 and upstream `master`). The Debian base floats on `trixie-slim`.
  - **The CI containers stay on `jammy` deliberately.** Playwright now also ships `noble` (24.04) and
    `resolute` (26.04) images, but moving would change the e2e jobs' OS and their apt `clang`
    (14 → 18) along with the browsers — the same rule the Debian base follows: leave a release when
    its standard support ends, in a change of its own. Logged in `TODO.md`.
  - Verified on Windows 11 (MSVC 14.51): a fresh `prepare.bat` (the pinned htmx and SQLite downloads
    still match their SHA-256s), a clean `-warnings-as-errors` build on the `dev-2026-09` release, and
    all 213 e2e tests — 71 each on chromium, firefox and webkit — on Playwright 1.63.0.

### Fixed
- **Clicks were lost while an htmx swap ran** ([#8](https://github.com/alexh95/odin-htmx-skeleton/issues/8)).
  `htmx-config` turned `transitions` on globally, so *every* swap — a validation message, a search
  result, a toast — ran inside `document.startViewTransition()`, and for as long as a view transition
  runs, Chromium hit-tests the whole page to `<html>`. A click whose mouse-up landed in that
  window (~250 ms of default crossfade) never reached its target. The easy way to hit it: type in
  the `/forms` email field, then click the theme picker — the mouse-down blurs the field, its
  `change` trigger validates, and that swap's transition took the mouse-up; the picker needed a
  second click. Now only the boosted brand + nav links run a view transition, opting in with
  `hx-swap="innerHTML transition:true"`: a page that is being replaced can afford the dead window,
  a fragment swap that leaves the rest of the page live cannot. Fragments lose nothing visible —
  each already has its own CSS entrance animation. The alternative the issue floated,
  `::view-transition { pointer-events: none }`, was tried first and does not help: Chromium still
  routes the hit to `<html>`. One side effect: back/forward no longer crossfade, since htmx 4 takes a
  history restore's transition from the global flag alone. Ported to the `--minimal` templates.
  e2e: a real press on the picker (`mouse.down()`, ~100 ms, `mouse.up()`) that blurs the email field
  must open it — `locator.click()` waits a transition out, which is how the suite missed this; a
  `startViewTransition` counter pins a fragment swap at zero transitions and a boosted navigation at
  one, so the cause is caught in every engine, including those that don't drop the click; and the
  minimal starter's spec presses the picker right after adding a note. No load-test change: no
  endpoint changed, and the pages differ only in a few bytes of htmx attributes.
- **`<title>` and `og:title` disagreed on the home page.** The previous pass gave `/` a title that
  names the project, but left `og:title` on the `"<page> · <brand>"` shape — so the page offered
  "Dashboard · Odin + HTMX" as its other name, and a crawler weighing two names for one page may
  print either. Both now resolve through a single `head_title` proc in `layout`, so they cannot drift
  apart again, and `seo.spec.ts` asserts they agree on every page in the sitemap. Ported to the
  `--minimal` templates, which carried the same mismatch.

### Added
- **The home page now says what the site is.** Its `<h1>` read "Dashboard" — the nav item, not the
  product — while `<title>`, `og:title` and the JSON-LD `name` all named the project; and the whole
  page carried ~120 words, every one of them a caption on a stat card or a link tile. Bing had
  crawled it and declined to index it ("known to Bing but has some issues"), which is the same thing
  a reader arriving from a search result experiences: a wall of widgets and no answer to "what is
  this". So:
  - the heading names the stack (**"A server-rendered web stack in one binary"**), agreeing with the
    title rather than competing with it;
  - the overview keeps its own `<h2>`, where "Overview" describes the *section* — which is what it
    was always describing;
  - a closing prose block explains the mechanism (rendered by Odin procedures, embedded assets, HTMX
    fragments, SQLite linked in). Deliberately **not** the About page's wording: two pages restating
    each other are two thin pages, so this one covers the mechanism and About covers the project.
  - the meta description was realigned with the title for the same reason.
  Reuses the About card's classes (`.card.about`, `.about-lede`, `.about-stack`) — no new CSS. e2e:
  the home `<h1>` is cross-checked against the app's own rendered nav label rather than a hardcoded
  string, so it holds for the `--minimal` starter too, and the prose block is asserted to carry real
  text. Load scenarios already cover `/` (`pages.js`, `mixed.js`); the page only got bigger.

### Added
- **How the site presents itself in search results.** It reached page one, and the result showed a
  placeholder icon, the site name "alexh95" and the title "Dashboard · Odin + HTMX" — three separate
  defaults, each with its own documented lever:
  - **`GET /favicon.ico`** — a real 16/32/48 multi-size `.ico`, rendered from the existing
    `favicon.svg` and embedded via `#load`. Crawlers look for it at the *site root* (not `/static`)
    and are far more reliable with a raster icon than an SVG; the SVG link stays for browsers, so
    each client takes what it prefers.
  - **`WebSite` JSON-LD on the home page**, with `name` matching `og:site_name`. Absent it, the site
    name is derived from the hostname — which on a subdomain is the bare registrable name, hence
    "alexh95" rather than the project. Emitted **only** on the home page: that is where Google reads
    it, and repeating it elsewhere is a conflicting signal at best.
  - **`BRAND_HOME_TITLE`** — the home page's `<title>` now stands alone instead of taking the
    `<page> · <brand>` shape, because that page is the result shown for the site as a whole and
    "Dashboard" describes a nav item, not the product. Interior pages keep the suffix.
- All three are **skeleton functionality, not deployment config**, so unlike the verification tokens
  they are ported into the `--minimal` templates too: every site wants a favicon a crawler can use
  and its own name in results.
- Four e2e cases cover them, including that `WebSite` appears on the home page *only*, that the ICO
  magic bytes are real, and that `WebSite.name` and `og:site_name` agree — they are trusted over the
  hostname fallback precisely because they agree, so a drift between them is a regression.

### Added
- **IndexNow — `GET /<key>.txt`.** One key push-notifies Bing, Yandex, Seznam and Naver that a URL
  changed instead of waiting to be re-crawled. Ownership is proved by serving the key back as plain
  text at its own path, so `views.INDEXNOW_KEY` (brand.odin) is public by design — the same
  per-deployment identity as `BING_SITE_AUTH`, blanked by `init` for the same reason, and an unset
  key means **the route is never registered at all**.
  The path *is* the key, so the route pattern is built at startup rather than written literally, and
  the dot is escaped (`%%.`): unescaped, a Lua pattern reads `.` as *any character* and would hand
  the key out from near-miss paths. Both the exact path and that near-miss are asserted in
  `seo.spec.ts`, along with byte-exact equality of the body — the engines compare it verbatim, so a
  trailing newline would fail the ownership check.

### Added
- **`LICENSE` — zlib.** There was none, so the default was *all rights reserved*, which flatly
  contradicted a repo whose pitch is "clone it, rename it, build your thing". zlib is the most
  permissive of the common licences that still asks altered versions to say they are altered —
  exactly the ask of a skeleton meant to be cloned and rewritten. Deliberately **not** mirrored into
  the JSON-LD `license` field: `views.odin` is shared with the `--minimal` templates every fork
  starts from, and a hardcoded licence URL there would have each fork asserting a licence its author
  never chose. GitHub's own licence detection is the signal that matters anyway.
- **`GET /BingSiteAuth.xml`** — Bing Webmaster ownership proof, served from the binary. DNS
  verification had cost two wrong record values and a resolver-cache stall; a file the app serves is
  deterministic the moment it deploys, with no propagation or caches in the way.
  `views.BING_SITE_AUTH` (brand.odin) holds the token — per-deployment identity, so it sits beside
  `SITE_URL` rather than in the view. **An empty token 404s the route**, and `init` blanks it, so a
  fork can never advertise someone else's ownership proof. The minimal templates deliberately do not
  carry the route at all: it is deployment config, not skeleton functionality.
  Covered in `seo.spec.ts` (XML shape + a 32-hex token), skipped in variants without a token.
  Not added to the load suite on purpose — a one-shot verification endpoint that search engines hit
  a handful of times ever is not a traffic path, and measuring it would be noise.

### Added
- **Crawler contract — the site can now be indexed.** It previously shipped `<title>`, a meta
  description and `og:title`/`og:description`, but nothing that told a search engine *which* URL a
  page is or where the pages are, and nothing linking the site to its repository:
  - **`views.SITE_URL`** (`brand.odin`, overridable by a `SITE_URL` env var) is the one canonical
    origin. Everything absolute derives from it, so the origin is stated once.
  - **`<link rel="canonical">` + `og:url`** on every page, self-referential and absolute
    (`SITE_URL + active`, the same href the nav marks). Plus `og:site_name`, `og:image` and
    `twitter:card`, and a JSON-LD `SoftwareSourceCode` block tying the site to `BRAND_REPO` so a
    crawler reads one project rather than two unrelated URLs.
  - **`GET /robots.txt`** — allows the pages, disallows the fragment routes (`/ui/`, `/api/`,
    `/search`, `/contacts`, `/validate/`, `/forms/submit`). Those answer with bare HTML built to be
    swapped into a page; indexed alone they are thin near-duplicates competing with the real pages.
  - **`GET /sitemap.xml`** — generated by walking `views.NAV`, so a page cannot be added to the nav
    and silently left out. Both endpoints emit absolute URLs on `SITE_URL`; a sitemap advertising a
    different host than the canonical tag is discarded.
  - **`og.png`** (1200×630, drawn in the project's own palette) embedded via `#load` like every
    other asset and served at a deliberately *unfingerprinted* `/static/og.png` — social platforms
    cache a preview against its URL, so that path has to survive redeploys.
- **`canonical_host` middleware** (`main.odin`): the app answers on both the custom domain and its
  `*.fly.dev` hostname, so a crawler that found both would index the site twice and split its
  ranking signals. A 301 collapses them onto `SITE_URL`, carrying the accumulated authority — a
  canonical tag alone only hints, and only to search engines. Scoped to `*.fly.dev` rather than
  "any non-canonical host" so localhost and LAN development keep working, and **`/healthz` is
  exempt**: Fly's own probe calls it, and a probe that follows a redirect off-host fails the
  deploy rather than the request.
- **`init --site <url>`** — the scaffolding tool now rewrites `SITE_URL` alongside the other brand
  constants, defaulting to `https://<name>.example.com`. Without it every fork would serve
  canonical tags and a sitemap pointing at *this* project's domain, telling Google the fork is a
  copy of someone else's page.
- **The `--minimal` starter ships the same crawler contract.** `init --minimal` replaces
  `routes.odin`, `controllers.odin` and `views.odin` wholesale, so the SEO work had to be ported
  into those templates too — otherwise the variant that exists *to be built on* would be the one
  shipping without canonical tags, robots or a sitemap. `OG_IMAGE_HREF` moved to `brand.odin`
  (which survives the strip) so both variants share one definition. Its sitemap lists whatever its
  smaller `NAV` holds, which is exactly the point of deriving it.
- **e2e `seo.spec.ts` (11 cases) and the `seo` load scenario**, per the both-suites rule: the
  crawler contract is invisible in the UI, so it can rot silently. Covers robots/sitemap content
  and content types, canonical↔og:url agreement per page, absolute `og:image`, JSON-LD *parsing*
  (invalid JSON there is invisible but fatal to crawlers), the PNG magic bytes, and all three
  redirect behaviours including the `/healthz` exemption.

### Changed
- **Named the project consistently `odin-htmx-skeleton`.** The repo, the Fly app and the domain
  said "skeleton" while `README.md`'s H1, the repo tree in `CLAUDE.md`, the `app.css` header and
  the startup banner still said `odin-htmx-demo` — the word a search engine weights most for a
  repo page was the one word that disagreed with itself. `tools/init` loses its now-dead
  `odin-htmx-demo` rename token (nothing matches it any more; `odin-htmx-skeleton` already covers
  every occurrence).
- `README.md` links the live demo, and `CLAUDE.md` gains a **Crawlers / SEO** section recording the
  rules that are easy to break silently: one canonical origin, sitemap/canonical *derived* from
  `NAV` rather than hand-maintained, new fragment routes belong in the `robots.txt` disallow list,
  `og.png` stays unfingerprinted, and JSON-LD is all literal braces so it must use `w()`.

### Changed
- **Dependency sweep — every pin checked against upstream.** Three moved, the rest were already
  current:
  - **Odin toolchain `dev-2026-07a` → `dev-2026-09`** (`Dockerfile` ARG + the CI `ODIN_VERSION` env).
    Two releases in one step. Per the standing warning above the CI matrix, all three hardcoded
    asset names were verified to resolve *before* landing — `dev-2026-09` is regular
    (`odin-linux-amd64-`, `odin-macos-arm64-`, `odin-windows-amd64-`), so the version-only bump is
    safe here; `dev-2026-08` was checked too and is likewise regular.
  - **odin-http `112c49b` → `fac113f`** (8 commits). Six are vendored-OpenSSL churn that cannot
    reach this binary — it never takes odin-http's TLS client path, and `ldd`/`nm` on the built
    binary confirm it links only libc/libm with zero OpenSSL symbols (Fly terminates TLS at the
    edge). The remaining two are small fixes (a client-cookie delete allocator, #114/#117).
  - **Playwright `1.61.1` → `1.62.1`** (`e2e/package.json` + lockfile, and both CI container image
    tags). This unblocks the previous sweep's deliberate hold: it stayed at 1.61.1 only because
    `mcr.microsoft.com/playwright:v1.62.0-jammy` was unpublished. `v1.62.1-jammy` now exists, so the
    npm package and the image move together as they must.
  - **Checked and already current:** SQLite `3.53.4` (the mirror's `master` reads 3.54.0, but no
    `version-3.54.0` release tag exists yet), htmx `4.0.0`, `actions/checkout@v7`,
    `actions/cache@v6`, `actions/upload-artifact@v7`, `superfly/setup-flyctl` at SHA `ed8efb33`
    (tag 1.6). **`ilammy/msvc-dev-cmd@v1.13.0` is no longer a deliberate hold** — upstream has
    published nothing newer, so the pin is simply current; the standing deprecation warning remains.
    The Debian base is the floating `trixie-slim` tag and tracks Debian 13 point releases on rebuild.
  - Verified: clean `-warnings-as-errors` build on `dev-2026-09`, and 51/52 e2e on chromium (the one
    failure is `persistence.spec.ts`, the known sandbox port-reuse race — `Address_In_Use` on
    restart — which passes on CI).
- **htmx `4.0.0-beta6` → `4.0.0`** (the 4.0 final, released 2026-08-28; + new SHA-256 in
  `prepare.sh`/`prepare.bat`). One behaviour change upstream bit us, and it is subtle: an OOB swap
  now **suppresses an empty main swap** by default. htmx computes
  `hasPartials = partialTasks.length || (oobTasks.length && !config.allowEmptySwapAfterOOB)` and
  skips the main swap when it is set — in beta6 only `hx-partial` counted, so an empty body still
  swapped. Delete-from-drawer depends on exactly that shape: `contacts_delete` answers `?from=drawer`
  with an empty body plus one OOB `<tr hx-swap-oob="delete">`, and *closing the drawer is that empty
  swap into `#overlay`*. Under 4.0.0 the drawer stayed open. Fixed with the new `swapEmpty:true` swap
  modifier on that one button (`views_fragments.odin`) rather than the global
  `allowEmptySwapAfterOOB` config — the safer new default holds everywhere else, and the one site
  that relies on the old semantics now says so. The other OOB sites were audited and are unaffected:
  the create form's validation-error toast swaps `beforeend` (an empty fragment appends nothing) and
  `/ui/clear` sends no OOB at all. Every other htmx-4 behaviour the app relies on is unchanged
  (`htmx:after:*` events and `detail.ctx`, `hx-partial`, `hx-boost`, `hx-preserve`, `hx-vals`,
  OOB toasts, `htmx-config`). Note `config.defaultSwapEmpty` was also dropped from the empty-swap
  chain upstream; this repo never set it. Caught by the existing `crud.spec.ts` drawer-delete
  scenario — 51/52 e2e green on chromium (the lone failure, `persistence.spec.ts`, is a local
  harness port-reuse race — the restarted server hits `Address_In_Use` — and fails identically on
  beta6, so it is unrelated to this bump).
- **Odin toolchain `dev-2026-06` → `dev-2026-07a`** (`Dockerfile` ARG + the CI `ODIN_VERSION` env).
  Note the CI matrix's three hardcoded asset names had to change too, and two changed *shape*, not
  just the version substring: upstream's `dev-2026-06` shipped a truncated `odin-macos-arm64-dev-06`
  and an arch-less `odin-windows-dev-2026-06`, while `dev-2026-07a` is regular
  (`odin-macos-arm64-dev-2026-07a`, `odin-windows-amd64-dev-2026-07a`). A version-only bump would
  have 404'd the macOS and Windows legs — all three URLs were verified to resolve before landing.
  Upstream's notable changes here: Linux now defaults to **PIE + full RELRO** and C-vararg handling
  tightened; neither affected this codebase (clean `-warnings-as-errors` build, 156/156 e2e).
- **Dependency sweep — low-risk pass.** Every pin checked against upstream and bumped where safe:
  - **Debian base `bookworm-slim` → `trixie-slim`** (Debian 13.6, both Dockerfile stages — they must
    match for glibc). Bookworm's *regular* security support ended 2026-07-12 (LTS-only from there),
    which made this the time-sensitive one. Brings clang 19 (was 14) and glibc 2.41 (was 2.36).
  - **htmx `4.0.0-beta5` → `4.0.0-beta6`** (+ new SHA-256 in `prepare.sh`/`prepare.bat`). One
    breaking change upstream — `htmx:swap:finally` renamed to `htmx:finally:swap` — which this repo
    never referenced; all seven htmx-4 behaviours the app relies on are unchanged.
  - **SQLite `3.53.3` → `3.53.4`** (amalgamation + new SHA-256; same 3.53 branch, patch only).
  - **GitHub Actions onto their Node 24 majors**: `checkout@v4→v7`, `cache@v4→v6`,
    `upload-artifact@v4→v7`. Note `upload-artifact@v5` is a trap — it advertises Node 24 but still
    declares `using: node20`; v6 is the true minimum. `msvc-dev-cmd` is deliberately **held** at
    v1.13.0 (upstream stale since 2024-03, still Node 20), so one deprecation warning remains by
    design. `setup-flyctl` is no longer floating on `@master` — pinned to SHA `ed8efb33` (tag 1.6).
  - **Checked and already current:** `odin-http` (submodule `112c49b` = upstream HEAD).
  - **Deliberately held: Playwright.** npm has 1.62.0, but the matching CI container image is not
    published yet — `mcr.microsoft.com/playwright:v1.62.0-jammy` 404s (verified against the full
    registry tag list; playwright.dev's docs page claims otherwise but just templates the version
    number in). The npm package and the image tag must move together, so both stay at 1.61.1.
- **Load tests re-run for 1.0** — [`load-tests/RESULTS.md`](load-tests/RESULTS.md) refreshed on the
  current SQLite build (2026-07-01, Ryzen 5800X, `THREADS=1` vs `16`, `:memory:`). Reads scale **~4×**
  (search 4.6×, pages 4.2×, list/mixed 4.0–4.1×, api 3.8×); the `detail` events-JOIN is the worst
  read at **1.9×** and flat past 50 VUs — the single shared connection's exclusive lock, the concrete
  case for per-thread WAL connections. Writes ~2×, `static` ~2.3× (peaks **~2.3 GB/s** over
  loopback), **0% errors through 200 VUs**; a file DB costs **~3×** on writes. The doc now leads with
  SQLite (the current store) and demotes the pre-SQLite in-memory numbers to a historical note.
- **Simpler toast observer.** `watchToasts` (`app.js`) watches `#toasts` directly again instead of the
  whole `document.body` subtree — a workaround that's unnecessary now that `#toasts` is `hx-preserve`'d
  (so it's the same node across boosted navigations). Same behaviour, narrower scope; the toast e2e
  still passes.

## [1.0.0] - 2026-07-01

First tagged release: the project is now a **template-ized starter skeleton** (Phase F). It's a
GitHub *template repository* with a `tools/init` rename script (`--minimal` also strips the demo to a
one-page Notes starter, guarded in CI), a centralized brand, and starter docs
([`README`](README.md) "Using this as a starter", [`docs/STRIP.md`](docs/STRIP.md)). The bundled
contacts/events console — Odin + HTMX + SQLite in one self-contained binary, with a multi-style theme
library, boosted SPA-like navigation, and browser + load suites gating CI — is the **worked example**
you clone and strip, not a product to finish. Everything below shipped continuously to the live demo
pre-1.0; **1.0.0 marks the point it became clone-and-go.**

### Fixed
- **A toast no longer vanishes when you navigate.** A boosted nav swaps the `<body>`, which was
  wiping any live toast along with `#toasts`. `hx-preserve` on `#toasts` keeps the node (and its
  toasts) across the swap, so a toast rides through a page change and retires on its own schedule.
  Pinned by e2e.

### Added
- **`tools/init` — a rename script for starting a new project** (Phase F → 1.0). An Odin program
  (`odin run tools/init -- <new-name>`) that renames the skeleton in one pass across a fixed, audited
  file set: the binary (`demo`), the Fly app + Docker image, the apollo-11 service + volume, the
  `main.odin` banner, the e2e package names, and the three `brand.odin` constants (`--wordmark` /
  `--suffix` / `--repo` override the derived defaults). Name validation + a confirm prompt guard it.
  The tool is itself Odin — the skeleton's tooling stays on the stack it teaches. The repo is also a
  GitHub *template repository* now, and the README's "Using this as a starter" walks the
  use-template → `init` → keep-vs-strip path.
  - `--minimal` additionally **strips the demo to a one-page Notes starter** — the full
    model→repo→service→view→controller stack over a single entity, keeping the shell, theme, data
    layer, and test/deploy harness. It deletes the contacts/events domain, the demo pages, and their
    specs/scenarios, then drops in minimal templates (`tools/init/minimal/`, embedded via `#load`).
    Validated end-to-end: renamed + stripped app builds `-warnings-as-errors`, runs, and passes a
    fresh 4-test e2e suite across all three engines.
  - CI **`minimal` job** guards the templates from rotting: it strips a fresh checkout to the Notes
    starter and runs its e2e (global-setup builds `-warnings-as-errors`, so one job covers compile-
    and runtime-rot, and the rename path too). Chromium only; gates deploy alongside build + e2e.
- **About page** (`/about`) — a content page describing the skeleton (Odin + HTMX + SQLite in one
  binary, the demo as the worked example) with a button linking to the source on GitHub. Added to the
  primary nav (boosted like the rest). The repo URL is a `BRAND_REPO` constant in `brand.odin` —
  point it at your fork — alongside the brand wordmark/suffix; new `info` + `github` icons. e2e: the
  page opens from the nav and the GitHub link is present and safe (`target=_blank`, `rel=noopener`);
  the 390px responsive sweep now covers it too. **51 e2e total.**
- **SPA-like navigation via `hx-boost`.** The brand and primary-nav links are boosted: htmx fetches
  the page, swaps the `<body>`, and pushes history instead of a full document load. Navigating
  between pages no longer re-parses the document, re-evaluates CSS/JS, or re-runs the theme pre-paint
  script (so no flash), and with `transitions` on it crossfades. Server work and bytes are unchanged
  (whole pages are still rendered) — this is a client-side / perceived-speed win, not a throughput
  one. `hx-boost` sits on each link (htmx 4 doesn't inherit it from `<nav>` the way htmx 2 did) and
  is scoped to internal HTML links, so the JSON-API tile and the no-action search/filter forms keep
  their normal behaviour. To stay correct under a body swap, `app.js` hardens its per-node state: the
  toast-retire `MutationObserver` watches `document.body` (stable) instead of the swapped `#toasts`,
  and the dashboard count-up + theme-picker pressed-state re-init on `htmx:after:process` (both made
  idempotent). New e2e: nav swaps in place without a reload and updates the `<title>`; toasts still
  auto-retire after a boosted nav. **49 e2e total.**
- **Events — a second table, related to contacts.** `events(actor_id, target_id → contacts,
  ON DELETE CASCADE, kind, at, note)` (`migrations/0002_events.sql`) records interactions *between*
  two contacts. The detail drawer's activity feed is now **real data**: `event_timeline` JOINs the
  events back to contacts to resolve the other party, rendered as a one-click jump (replacing the
  deterministic-fake `service_activity`). Deleting a contact cascades its interactions. New domain
  types (`models.Event`/`Event_Kind`/`Interaction`), seeded deterministically. End-to-end at par:
  model + repository + service + view + e2e + load. New e2e: the FK cascade (delete a contact → its
  interactions vanish); the detail `load` scenario now exercises the JOIN. **42 e2e total.**

### Changed
- **Phase F docs — `docs/STRIP.md` + `USE_CASES.md` re-skin** (Phase F → 1.0). New
  [`docs/STRIP.md`](docs/STRIP.md): a demo-vs-scaffold map and file-by-file walkthrough for removing
  the contacts/events demo by hand, cross-linked to `init --minimal` (the automated version) and the
  CLAUDE recipes. `docs/USE_CASES.md`'s old "flagship (the app's direction)" section is rewritten as
  "the worked example" (built, not a direction to chase), the retired product-depth items (bulk
  actions, a named console) are named as out-of-scope, and the "read first" banner is tightened. With
  these + the template repo, `init`, and `init --minimal`, **Phase F (template-ize) is complete.**
- **Brand/app name centralized for renaming** (Phase F → 1.0). `app/src/views/brand.odin` now holds
  `BRAND_WORDMARK` (the topbar wordmark) and `BRAND_SUFFIX` (the `<title>` / og:title suffix), read
  only by `layout`. Renaming the skeleton's display name is now a two-constant edit instead of
  literals scattered through the views. Output is byte-identical; the remaining name touch-points
  (binary/`fly.toml`/`Dockerfile` names, the `main.odin` banner) are the `init` script's job.
- **Quality pass: dropped a needless indirection, fixed stale copy.** The body-reading handlers that
  need only the response (`contacts_create`, `validate_email_field`, `forms_submit`) now pass `res`
  directly through `http.body`'s user pointer (odin-http's own idiom) instead of each allocating a
  `Form_Ctx` whose `id` they never set; `Form_Ctx` remains only for `contacts_update`, which needs
  the row id. Four user-facing strings that still called the store "in-memory" now say SQLite
  (in-memory is just the default `:memory:` mode; a real deploy persists to a file).
- **Reframed the project as a starter skeleton** (docs only). It's a template you clone, rename,
  strip, and build on — the contacts/events admin app + theme library are the *worked example*, not
  a product to finish. `TODO.md` rewritten around it: a **Phase F → 1.0** "template-ize" roadmap
  (GitHub template, an `init` rename script, brand parameterization, a starter README, a
  `docs/STRIP.md`), a **1.x** of what every new site needs (**auth/sessions/CSRF**, per-thread WAL
  connections, a second entity as an "add your own resource" example), and **stretch** goals
  (a `--minimal` variant, common-need recipes, export/a11y). Product-depth items (bulk actions, a
  named console identity) retired as goals. README + `docs/USE_CASES.md` reframed to match.
- **htmx 2 → 4 (pinned to 4.0.0-beta5).** `prepare.*` now pin htmx exactly — a specific version
  **and a SHA-256 check** (replacing the floating `htmx.org@2`) — same reproducibility discipline as
  `ODIN_VERSION` and the SQLite amalgamation; the embedded copy drops ~51 KB → ~36 KB. Migration
  fixes for htmx 4's breaking changes, all caught by the e2e suite:
  - **Config keys renamed** in the `htmx-config` meta: `defaultSwapStyle` → `defaultSwap`,
    `globalViewTransitions` → `transitions`.
  - **`htmx:load` → `htmx:after:process`** for re-initialising swapped content (range-slider fill).
  - **Form auto-reset moved from `hx-on` to `app.js`.** htmx 4's `htmx:after:request` carries
    `event.detail.ctx` (no `.successful`) and the reset is scoped by `ctx.sourceElement` on
    `form[data-reset-on-success]` — robust whether the form's target is inside it (`#form-result`)
    or elsewhere (`#contact-tbody`), and a child field's validation can't trip it.
  - **Form bodies decode `+` as space.** htmx 4 sends spaces as `+` (the standard); odin-http's
    `body_url_encoded` only percent-decodes, so controllers parse POST bodies with a new `body_form`
    helper (`+`-aware, like `query_decode`). This was the latent bug behind broken creates/edits.
  - **OOB table-row refresh via `<hx-partial>`.** htmx 4's OOB `querySelectorAll` doesn't descend
    into `<template>`, and a response starting with the non-table `<aside>` drops a trailing bare
    `<tr>`; the drawer-edit now wraps the row in `<hx-partial hx-target="#contact-N" hx-swap=…>`.
    Removed the now-dead `oob` arg from `view_contact_row`.
  - **Fingerprinted asset URLs (cache-bust without a query).** The page now links content-addressed
    paths — `/static/app.<hash>.css`, `/static/htmx.<hash>.min.js`, `/static/app.<hash>.js` — instead
    of a `?v=<hash>` query (cleaner, and `htmx.min.js` previously had *no* buster, so Cloudflare
    served a stale htmx after the 2→4 bump until its URL changed). `serve_static` accepts both the
    hashed and bare names; hashed URLs are served `Cache-Control: immutable` (the bytes for that URL
    can't change), bare names keep ETag + revalidation.
- **Docs accuracy pass.** Brought the prose docs up to date with the SQLite store + events: the
  top `README.md` no longer calls the e2e/load suites "plans only" (both are implemented and gate
  CI); `CLAUDE.md`, `PHILOSOPHY.md`, `app/README.md`, the e2e/load READMEs+PLANs, and the
  apollo-11/infra docs now reflect three dependencies (HTMX + odin-http + SQLite), the C-toolchain
  requirement, `DB_PATH`, the exclusive-lock concurrency model, the `data-style`×`data-scheme` theme
  system, the repository split, and the events JOIN.
- **Repository split into common + per-entity files.** `repo_sqlite.odin` → `repo.odin` (the shared
  connection/lock, migration runner, and `exec`/`prep`/`bind_text`/`clone_col`/`scalar_int` helpers)
  + `contacts.odin` (the seven `repo_*`) + `events.odin` (`event_timeline`). Adding a table is now a
  new file + a migration, no churn to the plumbing. Added `repo_close` (finalises statements,
  checkpoints the WAL) wired via `defer` in main.
- **Load tests re-measured for SQLite** ([`load-tests/RESULTS.md`](load-tests/RESULTS.md)). Reads
  still scale with threads but ~3–4× (vs the in-memory store's ~5×) — the v1 single shared connection
  forces an *exclusive* lock on reads too; the new `detail` events-JOIN scales worst (1.9×), the
  measured trigger for per-thread WAL connections. A file DB costs ~2.7× on writes (WAL + fsync) and
  nothing on reads. 0% errors throughout.
- **Persistent SQLite data layer** — replaces the in-memory POC store. The seven `repo_*`
  procedures are reimplemented over SQLite (`src/repository/repo_sqlite.odin`) behind a ~15-decl
  amalgamation binding (`src/sqlite/`); **services, views, controllers, e2e and load suites are
  unchanged** (the whole point of the repository seam). Backend selected by **`DB_PATH`**:
  `:memory:` (default — a real in-RAM SQLite, seeded fresh per boot, gone on exit; what the e2e/load
  suites get, identical isolation to before) or a file path that **persists**. WAL +
  `busy_timeout`/`foreign_keys`/`synchronous=NORMAL`; plain-SQL migrations (`migrations/0001_init.sql`,
  `#load`ed) behind a `schema_version` table; `repo_seed` seeds only an empty store; statements
  prepared once. Concurrency v1: one shared connection under the existing `sync.RW_Mutex` taken
  **exclusively** for every op (a single connection's prepared statements can't be shared across
  concurrent readers — parallel reads return with per-thread WAL connections, deferred to load-test
  evidence). One new e2e test: **data survives a process restart** (41 e2e total). See
  [`docs/DATA_IMPL.md`](docs/DATA_IMPL.md).
- **`prepare.*` fetches + compiles the SQLite amalgamation** (the htmx precedent, not a submodule):
  a pinned, **SHA-256-verified** `sqlite-amalgamation-3530300.zip` (SQLite 3.53.3) → unzipped into a
  gitignored `app/vendor/sqlite/` → compiled to a static lib (`sqlite3.lib` via `cl /MT` on Windows,
  `sqlite3.a` via `clang`+`ar` on unix), idempotently. A **C toolchain is now a hard requirement**;
  `prepare` checks for it and prints a per-OS install hint. The Dockerfile and CI gain
  `clang binutils unzip`. apollo-11 mounts a named volume at `/data` (`DB_PATH=/data/data.db`) for a
  durable live demo; Fly stays `:memory:` until a volume is provisioned (documented in `fly.toml`).
- **Data-layer implementation plan** ([`docs/DATA_IMPL.md`](docs/DATA_IMPL.md), docs only) — a
  concrete "how" for replacing the in-memory POC with **SQLite** in Odin: the binding choice
  (vendor vs amalgamation), schema + boot-time migrations, the seven `repo_*` as prepared SQL, the
  allocator discipline (clone column text into the temp arena — the same guarantee `snapshot()`
  gives today), how WAL maps onto the server's reader/writer model, build/deploy/ops, and the
  rollout. Complements `DATA.md` (the why/when).
- **`list` load scenario** (`GET /contacts?status=&sort=`) — the filtered/sorted table-region
  fragment, closing the last load-parity gap from Phase D; wired into the run driver (~38k req/s).
- **Overview → tool wiring** (Phase D increment 4, product cohesion). The dashboard stat cards are
  now links into the data view: *Active*/*Invited* → the table filtered to that status, *Avg.
  engagement* → sorted by score, *Total* → the full table. `page_data` now honours a `sort` query.
  Ties the four pages into one console (the overview drives the working tool) rather than four
  separate demos. e2e covers the drill-through.
- **Status quick-filters on the data table** (Phase D increment 3). A row of filter chips (All /
  Active / Invited / Disabled) above the table; the active one is marked, and the filter threads
  through the request like search/sort/page (`service_page` gains a `status` arg; every region link
  carries `&status=`), so filtering composes with text search and survives sort/paginate. e2e covers
  it; no new endpoint (a query param on the existing `/contacts` region).
- **Contact detail drilldown** (Phase D, flagship app — first increment). Clicking a row's name
  (`GET /contacts/:id`) opens a drawer with the full record (role, status, an engagement meter,
  id), a **derived activity trail** (a plausible, deterministic timeline — there's no persisted
  event log yet, see `docs/DATA.md`), and **related** contacts (others in the same role, each a
  one-click jump to its own detail). Re-skins under every style via tokens. The service layer gains
  `service_activity`/`service_related`; new `GET /contacts/(%d+)` route. e2e covers
  open/content/related/close; `load-tests/scenarios/detail.js` keeps it at par (~42k req/s locally).
- **Actionable detail drawer** (Phase D increment 2). The drawer is no longer read-only: **inline
  edit** (name/email/role/status/engagement, swapped in place — the slide doesn't re-animate),
  **cycle status**, and **delete** — all from the drawer. Edits/cycles re-render the drawer *and*
  refresh the table row behind it via an OOB swap (the `<tr>` wrapped in a `<template>` to survive
  the non-table swap context); drawer-delete closes the overlay and OOB-removes the row.
  `repo_update` now persists `score`. e2e covers edit+OOB-row, cycle, delete; the `write` load
  scenario becomes create→edit→delete so `POST /contacts/:id` is at par.
- **`/components` style showroom.** The components page opens with a catalog of all **6 styles ×
  23 schemes** — each style labelled with its scheme swatches; click any swatch to jump straight to
  that exact `style + scheme` (`setTheme` applies + persists) and the whole page re-skins live, the
  components below acting as the live preview. The active swatch is marked. No new server surface
  (client-side, like the picker), so load-tests stay at par; e2e covers the jump + persistence.
- **Arcade (video-game) style** (Phase C, 5/5 — the style library is complete). A chunky neon HUD:
  glowing panels and buttons, heavy uppercase type, vibrant gradients. Three schemes — **Arcade**
  (dark magenta/cyan), **Synthwave** (dark pink→orange sunset), and **Pop** (a clean candy-bright
  light variant). Final library: **6 styles, 23 schemes** (Modern 7, Skeuomorphic 3, Terminal 4,
  Brutalist 3, Editorial 3, Arcade 3), each with at least one light scheme, every one a pure
  `[data-style]` block over untouched component HTML.
- **Editorial / Paper style** (Phase C, 4/5). Serif throughout, warm and print-like: hairline
  rules, a single restrained accent, small-caps eyebrows, a ruled page header, title-case buttons
  (not shouty). Three schemes — **Manuscript** (light, ink on warm white, claret accent), **Sepia**
  (aged warm paper), and **Night** (a dark reading mode, cream on warm brown with gold).
- **Brutalist style** (Phase C, 3/5). Raw and loud: zero radius, thick borders, flat fills, and
  hard offset shadows that shift on press; heavy uppercase type; inverted nav block. Ships **dark
  *and* light** — **Paper** (light, cobalt/red), **Ink** (dark, white-on-black), and **Acid** (a
  loud acid-yellow with black + magenta).
- **Terminal / CRT style** (Phase C, 2/5). Monospace throughout, phosphor text with a soft glow,
  boxy thin-bordered panels, solid-fill uppercase buttons, and faint CRT scanlines (a single fixed
  gradient — cheap). Four schemes: **Green** (classic phosphor), **Amber**, **IBM** (cool
  blue/white), and **Paper** (a light teletype printout — every style now ships a light scheme).
- **Skeuomorphic style** (Phase C, first of five). A tactile treatment built entirely from layered
  gradients + bevel shadows — **no image assets**: raised panels with an inset top highlight,
  recessed (inset-shadow) form fields, glossy buttons that physically press on `:active`, a domed
  range thumb in a recessed groove. A per-style **bevel kit** (`--hi`/`--lo`/`--gloss`) drives it,
  tuned by three schemes: **Aqua** (light, lickable blue), **Graphite** (dark brushed metal), and
  **Brass** (warm wood + brass). Adding it took only a `[data-style="skeuo"]` block + scheme
  palettes + the picker entries — the component HTML is untouched. e2e now also covers switching the
  *style* axis and revealing that style's schemes. Remaining: Terminal, Brutalist, Editorial, Video-game.
- **Theme picker — two axes, `data-style` × `data-scheme`** (Phase B of the style library). The
  page shell carries `data-style` (the treatment) and `data-scheme` (the palette) on `<html>`,
  rendered server-side as `modern`/`midnight` (works with no JS) and restored from `localStorage`
  by the pre-paint script (no flash). A stateless topbar picker (a `<details>` popover) applies and
  persists the choice via tiny vanilla JS — no server endpoint, so load-tests stay at par. The CSS
  splits the old single dark/light theme into the `[data-style][data-scheme]` token contract;
  **Modern** ships **seven schemes** — Midnight, Daylight, Nebula, Aurora, plus warm **Ember**
  (dusk) and **Sandstone** (warm light) and cool **Ocean**. A new `--on-accent` token keeps text
  readable on light-accent gradients (so buttons aren't white-on-bright). e2e covers switch +
  persist. Phase C layers in the additional styles (Skeuomorphic, Terminal, Brutalist, Editorial,
  Video-game).
- **Vision + direction docs.** [`PHILOSOPHY.md`](PHILOSOPHY.md) (server-rendered HTML, browser as
  runtime, JS only where the browser can't, the Odin↔HTMX shared worldview, the honest 90/10),
  [`docs/USE_CASES.md`](docs/USE_CASES.md) (the sweet spot + the decision to evolve the sampler into
  one flagship internal admin console), and [`docs/DATA.md`](docs/DATA.md) (the repository seam, and
  SQLite→Postgres as the path past the in-memory POC). Wired into `CLAUDE.md`; phased plan in `TODO.md`.
- Initialized the repository as git and made the first commit.
- Adopted Conventional Commits; documented the spec and changelog mapping in `CLAUDE.md`.
- Infrastructure plan ([`infra/PLAN.md`](infra/PLAN.md)): remote hosting, CI/CD, deployment,
  and where to run e2e / load-tests — free / low-cost.
- Deployment: `Dockerfile` (two-stage, pinned Odin `dev-2026-06`, single-binary + static
  runtime), `fly.toml` (Fly.io, always-on `shared-cpu-1x`), and `.dockerignore`.
- CI/CD: `.github/workflows/ci.yml` — build with `-warnings-as-errors`, smoke-test the binary
  (pages, static, JSON API, CRUD), and deploy to Fly.io on green `master`.
- `app/main.odin` reads `PORT` from the environment and binds `0.0.0.0` when `BIND_ALL` is
  set, so the binary is container-deployable (local default stays loopback).
- `GET /healthz` liveness probe (200 `ok`); wired as the Fly.io health check in `fly.toml`.
- End-to-end test suite ([`e2e/`](e2e/)): Playwright over a freshly built binary — navigation,
  search, components, forms, CRUD and assets, including the three regression bugs. Runs across
  all three engines (Chromium, Firefox, WebKit). Wired into CI as a gating job; deploy now needs
  both `build` and `e2e`.
- `compose.yaml` for an optional local prod-parity run (`docker compose up --build`) — builds
  the same image Fly deploys. Not required for dev; handy for load-tests against a prod-like
  container.
- Favicon (`app/static/favicon.svg`, linked from the page head): a fusion mark — htmx's `</>`
  brackets on the project's violet→cyan gradient tile with the app's bolt accent.
- SEO: a **page-specific `<meta name="description">`** (the item Lighthouse flagged) plus Open
  Graph `og:type`/`og:title`/`og:description` on every page, threaded through `render_page`.
- Two-host deploy ([`deploy/apollo-11/`](deploy/apollo-11/)): a sudo-free `deploy.sh` (+ compose,
  README) that builds the self-contained image **on** a home Docker box from source tarred over
  SSH, joins it to the existing nginx-proxy-manager `npm` network for a subdomain, and publishes a
  host port for proxy-free load testing. IP/hostname/domain are parameterized. Required
  `seccomp=unconfined` so odin-http's io_uring isn't blocked by Docker's default profile (Fly
  dodged this via Firecracker). Yielded the two-host numbers in
  [`load-tests/RESULTS.md`](load-tests/RESULTS.md): byte-heavy endpoints saturate the 1 GbE wire
  (~912 Mbit vs 2.4 GB/s loopback), and NPM+TLS on the shared box costs ~12×.
- Load tests ([`load-tests/`](load-tests/)): **k6** scenarios for every endpoint class —
  `static`, `pages`, `search`, `api`, `write` (create→delete), and a `mixed` 90/10 read/write
  blend — sharing one warmup→measured-window shape with per-phase thresholds and a
  dependency-free JSON/CSV summary. A `run.sh`/`run.bat` driver builds the app `-o:speed`,
  launches a fresh server per scenario × VU level (clean store), sweeps the VU curve, and
  stitches `results/summary.md`. `bombardier` baselines run if present. Numbers and the
  single-thread-ceiling reading land in [`load-tests/RESULTS.md`](load-tests/RESULTS.md).

### Changed
- **CI builds on all three platforms now**, not just Linux. The `build` job is a matrix over
  `ubuntu-latest`, `macos-latest` (Apple Silicon / arm64-darwin — exercises odin-http's **kqueue**
  path under `core:nbio`) and `windows-latest` (the primary dev platform — **IOCP** path). The
  ubuntu leg is unchanged; e2e and deploy are untouched. Each leg downloads its own **verified**
  Odin release asset (the names are irregular: the macOS-arm64 asset is tagged `…-dev-06`, the
  Windows asset carries no arch and unpacks to `dist/`), with `runner.os` in the cache key. C
  toolchain per OS so Odin can link — apt `clang` (Linux), Xcode CLT (macOS),
  `ilammy/msvc-dev-cmd` before the build (Windows); the build `-out` carries a per-OS extension
  (`.exe` on Windows). One shared bash smoke script boots the binary and hits the same endpoints on
  every OS, with `DB_PATH=:memory:` set for forward-compat with the planned SQLite layer.
- Refactored the backend into one Odin **package per layer** under `app/src/`
  (`models`, `repository`, `services`, `views`, `controllers`, and `src/` = entry `main`+routes),
  so the layering is compiler-enforced rather than convention. Cross-layer calls are now
  qualified (`repository.repo_list`, `views.view_dashboard`, …). Build entry is `odin build src`;
  `htmx.min.js` is `#load`ed from `controllers`. Behaviour unchanged (93/93 e2e green).
- Vendored odin-http as a pinned git submodule (`app/odin-http`, commit `112c49b`) for
  reproducible CI/CD builds; `prepare.*` stays the local-dev convenience path.
- e2e now runs **fully in parallel**: each Playwright worker spawns its own server on its own
  port with an isolated in-memory store (`global-setup.ts` builds once, `fixtures.ts` spawns
  per worker), replacing the single shared server + `workers: 1`. ~2.5× faster locally. On CI
  the engines are **sharded across concurrent runners** (a browser matrix) instead of piling
  workers onto one CPU-bound runner, and each shard runs in **Playwright's official Docker
  image** (which also ships node/npm) so the browsers + OS deps are preinstalled (no per-run
  install — that was the biggest, most variable cost). `workers` tracks the runner's cores.

### Performance
- **Cache-busting for CSS/JS.** Asset URLs in the page `<head>` now carry a `?v=<content-hash>`
  (computed once at startup, exposed as `views.ASSET_VERSION`). Since the HTML is dynamic and never
  cached, a changed stylesheet yields a new URL clients fetch immediately — no more serving the old
  `app.css` until `max-age` expires (the cause of needing a hard refresh after deploys). Verified on
  both deployments.
- **Moved the Fly deployment from `iad` (US-East) to `fra` (Frankfurt)** so it serves the
  primary (European) audience from nearby. Latency is RTT-bound, not compute-bound (the server
  answers `/healthz` in sub-ms), so over IPv4 a full page load dropped from ~850 ms to **~160 ms**.
  Fly's *IPv6* anycast additionally mis-routed some EU ISPs to a far edge (~785 ms over v6);
  fronting the origin with a **proxied Cloudflare record** (Full-strict, cert validated via DNS-01)
  fixed it — page TTFB is now **~105 ms on both v4 and v6** from a nearby Cloudflare edge, with
  `/static` edge-cached.
- **Multithreaded server.** The event loop now runs one nbio thread **per core** (was pinned to
  one); `THREADS` env overrides. The in-memory store, previously lock-free *because* it was
  single-threaded, is now guarded by an `sync.RW_Mutex` — reads share, writes are exclusive — and
  the repository hands callers **temp-arena snapshots** (structs copied, strings cloned under the
  lock) so nothing aliases store memory across a concurrent delete/realloc. Load-tests sweep
  `THREADS=1` vs `N` against the same binary for the before/after; numbers in
  [`load-tests/RESULTS.md`](load-tests/RESULTS.md).
- Static assets now send `Cache-Control: public, max-age=3600` and a strong **ETag** (a content
  hash computed once at startup), with conditional `304 Not Modified` handling — repeat page
  loads reuse cached htmx/CSS/JS instead of re-downloading, and a redeploy changes the hash so
  clients never serve stale assets.
- All static assets (`app.css`, `app.js`, `favicon.svg`, htmx) are now **embedded into the
  binary** and served from memory, replacing the disk-served `respond_dir` path. The deployed
  artifact is a single self-contained file (the Dockerfile no longer ships `static/`), there
  are no per-request disk reads, and path traversal is structurally impossible.
- First page load: `defer` the embedded htmx script so it no longer blocks rendering (the
  pre-paint theme script stays synchronous to avoid a flash). htmx still initialises before
  `DOMContentLoaded`; the full e2e suite passes unchanged across all three engines.

### Fixed
- **Broken mobile layout.** The topbar (brand · nav · search · picker) was a rigid single row that
  forced a **page-wide horizontal scroll on phones** (~184px past a 390px viewport), with the search
  box clipped; the data table also clipped its right-hand columns. Now: below **720px** the search
  drops to a full-width second row (brand mark only, icon-only nav, picker right-aligned); the nav
  labels hide until they genuinely fit (**≤940px**, was 880 — which closed an 881–939px overflow
  band on small laptops); and below **560px** the data table folds email/role/engagement into the
  detail drawer (name · status · actions remain), with `.table-scroll` still catching anything
  wider. **Zero horizontal overflow from 320–1280px**, desktop unchanged; pinned by 4 e2e tests.
- **Reflected HTML-injection via the `sort` query param** (security). The data table reflected
  `sort` into its `hx-get="…"` attributes (filter chips + pager) **without** the `url_encode` its
  sibling params (`q`, `status`) already used, so a crafted value — e.g.
  `/data?sort="><img src=x onerror=…>` — could break out of the attribute on a directly-navigable,
  `text/html` GET endpoint. `sort` is now `url_encode`d at every reflection site (legit values like
  `score_desc` are unreserved and round-trip unchanged; `sort_th` was already safe, emitting only
  derived column literals). Pinned by an e2e regression test.
- Range slider fill was missing under Terminal, Brutalist, Editorial and Arcade — each style's
  `input` rule tied the range track on specificity and (being later) clobbered the fill layer (the
  same issue the skeuo style hit). Each now restores the fill on its
  `[data-style] input[type="range"]` rule, matched to the style (phosphor glow, flat accent, a
  refined gradient, neon). Completes the style library.
- Range slider fill lagged behind the thumb: the shared `input` rule transitioned `background`,
  which animated the `background-size` that paints the fill. The range track now opts out
  (`transition: none`), so the fill tracks the thumb instantly while the thumb keeps its own
  transform transition.
- Low-contrast schemes: the green scheme (Aurora) was washed out and white button text was hard to
  read on bright accents. Aurora is rebuilt around a vivid emerald with lifted muted text, and the
  new `--on-accent` token flips button/badge text dark on light-accent schemes.
- Linux/CI build: `prepare.*` now creates `bin/` (odin's `-out:` won't), the shell scripts
  carry the exec bit, and the Dockerfile/CI invoke `prepare` via `sh` — so the build no
  longer depends on a pre-existing `bin/` or the exec bit surviving a Windows-origin context.
- Page `<head>` was emitting `%!(MISSING)`: Odin's `fmt` treats `{`/`}` as directives, so the
  `htmx-config` JSON and the theme pre-paint script were mangled (htmx ran on defaults and
  threw on `JSON.parse`). The cycle button's `hx-vals` JSON had the same break. Brace-bearing
  literals now bypass `fmt` (written with `w()`). Caught by the new e2e suite.
- Out-of-band toasts (form submit, contact create) now keep their `.toast` wrapper — htmx's
  positional OOB swap appends an element's children, so the toast is wrapped in a carrier.

## [0.2.0] — 2026-06-26

### Added
- Project docs for efficient single-prompt sessions: `CLAUDE.md` (architecture, code/CSS/JS
  aesthetics, odin-http API cheat sheet, allocator model, Odin/HTMX gotchas, recipes), this
  `CHANGELOG.md`, and `TODO.md`.
- Test plans: `e2e/PLAN.md` (Playwright browser tests) and `load-tests/PLAN.md` (k6/bombardier
  throughput tests). Plans only — not yet implemented.
- Top-level `README.md` describing the `app/` + `e2e/` + `load-tests/` layout.

### Changed
- Restructured the repo: the entire application moved into `app/`, with `e2e/` and
  `load-tests/` as siblings. Run/prepare scripts are location-independent (`%~dp0` /
  `dirname`), so they work unchanged from `app/`.

### Fixed
- Invite dialog no longer closes on an outside (backdrop) click, so a half-typed field can't
  be lost by accident. Dismissal is explicit (× / Cancel).
- `/forms` no longer clears the name and email fields when the email validates. The email
  field's `htmx:afterRequest` was bubbling to the form and triggering `reset()`; the handler
  is now guarded with `event.target === this`.
- Range sliders now paint their fill to match the thumb as it moves (was a static 60%). The
  fill is driven by a `--fill` custom property updated from `app.js`.

## [0.1.0] — 2026-06-26

### Added
- Initial Odin + HTMX showcase.
  - Pure-Odin backend on `odin-http` (server, router, request/response over `core:nbio`);
    HTMX embedded into the binary via `#load` and served from memory; CSS/JS from disk.
  - Layered backend: models → repository → services → controllers → views.
  - Pages: Dashboard, Components gallery, Forms (with live inline validation), Data & CRUD.
  - Global debounced HTMX active-search plus a plain JSON API (`/api/search`).
  - In-memory CRUD over POST/DELETE; single-threaded lock-free store.
  - Hand-written, token-driven CSS with a dark/light theme toggle and snappy animations.
  - Cross-platform `prepare`/`run` scripts (Windows / Linux / macOS).

[Unreleased]: https://github.com/alexh95/odin-htmx-starter/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/alexh95/odin-htmx-starter/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/alexh95/odin-htmx-starter/compare/v1.2.1...v2.0.0
[1.2.1]: https://github.com/alexh95/odin-htmx-starter/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/alexh95/odin-htmx-starter/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/alexh95/odin-htmx-starter/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/alexh95/odin-htmx-starter/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/alexh95/odin-htmx-starter/releases/tag/v1.0.0
