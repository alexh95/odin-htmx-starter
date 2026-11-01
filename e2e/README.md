# End-to-end tests

Playwright browser tests for the starter's profiles. They drive real browsers against a freshly
built profile binary and assert on what happens *after* HTMX swaps land in the DOM — the bits curl
can't see. See [`PLAN.md`](PLAN.md) for the design rationale, and the repo's `docs/PLAN.md`
§19.1.2 for the matrix.

## Run

From this directory (npm — isolated test-only tooling, never shipped):

```sh
npm ci
npx playwright install --with-deps chromium firefox webkit   # one-time: fetch browsers
npm test                            # skeleton: three engines + the api project; -- --project=chromium narrows
```

`E2E_PROFILE` picks the profile under test: `skeleton` by default, in the three engines (Firefox
only in CI: it can't start on the dev PC) plus the `api` project; `lab` in the three engines too, and
`full` answers two hosts on one port (its lab host on `127.0.0.1`, Houston's on `localhost`), and a spec runs on
its own feature's host (`fixtures.ts`), skipped where its features sit on different hosts. `full-vanilla` (`full`'s
files on the vanilla client, CI only) runs the same chromium specs: the hyperscript-only ones skip themselves by
`BUILD.client`, so what runs there is the core flows and the twinned behaviours (D22).
`streams` in chromium and webkit (and firefox, in CI only); any other profile in chromium plus `api` (`E2E_PROFILE=minimal
npm test`). The servers run with the per-client stream caps lifted (`STREAM_CONNECTS`,
`STREAMS_PER_CLIENT`): the suite is one client opening far more streams than a person would. The lab's
drain-and-restart check needs a graceful stop, which a Windows child gets only from a
`-define:TEST_ROUTES=true` build (`E2E_BUILD_FLAGS`); in a release build it skips there.

Specs that never open a page (each talks HTTP, to the worker's server or its own) form the `api`
project in `playwright.config.ts`, so they run once rather than once per engine.

**Through a proxy** (CI's `e2e-proxy` job, PLAN §20.1): `E2E_PROXY=http://odin-htmx-starter.alexh95.com`
points the pages at a proxy in front of one server on `E2E_UPSTREAM_PORT` (8080, the port
`deploy/Caddyfile` forwards to), in chromium, one worker; the server takes the proxy's origin as its
own and listens beyond loopback, so a proxy in a container reaches it. The names are the real hosts', so
global-setup refuses to start unless the proxy's host resolves to this machine (a hosts-file line), and
a taken upstream port stops the run too (another server would answer for the suite). Node-side clients
still talk to the server direct; `tests/lab/proxy.spec.ts`, which runs only here, checks what the proxy
itself must do with streams. CI runs `lab` (`odin-htmx-starter.alexh95.com`) and `streams`
(`starter-streams.alexh95.com`) this way. Behind a proxy the server sees the proxy's container, not
loopback, so there a nick build lets anyone take a nickname (`ACCOUNTS_NICK_FROM=all`); specs that need the
LAN or an admin (ops's) start servers of their own and talk to them direct.

**Members** (`helpers/members.ts`): on a nick build a spec's members are browser contexts of their own,
each with a nickname picked at `/login`. The worker's server counts loopback as the LAN
(`LAN_CIDRS=127.0.0.0/8`) and fixes `ACCOUNTS_NICK_KEY`, so a nickname outlives a spec's restart; the bot's
mock is seeded (`BOT_SEED`) and quick (`BOT_DELAY_MS`).

`global-setup.ts` builds the profile once through `../build.sh <profile>` (`build.bat` on Windows),
which holds every flag (`-vet -strict-style -warnings-as-errors` and the further vet flags). It runs `prepare` first only
when prepare's outputs are missing or don't match its pins, so a run needs `odin` (and its
linker), plus **a C toolchain** whenever prepare has work to do (it compiles SQLite; on Windows,
that means an x64 Native Tools prompt). A prepare failure stops the run. It then asks the binary
what it mounts (`--features --json`). Each Playwright **worker spawns its own server** on a port
the OS picks, with an **isolated `:memory:` store** — which is what lets the suite run **fully in
parallel** across workers and engines. The server's env is pinned (`helpers/server.ts`), so a
`PORT` or `DB_PATH` exported in your shell can't redirect the suite to another server or your
`data.db`.

- `npm run test:ui` — interactive runner.
- `npm run test:headed` — watch it drive a real browser.
- `npm run report` — open the last HTML report.

On CI the engines are sharded across runners inside Playwright's official Docker image (browsers
+ OS deps + node/npm preinstalled), so there's no browser-install step there. The chromium shard
also runs the `api` project.

## Tags: which specs run on which profile

Specs live by feature, `tests/<f>/`, and carry a tag for every feature they touch: `@<f>`, or
`@<f>-<member>` when they need one member of a build family (`@contacts-sqlite`, `@platform-full`).
A spec in `tests/<f>/` always carries `@<f>`. `fixtures.ts` runs a spec only when the build has
every feature (and member) its tags name, and skips it otherwise, naming what's missing; an
untagged spec fails. `has('<tag>')` from `fixtures.ts` lets a shared spec branch on the build (the
cross-site guard forges a contact where there are contacts, a note where there are notes).
`--grep @contacts` narrows a run the usual way.

## Route coverage

Every server the suite starts gets a `/metrics` bearer, and `stopServer` keeps its per-route request
counters (`app_http_requests_total`) in `../app/build/coverage/e2e/<profile>/`. `tools/check parity`
holds them, and the load suite's, against the profile's routes (`bin --routes --json`): every route
needs a non-zero count from both suites, or a waiver with a reason in `../tests/parity-waivers.txt`
(PLAN §19.1.11). A route reached only by a click counts too.

## Layout

```
global-setup.ts        prepare if needed, build the profile through build.{sh,bat}, read --features --json
fixtures.ts            per-worker server (own port + isolated store) → parallel; the tag selection; has()
helpers/server.ts      starts a server (free port, pinned env, fails fast with its output) + get/post/del;
                       stopServer keeps the route counters
tests/
  platform/            what every profile serves: assets, routing, security headers + CSP, the cross-site
                       write guard, input limits, operations (probes, /metrics, /licenses, the access log),
                       SEO contract, canonical redirect, style defaults, responsive, navigation + theme
                       picker, backup (@platform-sqlite), escaping (every `_` a lone install and every
                       data-behave a twin, on every sitemap page; the hyperscript gate, on that client),
                       the client stack (PLAN §19): csp-clean (no violation on any sitemap page or in one
                       interaction per feature), csp-enforced (the policy refuses an injected hx-on, and the
                       nonce class strips an unnonced hx-get), harness-csp (what Playwright's own calls do
                       under the CSP) and bundle-race (assets held 400 ms: the streams still wire);
                       rbac (every row of `--routes` × every role × every host against the grants it
                       freezes; off the LAN, `.Lan_Only` rows are 404 for an admin too) and cross-site (every
                       write forged from a foreign page is 403 on every host, signed in; no foreign-Origin
                       upgrade becomes a socket), both api-only and side-effect free. headers and csp-clean
                       run on both of `full`'s hosts; behind a proxy `E2E_PROXY_LAB` names the lab host's
                       proxied origin beside `E2E_PROXY`'s
  dashboard/           the dashboard's figures come from the store
  gallery/             components (tabs, accordion, toasts, modal, drawer) and forms (validation, sliders)
  contacts/            CRUD, paging, search, ids, escaping, writes, 422s, events (FK), persistence
  home/ notes/ about/  the minimal profile's pages: the notes card, adding and refusing a note, about
  lab/                 the stream contract (spike S0.3's checks on the real stream and hub): protocol.spec
                       (03's Node-side checks and PLAN §8.2/§9's, api), engine.spec (sockets from the page),
                       extensions.spec (hx-sse, hx-ws, hx-multipart in the engine, the page contract, drain
                       and restart), pages.spec; streams.ts holds the SSE reader and the raw WebSocket client.
                       lab is built on the hyperscript client, so its run covers the behaviours and the gate
  scripting/           the nonce class: each response's nonce on every htmx element, hx-on, a trigger
                       filter, js: values, the password widget three ways and hs-include, Trusted Types;
                       streams-hxcsp.spec pins hx-csp on SSE, WebSocket and multipart fragments
  compat/              htmx-2-compat's semantics on its page only; hx-alpine-compat inert
```

The regression tests pin bugs fixed earlier: the modal keeps its field on a
backdrop click, `/forms` doesn't wipe name/email on validation, range sliders
paint `--fill` to match the thumb, a crafted `sort` param can't inject markup,
and a click isn't swallowed by a swap's view transition. That last one presses
with `mouse.down()` / `mouse.up()`: `locator.click()` waits a transition out,
which hides the race.

## Parity with load-tests

Per `CLAUDE.md`: every endpoint covered here also has a `load-tests/` scenario, and vice versa,
which the route counters now check rather than state. When you add a spec for a new endpoint, add
its load scenario in the same change (or a waiver with its reason). e2e proves *correct*;
load-tests prove *fast*.
