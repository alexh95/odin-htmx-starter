# odin-htmx-starter: the plan

**Date** 2026-10-25, revised 2026-10-26 · **Status** draft; Alex's answers of 2026-10-25 folded in, rounds 1–3,
including #1 (direct calls, no DI) through `docs/design/LEAN-COMPOSITION.md`, as round 3 chose it; the device roles of
2026-10-25 and 2026-10-26 folded in (`docs/design/DEVICES-SUMMARY.md`, §20.8); round 4 of 2026-10-26 folded in (Q33:
M14 Devices is scheduled); round 5 of 2026-10-26 folded in (Q6, Q34, Q35: the gate's references and the storm
budget). **M0 is done** (2026-10-26): the transition, and a decision record for each of S0.1–S0.12 in `docs/spikes/`,
whose changes are folded in below; M1 is next

**How this was made.** A research round (`docs/research/`, notes 01–13), then a design round (`docs/design/`);
`docs/design/DECISIONS.md` (D1–D45, Appendices A–C) is the source of truth for everything below. The lead architect's
`docs/design/RESOLUTIONS.md` (X1–X43) decided the open items this plan's writing round left, and X36–X43 those that
round 3's fold and the device inventory raised; they are folded in below, cited "(RESOLUTIONS X5)" where it helps, and
the ones that are Alex's judgement are questions Q29–Q33. Alex's answers (`docs/design/ANSWERS.md`, rounds 1–3 of
2026-10-25 and round 4 of 2026-10-26) are folded in and cited "(ANSWERS F2)". Round 3 chose the
lean composition of `docs/design/LEAN-COMPOSITION.md` ("LC", cited "LC §6"; its prototype evidence is LC §16 and
research note 14), which replaces the composition mechanism of D4–D10, D13, D15, D16, D18, D19, D21–D27, D29,
D31, D33–D37, D39, D40, D45 and X5, X29, X30, X33 where they differ (LC §15); everything else those decisions say
stands, and the plan cites both.

**How to read it.** §1 is one screen and can be read alone. §2 defines every shared name, and §22 holds the
milestones and the questions for Alex. Citations follow §2.1. **NEW** marks what no research note verified;
**UNVERIFIED (…)** names the spike, milestone or CI job that settles a claim; **Open:** marks a gap that no decision
or resolution settles yet.

## Contents

1. [Summary](#1-summary)
2. [Glossary and naming conventions](#2-glossary-and-naming-conventions)
3. [Identity, philosophy and the ledger](#3-identity-philosophy-and-the-ledger)
4. [Repo decision and transition](#4-repo-decision-and-transition)
5. [Architecture: layers, packages and the directory tree](#5-architecture-layers-packages-and-the-directory-tree)
6. [Composition: the feature contract, seams and implementation axes](#6-composition-the-feature-contract-seams-and-implementation-axes)
7. [Profiles, hosting units and the generator](#7-profiles-hosting-units-and-the-generator)
8. [Server substrate: the fork, streams, router, configuration, boot and drain](#8-server-substrate-the-fork-streams-router-configuration-boot-and-drain)
9. [Realtime: the hub and the page contract](#9-realtime-the-hub-and-the-page-contract)
10. [Crash model and operability](#10-crash-model-and-operability)
11. [Data: store v3, memory mode, migrations, retention, search and backups](#11-data-store-v3-memory-mode-migrations-retention-search-and-backups)
12. [Client stack: bundles, CSP, the 17 extensions, hyperscript and themes](#12-client-stack-bundles-csp-the-17-extensions-hyperscript-and-themes)
13. [Houston: product, information architecture and journeys](#13-houston-product-information-architecture-and-journeys)
14. [Houston feature specs I: talk and ask](#14-houston-feature-specs-i-talk-and-ask)
15. [Houston feature specs II: plan, watch, play and operate](#15-houston-feature-specs-ii-plan-watch-play-and-operate)
16. [The terminal console to the Raspberry Pi](#16-the-terminal-console-to-the-raspberry-pi)
17. [Security model](#17-security-model)
18. [Performance budgets and the parity gate](#18-performance-budgets-and-the-parity-gate)
19. [Testing and the Odin code audit](#19-testing-and-the-odin-code-audit)
20. [Pipeline, hosting and deploys](#20-pipeline-hosting-and-deploys)
21. [spark integration](#21-spark-integration)
22. [Milestones, effort, cut list, risks and questions for Alex](#22-milestones-effort-cut-list-risks-and-questions-for-alex)

## 1. Summary

The starter, `odin-htmx-starter`, is a superset of the skeleton whose unit of choice is the Odin package: features are
packages, a profile is a hand-written entry package that imports and mounts them, built by its line in
`build.{sh,bat}`, and each profile builds to one self-contained binary. The showcase is Houston, the crew's home channel
on apollo, where Alex's friends and family talk, ask a bot, watch videos, play spark's games and plan things; it is the
profile `full`, which implements every catalog feature itself: Houston's own on `houston.alexh95.com`, and every
starter demo and lab page, the four lab-only extensions' included, on a second, session-free host (ANSWERS F2,
round 3).

### 1.1 Decisions in one screen

- **Repo**: promote the skeleton by renaming it in place to `alexh95/odin-htmx-starter`, not a new repo (Q1: yes). The
  skeleton has 0 forks, and the rename carries history, issues, releases, secrets and spark's pin, which a new repo
  would move by hand or break silently. The skeleton freezes as tags v1.2.0 (709bc94) and v1.2.1 (6d37506, its
  `Content-Length: -5` crash fix, already on `master`) and branch `skeleton-1.x`; v2.0.0 follows. This workspace
  becomes the renamed repo's checkout at M0, `_ref/` goes, and the planning docs are committed after a scrub:
  `docs/research/`, the proposals, `OUTLINE.md` and `docs/private/` stay out of git (D1; §4; ANSWERS F4, F5).
- **Hosts**: the brief's "separate to be more representative" option: one binary and one container per profile, at
  the root of its own one-label host under `alexh95.com` (`houston`, `houston-lab` for Houston's session-free demo and
  lab pages, `odin-htmx-starter` for the lab, `starter-<profile>` witnesses, `odin-htmx` on Fly), no `BASE_PATH`. The
  brief's `htmx-odin-starter.alexh95.com/minimal` and `/full` 301 to `odin-htmx-starter.alexh95.com`, which redirects
  them, prefix stripped, to `starter-minimal` and `houston` (D2, D25; §7.3; Q2: as recommended, plus `houston-lab`).
- **apollo first**: stage 1a (LAN direct) and 1b (NPM behind a LAN-only Access List) from M3, Houston there from M4, the
  family beta from M6; nothing new goes public before M12's security gate and Alex's go; a VPS is stage 3. The LAN
  finds apollo's names through split DNS, which Alex decided on 2026-10-26: seven DNS-only `A` records pointing at
  `<APOLLO_LAN_IP>`, added at M3 before the first LAN deploy, and at M12 the records of the names that go public are
  deleted, so the wildcard applies again (RESOLUTIONS X41; §20.3). Fly keeps only the skeleton witness, which is
  public today (still on 709bc94: 6d37506's deploy was skipped, so M0 re-runs it, §4.2 step 1) and from M0 serves
  6d37506 (v1.2.1) untouched until the M3 exit; only then, once `starter-skeleton` has passed on apollo's LAN, is it
  redeployed from `cmd/skeleton` (D41; RESOLUTIONS X2; §20.3; Q29: yes). Alex is warned if the witness ever costs
  more than $10/month (Q15).
- **Philosophy**: PHILOSOPHY.md keeps its thesis; "the line we hold" counts optional _hyperscript as a dependency; the
  ledger's eight rows name app.js, optional SQLite, optional _hyperscript, the odin-http fork, ffmpeg as an offline
  tool, `tools/bundle`, the `platform/guard` crash guard and M14's plain-text device feed, and a never-added list
  guards everything else (D3; RESOLUTIONS X1, X42; Q33: yes).
- **Package shape and switching**: each feature is a models, domain, views and web package, plus any switched
  implementations, over platform layers L1–L4 (L4 is `platform/app`, which holds `front`; RESOLUTIONS X30), with its
  stores in `app/stores/{sqlite,memory}/<f>/`; layers call each other directly, with no dependency injection, and
  `tools/check imports` enforces the directions (D4; ANSWERS #1). Which implementation runs is a family collection on
  the build line (store, identity, client, theme), spelled once in `build.{sh,bat} <profile>`, or a hand-written
  `switch` (the chat transport, the bot backend, the games catalog). Each profile is four hand-written files in
  `app/cmd/<profile>/` (`main.odin`, `routes.odin`, `routes_test.odin`, `brand.odin`), which the generator writes and
  edits and `tools/check profile` keeps consistent (D7, D8; LC; ANSWERS round 3). Only the transport axes and the bot
  backend switch per request, named in `x-impl` (D8).
- **The fork**: laytan/odin-http fac113f vendored in-tree at `app/vendor/odin-http/`, with an `UPSTREAM.md`, plus
  twenty-four generic changes F-1..F-24 (streams, timeouts, connection caps, shutdown deadlines, the guard hook, the
  `Content-Length` fix, deferred responses for pool replies, S0.5); no separate repo; spike S0.2 proves k6 parity first (D11; Q4; ANSWERS F3).
- **The hub**: topics `<feature>.<family>:<key>`, one wakeup per loop per burst, event ids `<epoch>-<seq>`, and
  persisted topics resume by SQLite rowid through a keyset replay before falling back to `resync` (D13).
- **Crash model**: every entry point runs under a setjmp guard; a trap with no lock held, no async op posted and
  nothing inside SQLite answers 500 and keeps serving; any other trap exits 70 and compose restarts the process (D15).
- **Data**: store v3 (one writer, per-loop readers, QPSG, a writer task, a query pool) passes on the file DB; spike
  S0.4 picks the `skeleton` profile's `:memory:` mode before M1, or Q6 applies (D16, D17).
- **Client stack**: one precompressed bundle per profile, the union of the one-line `EXTS` of every package the build
  reaches, read from the compiler's own package list (RESOLUTIONS X29; LC §11); the skeleton's hash CSP, extended by
  route flags, with a nonce only on `/scripting/*`, which exists only on session-free origins (D19, D20). 13 of the 17
  htmx extensions have real uses in Houston, and four are proven in the lab and on Houston's own session-free lab host,
  `houston-lab.alexh95.com`, so `full` covers all 17 itself (D21; ANSWERS F2); _hyperscript 0.9.94 is one of two client
  implementations behind `html.behave`, with vanilla twins for the eight core behaviours and an install-only gate (D22;
  both kept, ANSWERS #2).
- **Bot**: mock now, llama.cpp later. `backend_mock`, the default, answers with random "TODO" and "under construction"
  lines; `backend_llama` is the binding to a llama.cpp server on the LAN at `BOT_LLAMA_URL`, tested against
  `tools/fakellama` until Alex runs a model. That server has a host: llama.cpp's official Vulkan image on apollo's
  spare GPU (`<APOLLO_GPU>`), in a compose project Alex owns and agents never restart, so `BOT_LLAMA_URL` is
  `http://<APOLLO_LAN_IP>:<LLAMA_PORT>` from M7 (RESOLUTIONS X41). No model ships; the `bot` package stays a catalog
  feature, in `streams` too (D31; §14.3; Q32: yes).
- **Terminal**: an Odin agent (`cmd/term-agent`, a systemd unit) on a Raspberry Pi 4 (64-bit Pi OS Lite, wired; a Pi
  3B+ is the second device for multi-device tests; RESOLUTIONS X41) dials out to Houston at
  `ws://<APOLLO_LAN_IP>:8120/term/agent` with a device token, LAN only, so the Pi opens no port; line mode first, then a
  PTY whose VT parser runs in the agent, outside the server process (Q8: agent-side VT); the agent ships as a release
  asset (D32; §16; Q30).
- **Games**: iframes of `games.alexh95.com/play/<g>/?embed=1` work against today's spark, so the portal needs no
  adaptation to embed them; one small spark change, SP2 (a `frame-ancestors` allow-list), must be live before Houston
  goes public, and the other spark CLs are optional (D34, D43; §15.3).
- **Devices**: the pipeline needs only the dev PC, GitHub CI and apollo; the other home devices are test clients
  (an old Android phone is the oldest-browser device, a VR headset plays WebXR games in the embed) or optional roles,
  and none blocks a milestone (RESOLUTIONS X41; §20.8). The features they suggest (a device registry and feed,
  cameras, a wall dashboard) are M14 Devices, scheduled, optional and after M12, about 30 h (an estimate); the rest
  stay ideas (Q33: yes, 2026-10-26; ANSWERS round 4; RESOLUTIONS X42; §22.3).
- **Parity gate**: in every cell, the median paired ratio of the `skeleton` profile over the faster of 709bc94 and
  v1.1.1 must be ≥ 0.97, on both legs, at the M1 exit and at every milestone exit after it (D38).

### 1.2 Profiles

| Profile | Purpose | Host |
|---|---|---|
| `minimal` | the smallest hello world; no SQLite library; ≤ 1.5 MiB | `starter-minimal.alexh95.com` |
| `skeleton` | the S18 parity witness and the skeleton's 40-item checklist (01 (A)) | `odin-htmx.alexh95.com` (Fly, from the M3 exit; 6d37506 (v1.2.1) until then); `starter-skeleton.alexh95.com` (LAN only) |
| `streams` | the stream substrate without SQLite, so stream regressions are attributable | `starter-streams.alexh95.com` |
| `full` (Houston) | the showcase; implements every catalog feature itself: Houston's on its main host, and every starter demo and lab page (the skeleton's, the lab's, the four lab-only extensions' and `landing`) on a second, session-free host (ANSWERS F2, round 3) | `houston.alexh95.com`; `houston-lab.alexh95.com` (session-free) |
| `lab` | the starter's own page, the witness board and the four lab-only extensions, on an origin with no sessions; an independent witness | `odin-htmx-starter.alexh95.com` |
| `full-vanilla` | `full`'s files built with the second client implementation (`app/cmd/full` with `client=vanilla`, no directory of its own) | CI only |

`cmd/term-agent`, the Raspberry Pi agent, is not a profile. The full catalog is in §7.

### 1.3 Changes to SETTLED

| Item | Change | Why |
|---|---|---|
| S9 (wording overturned) | "no C toolchain" becomes "no SQLite library and no C compile step"; "through a Store vtable" becomes "through `store:<f>`, the build's store family" | the platform linker stays: clang on Linux and macOS, the MSVC/SDK libraries on Windows (09 §6.1); a domain calls its store directly, with no injection (ANSWERS #1; LC §3) |
| S18 (refined) | "store v3 does" holds for the file DB only; `:memory:` goes to S0.4 and Q6 before M1 | no measured mode passes every `:memory:` cell (12 §2; D17) |
| S3 (refined) | ids are `<epoch>-<seq>`; persisted topics also resume by rowid before `resync` | a restart otherwise forces durable chat to resync (13 §3.6, §7 item 8; D13) |
| S5 (refined) | the guard wraps every completion callback the fork owns; a trap inside SQLite is dirty; a pure recovery resets the loop's reader statements | crashes inside odin-http escape an app-level guard; an unreset reader pins the WAL (13 §1.3, §2.1; 12 §10; D15) |
| S12 (refined) | `/scripting/*` and `/compat/*` exist only on origins with no sessions: the `lab` profile's, and `full`'s second host `houston-lab.alexh95.com` (ANSWERS F2) | cookie `Path` does not isolate same-origin pages (CF §4.8; D20, D25) |
| S15 (refined) | behaviours are a closed enum emitted only by `html.behave`, with a vanilla twin where one exists | one definition, and a second client implementation (05 §9; D22) |
| S17 (refined, then reworded) | "explicit `register()` calls; proc-field vtables; runtime env selection among imported" becomes "hand-written `main.odin` and `routes.odin` per profile; the store, identity, client and theme families as collections on `build.{sh,bat} <profile>`'s line; hand-written switches for the transports and the bot backend"; per-request switching only on transport axes and the bot backend, always announced | no dependency injection (ANSWERS #1, round 3; LC §1); what served a request stays visible (philosophy judge must-fix 16; D8) |
| S20 (refined) | "Video goes to bunny.net when public" becomes "a bunny.net pull zone is optional for public video (Q26)" | the home uplink, `<HOME_UPLINK>`, is not a binding stage-2 trigger (DEVICES-SUMMARY; RESOLUTIONS X41; §20.3) |

### 1.4 Milestones

M0 Spikes → M1 Request-path substrate (v2.0.0) → M2 Stream substrate → M3 Pipeline and apollo LAN → M4 Identity and the
Houston shell → M5 Operate → M6 Comms → M7 Ask → M8 Plan → M9 Watch → M10 Play and gather → M11 Terminal → M12 Public
(v2.11.0). M0–M12 is about 610 agent-hours, a guide rather than a cap (ANSWERS #3); the substrate, M0–M3, is 205 h
and comes before the first showcase feature. Houston is useful to the family from M6, on the LAN. M13 Portal (the spark
portal on the starter) is optional, 60 h. M14 Devices (the device registry and feed, cameras and a wall dashboard) is
scheduled, optional too and after M12 like M13, about 30 h, an estimate (Q33: yes, 2026-10-26; RESOLUTIONS X42). The
public Fly witness moves to the starter only at the M3 exit (v2.2.0; Q29). Gates, hours, the cut list and the ideas
list are in §22.

### 1.5 What Alex decided first

| Q | Question | Decided (2026-10-25) |
|---|---|---|
| Q1 | Promote by renaming the repo in place? | **yes** (ANSWERS #5): after tagging v1.2.0 at 709bc94 and v1.2.1 at 6d37506, branching `skeleton-1.x` and setting `FLY_DEPLOY` off; all starter work happens in this workspace, which becomes the checkout at M0 (ANSWERS F5) |
| Q2 | Host names | **as recommended** (ANSWERS Q2): `houston` for Houston, `houston-lab` for its session-free lab pages (ANSWERS F2), `odin-htmx-starter` for the lab and aliases, `starter-<profile>` witnesses, plus `htmx-odin-starter` as a 301 alias |
| Q3 | The showcase's name | **Houston** (ANSWERS #6) |
| Q4 | Fork odin-http: where does the fork live, and when is the seam offered upstream? | **fork it, vendored in-tree** at `app/vendor/odin-http/` with `UPSTREAM.md`, no separate repo (ANSWERS #7, F3); an upstream offer after M2 goes through a fork made then |
| Q5 | Install Odin dev-2026-10 in WSL2 for the Linux legs? | **yes** (ANSWERS Q5) |
| Q6 | Only if S0.4 finds no passing `:memory:` mode: what does the gate do? | **answered 2026-10-26** (round 5): the default; S0.4's candidate C, the failing `:memory:` cells gated against HEAD 709bc94 with a documented exception, file-DB cells never waived |
| Q24 | apollo facts at M0 (for S0.12), and agents running ≤ 10-minute LAN load tests? | **yes to both** (ANSWERS Q24) |

Also decided on 2026-10-25 (`docs/design/ANSWERS.md`):
- **#1, F1, round 3**: layers call each other directly, with no dependency injection. Alex took the simpler set
  (ANSWERS round 3): each package keeps its own `ROUTES` table, and the profile's hand-written `routes.odin` mounts one
  line per package; four family collections (`store`, `identity`, `client`, `theme`) live on `build.{sh,bat}
  <profile>`'s line; one hand-written `switch` in `chat_web` covers all four transports and another the bot backend,
  whose default is set on `/admin/bot`; `main.odin` and `routes.odin` are hand-written, written and edited by the
  generator and checked for consistency in CI; chat imports notify directly, audit goes through `store:audit`, and
  the bot's room mode runs over static topic rows. Folded in from `docs/design/LEAN-COMPOSITION.md` (§5–§7).
- **#2**: both client implementations stay, _hyperscript and the vanilla twins (D22). **#3**: no cap on effort; the
  hours in §22 are a guide.
- **#4, F2, round 3**: `full` implements every catalog feature itself. Houston proper stays on
  `houston.alexh95.com`; every starter demo and lab page (the skeleton's notes, contacts/events, gallery and dashboard,
  the lab's stream demos, scripting and compat, with `landing` at the root) goes on the session-free
  `houston-lab.alexh95.com`, its demo data capped and reset nightly; `lab` stays an independent witness (§7.3).
- **F4**: the public repo keeps `docs/research/`, `docs/design/proposal-*.md`, `docs/design/OUTLINE.md` and
  `docs/private/` out of git, and the public docs are scrubbed of LAN and host details (§5.3, §20).
- **Q8** agent-side VT; **Q14** yes; **Q15** keep the Fly witness and warn Alex above $10/month; **Q17** yes (zlib,
  still scrubbed); **Q29** yes (Fly keeps 6d37506 until the M3 exit); **Q32** yes (the bot stays a catalog feature).

Decided in the device discussion (2026-10-25 and 2026-10-26; `docs/design/DEVICES-SUMMARY.md`; RESOLUTIONS X41):
- **The bot's host**: llama.cpp's official Vulkan server image on apollo's spare GPU (`<APOLLO_GPU>`), Alex's step at
  M7 (§14.3).
- **The terminal device**: a Raspberry Pi 4 on 64-bit Pi OS Lite, wired (§16).
- **Split DNS** (2026-10-26): seven DNS-only `A` records pointing at `<APOLLO_LAN_IP>`, added at M3 before the first
  LAN deploy; the records of the names that go public are deleted at M12 (§20.3).

Decided in round 4 (2026-10-26; ANSWERS round 4):
- **Q33**: yes, M14 Devices with the default scope, optional and after M12: the device registry and feed, cams and
  the wall dashboard; live video, the radio feed, the mesh bridge and WireGuard stay ideas (§22.3).

Decided in round 5 (2026-10-26; ANSWERS round 5), on the gate questions M0's spikes raised:
- **Q6**: the default. The `skeleton` profile's `:memory:` mode is S0.4's candidate C, and the `:memory:` cells it
  fails are gated against HEAD 709bc94 with a documented exception each; file-DB cells are never waived (§11.3, §18.2).
- **Q35**: the light routes, `static` and `seo`, gate against HEAD alone; the store routes against max(HEAD, v1.1.1)
  (§18.2; S0.1).
- **Q34**: the default. The login-storm budget is absolute, and the argon pool has 1 thread on ≤ 2 CPUs (§17.1,
  §18.4; S0.5).

Decided in round 10 (2026-10-27; ANSWERS round 10), on the skeleton's binary:
- **Budget (a)**: `skeleton` ≤ 3 MiB (Windows `-o:speed`), in CI, the drills, D38 and §18.4; no SQLite OMIT flags, no
  re-encode of the social card.

Decided in round 9 (2026-10-26; ANSWERS round 9), on the gaps M2's slices 7–11 found:
- **`identity_nick` is built in M2** for `streams` (a signed nickname cookie, role User, `ACCOUNTS_NICK_FROM=lan`); the
  rest of `accounts` stays at M4 (§22.3).
- **`ACCOUNTS_NICK_ADMIN_CIDRS`** (empty by default) makes nick's clients there Admin, so `/admin/ops` opens in
  `streams`; e2e sets it to loopback (§17.1, §2.9's env table).
- **Off-LAN visitors are Guests** under D35's table, with no `Chat_Read`: chat shows them a "chat is open on the LAN"
  notice (§14.1, §17.1).

Decided in round 8 (2026-10-26; ANSWERS round 8), on CI's first runs:
- **The idle budget is the dev PC's**, gated by its drills on both legs at 16 loops, as the binary budget is gated on
  Windows; CI's Linux runner reports its idle RSS and its makeup without failing (§18.4, §20.1).

Decided in round 7 (2026-10-26; ANSWERS round 7), on the M1 budgets:
- **Budget (a)**: binary budgets are in MiB, as CI reads them (skeleton ≤ 2.75 MiB holds); `minimal` ≤ 1.5 MiB; idle
  memory ≤ 6 MB + 0.4 MB per event loop, 12.4 MB at the default 16 (§18.4).

Decided in round 6 (2026-10-26; ANSWERS round 6), on the M1 parity gate:
- **Linux `write@mem`** passes at a median of 0.93 of HEAD (a `perf-floor` line): the server's CPU per write equals
  HEAD's, and the gap is the writer task's hop under a closed-loop client; the sort indexes stay (§18.2,
  `docs/perf/PARITY.md`).

Every other question, with its options and status, is in §22.7.

## 2. Glossary and naming conventions

This is the one place where shared names are defined. Every other section uses them exactly as written here; where a
section needs more than a name, it points to the section that owns the detail.

### 2.1 Ids and documents

| Id | Meaning | Where |
|---|---|---|
| D1–D45 | design decisions | `docs/design/DECISIONS.md` |
| X1–X43 | the lead architect's resolutions of the open items this plan's writing round left (X36–X43: those found while folding round 3 and the device inventory), cited "(RESOLUTIONS X5)" | `docs/design/RESOLUTIONS.md` |
| DEVICES-SUMMARY | the public-safe summary of the device discussion with Alex (2026-10-25, split DNS 2026-10-26): device classes and roles only (§20.8) | `docs/design/DEVICES-SUMMARY.md`; models, addresses and measurements in the git-ignored `docs/private/DEVICES.md` and `docs/private/APOLLO.md` |
| S1–S22 | working assumptions settled by evidence | `docs/design/SETTLED.md` |
| #1–#9, F1–F5, Qn; rounds 3 and 4 | Alex's answers of 2026-10-25 (round 1's topics, round 2's follow-ups and questions), cited "(ANSWERS F2)"; round 3's two answers (the no-DI choices, what "every feature" in `full` covers), cited "(ANSWERS round 3)"; round 4's one answer (Q33, 2026-10-26: M14 Devices is scheduled), cited "(ANSWERS round 4)" | `docs/design/ANSWERS.md` |
| LC | the lean composition design: direct calls, no injection (ANSWERS #1, round 3), cited "LC §6"; its §16 holds the prototype evidence, and its §15 lists what it changes in each decision | `docs/design/LEAN-COMPOSITION.md` |
| 01–14 | research notes, cited "03 §7"; note 14's experiments by number, "14 (1)" | `docs/research/` (git-ignored, ANSWERS F4) |
| RF, PF, CF | the risk-first, product-first and composition-first proposals, cited "RF §3.10" | `docs/design/proposal-*.md` (git-ignored, ANSWERS F4) |
| `SK/`, `spark/ws/` | the skeleton at 709bc94 (tag v1.2.0) and spark's workspace, cited `SK/<path>:<line>` and `spark/ws/<path>:<line>`; `SK/` lines stay at 709bc94 | `_ref/odin-htmx-skeleton/` while planning, then `git show v1.2.0:<path>` in this checkout once `_ref/` goes at M0 (ANSWERS F5); `<SPARK_DIR>\ws` |
| M0–M14; S0.1–S0.12; Q1–Q33; R1–R21 | milestones (below); M0 spikes, each recorded in `docs/spikes/S0.<n>.md`; questions for Alex, each with a recommended default and, in §22.7, its status after Alex's answers (DECISIONS.md Appendix C; Q29–Q33 came from RESOLUTIONS.md); risks (R2a is a sub-item of R2) | §22 |
| F-1–F-12; SP1–SP7 | the odin-http fork's changes; spark changes, each an Ark CL | §8; §21 |

| M | Name | Release | M | Name | Release |
|---|---|---|---|---|---|
| M0 | Spikes | — | M7 | Ask | v2.6.0 |
| M1 | Request-path substrate | v2.0.0 | M8 | Plan | v2.7.0 |
| M2 | Stream substrate | v2.1.0 | M9 | Watch | v2.8.0 |
| M3 | Pipeline and apollo LAN | v2.2.0 | M10 | Play and gather | v2.9.0 |
| M4 | Identity and the Houston shell | v2.3.0 | M11 | Terminal | v2.10.0 |
| M5 | Operate | v2.4.0 | M12 | Public | v2.11.0 |
| M6 | Comms | v2.5.0 | M13 | Portal (optional) | a spark CL |
| | | | M14 | Devices (optional; Q33: yes) | the next minor |

Versions: v1.2.0 is the skeleton finale (709bc94, no code change); v1.2.1 is 6d37506, the skeleton's
`Content-Length: -5` crash fix, already on `master` and on Fly from M0 (§4.2 step 1; ANSWERS F5); v1.2.2 is the
optional QPSG backport on `skeleton-1.x`; **v2.0.0 at the M1 exit**, tagged with `FLY_DEPLOY` still off, then
milestone M<n> releases v2.<n−1>.0 through M12 (D40); v2.2.0 at the M3 exit is the first tag that deploys Fly
(RESOLUTIONS X2). M13 is a spark CL, and the optional M14 takes the next minor release after M12's.

### 2.2 Products, repos and machines

| Name | What it is |
|---|---|
| odin-htmx-starter | the starter; repo `alexh95/odin-htmx-starter`, formerly `odin-htmx-skeleton` ("the skeleton", `SK/`), which is frozen as tags v1.2.0 and v1.2.1 and branch `skeleton-1.x` (D1); its checkout is this workspace, `<WORKSPACE>`, from M0 (ANSWERS #5, F5) |
| Houston | the product name of profile `full` (D28) |
| the fork, `app/vendor/odin-http/` | laytan/odin-http fac113f plus F-1..F-24, vendored in-tree; its `UPSTREAM.md` names the base commit and each change. There is no separate repo; an upstream offer goes through a GitHub fork made at that time (D11; ANSWERS F3) |
| spark | Alex's games workspace (`<SPARK_DIR>`), served at games.alexh95.com |
| apollo | Alex's home server: a modest machine shared with Alex's other self-hosted services; LAN address `<APOLLO_LAN_IP>`, SSH alias `<APOLLO_SSH_ALIAS>` (D42); its spare GPU, `<APOLLO_GPU>`, hosts the bot's llama.cpp server (§14.3; RESOLUTIONS X41) |
| site placeholders (`<APOLLO_LAN_IP>`, `<APOLLO_CPU>`, `<APOLLO_GPU>`, `<APOLLO_SERVICES>`, `<APOLLO_DATA_DIR>`, `<HOME_UPLINK>`, `<LLAMA_PORT>` …; the dev PC's local paths `<WORKSPACE>`, `<SPARK_DIR>`, `<OLD_DEMO_DIR>`, `<SKELETON_FIX_CLONE>`) | real site values (the LAN address, apollo's hardware, OS and services, the SSH alias and user, host paths, the home uplink, the folders on the dev PC); each is defined in the git-ignored `docs/private/SITE.md`, where agents look it up, so the public docs never spell them out (ANSWERS F4) |
| NPM | nginx-proxy-manager on apollo, which terminates TLS for `*.alexh95.com`. D41 modelled upstream v2.16.0, but apollo's NPM is older (its version is recorded in `docs/private/SITE.md`), so the `e2e-proxy` job pins and models apollo's actual version; upgrading NPM is Alex's optional step, never an agent's (RESOLUTIONS X40) |
| the stack Caddy | the `caddy` service of `deploy/compose.yaml`, which routes by Host on `<APOLLO_LAN_IP>:8120` (port free: **UNVERIFIED (M3)**; D41) |
| the dev PC | Ryzen 7 5800X, Windows 11, WSL2; its 16 GB GPU runs bigger models for occasional bot smoke tests, never as Houston's always-on backend (§14.3) |
| the Pi | the Raspberry Pi 4 (4 GB; 64-bit Pi OS Lite, wired; linux_arm64) that runs `cmd/term-agent` (D32); a Pi 3B+ is the second device for multi-device tests, and Pi Zero class boards can't run the agent (RESOLUTIONS X41; §16) |

### 2.3 Profiles

Each profile is an entry package `app/cmd/<profile>/` of four hand-written files, built by its line in
`build.{sh,bat} <profile>` (D7, D24; LC §6; full catalog in §7).

| Name | What it is |
|---|---|
| `minimal`, `skeleton`, `streams`, `full`, `lab` | the five hosted profiles; `full` is Houston |
| `full-vanilla` | `app/cmd/full` built with the vanilla client (`client=vanilla` on its `build.*` line), with no directory of its own; its lab host's one hyperscript widget is inert there (§7.1); CI only |
| `cmd/term-agent`; `cmd/app` | the Pi agent, not a profile; the one entry package the generator writes in a fork (D26) |
| witness | a hosted profile that proves a claim (`skeleton`: parity; `minimal`: the smallest build; `streams`: the stream substrate without SQLite; `lab`: the four lab-only extensions and the stream contract pages, independently of `full`, which serves the same pages on its own lab host too, ANSWERS F2); every witness gets the witness resource class (D38; RESOLUTIONS X22) |
| witness board | the lab's `/status` page, which shows every witness (D36) |

### 2.4 Hosts, containers and stages

| Host (D2) | Serves | Service |
|---|---|---|
| `houston.alexh95.com` | `full` | `starter-full` |
| `houston-lab.alexh95.com` | `full`'s lab host: every starter demo and lab page, with `landing` at its root, session-free (§7.3; ANSWERS F2, round 3) | `starter-full` |
| `odin-htmx-starter.alexh95.com` | `lab`, plus the aliases `/full`, `/minimal`, `/skeleton`, `/streams` (D25) | `starter-lab` |
| `starter-minimal.alexh95.com` | `minimal` | `starter-minimal` |
| `starter-streams.alexh95.com` | `streams` | `starter-streams` |
| `starter-skeleton.alexh95.com` | `skeleton`, LAN only | `starter-skeleton` |
| `odin-htmx.alexh95.com` | `skeleton` on Fly (fra, Cloudflare-proxied), from the M3 exit; 6d37506 (v1.2.1) until then (RESOLUTIONS X2; ANSWERS F5) | Fly app `odin-htmx-skeleton` |
| `htmx-odin-starter.alexh95.com` | a 301 alias of `odin-htmx-starter.alexh95.com` | `caddy` |

Container services: `caddy`, `starter-full`, `starter-lab`, `starter-minimal`, `starter-streams`,
`starter-skeleton`. Images: `ghcr.io/alexh95/odin-htmx-starter-<profile>`. Hosting stages (D41, §20): **0** dev PC,
**1a** apollo LAN direct, **1b** apollo LAN via NPM, **2** apollo public, **3** VPS.

### 2.5 Directory layout

| Path | Holds |
|---|---|
| `app/vendor/odin-http/` | the fork, vendored in-tree, with `UPSTREAM.md` (laytan fac113f plus F-1..F-24; ANSWERS F3) |
| `app/vendor/{sqlite,htmx,hyperscript}` | pinned third-party sources |
| `app/platform/<pkg>` | the platform packages (§2.6) |
| `app/platform/static/` | `base.css` (D19), app.js, the core `_hs` set, favicon, og.png; not a package |
| `app/features/<f>/` | domain package; `models/`, `views/`, `web/`, `<axis>_<impl>/` (switched implementations), `storetest/` (the store conformance suite, D37), `static/` (CSS, `_hs`), `README.md` |
| `app/stores/{sqlite,memory}/<f>/` | one store package per feature and family, `<f>_store_sqlite` and `<f>_store_memory`: `store.odin`, `contract.odin` and, in the SQLite family, `migrations/NNNN_name.sql`; a feature with no member in a family has no directory there (LC §3) |
| `app/cmd/<profile>/{brand,main,routes,routes_test}.odin` | entry packages, all hand-written: names, nav per host and copy; the boot sequence; the host tables; the boot checks under `odin test` (LC §6) |
| `build.{sh,bat}`, `ols.json` | at the repo root, with paths relative to it: `build.{sh,bat} <profile>` (`CMD=check\|test\|run`), the one place the four family flags live; the editor's collections, pinned to `full`'s families. The skeleton kept its `ols.json` in `app/`; the starter's moves beside `build.*` (LC §3) |
| `app/build/` | prepare's output, git-ignored |
| `app/prepare.{sh,bat}`, `app/run.{sh,bat}` | fetch, build and bundle; run a profile; both stay in `app/`, as in the skeleton, and call the root `build.*` |
| `e2e/tests/<f>/`, `load-tests/scenarios/<f>/`, `perf/{baseline,results}/` | per-feature e2e specs and k6 scenarios; parity runs |
| `tests/parity-waivers.txt` | route-coverage waivers, each with a reason (D37) |
| `tools/{init,bundle,check,baseline,streamload,fakellama,transcode,watch,og,upstream}` | the generator and the build, check, test and content tools |
| `deploy/{compose.yaml,Caddyfile,promote.ps1}` | the apollo stack and its deploy script |
| `deploy/docker/{Dockerfile,seccomp-io-uring.json}`, `deploy/fly/fly.toml`, `deploy/pi/term-agent.service` | images, Fly and the Pi unit |
| `docs/{BRIEF.md,PLAN.md,CATALOG.md,catalog.json,DATA.md,USE_CASES.md,SECURITY.md,OPS.md}` | plan and reference docs (`CATALOG.md` and `catalog.json` are generated) |
| `docs/{design,research,spikes,audit,perf}/` | design inputs, research notes, spike records, audit reports, parity results; `docs/research/`, `docs/design/proposal-*.md` and `docs/design/OUTLINE.md` are git-ignored (ANSWERS F4; §5.3) |
| `docs/private/` | git-ignored: `SITE.md`, the LAN addresses, apollo's hardware and services, user names and host paths that the public docs replace with placeholders (ANSWERS F4) |
| `.github/workflows/{ci.yml,nightly.yml,release.yml}`, `.github/matrix/pairwise.json` | CI and the committed covering array |

### 2.6 Platform packages

Layers (D4; RESOLUTIONS X30; LC §5): **L1** bindings, **L2** core, **L3** I/O, **L4** composition (`platform/app`,
imported only by `cmd/*`). Only `platform/web` imports odin-http, and it re-exports `web.Request` and `web.Response`.
Below L4, platform imports a feature only through a family collection: `platform/app` imports `identity:`, and
`platform/html` imports `client:` and `theme:` (§2.8). Detail in §5.

| Package | L | Holds |
|---|---|---|
| `platform/sys` | 1 | glibc `_setjmp`, sigaction and sigaltstack, the Windows VEH and `_resetstkoflw`, setrlimit, the vDSO clock; the thread-local counters the guard classifies by (here because `platform/sqlite`, L1, raises `in_sqlite`) |
| `platform/sqlite` | 1 | the SQLite binding (core only); raises `in_sqlite` around every call |
| `platform/escape` | 1 | the injection boundary, `w esc url_encode json_esc`: a leaf, so `platform/markdown` (L2) escapes with it and `platform/html` re-exports it (M1, **NEW**) |
| `platform/signed` | 1 | `<body>.<MAC>` text the server hands out and reads back (a pending sign-in, envadmin's cookie): `sign` and `open`, the one parser of it, fuzzed (M5, M4-13, **NEW**) |
| `platform/fuzz` | 1 | the parsers' tests' seeded random input, `FUZZ_SCALE`/`FUZZ_SEED` for the nightly; only tests import it (M5, M4-13, **NEW**) |
| `platform/ext` | 1 | the closed `Ext` enum of htmx extensions with its registration-name and file tables; imports nothing; re-exported as `web.Ext` (RESOLUTIONS X33) |
| `platform/store` | 2 | what every store shares: `Migration`, `Error`, `enum_from_int`, `Search_Hit` (domains return it) and `Find_Source` (a row of `main`'s `FIND_SOURCES`) |
| `platform/store/sqlite` | 2 | store v3: the writer connection, per-loop readers, the writer task, the query pool (D16); `open` and `migrate`, which answer `--backup` and `--adopt-profile`; the pure-trap reader reset, pulled from guard's recovery count before each reader use and on a per-loop 1 s timer (S0.6); `sqlite3_db_status` numbers pushed to obs (LC §5) |
| `platform/store/memory` | 2 | rings and maps behind guarded locks, ids `<epoch>-<seq>` |
| `platform/env` | 2 | the typed env table (D10): the platform's rows and each feature's, recorded by its `init`; features read their rows here, never through `platform/app` (LC §5) |
| `platform/workers` | 2 | the argon, query, llama and jobs pools, the scheduler over the mounted `JOBS` (`run_now`, `cancel`, each run's state as data), generation checks |
| `platform/authz` | 2 | `Role`, `Perm`, `ROLE_PERMS`, `Viewer` (it carries the member's preferences), the identity contract `Load_Viewer`, which takes an `Ask` (the Cookie header, the client address, https) and returns the Viewer and a Set-Cookie value, so no identity sees odin-http's types |
| `platform/authz/anonymous` | 2 | `authz_anonymous`, the default identity (every viewer is the Guest): a member of the `identity` family (§2.8) |
| `platform/obs` | 2 | logfmt, request ids, counters and health state (`platform/web` serves `/metrics` and `/livez /readyz /healthz` from them), the health, limits and numbers features push (§10.4), spall |
| `platform/guard` | 2 | `guard_call`, the counters' helpers, `guarded_mutex`, the trap handler, the watchdog |
| `platform/markdown` | 2 | the markdown renderer (depth cap 32, input cap 64 KiB), escaping through `platform/escape` |
| `platform/password` | 2 | argon2id at OWASP's parameters on its own pool, PHC strings, constant-time compares and the dummy derive (§17.1; M4: both password identities, `accounts` and `envadmin`, use it) |
| `platform/totp` | 2 | RFC 6238 one-time codes (HMAC-SHA1, 30 s, 6 digits), a step either side accepted and named, base32 secrets and the `otpauth://` text (§17.1, Q11; M4) |
| `platform/web` | 3 | the prefix router (one map per host), CSP flags, `Req_Ctx`, `respond_*`, `web.Request` and `web.Response` (odin-http's types, re-exported), body caps, the trusted-proxy client address, the limiter, assets, robots/sitemap/Bing/IndexNow, `/licenses`; `web.Route`, and the platform's two tables: `web.ROUTES` (a site's main host: `/metrics /livez /readyz /healthz` over obs's data, the sitemap, the ownership proofs) and `web.PUBLIC_ROUTES` (every host: static assets, `/events`, `robots.txt`, `favicon.ico`, `/licenses`, `/csp-report`) |
| `platform/html` | 3 | `w esc url_encode json_esc` (re-exported from `platform/escape`), the layout, NAV, `Home_Card`, components, `behave`; it imports the `client:` and `theme:` families |
| `platform/stream` | 3 | the SSE encoder, the WS handshake and codec, the multipart writer, the Range sender (D12) |
| `platform/stream/client` | 3 | the non-blocking chunked, SSE and WS client (D12) |
| `platform/hub` | 3 | topics mounted per host from `TOPICS` tables, publish, a row's `deliver`, per-loop inboxes, rings, replay (D13) |
| `platform/client/hyperscript`, `client/vanilla` | 3 | the two members of the `client` family, behind `html.behave` (D22) |
| `platform/theme/full`, `theme/lite` | 3 | the two members of the `theme` family: 6 styles × 24 schemes; one style with two schemes (D23) |
| `platform/app` | 4 | the composition package: `front` (it imports the `identity:` family), `app.Host`, `boot`, `check` (the boot checks), `serve`, `wait`, `shutdown`, and the platform's own CLI flags (RESOLUTIONS X30; LC §5) |

### 2.7 Feature packages and Odin package names

Features: `home notes about dashboard gallery contacts accounts audit modules ops status jobs chat notify uploads bot
wiki find lists polls calendar guestbook video games c4 term dbview landing scripting compat lab`, plus M14's
`devices cams wall` (optional; Q33: yes; RESOLUTIONS X42; the name `wall` is **NEW**).

| Package | Directory | Odin name | Example |
|---|---|---|---|
| models | `app/features/f/models/` | `f_models` | `chat_models` |
| domain | `app/features/f/` | `f` | `chat` |
| views | `app/features/f/views/` | `f_views` | `chat_views` |
| web | `app/features/f/web/` | `f_web` | `chat_web` |
| switched implementation | `app/features/f/<axis>_<impl>/` | `f_<axis>_<impl>` | `chat_transport_ws` |
| store | `app/stores/<family>/f/` | `f_store_<family>` | `chat_store_sqlite` |
| identity | `app/features/accounts/identity_<x>/`, `app/platform/authz/anonymous/` | `accounts_identity_<x>`, `authz_anonymous` | `accounts_identity_nick` |

A package name must be unique per program, so the store names carry their family, and a feature's `storetest` imports
both of its stores into one test binary (LC §3).

### 2.8 Implementations and families

Which implementation runs is a family collection on the build line, a hand-written `switch` with a direct call in each
case, or an env value read at boot and then the same kind of switch; it is never a value handed in at run time (§6.1;
LC §1; ANSWERS #1, round 3).

| Axis | Members | Chosen | Notes |
|---|---|---|---|
| store (family) | `app/stores/sqlite/<f>/` (`<f>_store_sqlite`), `app/stores/memory/<f>/` (`<f>_store_memory`) | per build, `-collection:store=app/stores/<sqlite\|memory>`; one family for every feature of a build | notes, chat, notify, polls, lists, calendar, guestbook, jobs, audit, wiki, video, bot conversations (D8), uploads' session rows (RESOLUTIONS X13); SQLite only: accounts, contacts, term. Each store's `IMPL` constant names it |
| search, wiki source, video catalog | the store's: a `contains_ci` scan or FTS5; `source_files` (the read-only embedded docs) or the editable SQLite wiki (D36); `catalog_file` (the manifest scan) or the SQLite library (D33) | follow the store family | memory first in each pair; the old member names survive as `IMPL` |
| identity (family) | `features/accounts/identity_{accounts,envadmin,nick}/`, `platform/authz/anonymous/` | per build, `-collection:identity=…` | called the `accounts`, `envadmin`, `nick` and `anonymous` identities; contract `authz.Load_Viewer`, called by `front` (D35) |
| client (family) | `platform/client/{hyperscript,vanilla}/` | per build, `-collection:client=…` | read by `platform/html`'s `behave` (D22) |
| theme (family) | `platform/theme/{full,lite}/` | per build, `-collection:theme=…` | read by `platform/html` (D23) |
| chat transport | `features/chat/transport_{ws,sse,poll,multipart}` | per request, one hand-written `switch` in `chat_web`; every chat profile links all four | (D8, D30); each declares its own extension in `EXTS` (`.Ws`, `.Sse`, `.Ptag`, `.Multipart`), unioned into `chat_web.EXTS` (RESOLUTIONS X29) |
| bot backend | `features/bot/backend_{mock,llama}` | per request among the healthy ones, a `switch` in `bot_web`; both linked | (D31); the default is `BOT_BACKEND`, changed at run time on `/admin/bot` |
| games catalog | `features/games/catalog_{static,api}` | per process: `api` when `GAMES_API_URL` is set, `static` otherwise; a `switch` in `games_web` | (D34); both pure Odin, so nothing is kept off the linker |
| terminal mode | "line" and "PTY" | per device row | a device setting, not packages; `features/term/grid` is the server side, `features/term/vt` the agent's parser |

### 2.9 Route prefixes

A feature owns `/<name>`, `/admin/<name>` and `/api/<name>`; each exception is listed in its README with the reason
(D9; the rule in §6, the router in §8).

| Feature | Prefixes | Reason for any exception |
|---|---|---|
| `chat notify uploads bot wiki find lists polls calendar guestbook games c4 status notes about` | `/<name>` (`/chat`, `/find` …) | the rule |
| `scripting compat lab` (the `lab` profile, and `full`'s lab host only, §7.3) | `/scripting`, `/compat`, `/lab` | the rule |
| `audit ops jobs modules dbview` | `/admin/audit`, `/admin/ops`, `/admin/jobs`, `/admin/modules`, `/admin/dbview` | the rule |
| `home` | `/` (a root row) | the Today page; the root in `minimal`, `streams` and on Houston's main host, and in a generated project unless `dashboard` or `landing` is selected (RESOLUTIONS X5) |
| `landing` | `/` (a root row) | the catalog explorer; the root in `lab` and on `full`'s lab host |
| `accounts` | `/login /logout /register /invite /account`, `/admin/accounts` | conventional URLs |
| `video` | `/video`, `/media` | content-addressed files |
| `term` | `/term` (the agent dials `/term/agent`), `/admin/term` | the rule |
| `devices cams wall` (M14, optional) | `/devices` (the plain-text feed) and `/admin/devices`; `/cams`; `/wall` | the rule |
| `dashboard` | `/dashboard`, `/ui/ping`; its page is `skeleton`'s root row at `/` (the skeleton's page, `SK/app/src/routes.odin:35`) and sits at `/dashboard` on `full`'s lab host | the skeleton's exact URLs, for parity |
| `gallery` | `/components /forms /ui /validate` | the same |
| `contacts` | `/data /contacts /search /api/search` | the same; so global search is `find` at `/find` (`SK/app/src/routes.odin:42`) |
| platform | `web.ROUTES`, a site's main host: `/healthz /livez /readyz /metrics /sitemap.xml /BingSiteAuth.xml /<indexnow-key>.txt`; `web.PUBLIC_ROUTES`, every host: `/static /robots.txt /favicon.ico /licenses`; `web.REPORT_ROUTES`, where the profile asks for CSP reports: `/csp-report`; `hub.ROUTES`, every host that mounts topics: `/events` (M2) | owned by no feature |

`/` is no feature's prefix: each host's one `GET /` row is written in the profile's `routes.odin` and names the root
feature's handler (§6.3; LC §7). Product names (Comms, Capcom, Logbook …) are nav labels in `brand.odin`, never
prefixes.

### 2.10 Hub topics

Names are `<feature>.<family>:<key>`; policies are `.Queue`, `.Latest` (the newest message per publish key: the topic
key by default, or the element id a publisher passes; RESOLUTIONS X8) and `.Sample` (drops intermediate updates while
a send is in flight) (D13; §9). Each package declares its families in a `TOPICS` table, which the profile's
`routes.odin` mounts per host (LC §6).

| Feature | Topics |
|---|---|
| notify, home | `notify.user:<uid>` (persisted: D13's example URL carries its rowid); `home.presence` (`.Latest`) |
| chat | `chat.room:<id>` (persisted); `chat.presence:<id>` (`.Latest`); `chat.typing:<id>` (`.Latest`); `chat.reply:<room>` (the bot's room answers, a server-side `deliver` row; §6.2) |
| bot, ops, jobs | `bot.health`; `bot.ask:<room>` (room mode, a server-side `deliver` row; §6.2); `ops.panel`; `jobs.runs` (`.Latest`, publish key = the run id) |
| games | `games.players` (`.Latest`); `games.board:<g>` |
| polls, lists, calendar | `polls.poll:<id>` (`.Latest`); `lists.list:<id>` (persisted); `calendar.event:<id>` |
| uploads, guestbook, c4, term | `uploads.upload:<id>`; `guestbook.queue`; `c4.game:<id>`; `term.session:<sid>` |

### 2.11 Enums and modes

| Name | Members |
|---|---|
| `web.Ext` (= `ext.Ext`; D19, X33) | `.Sse` sse, `.Ws` ws, `.Multipart` hx-multipart, `.Live` hx-live, `.Pending` hx-pending, `.Browser_Indicator` browser-indicator, `.Prompt` hx-prompt, `.Preload` preload, `.Ptag` ptag, `.History_Cache` history-cache, `.Head` hx-head, `.Upsert` upsert, `.Targets` hx-targets, `.Download` download, `.Compat_Htmx2` compat, `.Compat_Alpine` alpine-compat, `.Csp` hx-csp |
| `web.Route_Flag` (D5) | `.Step_Up .Lan_Only .Private .Fragment .Stream .Frame_Games .Media .Nonce_Csp .Lab_Host` (the last: a mount rule, "mount only on a host where no cookie-setting identity runs", checked at boot: houston-lab, or `lab`'s one origin; §6.1 check 4, §7.3; ANSWERS F2, **NEW**) |
| `web.Bundle` (D19) | `Main`, `Scripting`, `Compat_Htmx2`, `Compat_Alpine` |
| `authz.Role` (D35) | `Guest`, `User`, `Mod`, `Admin`; labels Guest, Member, Moderator, Admin |
| `authz.Perm` (D35) | `Public` (no check, D5); `Account_Self`; `Chat_Read Chat_Post Chat_Dm Chat_Create_Room Chat_Attach Chat_Moderate`; `Bot_Use Bot_Llama`; `Video_Watch Video_Upload Video_Moderate`; `Wiki_Read Wiki_Edit`; `Lists_Edit`; `Polls_Create Polls_Vote`; `Calendar_Edit`; `Guestbook_Moderate`; `C4_Play`; `Term_Watch Term_Write`; `Admin_Accounts Admin_Audit Admin_Ops Admin_Jobs Admin_Modules Admin_Db Admin_Term` |
| `html.Behaviour` (D22) | `.Tabs .Toast .Reset_On_Success .Dismiss .Search_Box .Range_Fill .Composer .Auto_Scroll` (twinned), `.Rel_Time .Copy_Text .Show_Password .Draggable .Drop_Zone .Palette .Term_Keys .Measure_Term .Resume .Scrubber .Otp_Input .Expire`; hyperscript names are CamelCase (`ResetOnSuccess`), vanilla `data-behave` values kebab-case (`reset-on-success`) |
| `chat_web.Transport` (LC §4) | `.Ws .Sse .Poll .Multipart`, the cases of `chat_web`'s switch |
| `bot_web.Backend` (LC §4) | `.Mock .Llama`, the cases of `bot_web`'s `health`, `start` and `cancel` switches |
| `MEMMODE` (D16) | `single`, `ephemeral` |

`app.Capability`, `Module_Ops.zone` and `STORE` are gone (LC §14): a build that reaches a missing family member fails to
compile, the guard's counters decide pure or dirty, and no build links both store families.

### 2.12 Environment variables

D10's names and defaults; types, meanings and the `*_FILE` rule are in §8.

| Platform group | Variables and defaults |
|---|---|
| the skeleton's, same meaning | `PORT BIND_ALL DB_PATH SEED SITE_URL THREADS LOG_LEVEL` |
| lab host | `SITE_URL_LAB`, the origin of `HOSTS`' second host (`cmd/full/brand.odin` names `https://houston-lab.alexh95.com`; boot refuses it empty or naming `SITE_URL`'s host; §7.3, ANSWERS F2, **NEW**) |
| store | `MEMMODE` (single\|ephemeral; default `ephemeral`, except the `skeleton` profile, whose mode D17 picks); the store family is the build's, so there is no `STORE` |
| connections | `MAX_CONNS` (fd soft limit − 64), `HEADER_TIMEOUT_MS` 10000, `IDLE_TIMEOUT_MS` 75000, `BODY_TIMEOUT_MS` 30000, `SEND_TIMEOUT_MS` 30000, `DRAIN_DEADLINE_MS` 5000 |
| proxy and LAN | `TRUST_PROXY` (**empty = trust no peer**; on apollo, the stack Caddy's fixed address as a /32, RESOLUTIONS X43; §17.8), `LAN_CIDRS` 192.168.0.0/16 |
| streams | `STREAM_HEARTBEAT_S` 20, `STREAM_MAX_QUEUED` 256KiB, `STREAMS_PER_USER` 8, `STREAMS_PER_CLIENT` 16, `STREAMS_TOTAL` 8192, `STREAM_CONNECTS` 20, `STREAM_QUEUED_TOTAL` 64MiB, `HUB_RING` 256, `HUB_RING_BYTES` 1MiB |
| secrets and cookies | `METRICS_TOKEN_FILE`, `SESSION_KEY_FILE`, `COOKIE_SECURE` auto |
| build-time `-define` | `VERSION`, `TEST_ROUTES` (crash-drill routes; release images assert 404), `PROFILE` (spall) |

| Feature | Variables and defaults |
|---|---|
| chat | `CHAT_ROOM_CAP` 500, `CHAT_ROOM_MAX_AGE` 7d, `CHAT_DM_CAP` 1000, `CHAT_DM_MAX_AGE` 30d, `CHAT_ANNOUNCE_CAP` 100, `CHAT_ANNOUNCE_MAX_AGE` 365d, `CHAT_RING_BYTES` 16MiB, `CHAT_TRANSPORT` |
| bot | `BOT_BACKEND` mock, `BOT_LLAMA_URL` (required for llama, never assumed in code; on apollo `http://<APOLLO_LAN_IP>:<LLAMA_PORT>`, §14.3), `BOT_LLAMA_KEY_FILE`, `BOT_SEED`, `BOT_DELAY_MS`, `BOT_CONCURRENCY` |
| accounts (with its `nick` identity) | `ACCOUNTS_REGISTRATION` invite, `ACCOUNTS_ADMIN_HASH`, `ACCOUNTS_ARGON_THREADS` 2, `ACCOUNTS_NICK_FROM` lan (RESOLUTIONS X7), `ACCOUNTS_NICK_ADMIN_CIDRS` none (ANSWERS round 9) |
| games, video | `GAMES_URL`, `GAMES_API_URL` (set = `catalog_api`), `GAMES_CATALOG`; `VIDEO_DIR` /data/media, `VIDEO_SIGN_KEY_FILE`, `VIDEO_CDN_URL` |
| notes, contacts (the demo caps on `full`'s lab host) | `NOTES_CAP` 500, `CONTACTS_CAP` 2000; the jobs `notes.reset` and `contacts.reset` put the demo rows back nightly at 04:00 local time; the caps apply only where `full` mounts these features on its lab host, so the `skeleton` profile stays uncapped (RESOLUTIONS X38; §7.3) |
| term, status, guestbook | `TERM_IDLE` 15m; `STATUS_PROBES`; `GUESTBOOK_OPEN` 1 |
| `cmd/term-agent` (the Pi's `/etc/houston/term-agent.env`, Q30) | `TERM_AGENT_URL`, `TERM_AGENT_HOST`, `TERM_AGENT_TOKEN_FILE` (→ `/etc/houston/term-agent.token`, mode 0600) |

### 2.13 Seams

Features meet only through these (D6; LC §9; detail in §6.2):

| Seam | How | Without the other side |
|---|---|---|
| `notify_web.send(user, kind, ref, html)` | a direct import by every producer (chat, lists, calendar, polls, guestbook, bot, jobs): the one web-to-web edge | none: notify is a hard dependency of each producer, and the generator closes a selection over it |
| `audit_store.append(actor, action, target, reason, meta)` | `import audit_store "store:audit"`, from any domain, web or identity package | the memory family writes one `mod=audit` log line, the SQLite family an `audit_log` row |
| bot room mode | two static topic rows, one each way (RESOLUTIONS X37): chat publishes on `bot.ask:<room>`, which bot's row consumes, and the answer comes back on `chat.reply:<room>`, which chat's row consumes and stores as a chat message | neither feature imports the other, and each works alone: without bot nothing mounts `bot.ask`, so the publish is dropped and counted |
| `HOME_CARDS`, `FIND_SOURCES` | tables in the profile's `main`, handed to `home_web.init` and `find_web.init` | a feature not listed has no card or source |
| `NAV`, `LAB_NAV` | `brand.odin`, one nav per host | — |
| health, limits and numbers | pushed to `platform/obs` by direct calls; read by `status`, `modules` and `/readyz` | — |
| domain imports, plain links | hard dependencies (dashboard → contacts, video → uploads); UI composition (D34) | — |

### 2.14 Codes and headers

| Code | Meaning |
|---|---|
| exit 70 | a dirty crash or a watchdog exit (D15) |
| WS 1008 / 1009 | policy or revoked auth / message too big; the client does not reconnect |
| WS 1011 / 1012 / 1013 | pure-zone crash in that stream / drain or restart / slow consumer; hx-ws reconnects (D13) |
| 429 + `Retry-After` | a rate limit, routed to the toast slot through `hx-status:429` (D35) |
| 421 | a request to the stack Caddy whose Host names no site: the catch-all `:80` block, with one line pointing to `docs/OPS.md` (RESOLUTIONS X23) |
| `x-version`, `x-impl` | the build's version; the implementation that served a runtime-switched axis, as `<feature>.<axis>=<impl>` after D8's example `x-impl: chat.transport=sse` (so also `bot.backend=mock`) |

### 2.15 Terms

| Term | Meaning |
|---|---|
| pure zone | code where a trap leaves nothing shared broken (the parsers: no lock held, no op posted, outside SQLite, as the guard's counters show); the guard answers 500, or closes the stream with 1011, and serving continues (D15) |
| dirty | a trap with a lock held, an async op posted or a SQLite call in progress, or over 100 pure recoveries in 60 s (**NEW**): drain and exit 70 (D15) |
| slice gate | checks (a)–(f) that every milestone exit from M4 on adds (D44) |
| parity gate | D38's procedure: the `skeleton` profile against 709bc94 and v1.1.1, at M1 and every milestone exit |
| HEAD | 709bc94 (tag v1.2.0), the skeleton's head when S18 was measured, and baseline A; `master`'s later 6d37506 (v1.2.1) is not a baseline, and S18 is unchanged (ANSWERS F5) |
| leg | one OS environment of a gate: Windows native, or Linux on WSL2 |
| cell | scenario × store × leg |
| paired ratio | per round, C / max(A, B): the starter's `skeleton` over the faster of HEAD and v1.1.1 |
| writer task | the thread that owns the SQLite writer and commits every 10 ms or 100 items (D16) |
| query pool | the 2-thread pool for scans, ranking, exports and backups (D16) |
| hub sequence | `<epoch>-<seq>`, the process-wide, monotonic id of every stream event |
| render-time cursor | `after=<epoch>-<seq>`, the hub sequence when the page rendered, in its stream URL |
| `topic@rowid` | the newest rowid a page rendered for a persisted topic, e.g. `chat.room:12@88200` |
| page bundle | one `web.Bundle`: the scripts a page loads; links across bundles are full navigations |
| route id | `"<METHOD> <pattern>"`, unique per host |
| home card | a feature's `home_card` fragment on the Today page, listed in `main`'s `HOME_CARDS` |
| `accounts_prefs` | the members' preferences table (theme, chat transport, mutes), owned by `accounts`; formerly `user_prefs` (D23, D35; RESOLUTIONS X9) |
| root feature | the feature whose page a host's one `GET /` row names, written in the profile's `routes.odin`: `home` by default (in `minimal`, `streams` and on Houston), `dashboard` in `skeleton`, `landing` in `lab` and on houston-lab; exactly one per host, and the generator refuses two (D27; RESOLUTIONS X5; LC §7) |
| twinned behaviour | a behaviour with both a hyperscript and a vanilla implementation |
| lab-only extensions | hx-live, hx-csp, htmx-2-compat and hx-alpine-compat, shown only on session-free origins: the `lab` profile and `full`'s lab host (D21; ANSWERS F2) |
| lab host | a second, session-free origin a profile serves from the same binary, named by `SITE_URL_LAB`: `HOSTS`' second row, whose `identity` field is false, so no identity runs, nothing sets a cookie and every row is `.Public`. Only the rows its own table mounts answer there, plus the platform's public rows (`web.PUBLIC_ROUTES`). Only `full` has one, `houston-lab.alexh95.com`, with every starter demo and lab page and `landing` at its root (§7.3; ANSWERS F2, round 3) |
| family | one of the four collections on the build line, `store`, `identity`, `client` and `theme`; a member is the directory one flag points at, and one build has one member of each (LC §3) |
| build line | a profile's line in `build.{sh,bat} <profile>`, the one place the family flags live (LC §3) |
| mount | a line in a profile's host table that adds a package's table, `chat_web.ROUTES[:]`; `TOPICS` and `JOBS` are mounted the same way (LC §6) |
| dispatch table | a table of rows a lookup picks from (`ROUTES`, `TOPICS`, `JOBS`, `HOME_CARDS`, `FIND_SOURCES`): with continuations, the only place a proc value is stored (§6.1) |
| profile tables | the package-level tables in a profile's files: in `routes.odin` one route table and one topic table per host (`MAIN_ROUTES`, `LAB_ROUTES`, `MAIN_TOPICS` and `LAB_TOPICS` in `full`; `ROUTES` and `TOPICS` in a one-host profile), `HOSTS` (one `app.Host` per origin) and `JOBS`; in `main.odin` `HOME_CARDS`, `FIND_SOURCES` and the `BUNDLE_EXTS` constant (§7.2, §7.3; LC §6, §7) |
| job id | a `JOBS` row's id, prefixed by its feature as topics are: `notify.prune`, `chat.retention`, and `full`'s own `notes.reset` and `contacts.reset` for houston-lab's demo data, nightly at 04:00 local time (§7.3, §15.4; RESOLUTIONS X38) |
| switched implementation | a package one of whose members a hand-written `switch` calls per request or per process: the chat transports, the bot backends, the games catalogs (§6.4) |
| store contract | the proc types in a feature's `models`, checked by typed-constant lines in each store's `contract.odin` (§6.4) |
| demo data | houston-lab's notes and contacts rows: capped by `NOTES_CAP` (500) and `CONTACTS_CAP` (2000) and reset nightly at 04:00 local time; the `skeleton` profile's rows are never capped (§7.3, §11.6; RESOLUTIONS X38) |
| audit stamp | `Audited: <commit> <date> <report>` in a package README (D39) |
| audit-debt | changed lines since a package's audit stamp; over 300 blocks a release |
| singleton | a generated selection of one feature (`--features <f>`) |
| covering array | the strength-2 set of selections that covers every pair of features present or absent (D37) |

### 2.16 Spec and CI job names

Specs (§19): `rbac.spec`, `revoke.spec`, `escaping.spec`, `headers.spec`, `csp-clean.spec`, `csp-enforced.spec`,
`harness-csp.spec`, `bundle-race.spec`, `streams-hxcsp.spec`, `games-frame.spec`, `download.spec`, `a11y.spec`.

CI jobs (§20): `pins`, `check`, `build`, `e2e`, `e2e-proxy`, `proxy-config`, `linux-ops`, `docker`, `generator`,
`load-smoke`, `term-agent`, `nightly`, `release`, `deploy-fly`.

`tools/check` checks (§6.1, §19.2.1): `imports` (with the collection rules), `profile`, `routes` (per host), `topics`,
`contracts`, `exts`, `locks`, `entry-points`, `tables`, `names`, `parity`, `pins` and `audit-debt`, plus the
catalog's freshness.

## 3. Identity, philosophy and the ledger

This section says what the starter and Houston are, and which lines of the skeleton's `PHILOSOPHY.md` change on
purpose. The code shape is in §5 and §6; Houston's features are in §13.

### 3.1 The starter

`odin-htmx-starter` is a superset of the skeleton. The skeleton's feature set survives as the `skeleton` profile, held
to the skeleton's performance or better by the parity gate (§18). Granularity is the core idea:

- **features are packages**: each feature is a models, domain, views and web package, plus its stores and any switched
  implementations, and the layers call each other directly (D4; ANSWERS #1; LC §5);
- **profiles are hand-written entry files**: `cmd/<profile>/main.odin` imports the selection and calls each package's
  `init`, and `routes.odin` mounts one line per package in each host's table, as the skeleton's `main.odin` and
  `routes.odin` do; the build line picks the families (D7; LC §6);
- **any selection is a hello world**: `tools/init` composes it into a project that boots to one working card per
  selected feature (D26, D27);
- **several full implementations where the choice matters**: four chat transports, two bot backends, two stores, two
  client runtimes and two terminal modes (D8).

The pitch, for the README (adapted from PF §1.1):

> Server-rendered web apps in Odin and htmx 4, one self-contained binary per feature selection. The skeleton showed
> that, for a large class of apps, an Odin binary which renders HTML and lets htmx swap it is the right tool. The
> starter keeps that thesis and makes it granular: every capability is a package, a profile is the list of packages it
> mounts, and where a choice matters there is more than one full implementation, picked by one build flag or one
> `switch`. The proof is a product a household uses, held to the skeleton's performance or better.

### 3.2 Houston

Houston is the crew's home channel (D28): the household app on apollo where Alex's friends and family talk, ask
the bot, watch home videos, play spark's games and plan things, and where Alex runs the server from one admin area.
It is the `full` profile, branded in `cmd/full/brand.odin`. Scale target: 5–50 accounts, a handful of concurrent
viewers, bursts during gatherings. Its labels, nav and journeys are in §13. Its tenets (D3, from PF §1.2):

1. Every feature answers a real household need, and every htmx extension and behaviour earns its place through one of
   those needs. An extension with no honest product use lives on a session-free lab page, never on Houston's own
   origin: in the `lab` profile, and on Houston's lab host, `houston-lab.alexh95.com` (D21; ANSWERS F2).
2. Reading works without JavaScript on public pages, login, the wiki, video and games: boosted links are real links
   and forms really post. JavaScript makes it live; it does not make it work (D22).
3. One binary, one SQLite file and one media volume per deployment.
4. Branding is configuration (`cmd/full/brand.odin`); packages and route prefixes stay generic (D9).

### 3.3 PHILOSOPHY.md changes, on purpose

`PHILOSOPHY.md` keeps its thesis. It says a change that argues with it needs "a very good reason", or the document
needs "updating on purpose" (`SK/PHILOSOPHY.md:3-5`). The rename keeps that edit visible in one history (10 §7.1;
§4). "The line we hold" (`SK/PHILOSOPHY.md:49`) now reads (D3; RESOLUTIONS X1):

> The shipped app depends on htmx (plus the extensions a profile loads, from the same tarball under the same 0BSD
> licence), odin-http (our fork), optionally SQLite, and optionally _hyperscript. An optional client runtime is still
> a dependency, and is counted as one.

"The 90%, honestly" names eight items. The ledger counts everything that bends the philosophy, so rows 6 and 7 are new
(RESOLUTIONS X1), and row 8 comes with M14 (RESOLUTIONS X42; Q33: yes, 2026-10-26):

| # | Ledger item | What it costs | Why it's worth it |
|---|---|---|---|
| 1 | **app.js** | vanilla JavaScript in every profile (8,501 B in the skeleton, 05 §0) | it does only what the server can't: the theme pre-paint, count-up, the hyperscript gate, the roughly 40-line chunked-upload shim, later the games postMessage listener (D22) |
| 2 | **SQLite**, optional per profile | a C library, statically linked when present, and a C compile step in prepare; FTS5 adds 220,160 B (12 §8) | persistence with no server and no network hop; profiles without it build with no SQLite library (D18) |
| 3 | **_hyperscript 0.9.94**, optional per profile, core only | 39.7 KB br (175,365 B raw, 4.8× htmx's 36,716 B); a second, interpreted runtime; pre-1.0 with a bus factor of about 1 (05 §0); it runs any `_` that reaches the page, so the CSP no longer backstops escaping (05 §5) | the element names its behaviour (`_="install Name"`) and the definition lives with the feature that owns the markup (`static/<f>._hs`), from htmx's own authors; the CSP stays free of `unsafe-eval`, which `hx-on` and hx-live need (05 §9); an install-only gate and vanilla twins keep it contained and replaceable (D22) |
| 4 | **the odin-http fork** | a small diff we maintain (about 300 lines over fac113f, 10 §7.2), vendored in-tree at `app/vendor/odin-http/` and re-applied and re-tested on each upstream bump (D11; ANSWERS F3) | streams on the HTTP port, shutdown deadlines, the crash guard, timeouts and limits need code inside odin-http (S1); offered upstream after M2, through a fork made then (Q4) |
| 5 | **ffmpeg, an offline tool** on the dev PC | a GPL tool (S21), run by hand through `tools/transcode` | home video as MP4, HLS and AV1 with no transcoder in the app (07 §4.3, D33); never in a shipped binary or a published image (S21) |
| 6 | **`tools/bundle`**, a prepare-time Odin tool | a prepare step that reruns whenever CSS, `_hs` or extension files change, where the skeleton's prepare ran once (`SK/CLAUDE.md` "Build / run / verify"); it calls the `brotli` and `gzip` CLIs, because core Odin has no compressor (09 §0.8) | it concatenates pinned, SHA-verified files in a fixed order and precompresses them (D19): no module graph, no transpile step, no npm, and nothing at runtime, so it is a bundler only in the sense of concatenation, against "No bundler, no framework, no build step beyond `odin build`" (`SK/PHILOSOPHY.md:14`) |
| 7 | **`platform/guard`**, non-local control flow | `setjmp`/`longjmp`, formally UB (R4), against PHILOSOPHY's "no hidden control flow" (`SK/PHILOSOPHY.md:38`); confined to one package and the fork's callback entry points | Odin has no recover, so without it a single trap kills every stream on every loop (13 §0); pure-or-exit keeps it from hiding bugs: every trap is logged, and a dirty one exits with code 70 (D15; §10) |
| 8 | **the device feed's plain-text stream** (M14, optional) | a non-HTML representation: a plain-text `text/event-stream` (unread count, presence, next event, bot health) beside the HTML every other route answers, with a format spec of its own (§22.3) | screens that can't render HTML (the touch panel and the OLED tiles of §20.8) still show Houston's state, and the server still renders every line of it (RESOLUTIONS X42) |

Row 8 enters `PHILOSOPHY.md` in the change that lands the feed, and M14's exit gate checks it (§22.3; ANSWERS round 4).

**What is not a runtime dependency** (RESOLUTIONS X1):
- Each profile still runs bare (`./bin/<profile>`) with no proxy. The compose and stack-Caddy setup on apollo (§20.4)
  is hosting topology for running the hosted profiles side by side on one box, not something a profile needs.
- hx-pending's optimistic copies and hx-history-cache's sessionStorage snapshots are transient caches of
  server-rendered HTML. The server stays the source of truth.

**Never added unless Alex asks.** Adopting any of these adds a ledger row in the same change (D3):

| Item | Why it stays out |
|---|---|
| an xterm.js lab | 488 KB of second runtime (07 §0.4) that needs `style-src 'unsafe-inline'` (11 §5.2; Q8) |
| a live-Alpine page | Alpine is a client framework; hx-alpine-compat stays inert (D21) |
| hyperscript's `socket`, `eventsource`, `worker`, `component` | banned: no reconnect, a leaking stream, CSP failures, client-side templating (05 §0; D22) |
| litestream | checkpoint coordination is unverified (08 §9; D16) |
| a PWA service worker | offline-first is outside the sweet spot (`SK/docs/USE_CASES.md:33`; Q22) |
| i18n catalogs | out by default (Q22) |
| SSO with spark | rejected with the reverse proxy under the starter's domain (S22) |
| runtime disabling of compiled features | the build line and the profile's imports are the selection (S17); `/admin/modules` shows features, never toggles them (Q28; D36) |

Other skeleton docs that drifted (STRIP.md, the e2e and load PLAN files) are rewritten or removed, not copied (D45;
§5).

### 3.4 Scope honesty

`SK/docs/USE_CASES.md:34-40` names games and "latency-hostile UX" as the wrong tool. The starter crosses that line
twice, on purpose, as stress tests of the thesis: the terminal (a key echo over the LAN, D38's budget p95 ≤ 50 ms,
**UNVERIFIED (M11)**; 07 §3.3) and c4 (server-authoritative connect-four over WS, on the cut list; D34). spark's
games are embedded, not rebuilt in hypermedia (D34). `USE_CASES.md` gains a note: server-authoritative, event-rate
realtime is in scope; 60 fps client loops stay out (10 §7.1).

### 3.5 Licences

Everything shipped is permissive: htmx, its extensions and _hyperscript are 0BSD, odin-http is MIT, Odin is zlib and
SQLite is public domain (10 §8.1), so the starter's own source stays zlib (10 §8.2). Copyleft appears only in
published container images (the distroless base's Debian packages, listed in a `SOURCES.md`; Q18) and in dev tools
that are never distributed (k6, axe-core) (10 §8.2). `THIRD_PARTY_NOTICES` and the `/licenses` route carry
odin-http's MIT notice, the Unicode V3 notice and the Shopify MIT notice that `hx-multipart.min.js` drops (10 §8.3).

## 4. Repo decision and transition

The brief asks for "the decision: promote the skeleton, or start a new repo and retire the skeleton". **The decision:
promote the skeleton by renaming it in place**, from `alexh95/odin-htmx-skeleton` to `alexh95/odin-htmx-starter`.
History, issues, releases, settings and secrets carry on, and versioning continues at v2.0.0 (D1). Alex confirmed it
on 2026-10-25 (Q1: yes; ANSWERS #5) and asked that all starter work happen in this workspace, `<WORKSPACE>`, never
the old `<OLD_DEMO_DIR>` folder; this workspace becomes the renamed repo's checkout at M0 (ANSWERS F5; §4.2).

**Why, in short.** The skeleton has almost no outside surface to break (0 forks, §4.1). GitHub redirects the old name
for the web, git and the API, and spark's pin keeps resolving because the history is continuous. A new repo would
move issues, releases and secrets by hand, and a fresh-history one would break spark's pin with no visible error
(10 §0, §2.1, §2.2, §5.2; §4.6). **What "retire the skeleton" becomes:** the old name is retired behind GitHub's
redirect and never reused, the code is frozen as tags v1.2.0 (709bc94) and v1.2.1 (6d37506, the crash fix already on
`master`) and branch `skeleton-1.x`, and the live demo carries on as the `skeleton` witness (§4.3).

### 4.1 The options

The skeleton has almost no outside surface: 0 forks, 1 star from an outside account, no public repo that references
it, and 26 views (4 unique visitors) in 14 days (10 §0). Its only downstream is spark's portal, pinned at 709bc94.
After a rename GitHub redirects web URLs, git clone, fetch and push, the REST API (301 to `/repositories/<id>`), archive
tarballs and Actions badges; this was verified on the renamed `containers/libpod` (10 §2.1). The redirects die if a
repo is ever created under the old name, so `odin-htmx-skeleton` is never recreated: the frozen skeleton lives in a
tag and a branch.

| Option | History | Redirects | spark's pin | Issues, releases, secrets | Live demo | Verdict |
|---|---|---|---|---|---|---|
| (a0) in place, keep the name | continues | not needed | unchanged | stay | unchanged | rejected: "skeleton" contradicts a superset starter, and the brief asks for the decision (10 §2.4) |
| **(a) in place + rename** | continues | web, git, API, tarballs, badges (10 §2.1) | resolves through the redirect (10 §5.2) | all carried, with the template flag | unchanged once `FLY_DEPLOY` is off (10 §4.2) | **chosen** (D1) |
| (b) new repo with history, archive the skeleton | carried by `clone --bare` + `push --mirror` | none; an archive banner | resolves only after spark repoints; silently stale until then | issues one by one, the rest re-entered by hand (10 §2.2) | unchanged until Alex acts | runner-up (10 §10) |
| (b′) new repo, fresh history | lost | none | unresolvable: `upstream.ps1` throws and `versions.ps1:19` hides it (10 §5.2) | none carried | as (b) | rejected |
| (c) new repo, skeleton live and frozen | split across two repos | none | watches a frozen repo, 0 behind forever | split across two repos | keeps serving the skeleton (709bc94; 6d37506 from M0) with its known regression | rejected (10 §2.3) |

What the rename does to each part of the repo (10 §2.1):

| Part | After the rename |
|---|---|
| web URLs (repo, issues, PRs, wiki, releases, `/generate`, `/archive/…`) | 301 to the new name |
| git clone, fetch, push; the REST API | keep working; the API answers 301 to `/repositories/<id>` |
| raw.githubusercontent.com paths | still answer 200 |
| variables, secrets, caches, Actions history, releases, topics, homepage, the template flag | stay with the unchanged repo id (an inference: no doc lists secrets for renames, 10 §2.1) |
| the 9 open issues and PR #51 | stay open on the renamed repo (10 §1) |
| not redirected: actions used through `uses:`, GitHub Pages | not applicable: the skeleton is neither an action nor a Pages site |

### 4.2 Transition steps

In D1's order, with the Fly redeploy moved to the M3 exit (RESOLUTIONS X2, X3) and Alex's answers of 2026-10-25
applied (ANSWERS #5, F3, F5). Steps 1, 4 and 9 need Alex.

| # | Step | Who | Why |
|---|---|---|---|
| 1 | Re-run 6d37506's failed CI run so that its deploy job puts v1.2.1 on Fly, confirm `x-version: 6d37506` on odin-htmx.alexh95.com, then set the repo variable `FLY_DEPLOY` to `off` | Alex (the re-run may be the agent's when Alex asks) | the deploy job runs on a default-branch push with `vars.FLY_DEPLOY == 'true'` (`SK/.github/workflows/ci.yml:420`); CI triggers only on pushes and PRs to master/main (`ci.yml:5-9`), so tags and branches never deploy, but starter commits on master would. The default branch is `master`. 6d37506's push ran CI with `FLY_DEPLOY` on, but the run failed (the chromium e2e job timed out in its toolchain step) and skipped the deploy, so on 2026-10-25 the witness still answered `x-version: 709bc94`; after the re-run it serves v1.2.1 until the M3 exit (ANSWERS F5; **UNVERIFIED (M0)**) |
| 2 | Tag **v1.2.0 at 709bc94 with no code change** and **v1.2.1 at 6d37506**, and branch **`skeleton-1.x`** at 6d37506 | agent | the frozen v1.2.0 is exactly the build S18 measures, and the parity baseline stays 709bc94 plus v1.1.1; 709bc94's CI run is green and v1.1.1's is not (10 §1). v1.2.1 is the `Content-Length: -5` fix (`front` answers a malformed `Content-Length` with 400, and `auto_expect_continue` is off), never a baseline (ANSWERS F5). Cutting the branch at 6d37506 rather than 709bc94 is this plan's reading, so the frozen line keeps the crash fix |
| 3 | Optional: the QPSG fix (`sqlite3_db_config(db, 1007, 1)` after open, 01 §14.4) on `skeleton-1.x` as v1.2.2 | agent, for spark | it never changes the baseline |
| 4 | Rename the repo in GitHub settings, and drop "skeleton" from its description (10 §10) | Alex | never create a repo named `odin-htmx-skeleton` afterwards: that kills the redirects (10 §2.1) |
| 5 | Make this workspace the renamed repo's checkout: fetch `master` into `<WORKSPACE>`, remove `_ref/`, fold the workspace's own README (an index of the planning docs) into `docs/` so the repo keeps its README, keep the workspace's root `.gitignore` (it carries the skeleton's entries and §5.3's rules), and commit the planning docs once the scrub is done; then delete the separate clone `<SKELETON_FIX_CLONE>` | agent | all starter work happens in this workspace (ANSWERS #5, F5); the paths §5.3 keeps git-ignored never reach the public repo (ANSWERS F4) |
| 6 | First starter commit: the `tools/init` identity literals change in lockstep, read from one `tools/init/UPSTREAM` file; add `THIRD_PARTY_NOTICES` | agent | init refuses to run unless `brand.odin` holds the exact upstream `BRAND_REPO` line (`SK/tools/init/main.odin:48-53,197`, `SK/app/src/views/brand.odin:28`), and its README, JSON-LD, favicon, sweep and brand edits must each match (`main.odin:208-246,288-309`; 10 §5.3); `hx-multipart.min.js` drops its Shopify MIT notice (10 §8.3) |
| 7 | Vendor laytan/odin-http fac113f into `app/vendor/odin-http/` with an `UPSTREAM.md`, replacing the skeleton's `app/odin-http` submodule; F-1..F-13 land on top, S0.2's changes first | agent | the fork lives in-tree, with no separate GitHub repo (D11; Q4; ANSWERS F3) |
| 8 | At the M1 exit, when the `skeleton` profile passes the parity gate, the agent tags **v2.0.0** with `FLY_DEPLOY` still off | agent | the brief puts apollo before the web, so the Fly witness is not redeployed at M1: odin-htmx.alexh95.com keeps serving 6d37506 (v1.2.1) untouched until the M3 exit (RESOLUTIONS X2; Q29: yes) |
| 9 | At the M3 exit, once `starter-skeleton` has passed the parity gate and the 40-item checklist on apollo's LAN (stage 1a), with `deploy/fly/fly.toml` building `cmd/skeleton`: Alex sets `FLY_DEPLOY=true` first, then the agent pushes the **v2.2.0** tag, and its `deploy-fly` run deploys `cmd/skeleton` | Alex, then agent | the starter's `deploy-fly` job deploys only on a tag while `FLY_DEPLOY` is `true` (D40; §20), so the variable must be on before the tag's run starts (RESOLUTIONS X3); the agent then checks the witness's cost against Q15's $10/month line (§20.6) |

Afterwards: `_ref/` and the separate clone are gone (step 5); spark's bare clone and any clone of Alex's own keep
working through the redirect, and updating their remotes is tidying, not a fix (10 §2.1). Once the starter stack runs
on apollo, Alex retires the old skeleton container on `:8090` (Q27). The skeleton's unspent distribution
(awesome-odin, htmx's server examples, r/odinlang, Show HN) is spent on the starter once the name and hosts are final
(10 §3.1, §10).

### 4.3 The live demo becomes the skeleton witness

`odin-htmx.alexh95.com` stays on Fly (region fra, Cloudflare-proxied) and, from the M3 exit, serves the starter's
`skeleton` profile. It is the standing witness for "the skeleton's performance and feature set": the same host and
machine size before and after, with `x-version` naming each deploy (10 §4.1). The Fly app keeps the name
`odin-htmx-skeleton`: Fly apps can't be renamed, and the name shows only as `odin-htmx-skeleton.fly.dev`, which 301s to
`SITE_URL` (10 §0, §3.3). The host's Bing and IndexNow keys identify the host, not the repo, so they stay valid (10
§3.2). Houston never runs on Fly. Fly's settings and its cost (Q15: keep it, and warn Alex above $10/month) are in
§20. From M0 (§4.2 step 1) until the M3 exit the witness serves 6d37506 (v1.2.1, the skeleton's crash fix) untouched,
so "apollo first" holds without exception: the starter's code reaches Fly only after `starter-skeleton` has passed
the parity gate and the 40-item checklist on apollo's LAN (RESOLUTIONS X2; Q29: yes, 2026-10-25; ANSWERS F5; §20.3).

### 4.4 spark's pin

spark's pin (`spark/ws/portal/UPSTREAM.md:7`, 709bc94) stays and keeps resolving through the redirect, because the
history is continuous (10 §5.2). Its watched paths go stale once `app/src/*` moves into `platform/` and `features/`,
but nothing breaks on day one; SP6 repairs it after M1, at Alex's pace, as an Ark CL (D43). The details are in §21.4.

### 4.5 Versioning

SemVer continues in the same tag list. v1.2.0 (709bc94) is the skeleton finale and v1.2.1 (6d37506) its crash fix; a
QPSG backport would be v1.2.2 on `skeleton-1.x` (§4.2). **v2.0.0 comes at the M1 exit** (tagged with
`FLY_DEPLOY` still off, §4.2), because the restructure (the layout, the init CLI, the CLAUDE.md recipes) breaks anyone
who follows the template (10 §6). After that, each milestone is one minor release (M2 = v2.1.0 … M12 = v2.11.0; M13
is a spark CL, and the optional M14 takes the next minor), and a major comes only with a breaking change (D40). The
CHANGELOG continues in the same file (10 §6) under the same Conventional Commits policy (D40), with its pre-2.0
entries left in place (10 §6 makes moving them to a separate file optional; D40 is silent). Forks record their
upstream version, commit and init command line in `UPSTREAM.md` (D26; §7).

### 4.6 Why not the alternatives

A new repo with carried history and an archived skeleton moves issues, releases, settings and secrets by hand, and a
fresh-history repo breaks spark's pin with no visible error (10 §2.2, §5.2). Keeping the skeleton live and frozen
keeps the bound-LIMIT regression in public and doubles the upkeep (10 §0, §2.3). Landing the QPSG fix before tagging
v1.2.0 (PF §2, CF §2.1) is rejected too: it changes the frozen reference, and in PF's order the live demo is still
armed to redeploy (D1).

## 5. Architecture: layers, packages and the directory tree

This section is the static shape of the code: which package may import which, what each platform package holds, where
files live, who owns memory, and what CLAUDE.md now says. How features plug together is §6; what gets built is §7.

### 5.1 Layering

The skeleton's strict layering (`SK/CLAUDE.md` "Architecture — strict layering") extends to two axes, platform and
features (D4), and the layers call each other directly, with no dependency injection (ANSWERS #1; LC §5). An arrow
means "may import":

```
app/cmd/<p>/   brand.odin main.odin routes.odin routes_test.odin   (all hand-written)                ─► everything
   │
   ├─► f_web            features/f/web/          ─► f, f_models, f_views, f's switched impls, notify_web, store:audit, platform L1–L3
   │     ├─► f_<axis>_<impl>  (switched)         ─► f, f_models, f_views, platform L1–L3       transport_ws, backend_llama, catalog_api …
   │     └─► f_views    features/f/views/        ─► f_models, f, platform/html
   ├─► f                features/f/  (services)  ─► f_models, store:f, store:audit, other features' domains, platform L1–L2
   ├─► f_store_<family> app/stores/<family>/f/   ─► f_models, platform/store*, platform/sqlite (SQLite family), platform/workers
   └─► f_models         features/f/models/       ─► core, platform L1–L2 types

platform  L4 app      ─► identity:., store:., L1–L3             (only cmd/* imports it; it holds front)
          L3 web html hub stream stream/client client/* theme/*   (html ─► client:., theme:.)
          L2 store store/sqlite store/memory env authz authz/anonymous obs guard workers markdown password totp
          L1 sys sqlite ext escape signed fuzz
```

Each feature `f` is a set of packages (D4, with RESOLUTIONS X30 applied to the web row and LC §5's models and stores):

| Package (Odin name) | Directory | Holds | May import | Never imports |
|---|---|---|---|---|
| models `f_models` | `app/features/f/models/` | types, enum label tables, the store contract's proc types (§6.4) | core, platform L1–L2 | anything of `f` |
| store `f_store_<family>` | `app/stores/<family>/f/` | one store and its `contract.odin`; `migrations/` in the SQLite family | `f_models`, `platform/store*`, `platform/sqlite`, `platform/workers` | `f`, `f_views`, `f_web`, other stores, any collection |
| domain `f` | `app/features/f/` | services: validation, rules, ownership checks; plain values and errors, never HTTP | `f_models`, `store:f`, `store:audit`, other features' **domain** packages it depends on, platform L1–L2 | odin-http, `platform/web`, `platform/html`, `platform/hub`, another feature's store |
| views `f_views` | `app/features/f/views/` | HTML builders over `^strings.Builder` | `f_models`, `f`, `platform/html` | stores, `f_web`, odin-http |
| switched impl `f_<axis>_<impl>` | `app/features/chat/transport_ws/`, `bot/backend_llama/`, `games/catalog_api/` … | one transport, backend or catalog, chosen per request or per process by `f_web`'s switch (§6.4): its `NAME`, `EXTS` and handlers | `f`, `f_models`, `f_views`, platform L1–L3 | `f_web`, other impls, odin-http |
| web `f_web` | `app/features/f/web/` | handlers, `ROUTES` (its impls' rows too), `TOPICS`, `JOBS`, `EXTS`, `init`/`start`/`drain`, `home_card`, the axis switch, hub publishes and write continuations, stream adapters, background adapters (pollers, the llama worker's glue) | `f`, `f_models`, `f_views`, its own impls, `notify_web` (producers, §6.2), `store:audit`, platform L1–L3 | any other web package, `platform/app`, odin-http |
| identity `accounts_identity_<x>`, `authz_anonymous` | `app/features/accounts/identity_*/`, `app/platform/authz/anonymous/` | `NAME`, `SETS_COOKIE`, `load_viewer`, `cli`, its `ROUTES` (`/login`, `/logout` …) | `accounts_models`, `store:audit`, platform L1–L3 (`anonymous`, in L2: L1–L2); `identity_accounts` also `accounts` and `accounts_views` | `accounts_web`, other identities, `platform/app`, any store but audit; `nick` and `envadmin` never reach SQLite (D18) |
| entry | `app/cmd/<profile>/` | `brand.odin`, `main.odin`, `routes.odin` and `routes_test.odin`, all hand-written (§7.2) | everything | — |

**The rules** (LC §5):
- **Only the domain imports its store**, as "controllers never import repository" in the skeleton. Two importers are
  allowed besides: any domain, web or identity package for `store:audit` (§6.2), and a SQLite profile's `main` for
  `MIGRATIONS` (§11.7).
- **A store never imports its domain**: the domain calls the store directly, so that would be an import cycle
  (14 (1)). The shared types and the contract's proc types sit in `f_models`, below both, as the skeleton's `models`
  does.
- **A web package reaches another feature four ways only**: a domain import for a hard dependency (dashboard →
  contacts, video → uploads; D6), `notify_web` (the one web-to-web edge), a hub topic named by string, or a plain link
  (§6.2).
- **Below L4, platform never imports a feature except through a family.** `platform/app` imports `identity:`, whose
  members include feature packages; `platform/html` imports `client:` and `theme:`, which are platform packages and
  never import `platform/html` (that would be a cycle).
- **Features never import `platform/app`**, so the typed env table lives in `platform/env` (L2), and `Search_Hit` in
  `platform/store` (L2), because domains return it.
- **Preferences travel on the `Viewer`** that the identity loads (theme, chat transport, mutes from `accounts_prefs`,
  RESOLUTIONS X9), so chat, notify and `platform/html` read them without importing accounts (**NEW**).

**Platform layers** (D4, with RESOLUTIONS X30, X33; LC §5): **L1 bindings and leaf tables** `platform/sys`,
`platform/sqlite` (core only), `platform/ext` and `platform/escape` (no imports beyond core); **L2 core** `store`, `store/sqlite`, `store/memory`, `env`,
`workers`, `authz`, `authz/anonymous`, `obs`, `guard`, `markdown`, `password`; **L3 I/O** `platform/web`, `stream`,
`stream/client`, `hub`, `html`, `client/hyperscript`, `client/vanilla`, `theme/full`, `theme/lite`; **L4 composition**
`platform/app`. A layer imports its own layer and the layers below it, never above (inside L3, `hub` uses `stream`'s
encoders and the layout takes a `web.Bundle`, D19). No layer needs an exception:
- **`platform/app` is L4, the composition package.** It holds `front` and `app.Host`, and its `boot`, `check`, `serve`,
  `wait` and `shutdown` procs start and stop the server through `platform/web`, so it sits on top and imports L1–L3
  and the `identity:` family. Only `cmd/*` imports it (RESOLUTIONS X30, as LC §5 recasts it).
- **`front` lives in `platform/app`, not `platform/web`**: the identity packages import `platform/web` for their routes
  and cookies, so `platform/web` can't import `identity:` without a cycle (LC §5; **NEW**: not prototyped).
- **No feature package imports odin-http.** `platform/web` re-exports `web.Request :: http.Request` and
  `web.Response :: http.Response`, so every handler is written over `^web.Request` and `^web.Response`.
- **`platform/obs` (L2) supplies the data, `platform/web` serves it**: obs keeps the counters and health state, and web
  serves `/metrics`, `/livez`, `/readyz` and `/healthz` from them (13 §5.3).

**Platform work that touches an optional package, without a callback** (LC §5; **NEW**). Each is a direct call in one
direction:
- **The pure-trap reset** of the loop's reader statements (D15 rule 3) is pulled, not installed: `platform/guard`
  counts recoveries per thread, and `platform/store/sqlite` compares that count before each use of the loop's reader,
  and on a 1 s timer that the reader's first use arms on its loop, and resets every statement when it has moved
  (§10.2; S0.6). `guard` never calls into SQLite, so a memory profile still links none (D18).
- **SQLite numbers for ops** (`sqlite3_db_status`, the writer queue, pool depth) are pushed to `platform/obs` by
  `platform/store/sqlite` on its own timer. `ops` reads obs and never imports the store, so `streams` keeps ops without
  SQLite.
- **CLI flags owned by an optional package** are answered by that package, called from `main`: `--backup` and
  `--adopt-profile` by `store_sqlite`, `--hash-password` by `identity.cli` in the identities that check an argon2id
  hash (`accounts`, `envadmin`; `nick`'s and `anonymous`'s `cli` answer nothing). `platform/app` answers only the
  platform's own (`--features --routes --limits --healthcheck --worker`), so a profile without SQLite or a hashing
  identity links neither for a flag (§8.6).
- **Feature health and limits** are pushed to `platform/obs` as data; `status`, `modules` and `/readyz` read obs and
  `platform/env`, plus the tables `platform/app` holds after `app.serve`, and none of them imports a feature (§10.4).

**Enforcement.** Every rule above, the L4 placement, the collection rules and the odin-http rule included, is a CI
gate, `tools/check imports` (D4, D39; RESOLUTIONS X30; LC §11), not a review convention. It reads each package's
`import` lines (syntactically trivial, 09 §4.6) and checks them against the table: `store:<f>` only from `f`'s
domain, `store:audit` from any domain, web or identity package, either from a SQLite profile's `main`; `identity:`
from `platform/app` and `cmd`; `client:` and `theme:` from `platform/html`; and no web package imports another but
`notify_web`. The compiler already refuses cycles; the skeleton's direction rule was kept only by review (01 §1). The
split into packages exists because with one package per feature the layer rules become per-file conventions: all
files of a package see each other (09 §4.4; CF §3.1). Rejected: feature web packages that also hold views, and a
domain-plus-views package (D4).

**The request path** stays the skeleton's (`SK/PHILOSOPHY.md` "What it buys", Legibility), with no hop added (§6.5):

```
route ─► f_web handler ─► f service ─► store:f (the build's family) ─► f_views render ─► respond
                                     └─ f_web publishes to the hub after the service returns
```

Services stay pure, and views stay the only place HTML is built. Under store v3 a write commits on the writer task, so
the tail of a write handler (publish, notify, respond) is the write's continuation, a named proc in the same web file
(D16; LC §8; §11.1). Inside a feature, `static/` (`f.css`, `f._hs`) and `README.md` with fixed headings (§5.5) are files
by convention, not packages; its SQLite migrations sit in its SQLite store, `app/stores/sqlite/<f>/migrations/`.

### 5.2 Platform packages

| Package | Layer | Holds | Source |
|---|---|---|---|
| `platform/sys` | L1 | glibc `_setjmp` (3 ns, against 298–518 ns for `setjmp`), `sigaction` + per-thread `sigaltstack`, Windows VEH + `_resetstkoflw`, `setrlimit(NOFILE)`, vDSO `clock_gettime` (19 ns against 324–377 ns for Odin's raw-syscall `tick_now`); the thread-local counters (`locks_held`, `async_posted`, `in_sqlite`), kept here because `platform/sqlite` (L1) raises `in_sqlite` and can't import the guard (M1) | 13 §1.5, §5.5 |
| `platform/escape` | L1 | `w`, `esc`, `url_encode`, `json_esc`: the injection boundary, one definition of each. `platform/markdown` renders at write time in L2, so the boundary sits below it; `platform/html` re-exports it for views (M1, **NEW**) | `SK/app/src/views/html.odin:17-53` |
| `platform/ext` | L1 | the closed `Ext` enum (17 htmx extensions) with its registration-name and file tables; imports nothing; re-exported as `web.Ext`, so domains can name extensions without importing L3 | RESOLUTIONS X33; D19 |
| `platform/sqlite` | L1 | the SQLite binding plus spark's additions (`bind_blob`, `stmt_readonly`, `progress_handler`, `OPEN_READONLY` …); it increments `in_sqlite` around every call into SQLite, and binds `""` as empty text, never NULL | `SK/app/src/sqlite/`; 06 §3.1; D15 |
| `platform/guard` | L2 | `guard_call`, the helpers that keep `platform/sys`'s counters (`locks_held`, `async_posted`; `in_sqlite` is the binding's), `guarded_mutex` (the only `sync` locks allowed), the trap handler, the watchdog thread (§10) | 13 §1.4, §6.3; D15 |
| `platform/obs` | L2 | logfmt into per-thread buffers (≤ 1 µs per request), request ids `<boot>-<loop>-<seq>`, per-thread counters and health state, which `platform/web` serves as `/metrics` (Prometheus 0.0.4, admin or token) and `/livez /readyz /healthz` (RESOLUTIONS X30), spall behind `-define:PROFILE=true` | 13 §5, §6.2 |
| `platform/authz` | L2 | `Role`, `Perm`, `ROLE_PERMS`, `Viewer` (it carries the member's preferences), the identity contract `Load_Viewer (ask: Ask) -> (Viewer, set_cookie)`: `front` hands it the Cookie header, the client address and whether the request came as https, so no identity sees odin-http's types (§17; M1) | 07 §5.2; D35; LC §3, §5 |
| `platform/authz/anonymous` | L2 | `authz_anonymous`, the default identity: every viewer is the Guest, nothing sets a cookie, and its `cli` answers nothing; a member of the `identity` family | D35; LC §3 |
| `platform/env` | L2 | the typed env table (D10): rows `{name, type, default, secret, doc}`, the platform's recorded by `app.boot` and each feature's by its `init`, which then reads its own (§8.5) | 09 §4.5; D10; LC §5 |
| `platform/workers` | L2 | the `argon`, `query`, `llama` and `jobs` pools; the scheduler over the mounted `JOBS` rows (`run_now(id)`, `cancel(run)`, each run's state kept as data); replies by `next_tick` with a connection generation check; a full queue answers 503 | S11; 12 §4; D16; LC §9 |
| `platform/markdown` | L2 | spark's safe-subset renderer: nesting depth cap 32, input cap 64 KiB, rendered at write time, pure zone; relative doc links and images resolve against two prefixes the caller passes (`/wiki/`, a media folder) instead of spark's game paths | S6; 06 §3.2; D15 |
| `platform/store` | L2 | what every store shares: `Migration`, `Error`, `enum_from_int` (validated enum reads, fixes 02 F3), `Search_Hit` and `Find_Source`; each feature's store contract lives in its `models` package (§6.4) | S8, S9; D4, D16; LC §5 |
| `platform/store/sqlite` | L2 | store v3: one writer, per-loop readers, the writer task, the query pool, `open` (`--backup`, `--adopt-profile`) and the per-feature `migrate` (§11); it pulls the pure-trap reader reset from guard's recovery count and pushes its `sqlite3_db_status` numbers to obs (§10) | 12 §9; D16; LC §5 |
| `platform/store/memory` | L2 | rings and maps behind guarded locks, ids `<epoch>-<seq>` | D16 |
| `platform/web` | L3 | the prefix router, one map per host (§8), CSP route flags (D20), `Req_Ctx`, `respond_*`, `web.Request` and `web.Response` (odin-http's types, re-exported so no feature imports odin-http), per-route body caps, the trusted-proxy client address, the limiter, assets (fingerprints, br/gz/identity), robots/sitemap/Bing/IndexNow, `/licenses`; `web.Route`, `web.ROUTES` (a site's main host: the `/metrics /livez /readyz /healthz` routes over obs's data, the sitemap, the ownership proofs) and `web.PUBLIC_ROUTES` (every host); the `web.Ext`, `web.Route_Flag` and `web.Bundle` enums | `SK/app/src/controllers/middleware.odin:38-87,182-306`; 06 §3.1; 11 §6, §8; LC §7 |
| `platform/html` | L3 | `w esc url_encode json_esc` (re-exported from `platform/escape`), the layout, NAV, `Home_Card`, the skeleton's components; `Behaviour`, `BEHAVIOURS` and `behave`, the only emitter of `_` and `data-behave` (§12); it imports the `client:` and `theme:` families | `SK/app/src/views/html.odin:17-53`; 01 §3; D22; LC §3 |
| `platform/stream` | L3 | the SSE encoder, WS handshake and codec, multipart writer, Range sender (§8) | 03 §7, §10; D12 |
| `platform/stream/client` | L3 | one non-blocking chunked/SSE/WS client on `core:net` for `features/bot/backend_llama`, `cmd/term-agent` and `tools/streamload` (**NEW**) | D12 |
| `platform/hub` | L3 | topics declared in per-package `TOPICS` tables and mounted per host, per-loop inboxes, replay rings, policies, a row's `deliver`, heartbeats (§9) | S3; 03 §7; D13; LC §6, §9 |
| `platform/client/hyperscript` | L3 | the `client` family's hyperscript member: _hyperscript 0.9.94 core, served by the binary; `behave` writes `_="install Name"` | S15; D22 |
| `platform/client/vanilla` | L3 | the `client` family's vanilla member: `behave` writes `data-behave="name"`, routed by one delegated listener in app.js | D22 |
| `platform/theme/full` | L3 | the `theme` family's full member: 6 styles × 24 schemes and the hashed pre-paint | D23 |
| `platform/theme/lite` | L3 | the `theme` family's lite member: the `modern` style with `midnight` and `daylight`, the same pre-paint script | D23 |
| `platform/app` | L4 | the composition package: `front` (§8.4), `app.Host`, `boot`, `check` (the boot checks, §6.1), `serve`, `wait`, `shutdown`, and the platform's CLI `--features --routes --limits --healthcheck --worker`; it imports L1–L3 and the `identity:` family, and only `cmd/*` imports it | 09 §4.5; 13 §4.2, §6.1; 06 §3.1; RESOLUTIONS X30; LC §5 |

### 5.3 The directory tree

Every feature directory holds its domain files, `models/`, `views/`, `web/`, `static/` and `README.md`; the tree lists
only what each adds. Its stores live under `app/stores/`, one directory per family, and a feature with no member in a
family has no directory there, so a build that reaches it fails to compile (D18; LC §3).

```
odin-htmx-starter/
  PHILOSOPHY.md  CLAUDE.md  README.md  CHANGELOG.md  TODO.md  LICENSE  THIRD_PARTY_NOTICES  SOURCES.md
  build.sh build.bat          build.{sh,bat} <profile>: the one place the family flags live (CMD=check|test|run)
  ols.json                    the editor's four collections, pinned to full's families (the skeleton's sat in app/)
  app/
    vendor/odin-http/         the fork, vendored: laytan fac113f + F-1..F-24, with UPSTREAM.md (D11; ANSWERS F3)
    vendor/sqlite/            3.53.4 amalgamation; prepare builds it with D16's flags
    vendor/htmx/              the htmx 4.0.0 tarball pin → htmx.min.js + the 17 dist/ext files
    vendor/hyperscript/       _hyperscript.min.js 0.9.94 + its shipped .br
    prepare.sh prepare.bat run.sh run.bat     as in the skeleton; both call the root build.*
    build/                    prepare output, git-ignored: per-profile bundles (.br, .gz), CSS, _hs
    platform/
      sys/ sqlite/ ext/ escape/ app/ env/ store/ store/sqlite/ store/memory/ workers/ authz/ authz/anonymous/ obs/ guard/
      markdown/ web/ stream/ stream/client/ hub/ html/ client/hyperscript/ client/vanilla/ theme/full/ theme/lite/
      static/                 base.css, app.js, core _hs, favicon, og.png (not a package)
    features/                 each: models/ views/ web/ static/ README.md, + storetest/ where it has a store (D37)
      home/  about/  dashboard/  gallery/  modules/  ops/  status/  find/  c4/  dbview/
      landing/  scripting/  compat/  lab/
      notes/ jobs/ notify/ lists/ polls/ calendar/ guestbook/ uploads/ audit/ wiki/ video/ contacts/
      chat/       transport_ws/ transport_sse/ transport_poll/ transport_multipart/
      bot/        backend_mock/ backend_llama/
      accounts/   identity_accounts/ identity_envadmin/ identity_nick/
      games/      catalog_static/ catalog_api/
      term/       grid/ (server) vt/ (the agent's parser)
    stores/
      sqlite/     each <f>/: store.odin contract.odin migrations/NNNN_name.sql (package <f>_store_sqlite)
                  notes/ jobs/ notify/ lists/ polls/ calendar/ guestbook/ uploads/ audit/ wiki/ video/ chat/ bot/
                  accounts/ term/ contacts/ (migrations 0001–0003 keep their hashes, + 0004_sort_indexes)
      memory/     each <f>/: store.odin contract.odin (package <f>_store_memory); no accounts/, contacts/ or term/
                  notes/ jobs/ notify/ lists/ polls/ calendar/ guestbook/ uploads/ audit/ wiki/ video/ chat/ bot/
    cmd/
      minimal/ skeleton/ streams/ full/ lab/     brand.odin main.odin routes.odin routes_test.odin each;
                                                 full-vanilla is cmd/full built with the vanilla client (§7.1)
      term-agent/                                the Raspberry Pi agent (linux_arm64), not a profile
  e2e/          playwright.config.ts  global-setup.ts  helpers/  tests/<f>/*.spec.ts (tagged @<f>, @<f>-<impl>)
  load-tests/   run.sh  lib/  scenarios/<f>/*.js
  perf/         baseline/  results/
  tests/        parity-waivers.txt
  tools/        init/ (+ UPSTREAM)  bundle/  check/  baseline/  streamload/  fakellama/  transcode/  watch/  og/
                profile/ (M2: perf and spall, M1's profile made repeatable)
                upstream/ (paths.json)
  deploy/       compose.yaml  Caddyfile  promote.ps1  docker/Dockerfile  docker/seccomp-io-uring.json
                fly/fly.toml  pi/term-agent.service
  docs/         BRIEF.md PLAN.md CATALOG.md catalog.json DATA.md USE_CASES.md SECURITY.md OPS.md
                design/ spikes/ audit/ perf/
                research/ private/               git-ignored (ANSWERS F4), as are design/proposal-*.md and design/OUTLINE.md
  .github/      workflows/{ci.yml, nightly.yml, release.yml}  matrix/pairwise.json
```

A fork made by the generator has `cmd/app/` instead of the profile directories, and its `build.*` names one profile,
`app` (§7.4).

**Public-repo hygiene** (ANSWERS F4). The repo is public, so `.gitignore` keeps `docs/research/`,
`docs/design/proposal-*.md`, `docs/design/OUTLINE.md` and `docs/private/` out of git. LAN addresses, apollo's
hardware and the services running on it, user names and host paths live in the git-ignored `docs/private/SITE.md`,
and the public docs use placeholders. The planning docs are scrubbed to that rule before their first commit (§4.2
step 5), and every later doc follows it. Citations of the research notes and the proposals stay; the cited files are
local only.

### 5.4 Allocator model

Three buckets (D12), written into CLAUDE.md's "Allocator model" and the review rubric (02 §2.8 item 1):

| Bucket | Allocator | Lives until | Holds |
|---|---|---|---|
| request | `context.temp_allocator`, odin-http's per-connection arena | the response is flushed (02 §2.7) | response HTML, parsed forms, store snapshots for this request |
| process | `context.allocator`, at boot | the process exits | ETags, CSP strings, fingerprinted asset names, the parsed env table (`SK/CLAUDE.md` "Allocator model") |
| connection | the heap: the stream's `Conn` and its buffers (M2; D12) | one tick after `on_close` (03 §7) | subscriptions, cursors, per-socket buffers |

The rules:
- Handlers copy what they need before returning; after the handler the request arena is per-callback scratch (03 §7).
- Every timer, cross-thread and worker callback ends with `free_all(context.temp_allocator)`: nbio hands it the
  tick's context, whose temp allocator odin-http never frees (03 §2.8).
- Stream state never lives in the temp arena, which is freed under it after each flush (02 §2.7; S4).
- Structs a callback may still use (`Stream`, `Conn`) are freed one tick after `on_close`, which removes the
  use-after-free where `on_close` runs inside a frame parser (03 §7).
- A stream's state is not a `virtual.Arena` per stream, as D12 first had it: an arena commits a 4 KiB page, and F-1's
  `Stream` already holds a 4 KiB receive buffer, so the pair would pass §18.4's 6 KiB per open stream (M2).
- A recovered pure crash leaks what it had allocated from `context.allocator`; that is why many recoveries in a short
  window count as dirty (D15, §10).

### 5.5 What CLAUDE.md says now

The starter's `CLAUDE.md` keeps the skeleton's contract (standing policy, Conventional Commits, code aesthetics, views
and HTML rules, htmx gotchas, validation, CSS and JS conventions) and changes these parts on purpose (D45; LC §15):

| Part | What it says |
|---|---|
| Architecture | the platform layers and feature package shape of §5.1 (models, domain, views, web, switched implementations; the stores by family in `app/stores/`), with the `tools/check imports` table and its collection rules; layers call each other directly (ANSWERS #1) |
| Build | every build, check and test goes through `build.{sh,bat} <profile>` at the repo root (`CMD=check\|test\|run`), the one place the four family flags live; `ols.json` pins the editor to `full`'s families (§7.2) |
| Allocator model | the three buckets of §5.4 |
| Crash model | entry points go through `guard_call`; locks only through `guarded_mutex`; SQLite only through `platform/sqlite` (it keeps `in_sqlite`); what pure and dirty mean (D15, §10) |
| Recipes | new feature (models, domain, views, web, a store in each family it has, static, README; its lines in each profile that mounts it: imports and `init`, `start` and `drain` calls in `main.odin`, a mount line per host table in `routes.odin`; e2e and load scenarios); new store (a package per family, `<f>_store_<family>`, with its `contract.odin`; the storetest); new route (a row in the package's `ROUTES`, or, for a root, the profile's own row in `routes.odin`; e2e and load in the same change); new switched implementation (a package, a case in the web package's switch, its `EXTS` unioned in); new migration (in the SQLite store's `migrations/`, additive; a `migrate` line in each SQLite profile's `main`); new topic (a `TOPICS` row: family, policy, ring, persisted, subscribe, deliver); new job (a `JOBS` row, id prefixed by the feature); new behaviour (enum row, `_hs`, vanilla twin or empty); new perm (enum group, `ROLE_PERMS`); new env var (a row the feature's `init` records, prefix) |
| Gotchas | bare `odin build app/cmd/<p>` fails: it needs the four flags, so use `build.*`; store contracts are typed constants (`_ : m.Store_Insert : insert`), never `#assert(type_of(…) == T)`, which is false even for an exact match; store package names are unique per program; root rows live only in `routes.odin`; feature tables are package-level `[?]T` (09 §4.4); `EXTS` stays on one line; never keep stream state in the temp arena; the `fmt` brace rule for JSON and HCON; live logs are `<div role="log">` of `<article>`; `x-impl` on runtime-switched axes; boosted links never cross a bundle; hyperscript data only in `data-*` |
| Families and switches | (formerly "Ports") the four families on the build line and what each holds; the chat-transport and bot-backend switches; the seams of §6.2 (notify by direct import, `store:audit`, topics named by string, domain imports, plain links), each with its reason |
| Public-repo hygiene | §5.3's rule: what stays git-ignored, and that LAN and host details go to `docs/private/SITE.md`, never to a public doc (ANSWERS F4) |

Every feature's `README.md` uses D4's fixed headings (What, Routes, Env, Data, Implementations, Limits, Tests,
Audited) and carries its audit stamp, `Audited: <commit> <date> <report>` (D39, §19); its Env table comes from
`bin --limits --json`. `docs/CATALOG.md` is generated from those READMEs. Docs the skeleton let drift (STRIP.md, the e2e
and load PLAN files, the docker-host backup advice; 01 risks) are rewritten or removed, not copied.

## 6. Composition: the feature contract, seams and implementation axes

Features plug together through per-package dispatch tables that each profile mounts, direct imports, a few hub topics
and plain links. Layers call each other directly, with no dependency injection (ANSWERS #1): which implementation runs
is a build flag or a `switch`, never a value handed in. Every piece is a closed table or an explicit call. This section
folds in `docs/design/LEAN-COMPOSITION.md` ("LC"), which replaces D5–D8's `Feature` struct, `register()` calls,
proc-field vtables and `platform/ports` with the simpler set Alex chose (ANSWERS round 3). The package shape is in §5;
profiles and the generator are in §7.

### 6.1 The feature contract

A feature plugs into a profile through its web package's tables, kept in one file next to its handlers: `ROUTES` (its
own rows and its switched implementations'), `TOPICS`, `JOBS` and the one-line `EXTS`, plus its `init`, `start` and
`drain` procs and, when it has a page, a `home_card` (LC §6, §8). Tables are package-level `[?]T`, because a slice
literal inside a proc points into that proc's stack frame (09 §4.4). A profile mounts each table, one line per package
in each host's table, and calls the procs from `main` (§7.2). There is no `Feature` struct, no `register()` call and no
`requires` (LC §14). `web.Route` stays, from D5 with RESOLUTIONS X30's handler types:

```odin
Route :: struct {
	method:   http.Method,
	pattern:  string,                     // Lua pattern inside the feature's prefix; route id = "<METHOD> <pattern>"
	handler:  proc(req: ^web.Request, res: ^web.Response),  // odin-http's types, re-exported by platform/web
	perm:     authz.Perm,                 // .Public = no check
	flags:    bit_set[web.Route_Flag],    // .Step_Up .Lan_Only .Private .Fragment .Stream .Frame_Games .Media .Nonce_Csp .Lab_Host
	body_cap: int,                        // 0 = MAX_BODY, 64 KiB (SK/app/src/controllers/middleware.odin:36)
}
```

**The rule** (LC §1). Which implementation runs is never a value passed around at run time. It is one of three things:
- **a family collection on the build line** (§6.4), when the choice keeps a C library off the linker or swaps a whole
  platform layer: the store, the identity, the client and the theme;
- **a hand-written `switch` over an enum, with a direct call in each case** (§6.4), when it varies per request: the
  chat transport and the bot backend;
- **an env value read at boot, then the same kind of switch**, when both members are pure Odin and one serves the
  whole process: the games catalog.

A proc value is stored in only two kinds of place: **dispatch tables** (route rows: URL → handler; topic rows: topic
family → subscriber; job rows: job id → run; and the profile's `HOME_CARDS` and `FIND_SOURCES`), as in the skeleton's
router; and **continuations** that name the caller's own next step (nbio completions, the writer task's commit, timers,
jobs, the bot's token sink). Both say *when* code runs, never *which* implementation runs.

**An example: chat** (LC §8; values from D13, D21, D24 and D30):

```odin
package chat_web                 // routes.odin

EXTS :: chat_transport_ws.EXTS + chat_transport_sse.EXTS + chat_transport_poll.EXTS + chat_transport_multipart.EXTS + bit_set[web.Ext]{.Pending, .Upsert, .Prompt, .Targets, .Download}
ROOM :: "chat.room"

ROUTES := [?]web.Route{
	{.Get,  "/chat",                  index,                          .Public,        {.Private},           0}, // the rooms, or the LAN notice
	{.Get,  "/chat/r/([%w-]+)",       room_page,                      .Chat_Read,     {.Private},           0},
	{.Post, "/chat/r/([%w-]+)",       post_message,                   .Chat_Post,     {},                   4096},
	{.Get,  "/chat/r/([%w-]+)/ws",    chat_transport_ws.stream,       .Chat_Read,     {.Stream},            0},
	{.Get,  "/chat/r/([%w-]+)/since", chat_transport_poll.since,      .Chat_Read,     {.Fragment},          0},
	{.Get,  "/chat/r/([%w-]+)/parts", chat_transport_multipart.parts, .Chat_Read,     {.Stream},            0},
	{.Get,  "/chat/m/(%d+)/menu",     message_menu,                   .Chat_Read,     {.Fragment},          0},
	{.Get,  "/admin/chat",            moderation,                     .Chat_Moderate, {.Private, .Step_Up}, 0},
}   // sse has no row: it rides /events

TOPICS := [?]hub.Topic{
	{ROOM,            .Queue,  256, true,  subscribe_room,   nil},           // perm, then keyset replay by rowid (D13)
	{"chat.presence", .Latest, 256, false, subscribe_member, nil},
	{"chat.typing",   .Latest, 64,  false, subscribe_member, nil},
	{"chat.reply",    .Queue,  64,  false, nil,              store_reply},   // the bot's room answers (§6.2)
}
```

The route ids are `"GET /chat/r/([%w-]+)"`, `"GET /chat/r/([%w-]+)/ws"` and so on; rows with `body_cap` 0 get
`MAX_BODY`, and the post keeps its own 4096. `front` checks `.Chat_Read` before reading any body (§17); `.Private` adds
`no-store`, `noindex, nofollow` and `hx-history="false"` (§12); `.Stream` marks the socket routes, and sse has no row
because it rides `/events`. `chat_web` imports all four transports for its switch (§6.4), so its table lists their rows
and its `EXTS` unions their extensions with what chat needs whatever the transport (RESOLUTIONS X29, as LC §12 recasts
it; §12.1). `chat.reply` carries the bot's answers back into a room (§6.2).

**As built (M2):** `features/chat/web` holds this table with `[%w%-]+` (a bare `-` after a class is Lua's lazy
quantifier, which `tools/check routes` refuses), the socket's handler named `chat_transport_ws.socket` (`stream` is the
platform package), and the post's cap 32 KiB: a 2,000-rune body URL-encoded runs to 24 KB, so 4096 refused long
non-ASCII ones. M2 adds `POST /chat/rooms`, `POST /chat/transport` (the Connection setting), `POST …/typing`,
`POST …/read`, `GET|POST /chat/m/<id>/edit` and `POST /chat/m/<id>/delete`; `/admin/chat` is M6's. `EXTS` is the
transports' plus upsert: hx-prompt and hx-download arrive with moderation and attachments (M6), and unread counts go out
of band on a class selector, which needs no hx-targets. The `TOPICS` rows use named fields: `chat.room` with
`persisted = chat.PERSISTED` (false in memory) and a keyset `replay` for M6; `chat.presence` and `chat.typing` `.Latest`,
keyed per member, presence with a `watch` (§9.2); `chat.reply` comes with the bot.

**Boot checks** (D5, recast for tables; LC §11). `app.check` runs them per host, after the `init` calls, and each
profile's `routes_test.odin` runs the same checks in CI under `CMD=test ./build.sh <p>`. Each is fatal with a message:
1. a duplicate route id `"<METHOD> <pattern>"` on one host, or a row with no handler;
2. a row whose prefix or flags need a perm (`/admin/*`, `.Step_Up`, `.Lan_Only`) but that declares `.Public`
   (RESOLUTIONS X4);
3. not exactly one root row (`GET /`) on a host;
4. the lab rules: a `.Lab_Host` row on a host where a cookie-setting identity runs (`accounts`, `envadmin` or `nick`);
   a row with any perm but `.Public` on a host with no identity; a second host whose env var is unset or names
   `SITE_URL`'s host (D5, D25; §7.3). `identity.SETS_COOKIE` is a constant, but the env is read at boot, so this check
   stays at boot;
5. a router key fed by two mounted tables on one host (**NEW**);
6. the `BUNDLE_EXTS` constant differs from the embedded bundle's `/* exts: … */` header ("run prepare"; D19);
7. a nav href with no GET route on its host;
8. a topic family mounted twice on a host, or a persisted topic with no `subscribe`; a job id mounted twice.

LC §16's prototype ran 1–4: a deliberately bad profile trips 1, 3 and 4 (8 problems at boot, 7 under `odin test`,
which sets two distinct origins). An unknown env var inside a known prefix is only a warning, given after the `init`
calls have recorded their rows. A perm listed twice for one role in `ROLE_PERMS` needs no check: a `bit_set` can't
hold a member twice, so it is a compile-time impossibility (X4). This is the skeleton's "drift fails loudly"
(`SK/tools/init/plan.odin:228-239`) applied to composition (RF §3.9).

**Static checks** (LC §11). What the binary can't tell, because it can't see which feature owns a profile row's
handler or which table a row came from (14 (3)), is `tools/check`'s, over `core:odin/parser` with no build: `profile`
(every feature package a profile imports is mounted, with its `init` called when it declares one; no `ROUTES` table
that no committed profile mounts; a `migrate` line for every SQLite store the build reaches), `routes` per host (each
row inside its feature's prefixes, no router key claimed by two features, exactly one root and none inside a package's
`ROUTES`), `topics`, `contracts`, `imports` and `exts` (§19.2.1). LC's 264-line prototype checker reported 0 problems
for `skeleton` and `full` and 6 for the bad profile; the orphan and migrate parts of `profile` are **NEW**.

**As built (M1):** `odin run tools/check -- all` runs `imports`, `profile`, `routes` and `contracts` over the tree
(`parity`, after both suites' runs, is separate); it reads each profile's families from its `build.sh` line and a
feature's prefix exceptions from a `## Prefixes` table in its README (`| `/data` | why |`, a reason required; the
platform's in `app/platform/web/README.md`). `platform/app` imports `store:.` besides `identity:.`: the family's root
package holds its `NAME` for `--features`. Its test runs every check on the repo (clean) and on
`tools/check/testdata/bad`, a repo-shaped tree that trips each one (30 problems). `topics` and `exts` arrive with M2.
**As built (M2):** both are in `all`. `topics` reads each TOPICS row's family (`family = …`, or first when positional):
its feature's (`lab.feed` is lab's) and declared once; every package a host mounts that declares TOPICS is named by
the profile's `hub.mount` for that host and nothing it doesn't mount is; a profile with topics calls `hub.init`; and
every `hub.publish` with a literal topic names a declared family. `exts`: every mounted web package declares `EXTS`,
and main's `BUNDLE_EXTS` and `PAGE_BUNDLES` name exactly the mounted packages with `EXTS` or `BUNDLES` (the handler of
a profile's own row, as minimal's root, counts as mounted). `routes` also refuses a bare `-` after a literal character
in a pattern, Lua's lazy quantifier (`/csp-report` matched nothing until it was `/csp%-report`). The bad fixture trips
43 problems.

**Derived, never declared twice** (D5; LC §11): `robots.txt` Disallow lines from `.Fragment` rows (the literal prefix up
to the first pattern character; as built in M1, a prefix another line already covers is dropped and two or more rows
under one first segment collapse to it, `/ui/modal`, `/ui/drawer`, … → `/ui/`, which reproduces the skeleton's
hand-written list) and the sitemap from `NAV`, both per host (`SK/CLAUDE.md` "Crawlers / SEO");
`rbac.spec` from the mounted rows, every route × both hosts in `full` (§17); route coverage from route ids per host
(§19); the CSP and cache class from the flags (§12); the htmx-config allowlist from the bundle's extensions (§12);
dependencies from import lines and the compiler's package list (09 §4.6; §12.1); the README env tables from
`bin --limits --json`.

### 6.2 Seams between features

Features meet only through five kinds of seam, each justified in CLAUDE.md (D6, D45; LC §9).

**1. Domain imports for hard dependencies**: dashboard → contacts; video → uploads. The import lines are the
dependency graph (09 §4.6); the compiler refuses cycles (09 §4.4), and the generator closes a selection over them
(§7.4).

**2. `notify_web`, the one web-to-web import.** Every producer (chat, lists, calendar, polls, guestbook, bot, jobs;
§14.2) imports `notify_web` and calls `notify_web.send(user, kind, ref, html)`, which stores the item through notify's
domain and publishes the bell on `notify.user:<uid>` (D4 keeps publishes in web). So notify is a hard dependency of each
producer, the generator closes a selection over it, and `tools/check imports` allows no other web-to-web edge. `kind`
is a namespaced string (`"chat.mention"`), so notify never names a producer's kinds; mutes per kind keep the same
strings.

**3. `store:audit`.** A package that audits does `import audit_store "store:audit"` and calls
`audit_store.append(actor, action, target, reason, meta)`. The SQLite family writes an `audit_log` row, the memory
family one `mod=audit` log line (LC §16 ran both). It is the one store any domain, web or identity package may import:
an append-only log has no rules for a domain to add. The `audit` feature's page, `/admin/audit`, reads through audit's
domain and is mounted only in SQLite profiles (§17.7).

**4. Hub topics named by string**, for genuine broadcasts (D13) and for the bot's room mode. Room mode runs over two
static topic rows, one each way: `bot.ask`, consumed by bot, and `chat.reply`, consumed by chat, which stores the
answer as a chat message. That is what ANSWERS round 3's "a hub topic with a static `TOPICS` row" needs in practice,
and RESOLUTIONS X37 settles it so: neither feature imports the other, and each works alone. `chat_web` publishes a
message that mentions the bot on `bot.ask:<room>`, by name. `bot_web.TOPICS`
holds the row `{"bot.ask", .Queue, 64, false, nil, room_ask}`, whose `deliver` proc the hub runs once per publish, as
the router runs a route's handler (§9.2). `room_ask` starts the backend and streams upserts of `#m-<id>` to
`chat.room:<room>`; the finished answer goes back on `chat.reply:<room>`, chat's own row, which stores it as a message
from the bot and publishes the persisted bubble. Without bot nothing mounts `bot.ask`, so the publish reaches no row
and is dropped and counted; `tools/check topics` requires every family a package publishes to by literal name to be
declared by some package, so a typo fails CI (**NEW**: the `deliver` field and that check are not prototyped). A
subscription made in `main` at run time would be the observer pattern (14 (5)); a static row is a dispatch table.

**5. Plain links for UI composition**: "Invite crew" on a game page links to `/chat/r/<slug>?draft=<text>`, with no
code coupling (D34); `/admin/modules` links to `/admin/bot`, where bot owns its default switch (§15.4).

**Tables in the profile.** The Today page's cards and find's sources are `HOME_CARDS` and `FIND_SOURCES` in the
profile's `main` (§7.2), handed to `home_web.init` and `find_web.init`, which call each row in order and import no
other feature. The nav is `NAV` (and `LAB_NAV`) in `brand.odin`. Health, limits and numbers are pushed to
`platform/obs`, which `status`, `modules` and `/readyz` read with `platform/env` and the mounted tables (§10.4).
Scheduled work is each package's `JOBS` table, which `platform/workers` runs (§15.4).

**Deliberately absent** (D6):
- **Open plugin registries.** There is no `Admin_Panel`, `Probe` or `Notifier` list and no `On_User_Deleted` hook
  (CF §4.3 proposed eleven registries). A consumer makes one direct call or reads one table in the profile.
- **Foreign keys across features.** A feature stores user ids as plain integers plus an `author_name` snapshot taken
  at write time. Names change rarely, and rolling retention ages old snapshots out.
- **Cascades on account deletion.** Deleting an account is a soft disable that keeps the row, so nothing cascades
  across features and no deletion hook is needed.

Why: optional features compose without a dependency graph between them (RF §3.1), any combination migrates (CF §4.2),
and foreign keys into `users` from other features would make cascades break optional accounts (RF §7.1, rejected).

### 6.3 Prefix ownership

This is D9's ownership rule, now per host. The router mechanics (a prefix map per host, longest key first, Lua
patterns inside a feature, the costs) are in §8.

A feature owns `/<name>`, `/admin/<name>` and `/api/<name>`; the last two are two-segment router keys. Admin pages
follow it: `/admin/accounts`, `/admin/audit`, `/admin/bot`, `/admin/ops`, `/admin/jobs`, `/admin/modules`,
`/admin/dbview`, `/admin/term`. Exceptions are listed, with the reason, in the owning feature's README:

| Owner | Prefixes | Reason |
|---|---|---|
| each host's root row | `/` | written in the profile's `routes.odin`, never in a package's `ROUTES`; exactly one per host (RESOLUTIONS X5; LC §7) |
| `accounts` | `/login /logout /register /invite /account` | conventional URLs |
| `video` | `/media` | content-addressed files |
| the skeleton features (`dashboard`, `gallery`, `contacts`, `about`) | the skeleton's exact URLs: `/ui/ping` (dashboard, whose page is also `skeleton`'s root, and sits at `/dashboard`, its own prefix, on `full`'s lab host), `/data /contacts /search /api/search /components /forms /ui /validate /about` (`SK/app/src/routes.odin`) | parity needs them byte-identical (§18) |
| the platform | `web.ROUTES` on a site's main host: `/healthz /livez /readyz /metrics /sitemap.xml /BingSiteAuth.xml /<indexnow-key>.txt`; `hub.ROUTES` (`/events`) on every host that mounts topics (M2); `web.PUBLIC_ROUTES` on every host: `/static /robots.txt /favicon.ico /licenses`; `web.REPORT_ROUTES` (`/csp-report`) where the profile asks for CSP reports | shared by every profile (LC §7) |

**One root per host** (D9, D27; RESOLUTIONS X5, X28; LC §7). Each host's table has exactly one `GET /` row, written in
the profile's `routes.odin`, never in a package's `ROUTES`, so one package's page can sit at `/` in one profile and
elsewhere in another. The root is `home` in `minimal`, `streams` and on Houston's main host, `dashboard` in `skeleton`,
and `landing` in `lab` and on houston-lab. D9's "home, dashboard and landing are mutually exclusive" becomes "one root
per host": the generator refuses two roots on one host, boot counts the roots per host (§6.1 check 3), and
`tools/check routes` refuses a root row inside a package's table. In `skeleton` the dashboard's page is the root row
and keeps the skeleton's `/` (`SK/app/src/routes.odin:35`), on which D38's `/` 0.18 ms budget rests, with `/ui/ping`,
while gallery owns the rest of `/ui` (longest key first, D9). On `full`'s lab host the same `dashboard_web.page` sits
at `/dashboard`, inside dashboard's own prefix (LC §16). The skeleton's dashboard stays byte-identical, so it shows no
home cards; they appear only where `home` is the root.

**Ownership is per host, and static** (LC §7, §12). Each host has its own prefix map, and on one host a router key
belongs to one feature. The prefix rule itself is per feature, so it reads the same on every host: `/chat` is chat's
wherever it is mounted, and one package may be mounted on both hosts (the platform's public rows are). `tools/check
routes` checks ownership per host, and boot refuses a router key fed by two mounted tables on one host (§6.1 check 5).
Which feature may claim a prefix is the static check's alone, since the binary can't tell which feature a profile
row's handler belongs to (14 (3)); a build that skipped CI could boot with a row outside its feature's prefixes.

Global search is the **`find`** feature at `/find`, because the skeleton's `/search` is the contacts active-search
fragment (`SK/app/src/routes.odin:42`) that the k6 search scenario hits. Product names (Comms, Capcom, Logbook …) are
nav labels from `brand.odin`, never prefixes. Rejected: the branded prefixes `/capcom`, `/log` and `/control/console`,
and a global search at `/search` that collides with contacts (PF §4.2, CF §4.4; D9).

### 6.4 Implementation axes

The axes, from D8 with RESOLUTIONS X9 and X13 applied, chosen by LC §3–§4's mechanism (ANSWERS round 3):

| Axis | Implementations | Chosen | How |
|---|---|---|---|
| Store per feature (notes, chat, notify, polls, lists, calendar, guestbook, jobs, audit, bot conversations; uploads' session rows, RESOLUTIONS X13) | the SQLite and memory families, `app/stores/{sqlite,memory}/<f>/` | build: one family per build | `-collection:store=…` on the build line; the domain imports `store:<f>` |
| Identity | `accounts` (SQLite), `envadmin` (one env-provisioned admin, signed cookie), `nick` (signed nickname cookie, role User), `anonymous` (the default) | build | `-collection:identity=…`; `front` calls `identity.load_viewer` (contract `authz.Load_Viewer`) |
| Client behaviours | `client/hyperscript`, `client/vanilla` | build, one per profile | `-collection:client=…`, read by `platform/html` |
| Theme | `theme/full` (6 styles × 24 schemes), `theme/lite` (one style, two schemes) | build | `-collection:theme=…`, read by `platform/html` |
| Search per feature | FTS5 in the SQLite stores, a `contains_ci` scan in the memory stores | follows the store family | — |
| Video catalog; wiki source | `catalog_file` or the SQLite library; `source_files` (read-only) or the SQLite wiki (editable) | follow the store family | each store's `IMPL` names it (§2.8) |
| Games catalog | `catalog_static`, `catalog_api` | per process: `api` when `GAMES_API_URL` is set, `static` otherwise (`GAMES_CATALOG` still overrides the static JSON) | `games_web` reads it at `init`, then a `switch`; both pure Odin |
| Terminal mode | line, PTY | per device row | a column of the row, switched in `term_web` |
| **Chat transport** | `transport_ws`, `transport_sse`, `transport_poll`, `transport_multipart` | **per request**: the user's preference (Houston: `accounts_prefs`, read from the `Viewer`; elsewhere a cookie), `?transport=` in tests, default `CHAT_TRANSPORT` | one hand-written `switch` in `chat_web`; every chat profile links and ships all four |
| **Bot delivery** | POST → SSE, POST → multipart, room (over `bot.ask` and `chat.reply`, §6.2) | **per request** (a form choice): the same backend stream rendered for another transport | a local `switch` in `bot_web` |
| **Ops refresh** | SSE push, ptag poll, multipart slow panels | **per request** (`?mode=`) | a local `switch` in `ops_web` |
| **Bot backend** | `backend_mock`, `backend_llama` | **per request** among the healthy ones: guests always get mock; members choose when both are healthy; the default is `BOT_BACKEND`, which an admin can change at run time on `/admin/bot` (in memory only, audited, reset on restart) | one `switch` in `bot_web`; both linked (llama's client is `platform/stream/client`, pure Odin) |

**The chat switch** sits next to the routes in `chat_web`, which imports all four transports (LC §4):

```odin
package chat_web                 // transports.odin

import "core:strings"
import chat_transport_multipart "../transport_multipart"
import chat_transport_poll      "../transport_poll"
import chat_transport_sse       "../transport_sse"
import chat_transport_ws        "../transport_ws"

Transport :: enum u8 {Ws, Sse, Poll, Multipart}

pane :: proc(t: Transport, b: ^strings.Builder, slug: string) {
	switch t {
	case .Ws:        chat_transport_ws.pane(b, slug)
	case .Sse:       chat_transport_sse.pane(b, slug)
	case .Poll:      chat_transport_poll.pane(b, slug)
	case .Multipart: chat_transport_multipart.pane(b, slug)
	}
}
// from_name(s) and name(t) the same way, over each package's NAME.
```

The bot's is the same shape: `Backend :: enum u8 {Mock, Llama}`, with `health`, `start` and `cancel` switches, and the
token sink stays a continuation (§14.3).

**Cost of the switch** (14 (2)). Over 200M calls at `-o:speed`, an enum plus a switch costs 1.53–1.56 ns per call with
the same transport every time and 6.31–6.62 ns for a random mix of four, against 1.33–1.38 and 5.20–5.39 ns for the
proc-field table it replaces and 1.09–1.11 ns for a direct call. That is 0.2–1.2 ns more than a table, against
0.5–15 µs for a store call or a socket write, and the IR holds four direct calls and no indirect one.

**Store contracts are typed constants** (LC §3, §8). Each feature's `models` package declares its store's proc types,
and each store, in either family, checks its procs against them in its own `contract.odin`:

```odin
package chat_models

import "../../../platform/store"

Message :: struct {id, room, author, mention: u64, author_name, body, body_html: string, at: i64}
Room    :: struct {id: u64, slug, title: string, kind: Room_Kind}
Error   :: store.Error   // .None .Not_Found .Constraint .Failed

// The store contract; each store, in either family, checks its procs against these in contract.odin.
Store_Recent :: proc(room, before: u64, limit: int, out: ^[dynamic]Message) -> Error
Store_Insert :: proc(m: ^Message) -> Error
Store_Search :: proc(rooms: []u64, q: string, limit: int, out: ^[dynamic]Message) -> Error
```

```odin
package chat_store_sqlite        // contract.odin: a drifted signature fails here, built or not

import m "../../../features/chat/models"

_ : m.Store_Recent : recent
_ : m.Store_Insert : insert
_ : m.Store_Search : search
```

A drifted store fails in its own package, built or not: "Cannot assign 'insert' of type 'proc(^Message, u64) -> Error'
to 'Store_Insert'" (LC §16). `#assert(type_of(insert) == T)` can't do this job: it is false even for an exact match
(14 (1), 14 critic). Stores import no collection, so CI checks every store of both families on its own, and a store
that no profile builds can't rot (§20.1).

**The switching rule** (D8, unchanged). Per-request switching exists only on transport axes (how the same content
travels) and on the bot backend, the axes that are the showcase's point. Everything else is fixed by the profile's
build line and imports, or at boot by env for the games catalog. Every response from a feature with a runtime-switched
axis carries a header such as `x-impl: chat.transport=sse`, and its access-log line carries `impl=`, so what served a
request is always visible (D8).

**Coexisting implementations.** Implementations never import each other, so shared code lives in the domain or in
`models` (D4). Every store passes its feature's `storetest` conformance suite, which imports both stores into one test
binary (their package names are unique, LC §3), and every runtime-switched implementation runs the same e2e spec file,
parameterised and tagged (`@chat-ws` …; D37, §19). Rejected (D8): per-request cookie switching on every runtime axis,
with switches persisted in `app_settings` (CF §4.5), and a boot switch that embeds both client runtimes in `full`
(RF §4.2).

**Costs, plainly** (LC §12):
1. **Build-flag plumbing.** Bare `odin build app/cmd/<p>` no longer works: it needs four flags, and Odin has no
   response files (14 (1)), so they live in `build.{sh,bat}`, which every script, CI job, the Dockerfile and the
   generator call (§7.2). spark already builds with a collection flag (09 §4.3). 09 §5's flag-free build is overturned.
2. **The editor sees one member per family**, `full`'s (`ols.json`, §2.5); following a call into another member means
   switching one line. Not tried in an editor: **UNVERIFIED (M1)**.
3. **Fewer packages check alone.** Domains, views, web packages, switched implementations, identities, `platform/html`
   and `platform/app` need a profile's flags; stores and platform L1–L2 check alone (§20.1).
4. **One store family per build.** A profile can't put chat in SQLite and notes in memory, as D8 allowed; no hosted
   profile wants that (§7.1).
5. **Every chat profile ships all four transports** (X29's "a poll-only chat ships no ws" goes): ws, sse, hx-multipart
   and ptag are in every chat bundle and binary. As built (M2), their four files are 28,965 B raw and 8,217 B br alone
   (hx-multipart 13,892/4,549, hx-ws 8,515/2,623, hx-sse 6,225/2,257, ptag 333/194), of `streams`' Main at 68,186 B raw
   and 19,967 B br.
6. **Both bot backends and both games catalogs are linked** wherever their feature is; all four are pure Odin.
7. **Notify comes with every producer**, so chat's hello world gains the bell (§7.5).
8. **The generator edits hand-written files** (§7.4): a profile reshaped beyond the expected shape makes it stop and
   name the file. CI checks consistency, not bytes, so a hand edit that keeps the profile consistent passes, and one
   that leaves a package unmounted fails.
9. **Ownership is static** (§6.3).
10. **Two hosts share one process and one SQLite file** (§7.3): a crash in a demo page is a crash of Houston's process,
    which the crash model contains as it contains any other (D15). This is F2's one-binary, two-origins choice,
    unchanged.
11. **Effort is about neutral** (**NEW**, an estimate, not a measurement): there is no emitter for profile files and no
    alias layer, but the generator learns parse-based edits, and `tools/check` gains `profile`, per-host `routes` and
    `contracts`.

The four flags cost nothing measurable in time: `streams` and `full` check in 138 ms (best of 5) and build in 277 and
281 ms (best of 3), in line with 14 (1)'s one-collection program (LC §16).

### 6.5 Why this is not a framework in disguise

Every table is closed and written by hand: the `Ext`, `Route_Flag`, `Perm` and `Behaviour` enums, each package's
`ROUTES`, `TOPICS`, `JOBS` and `EXTS`, and each profile's host tables, `HOME_CARDS` and `FIND_SOURCES`. Nothing
registers itself (`@(init)` procs are contextless and limited to static storage, 09 §4.1, §4.3), nothing scans for
features at run time, and nothing hands a feature its implementation (§6.1's rule). Selection never hides in
`-define`: it is only for `VERSION`, `TEST_ROUTES` and `PROFILE`, since false `when` branches are never type-checked
(09 §4.3; D10; 14 (4)); the families are four flags on one line of `build.*`, and the rest is import lines. Compiled
features are never disabled at run time (Q28). The composing code (`Route`, `app.Host`, the boot checks,
`tools/check profile`, the derivations) is meant to stay smaller than any one feature, the philosophy judge's test (D6).

**The reading test** (LC §2). A reader starts in `app/cmd/<p>/routes.odin` and follows a request to its SQL with
go-to-definition alone. Once the router has matched the row, every hop is a qualified name, and nothing is looked up at
run time:

```
app/cmd/full/routes.odin              chat_web.ROUTES[:]                        (in MAIN_ROUTES)
 → app/features/chat/web/routes.odin  {.Get, "/chat/r/([%w-]+)", room_page, …}
 → chat_web.room_page                 chat.room_view(v, slug, &msgs)
 → chat.room_view                     chat_store.recent(room.id, …)              import chat_store "store:chat"
 → app/stores/sqlite/chat/store.odin  chat_store_sqlite.recent → SQL_RECENT
```

These are the skeleton's hops (route → controller → service → repository → SQL), with none added: the domain's import
lands straight on the store package, with no alias in between. With `ols.json` pinned to the SQLite family the last hop
opens the SQLite store; a memory profile's is the same path with `memory` in it, and the compiler's own dependency list
for that build names only that family (LC §16).

**Rejected** (LC §13): a `sel:` collection per profile with generated alias packages (LC's first version: a hop per
aliased call, 14–30 generated files per profile, and aliases can't name a package variable, 14 (1c)); generated
per-profile dispatchers for the transports and the bot backend; a `SELECTION` mini-language with generated `main.odin`
and `routes.odin` and D7's `--emit --like` byte check; null-object seam packages; generated fan-outs for the home
cards, find sources and lifecycle; a collection per axis per feature (14 (1)); `when` + `#config` with every
implementation imported (14 (4)); one flat route literal per profile, which repeats every row in every profile that
mounts it; root rows inside a package's `ROUTES`; the `.Lab_Host` gate as a host filter in `front`; a run-time
`hub.subscribe` in `main` for room mode (14 (5)); a build-time choice for the games catalog and the bot backend; the
bot default on `/admin/modules`; and `STORE=sqlite|memory` at boot (D8, D10), since no build links both families.

## 7. Profiles, hosting units and the generator

This section covers what gets built (six profiles), where each one runs (its own container and subdomain), and how a
fork gets its own selection (the generator). The feature contract they compose is §6.

### 7.1 Profile catalog

| Profile | Features (beyond platform) | Store | Identity / client / theme | Transports | Bundle (derived) | CSP | Purpose | Host |
|---|---|---|---|---|---|---|---|---|
| `minimal` | home, notes, about | memory only | anonymous / vanilla / lite | none | `htmx.min.js` byte-identical | the skeleton's header set exactly | the smallest hello world; no SQLite library; ≤ 1.5 MiB | `starter-minimal` |
| `skeleton` | dashboard, gallery, contacts, about | SQLite v3; `:memory:` per D17 | anonymous / vanilla (the skeleton's app.js behaviours) / full | none | `htmx.min.js` byte-identical | base | the S18 witness and the skeleton's 40-item checklist (01 (A)) | `odin-htmx.alexh95.com` (Fly, from the M3 exit); `starter-skeleton` (LAN only) |
| `streams` | home, notes, chat (4 transports), notify, bot (mock by default), ops, status, about | memory only | nick (posting only from `LAN_CIDRS` by default) / vanilla / lite | SSE, WS, multipart, poll | Main: htmx + sse, ws, hx-multipart, upsert, hx-pending, ptag, hx-targets, download, hx-prompt, browser-indicator | base | the stream substrate without SQLite, so stream regressions are attributable | `starter-streams` |
| `full` (Houston) | every catalog feature (ANSWERS round 3): Houston's (D29) on its main host; on its lab host `landing` (the root), `notes`, the skeleton's `dashboard` (at `/dashboard`), `gallery`, `contacts` and `about`, `lab`, `scripting` and `compat` (§7.3) | SQLite file | accounts on the main host, none on the lab host / hyperscript / full | all, plus Range and the agent WS | Main (13 extensions) + hyperscript; on the lab host also Scripting + Compat_Htmx2 + Compat_Alpine | base + flags; nonce on the lab host's `/scripting/*` | the showcase, implementing every catalog feature itself | `houston.alexh95.com`; `houston-lab.alexh95.com` (session-free) |
| `lab` | landing, status (witness board), wiki (the memory store, `source_files`: the starter's docs; from M8), scripting, compat, lab, about | memory only | anonymous / hyperscript / full | SSE, WS, multipart (contract pages) | Main + Scripting + Compat_Htmx2 + Compat_Alpine | base; nonce on `/scripting/*` | the starter's own page, the witness board and the four lab-only extensions, on an origin with no sessions; an independent witness (§2.3) | `odin-htmx-starter.alexh95.com` |
| `full-vanilla` (CI only) | as `full`: `app/cmd/full` built with `client=vanilla`, with no directory of its own, so the two can't drift apart (LC §3, §6). Its lab host's `/scripting/live` builds one widget in hyperscript, which is inert under the vanilla client; `lab` and `full` cover it (**NEW**; this plan first left `scripting` and `compat` out of `full-vanilla` for that widget) | SQLite | accounts / vanilla / full | all | Main; on the lab host as in `full` | base | the second client implementation: core and twinned-behaviour specs on the main host (D22) | CI |

The bundle column is derived, never declared: each list is the union of the `EXTS` of every package the build reaches,
read from the compiler's own package list (D19, D24; RESOLUTIONS X29; §12.1). Each host has exactly one root: `home` in
`minimal`, `streams` and on Houston, `dashboard` in `skeleton`, `landing` in `lab` and on houston-lab (RESOLUTIONS X5;
§6.3). Every hosted profile is all-SQLite or all-memory, so one store family per build costs none of them anything
(LC §3).

**As built (M2):** `streams` mounts home, notes, chat, notify, bot, ops, status, the nick identity's `/login` and `/logout` (`{"accounts",
identity.ROUTES[:]}`, its host's `identity` flag on) and about, as the catalog row above lists them. Its
Main bundle is what those packages' `EXTS` name: htmx with sse, ws, hx-multipart, ptag, hx-pending and upsert. `tools/check`
reads a profile's `identity:.`, `store:` and other family imports as `build.sh`'s line builds them.

`cmd/term-agent` (linux_arm64, the Raspberry Pi agent, §16) is not a profile. CI also builds generated selections as
throwaway profiles (§7.4). `full` (and with it `full-vanilla`) and `lab` grow milestone by milestone: each slice adds
its package's lines to the profiles that mount it (its imports and calls in `main.odin`, a mount line per host table in
`routes.odin`) when the slice lands, so no profile ever imports a package that doesn't exist yet (D24, D44; §22).

### 7.2 The profile's four files

Each profile is `app/cmd/<profile>/` with four hand-written files, as `SK/app/src/main.odin` and
`SK/app/src/routes.odin` are (D7; LC §6): `brand.odin` (`BRAND`, the nav per host, the copy), `routes.odin` (the host
tables), `main.odin` (the boot sequence as plain calls) and `routes_test.odin` (the boot checks under `odin test`). The
generator writes them for a new project and edits them when a feature is added or removed (§7.4), and CI checks that
they agree (`tools/check profile`, §6.1; §20.1). This replaces D7's first composition root: there are no `register()`
calls, no implementation values and no options literals, and CI no longer compares a regenerated `main.odin` byte for
byte. Rejected: CF §4.6's `profiles.odin` table (a second definition of each profile), `#config`/`when` feature flags
(false branches are never type-checked, 09 §4.3), and generated profile files (LC §13).

**The build line** is spelled in one place, `build.{sh,bat} <profile>` at the repo root, and every path on it is
relative to the repo root (LC §3):

```sh
# build.sh <profile> [odin flags…]: the only place the family flags live. CMD=check|test|run (default build).
case "$p" in
  minimal)      store=memory id=platform/authz/anonymous            client=vanilla     theme=lite ;;
  skeleton)     store=sqlite id=platform/authz/anonymous            client=vanilla     theme=full ;;
  streams)      store=memory id=features/accounts/identity_nick     client=vanilla     theme=lite ;;
  full)         store=sqlite id=features/accounts/identity_accounts client=hyperscript theme=full ;;
  full-vanilla) store=sqlite id=features/accounts/identity_accounts client=vanilla     theme=full  src=full ;;
  lab)          store=memory id=platform/authz/anonymous            client=hyperscript theme=full ;;
esac
exec odin "${CMD:-build}" "app/cmd/${src:-$p}" \
  -collection:store=app/stores/$store -collection:identity=app/$id \
  -collection:client=app/platform/client/$client -collection:theme=app/platform/theme/$theme \
  -vet -vet-cast -vet-semicolon -vet-tabs -vet-using-param -disallow-do -strict-style -warnings-as-errors "$@"
```

`run.*`, `prepare.*`, CI, the Dockerfile, the e2e global setup, `load-tests/run.sh`, `tools/watch` and `tools/init
--verify` all call it. Without the flags the compiler names each missing collection, "Syntax Error: Unknown library
collection: 'store'" (and `'client'`, `'identity'`, `'theme'`; LC §16). `full-vanilla` has no directory of its own: it
is `app/cmd/full` built with the vanilla client (§7.1). `ols.json`, beside it at the root, pins the editor's four
collections to `full`'s members, because OLS's `collections` are top-level and a profile can't remap one (14 (1)).

**`routes.odin`** mounts one line per package in each host's table, and writes the profile's own rows: the root, and
any page the profile places outside its package's table. From `streams`, which has one host:

```odin
package main

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import "../../platform/workers"
import identity "identity:."
import chat_web "../../features/chat/web"
import home_web "../../features/home/web"
// … the other web packages

// The skeleton's src/routes.odin, as one line per mounted package plus the profile's own rows.
ROUTES := [?]app.Mount{
	{"platform", web.ROUTES[:]},                                    // the main host's: /healthz /livez /readyz /metrics /sitemap.xml …
	{"platform", web.PUBLIC_ROUTES[:]},                             // every host's: /static /robots.txt /favicon.ico /licenses
	{"platform", web.REPORT_ROUTES[:]},                             // /csp-report
	{"platform", hub.ROUTES[:]},                                    // /events: this host's TOPICS (M2)
	{"home", {{.Get, "/", home_web.page_today, .Public, {}, 0}}},  // the root: Today
	{"identity", identity.ROUTES[:]},                               // /login /logout: the nickname form
	{"notes", notes_web.ROUTES[:]},                                 // /notes
	{"chat", chat_web.ROUTES[:]},                                   // /chat, the room page, post, the transports' rows, /admin/chat
	{"notify", notify_web.ROUTES[:]},                               // /notify
	{"bot", bot_web.ROUTES[:]},                                     // /bot, /admin/bot
	{"ops", ops_web.ROUTES[:]},                                     // /admin/ops
	{"status", status_web.ROUTES[:]},                               // /status
	{"about", about_web.ROUTES[:]},                                 // /about
}

// Subscribable topics, mounted per host by main's hub.mount("main", ..TOPICS[:]): a subscription to
// chat.room:12 runs that row as a GET runs a route's handler (its perm, its allow, then the keyset replay by
// rowid, D13).
TOPICS := [?][]hub.Topic{
	home_web.TOPICS[:],     // home.presence
	chat_web.TOPICS[:],     // chat.room, chat.presence, chat.typing, chat.reply
	notify_web.TOPICS[:],   // notify.user
	bot_web.TOPICS[:],      // bot.health, bot.ask
	ops_web.TOPICS[:],      // ops.panel
}

// One host. The third field says front runs the identity here (nick, which sets a cookie).
HOSTS := [?]app.Host{{"main", "SITE_URL", true, ROUTES[:], NAV[:]}}

// Scheduled jobs: platform/workers runs each row on its schedule; the jobs feature's "run now" looks a row up
// by its id, as the router looks up a route.
JOBS := [?][]workers.Job{
	notify_web.JOBS[:],     // notify.prune: read notifications after 30 days (D36)
	chat_web.JOBS[:],       // chat.retention
}
```

- **Tables are package-level**, because a slice literal inside a proc points into its frame (09 §4.4). Mounting another
  package's table, `chat_web.ROUTES[:]`, and writing the profile's own rows inline, `{{.Get, "/", …}}`, both compile
  under `-vet -strict-style` and run (14 (3) variant B; LC §16).
- **`app.Host`** is `{name, site_env, identity, routes, nav}`: the host's log and metrics label, the env var that
  names its origin, whether `front` runs the identity there, its routes and its nav. The prototype's host held the
  routes only; nav per host is **NEW**. **Topics per host** (**NEW**) are mounted by `main` with
  `hub.mount("<host>", ..TOPICS[:])` after `hub.init()`, beside a `{"platform", hub.ROUTES[:]}` line (`/events`) in
  that host's routes, not through `app.Host` (as built, M2): `platform/app` then never calls the hub, so a profile
  that doesn't stream links none of it (the skeleton's binary sat at its 2.75 MiB budget to the byte; 3 MiB since M2,
  ANSWERS round 10).
- **`app.Mount`** is `{feature, rows}` (M1): a mounted table says whose it is. `bin --features` lists the features
  from the mounts (with the build's family members: profile, store, identity, client, theme), `bin --routes` prints
  each row's feature, and the test suites choose their specs from that list (§19.1.2). The profile's own inline rows
  name the feature whose handler they mount (`{"dashboard", {{.Get, "/", dashboard_web.page, …}}}` in `skeleton`).
- **Boot keys every row by prefix** (D9), per host, so order here matters only inside a prefix. `bin --routes` prints
  the flat table of each host.

**`main.odin`** is the boot sequence as plain calls, as `SK/app/src/main.odin` is. From `full`:

```odin
package main

import "../../platform/app"
import "../../platform/html"
import "../../platform/store"
import store_sqlite "../../platform/store/sqlite"
import identity "identity:."
import accounts_store "store:accounts"
import audit_store "store:audit"
import chat_store "store:chat"
import notify_store "store:notify"
// … one store import per SQLite-backed feature, for its MIGRATIONS
import "../../features/chat"
import "../../features/wiki"
import bot_web "../../features/bot/web"
import chat_web "../../features/chat/web"
// … the other web packages

// The Today page's cards in order, and find's sources: dispatch tables, the same kind as ROUTES.
HOME_CARDS := [?]html.Home_Card{chat_web.home_card, bot_web.home_card, video_web.home_card, lists_web.home_card, status_web.home_card}
FIND_SOURCES := [?]store.Find_Source{{"chat", chat.search}, {"wiki", wiki.search}, {"lists", lists.search}, {"calendar", calendar.search}}

// Every extension the main bundle needs (D19). Boot refuses a bundle whose /* exts: */ header differs.
BUNDLE_EXTS :: chat_web.EXTS + notify_web.EXTS + bot_web.EXTS + ops_web.EXTS + lists_web.EXTS + video_web.EXTS // + …

main :: proc() {
	app.boot("full")                       // §8.6 steps 1–3: --healthcheck and --worker, NOFILE, logger, the platform env
	identity.cli()                         // --hash-password: accounts checks an argon2id hash

	// Each reads its own env rows and declares its limits to obs. Nothing starts yet. notify before its producers.
	notify_web.init()
	chat_web.init()
	bot_web.init()
	// …
	home_web.init(HOME_CARDS[:])
	find_web.init(FIND_SOURCES[:])
	hub.init()                             // the hub's and the streams' env rows (M2)
	hub.mount("main", ..MAIN_TOPICS[:])    // each host's topic tables
	hub.mount("lab", ..LAB_TOPICS[:])
	app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS)   // step 4: the boot checks (§6.1); --features, --routes, --limits answer here

	store_sqlite.open()                    // step 5: --backup and --adopt-profile, then DB_PATH and MEMMODE (§11)
	store_sqlite.migrate("accounts", accounts_store.MIGRATIONS[:])   // dependency order (§11.7)
	store_sqlite.migrate("audit",    audit_store.MIGRATIONS[:])
	store_sqlite.migrate("notify",   notify_store.MIGRATIONS[:])
	store_sqlite.migrate("chat",     chat_store.MIGRATIONS[:])
	// … one line per SQLite-backed store this build reaches; rows of features not migrated here stay, dormant

	app.serve(HOSTS[:], JOBS[:], &BRAND)   // steps 6–10: seed, assets, bind, loops, banner; returns once the loops run
	ops_web.start()                        // the 1 Hz panel publisher
	bot_web.start()                        // the llama health probe

	app.wait()                             // §8.7 steps 1–2: the signal; /readyz answers 503, the accept op goes
	chat_web.drain()                       // step 3: each closes its own streams (WS 1012, SSE retry:, multipart's last boundary)
	bot_web.drain()                        // cancel generations
	term_web.drain()                       // tell terminal sessions
	app.shutdown()                         // steps 4–6 under their deadlines: idle peers, active requests, timers, pools
	store_sqlite.close()                   // step 7: the writer's last batch, then the WAL checkpoint
	app.exit()                             // steps 7–8: flush the logs, exit 0, or 70 after a dirty crash
}
```

- **Migrations** are one call per store in dependency order, not one slice literal of pairs: the runner never holds a
  literal that points into `main`'s frame (09 §4.4). A memory profile's `main` has no `store_sqlite` import at all, and
  a `migrate` line left in one doesn't compile, since memory stores declare no `MIGRATIONS` (§11.7).
- **The lifecycle is in `main`.** `start` runs once `app.serve` has the loops running (§8.6 step 9), and the `drain`
  calls sit between the signal and the platform's deadlines (§8.7 step 3), in the order written. The platform keeps the
  deadlines; `main` shows who drains what. The store closes in `main` too, after the loops have stopped and before
  `app.exit`, because only `main` knows whether the build has a SQLite store: a memory profile has no
  `store_sqlite.close()` line, as it has no `migrate` line (M1). `app.serve` takes the brand by pointer and a header
  set (`.Standard`, or `.Skeleton` for the skeleton's exact header list in `minimal`, §17), and installs the
  platform's own SIGINT/SIGTERM handler, which `app.wait` returns on; a second signal exits 1 at once (F-10).
- **`HOME_CARDS` and `FIND_SOURCES`** are handed to the one feature that reads each, as `ROUTES` is handed to the
  router. The Today page shows the cards in the table's order, which no longer has to follow `NAV`. A source is a
  domain's `search`, which fills `store.Search_Hit` rows (§15.1).
- **`brand.odin`** keeps `BRAND`, `NAV` (and `LAB_NAV` in `full`, §7.3) and the copy: the names, nav labels, nav order
  and default scheme. Houston's is `cmd/full/brand.odin`, which is where Comms, Capcom and the other product names live
  (D28); packages and prefixes stay generic (D3, D9). Boot checks that every nav href is a GET route on its host
  (§6.1 check 7). A page whose words are the profile's takes them as a `Copy` struct defined there (M1):
  `about_web.init(ABOUT)` and `home_web.init(cards, HOME)`, so `skeleton`'s and `minimal`'s about pages are one
  feature with two texts, and `tools/init` renames every profile's brand fields in place.
- **`routes_test.odin`** runs the boot checks under `CMD=test ./build.sh <p>` (LC §16: `odin test` passes for
  `skeleton` and `full` and fails with 7 problems for a deliberately bad profile).

**The CI check.** The generator job runs `tools/check profile` on every committed profile (§6.1, §20.1): every feature
package a profile imports is mounted, no package's `ROUTES` is left unmounted by every profile, and every SQLite store
the build reaches has its `migrate` line. So CI checks consistency, not bytes: a hand edit that keeps a profile
consistent passes, and one that leaves a package unmounted fails (LC §12).

### 7.3 What a profile is at hosting time

A profile is one binary and one container, served at the root of its own one-label subdomain (D25); `full` also
answers a second, session-free one, its lab host (below). No binary depends on another profile's container, and there
is **no `BASE_PATH`**. One-label names are covered by the `*.alexh95.com` wildcard certificate; two-level names are not
(09 §5; D2). The comparison, verbatim from D25:

| | One binary, route-prefixed profiles | **Container per profile, one-label subdomains (chosen)** | Container per profile behind paths |
|---|---|---|---|
| Representative footprint and perf | no: `/minimal` isn't a minimal binary (08 §6.1) | yes: the parity witness is the real `skeleton` binary | yes |
| App change | none | none | `BASE_PATH` through every href, hx-* URL, src, connect URL, cookie `Path` and the sitemap (08 §6.2) |
| Root-only files (robots.txt, BingSiteAuth.xml, the IndexNow key) | one set for all | one set per profile | can't live under a mount |
| Isolation | shared cookies, storage, the 6-connection pool | host-only cookies, separate storage | shared origin |
| Cross-profile links | boosted navigation breaks across bundles and CSP (05 §9, 11 §6.4) | always full navigations | hand-marked `hx-boost="false"` |
| Restart and rollback blast radius | all profiles at once | per profile | per profile |
| Cost on apollo | one process | about 6–9 MiB idle each (08 §6.5) | same |

**The redirect aliases** keep the brief's URL shape. On `odin-htmx-starter.alexh95.com` they **strip the prefix**
(D25): `/full` → `https://houston.alexh95.com/…`, `/minimal` → `https://starter-minimal.alexh95.com/…`,
`/streams` → `https://starter-streams.alexh95.com/…`, `/skeleton` → `https://odin-htmx.alexh95.com/…` (the public
skeleton witness). The proxy-config CI job (D40) makes two curl assertions per alias, bare and deep:
`/minimal` lands on `https://starter-minimal.alexh95.com/`, and `/minimal/notes?x=1` lands on
`https://starter-minimal.alexh95.com/notes?x=1`. The stack Caddyfile answers with 302s, and
`htmx-odin-starter.alexh95.com` (the brief's spelling) answers 301 to
`https://odin-htmx-starter.alexh95.com{uri}` (D41; the Caddyfile is in §20). Both are **UNVERIFIED (proxy-config CI
job)**. PF §11.4's `redir /minimal* …{uri}` kept the prefix (`{uri}` is the full request URI) and would 404.

So the brief's `htmx-odin-starter.alexh95.com/minimal` reaches `https://starter-minimal.alexh95.com/` in two hops
(301, then 302), and `/full` reaches `https://houston.alexh95.com/`. The targets are https names that NPM serves, so a
browser can follow them on the LAN from stage 1b and publicly from stage 2; at stage 1a only the curl assertions
exercise them (**NEW**; stages in §20.3).

**Why the labs live only on session-free origins.** Eval-capable `/scripting/*` and htmx-semantics-changing
`/compat/*` never share an origin with sessions: cookie `Path` does not isolate same-origin pages, so a script on
`/scripting/` could fetch an admin page with the session cookie attached (CF §4.8 reason 3). They exist in two places,
the `lab` profile (identity `anonymous`) and `full`'s lab host. In either binary they are route classes with their own
page bundle and CSP flag (S12, D19, D20). Links across bundles are full navigations (`hx-boost="false"`), because a
body swap keeps the old document's CSP and scripts (11 §6.4, 05 §9). Rejected (D25): path mounts with `BASE_PATH`, an
`html.url` helper and a URL-literal lint (CF §4.8: one cross-cutting rule with a long regression tail, 08 §6.2, 09 §5);
the labs on Houston's own origin (RF §4.5).

**Houston's lab host** (ANSWERS #4, F2, round 3; LC §7). `full` carries every catalog feature itself, with no
dependency on another profile's container, on two hosts from one binary and one container (`starter-full`). Houston
proper stays on `houston.alexh95.com`. Every starter demo and lab page goes to the session-free
`houston-lab.alexh95.com`: the pages of the four lab-only extensions, which need `eval` or change htmx's semantics, and
with them the skeleton's and the lab's pages, which Houston has no product use for (the mechanism is **NEW**):

| Host | Origin env | Identity | Root | Mounts |
|---|---|---|---|---|
| `houston.alexh95.com` | `SITE_URL` | `accounts`: sessions, cookies | `home` at `/` (Today) | Houston's features (D29) |
| `houston-lab.alexh95.com` | `SITE_URL_LAB` | none: every viewer is the Guest, and nothing sets a cookie | `landing` at `/` (the catalog explorer) | every starter demo and lab page: `notes`; the skeleton's `contacts` (its contacts/events console), `gallery`, `about` and `dashboard` at `/dashboard`; `lab` (the stream contract pages); `scripting`; `compat` |

From `full`'s `routes.odin`:

```odin
// Houston proper.
MAIN_ROUTES := [?][]web.Route{
	web.ROUTES[:],
	web.PUBLIC_ROUTES[:],
	{{.Get, "/", home_web.page_today, .Public, {}, 0}},          // the root: Today
	identity.ROUTES[:],                                          // /login /logout /register /invite /account
	accounts_web.ROUTES[:],                                      // /admin/accounts
	chat_web.ROUTES[:],                                          // /chat …
	// … one line per Houston package
}

// houston-lab: no identity runs here; every starter demo and lab page.
LAB_ROUTES := [?][]web.Route{
	web.PUBLIC_ROUTES[:],
	{
		{.Get, "/",          landing_web.page,   .Public, {}, 0},   // the root: the catalog explorer
		{.Get, "/dashboard", dashboard_web.page, .Public, {}, 0},   // the page `skeleton` mounts at /
	},
	dashboard_web.ROUTES[:],                                     // /ui/ping
	gallery_web.ROUTES[:],                                       // /components /forms /ui /validate
	contacts_web.ROUTES[:],                                      // /data /contacts /search /api/search
	about_web.ROUTES[:],                                         // /about
	notes_web.ROUTES[:],                                         // /notes
	lab_web.ROUTES[:],                                           // /lab/streams
	scripting_web.ROUTES[:],                                     // /scripting/*: .Lab_Host, .Nonce_Csp
	compat_web.ROUTES[:],                                        // /compat/*: .Lab_Host
}

// MAIN_TOPICS and LAB_TOPICS are mounted by main: hub.mount("main", ..MAIN_TOPICS[:]) and
// hub.mount("lab", ..LAB_TOPICS[:]); LAB_TOPICS holds lab_web.TOPICS only. Each table also mounts hub.ROUTES.
HOSTS := [?]app.Host{
	{"main", "SITE_URL",     true,  MAIN_ROUTES[:], NAV[:]},
	{"lab",  "SITE_URL_LAB", false, LAB_ROUTES[:],  LAB_NAV[:]},
}

JOBS := [?][]workers.Job{
	notify_web.JOBS[:],
	chat_web.JOBS[:],
	// … one line per package with jobs
	{
		{"notes.reset",    .Daily, notes_web.reset},             // houston-lab's demo data, reset at 04:00 local (X38)
		{"contacts.reset", .Daily, contacts_web.reset},
	},
}
```

**How the hosts work:**
- **A row answers on the host whose table mounts it.** `front` picks the host by `Host` (the origin's host without the
  port, as D10 matched `SITE_URL_LAB`) and routes only within that host's prefix map (§8.4). A request whose `Host`
  matches no origin goes to the main host, where the canonical-host 301 still applies. In LC §16's prototype,
  `/dashboard` answers 200 on the lab host and 404 on the main one, `/chat` the reverse, `/scripting/live` only on the
  lab host and `/healthz` only on the main one.
- **The platform's rows** come in four tables: `web.ROUTES` (the probes, `/metrics`, the sitemap and the ownership
  proofs) for a site's main host, `web.PUBLIC_ROUTES` (static assets, `robots.txt`, `favicon.ico`, `/licenses`) for
  every host, `web.REPORT_ROUTES` (`/csp-report`) where the profile asks for CSP reports, and `hub.ROUTES`
  (`/events`) for every host that mounts topics.
- **Topics are per host too** (**NEW**): `/events` on houston-lab subscribes only to the families `hub.mount("lab",
  …)` gave it (the lab's stream demos), so a page there can't subscribe to Houston's topics even as a Guest.
- **No session.** The lab host's `identity` field is false, so `front` runs no identity there: it reads no `sid`, sets
  no cookie, and the Viewer is the anonymous Guest. Houston's `sid` is a host-only cookie, so browsers never send it
  there anyway (§17.1, §17.2).
- **The lab rules** are boot checks (§6.1 check 4). `.Lab_Host` keeps its name (§2.11) and now means "mount only on a
  host where no cookie-setting identity runs": scripting and compat can sit on houston-lab or on `lab`'s one origin
  (identity `anonymous`), never on Houston's. A host with no identity holds only `.Public` rows. A second host's env
  var must be set and name a different host than `SITE_URL`. So the eval-capable pages can't land on a session origin
  by a wrong mount line or a missing or wrong variable.
- **Its own bundles and CSP.** The lab host's scripting and compat pages load the `Scripting`, `Compat_Htmx2` and
  `Compat_Alpine` bundles, and `/scripting/*` carries `.Nonce_Csp` (§12); Houston's own pages never load those bundles
  or get a nonce CSP. A WS upgrade there checks `Origin` against `SITE_URL_LAB` (§8.2).
- **One root per host** (§6.3): `home` on Houston, `landing` on houston-lab, where the skeleton's dashboard page,
  `skeleton`'s root, sits at `/dashboard`, inside dashboard's own prefix.
- **The demo data** lives in Houston's SQLite file, in the demo features' own tables (contacts keeps the skeleton's
  table names, §11.5). Each is capped, by `NOTES_CAP` (500) and `CONTACTS_CAP` (2000), and reset nightly at 04:00
  local time by a job row, `notes.reset` and `contacts.reset`, that `full`'s `routes.odin` writes, as it writes the
  root: whether a feature's data is a capped demo is a fact about the profile, not the package (RESOLUTIONS X38). A
  feature's `reset` drops its rows and reseeds them as `SEED=1` does (§11.6). The caps apply only where `full` mounts
  these features on its lab host: the `skeleton` profile stays uncapped, so parity (§18) and the 20k-row `scale`
  scenario are untouched.
- **The lab host's pages** use the bare lab layout (no bell, no account menu) and its own nav, `LAB_NAV`, send
  `X-Robots-Tag: noindex` (the `lab` profile's origin holds the indexed copy; **NEW**), and link to Houston by absolute
  URL, so every crossing is a full navigation. Houston links to them from its footer (§13.2).
- **`lab` stays an independent witness** at `odin-htmx-starter.alexh95.com`: the same lab pages from its own binary and
  container, so neither depends on the other (ANSWERS F2).

The generator gives a selection with `scripting` or `compat` the `anonymous` identity (§7.4). ANSWERS round 3 settles
what this section used to leave open, whether "every feature" also takes in the catalog features Houston has no use
for (`notes`, the skeleton's `dashboard`, `gallery` and `contacts`, `landing`, and the lab's `/lab/streams`): it does,
all on houston-lab. ANSWERS round 3 names no page for one catalog feature, `about`, the skeleton's `/about`; the fold
mounts it on houston-lab with the skeleton's other pages, in LC §7, D25 and here alike, and RESOLUTIONS X36 confirms
that reading: `about` sits on houston-lab in `full`, next to the skeleton's other demo pages. Houston proper has no
"about the stack" page; its footer links to houston-lab (§13.2).

### 7.4 The generator

`tools/init` keeps the skeleton's plan-then-commit engine (D26; `SK/tools/init/plan.odin:52-268`). Every edit is
planned in memory, every literal edit must match, and any miss aborts with nothing written (`check()`,
`SK/tools/init/plan.odin:228-239`); then it asks `[y/N]`. It changes from overlay to compose (09 §4.6): the features
already exist as packages, so it deletes what is not selected and writes or edits the profile's files (LC §10). More
whole-file overlays are rejected; the skeleton's `--minimal` overlay already re-implements the layout shell in 328 lines
(01 §8). Dependency closure comes from the selected packages' import lines (09 §4.6), so a producer brings notify, its
hard dependency (§6.2).

| Command | Effect |
|---|---|
| `--list [--json]` | features, family members, switched implementations, dependencies, sizes, SQLite needs; the JSON is committed as `docs/catalog.json`, `#load`ed by the `landing` feature and checked fresh in CI |
| `--explain <features>` | the closure and the plan; writes nothing |
| `--profile <p>` | start from a named profile's selection; `--minimal` stays as an alias of `--profile minimal` |
| `--features a,b` | select features |
| `--add <f>`, `--without <f>` | add a feature to the selection, or drop one, editing the profile's files in place; `--without` also deletes `features/<f>/`, `app/stores/*/<f>/`, `e2e/tests/<f>` and `load-tests/scenarios/<f>` |
| `--store sqlite\|memory`, `--identity accounts\|envadmin\|nick\|anonymous`, `--client hyperscript\|vanilla`, `--theme full\|lite` | the family commands: they edit the profile's line in `build.*` and `ols.json` |
| `--dry-run` | print the plan, write nothing |
| `--verify` | on by default: apply to a scratch copy, build through `build.*`, run `tools/check profile`, and compare `bin --features --json` (the profile, the family members' `NAME`s and the route ids per host) with the plan before touching the tree |
| `--pairwise --seed <n>` | the covering array over feature presence (D37, §19) |
| `--yes` | skip the `[y/N]` question, as the skeleton's init does (01 §8); the generator CI job uses it (D40) |
| `--wordmark --suffix --repo --site` | the skeleton's naming flags, kept unchanged (01 §8); they write `cmd/app/brand.odin` (D26; RESOLUTIONS X6) |

The per-axis `--impl` commands go, and `--rich` with them: every chat transport and both bot backends are always linked,
the games catalog follows `GAMES_API_URL`, and the wiki and video follow the store family (LC §10). D7's `--emit --like`
check goes too: CI runs `tools/check profile` instead (§7.2).

**What it writes** (LC §10):

| File | When | What |
|---|---|---|
| `app/cmd/app/{main,routes,routes_test,brand}.odin` | a new project | §7.2's four files for the selection: imports, `init` calls in dependency order, `start` and `drain` calls, `store_sqlite.open` and one `migrate` per SQLite-backed store (SQLite family only), the host tables with the root row, `TOPICS`, `JOBS`, `HOME_CARDS`, `FIND_SOURCES`, `BUNDLE_EXTS`, `HOSTS`, the nav |
| `build.{sh,bat}` | a new project | one profile, `app`, with the selection's four families |
| `ols.json` | a new project | the four collections pinned to the project's families |
| `UPSTREAM.md`, `.github/workflows/ci.yml`, `CHANGELOG.md`, `TODO.md` | a new project | `UPSTREAM.md` holds the upstream URL, version, commit, the exact command line, the selection, and the vendored odin-http's base commit and changes from its own `UPSTREAM.md` (10 §6); the CI matrix is trimmed to `app`; a fresh CHANGELOG and TODO |
| the four profile files, `build.*`, `ols.json` | `--add <f>`, `--without <f>`, the family commands | edits in place |

- **Edits are planned against the parsed file.** `core:odin/parser` finds each table literal and the call block, and
  each edit is a literal insertion or deletion of one line: an import, a mount line per host table, a `TOPICS` or
  `JOBS` line, an `init`, `start` or `drain` call, a `migrate` line, a home-card or find-source row. If a file doesn't
  have the shape the plan expects, the engine aborts with nothing written (`SK/tools/init/plan.odin:228-239`) and says
  which file to fix by hand (**NEW**: parse-based edits are not prototyped).
- **It also deletes** the unselected `features/*` with their `app/stores/*/<f>/`, `e2e/tests/<f>` and
  `load-tests/scenarios/<f>`, and every `cmd/*` but `cmd/app`; removes the `Perm` and `Behaviour` groups of deleted
  features (literal edits that abort on a miss; D35, D22); and renames identity tokens from `tools/init/UPSTREAM`. It
  keeps the skeleton's closing checklist ("Done. Next:", `SK/tools/init/main.odin:86` onward) and its leftover report
  (`SK/tools/init/main.odin:122-177`).

**Lean defaults**: the memory family, the `nick` identity unless a feature needs accounts (or `anonymous` when the
selection has `scripting` or `compat`, whose pages need a session-free origin, §7.3; **NEW**), the vanilla client, the
lite theme, and `home` as the root (LC §10). What used to be per-axis defaults now follows from these or from env: the
wiki and video follow the store family (`source_files` and `catalog_file` on memory), the games catalog is static until
`GAMES_API_URL` is set, the bot defaults to mock (`BOT_BACKEND`), and a terminal device starts in line mode. So
`init myapp --features chat` writes chat's hello world (§7.5). **Refusals come with advice**: "contacts has no memory
store; use --store sqlite", and two roots on one host (§6.3; D26).

A sample plan (the CF §4.9 shape with this plan's names; `<n>` marks counts not yet known). A run prints it before
`Apply? [y/N]`; `--explain chat,bot --store sqlite` prints the same and stops:

```
$ odin run tools/init -- homechat --features chat,bot --store sqlite
plan for "homechat" from odin-htmx-starter v2.<n>.0 (<commit>)
  features    chat, bot, notify (a hard dependency of both), home (the root)
  families    store=sqlite  identity=nick  client=vanilla  theme=lite
  switched    chat.transport ws, sse, poll, multipart (default CHAT_TRANSPORT); bot.backend mock, llama (default mock)
  stores      app/stores/sqlite/{chat, bot, notify, audit} (audit: store:audit's rows; no /admin/audit page)
  sqlite      the store family: prepare builds the SQLite library
  bundle      htmx + ws, sse, ptag, hx-multipart, hx-pending, upsert, hx-prompt, hx-targets, download, browser-indicator
  hosts       main: <n> routes (chat <n>, bot <n>, notify <n>, home <n>, platform <n>), 1 root
  topics      chat.room, chat.presence, chat.typing, chat.reply, notify.user, bot.health, bot.ask, home.presence
  migrations  audit, notify, chat, bot (one migrate line each in main, in dependency order)
  removes     <n> feature dirs with their app/stores/*/<f>/, e2e/tests/<f> and load-tests/scenarios/<f>;
              every cmd/* but cmd/app; the Perm and Behaviour groups of the removed features
  writes      app/cmd/app/{main, routes, routes_test, brand}.odin, build.{sh,bat}, ols.json,
              .github/workflows/ci.yml (one profile), UPSTREAM.md, CHANGELOG.md, TODO.md
  verify      scratch copy: ./build.sh app ok, tools/check profile ok, bin --features --json = plan ok
Apply? [y/N]
```

**As built (M2), generator v1.** `tools/init` reads the tree with `core:odin/parser` (catalog.odin, profiles.odin)
and keeps no manifest. A feature is a directory under `app/features`; what it brings is what its web package declares
(`ROUTES`, `EXTS`, `TOPICS`, `JOBS`, `BUNDLES`, `init`, `home_card`); its dependencies are its packages' imports of
other features (dashboard and gallery need contacts); its stores are the `app/stores/<family>/<f>` that exist; the
family members are the directories (`stores/*`, `platform/client/*`, `platform/theme/*`, `platform/authz/anonymous` and
any `features/*/identity_*`). **A feature's lines come from a committed profile that mounts it, its donor**: its mount
lines, its `TOPICS` and `JOBS` lines, its nav entries (an href that is one of its GET rows), the copy its `init` takes
(`ABOUT`, `HOME`), and every statement of `main` that names its packages, each with its phase (before `app.check`;
between check and serve, after the store's open and migrations; after serve; after wait). The donor is `--profile`'s
when it mounts the feature, else one on the same store family, else any (a store-phase line taken across families is
printed under `check`). The committed profiles are hand-written and held to `tools/check profile`, and check refuses a
`ROUTES` no profile mounts, so every feature has one; the test `odin test tools/init` composes each committed profile
again from its own selection and holds the result to its lines. The platform's lines are written for the families:
`store_sqlite.init`, `open("<name>")`, one `migrate` per SQLite store with `MIGRATIONS` in dependency order and `close`
on SQLite; `hub.init`, `hub.mount` and `{"platform", hub.ROUTES[:]}` when a feature has `TOPICS`; `BUNDLE_EXTS`,
`PAGE_BUNDLES` and `HOME_CARDS` (when home is selected) from the declarations. `BRAND` is the base's (`--profile`'s,
else minimal's names), plus a `search` box from the donor whose href is a selected feature's page, and `overlays`
when a selected feature's pages target `#overlay` or `#toasts` (read from its source). The root is `--profile`'s,
else dashboard, landing or home, home joining when none is selected. A new project's profile is `app`; `--add` and
`--without` edit a profile in place (default `app`), line by line against the parsed files; a family command
(`--store sqlite --profile lab`) edits the build lines, and a store swap moves main's store lines too. `--verify`
copies the tree (no `.git`, builds or `node_modules`), writes the plan there, runs `prepare`, `build.*`, `CMD=test
build.*` and `tools/check profile routes topics exts`, and compares `--features --json` with the plan before it asks;
a failure leaves the copy for a look. A new project also gets the scripts' default profile (`run.*`, `prepare.*`,
`load-tests/run.sh`, the Dockerfile, the e2e setup) at `app`, CI trimmed to `app` (its matrices, its include rows with
a smoke write the selection keeps, one coverage run), nightly's TSan and soak jobs dropped (they build lab and
skeleton), and a fresh `UPSTREAM.md`, `CHANGELOG.md` and `TODO.md`. `--pairwise` (D37's covering array) joined at M4 (slice 13). Not in v1:
removing `Perm` and `Behaviour` groups (no feature has its own yet), and hosts beyond `main`. Without a selection,
`init <name>` renames as before (and runs again: a token the README no longer held had stopped it).

**As built (M2), identities.** The lean default holds: `nick` when the tree has it and the selection has neither
`scripting` nor `compat`, else `anonymous`. An identity that lives in a feature (`features/accounts/identity_nick`)
brings that feature into the selection: its mount is the identity's own routes (`{"accounts", identity.ROUTES[:]}`,
from its donor), `BUNDLE_EXTS` gains `identity.EXTS`, and the host's identity flag is on (off only for `anonymous`).
A selection of `accounts` on an identity that isn't its own is refused with the `--identity` to use. The plan's bundle
line follows a sum of other packages' `EXTS` (chat's is its transports'), and its topics line a family named by a
package constant. Checked: `init ci-chat --features chat` in a scratch copy plans home, notify, chat and accounts on
nick, then tests, checks and builds; `--features scripting` stays on anonymous.

The bundle line is derived (RESOLUTIONS X29, as LC §12 recasts it): `chat_web.EXTS` unions its four transports'
extensions (ws, sse, ptag, hx-multipart) with hx-pending, upsert, hx-prompt, hx-targets and download; `bot_web` brings
browser-indicator, plus sse and hx-multipart for its two deliveries and download for transcripts (that part of
`bot_web`'s `EXTS` is this plan's reading, **NEW**). Every chat selection ships all four transports' extensions. Chat's
transcripts get download through `chat_web` itself (X34), so dropping bot from the selection never drops download.

### 7.5 Hello world for any selection

A hello world is the leanest families plus a root feature (D27; LC §10). There are **no hello packages**. Every
feature with a page exports a `home_card`, and `main`'s `HOME_CARDS` lists them in order; every generated project has
one root per host, `home` unless the selection includes `dashboard` or `landing` (D27; RESOLUTIONS X5). So a selection
boots to a page with one working card per selected feature (PF §4.1): `init myapp --features chat` writes chat, notify
(its hard dependency) and home, and boots to Today with chat's card over all four transports, on the memory store and
the nick identity. Where `dashboard` or `landing` is the root, `/` is that feature's own page and shows no home cards.

**The ~400-line rule.** A feature whose leanest selection grows beyond about 400 lines gets a leaner real member of a
family, as chat has its memory store, never a demo-only copy. Rejected: PF §4.1's hello variant per feature with
mandatory `@<f>:hello` specs, a second implementation of every feature.

**CI coverage** (D27, D40): every named profile per push, each checked by `tools/check profile`; one rotating singleton
(`tools/init … --features <f> --yes` with `--verify`, on a clean checkout, then that output's check, build and chromium
e2e for its tags) per push; every singleton nightly. The pairwise covering array over feature presence starts nightly
at M4 (§19).

## 8. Server substrate: the fork, streams, router, configuration, boot and drain

Everything between the socket and a handler: the patched HTTP server, the stream protocols on top of it, the router,
the `front` chain, the typed configuration, and how a process starts and stops. The hub and the page contract are in
§9, the crash model in §10, the store in §11.

### 8.1 The odin-http fork

**Why a fork (S1).** odin-http at fac113f has no streaming, no upgrade, no SSE and no WebSocket support: every response
is buffered whole and sent with one `send` (03 §0, §2.3). The no-fork seam fails. A handler that writes to the socket
itself never posts a `recv`, so a vanished client goes unnoticed; `connection_close` is private, so the stream can't
end cleanly; and shutdown waits forever on the `Active` connection (03 §2.6, §2.7). Upstream is quiet: 0 commits since
fac113f, and the SSE PR #28 is stale since 2024 (03 §3). Crash containment and timeouts need code inside odin-http too
(S1). So the fork lives in-tree at `app/vendor/odin-http/`: laytan's fac113f vendored, F-1..F-13 on top, and an
`UPSTREAM.md` that names the base commit and each change (D11; ANSWERS F3). There is no separate repo; the agent
vendors it at M0, replacing the skeleton's `app/odin-http` submodule (§4.2 step 7).

| # | Change | Why | Evidence |
|---|---|---|---|
| F-1 | `Streaming` state, `Connection.stream`, `stream.odin` (`stream_begin/write/end/queued/loop`, `on_data`, `on_close`, `on_shutdown`) | SSE, WS and multipart on the HTTP port (S2) | 03 §10.1 (29/29 contract tests on Linux) |
| F-2 | HTTP/1.0 fallback: a close-delimited body instead of chunked | nginx without "Websockets Support" talks 1.0 upstream | 03 §10.5 |
| F-3 | `stream_sendfile(s, fd, off, len)` on `nbio.sendfile` | video Range without buffering the file | 07 §0.2 (256 MiB at 5.1 MB peak) |
| F-4 | `Server_Opts.on_thread_init` / `on_thread_shutdown` | hub inbox registration, heartbeat and watchdog timers, timer cancellation at drain | 03 §11 item 2; 13 §4.2 step 6 |
| F-5 | `Server_Opts.invoke`: every nbio completion callback the fork owns (accept, scanner recv, body read, dispatch, send completion, stream ops, sendfile) runs through this wrapper, where `guard_call` sits | F1-class crashes inside odin-http escape an app-level guard | 13 §1.3 (F1 row) |
| F-6 | `_body_length` rejects `Content-Length` < 0, overflow and non-digits with 400 | F1: one unauthenticated packet aborts the process; the skeleton's 6d37506 (v1.2.1) refuses it in `front` instead, and leaves `OPTIONS *`, which odin-http answers itself, to the upstream fix | 02 §1.2 (`SK/app/odin-http/body.odin:119-148`) |
| F-7 | Timeouts: header read 10 s, idle keep-alive 75 s, body read 30 s, as per-op nbio timeouts on the scanner's recv | slowloris; shutdown hangs | 02 F5; `scanner.odin:204` |
| F-8 | `max_connections` (fd soft limit − 64) answering 503; accept errors logged and re-posted instead of `panicf` | at the fd limit the server stops accepting after 1,012 streams and `/healthz` hangs; non-EMFILE accept errors panic | 13 §3.5; 03 §2.8 (`server.odin:418-428`) |
| F-9 | Shutdown deadlines: Active ≤ `DRAIN_DEADLINE`, idle peers and peers still sending their headers get `shutdown(SEND)` then a recv cancel within 500 ms, streams get 2 s grace; past the deadline, closing connections no longer hold the loop | the three unbounded waits | 13 §4.1-4.2; S0.7 |
| F-10 | SIGTERM handled as well as SIGINT; a second signal exits immediately | PID-1 SIGTERM under compose | 13 §4.2 step 1 |
| F-11 | Per-thread Date header buffer | the Date race (2 malformed headers in about 800k) | S6; 01 §16 |
| F-12 | `listen` returns an error naming io_uring and seccomp; bind retry for 3 s | `Address_In_Use` after `kill -9` | 13 §3.3 |
| F-13 | Deferred responses: `response_defer` hands a handler a `Response_Ref` (loop, socket, a per-thread request generation) and `response_resume` returns the Response on that loop, or nil once the connection is gone or has moved on; while deferred, a poll on the socket closes the connection when the peer leaves and calls the application's `on_gone`; a thread's shutdown waits, to `DRAIN_DEADLINE_MS`, for the replies it owes | a pool's reply (argon2id, the query pool, llama, jobs) must not touch a connection that is gone | S0.5 (ASan: 5,042 clients left mid-verify, 0 reports; a raw-pointer control, 3/3 heap-use-after-free) |
| F-14 | The chunked body decoder refuses bad input instead of asserting: chunk data not followed by CRLF is a 400, trailer fields are discarded (at most 32 lines), and a chunk size is 1–15 plain hex digits. Found by the M1 audit (M1-01, CRITICAL): one client could stop the process with about 101 such requests a minute | — | M1 audit |
| F-15 | Throughput on the response path, from a profile behind M1's parity gate: header values written whole instead of rune by rune (12 % of a write's CPU), lookups with an already-lower-case key skip `sanitize_key`'s copy, and F-13's watch is optional (`response_defer(…, watch)`), off for store writes (7 %) | — | M1 parity gate |
| F-16 | The M1 re-read's fixes: a scan asked for inside a scan callback is queued and run by the outermost call, not nested one frame per buffered token (M1-17, CRITICAL once confirmed: 12,000 one-byte chunks overflowed a loop's stack); chunk framing counted against the body cap, 4 KiB CRLF-only chunk lines, trailer scan errors as errors (M1-18..M1-21); client-caused parse and send failures at info (M1-22) | — | M1 audit |

**What stays out of the fork.** Only the generic seam and the fixes go in. The WS codec, the SSE encoder, the multipart
writer, Range parsing and the hub live in the starter (`platform/stream`, `platform/hub`; S1), so the diff stays small
enough to offer upstream. F-5's guard is §10's subject.

**The hot path keeps its shape.** 03's prototype added an enum value, a struct field and a shutdown case to the request
path (03 §10.4), but no k6 run has measured it. Spike S0.2 proves parity first: 709bc94 rebuilt on the fork with F-1
and F-5…F-12 must reach a paired ratio ≥ 0.97 against HEAD on every scenario, on both legs, before anything builds on
the fork (D44; **UNVERIFIED (S0.2)**).

**Upstream and rebase.** The seam is offered to laytan as a PR after M2 (Q4), from a GitHub fork made at that time
out of `UPSTREAM.md`'s changes (ANSWERS F3). On each upstream bump the new base is vendored, F-1..F-13 are re-applied,
`UPSTREAM.md` is updated and 03's contract suite re-run; every milestone audit reads the diff against the base line by
line (§19). Rejected (D11): the
no-fork takeover seam, a separate realtime port (S2), and a guard only where odin-http calls user code, which misses
odin-http's own parser callbacks.

### 8.2 Streams

`platform/stream` holds the protocol code on top of F-1 (D12):

| Piece | Contract | Evidence |
|---|---|---|
| SSE encoder | splits user text on CR, LF and CRLF into one `data:` line each, so a CR can't start an `event:` field | 03 §1 (hx-sse splits on all three); 03 §10.2 check 6 |
| WS handshake | its own `Origin == SITE_URL` check (`SITE_URL_LAB` on a lab host, §7.3), because GET upgrades pass `same_origin` and carry no `Sec-Fetch-*`; a handshake without `Origin` is not a browser's, cannot be cross-site WebSocket hijacking, and passes (device clients such as `cmd/term-agent` authenticate by token instead; S0.3); while the origin is still the brand's placeholder (a dev run with no `SITE_URL`), an `Origin` naming the request's own `Host` passes instead (M2); version ≠ 13 → 426 | 04 §4.4; 03 §10.2 check 8; S0.3 |
| WS codec | strict RFC 6455: RSV bits, UTF-8, control frames, masking, version; unmasked or RSV1 → 1002, bad UTF-8 → 1007, oversize → 1009 | 03 §10.2 checks 7 and 10; 03 §5.1 (spark's wsserver's RFC 6455 coverage table, taken as a checklist; the codec gets new unit tests, RESOLUTIONS X24) |
| multipart writer | `multipart/mixed` with CRLF framing and a `Content-Length` per part, one chunk per part, flushed at once | 03 §1, §8; 04 §4.3 (LF-only swapped nothing) |
| Range sender | 200, 206, suffix, 416, HEAD, If-Range, ETag, over F-3's `stream_sendfile` | 07 §0.2 (200, 206, suffix, 416, HEAD verified); the media route is in §15 |

Every stream response sends `X-Accel-Buffering: no` and `Cache-Control: no-cache, no-transform`, so nginx (NPM) flushes
each event (08 §3.2) and no proxy compresses a stream: Caddy's `encode` skips a `no-transform` response, and a
compressed stream would hold 1.1 MiB (gzip) to 2.8 MiB (zstd) of Caddy's memory against 65 KiB raw, though it added no
delay worth counting (S0.8: p99 ≤ 4.6 ms with `encode zstd gzip`, ≤ 1.3 ms without). Every stream also writes its first bytes with the headers (an SSE comment line, a multipart CRLF preamble):
WebKit resolves a streamed fetch only at its first body bytes, so a quiet SSE stream stayed "connecting" until the
first heartbeat (19.6 s) and a slow first part held a multipart response, inside htmx's 60 s request timeout (S0.3).
A slow WebSocket consumer gets close 1013 before its queue passes the cap, then 2 s to take it before the fork cuts it
off (`stream_would_overflow`, and F-1's `stream_end` with a deadline; S0.3). HTTP/1.0 peers get a close-delimited body (F-2). Each stream is a `Conn` on
the heap, freed one tick after `on_close`, and registered on its loop: one timer per loop sends the heartbeats and
enforces the WS pong deadline (§9.4); the three allocator buckets are in §5.

`platform/stream/client` is one non-blocking chunked, SSE and WS client on `core:net` (**NEW**). Its three users are
`bot/backend_llama` (§14), `cmd/term-agent` (§16) and `tools/streamload` (§19): one definition of the streaming client.

### 8.3 Router

Dispatch is by host, then by prefix (S7, D9; LC §7). Each host has its own map, built at boot from the tables that
host mounts, from the first one or two path segments to the owning feature's rows, and the longest key wins:
`/ui/ping` → dashboard, `/ui` → gallery; `/admin/<f>` and `/api/<f>` are two-segment keys; the root row is the key
`/`. Which feature may claim which prefix is §6.3's rule, checked per host.

Inside the feature, odin-http's anchored Lua patterns are tried in order, at about 140 ns per route tried. The worst
case (the last route) is 4.19 µs at 30 routes, 22.4 µs for a flat 150-route table and 78.9 µs at 600 (09 §4.4); with
≤ 20 routes per feature behind the prefix map it is about 2.8 µs, inside D38's routing budget of ≤ 3 µs. Static assets
match before anything else: the skeleton registered `/static/(.+)` last, so every asset request walked the whole table
(09 §4.4, `SK/app/src/routes.odin:65`). The 405 with `Allow` and the site 404 keep the skeleton's fallback
(`SK/app/src/routes.odin:67-69`, 01 §2). Each row's route id (`"<METHOD> <pattern>"`) keys its per-route request
counter (§10, §19).

### 8.4 The `front` chain

`front` keeps the skeleton's order (`SK/app/src/controllers/middleware.odin:38-87`) and adds two inputs read once at
the top: the trusted client address and the request id. It lives in `platform/app`, not `platform/web`, because it
calls the build's identity and the identity packages import `platform/web` (§5.1; LC §5; **NEW**: not prototyped).

1. **Security headers** by the route's flags: the base policy plus boot-constant flag strings looked up in O(1) (§12).
2. **Canonical host and the host's table**: the `*.fly.dev` → `SITE_URL` 301 (`middleware.odin:266-282`). `front`
   picks the host by `Host` (the origin's host without the port, matched against each `HOSTS` row's env var) and routes
   only within that host's prefix map, so a row answers only on the host whose table mounts it and 404s elsewhere; a
   request whose `Host` matches no origin goes to the main host, where the canonical-host 301 still applies (§7.3;
   LC §7; ANSWERS F2; **NEW**). The flag filter of the first design is gone: the tables say which rows answer where.
3. **`same_origin`**: a write must be same-origin by `Sec-Fetch-Site` or `Origin` (`middleware.odin:222-242`; §17).
4. **Viewer load and perm check**: the build's identity (`identity:`'s `load_viewer`, contract `authz.Load_Viewer`)
   loads the `Viewer`, with the member's preferences on it; the route row's `perm`, `.Step_Up` and `.Lan_Only` are
   checked before a byte of the body is read (D35; status codes in §17). On a host whose `identity` field is false no
   identity runs: no `sid` is read or set, and the Viewer is the anonymous Guest (§7.3).
5. **Body read** with the route's `body_cap` (0 = `MAX_BODY`, 64 KiB, `middleware.odin:36`) under F-7's body timeout:
   413 past the cap, 400 if malformed.
6. **Handler**, inside F-5's guard.
7. **One access-log line**: logfmt with the request id, route id, status, µs, and `impl=` when a runtime-switched axis
   served the request (§10).

**As built (M1)**, with the host, route, request id and security headers settled first: a malformed
`Content-Length` gets 400 and a closed connection before anything else answers; then the canonical-host 301; then
`same_origin` for **every** write, routed or not, so a cross-site POST to an unknown path is a 403 and not a 404;
then, when no row matches, the body cap (413) before the 405 with `Allow` or the 404, as the skeleton's fallback
answered; then the viewer and the route's access rules, the body under the route's cap, the handler, and the log
line. A handler that answers later (F-13's deferred response, store v3's writes) leaves the log line to its
continuation: `web.resume` restores the request's context on the answering loop and `web.finish` counts, logs and
clears it, so the deferred path logs exactly as the direct one.

**Client address.** `X-Real-IP`, `X-Forwarded-Proto` and `X-Request-Id` count only when the TCP peer is inside
`TRUST_PROXY` (empty = trust no peer; on apollo, the stack Caddy's fixed address as a /32, RESOLUTIONS X43);
otherwise the peer address is the client (D35, §17.8). Limits and logs use the hashed client id, never the raw IP
(§17.5). **Request ids** come from a trusted peer's `X-Request-Id` or are generated as `<boot>-<loop>-<seq>` with no
syscall and no lock, and are echoed as `x-request-id` (13 §5.1). `/healthz` stays exempt from redirects and auth,
because health probes call it (08 §6.4; `middleware.odin:267`).

### 8.5 Configuration

One typed env table lives in `platform/env` (L2; D10; LC §5): `app.boot` records and reads the platform's rows, and
each feature's `init` records and reads its own, so features never import `platform/app`. Each row is
`{name, type, default, secret, doc}`; the types are int, bool, duration (`7d`), size (`16MiB`), CIDR list, enum, path
and secret. Each value is parsed once at boot, printed by `--limits` and `--features --json` with secrets masked (both
answered in `app.check`, once every `init` has recorded its rows, §8.6), and listed on `/admin/modules`; the README env
tables are generated from `bin --limits --json`. `*_FILE` variants read compose secrets (08 §5.7). Boot warns on an
unknown variable inside a known prefix.

**Platform** (no prefix; the skeleton's names keep their meaning, `SK/CLAUDE.md` env table):

| Name | Default | Meaning |
|---|---|---|
| `PORT`, `BIND_ALL` | first argument, else 8080; unset (loopback) | listen port; any value listens on 0.0.0.0 (containers) |
| `DB_PATH`, `SEED` | `:memory:`; unset | SQLite file (`:memory:` is fresh per process); `1` seeds an empty file DB |
| `SITE_URL` | brand.odin | the canonical origin; also what the WS `Origin` check compares |
| `SITE_URL_LAB` | brand.odin (only `cmd/full`'s names one) | the origin of `HOSTS`' second host, `https://houston-lab.alexh95.com` in `full`; `front` matches its host, without the port, against `Host`. Only the rows the lab host's table mounts and the platform's public rows answer there, with no identity, and the WS `Origin` check there compares against it; boot refuses it empty or naming `SITE_URL`'s host (§6.1 check 4, §7.3; ANSWERS F2; **NEW**) |
| `THREADS`, `LOG_LEVEL` | one per core; `info` | event-loop threads; `debug`/`info`/`warn`/`error` (`warn` silences the access log) |
| `MEMMODE` | `ephemeral` (`skeleton`: per D17) | `single` or `ephemeral` (§11); D10's `STORE` is gone, since the store family is the build's (LC §3) |
| `MAX_CONNS` | fd soft limit − 64 | connection cap; past it new connections get 503 (F-8) |
| `HEADER_TIMEOUT_MS`, `IDLE_TIMEOUT_MS`, `BODY_TIMEOUT_MS`, `SEND_TIMEOUT_MS`, `DRAIN_DEADLINE_MS` | 10000, 75000, 30000, 30000, 5000 | F-7's timeouts, and one send to a client that doesn't read (M2, M1-02: then the connection is cut); how long Active requests get at drain (F-9) |
| `TRUST_PROXY` | **empty = trust no peer** | CIDR list of proxies whose forwarded headers count; on apollo, the stack Caddy's fixed `ipv4_address` as a /32 (§20.4; RESOLUTIONS X43) |
| `LAN_CIDRS` | 192.168.0.0/16 | what `.Lan_Only` and `ACCOUNTS_NICK_FROM=lan` accept |
| `STREAM_HEARTBEAT_S`, `STREAM_MAX_QUEUED` | 20, 256KiB | per-loop heartbeat; per-stream queue cap before `Too_Slow` (§9) |
| `STREAMS_PER_USER`, `STREAMS_PER_CLIENT`, `STREAMS_TOTAL`, `HUB_RING` | 8, 16, 8192, 256 | stream caps; replay ring per topic (§9) |
| `STREAM_CONNECTS`, `STREAM_QUEUED_TOTAL`, `HUB_RING_BYTES` | 20, 64MiB, 1MiB | stream connects a minute per client (429 past it); bytes queued to all streams (new streams 503 past it); bytes per topic's ring (§9; M2) |
| `METRICS_TOKEN_FILE`, `SESSION_KEY_FILE` | unset | bearer token for `/metrics` (§10); secret key for signed cookies and tokens |
| `COOKIE_SECURE` | auto | `Secure` when the request arrived as https through a trusted proxy (§17) |

**Features** (prefix = feature name):

| Name | Default | Meaning |
|---|---|---|
| `CHAT_ROOM_CAP`, `CHAT_ROOM_MAX_AGE` | 500, 7d | room retention, whichever hits first |
| `CHAT_DM_CAP`, `CHAT_DM_MAX_AGE` | 1000, 30d | DM retention |
| `CHAT_ANNOUNCE_CAP`, `CHAT_ANNOUNCE_MAX_AGE` | 100, 365d | announcement retention |
| `CHAT_RING_BYTES`, `CHAT_TRANSPORT` | 16MiB; — | global budget of the in-memory chat rings; default transport when the user has no preference (§14) |
| `BOT_BACKEND`, `BOT_LLAMA_URL` | mock; none | default backend, switchable by an admin at runtime on `/admin/bot` (D8); required for llama, never assumed (07 §2.2); on apollo, `http://<APOLLO_LAN_IP>:<LLAMA_PORT>` (§14.3; RESOLUTIONS X41) |
| `BOT_LLAMA_KEY_FILE`, `BOT_SEED`, `BOT_DELAY_MS`, `BOT_CONCURRENCY` | unset | llama key; mock determinism and speed; concurrent generations |
| `ACCOUNTS_REGISTRATION`, `ACCOUNTS_ADMIN_HASH` | invite; unset | registration mode (Q10); argon2id hash of the bootstrap admin |
| `ACCOUNTS_ARGON_THREADS`, `ACCOUNTS_NICK_FROM` | 2 (1 with ≤ 2 CPUs, Q34: answered); lan | argon pool threads; `nick` only for clients in `LAN_CIDRS` |
| `ACCOUNTS_NICK_ADMIN_CIDRS` | unset (none) | `nick` makes its clients in these CIDRs Admin, so `/admin/ops` opens in `streams` (ANSWERS round 9); the e2e suite sets loopback |
| `GAMES_URL`, `GAMES_API_URL`, `GAMES_CATALOG` | unset | spark's origin; its API, whose presence selects `catalog_api` (§15.3); a `catalog_static` override |
| `NOTES_CAP`, `CONTACTS_CAP` | 500, 2000 | the demo caps on `full`'s lab host, whose rows the jobs `notes.reset` and `contacts.reset` put back nightly at 04:00 local time; read only where `full` mounts these features on its lab host, so `skeleton` stays uncapped (§7.3, §11.6; RESOLUTIONS X38) |
| `VIDEO_DIR`, `VIDEO_SIGN_KEY_FILE`, `VIDEO_CDN_URL` | /data/media; unset | media volume; signed-URL key; an optional bunny.net pull zone (stage 2; Q26) |
| `TERM_IDLE`, `STATUS_PROBES`, `GUESTBOOK_OPEN` | 15m; unset; 1 | terminal idle timeout; external probes on `/status`; guestbook form on |

**Build-time `-define`** is used only for `VERSION`, `TEST_ROUTES` (the crash-drill routes; release images assert they
answer 404) and `PROFILE` (spall) (S17). Compose pins the stack network's subnet, gives `caddy` a fixed
`ipv4_address` and sets every app container's `TRUST_PROXY` to that one address as a /32, so the app trusts the stack
Caddy alone and nothing trusts every private range by default; why is in §17.8 (RESOLUTIONS X43).

`ACCOUNTS_NICK_FROM` carries the `ACCOUNTS_` prefix because the `nick` identity lives in the `accounts` feature
(`features/accounts/identity_nick`, §2.8), following D10's "prefix = feature name" rule (RESOLUTIONS X7).

### 8.6 Boot order

Adapted from RF §3.8, and written as plain calls in the profile's `main.odin` (§7.2; LC §6). Each step fails loudly
with a message.
1. **CLI short-circuits, each answered by its owner** (LC §5). `app.boot` answers `--healthcheck` and `--worker` and
   exits before any server state exists; `identity.cli()` answers `--hash-password` (in `accounts` and `envadmin`);
   `--features`, `--routes` and `--limits` wait for step 4 and `--backup` and `--adopt-profile` for step 5, where their
   owners answer them.
2. **Raise `RLIMIT_NOFILE`** soft to hard (13 §3.5), in `app.boot`.
3. **Logger and typed env**: per-thread logfmt buffers, then the platform's env rows (`app.boot`); then each feature's
   `init`, in dependency order (notify before its producers), records and reads its own rows in `platform/env` and
   declares its limits to obs, starting nothing; `home_web.init` and `find_web.init` take `HOME_CARDS` and
   `FIND_SOURCES`. A bad value is fatal. A SQLite profile's `store_sqlite.init()` records the store's rows (`DB_PATH`,
   `SEED`, `MEMMODE`) here too, so step 4 prints them (as built in M1).
4. **`app.check(HOSTS, JOBS, BUNDLE_EXTS)`** runs the boot checks of §6.1 per host, including `BUNDLE_EXTS` against the
   embedded bundle's `/* exts: … */` header (D19); `--features`, `--routes` and `--limits` answer here, with every row
   recorded, and exit.
5. **Open the store and migrate per feature** (SQLite profiles only; §11): `store_sqlite.open()` answers `--backup`,
   then reads `DB_PATH` and `MEMMODE`, and one `store_sqlite.migrate` call per store follows, in dependency order;
   `--adopt-profile` acts there, once. A memory profile's `main` has neither call.

Steps 6–10 run inside `app.serve(HOSTS, JOBS, BRAND)`, which returns once the loops run:

6. **Seed unowned stores** (`SEED=1` or `:memory:`), after sweeping stale ephemeral files (12 §1).
7. **Fingerprint assets** (crc32, D19), build the CSP strings per flag combination and the htmx-config meta (§12).
8. **Bind**, retrying for 3 s on `Address_In_Use` (F-12); a listen failure exits non-zero.
9. **Start the loops**: `on_thread_init` (F-4) registers each loop's hub inbox and its heartbeat and watchdog ticks;
   then the watchdog thread, the writer task and the worker pools start, the scheduler with the mounted `JOBS`. After
   `app.serve` returns, `main`'s `start` calls run (ops' 1 Hz publisher, bot's llama health probe).
10. **Print the banner after bind.** The skeleton prints it before (`SK/app/src/main.odin:123`, listen at `:126`), so
    readiness is judged by `/readyz`, never by the log line (13 §3.3).

### 8.7 Drain sequence

A deploy sends SIGTERM, and the process must exit before compose's 10 s `stop_grace_period` ends in SIGKILL. Today
nothing bounds it: 500 SSE + 500 WS exited after 13.2 s (a pending 15 s timer), and a slowloris, a half-sent body or
an idle peer that never answers the FIN each held exit for more than 30 s (13 §4.1). The fork's sequence (13 §4.2):

| # | Step | Deadline |
|---|---|---|
| 1 | Signal: SIGINT or SIGTERM (F-10); a second signal exits now | — |
| 2 | Unready: `/readyz` → 503 with `x-draining: 1`; the accept op is removed; the worker pools stop intake and cancel their queued jobs (503), and in-flight jobs finish: a reply posted after its loop has left faults inside nbio, so every reply must land within one job (S0.5) | at once |
| 3 | Streams: `main`'s `drain` calls run in the order written, each closing its own streams: WS close 1012; SSE gets one event carrying `retry:` with per-client jitter (e.g. 500–3000 ms), sent with `data:` because a lone `retry:` is ignored, then the terminal chunk; multipart gets its closing boundary; bot cancels its generations, and term tells its sessions | ≤ 2 s grace |
| 4 | Idle keep-alive peers, and connections still reading their request line or headers (no handler runs yet; a slowloris looks like this, S0.7): `shutdown(SEND)`, cancel the pending recv, close | ≤ 500 ms |
| 5 | Active requests: wait, then force-close (503 if nothing was sent); each loop also waits for the pool replies it owes (F-13); past the deadline, connections already closing no longer hold the loop | ≤ `DRAIN_DEADLINE_MS` (5 s) |
| 6 | Timers and workers: `on_thread_shutdown` cancels the per-loop timers; the pools stop once their replies are in (step 2); llama streams abort; no thread that sleeps between checks (the watchdog) is joined: it is told to stop, and the process doesn't wait for it (S0.7) | — |
| 7 | Flush: per-thread log buffers, a final metrics snapshot line, store close with a WAL checkpoint | — |
| 8 | Exit 0, or 70 after a dirty crash (§10) | total ≤ 6 s |

In `main` (§7.2; LC §6), `app.wait()` runs steps 1 and 2 and returns, the `drain` calls are step 3, and `app.shutdown()`
runs the rest under their deadlines: the platform keeps the deadlines, and `main` shows who drains what. The total stays
under compose's 10 s and Fly's `kill_timeout` of 10 s (D41). Spike S0.7 proved it on the fork with 500 SSE + 500 WS +
a slowloris + a half body + a stuck idle peer: exit in 5.6 s on Windows and Linux (the half body's 5 s deadline, one
100 ms shutdown tick, at most 500 ms of leftovers), 500/500 WebSockets got 1012 and 500/500 SSE streams their `retry:`
event (`docs/spikes/S0.7.md`). The per-push shutdown-bound drill keeps it true (§19); §20's `promote.ps1` relies on it.

**As built (M2):** the SSE drain event of step 3 is `retry: <500–3000>`, `event: restart`, `data: restarting`: a named
event, so hx-sse applies the delay and swaps nothing; the platform had sent none until slice 13's drill looked for it.

**As built (M2), M1-05.** The SQLite writer refuses new writes from step 2 (503), as the pools do. A reply can still
outlive its loop, a write already on the writer when the loops leave, so a loop marks itself leaving just before it
releases its event loop (the fork's `on_thread_release`, M2), and every cross-thread post (the writer's replies, a
pool's results, the hub's wakeups) goes through `workers.post`, which sends nothing to a loop that has left: the
writer frees those ops instead. The rest of the shutdown is bounded too: `app.shutdown` arms an exit at
`DRAIN_DEADLINE_MS` + 1.5 s, which covers the profile's closes (the writer can wait out `SQLITE_BUSY`) and exits 70,
saying why. The drills' `latewrite` phase holds the writer 2 s across a shutdown: exit 0 at 2.0 s (the process spun
for good on Windows before), and past the bound, exit 70 at 1.7 s.

## 9. Realtime: the hub and the page contract

How server-side events reach browsers. The stream protocols (SSE encoder, WS codec, multipart writer) are §8.2; which
transport a chat room uses is §14; the budgets these numbers feed are §18.

### 9.1 The page contract

D14 fixes what a page may open:

- **At most one SSE stream per page**, at layout level. It carries the member's own topic, presence and the page's
  topics. Unnamed events carry OOB or `<hx-partial>` HTML (badges, toasts, upserts). Named events only trigger refetches
  or a navigation (`resync` refetches a fragment; `kicked` navigates to `/login`); content never rides `event: message`,
  because any named event becomes a DOM event and is not swapped (04 §4.2).
- **At most one `hx-ws:connect` per page**, inside the swapped region (a chat room in WS mode, the terminal, a c4 game),
  so switching rooms opens a fresh socket. htmx never shares a socket between elements, even for the same URL (03 §1).
- **A boosted navigation re-creates `#live`**; the render-time cursor closes the gap (§9.3). Presence is debounced
  10 s so it doesn't flap.
- **Presence follows `pauseOnBackground`** (04 §4.2: a hidden tab closes its streams): online while a stream is open,
  away if it closed less than 5 minutes ago, offline otherwise.
- **Live logs are `<div role="log">` of `<article>`** elements, never `<ul>`/`<li>` or table targets, because
  hx-pending wraps its clones in `<div class="hx-pending" style="all: initial">` (04 §5.5). Live regions exist in the
  initial markup (11 §7.4).

The layout renders the stream element per page (the URL goes through `esc`, so `&` is written `&amp;`):

```html
<div id="live" hx-sse:connect="/events?t=chat.room:12@88200,notify.user:42@5512,chat.presence:12&amp;after=<epoch>-<seq>"></div>
```

`@88200` is the newest rowid the page rendered for a persisted topic and `after` the hub sequence at render time (§9.3).

**Why.** Over HTTP/1.1 a browser holds at most 6 connections per origin, shared by every tab, and each `hx-sse:connect`
holds one for good; WebSockets have their own pool of 255 (03 §9). That bites on the LAN-direct stage 1a; behind NPM's
HTTP/2 (stage 1b on) SSE streams share one connection (08 §3.2). Each WebSocket is its own TCP connection everywhere.

### 9.2 Hub mechanics

`platform/hub` is one cross-thread hub with a shard per event loop (S3, D13):

```
 publisher: any thread (a handler, a write's continuation after commit, a worker, the games poller)
   │  hub.publish(topic, html, rowid = 0, key = "")     key: the .Latest publish key, "" = the topic key
   ▼
 hub mutex (guarded_mutex): take the hub sequence, put a ref in the topic's ring, snapshot the loop inboxes
   │  one refcounted Msg, refs = loops + 1
   ├──► inbox[loop 0]     first message since the last drain → one next_tick_poly(drain, l = loop 0)
   ├──► inbox[loop 1]     already armed → append only
   └──► inbox[loop N−1]
          │ on that loop's thread
          ▼
 drain: swap the inbox buffers, clear armed; per message, encode once per transport (SSE block, WS frame),
        stream_write to this loop's subscribers of the topic, release the ref; then free_all(context.temp_allocator)
```

- **At most one `next_tick_poly` per loop per burst.** nbio's cross-thread queue holds 128 slots and spins when full,
  and posting per message per connection livelocked it (07 §0.2, S3).
- **The hub mutex is a `guarded_mutex`**, so a trap under it is dirty and exits 70. Otherwise SSE delivery silently
  stops while `/healthz` stays 200 (13 §1.3; §10).
- **Subscribing copies the ring refs out under the mutex** and writes the replay after releasing it; 03's prototype
  wrote the replay under the lock (03 §10.5).
- **Persisted topics publish after the writer task commits** and carry the SQLite rowid (12 §9). Memory topics
  publish at once. Ids are never pre-allocated or seeded from `max(id)`: a crash would reuse them and cursors would
  skip messages (D13).
- **Authors get every copy.** The author's reply and the hub's copy carry the same id and dedupe by upsert, so the
  author's other tabs and devices get the message too.

**Topics** are named `<feature>.<family>:<key>` and declared per package in a `TOPICS` table next to its routes, which
the profile mounts per host as it mounts `ROUTES`, with `hub.mount("<host>", ..TOPICS[:])` in `main` (D13; LC §6, §8).
A row is `hub.Topic{family, policy, ring, persisted, perm, allow, replay, deliver}` (as built, M2: D13's `subscribe`
is split into the three it did), for example `{family = "chat.room", policy = .Queue, persisted = true, perm =
.Chat_Read, allow = room_member, replay = room_after}`. A subscription runs the row as a GET runs a route's handler:
the perm, then `allow` for the key (a room's members, a user's own notifications), then for a persisted topic the
keyset replay by rowid (§9.3). A loop joins the hub when it gets its first subscriber, so no thread hook is needed and
a loop with none gets no messages (M2). `deliver`, set only on a server-side row such as `bot.ask`, runs
once per publish (§6.2; **NEW**). `/events` on a host subscribes only to the families its table mounts, so a
houston-lab page can't subscribe to Houston's topics (§7.3; **NEW**). `.Queue` caps each consumer and drops the slow
one; `.Latest` keeps the newest message per publish key and never grows past its ring; `.Sample` drops intermediate
updates while a send is in flight. **As built (M2)**, two more fields: `member` (the family is keyed by the viewer's id,
as `notify.user` is: the layout's `#live` adds it to every page of theirs, `web.render_page(…, live = …)` adds the
page's own, and `/events` refuses it to anyone else) and `watch`, which `/events` calls on the stream's loop when it
subscribes to one of the row's keys and again when that stream ends: chat's presence (§14.1). A stream that wants a
room's messages on a connection of its own (chat's socket and multipart) calls `hub.subscribe` itself, and the hub
writes it a part per message whose `HX-Part-ID` is the rowid it was published with.

| Topic | Policy | Persisted | Carries |
|---|---|---|---|
| `notify.user:<uid>` | `.Queue` | yes (rowid, D13's URL) | the bell list, `.notify-count`, unread badges `.unread-<room>` |
| `home.presence`, `chat.presence:<id>`, `chat.typing:<id>` | `.Latest` | no | who is online; typing expires after 5 s (D30) |
| `chat.room:<id>` | `.Queue` | yes | messages, edits, tombstones |
| `bot.health`, `games.players`, `polls.poll:<id>`, `calendar.event:<id>` | `.Latest` | no | health badge, player counts, poll bars, RSVP counts |
| `games.board:<g>`, `jobs.runs` (publish key = the run id), `uploads.upload:<id>` | `.Latest` | no | top-10 upserts, run progress, upload progress |
| `ops.panel` | `.Sample` | no | the 1 Hz ops render (§15) |
| `lists.list:<id>` | `.Queue` | yes | item upserts keyed `data-pos` |
| `guestbook.queue`, `c4.game:<id>`, `term.session:<sid>` | `.Queue` | no | the moderation queue, spectator moves, watched terminal rows |
| `bot.ask:<room>`, `chat.reply:<room>` | `.Queue` | no | the bot's room mode: the question, to bot's `deliver` row; the finished answer, to chat's, which stores it (§6.2) |

D13 assigns policies by kind (presence, counters, poll bars, progress: `.Latest`; telemetry: `.Sample`); the table
applies that rule where no decision names a topic's policy, and the rest are `.Queue` (**NEW**). `subscribe`'s perm
check is §17's.

**The `.Latest` key** (D13; RESOLUTIONS X8). `.Latest` keeps the newest message per publish key. The default key is the
topic key; a publisher may pass a key, which is the element id the message targets. `jobs.runs` publishes with key = the
run id, so its replay holds the latest row of each run, capped at the ring size.

### 9.3 Ids, resume and the connect procedure

Every SSE event's `id:` is the **hub sequence** `<epoch>-<seq>`, process-wide and monotonic. The epoch is the boot time
in milliseconds, so a restart inside the same second still starts a new epoch: with whole seconds, S0.3's restart spec
got a replay from the new process's ring instead of `resync`. The epoch matters: 03's
prototype restarted ids at 1, so a stale `Last-Event-ID` after a restart never triggered a resync (`resync_events: 0`
in every storm run, 13 §3.6). Persisted payloads carry their rowid in the DOM (`id="m-<rowid>"`, a zero-padded
`data-seq`, because upsert sorts with `localeCompare`, 07 §6.2). The page's stream URL names `topic@rowid` for each
persisted topic and `after` for the hub sequence at render time (PF §6.2).

On connect, after every topic row's `subscribe` perm check passes (one failure answers 403), D13's procedure:

1. a `Last-Event-ID` from this epoch still inside the rings → replay from the rings;
2. otherwise an `after` from this epoch inside the rings → replay from the rings (this closes the gap between render
   and connect on every boosted navigation that re-creates `#live`);
3. otherwise (a foreign epoch after a restart, or a gap older than a ring) → for each `topic@rowid`, a keyset replay
   from the owning feature's store (`id > ? ORDER BY id LIMIT 200`); more than 200 missing, or any memory topic →
   `event: resync` for that topic, which the page answers by refetching its fragment (`hx-trigger="resync from:body"`).

Duplicates from an overlap are harmless: every live element has a stable id and is swapped by upsert or by id, and
resync is the always-correct fallback (R19). Per-room transports resume their own way: on every (re)connect a WS page
sends the room's version it has seen (`#ver-<room>`, which every message fragment keeps current) and gets what changed
since, or the last 50 replacing its log when the room let some of that go (M2-31, as built in M3); SSE's resync asks
`/since?ver=` the same way (M2-35); multipart resumes by `HX-Last-Part-ID` (a rowid or a hub sequence); polling
uses the ptag as the cursor (the last rowid, 304 when nothing is new). The cursor design is **NEW, UNVERIFIED until the
M2 resume specs**, including one across a server restart (§19).

### 9.4 Limits and liveness

| Limit | Value | When hit |
|---|---|---|
| queued bytes per stream | 256 KiB (`STREAM_MAX_QUEUED`) | the consumer is closed as `Too_Slow`: SSE ends; WS closes 1013 when the next frame would pass the cap and is cut after 2 s if it doesn't read (S0.3); both resume |
| queued bytes in total | 64 MiB (`STREAM_QUEUED_TOTAL`) | new streams get 503 |
| streams per user / per client / total | 8 / 16 / 8192 (`STREAMS_TOTAL` ≤ `MAX_CONNS`) | the new stream is refused with 503 (03 §7) |
| message size | 64 KiB | publish rejects it; a WS frame past it closes 1009 |
| stream connects | 20 per minute per client id (`STREAM_CONNECTS`) | 429 with `Retry-After` |
| heartbeat | one timer per loop, every 20 s: `: hb` for SSE, a ping for WS; under NPM's 90 s, Fly's 60 s and Cloudflare's 125 s idle cuts (S20, 08 §0) | dead peers surface as send errors |
| WS pong deadline | 45 s | the socket closes |
| replay ring | 256 per topic (`HUB_RING`), at most 1 MiB (`HUB_RING_BYTES`, M2); a topic with no publish for 10 min lets its ring go | older gaps go to keyset replay or resync |

| Close code | Used for | hx-ws reconnects? |
|---|---|---|
| 1008 | policy: revoked auth, a kick, a frame flood | no |
| 1009 | a message over 64 KiB | no |
| 1011 | a pure-zone crash in that stream (§10) | yes |
| 1012 | drain and restart (§8.7) | yes |
| 1013 | a slow consumer (`Too_Slow`) | yes |

hx-ws reconnects only on 1001, 1005, 1006 and 1011–1014 (03 §7; 04 §4.4), so 1008 and 1009 stop a client for good and
the rest bring it back with htmx's backoff (500 ms doubling to 60 s, ±30 % jitter; 03 §1, 04 §4.2). WebKit on Linux
(libsoup) takes 1012–1014 for protocol errors and hands the page 1006, which reconnects all the same. A kick or role
change publishes a revoke that closes the affected streams with 1008 (07 §1.5). An SSE stream gets the named event
`kicked` instead, which triggers a full navigation to `/login` and so removes `#live`, and a reconnect without auth
gets a 403. `revoke.spec` (M4) asserts that the server sees at most 3 reconnects in 30 s; whether hx-sse itself stops
retrying after a 403 is **UNVERIFIED (M4)** (RESOLUTIONS X19; §19.1.3).

### 9.5 Measured costs

From 03's prototype on Linux (`-o:speed`, 4 loops, one Node client over the WSL NAT; client-bound, so upper bounds) and
13's storm test (client and server on Linux loopback):

| Measurement | Result | Source |
|---|---|---|
| RSS per open SSE stream | about 5.2 KiB (4000 streams: 48.3 MB against 26.6 MB idle) | 03 §10.4 |
| SSE fan-out, 1000 subscribers × 50 publishes | p50 60 ms, p99 74 ms | 03 §10.4 |
| SSE fan-out, 3000 subscribers | p50 68–114 ms, p99 115–188 ms | 03 §10.4 |
| WS chat, 1000 sockets × 20 messages to all | done in about 1.6 s | 03 §10.4 |
| leak check, 3 × 3000 SSE and 3 × 1000 WS opened and closed | RSS flat at 26.6 MB | 03 §10.4 |
| reconnect storm, 2000 SSE + 2000 WS, restart 0.2 s after `kill -9` | 4000/4000 back by 1.475 s | 13 §3.4 |
| the same with a 1.5 s gap | all back by 4.1 s | 13 §3.4 |

After a short gap the 1000-entry listen backlog drops SYNs that retransmit after about 1 s, hence the 1.43–1.48 s
cluster (13 §3.4). Windows put every connection on one loop (03 §2.1, §10.4), so fan-out and cross-loop claims come
from the Linux leg only (R3); `tools/streamload` replaces the client-bound Node clients in the gates (§19).

## 10. Crash model and operability

What happens when code fails, and how Alex sees it. The fork's guard hook (F-5) and the drain sequence are in §8; the
crash drills that keep this true are in §19.

### 10.1 Why containment is narrow

Odin has no `recover`. `Assertion_Failure_Proc` is `-> !` (noreturn), and bounds checks are contextless: they print a
line and trap without consulting `context`; divide-by-zero traps with SIGILL and a nil dereference faults (13 §1.1).
Without a guard, one bad request kills every loop of the process (02 §1.3, F2), and F1 does it with one
unauthenticated packet (02 §1.2).

The mechanism itself works. A `setjmp` in a guard frame, `context.assertion_failure_proc` → `longjmp`, and a trap
handler (a vectored exception handler on Windows, `sigaction` on an alternate stack on Linux) caught all 15 crash kinds
on both OSes, and 4 threads × 20,000 recoveries each never failed (13 §0, §1.2). But `longjmp` skips every `defer`, so a
recovery can leave the process worse than a crash (13 §1.3):

| What the crash interrupted | State after the jump | Consequence |
|---|---|---|
| a `sync.Mutex` / `RW_Mutex` taken with `lock; defer unlock` (the skeleton's store lock) | still held | the 500 goes out, then `/healthz` and every bystander hang forever with the process alive: no restart policy fires |
| the hub mutex | still held | `/healthz` stays 200 while SSE delivery silently stops; the producer blocks forever |
| deferred `sqlite.reset(stmt)` and `free` | skipped | a statement left mid-step; leaked resources |
| `context.allocator` allocations | leaked | a slow leak per crash |
| nbio ops the handler posted (a timer, `http.body`, a dial) | still pending, pointing into an answered response | a use-after-free crash 200 ms later |
| a crash in a stream callback (`on_data`) | outside any middleware guard | the process dies, all streams dropped |
| a crash inside odin-http (F1) | outside an app-level guard | the process dies |
| the connection's temp arena | intact | fine: freed after the 500 |

### 10.2 The design

The guard may continue only where nothing shared was touched; everything else exits and restarts. D15's rules, in
substance (S5, 13 §1.4, §6.3):

1. **Guard every entry point**: every completion callback the fork owns (F-5), the hub drain, app timers, worker tasks
   (argon, query, llama, jobs) and the writer task. Linux binds glibc `_setjmp` with `sigaction` and a lazily set
   per-thread `sigaltstack`; Windows uses a vectored exception handler and `_resetstkoflw` (without it a second stack
   overflow kills the process, 13 §1.2). Odin does not mark `setjmp` returns_twice, so the guard is formally UB: the
   guarded frame stays trivial, with volatile loads after the jump (13 §1.1; R4). The ledger counts it as row 7 (§3.3).
2. **Thread-local counters**, kept by helpers: `locks_held` (from `guarded_mutex`, the only `sync` locks allowed,
   enforced by `tools/check locks`), `async_posted` (ops posted by this callback) and `in_sqlite` (incremented around
   every call into SQLite by `platform/sqlite`).
3. **Classify on a trap.** Dirty if `locks_held`, `async_posted` or `in_sqlite` is above zero; a trap inside SQLite's C
   code is never pure (13 §1.4, §2.1). Dirty → answer 500 if possible, log, drain, **exit 70**. Pure → answer 500 (or
   close that stream with 1011), log `ev=crash zone=pure`, count `app_guard_recoveries_total`, keep serving; every
   statement on this loop's reader connection is reset before its next use (walk `sqlite3_next_stmt`, `sqlite3_reset`
   each), because the jump skipped the deferred resets and an unreset reader statement pins the WAL without bound (12
   §10). The reset is pulled, not installed: `platform/store/sqlite` compares guard's per-thread recovery count before
   each use of the loop's reader and on a 1 s timer that the reader's first use arms on its loop (it stops re-arming
   once the server drains), and resets when it has moved, so `guard` never calls into SQLite and a memory profile
   links none (LC §5). The timer is S0.6's finding: a loop that crashed and then got no more reads kept its snapshot,
   and the WAL grew 165 MB in 5 s of writes; with the timer it stays flat on both OSes. More than 100 pure recoveries in 60 s counts as dirty, because each one leaks its
   `context.allocator` allocations (**NEW**).
4. **Watchdog thread**: wakes every 1 s; a loop whose `tick_age` exceeds 10 s, or the store write lock held for more
   than 5 s → log `lvl=fatal`, flush logs, write `/data/last-crash.txt` (shown on `/admin/ops` after the restart),
   exit 70. It turns every hang in the table above into an exit.
5. **Supervision**: compose `restart: unless-stopped` and `init: true`; `setrlimit` NOFILE soft = hard at boot and
   compose `ulimits: nofile: 65536`; bind retry for 3 s (F-12).
6. **Remotely triggerable crashes are fixed regardless**: F1 (F-6), enum columns read through `store.enum_from_int`
   (02 F3), the markdown depth cap of 32 and input cap of 64 KiB (06 §3.2; 13 §2.1), the accept panic (F-8), the
   strict WS codec. The guard is defence in depth.
7. **Zones by counters, not declarations**: the markdown, form, frame and multipart parsers, the terminal's grid-frame
   decoder and the cursor parser hold no lock, post no op and stay outside SQLite, so a trap in them is pure; a trap
   inside SQLite is dirty because `in_sqlite` says so. No package declares a zone (`Module_Ops.zone` is gone, LC §14).
8. **Always log what died**: the trap handler writes one line of its own (signal or code, thread, route, request id)
   and a `core:debug/trace` capture for assert and panic. Release builds keep a split debug file per `VERSION`
   (13 §3.2).

**Costs.** On the happy path the guard is one jump-buffer save: glibc `_setjmp` at 3 ns on Linux (plain `setjmp` costs
298–518 ns, because it saves the signal mask with a syscall) and `libc.setjmp` at 35–73 ns on Windows (13 §1.5). A
recovery averages 1.15 µs on Linux and 15.7–17.4 µs on Windows (4 threads × 20,000, 13 §1.2). k6 on `/ui/ping`
(Windows, median of 3) read 49.3k rps with the guard against 48.7k without, inside the noise (13 §1.5).

Rejected (D15): a middleware-only recover (Odin has none), unlocking and continuing after a dirty trap, and one guard
around `nbio.tick`, which may leave completions unconsumed (13 §1.3).

### 10.3 Supervision facts

| Fact (13 §3) | Consequence in the design |
|---|---|
| Docker outside Swarm never restarts an unhealthy container (moby#28400, open since 2016); health is only a status | the in-process watchdog turns hangs into exits |
| The restart backoff is 100 ms doubling to 60 s, reset only after ≥ 10 s of uptime | a repeated poison request costs up to 60 s per cycle: contain pure crashes, harden inputs |
| The container fd limit is soft 1024 by default (Docker 29.9.1 on the dev PC; apollo's Docker `<APOLLO_DOCKER_VERSION>` UNVERIFIED): 1,012 streams served, then accepts stop and `/healthz` times out | `setrlimit` soft = hard, compose `nofile: 65536`, `MAX_CONNS` = soft − 64 answering 503 (F-8) |
| After `kill -9`, an immediate restart fails with `Address_In_Use` on Linux io_uring (cause UNVERIFIED) | bind retry for 3 s (F-12); a listen failure exits non-zero |
| Unguarded `-o:speed` crashes print one line for assert, panic and bounds, and nothing for divide-by-zero or nil (exit 132 or 139) | the trap handler writes its own line; release symbols kept per `VERSION` |
| `restart: unless-stopped` restarts after exit 0 or 70 | drain-and-exit is enough; no autoheal and no Docker socket |
| Spawn to serving: 2.6–2.7 ms (prototype, Linux); the skeleton's banner on Windows at 16.9–57.3 ms (`:memory:`) and 21.4–34.7 ms (20k-row file DB) | restart is cheap; readiness is `/readyz`, not the banner (§8.6) |

### 10.4 Observability

**Access log.** logfmt, one line per event, built in the request arena and appended to a per-thread 64 KiB buffer that
flushes at 56 KiB, 1 s after the last flush, on drain and from the crash handler. It costs 0.15–0.84 µs per line
against 5.7–106 µs for the skeleton's `log.infof` line (13 §0, §5.1). Lines lost on SIGKILL are at most 1 s or 56 KiB
per thread.

```
ts=1792928474803 lvl=info mod=http ev=req id=4d48cf84-03-1a2b m=GET route=/contacts/:id st=200 us=183 loop=3 cid=9f2c1e0a
ts=… lvl=error mod=guard ev=crash id=… route=/wiki/:slug kind=bounds zone=pure action=500
```

`route` is the registered pattern (bounded cardinality; the example abbreviates the Lua patterns of §8.3 as `:id`
and `:slug`); `cid` is the hashed client id, never the raw IP; request ids are `<boot>-<loop>-<seq>` (§8.4);
`/healthz`, `/livez` and `/metrics` log at debug (13 §5.1).

**Metrics.** Per-thread counters in a thread-local block, summed on scrape with relaxed atomic loads: 6–50 ns per
request, against 97–121 ns for shared atomics under 8 threads (13 §5.2). Route ids are keyed once at boot, when
`app.check` reads each host's mounted tables, so nothing is looked up per request. Families cover HTTP, connections per
loop, streams and the hub, the store, workers, the process (`app_loop_tick_age_seconds`, `app_guard_recoveries_total`)
and modules. `platform/obs` keeps the registry and the health state, and `platform/web` serves the routes over them
(§5.1). `/metrics` serves Prometheus text (`text/plain; version=0.0.4`) to an Admin session or the bearer token in
`METRICS_TOKEN_FILE`; NPM never exposes it. The same registry feeds the in-app `/admin/ops` dashboard (§15). There is no
Prometheus or Grafana for now (Q25).

**Health.**
- `/livez`: no locks, no I/O; 200 if every loop ticked within 5 s. The in-binary `--healthcheck` probes it.
- `/readyz`: the store ping by try-lock with a 100 ms deadline (never a blocking lock: the hang above), migrations
  done, not draining, critical modules up; otherwise 503. `/readyz?detail` lists each module's state.
- `/healthz`: the skeleton's contract, body exactly `ok`, exempt from redirects and auth (§8.4).
- Optional backends (llama, the Pi agent) report `degraded` and never fail readiness (13 §5.3).

**Profiling and clocks.** spall is compiled in only with `-define:PROFILE=true`: 47 ns per request on 1 thread, 127 ns
on 8, about 67 B per request, captured in time boxes from an admin toggle (13 §5.4). Odin's `time.now` and
`tick_now` on Linux are raw syscalls (324–377 ns) against 19 ns for glibc's vDSO `clock_gettime`, so `platform/sys`
binds `clock_gettime` and the logger reads the wall clock once per flush (13 §5.5).

**The operability contract** (13 §6.1; LC §5). There is no `Module_Ops` struct. Each feature pushes its health,
metrics and limits to `platform/obs` by direct calls, and `main` calls its `drain` (§8.7):
- its `init` declares every cap and timeout by name, value and unit, which boot prints, `--limits` lists and
  `/readyz?detail` shows;
- it sets its health when that changes, a `Health` value, never through a call that could wait on a lock; the store
  marks itself critical, so its `Down` answers `/readyz` 503, and optional backends report `Degraded`;
- its counters are obs's per-thread families under its `mod=` name, and other packages' numbers it shows (SQLite's,
  for `ops`) are pushed by their owners (§5.1);
- its `drain` stops new work and tells clients (1012, SSE `retry:`) without blocking; resources go with the platform's
  flush (§8.7 step 7).

Pure or dirty is the guard's counters' call (§10.2 rule 3), not a declared zone.

```odin
Health :: struct { state: enum { Ok, Degraded, Down }, since: time.Time, message: string }   // what a feature pushes
```

| Module | Limits it declares (summary of 13 §6.1) | Drain |
|---|---|---|
| http (fork) | 8000 B headers, F-7's timeouts, `MAX_BODY` and per-route caps, `MAX_CONNS`, listen backlog | stop accept; idle close with recv cancel; Active deadline |
| streams + hub | 256 KiB per stream, the global ceiling, stream caps, heartbeat, pong deadline, 64 KiB messages, ring size | 1012 / SSE retry, 2 s grace, cancel timers |
| store | `busy_timeout` 5000, lock-wait p99 alert at 50 ms, reader count | stop writes, checkpoint, close |
| llama, terminal, workers, auth | connect / first-token / idle deadlines; bytes/s and sessions; pool size, queue cap, task deadline; concurrent argon verifies | abort streams; a "restarting" line; stop intake |

Global: `DRAIN_DEADLINE_MS` 5000, watchdog stall 10 s, NOFILE raised at boot, bind retry 3 s. After a watchdog exit,
`/admin/ops` shows `/data/last-crash.txt` (D15); after any crash, the split debug file for that `VERSION` resolves the
logged `exe+offset` frames offline (13 §3.2).

## 11. Data: store v3, memory mode, migrations, retention, search and backups

How features persist: `platform/store/sqlite` (store v3), `platform/store/memory`, the per-feature migration runner,
retention, FTS5 and backups. The parity rule these numbers must pass is §18; the hub that publishes after commit is §9.

### 11.1 Store v3

D16 (S8, 12 §9):

- **Connections.** One writer connection under a `guarded_mutex` with `BEGIN IMMEDIATE`; one read-only connection per
  nbio loop, opened lazily through `@(thread_local)` (no init hook needed, 12 §2; as built in M2, a handler's reads
  share one read transaction, begun at its first read and committed when the handler returns: one WAL read lock where
  each statement took one, +2.1 % on `pages` on the Linux leg, M1's profile follow-up); `SQLITE_DBCONFIG_ENABLE_QPSG`
  (1007) on every connection before any prepare; WAL, `synchronous=NORMAL`, `journal_size_limit=64 MiB`,
  `busy_timeout` 5000. Several writer connections were rejected: 1.23M `SQLITE_BUSY` errors in 4 s (12 §3.4).
- **The writer task.** A dedicated thread with a bounded queue commits whatever is queued as soon as it is free, up to
  100 items per transaction (chat messages, receipts, notifications, audit rows, the skeleton's request writes), and
  posts each write's continuation back to its originating loop, with one `next_tick` per loop. It has no timer: a 10 ms
  tick would add up to 10 ms to every request write (S0.4). The continuation is a named proc in the feature's web package, which publishes the persisted
  topic, so `platform/store/sqlite` never imports `hub`; a memory store calls it at once (LC §8). The writer queue,
  pool depth and `sqlite3_db_status` numbers are pushed to `platform/obs` on the store's own timer (LC §5).
- **The query pool.** Two threads for anything that scans, ranks, exports, backs up or can hit a budget (bm25, dbview,
  `VACUUM INTO`, retention chunks). The handler calls `http.response_defer`; results return through
  `nbio.next_tick_poly(l = loop)` and `http.response_resume`, whose generation check (F-13) makes a client that left
  mid-query cost a map lookup, never a use-after-free; a full queue answers 503.
- **Chunked deletes** of 1,000 rows per transaction on the writer task (one 100k-row delete held the writer 330 ms,
  12 §3.2); **a sort index per list sort key**; **keyset paging** for history and infinite scroll.
- **Write ops** (M1). A write is a `store.Op` (in `platform/store`, so `models` describe one without importing
  SQLite): the feature's store sets its `run`, the caller its `done`, and the SQLite family runs it in the writer
  task's next batch while the memory family runs it at once. An op owns its memory (`store.new_op` allocates it with a
  block for its strings, `free_op` from `done` releases both), because it can outlive its request: a peer that leaves
  closes its connection, and the request arena with it, while the write is still queued.
- **Statements per connection** (M1). A feature's store reads with `read(SQL)` … `defer reset(q)` and writes with
  `writer_stmt(SQL)` inside its op's `run`; each connection prepares a statement on first use and keeps it, keyed by
  the SQL string's address, so SQL is a constant or a string built once at init, never one built per call.
- **Close is `main`'s call** (M1). `platform/app` never imports SQLite, so a SQLite profile's `main` calls
  `store_sqlite.close()` after `app.shutdown()`: the writer commits what is queued, every connection closes, and the
  last close checkpoints the WAL (§8.7 step 7).
- **Statement discipline.** Every step is followed by `defer sqlite.reset`: an unreset statement on a loop's reader
  holds its snapshot open, and the WAL grows about 5.4 MB per second at 3.2k msgs/s (12 §3.3; hence §10's reset).
  `synchronous=NORMAL` survives a process crash; only a power loss or an OS crash loses the last commits (12 §3.1).

| Measurement (dev PC, Windows) | Result | Source |
|---|---|---|
| v3 at 16 loops, 200 VUs, read scenarios | 2.4–4.3× HEAD; 1.2–2.7× v1.1.1 on a file DB | 12 §0, §2 |
| read p99 | 25–53 ms (HEAD) → 8–25 ms (v3) | 12 §2 |
| `scale@20` (20 VUs, 20k rows) | 668–840 against 150–173 rps (4–5× HEAD) | 12 §2 |
| file-DB writes, every variant | 10.4–10.9k rps: the single writer's commit is the ceiling | 12 §2 |
| blocking, 4 loops, 50 VUs: two inline 2 s queries / a 4 ms scan inline | fast path 51.4k → 28.4k / 11.5k rps; on the pool 51–52k | 12 §4 |
| chat inserts, file WAL | NORMAL: autocommit 18–19k msgs/s, 10 per transaction 56–59k, 100 per transaction 131–163k; FULL autocommit 936/s | 12 §3.1 |

### 11.2 SQLite build flags

`-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_THREADSAFE=2 -DSQLITE_DEFAULT_MEMSTATUS=0
-DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_FTS5` (S10, D16):

| Flag | Measured effect (12 §8) |
|---|---|
| `DEFAULT_MEMSTATUS=0` | a sorting query on 16 per-thread connections: 216k → 886k q/s (4.1×), because every `sqlite3_malloc` otherwise takes one global mutex. It disables `sqlite3_memory_used`, so the ops dashboard reads `sqlite3_db_status` |
| `THREADSAFE=2` | no scaling gain alone; −15 to −20 % per call on several queries; safe under "one connection per thread, the writer under a mutex" |
| `DQS=0` | the skeleton's store tests pass: no double-quoted string literals in its SQL |
| `DEFAULT_FOREIGN_KEYS=1` | no cost measured; every connection (readers, the pool, `--backup`) enforces foreign keys |
| `OMIT_LOAD_EXTENSION` | no size change at PE alignment; the Linux lib references no `dlopen`, so `platform/sqlite` drops `system:dl` (on glibc 2.34 and later the skeleton links without it with either lib, S0.11) |
| `OMIT_SHARED_CACHE` | −5,632 B; silently turns a `cache=shared` URI into a private empty database (a trap to document) |
| `ENABLE_FTS5` | +220,160 B (2,440,704 → 2,660,864 B, `-o:speed`); S0.11: +226,304 B on Windows (clang 19), +254,728 B on Linux (clang 18, unstripped) |

The tuned build is 0.96–1.07× the default on the 20-row scenarios (noise) and +26 % (`:memory:`) or +7 % (file) on
`scale@20`. `SQLITE_OMIT_PROGRESS_CALLBACK` stays off: dbview and the pool's budgets use `progress_handler`. Each reader
holds about 1.15 MB of SQLite heap. Spike S0.11 built it on Windows (clang 19, MSVC 19.43) and Linux (clang 18, gcc
13): +192,904 to +228,584 B over the default flags (FTS5 is the whole delta; the other six flags shrink the binary), and
the store and views tests and a smoke pass on every build. `prepare.{sh,bat}` hold the flags in one `SQLITE_FLAGS`
string (`cl` accepts `-D` too), compile with `cl /O2 /MT` or, when `cl` is missing, `clang -O2 -fms-runtime-lib=static`
and `llvm-lib`, and write the flags to `vendor/sqlite/.flags`, so a flag change rebuilds the lib (today's "lib newer
than source" check would keep the old one). The Linux margin is thin (clang 18: 1,416 B under 230,000 B; the production
image's clang is measured by M1's docker job), and §18.4's 2.75 MB budget is a Windows figure: the tuned skeleton is
2.66 MB on Windows and 2.77 MB unstripped on Linux (`docs/spikes/S0.11.md`).

### 11.3 `MEMMODE` and `:memory:` parity

A plain `:memory:` database is private to its connection, so it can't serve per-loop readers. Shared cache serialises
readers and fails the writer with `SQLITE_LOCKED` (6 writes succeeded against 133k errors); memdb has no WAL, and a
writer starves new readers to 393 reads/s; both are rejected (12 §1). One vocabulary remains (D16): `single` is one
in-RAM connection whose reads take the writer lock (the skeleton's model); `ephemeral`, the default, is a WAL temp file
swept at boot, which runs the production code path.

S18's both-stores requirement stands, but no measured mode passes every `:memory:` cell (12 §2, 16 loops, 200 VUs,
against v1.1.1; D17):

| Cell | v1.1.1 | HEAD | single + QPSG | ratio | v3 ephemeral | ratio |
|---|---:|---:|---:|---:|---:|---:|
| list | 39,301 | 10,225 | 21,502 | 0.55 | 37,648 | 0.96 |
| pages | 36,267 | 13,506 | 20,862 | 0.58 | 32,990 | 0.91 |
| write | 38,908 | 36,172 | 35,753 | 0.92 | 12,756 | 0.33 |
| mixed | 28,782 | 13,883 | 22,025 | 0.77 | 37,150 | 1.29 |

Spike S0.4 measures every `:memory:` cell, with the sort indexes installed (they add write cost), for three candidates:
- **A**: `single` + QPSG + sort indexes + a dashboard aggregate cached for 1 s (12 §2.1, §9); the cache makes the
  dashboard lag a write by up to 1 s (0.3–0.7 s in S0.4's smoke), which the e2e `dashboard` spec can see.
- **B**: `ephemeral` + sort indexes + the temp file on tmpfs (`/dev/shm`) on Linux, unsynced (as built, in an
  `odin-htmx-starter/` directory of its own there or in the temp directory: boot sweeps it, and listing a Windows temp
  directory of 3,900 entries took 170 ms of a 50 ms boot budget). Research 12's ephemeral
  numbers already ran the file with `synchronous=OFF`, and WAL's `NORMAL` never syncs a commit, so on Windows B is v3
  with the sort indexes: tmpfs is its one new lever (S0.4).
- **C**: B + group commit of concurrent skeleton writes on the writer task (§11.1: whatever is queued, as soon as it is
  free, up to 100 per `BEGIN IMMEDIATE` transaction, with each row read back inside it); each write handler answers
  through F-13's deferred response after its batch commits (S0.4).

**Decision rule.** The first candidate that passes every `:memory:` cell under D38's rule on both legs becomes the
`skeleton` profile's default. If none passes, Q6 applies before M1; its default gates the failing `:memory:` cells
against HEAD with a documented exception and never waives a file-DB cell.

**What S0.4 found, and what Alex chose** (`docs/spikes/S0.4.md`; ANSWERS round 5, 2026-10-26). None passes every cell.
**C is chosen**: the `skeleton` profile runs store v3 with the sort indexes, `MEMMODE=ephemeral` unsynced (on
`/dev/shm` on Linux) and group commit through the writer task. On Linux, where the noise band is about 2 %, C passes
search, api, detail, mixed and scale@20 against max(HEAD, v1.1.1) and misses pages, list and write by 4–9 %, because
v1.1.1 sorts its 20 rows in Odin straight from RAM; those cells are gated against HEAD, each with a documented
exception in `tests/parity-waivers.txt` (Q6's answer). C's write handlers answer after the batch commits, through
F-13's deferred response. The file DB takes C too (R2a): v3's file-DB write measured 0.38–0.43× v1.1.1, C's 2.9–4.3×. No 1-loop leg is added: at one loop
every variant is below v1.1.1 on list, pages and write (file-DB write 6,683 rps for v3 against 7,501; 12 §2).

### 11.4 Optional SQLite

**The provable claim (D18):** a profile built with `-collection:store=app/stores/memory` and the `envadmin`, `nick` or
`anonymous` identity, whose `main` doesn't import `platform/store/sqlite`, builds from a checkout where prepare's
SQLite step never ran and no sqlite3 library exists (LC §15). It still needs the platform linker (`clang` or
`$ODIN_CLANG_PATH` on Linux and macOS, the MSVC/SDK libraries on Windows; 09 §6.1): an unreferenced foreign library
never reaches the linker, and an imported but uncalled package costs about 512 B (09 §4.1). LC §16 showed it with a
real static library standing in for SQLite: `streams`' linker line ends at `kernel32.lib` and its executable holds
none of the library's marker, while `full`'s line ends with the library. CI builds `minimal`, `streams` and `lab` that
way (§20). Features whose value is persistence are absent from memory profiles: contacts (and dashboard, which
imports it), gallery, the `accounts` identity, the `/admin/audit` page, find's FTS, dbview and term. A store with no
memory member has no directory in `app/stores/memory/`, so a memory build that reaches one fails to compile ("Syntax
Error: Path does not exist: store:contacts", LC §16): D18's refusal, made by the compiler, and the generator refuses
first, with advice (§7.4). Adapted from RF §7.3:

| Feature | Memory behaviour | SQLite behaviour |
|---|---|---|
| notes, notify, polls, lists, calendar, guestbook, jobs | maps and rings behind guarded locks, ids `<epoch>-<seq>`, lost on restart | tables, rowids |
| chat | seed rooms, DMs on demand; the ring is the history; `contains_ci` search; the UI says "ephemeral mode" | retention per room kind, FTS, resume across restarts by rowid |
| bot conversations | a per-session ring of the last K turns (12 §6; K = 8 in RF §7.3) | stored for their owner only (Q20) |
| identity | `envadmin` (one admin, signed cookie), `nick`, `anonymous` | `accounts`: users, sessions, invites, TOTP, `accounts_prefs` |
| audit | the memory audit store writes one `mod=audit` log line per `store:audit` call | `audit_log` and `/admin/audit` |
| uploads | the memory store: session rows in memory, lost on restart, so no resumable uploads | the SQLite store: `uploads_blobs` and `uploads_parts`; resumable uploads need it (RESOLUTIONS X13) |
| video | the memory store, `catalog_file`: a read-only manifest scan | library, visibility, watch progress (video metadata only; upload rows belong to `uploads`, X13) |
| wiki | the memory store, `source_files`: read-only embedded docs | editable pages, revisions, FTS |
| find | `contains_ci` over the memory sources | FTS5 per feature, bm25 on the pool |
| contacts, dashboard, gallery, dbview, term | not offered | full |

### 11.5 Schema sketch

Tables are prefixed with the feature name, except the legacy skeleton tables (`contacts`, `events`, `notes`) and
accounts' `users` and `sessions` (D16); the members' preferences table is `accounts_prefs`, owned by `accounts`
(RESOLUTIONS X9). Ids are rowids; times are unix ms. `→` marks a foreign key, and every one stays inside its feature:
other features store a user id as a plain integer plus an `author_name` snapshot taken at write time, and deleting an
account is a soft disable, so nothing cascades (D6). Names are indicative; each README's Data heading holds the real
schema.

```sql
schema_migrations(feature, seq, name, sha256, applied_at, PK(feature, seq)) WITHOUT ROWID   -- platform (12 §5)
schema_meta(key PK, value) WITHOUT ROWID   -- app, profile, adopted_from; PRAGMA application_id = 0x4F485354
contacts, events (migrations 0001–0003, hashes kept) + 0004_sort_indexes; notes            -- skeleton features
  -- in full: houston-lab's demo data, capped by CONTACTS_CAP and NOTES_CAP and reset nightly (§11.6)
users(id, username UNIQUE COLLATE NOCASE, display, pw_hash, role, disabled_at, totp_secret, failed_logins, backoff_until, …)
sessions(token_hash PK, user_id → users, created_at, last_seen, expires_at, step_up_at, client_id) WITHOUT ROWID
accounts_invites(code_hash PK, role, max_uses, uses, …); accounts_recovery_codes(user_id → users, code_hash, used_at)
accounts_prefs(user_id → users, key, value, PK(user_id, key)) WITHOUT ROWID      -- theme, chat transport, mutes
audit_log(id, at, actor_id, actor_name, action, target_kind, target_id, reason, client_id, meta)  INDEX(at)
  -- triggers: BEFORE UPDATE → RAISE(ABORT); BEFORE DELETE WHEN old.at > now − 400 d → RAISE(ABORT)
chat_rooms(id, kind, slug UNIQUE, title, cap_messages, cap_age_s, slow_mode_s, locked, created_by, created_at)
chat_members(room_id → chat_rooms, user_id, role, last_read_id, muted_until, PK(room_id, user_id)) WITHOUT ROWID
chat_messages(id, room_id → chat_rooms, user_id, author_name, at, body, edited_at, deleted_by, pinned, blob_sha)
  INDEX(room_id, id), INDEX(at)
chat_fts USING fts5(body, content='chat_messages', content_rowid='id', tokenize='unicode61 remove_diacritics 2')
  -- AFTER INSERT/UPDATE/DELETE triggers; every feature with a `search` source on SQLite has the same shape
notify_items(id, user_id, kind, ref_kind, ref_id, html, at, read_at)  INDEX(user_id, id)
uploads_blobs(sha256 PK, mime, bytes, width, height, uploader, at); uploads_parts(id, user_id, size, received, state)
  -- owned by uploads, through app/stores/sqlite/uploads (X13)
bot_conversations(id, user_id, title, created_at, updated_at); bot_messages(id, conv_id → bot_conversations, role, …)
wiki_pages(id, slug UNIQUE, title, visibility, md, html, rev, author_name, updated_at); wiki_revs; wiki_fts
lists_lists, lists_columns, lists_items(id, list_id, column_id, pos, text, done, assignee, …)
polls_questions, polls_options, polls_votes(poll_id, user_id, option_id, at, PK(poll_id, user_id, option_id))
calendar_events(…) INDEX(starts_at); calendar_rsvps(event_id, user_id, answer, …); calendar_feeds(user_id, token_hash)
guestbook_notes(id, name, body, at, status, client_id, reviewed_by, reason)  INDEX(status, id)
jobs_runs(id, kind, state, lease_until, progress, log, created_at, started_at, finished_at)  INDEX(state, id)
video_items(id, sha256 UNIQUE, title, visibility, owner, …); video_renditions; video_tracks; video_progress
term_devices(id, name UNIQUE, token_hash, mode, enabled, last_seen); term_commands(device_id, argv); term_sessions
```

### 11.6 Retention and rolling buffers

| Data | Policy | Mechanism |
|---|---|---|
| chat rooms, DMs and announcements; the in-memory chat ring | per room kind, whichever cap hits first, pinned messages exempt; the ring holds the last 100 per room under `CHAT_RING_BYTES` (Q19; caps and defaults in §14.1) | chunked deletes on the writer task and an age sweep job (§14.1) |
| typing, presence | memory only: typing expires after 5 s; presence debounced 10 s | `.Latest` hub topics |
| notifications; sessions | 200 per user and read ones after 30 d; idle 14 d, absolute 30 d | jobs sweeps |
| bot conversations | kept for their owner until deleted; no cap is decided (Q20 covers privacy only) | owner action |
| guestbook pending notes | expire after 14 days | a jobs sweep |
| audit log | append-only; deletes only past 400 days | triggers plus a jobs sweep |
| term recordings | 30 days or 1 GiB in total, whichever comes first (Q12); the size cap protects apollo's disk (RF §7.2, **NEW**; RESOLUTIONS X10) | a jobs sweep of `.cast` files and rows |
| hub replay rings | 256 per topic (`HUB_RING`); the newest message per publish key on `.Latest` topics | in memory; a new epoch per boot |
| backups | 7 nightly, 5 pre-deploy | jobs and `promote.ps1` (§11.8) |
| houston-lab's demo data (notes; contacts and events) | capped by `NOTES_CAP` 500 and `CONTACTS_CAP` 2000, and reset nightly at 04:00 local time; the `skeleton` profile stays uncapped (RESOLUTIONS X38) | the job rows `notes.reset` and `contacts.reset`, written in `full`'s `routes.odin`: each drops its feature's rows and reseeds them as `SEED=1` does (§7.3; LC §7) |

### 11.7 Migrations

The 12 §5 runner (6/6 tests pass) keys every migration by `(feature, seq, name, sha256)`. Each feature's SQLite store
holds one package-level `MIGRATIONS := [?]store.Migration{…}` (09 §4.4), `#load`ed from
`app/stores/sqlite/<f>/migrations/NNNN_name.sql`, and a SQLite profile's `main` makes one `store_sqlite.migrate("<f>",
<f>_store.MIGRATIONS[:])` call per store, in dependency order (§7.2; LC §6): a package variable named across the
collection, with no wrapper (LC §16). A memory profile's `main` has no such call, and a `migrate` line left in one
doesn't compile; `tools/check profile` requires a `migrate` line for every store with `MIGRATIONS` that a SQLite build
reaches (§6.1). At boot the runner refuses a database that belongs to another application or has user tables but no
bookkeeping. It adopts a skeleton database (709bc94 or v1.1.1) or a spark portal database as a legacy feature with
`schema_version` frozen, so the old binary still recognises it and spark's applied `0001_init.sql` hash stays valid. It
refuses another profile's database unless the binary runs once with `--adopt-profile`, refuses foreign or edited
migrations, leaves the rows of features this build doesn't migrate dormant, and applies pending migrations in the order
of `main`'s calls, one transaction each.

Contacts' 0001–0003 keep their hashes and gain `0004_sort_indexes` (D36). Migrations are forward-only and
**additive**, so binary N−1 runs on schema N and a rollback needs no restore (08 §5.5); a destructive change takes two
releases (stop using the column, then drop it). Unit tests run the 6 cases plus real fixture databases (D37, §19).

### 11.8 FTS5 and backups

**FTS5** (D16, 12 §7) uses `unicode61 remove_diacritics 2` over external content kept in sync by triggers, highlighted
with FTS5's own `highlight()`/`snippet()` so the marks match the hits. At 100k messages a MATCH costs 12 µs–2.8 ms
against 46–272 ms for a `contains_ci` scan, and the index adds 5.7 MB (+32 %). Trigram was rejected: its index is 6×
larger. bm25 ranking runs on the pool (26 ms over 34k hits); `optimize` runs weekly through the writer task.
`contains_ci` stays for small tables and memory implementations, and one result list never mixes the two engines:
FTS folds `café` to `cafe` and `contains_ci` does not (12 §7, §10). M8's exit asserts MATCH ≤ 3 ms at 100k messages.

**Backups.** `--backup` runs `VACUUM INTO`, live-safe and refusing to overwrite
(`SK/app/src/repository/db.odin:269-295`), nightly from the query pool as a job (keep 7) and before every deploy from
`promote.ps1` (keep 5, §20). Off-box copies follow Q16: a nightly pull to the dev PC now, a Hetzner Storage Box at
stage 2. A restore drill runs every release. litestream is deferred: its checkpoint coordination is unverified (08 §9).
*Where on apollo (M4-12, Alex's answer, 2026-11-01: "Yes, use the HDD"):* Houston's nightly backups go to
`<APOLLO_BACKUP_DIR>` on apollo's HDD, a different disk from the database's volume and Docker's data-root (the SSD),
through `FULL_BACKUPS` in the stack's `.env` (a bind mount at `/backups`, the directory chowned to `10001:10001`).
The off-box half (Q16's nightly pull to the dev PC) is still open.

## 12. Client stack: bundles, CSP, the 17 extensions, hyperscript and themes

Everything a page runs comes from the binary as a few fingerprinted files, under a CSP that never allows eval. htmx
4.0.0 is the pin (S16); _hyperscript 0.9.94 core is optional per profile (S15, Q7); the `pins` job checks both (§20).

### 12.1 Bundles

**As built (M1).** `prepare.*` builds `tools/bundle` and runs it for every `app/cmd/<p>/` with a `main.odin`, writing
`app/build/<p>/` (`main.js`, `app.css`, `app.js`, each with `.br` and `.gz`); `build.sh` passes
`-define:BUILD_DIR=../../build/<p>` and `platform/web` `#load`s from there under `when #exists`. The stylesheet is the
theme the build reaches plus each reached feature's `static/<f>.css`; a lite theme's is the full one with every
`/* full-only: … */ … /* /full-only */` region cut, so the two never drift. Feature `EXTS` are still empty in M1, so
both profiles' `main.js` is `htmx.min.js` byte for byte.

**One definition** (D19; RESOLUTIONS X29, as LC §12 recasts it). Each feature's web package declares its extensions on
one lint-enforced line, for example `EXTS :: bit_set[web.Ext]{.Sse, .Pending, .Upsert}` in `lists_web`. Switched
implementations declare `EXTS` too, for an extension only that implementation needs: `chat_transport_ws` declares `.Ws`,
`chat_transport_sse` `.Sse`, `chat_transport_multipart` `.Multipart` and `chat_transport_poll` `.Ptag`. `chat_web`,
which imports all four for its switch, unions them into its own `EXTS` with what chat needs whatever the transport
(`.Pending .Upsert .Prompt .Targets .Download`; the last for transcripts, D21, X34), and `bot_web` adds
`.Browser_Indicator`. The profile's `main` names the union once, `BUNDLE_EXTS :: chat_web.EXTS + notify_web.EXTS + …`
(§7.2), and `tools/check exts` requires it to name every mounted package that declares `EXTS` (§6.1). `web.Ext`
(declared in `platform/ext`, L1, and re-exported by `platform/web`; X33) is a closed enum with one table of registration
names (04 §2.2; the member → name list is in §2) and one of file names, so a misspelt extension is a compile error. Each
file is `dist/ext/<extension>.min.js` from the htmx 4.0.0 tarball (04 §1.2), with the extension names of §12.3.

**`tools/bundle <profile>`**, run by prepare: (1) take the package list from the compiler, `./build.sh <p>
-export-dependencies:json`, which resolves the four collections and lists exactly the build's family members (LC §11:
`streams` lists the memory stores, `client/vanilla`, `identity_nick` and `theme/lite` and no SQLite package; `full`
lists the SQLite stores with their migrations), and union the `EXTS` of those packages; (2) concatenate `htmx.min.js` →
`hx-csp` (Scripting only, first among extensions, 11 §8.1) → the other extensions in a fixed order, separated by
`"\n;\n"`, under a header `/* exts: … */`; (3) concatenate CSS (`platform/static/base.css`, the theme, each feature's
`static/<f>.css`) and behaviours (the platform's core set, each feature's `static/<f>._hs`) the same way; (4)
precompress with `brotli -q 11 -f` and `gzip -9 -n -k -f`, which write beside the input. S0.10 settled the details:
Odin exports the package list from `build`, `run` and `test`, not `check`, so the app `#load`s each bundle under
`when #exists(...)` and a build before prepare still compiles, then boot check 6 refuses it ("run prepare"); a test
imports no package that declares `EXTS` beyond what `main` mounts, since `odin build` compiles `_test.odin` files too;
on Linux both compressors are required, and on Windows the tool finds them on the `PATH` or in Git for Windows, which
ships both (a build without them ships the encodings it has), so the files are byte-identical on both OSes; an empty
union gets no header, so `minimal`'s bundle is `htmx.min.js` exactly and boot reads a headerless bundle as the empty
set.

**Assets ride with the package that owns them** (D4): deleting a feature deletes its CSS and `_hs`. The binary `#load`s
identity, `.br` and `.gz`, fingerprints each by the crc32 of its identity bytes (one URL for every encoding) and serves
br > gzip > identity with `Vary: Accept-Encoding`, an ETag per encoding and immutable caching (11 §8.3). Boot refuses to
start ("run prepare") if `main`'s `BUNDLE_EXTS` differs from the header (§6.1 check 6); the check stays fatal (X29).
Compression runs at prepare because Odin has no brotli and gzips only through `vendor:zlib` (a C dependency, 09 §0.8),
and NPM gzips only `text/html`: htmx, `full`'s extensions and hyperscript fall from 249,803 B to 60,161 B br (11 §0).

**Why a bundle is mandatory.** A deferred htmx initialises on a `setTimeout`, so a later extension file misses the
initial DOM (04 §2.3): with separate files a `<form hx-ws:send>` submitted natively in 3/3 runs per engine (Chrome 156,
Chromium 153, WebKit 26.6), and without hyperscript `hx-ws:connect` and `hx-sse:connect` never wired. One bundle
delayed 400 ms: 0 failures (11 §3). S0.10 proved the mechanics: `bundle-race.spec` passed 9/9 per engine in Chromium
153 and WebKit 26.6 with every asset held 400 ms, while the separate-files control failed every run
(`docs/spikes/S0.10.md`); the spec keeps it (§19).

**Page bundles.** `web.Bundle` is `{Main, Scripting, Compat_Htmx2, Compat_Alpine}`. `Main` is the union; the other
three have fixed sets in one table and are built only for a profile mounting `scripting` or `compat` (`lab`, and
`full` for its lab host, ANSWERS F2). Those two web packages say so in one line each, `BUNDLES ::
bit_set[web.Bundle]{.Scripting}` and `{.Compat_Htmx2, .Compat_Alpine}`; `tools/bundle` builds Main plus every bundle a
reached package names, `web.Bundle` and its fixed table live in `platform/ext` beside `Ext`, and `tools/check exts`
covers `BUNDLES` lines too (S0.10). The
layout takes the bundle as a parameter. Links across bundles are full navigations, because a body swap keeps the old
document's CSP and scripts (11 §6.4, 05 §9). **As built (M2):** a page on a fixed bundle links out unboosted (the
layout boosts only on Main), and a boosted request for one (`HX-Boosted: true`) gets `HX-Redirect` to itself from
`web.render_page`, so the browser loads it whole, whichever link it came from; each bundle's htmx-config JSON is
`<bundle>.config.json` beside it, folded into a head constant per bundle. **Hyperscript** is a separate deferred file
after the bundle, using upstream's shipped `.br`: both layouts are race-free, and separate keeps 175 KB cacheable
when the extension set changes, for 1,151 B br more (11 §8.1). **As built (M2):** the fixed bundles came out of the real
packages byte for byte as the fixture had them (Scripting 85,173 B, 25,063 br; Compat_Htmx2 38,466 and Compat_Alpine
38,487 B), and main names the ones its pages load in `PAGE_BUNDLES` (the scripting and compat packages' `BUNDLES`
lines), which boot check 6 holds to the embedded set.

**The htmx-config meta** is generated at boot from the same union as strict JSON (S14; hyperscript `JSON.parse`s it
and dies on HCON, 05 §3), written with `w()`, never `fmt` (`SK/CLAUDE.md` "Views"). It names `hs-include` whenever
the hyperscript client is present: an extension missing from the list registers as nothing, silently (11 §8.2).
`minimal` and `skeleton` keep `{"defaultSwap":"innerHTML"}` (`SK/app/src/views/views.odin:321`); Scripting uses
11 §8.2's verified value (`hx-csp` first, `hs-include`, `"safeEval":true`). `full`'s value (order illustrative;
`full-vanilla` drops `hs-include`):

```json
{"defaultSwap":"innerHTML","extensions":"sse, ws, hx-multipart, hx-pending, browser-indicator, hx-prompt, preload, ptag, history-cache, hx-head, upsert, hx-targets, download, hs-include"}
```

| Bundle | Profiles | Contents | Raw B | br B |
|---|---|---|---:|---:|
| `htmx.min.js` | `minimal`, `skeleton` | htmx 4.0.0, byte-identical to the skeleton's, same crc32 name | 36,716 | 11,736 |
| Main | `full`, `full-vanilla` | htmx + the 13 Houston extensions (§12.3) | 79,790 | 23,022 |
| Main | `streams` | htmx + the profile's derived union: sse, ws, hx-multipart, upsert, hx-pending, ptag, hx-targets, download, hx-prompt, browser-indicator (as built at M2: sse, ws, hx-multipart, hx-pending, ptag, upsert, 68,186 B raw, 19,967 B br) | 71,358 | 20,852 |
| Main | `lab` | htmx + the lab's derived union (S0.10's fixture: 5 extensions; as built at M2: sse, ws, hx-multipart, 65,391 B raw, 19,201 B br) | 71,391 | 20,777 |
| `_hyperscript.min.js` | `full`, `lab` | 0.9.94 core | 175,365 | 39,706 |
| Scripting | `lab`; `full` (lab host only) | htmx + hx-csp + hx-live + sse, ws, hx-multipart, hx-pending | 85,173 | 25,063 |
| Compat_Htmx2, Compat_Alpine | `lab`; `full` (lab host only) | htmx + htmx-2-compat; htmx + hx-alpine-compat | 38,466; 38,487 | 12,180; 12,249 |

Sizes: S0.10's `tools/bundle` over a fixture of the plan's packages, with the real `streams` and `lab` unions as built
at M2 in their rows; hyperscript from 11 §9. Budgets: §18.

Every bundle list is derived from the build, never declared (D24's column is labelled so): `streams` gains hx-prompt
(chat moderation reasons) and browser-indicator (bot generation), the real uses D21 gives them, and every chat
selection ships ws, sse, hx-multipart and ptag, because every chat profile links all four transports (X29's lean
transport sets go, LC §12; §7.4's sample). As built (M2), the four transports' extensions are 28,965 B raw and 8,217 B br
of `streams`' 68,186 and 19,967; hx-prompt, hx-targets, download and browser-indicator join when a package uses them
(moderation and attachments at M6), since the list is derived.

**How an implementation's extensions travel** (RESOLUTIONS X33, X34, as LC §11 recasts them):
- The `Ext` enum and its two tables live in `platform/ext`, an L1 leaf package that imports nothing, and
  `platform/web` re-exports it as `web.Ext`. A switched implementation declares `EXTS :: bit_set[ext.Ext]{.Ws}` (or
  over `web.Ext`, since it may import L3, §5.1). The two names are the same type.
- The web package that switches over its implementations unions their `EXTS` into its own, as `chat_web.EXTS` does
  (§6.1), and `main`'s `BUNDLE_EXTS` unions the mounted packages' `EXTS`. X33's vtable `exts` field and its
  `register()` union are gone.
- `tools/bundle` computes the union from the compiler's package list, and boot compares `BUNDLE_EXTS` with the
  bundle's header: a mismatch is fatal, and means the profile's `main` and its build line disagree, or prepare is stale.
- `chat_web` declares `.Download` for chat's own transcripts (D21), so a selection with chat and without bot still
  ships hx-download.

### 12.2 CSP and headers

**Base policy** (D20, S12): the skeleton's hash CSP verbatim, built once at boot
(`SK/app/src/controllers/middleware.odin:182-205`), with its `nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: strict-origin-when-cross-origin` and `x-version`. `minimal` sends exactly that set (11 §5.2).

```text
default-src 'self'; script-src 'self' 'sha256-<THEME_PREPAINT_JS>'; style-src 'self'; style-src-attr 'unsafe-inline';
img-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'
```

Every other profile adds `Permissions-Policy: camera=(), microphone=(), geolocation=()` (spark's minus
`interest-cohort`, 06 §3.1; never fullscreen, autoplay or gamepad entries: `(self)` on them blocked the games iframe in
Chromium, 11 §3), COOP `same-origin` and CORP `same-origin` (`cross-origin` on `og.png` and favicons), both harmless to
the iframe and its previews (11 §3). That includes `skeleton`: the three extra headers are static boot strings that
change neither cost nor feature set, and its 40-item checklist lists them as intended differences (RESOLUTIONS X35).
Never COEP: it blocked both in Chrome and WebKit. HSTS only at NPM, from stage 2
(§20). `connect-src` stays `'self'` through `default-src`: it covers same-origin `ws:` and `wss:` in Chrome 156,
Chromium 153 and WebKit 26.6 (11 §3), where a fixed `wss://host` would break the LAN-IP stage. Firefox is
**UNVERIFIED (CI `e2e`)**.

**Route flags add to the base** as boot-constant strings looked up in O(1) (11 §6.1); example routes: RF §5.2, D12.

| Flag | Adds | Example routes |
|---|---|---|
| `.Private` | `Cache-Control: no-store`, `X-Robots-Tag: noindex, nofollow`, `hx-history="false"` on `<body>` | `/admin/*`, `/account`, `/login`, chat room pages (one row serves rooms and DMs, §6.1), `/term`, `/bot` |
| `.Frame_Games` | `frame-src <GAMES_URL>` | the games player page (§15) |
| `.Media` | CORP `same-origin`, immutable caching, `Accept-Ranges` | `/media/*` |
| `.Nonce_Csp` | `script-src 'nonce-<16 B>' 'sha256-<prepaint>'` per response, `no-store`, `hx-nonce` stamping | `/scripting/*` only, on the session-free origins: `lab`'s, and `full`'s lab host (ANSWERS F2) |
| `.Stream` | `X-Accel-Buffering: no`, `Cache-Control: no-cache` (D12) | `/events`, every SSE, WS and multipart route |
| `.Lab_Host` | no header: it is a mount rule, checked at boot (§6.1 check 4). The lab host itself never sets a cookie (no identity runs) and sends `X-Robots-Tag: noindex` on every page, since the `lab` profile's origin holds the indexed copy (**NEW**) | every `scripting` and `compat` route (§7.3; ANSWERS F2) |

`.Step_Up`, `.Lan_Only` and `.Lab_Host` are also access rules (§17.2); `.Fragment` feeds `robots.txt` (§6). **The nonce
class**: the CSP is `head ‖ nonce ‖ tail` in the temp allocator, about 182 ns per response (11 §5.2, §6.1). Views emit
a marker `hx-nonce="<%N%>"` that the response writer replaces; the marker contains `<`, so escaped user text can't
forge it (11 §5.3, design only: **NEW, UNVERIFIED (M2)**). `/scripting/tt` adds Trusted Types and loads no hyperscript, which
TT breaks (`put` blocked 12/12 in 3 engines, 11 §2.3). Links never boost into or out of the class.

**Why not app-wide hx-csp** (11 §2, D20): (1) it strips `hx-*` from SSE, WS and multipart fragments even with the
stream response's own nonce, so every fragment would be rendered per subscriber, breaking the hub's encode-once
fan-out (§9); (2) it fails open: an injected, unnonced `hx-sse:connect` or `hx-ws:connect` connected and swapped in
all three engines; (3) it doesn't gate hyperscript's `_`, and its TT mode breaks `put`. `'unsafe-eval'` is never
added; `hx-on`, trigger filters, `js:` values and hx-live live only under the nonce class. **With hyperscript loaded
the CSP changes meaning**: an injected `_` or `<script type="text/hyperscript">` runs (05 §5); the four defences are
in §17.4.

**CSP reports** (D9, D20; RESOLUTIONS X11). `full`, `streams` and `lab` send `Reporting-Endpoints: csp="/csp-report"`
and add `report-to csp` to their CSP (11 §5.1 calls both optional). `minimal` and `skeleton` never do: their CSP stays
the skeleton's verbatim, and `minimal` keeps the skeleton's exact header set. `/csp-report` is a platform route that
logs each report at warn and is rate-limited (§17.5). **As built (M2):** such a profile serves with
`web.Header_Set.Reporting` and mounts `{"platform", web.REPORT_ROUTES[:]}`.

**As built (M2), the nonce class.** The nonce is base64url (16 random bytes), so a page can put it in a connect URL as it
is: `/scripting/streams` sends it as `pn`, and its streams stamp it (11 §2.3's first way). Trusted Types is a route
flag, `.Trusted_Types`, which boot accepts only beside `.Nonce_Csp`; a page under it loads no hyperscript.
`streams-hxcsp.spec` pins 11 §2.2's matrix on the real streams, in Chromium and WebKit: a streamed button works with
the page's nonce or by delegation and is stripped with none or with the stream's own. The fail-open probe came out
narrower than 11 §2.2 found on the pre-release: in 4.0.0 an unnonced `hx-sse:connect` or `hx-ws:connect` that arrives
in an htmx swap is stripped (before-init now fires on it), while one that other code wrote into the page and handed to
`htmx.process` inside a subtree is wired by the extension's after-process hook and connects. The reasons against
app-wide hx-csp stand: streamed fragments are still stripped, that second path is still open, and `_` is still
ungated.

### 12.3 The 17 extensions

Thirteen have real uses in Houston; four are proven on the session-free lab pages with a written reason, in the `lab`
profile and on Houston's lab host, so `full` covers all 17 itself (D21; ANSWERS F2; §7.3). Each has an e2e assertion
on its behaviour (no API lists registered extensions, 11 §8.2); `bundle-race.spec` covers loading (§12.1).

| Extension | Real use in Houston | Lab proof and reason (lab-only four) |
|---|---|---|
| hx-sse | the layout stream (notify, presence, ops, games, jobs, polls, lists); bot POST → SSE with `hx:release`; chat transport B; terminal line-mode output | — |
| hx-ws | chat transport A (default); terminal I/O; c4 moves | — |
| hx-multipart | `/status` multipart/parallel probes; bot delivery B (shell, tokens, title and usage parts); chat transport D (`HX-Last-Part-ID`); ops slow panels | — |
| hx-pending | chat optimistic bubble (B, C); lists add item; poll vote; bot question echo; guestbook submit | — |
| hx-browser-indicator | boosted navigation (`boostBrowserIndicator`); bot generation; exports. Chromium only, a no-op elsewhere (04 §5.6) | — |
| hx-prompt | every moderator and admin reason → `HX-Prompt` → the audit log | — |
| hx-preload | boosted navigation; video cards on mouseover; wiki links; game tiles; find results. It sends no `HX-Preloaded` header (04 §4.5), so every GET stays side-effect free | — |
| hx-ptag | chat transport C (the ptag is the cursor; 304 when nothing is new); ops and status poll variants; leaderboards | — |
| hx-history-cache | wiki, video library, `/find`, games catalog; `.Private` routes set `hx-history="false"` because it snapshots page HTML into sessionStorage (04 §5.10) | — |
| hx-head | boosted-navigation head merge (title, description, canonical, og; `og:video`) | — |
| hx-upsert | chat (replay, edits, tombstones), presence, notifications, jobs, lists, c4 cells, leaderboards; keys are zero-padded strings because upsert sorts with `localeCompare` (07 §6.2) | — |
| hx-targets | unread badges `.unread-<room>`, `.notify-count`, user chips after a role or avatar change, RSVP counts `.rsvp-<id>` | — |
| hx-download | CSV (audit, accounts), chat and bot transcripts, `.cast` recordings, wiki `.md`, calendar `.ics`, recovery codes; never video (it buffers the whole body in a Blob, 04 §5.14) | — |
| hx-live | — | `/scripting/live`: the password-rules widget built three ways (app.js, hyperscript, hx-live). It needs eval: EvalError under the hash CSP (04 §5.4). As built (M2): the app.js way is the feature's `static/scripting.js`, the hyperscript way the `PasswordRules` behaviour, whose score hs-include sends to `POST /scripting/score` (hs-include's real use, and `bundle-race`'s proof that hyperscript, loaded last, registered it) |
| hx-csp | — | `/scripting/*` with per-response nonces; `/scripting/streams` pins the upstream gaps so a fix shows up as a spec diff. App-wide it fails (11 §2) |
| htmx-2-compat | — | `/compat/htmx2` replays the skeleton's htmx-2-era views (commit 78a31ca, 07 key facts): a 422 is not swapped and `htmx:afterSwap` fires. It breaks the 422 pattern and turns on implicit inheritance (04 §5.15) |
| hx-alpine-compat | — | `/compat/alpine`: inert registration, no errors, no Alpine vendored. It needs Alpine, a client framework (PHILOSOPHY "The line we hold") |

**htmx 4 core features showcased** (RF §5.4, PF §5.4): morph swaps (`innerMorph` on ops tables and the terminal
screen, `outerMorph` for the bot's final message); `<hx-partial>`; `hx-status:422/429/5xx`; `swapEmpty`; the `delete`
swap; view transitions on boosted links only (`SK/CLAUDE.md` "View Transitions"); `hx-config timeout:0` on the upload
finish request only (§14.2); HCON in `hx-vals` (the meta stays JSON, S14); `hx-sync` (`this:replace` on search; the
default is `queue first`, 04 §9); `hx-disable`; `hx-indicator`; `hx-ignore` on UGC; `intersect once` and `every 2s`
triggers; the `HX-Trigger`, `HX-Location`, `HX-Retarget`/`HX-Reswap` and `HX-Push-Url` response headers; explicit
`:inherited`. QUERY / `hx-query` only if the fork's method table accepts it (cut list, §22). Alpine stays inert unless
Alex asks (D3).

### 12.4 Hyperscript and the two client implementations

Behaviours live in each feature's `static/<f>._hs` and in the platform's core set; markup only ever says
`_="install Name"`, written only by `html.behave` (D22, S15). Vanilla twins live in app.js behind one delegated
`data-behave` listener on `htmx:after:process`. Alex chose to keep both implementations for now (ANSWERS #2). They are
the two members of the `client` family: `platform/html` imports `client:.`, which the build line points at
`platform/client/hyperscript` or `platform/client/vanilla`, and neither member imports `platform/html` (LC §3, §5). The
table's owner column is this plan's assignment (**NEW**; "platform" = the core set; app.js lines are
`SK/app/static/app.js`).

```odin
Behaviour :: enum {Tabs, Toast, Reset_On_Success, Dismiss, Search_Box, Range_Fill, Composer, Auto_Scroll, // twinned
	Rel_Time, Copy_Text, Show_Password, Draggable, Drop_Zone, Palette, Term_Keys, Measure_Term, Resume, Scrubber,
	Otp_Input, Expire}
BEHAVIOURS :: [Behaviour]struct{hs, vanilla: string}{ // one row per member; "" = no twin
	.Reset_On_Success = {"ResetOnSuccess", "reset-on-success"}, .Rel_Time = {"RelTime", ""}, … }
behave :: proc(b: ^strings.Builder, x: Behaviour) { … } // _="install X" or data-behave="x", per the client
```

| Behaviour (hs / vanilla) | Does | Twin | Owner |
|---|---|---|---|
| `Tabs` / `tabs` | `take @aria-selected` on a tablist (app.js:57-62) | yes | platform |
| `Toast` / `toast` | wait 3.6 s, add `.leaving`, wait for `animationend` or 1 s, remove; the dismiss button (app.js:64-90; 05 §7) | yes | platform |
| `ResetOnSuccess` / `reset-on-success` | resets a form after its own 2xx only, clears `.form-error`; a 422 keeps the input (app.js:154-161) | yes | platform |
| `Dismiss` / `dismiss` | outside click and Escape close popovers, menus and search results (app.js:175-194) | yes | platform |
| `SearchBox` / `search-box` | Enter doesn't submit (`on submit halt`); Escape clears (app.js:184-186) | yes | platform |
| `RangeFill` / `range-fill` | sets `--fill` through `setProperty` and syncs the `<output>` (app.js:114-132) | yes | platform |
| `Composer` / `composer` | Enter sends, Shift+Enter adds a newline, the box grows | yes | chat |
| `AutoScroll` / `auto-scroll` | keeps a log at the bottom unless the reader scrolled up (`measure`) | yes | chat |
| `RelTime`, `CopyText` | "3 min ago" from `data-ts` every 30 s (the server renders the absolute time); `navigator.clipboard.writeText` | no | platform |
| `ShowPassword`, `OtpInput` | toggles a password input's type; TOTP digits auto-advance and accept a paste | no | accounts |
| `Draggable`, `DropZone` | HTML5 drag and drop of board cards → `POST /lists/<id>/items/<iid>/move`; move buttons are the no-JS path | no | lists |
| `Palette` | Ctrl-K opens a `<dialog>`; arrow keys and Enter | no | find |
| `TermKeys`, `MeasureTerm` | keys from the labelled textarea → a hidden `hx-ws:send` form (custom trigger **UNVERIFIED (M11)**, fallback a 30-line app.js sender); columns and rows from `measure` → resize | no | term |
| `Resume`, `Scrubber` | posts the watch position every 10 s (the page renders `data-resume`); thumbnails on seek-bar hover (VTT sprites) | no | video |
| `Expire` | removes typing indicators after `data-ttl`; a `wait` read from an attribute is **UNVERIFIED (M6)**, the server's delete is the fallback (PF §5.5) | no | chat |
| `PasswordRules` | ticks a password's rules and keeps the score for hs-include (`set dom :score`: a behaviour's own `:x` lives in the behaviour's scope, which hs-include doesn't read) | no | scripting (M2) |

**The gate** is a `hyperscript:before:init` listener in app.js that cancels initialisation unless `_` matches
`/^\s*install\s+[A-Z][A-Za-z0-9_]*(\s*\([^)]*\))?\s*$/` (05 §5: it blocked an injected `_` and an injected
`<script type="text/hyperscript">` while behaviours kept working). Definitions loaded from `._hs` aren't gated.

**Bans and rules.** `socket`, `eventsource`, `worker`, `component`, `js` and `hdb` are banned (05 §0: no reconnect,
a leak past the element's life, CSP-blocked, or client templating); HTML streams go through hx-sse and hx-ws. Data
reaches behaviours only through `data-*` (§17.4). Large lists get one delegated container behaviour, never one per
row: an inline `_` costs about 0.1 ms per element and `install` 0.04–0.06 ms, while one delegated handler over 1000
rows took 2.4–4.4 ms in all (05 §6). UGC bodies carry `hx-ignore` and `data-disable-scripting` (why both: §17.4).
htmx loads first (05 §3).

**Progressive-enhancement rule** (RF §5.5): every feature's core flow works with zero behaviours (forms + htmx). Core
specs run on `full` and on the CI-only `full-vanilla` build, `full`'s files with the vanilla client (core and
twinned-behaviour specs on the main host, chromium; §19). **app.js keeps**, in every profile: the hashed theme pre-paint
(`SK/app/src/views/html.odin:42`) and persistence, count-up, the gate (hyperscript profiles), the roughly 40-line
chunked-upload shim (fetch reports no upload progress, 07 §4.3) and later the games postMessage listener (SP7, §21); in
vanilla profiles, also the eight twins. `escaping.spec` checks every rendered `_` against `^install [A-Z]\w*$` and every
`data-behave` value against `BEHAVIOURS` (§19.1.5). Beyond its bytes (§12.1), hyperscript costs 5–19 ms of cold
execution against htmx's 1.5–3 ms (05 §0); it is ledger line 3 (§3).

**As built (M2):** `platform/html/behave.odin` holds the enum and the table above (20 members, 21 with slice 5's `PasswordRules`) and writes the
attribute from `client.NAME`. A profile's `app.js` is `client/core.js` (the theme picker and its persistence,
count-up, the overlay's Escape: everything both members keep) followed by the member's own `app.js`, concatenated by
`tools/bundle`. The vanilla member's twins hang off one listener per event on `document`, dispatched by the nearest
`data-behave`, and `htmx:after:process` arms what needs arming (a toast's timer, a range's fill). The hyperscript
member's `app.js` is the gate alone; the layout loads `_hyperscript.min.js` (`defer`, after app.js, so the gate is
listening before anything initialises) and then `behaviours._hs` as `<script type="text/hyperscript" src>`: the
core set (`client/hyperscript/behaviours._hs`) followed by each reached feature's `static/*._hs`, served as
`text/plain` so no browser treats it as script. Two rows read differently as built: `Dismiss` empties its element
(search results) or closes it (a `<details>`) on a click outside its *parent*, so the field that fills it doesn't
count as outside, and Escape lives in `Dismiss`, which `SearchBox`'s results install; `SearchBox` only halts the
submit. `Composer` and `AutoScroll` land with chat (M2's slice 8). `lab` runs on the hyperscript client and
`skeleton` and `minimal` on vanilla; the skeleton's specs also passed on a hyperscript build of it (Chromium and
WebKit), the check `full-vanilla` makes from the other side. `escaping.spec` walks the sitemap and, on a hyperscript
build, injects both forms of 05 §5 beside an `install` and checks that only the `install` initialised. Code that is no
behaviour and must run under either client goes in a feature's `static/*.js`, which tools/bundle appends to `app.js` as
it appends `static/*.css` to `app.css` (each file wrapped in its own function): the scripting lab's plain-JS widget and
the compat page's htmx 2 event counter are the two. `PasswordRules` (scripting) is the table's twenty-first row.

### 12.5 Themes

The skeleton's token system is unchanged: `data-style` × `data-scheme` and the hashed pre-paint (D23, `SK/CLAUDE.md`
"CSS conventions"), and the two themes are the members of the `theme` family, read by `platform/html` (LC §3).
`theme/full` is 6 styles × 24 schemes (`skeleton`, `full`, `lab`, `full-vanilla`). `theme/lite` is
the `modern` style with `midnight` and `daylight` (`minimal`, `streams`); it keeps the same pre-paint script, so
`minimal`'s CSP string stays identical. Houston adds one palette block, `houston`, as its server-rendered default, and
stores each member's choice in the accounts feature's `accounts_prefs`, so the server renders the right attributes on
every device; localStorage still covers guests (PF §5.6). Feature CSS is namespaced `.<f>-*` (`tools/check` names).

## 13. Houston: product, information architecture and journeys

### 13.1 What Houston is

**Houston, the crew's home channel** (D28; Q3: Houston, 2026-10-25), is the `full` profile at `houston.alexh95.com`,
branded in `cmd/full/brand.odin`; its session-free lab host `houston-lab.alexh95.com` carries every starter demo and lab
page, the four lab-only extensions' included (§7.3; ANSWERS F2, round 3). What it is for, its scale target (5–50
accounts) and D3's four tenets are in §3.2. The brief calls the showcase a test of whether these tools hold code quality
at huge scope; the measures are the slice gate at every milestone exit (§22.1), the per-milestone audit with its
audit-debt limit (§19.2), the parity gate (§18) and §6.5's rule that the composing code stays smaller than any one
feature. UI labels are plain words; Apollo vocabulary appears only in product names (Comms, Capcom, Watch, Arcade,
Logbook, Checklists, Go/No-go, Calendar, Visitor log, Control), which are nav labels from `brand.odin`, never route
prefixes (D9, §6).

### 13.2 Information architecture

| Nav label (brand.odin) | Feature package | Prefixes | What it is for | Implementations in `full` | Milestone |
|---|---|---|---|---|---|
| Today | `home` | `/` | one page of cards from every feature | — | M4 |
| Comms | `chat` | `/chat` | rooms, DMs, presence, typing, receipts, moderation | the SQLite store; transports ws, sse, poll, multipart behind `chat_web`'s switch | M6 |
| Inbox (bell) | `notify` | `/notify` | mentions, DMs, assignments, reminders, results | the SQLite store | M6 |
| Capcom | `bot` | `/bot`, `/admin/bot` | the AI bot: mock now, llama.cpp on the LAN later; the admin's default backend | `backend_mock`, `backend_llama` behind `bot_web`'s switch; the SQLite store | M7 |
| Watch | `video` | `/video`, `/media` | library, player, captions, resume | the SQLite store | M9 |
| Arcade | `games`, `c4` | `/games`, `/c4` | spark's games embedded with live player counts and leaderboards; connect-four | `catalog_static`, or `catalog_api` once `GAMES_API_URL` is set | M10 |
| Logbook | `wiki` | `/wiki` | house manual, recipes, trip notes, the starter's docs | the SQLite store (docs seeded read-only) | M8 |
| Checklists | `lists` | `/lists` | shared live lists with a board view | the SQLite store | M8 |
| Go/No-go | `polls` | `/polls` | quick polls with live results | the SQLite store | M8 |
| Calendar | `calendar` | `/calendar` | gatherings, RSVP, ICS feed | the SQLite store | M10 |
| Visitor log | `guestbook` | `/guestbook` | public notes, moderated | the SQLite store | M10 |
| Search (Ctrl-K) | `find` | `/find` | global search and the command palette | per-feature FTS | M8 |
| Status | `status` | `/status` | public health of the parts | — | M5 |
| Me | `accounts` | `/account`, `/login`, `/logout`, `/register`, `/invite` | profile, sessions, TOTP, preferences | `accounts` | M4 |
| Control | `accounts`, `audit`, `ops`, `jobs`, `modules`, `dbview`, `term` | `/admin/accounts`, `/admin/audit`, `/admin/ops`, `/admin/jobs`, `/admin/modules`, `/admin/dbview`, `/admin/term` | Alex's area | — | M4–M11 |
| Console | `term` | `/term` (agent at `/term/agent`) | the console of the Raspberry Pi 4 (§16), LAN-only | line and PTY modes | M11 |
| (shared) | `uploads` | `/uploads` | chunked uploads for chat images, avatars and video | the SQLite store (X13) | M6 |
| Control | `devices` | `/admin/devices`, `/devices` (the feed) | the device registry, which generalises `/admin/term`'s device tokens to every device, and a plain-text `text/event-stream` (unread count, presence, next event, bot health) for screens that can't render HTML (ledger row 8, §3.3) | the SQLite store | M14 (optional) |
| Cams | `cams` | `/cams` | each camera's MJPEG stream, pulled once and fanned out to members as `multipart/x-mixed-replace`, which a plain `<img>` renders with no JS; LAN-only and members-only first | one upstream pull per camera (`platform/stream/client`), fanned out by `platform/stream`'s multipart writer | M14 (optional) |
| (no nav: a device's own URL) | `wall` | `/wall` | the wall and TV dashboard: a kiosk view of Today, signed in by a device token | Today's cards (`home`) | M14 (optional) |
| Lab (a footer link, on its own host) | `landing`, `notes`, `dashboard`, `gallery`, `contacts`, `about`, `lab`, `scripting`, `compat` | on `houston-lab.alexh95.com` only: `/` (landing), `/notes`, `/dashboard` and `/ui/ping`, `/components /forms /ui /validate`, `/data /contacts /search /api/search`, `/about`, `/lab`, `/scripting`, `/compat` | every starter demo and lab page, session-free, its demo data capped (`NOTES_CAP` 500, `CONTACTS_CAP` 2000) and reset nightly at 04:00 (§7.3; ANSWERS F2, round 3; RESOLUTIONS X38). `about` is here too: Houston proper has no "about the stack" page, and its footer links to this host (RESOLUTIONS X36) | the SQLite store (notes, contacts) | M4 (the packages from M1–M3) |

The three M14 rows join `full` when M14 lands, after M12 (Q33: yes, 2026-10-26; RESOLUTIONS X42); the nav label Cams
and the package name `wall` are **NEW**.

**Layout** (D29): a topbar (wordmark · nav · `/find` active search · the notifications bell with an hx-targets badge ·
theme picker · account menu), then `<main>`, `#overlay`, `#toasts` (`hx-preserve`, `aria-live`) and `#live`, the
page's one SSE stream (§9). **Guests** see the Today landing, Arcade, public Watch, public Logbook, the Visitor log,
Status and Sign in. **Members** see the full nav in `brand.odin`'s order; items the viewer's role can't open are
hidden, and `front` enforces the same rule (§17.2). **Fragment conventions**: every list item has a stable id
(`m-<id>`, `item-<id>`, `job-<id>`) and is swapped by upsert; toasts are OOB carriers into `#toasts`; overlays use
`<dialog>`; live logs are `<div role="log">` of `<article>` (D14, §9).

### 13.3 Journeys by role

Rewritten from PF §6.3 with this plan's generic routes (D29).

**Guest** (a cousin Alex sends the link to):
1. lands on Today at `/`: what Houston is, approved Visitor log notes, public videos, the Arcade;
2. plays brick at `/games/brick`: the click-to-play facade becomes an iframe on a desktop, a "Play full screen"
   link-out on a phone (D34);
3. reads a public Logbook page at `/wiki/<slug>`, which works without JavaScript (tenet 2, D3);
4. tries the bot at `/bot` in mock mode (guests get mock only, 5 per hour per client id, D31);
5. signs the Visitor log at `/guestbook`; hx-pending shows the note, which appears once a moderator approves it;
6. follows an invite link to `/register` and becomes a member (invite-only registration, Q10).

**Member** (crew):
1. opens Today: who's around, unread per room, the next gathering, open polls, who is playing;
2. talks in `/chat/r/<slug>`: Enter sends (`Composer`); an @mention lights the bell everywhere (`.notify-count`);
3. calls a Go/No-go at `/polls`; the bars move live as votes land;
4. builds a packing checklist at `/lists/<id>`, assigns items (assignees get an Inbox notice) and drags cards on
   the board view;
5. RSVPs to a gathering under `/calendar` and subscribes a phone to `/calendar/feed.ics?t=<token>`;
6. resumes a video at `/video/<id>` where they left off on another device;
7. asks the bot at `/bot/c/<id>`; tokens stream in, and Stop (`/bot/gen/<gid>/stop`) ends it;
8. presses "Invite crew" on a game page, which opens `/chat/r/<slug>?draft=<game link>` (D6);
9. searches with Ctrl-K (`/find`): results only from rooms they belong to (D36).

**Moderator**:
1. approves visitor notes in the guestbook queue, or rejects one with an hx-prompt reason (→ audit);
2. in a room, opens the on-demand message menu (`GET /chat/m/<id>/menu`, rendered with the viewer's perms) and
   deletes a message to a tombstone with a reason; the audit log keeps who and why, never the body;
3. mutes a user, sets slow mode and locks a room.

**Admin** (Alex):
1. bootstraps with `ACCOUNTS_ADMIN_HASH` (from `--hash-password`) and enrols TOTP, required for Admin (Q11);
2. issues invites and manages accounts at `/admin/accounts` (role changes with a reason; user chips update);
3. watches `/admin/ops`, and runs and cancels jobs at `/admin/jobs` (cancel takes an hx-prompt reason);
4. reads `/admin/modules`, and switches the bot default on `/admin/bot`, which `modules` links to (in memory, audited,
   reset on restart, D8; §15.4);
5. registers the Pi at `/admin/term` (the device token is shown once), then opens a console at `/term` after step-up
   while a family member with `Term_Watch` watches read-only (both LAN-only, §16, §17); by Q31's default that
   family member is a Moderator (§17.1).

### 13.4 Coverage matrix

P = primary use, s = secondary. Extensions in `web.Ext` order (§2): sse, ws, mp (hx-multipart), live,
pend (hx-pending), bi (hx-browser-indicator), prm (hx-prompt), pre (hx-preload), ptag, hc (hx-history-cache), head,
ups (hx-upsert), tgt (hx-targets), dl (hx-download), 2c (htmx-2-compat), ac (hx-alpine-compat), csp; hs = hyperscript
behaviours (§12.4). Transports: poll, SSEp (persistent SSE), SSEr (SSE request stream), WS, MP (multipart stream),
Rng (Range). DB = SQLite required, optional or not used (D18). Adapted from RF §6.10 and PF §6.5; the assignments
are **NEW**.

| Feature | sse | ws | mp | live | pend | bi | prm | pre | ptag | hc | head | ups | tgt | dl | 2c | ac | csp | hs | poll | SSEp | SSEr | WS | MP | Rng | DB |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| layout (every page) | P | | | | | P | | P | | | P | | | | | | | P | | P | | | | | — |
| home | P | | | | | | | | | | | s | s | | | | | | | P | | | | | no |
| chat | P | P | P | | P | | P | | P | | | P | P | s | | | | P | P | P | | P | P | | opt |
| notify | P | | | | | | | | | | | P | P | | | | | s | | P | | | | | opt |
| bot | P | | P | | P | s | | | | | | s | | s | | | | s | | s | P | | P | | opt |
| uploads | s | | | | | | | | | | | | | | | | | | | s | | | | | opt ¹ |
| video | | | | | | | s | P | | P | s | | | | | | | P | | | | | | P | opt |
| games | P | | | | | | | P | s | P | | P | | | | | | | s | P | | | | | no |
| c4 | s | P | | | | | | | | | | P | | | | | | | | s | | P | | | no |
| wiki | | | | | | | | P | | P | s | | | s | | | | | | | | | | | opt |
| lists | P | | | | P | | | | | | | P | | | | | | P | | P | | | | | opt |
| polls | P | | | | P | | | | | | | | | | | | | | | P | | | | | opt |
| calendar | s | | | | | | | | | | | | P | s | | | | | | s | | | | | opt |
| guestbook | s | | | | P | | P | | | | | | | | | | | | | s | | | | | opt |
| find | | | | | | | | P | | P | | | | | | | | P | | | | | | | opt |
| status | | | P | | | | | | P | | | | | | | | | | P | | | | P | | no |
| accounts | | | | | | | P | | | | | | P | s | | | | P | | | | | | | req ² |
| audit | | | | | | | | | | | | | | P | | | | | | | | | | | req |
| ops | P | | s | | | | | | s | | | | | | | | | | s | P | | | s | | no |
| jobs | P | | | | | | P | | | | | P | | s | | | | | | P | | | | | opt |
| modules | | | | | | | s | | | | | | | | | | | | | | | | | | no |
| dbview | | | | | | | | | | | | | | | | | | | | | | | | | req |
| term | P | P | | | | | s | | | | | | | s | | | | P | | s | P | P | | | req |
| skeleton features ³ | | | | | | | | | | | | | | | | | | | | | | | | | req |
| lab: scripting, compat, lab (also on `full`'s lab host) | s | s | s | P | s | | | | | | | | | | P | P | P | P | | s | s | s | s | | no |

¹ uploads owns its session rows (`uploads_blobs`, `uploads_parts`) through its store in either family; it does not
require SQLite, but resumable uploads do (RESOLUTIONS X13; §14.2). ² the `accounts` identity requires SQLite;
`envadmin`, `nick` and `anonymous` need none.
³ dashboard, gallery, contacts and about, as in the `skeleton` profile, which ships core htmx only (D24); about needs
no SQLite (D18). `notes` (`minimal`, `streams`) also uses core htmx only, with SQLite optional (D8). In `full` all five
sit on the lab host (§7.3).

**Check**: every extension and every transport has at least one P. hx-live, hx-csp, htmx-2-compat and
hx-alpine-compat have theirs only on the session-free lab pages, in `lab` and on `full`'s lab host, by design (§12.3).

## 14. Houston feature specs I: talk and ask

This section specifies the two features Alex named first, chat and the bot, and the three they lean on: `notify`,
`home` and `uploads`. Hub mechanics are in §9, the store in §11, security rules in §17 and exit gates in §22.

### 14.1 Chat (`chat`)

| | |
|---|---|
| Nav label, prefix | Comms, `/chat` (D29) |
| Built | M2 in `streams` (the memory store, all four transports); M6 in `full` (the SQLite store, FTS, uploads, moderation) |
| Implementations | the stores `app/stores/{sqlite,memory}/chat/`; `transport_ws`, `transport_sse`, `transport_poll`, `transport_multipart`, all four linked behind `chat_web`'s switch (LC §4). Chat's hello world is the memory store with all four transports and notify, its hard dependency (D26, D27; LC §10) |
| Topics | `chat.room:<id>` (persisted); `chat.presence:<id>` and `chat.typing:<id>` (`.Latest`); `chat.reply:<room>` (the bot's room answers, §6.2) |
| Perms, behaviours | `Chat_Read Chat_Post Chat_Dm Chat_Create_Room Chat_Attach Chat_Moderate` (D35); `Composer`, `AutoScroll` (twinned, D22); `Expire` on typing indicators (hyperscript only, §12) |

**Model** (D30, 07 §1):
- Rooms are public, private or announcements; a DM is a two-member room of kind DM (07 §1.3).
- Presence: online while a stream is open, away if it closed less than 5 minutes ago, offline otherwise, debounced
  10 s (D14). Typing: at most one event per 2 s, expiring after 5 s, memory only.
- Read receipts: the newest visible message carries `hx-trigger="intersect once"` → `POST /chat/r/<slug>/read?upto=`.
  Never a GET: a preload can't be told apart from a real read (04 §9).
- Members edit their own messages within 10 minutes and delete their own. Moderators delete any message (to a
  tombstone), mute, kick, lock a room and set slow mode, each with an hx-prompt reason for the audit log.
- Mentions go to `notify_web.send` (a direct import, so notify comes with chat), `@bot` to `bot.ask:<room>` on the
  hub (§6.2, §14.3), images through `uploads` (§14.2). Moderation actions go to `store:audit`. Bodies are at most
  2,000 runes, cut by rune (the skeleton's rule).

**Visitors who can't read.** A Guest has no `Chat_Read` (D35), so on a `nick` witness an off-LAN visitor, who gets no
nickname, sees one page at `/chat`: a notice that chat is open on the LAN (ANSWERS round 9). It answers 200, not 401,
because nick has no login to send them to; every other chat route keeps its `Chat_Read` check (§17.2).

**Room URLs.** Every room route is keyed by slug, `/chat/r/<slug>/...`, read receipts included, as §6.1's pattern
`/chat/r/([%w-]+)` reads; a DM gets an opaque generated slug (D30; RESOLUTIONS X12).

**Rolling buffer and truncation.** Whichever cap hits first wins; pinned messages (at most 20 per room) are exempt.
The defaults are Q19.

| Room kind | Keeps | Env vars (D10) |
|---|---|---|
| room (public or private) | 500 messages or 7 days | `CHAT_ROOM_CAP`, `CHAT_ROOM_MAX_AGE` |
| DM | 1000 messages or 30 days | `CHAT_DM_CAP`, `CHAT_DM_MAX_AGE` |
| announcements | 100 messages or 365 days | `CHAT_ANNOUNCE_CAP`, `CHAT_ANNOUNCE_MAX_AGE` |
| any room, set by its owner or an admin | up to 5000 messages or 90 days | the room's settings |

- **With SQLite**, the writer task runs chunked deletes every 50 inserts per room (1,000 rows per transaction, D16)
  and a 60 s job sweeps by age. FTS5 triggers make deletes about 5× dearer, so retention is budgeted at 6.4 ms per
  1000 rows (12 §7, §9). §11 has the measurements behind chunking.
- **The in-memory ring**, in both modes, keeps the last 100 messages per room for first paint and replay, under a
  global `CHAT_RING_BYTES` of 16 MiB that evicts the oldest rooms' tails first. In memory mode the ring is the
  history: a restart empties it, and the UI says "ephemeral mode" (D16).
- **The marker**: when "load older" passes the oldest kept message, the log shows "Older messages were removed (this
  room keeps the last 500 messages or 7 days)", with the room's own caps.
- **Tombstones**: a moderation delete clears the body and keeps the row and id, so it travels as an upsert like an
  edit (07 §1.2). The audit log keeps who and why, never the body; retention doubles as data minimisation (07 §1.5).

**Ids and markup.** Ids are SQLite rowids, or `<epoch>-<seq>` in memory mode.

```html
<div role="log" aria-label="Messages">
  <article id="m-88201" data-seq="000000088201" data-author="42">
    <div class="chat-body" hx-ignore data-disable-scripting>…escaped text…</div>
  </article>
</div>
```

`data-seq` is the id zero-padded to 12 digits, because hx-upsert sorts with `localeCompare` (07 §6.2). The log is a
`<div role="log">` of `<article>`, never `<ul>`, because hx-pending wraps its clones in a `<div>` (D14, 04 §5.5), and
it exists in the initial markup (11 §7.4). Only the body carries `hx-ignore` and `data-disable-scripting`, so
server-rendered actions keep working (11 §5.2). A persisted message publishes to `chat.room:<id>` after the writer
task commits, carrying its rowid; the page resumes from `chat.room:<id>@<rowid>` (D13, §9).

**Four transports, all full implementations** (D8). Users see them as a "Connection: Auto / WebSocket / Streaming /
Polling / Multipart" setting: a compatibility mode for networks whose proxies kill WebSockets.

| | Client | Server | Resume |
|---|---|---|---|
| A WS (default) | `hx-ws:connect="/chat/r/<slug>/ws"` on the room pane; `<form hx-ws:send>` composer | JSON in (the 04 §4.4 frame shape); escaped `<hx-partial hx-swap="upsert sort">` out | snapshot of the last 50 on (re)connect; upsert dedups |
| B SSE + POST | the room topic on `#live`; `hx-post` composer with `hx-pending` | POST → writer task → commit → the bubble in the response and on the hub | `Last-Event-ID`, `after`, then `@rowid` keyset replay (D13) |
| C poll + ptag | `hx-get="/chat/r/<slug>/since" hx-trigger="every 2s" hx-ptag` | 304 when nothing is new | the ptag (last rowid) |
| D multipart | `hx-multipart:connect="/chat/r/<slug>/parts"` | one part per event with `HX-Target`, `HX-Swap`, `HX-Part-ID` | `HX-Last-Part-ID` |

- The choice is per request, among the four, by `chat_web`'s switch (§6.4): `accounts_prefs` in Houston (read from
  the `Viewer`), a cookie elsewhere, `?transport=` in tests, else `CHAT_TRANSPORT`. Responses carry
  `x-impl: chat.transport=<t>`, log lines `impl=`.
- "Auto" is WS, falling back to SSE after two failed connects. It reads the `htmx:ws:error` event detail, which is
  **UNVERIFIED (M6)**: a spike at the M6 start settles it. *Settled (M6.1):* the detail is a bare Event, so Auto
  counts `htmx:ws:close` events with no connection between them.
- `Composer` (Enter sends) and `AutoScroll` behave the same over A–D (07 §1.2). Specs run per transport
  (`@chat-ws` …) and resume without duplicates, including across a server restart (D37).

**Fan-out.** Each message is rendered once. Per-viewer differences come from CSS (`<body data-me>` against
`data-author`) and an on-demand menu, `GET /chat/m/<id>/menu`, rendered with the viewer's perms. The hub skips
nobody: the author's reply and the hub's copy share an id and dedupe by upsert, so the author's other tabs get the
message too (D13). Unread counts for other rooms go to `notify.user:<uid>` as hx-targets updates of `.unread-<room>`.
The writer task's measured insert rates are in §11; D38 budgets ≥ 50k msgs/s and send → another member's DOM p95
≤ 50 ms on the LAN via NPM (**NEW**, §18).

**Limits** (D30; the rate-limit table is in §17.5): posts 5 per 10 s per user, burst 10, with a 429 and `Retry-After`
into the toast slot; WS frames 20 per second per connection, then close 1008; 64 KiB WS messages; typing 1 per 2 s;
2 concurrent uploads per user; slow mode per room.

**Extensions used** (D21): hx-ws (A), hx-sse (B), hx-ptag (C), hx-multipart (D), hx-pending (the optimistic bubble in B
and C), hx-upsert (replay, edits, tombstones, presence), hx-targets (`.unread-<room>`), hx-prompt (moderation reasons),
hx-download (transcripts). Each transport package declares its own extension, and `chat_web.EXTS` unions them with
hx-pending, hx-upsert, hx-prompt, hx-targets and hx-download, so every chat bundle carries all four transports'
extensions (RESOLUTIONS X29, as LC §12 recasts it; §12.1). Room pages carry `.Private`: 11 §5.2 asks for `noindex` on
private rooms and DMs and `no-store` on DMs, and one route row serves every room (§6). Tables are prefixed `chat_`, with
user ids plus an `author_name` snapshot and no foreign key into `users` (D6, §11); search is `find`'s.

**As built (M2)**, public rooms on the memory store in `streams` (the package tour is `features/chat/README.md`):
- **Ids** are one number in memory, the boot time in ms × 10⁶ plus the sequence, and room versions count from the same
  base: a page from before a restart keeps its messages and never sees a new one take an old one's id, and a poll's old
  tag or a multipart's old part id reads as older than anything the new process has. No `data-seq`: hx-upsert sorts
  with `localeCompare(…, {numeric: true})`, so ids order as numbers.
- **Each transport package** gives the room page its wiring (the pane's attributes, the composer's) and serves its own
  endpoint; `sse` has none and puts the room's topic on `#live`, whose resync refetches through `poll`'s `/since` with
  no tag (the last 50). A socket and a multipart response subscribe before they read their snapshot, so a message
  between the two arrives twice rather than never. A socket's frame is posted by `chat_web`'s one post path (set as
  `chat_transport_ws.post` at init), and its refusals go back down the socket (the reason out of band into the form's
  slot, the 429 as a toast).
- **Presence** rides `#live` on every transport: the hub's `watch` hears a page's `chat.presence:<id>` stream open and
  close; online shows at once, away 10 s after the last closed and gone after 5 minutes, both from the `chat.presence`
  job every 5 s. **Typing** is `POST …/typing` from the composer's textarea (`input changed throttle:2s`), one in 2 s
  per member published, upserted into `#typing-<id>` and faded by CSS (`Expire` removes it under hyperscript); the
  writer's own is marked by `AutoScroll` and hidden.
- **Read receipts**: the newest message of a render, and every message the hub pushes, carries the receipt, so
  whichever is newest in view posts it. A reader's unread count for a room goes out of band into every
  `.unread-<slug>` of theirs on `notify.user`; a reader who has never read a room has no count.
- **The menu** has Link, and Edit and Delete for one's own within the window; its slot is a `Dismiss` (a click outside
  the message, or Escape, empties it), so it needs no close route. A room's slug is made from its name.
- **Specs** resume across a server restart on every transport; `setOffline` cuts only new requests and Chromium's
  socket in Playwright, so its spec holds the rest only to "nothing doubles".

### 14.2 Notifications, Today and uploads

**`notify`** (the Inbox bell, `/notify`; the memory store at M2, the SQLite store at M6; D36). Producers call
`notify_web.send(user, kind, ref, html)` directly: it is the one web-to-web import, so notify is a hard dependency of
each producer, and `kind` is a namespaced string (`"chat.mention"`), so notify never names a producer's kinds (D6;
§6.2). Producers: mentions, DMs, list assignments, calendar reminders, poll results, a bot reply that finished after you
navigated away, moderation, the guestbook queue (moderators) and job failures (admins). `notify.user:<uid>` rides the
page's one `#live` stream (D14): it upserts `#notify-list` and updates every `.notify-count` through hx-targets. It
keeps 200 per user; read ones go after 30 days. Mutes per room and per kind live in `accounts_prefs`. **As built
(M2):** a push is out of band, the item `afterbegin:#notify-list` and the count `innerHTML:.notify-count`, which core
htmx swaps into every match (none is no error), so notify needs no hx-targets; its `EXTS` is hx-sse, for the `#live` it
puts on every page of a member's. A resync refetches the log (`GET /notify/list`); the memory store loses it all at a
restart, which the page shows by refetching an empty one.

**`home`** (Today, `/`; D36, D27): the Today page shows the cards the profile's `main` lists in `HOME_CARDS`, in that
order, each a fragment refreshed over `#live`; guests see it as the landing. `home_web` calls each row and imports no
other feature (§6.2). Every generated project has a root feature, `home` unless the selection includes `dashboard` or
`landing` (D27; RESOLUTIONS X5), so any selection boots to one working card per selected feature (§7). `home` exists
from M1 (in `minimal`); Houston's Today with cards arrives at M4 with `cmd/full`.

**`uploads`** (`/uploads`; M6; shared by chat images, avatars and video; D35):
1. Create an upload, which returns its id.
2. `PUT /uploads/<id>?off=<n>` for each chunk of at most 4 MiB, under the route's own body cap.
3. Finish, `POST /uploads/<id>/finish`: sniff, decode and sha256; the file becomes a content-addressed blob.

The chunks go through app.js's roughly 40-line chunked-upload shim (fetch), because fetch reports no upload progress (07
§4.3), so no htmx timeout applies to them. `hx-config timeout:0` sits only on the finish request, which can run long
while the server hashes and moves the file (D21; RESOLUTIONS X14; **UNVERIFIED (M6)**). Progress comes from the server
on `uploads.upload:<id>`. Size caps, content checks and serving headers are in §17.6; the rate limit is 20 per hour and
2 concurrent per user (§17.5).

**Storage** (D8, D18; RESOLUTIONS X13). `uploads` owns its session rows, `uploads_blobs` and `uploads_parts`. In
the SQLite family it stores them through `app/stores/sqlite/uploads`; in the memory family they live in memory and are
lost on restart, so resumable uploads need SQLite, but `uploads` itself does not require it. Video's SQLite store
holds video metadata, not uploads (§15.2).

### 14.3 The AI chatbot (`bot`)

**Mock now, llama.cpp later.** The brief keeps the AI itself out of the starter: no model and no llama.cpp ship in any
profile or image, and no claim of the starter depends on one. What is built now is what the brief says matters: the
front-end and back-end interfaces, the llama.cpp binding (`backend_llama`, tested against `tools/fakellama`) and a mock
(`backend_mock`, the default) that answers with random "TODO" and "under construction" lines. The interface below
carries the `TODO(Alex)` for the day llama.cpp runs on the LAN: set `BOT_BACKEND=llama` and `BOT_LLAMA_URL`; the code
assumes no host or port (07 §2.2).

**The bot's host** (RESOLUTIONS X41; DEVICES-SUMMARY; §20.8). llama.cpp now has a home: its official Vulkan server
image on apollo's spare GPU (`<APOLLO_GPU>`), in a separate compose project that Alex owns and agents never restart.
It is outside the starter's `deploy/compose.yaml` and every image, so nothing AI ships, as above.
- It publishes one LAN port, `<LLAMA_PORT>`, behind an API key, which `BOT_LLAMA_KEY_FILE` already carries, so
  Houston's `BOT_LLAMA_URL` is `http://<APOLLO_LAN_IP>:<LLAMA_PORT>`.
- It fits a current 4–8B instruct model at Q4 (about 2.5–5 GB) with about 8k of context. The estimate is 40–60 tokens/s;
  M7 measures it with `llama-bench` (**UNVERIFIED (M7)**). Its cost to apollo is about one CPU thread, and the GPU's
  power only while a reply is being written.
- Creating it is Alex's step at M7 (§20.7): the Vulkan image pinned to a build, the render device, an API key file,
  `cpus: 1.0`, a model on the spare disk, and a check of the power supply's rating for sustained GPU load.
- The dev PC's 16 GB GPU runs bigger models for occasional smoke tests, never as Houston's always-on backend. A gaming
  laptop with a 6 GB GPU is the fallback only if apollo's GPU route fails (§20.8).

**The bot's place in the starter** (RESOLUTIONS X32). "Not part of the starter" means that no model, no llama.cpp and
nothing AI ships. The `bot` package (the chat UI, the stream contract, the backend interface, the llama.cpp binding
and the mock) is exactly what the brief calls relevant, so it stays a catalog feature and is in `streams` as well as
Houston. Alex confirmed this with Q32 on 2026-10-25: the bot stays a catalog feature, and it is in `streams`.

`bot` (Capcom, `/bot`; D29) is built at M2 in `streams` (memory, mock, SSE and multipart delivery) and finished at M7
in `full` (the SQLite store, the llama binding, `tools/fakellama`, room mode, the health badge). Implementations:
`backend_mock`, `backend_llama`, both linked behind `bot_web`'s switch; conversations in the bot's store, in either
family. Topics `bot.health` and `bot.ask:<room>` (room mode, §6.2); perms `Bot_Use`, `Bot_Llama`.

**The interface** (D31, with the `Bot_Backend` vtable replaced by `bot_web`'s switch, LC §4):

```odin
Bot_Turn    :: struct { role: Bot_Role, text: string }
Bot_Request :: struct { conv_id, user_id: i64, system: string, history: []Bot_Turn, max_tokens: int, temperature: f32, stop: []string }
Bot_Event   :: union { Bot_Token, Bot_Done, Bot_Error, Bot_Queued }   // tokens coalesced to at most 20 Hz
Bot_Done    :: struct { stop: Bot_Stop, tokens, ms_first_token, ms_total: int }   // llama's timings shape
Bot_Health  :: struct { state: enum u8 { Ready, Loading, Sleeping, Offline, Mock }, slots_total, slots_busy, queued: int, model: string }
Bot_Sink    :: struct { user: rawptr, loop: ^nbio.Event_Loop, gen: u64, on_event: proc(user: rawptr, gen: u64, ev: Bot_Event) }
Backend     :: enum u8 { Mock, Llama }   // bot_web's switch: each proc below is a direct call per case (LC §4)
health :: proc(b: Backend) -> Bot_Health                                    // switch b { case .Mock: bot_backend_mock.health() … }
start  :: proc(b: Backend, req: Bot_Request, sink: Bot_Sink) -> Bot_Gen_Id  // events arrive on sink.loop via next_tick
cancel :: proc(b: Backend, id: Bot_Gen_Id)                                  // idempotent
// TODO(Alex): llama.cpp on the LAN. Set BOT_BACKEND=llama and BOT_LLAMA_URL (on apollo http://<APOLLO_LAN_IP>:<LLAMA_PORT>); never assume a port in code (07 §2.2).
```

**Choosing a backend** (D8): per request, among the healthy ones, by `bot_web`'s switch; both are always linked, and
llama's client is pure Odin (LC §4). Guests always get mock; members choose when both are healthy. The default is
`BOT_BACKEND` (mock); an admin can change it on bot's own `/admin/bot`, which bot owns by D9's prefix rule, in memory
only, audited and reset on restart. Bot pushes the current default to `platform/obs`, so `/admin/modules` shows it and
links to `/admin/bot` without importing bot (LC §9). Responses carry `x-impl: bot.backend=<name>`.

**`backend_mock`** (the default): a timer chain on the stream's loop emits canned "under construction" and "TODO"
lines, picked at random, word by word with 30–120 ms jitter. `BOT_SEED` makes it deterministic and `BOT_DELAY_MS=0`
fast. Its `Bot_Done` stats have llama's shape, so the UI is the same for both.

**`backend_llama`** (the binding is in place; the model comes later):

| Aspect | Contract |
|---|---|
| Endpoint | `POST {BOT_LLAMA_URL}/v1/chat/completions`, `stream:true`. The URL is required: the README says port 9931, the b9190 build 8080 (07 §2.2), and apollo's server publishes `<LLAMA_PORT>` |
| Client, pool | `platform/stream/client` (**NEW**, D12) on the llama worker pool, sized from `/props total_slots` (or `BOT_CONCURRENCY`) |
| Parsing | chunked transfer, SSE `data:` lines, `choices[0].delta.content`, then `[DONE]` |
| Health | `/health` (503 = loading) and `/props is_sleeping`, mapped to `Bot_Health.state` and published on `bot.health` |
| Deadlines | connect 2 s, first token 30 s, idle 15 s |
| Cancel | closes the upstream socket, which is what stops llama.cpp's generation (07 §2.2); Stop and a closed browser stream both call it |
| Transport | plain http on the LAN, so no OpenSSL; a key, if set, comes from `BOT_LLAMA_KEY_FILE` as a bearer token (07 §2.3), never logged |

`tools/fakellama` (Odin, on the starter's own SSE encoder) tests the parser without a GPU: chunk boundaries inside
`data:` lines, `[DONE]`, an OAI error and a 503 "Loading model". A smoke against a real `llama-server` happens only
once Alex runs one: apollo's from M7, or the dev PC's when Alex starts it.

**Front-end contract** (D31). hx-pending echoes the question at once and the browser indicator is on:

```html
<form hx-post="/bot/c/<id>/ask" hx-target="#c-log" hx-swap="beforeend" hx-disable="find button[type=submit]">
```

The response is `text/event-stream` with four frames:
1. The assistant shell `<article id="m-<mid>">` with a Stop button (`hx-post /bot/gen/<gid>/stop`); a queued
   generation shows "Queued (#2)" in it until a slot frees.
2. Unnamed events of escaped token text as `<hx-partial hx-target="#mb-<mid>" hx-swap="beforeend">`, with
   `event: hx:release` after the first token, so the form unlocks while tokens continue.
3. A final `<hx-partial hx-target="#m-<mid>" hx-swap="outerMorph">` with the markdown render (`platform/markdown`,
   depth cap 32, input cap 64 KiB) and the stats.
4. The end of the stream.

**Delivery** is a form choice per request (D8): the same backend stream rendered for another transport. A is POST →
SSE (the four frames above). B is POST → multipart: the same four as parts, plus `#conv-title` and `#usage` parts.
Room mode: `@bot` in a chat room → chat publishes on `bot.ask:<room>` → bot's `deliver` row starts the backend and
streams upserts of `#m-<id>` to `chat.room:<room>` for every member → the finished answer goes back on
`chat.reply:<room>`, whose row in chat stores it as a message from the bot. These are two static topic rows, one each
way, so neither feature imports the other and each works alone; without bot the publish is dropped and counted (§6.2;
LC §9; RESOLUTIONS X37).

**Policy and privacy** (Q20): conversations are stored for their owner only; admins see counts and timings. Guests
get mock only, 5 per hour per client id; members get 1 concurrent generation and 30 per hour. No tools and no
function calling, so a prompt injection has nothing to act on (07 §2.6). M7's checks (Stop ≤ 100 ms, the queue spec
with `BOT_CONCURRENCY=1`, 1000 concurrent mock generations ≤ 1 core and ≤ +30 MB, **NEW**) are in §18 and §22.

**As built (M2)**, in `streams` on the memory store (`features/bot/README.md` is the tour):
- **Routes**: `GET /bot` (a member's conversations, or the guest's one-question page), `POST /bot/c` (a new
  conversation), `GET /bot/c/<id>`, `POST /bot/c/<id>/ask` (a member's, kept), `POST /bot/ask` (anyone's, kept by no
  one: the guest's way), `POST /bot/gen/<gid>/stop`; both asks are `.Stream` rows. `/admin/bot` comes with the second
  backend (M7): with only the mock there is no default to choose, so `Backend` has one member and `BOT_BACKEND` one
  choice. The `bot.health` topic is declared and on the pages' `#live`; the mock's health never changes.
- **The frames** are as above; a live answer's ids are `m-g<gen>` and `mb-g<gen>`, a stored one's its turn id. The
  render is the domain's (`bot.render`: markdown, else escaped text), since views import only html and their domain.
- **Stop** is posted to the generation's loop (`workers.post`), which removes the mock's timer and sends
  `Bot_Done{.Stopped}`: the e2e spec times it in the page, 5–9 ms idle on both deliveries in either engine, and
  holds the best of up to three Stops under 100 ms, since a loaded CI runner's page clock reads its load. A browser
  that goes away cancels the same way.
- **Limits**: `BOT_MEMBER_PER_HOUR` and `BOT_GUEST_PER_HOUR` (`web.Limit`), and one answer at a time per member, each a
  429 into the toasts. The load driver lifts the hourly limits and sets `BOT_DELAY_MS=0`, so a quick run makes
  thousands of generations; it reaches Stop only on ended generations (a stream's id is in its body, which k6 reads at
  the end), so the Stop storm is the e2e suite's timing, not a load figure.

## 15. Houston feature specs II: plan, watch, play and operate

Contracts for the remaining features, one subsection each: routes, extensions, behaviours, storage and the milestone.
Each feature's README carries the full spec under D4's fixed headings. Accounts and audit are in §17, the terminal in
§16, and each milestone's exit gate in §22.

### 15.1 Plan: wiki, find, lists, polls, calendar, guestbook

**`wiki`** (Logbook, `/wiki`; M8; D36):
- Pages have a slug, a title and a visibility (public or members). Revisions keep a line diff computed on the query
  pool; saving over a newer revision answers 409 and shows the diff.
- Markdown is rendered at write time by `platform/markdown` (depth cap 32, input cap 64 KiB) and stored as HTML, so a
  page view never parses (13 §2.1). Rendered bodies sit in `hx-ignore` + `data-disable-scripting` containers (D20).
- The editor's preview is server-rendered on `keyup changed delay:500ms`. Each page sets its own head through
  hx-head (title, description, canonical, og); history-cache serves back and forward; wiki links preload.
- Exports: `.md` through hx-download. Search: FTS5 through `find`.
- Implementations follow the store family (LC §3): the SQLite store is editable (Houston seeds the starter's docs as
  read-only Manual pages), and the memory store is `source_files`, the read-only embedded docs (the lab's wiki from
  M8, and the lean default).
- Perms `Wiki_Read`, `Wiki_Edit`. M8 adds a markdown fuzz (depth cap, 0 crashes) and a back/forward spec with zero
  server hits.

**`find`** (Search (Ctrl-K), `/find`; M8; D36):
- One page and the Ctrl-K palette over the rows of the profile's `FIND_SOURCES` table, each a domain's `search`, which
  fills `store.Search_Hit` rows; `find_web` calls each row and imports no other feature (D6; §6.2, §7.2). The results
  are filtered by the viewer: chat searches only rooms the viewer belongs to, and DMs only their own; the wiki by
  visibility.
- SQLite implementations use FTS5 and memory implementations a `contains_ci` scan; one result list never mixes the
  two engines, and bm25 ranking runs on the query pool (D16). §11.8 has the tokenizer, the folding rule and the
  costs at 100k messages (12 §7).
- The search box uses `hx-sync="this:replace"`; results preload; `/find` is history-cached. The `Palette` behaviour
  opens the Ctrl-K `<dialog>`; without it, `/find` is a plain GET form. Limit: 10 per second per user.
- It lives at `/find` because the skeleton's `/search` is the contacts fragment (D9, §6). M8 asserts FTS MATCH
  ≤ 3 ms at 100k messages and that results respect membership.

**`lists`** (Checklists, `/lists`; M8; D36):
- A list holds items: text ≤ 200 runes, done, an assignee (→ `notify_web.send`), and an integer position. Positions
  keep gaps of 1024 and the server renumbers them.
- The checklist view adds items with hx-pending. The board view has columns; `Draggable` and `DropZone` send
  `POST /lists/<id>/items/<iid>/move`, and move buttons are the no-JS path.
- Changes ride `lists.list:<id>` (persisted) as upserts keyed `data-pos`. Templates: groceries, packing.
- Perm `Lists_Edit`. M8 runs drag and drop with trusted mouse input and the button fallback; the board view is
  cut-list item 8.

**`polls`** (Go/No-go, `/polls`; M8; D36):
- A question with options or the Go/No-go preset; single or multiple choice; an anonymous flag; a closing time.
- Votes go in with hx-pending. Results are CSS bars, `style="--p:NN%"`, which `style-src-attr` allows.
- The topic `polls.poll:<id>` is `.Latest`, so it holds one value and never grows. Closing notifies the voters.
- Perms `Polls_Create`, `Polls_Vote`; votes 10 per minute per user. Polls are cut-list item 9.

**`calendar`** (Calendar, `/calendar`; M10; D36):
- A server-rendered month grid and event pages. The create wizard makes each step a URL through `HX-Push-Url`, with a
  422 per step.
- RSVP yes, maybe or no updates every `.rsvp-<id>` count through hx-targets; changes ride `calendar.event:<id>`.
- Reminders are `JOBS` rows that call `notify_web.send`, 24 h and 1 h before.
- A per-event `.ics` download (hx-download) and a per-user secret feed, `/calendar/feed.ics?t=<token>`, for phones.
- Perm `Calendar_Edit`; RSVPs 10 per minute per user. M10's spec parses the ICS feed. The feed, then the calendar,
  is cut-list item 6.

**`guestbook`** (Visitor log, `/guestbook`; M10; D36):
- A public form: name ≤ 40 runes through `clean_name`, message ≤ 500 runes, submitted with hx-pending.
- Anti-abuse: a honeypot, a signed render timestamp (submits under 3 s are refused), 3 per hour per client id, and the
  `GUESTBOOK_OPEN` switch.
- Notes enter the moderation queue `guestbook.queue` and appear only once approved. A reject needs an hx-prompt
  reason; pending notes expire after 14 days. So a public visitor can write, but nothing shows unmoderated.
- Perm `Guestbook_Moderate`. M10 has a moderation-queue spec; the guestbook is cut-list item 3.

### 15.2 Watch: video (`video`)

`video` (Watch, `/video` and `/media`; M9; D33). Implementations follow the store family (LC §3): the memory store is
`catalog_file` (a scan of `VIDEO_DIR/v/*/meta.json`, no SQLite, no uploads, no watch progress; the lean default), and
the SQLite store holds the library, visibility and watch progress (video metadata only, since the upload rows belong to
`uploads`, RESOLUTIONS X13; Houston). Perms `Video_Watch`, `Video_Upload`, `Video_Moderate`.

**Library and player.** `/video` is a grid with infinite scroll (`intersect once`), hx-preload on mouseover and
history-cache; search goes through `find`. The player page `/video/<id>`:

```html
<video controls preload="metadata" poster="/media/v/<sha256>/poster.webp" data-resume="<seconds>">
  <source src="/media/v/<sha256>/hls/index.m3u8" type="application/vnd.apple.mpegurl">
  <source src="/media/v/<sha256>/720.mp4" type="video/mp4">
  <track kind="captions" srclang="en" label="English" src="/media/v/<sha256>/captions/en.vtt" default>
</video>
```

- HLS comes first and MP4 second, so the browser picks with no hls.js. Captions are WebVTT; chapters are a
  server-rendered list; "up next" follows. hx-head sets `og:video` per page.
- `Resume` posts the position every 10 s and the page renders `data-resume`. `Scrubber` shows hover thumbnails from
  the `thumbs.vtt` sprite index (07 §4.5). Both are hyperscript-only; the video plays without them.
- Verified browser facts (07 §4.2, Chrome 156 headless): Chrome plays native HLS, MP4 and AV1 WebM from the Odin
  Range server. Its first media request is `Range: bytes=0-`, for `.m3u8` and `.ts` too, so every file must answer
  Range from byte 0. Firefox native HLS is unverified, so MP4 is the fallback. Playwright's bundled Chromium lacks
  H.264/AAC, so playback specs use `channel: 'chrome'` or AV1 WebM.

**The media route** `/media/v/<sha256>/<file>` matches the strict pattern `[0-9a-f]{64}/[a-z0-9_.-]+` and carries
`.Media` (CORP same-origin, `immutable`, `Accept-Ranges`). It sends files with `stream_sendfile` (F-3) and its own
MIME table, since odin-http's has no `.mp4`, `.webm`, `.m3u8`, `.ts`, `.vtt` or `.webp` (07 §0.1).

| Request | Answer |
|---|---|
| no `Range` | 200, the whole file |
| `bytes=a-b` or `bytes=a-` | 206 with `Content-Range` |
| `bytes=-n` (suffix) | 206, the last n bytes |
| outside the file | 416 with `Content-Range: bytes */<size>` |
| `HEAD` | the same headers, no body |
| `If-Range` | 206 if the ETag matches, else 200 with the whole file |

- Single ranges only; browsers don't need more (07 §4.3).
- The content length is written by hand, with `_response_write_heading(res, -1)`: a positive length reserves that
  many bytes in the response buffer, which made a 256 MiB file a 261.6 MB peak instead of 5.1 MB (07 §0.2). D38's
  budget is ≤ 8 MB peak private memory for a 256 MiB transfer; Linux splice is **UNVERIFIED (M9)**.
- Members-only videos use HMAC-signed URLs `?exp=&sig=` that last 10 minutes, keyed by `VIDEO_SIGN_KEY_FILE`, so a
  segment request needs no session lookup (07 §4.6).
- hx-download is never used for video: it buffers the whole body in a Blob (D21).

**The content pipeline** is offline, on the dev PC. `tools/transcode` runs 07 §4.3's recipes (verified with ffmpeg
N-124278) into one content-addressed folder per video, and a `jobs` scan imports it:

| Output | Recipe |
|---|---|
| H.264/AAC MP4 | `-movflags +faststart` |
| HLS VOD | `-f hls -hls_time 2 -hls_playlist_type vod -hls_segment_filename 'seg%03d.ts'` |
| AV1/Opus WebM | `libsvtav1` (SVT-AV1 v4.1.0) + `libopus` |
| poster | `-ss <t> -frames:v 1` |
| hover thumbnails | a sprite sheet plus a WebVTT index |

```text
VIDEO_DIR/v/<sha256>/   720.mp4  av1.webm  hls/index.m3u8  hls/seg000.ts …  poster.webp  thumbs.vtt
                        captions/<lang>.vtt  meta.json
```

- Uploaders may also upload web-ready MP4 or WebM through `uploads` (§14.2, up to 4 GiB), with no transcode. That
  in-app upload path is cut-list item 4; the offline import, Range, HLS and MP4 stay.
- ffmpeg never goes into an image (GPL, S21); it is a ledger line as a dev-PC tool (§3). In-app transcoding with a
  host ffmpeg is Q21's non-default option, and no milestone builds it (D44; RESOLUTIONS X27).
- **Public stage**: optionally, a bunny.net pull zone (`VIDEO_CDN_URL`) in front of `/media`, for public videos only
  (Q26). The home uplink is not a binding stage-2 trigger, so public video from home is plausible at family scale and
  the CDN is optional (RESOLUTIONS X41; §20.3). Never Cloudflare's CDN, whose terms forbid video (S20). §20 has the
  hosting side.

### 15.3 Play: games and connect-four (`games`, `c4`)

**Does the game portal need adaptation? Not to embed the games.** The iframe embed of `/play/<g>/?embed=1` works
against today's spark with no change (S22, verified in 06 §2.0), so `games` ships against spark as it is. One small
spark change is required, and only before Houston goes public: SP2, a `frame-ancestors` allow-list on `/play/*`
(hardening: anyone can frame those pages today, 06 §5), which M12's gate needs live. The rest are recommended, not
required: SP1 (a catalog API, about 50 lines), SP3 (an embed-mode test), SP4 (a note that healthz `players` is depended
on) and SP7 (a postMessage bridge, phase 2). Rebuilding the portal itself on the starter is optional (M13). §21 has
the SP table.

`games` (Arcade, `/games`; M10; D34) needs no SQLite. Its catalog is `catalog_static` unless `GAMES_API_URL` is set.

- **Catalog.** `/games` is rendered server-side through `games_web`'s switch over `catalog_static` (a repo JSON of
  brick, gridlock and backpulse, overridable with `GAMES_CATALOG`) and `catalog_api`, which fetches from
  `GAMES_API_URL` on the server and caches with spark's catalog cache pattern (D43). `games_web` picks one at `init`:
  `api` when `GAMES_API_URL` is set, so once spark's `GET /api/games` lands (SP1), and `static` otherwise. Both are pure
  Odin and both are linked (LC §4). Tiles preload; the catalog is history-cached.
- **Embed.** `/games/<g>` is a click-to-play facade, so nobody downloads 0.4–1.7 MB of wasm before asking (06 §2.2).
  Its button `hx-get`s the player fragment (D34's markup plus the `title` of 06 §2.2):

  ```html
  <iframe src="{GAMES_URL}/play/<g>/?embed=1" title="<g>"
          allow="xr-spatial-tracking; fullscreen; autoplay; gamepad; screen-wake-lock; clipboard-write" loading="lazy"></iframe>
  ```

  On `(pointer: coarse)` CSS shows a "Play full screen" link-out instead: iPhone has no element fullscreen (06 §2.2).
  The frame is not sandboxed, because the sandbox would need `allow-popups allow-scripts allow-same-origin`, which
  undoes it (06 §2.0). The route flag `.Frame_Games` adds `frame-src <GAMES_URL>`; the Permissions-Policy header never
  names fullscreen, autoplay or gamepad, which would silently break the frame (D20), and by the same rule it never
  names `xr-spatial-tracking` (**NEW**). In Chrome the `allow` list turns on fullscreen, autoplay, screen-wake-lock and
  clipboard-write; vibration stays blocked in cross-origin frames (06 §2.0). `games-frame.spec` checks the frame in 3
  engines at M10.
- **WebXR in the embed** (RESOLUTIONS X41; §20.8). `xr-spatial-tracking` in the `allow` list lets a WebXR game ask for
  an immersive session from inside Houston's frame, so the VR headset, a test client from M10, can play WebXR games
  inside Houston. `games-frame.spec` gains a WebXR case at M10 (§19.1.4); play on the headset itself is
  **UNVERIFIED (M10)**.
- **Previews are proxied same-origin** at `/games/p/<g>.<crc>.png`, fetched at refresh with a 200 KB cap, so
  `img-src` stays `'self'` and visitors' IPs never reach the games host.
- **The poller**, on one loop, reads `/ws/<g>/healthz` `players` every 5 s and `/api/scores/<g>` every 30 s. Every
  game server answers `ok`, `game` and `players` (06 §1.4). Diffs go to `games.players` (`.Latest`, the tile badges)
  and `games.board:<g>` (an upsert of the top 10, `key:data-score sort:desc`; a ptag poll is the no-stream variant).
  M10 caps it at ≤ 3 GETs per 5 s against spark. A private game answers 404 through the gate and shows as offline.
- **"Invite crew"** is a plain link to `/chat/r/<slug>?draft=<game link>`, for example a gridlock room link with
  `?connect=auto&room=<code>` (D6, 06 §1.4). SP7 later adds instant leaderboard refresh and richer invites, through
  an app.js postMessage listener (D22).
- **The LAN scheme rule.** `GAMES_URL` must match Houston's scheme: an https Houston needs
  `https://games.alexh95.com`, or the frame is mixed content. `http://<APOLLO_LAN_IP>:8111` works only with an http
  starter, and there wake lock, clipboard, Web Share and service workers are off (no secure context) (06 §2.9).
  `GAMES_API_URL` is the server-side base; whether the container reaches `<APOLLO_LAN_IP>:8111` is recorded by
  `promote -Status` at M3 (D42).
- **Rejected**: a reverse proxy under the starter's domain, and SSO (S22).

**`c4`** (Arcade, `/c4`; M10; D34): connect-four as game content that is itself hypermedia. The state is
server-authoritative over WS (`hx-ws` moves), cells are upserted, spectators follow over SSE on `c4.game:<id>`, and
a depth-limited minimax opponent runs in the pure zone. Perm `C4_Play`. It is cut-list item 2.

### 15.4 Operate: ops, status, jobs, modules, dbview

Every `/admin/*` page needs its `Admin_*` perm (Admin only, §17.1) and is LAN-only, in-app and at NPM (D41, Q13).

**`ops`** (`/admin/ops`; M2 in `streams`, M5 in `full`; D36): one 1 Hz publisher renders the metrics registry (13 §5.2:
HTTP, connections per loop, streams and the hub, store, workers, process, modules) once into OOB fragments and
server-side SVG sparklines on `ops.panel`. So N viewers cost one render: M5 asserts flat CPU from 1 to 100 viewers.
Tables use `innerMorph`. The refresh mode is per request (`?mode=`, D8): SSE push, `?mode=poll` with ptag 304s, or
multipart slow panels. SQLite numbers come from `sqlite3_db_status`, because `MEMSTATUS=0` disables
`sqlite3_memory_used` (D16); `platform/store/sqlite` pushes them to `platform/obs`, so `ops` never imports the store
(§5.1). The page shows `last-crash.txt` after a restart (§10). Perm `Admin_Ops`; no Prometheus or Grafana for now (Q25).

**`status`** (`/status`; basic at M2, full at M5; D36): one `multipart/parallel` response. Each part is a feature's
health as pushed to `platform/obs` (§10.4), or a `STATUS_PROBES` external: llama `/health`, the Pi agent's last seen,
games healthz, disk free, the nightly backup's age (a run by hand or a pre-deploy snapshot said beside it, never
counted), the witnesses. Each probe has a 2 s timeout and its part swaps in as it answers;
M5 asserts the parallel order. Details sit behind `Admin_Ops`; a ptag poll every 30 s is the variant. In the lab, the
same feature is the witness board (M3).
**As built (M3):** `STATUS_PROBES` (`name=host:port,…`) is probed by a thread of the feature's own every 10 s, each
`/healthz` with a 2 s socket timeout; the board shows each external's last answer (its state, and its version and
time, which are anyone's), so the parts don't wait on a probe. The lab mounts `status`; the stack's lab names the
three other witnesses. Resolve has no timeout of its own, which a stack network doesn't need; connect has had the probe's 2 s since M5 (M5-09).

**As built (M2)**, both in `streams`. `ops`: the `ops.sample` job (1 s) reads requests (`obs.requests_total`), streams,
the hub's counters (`hub.numbers`), the loops' ticks and the resident memory (`sys.rss_bytes`: Linux's
`/proc/self/statm`, Windows' working set; 0 elsewhere), keeps a minute of samples, renders the cards once out of band
(`innerMorph`) and publishes them on `ops.panel` (`.Sample`); `?mode=poll` answers the kept render with its sample as
the ptag (304 while the poller has it) and `?mode=multipart` streams the topic. The limits table and the last run's crash
file are on the page. The views get obs's modules and limits as the domain's rows, since views import only html and
their domain. `status`: a probe per module that reports to obs (the hub and the bot now do, beside the SQLite store),
plus the loops (down when one hasn't ticked for 2 s) and the process (uptime, version); one `multipart/parallel`
response fills the cards, and `?mode=poll` is the variant, its ptag a hash of the states. Specs: ops on servers of their
own that make loopback admin (`ACCOUNTS_NICK_ADMIN_CIDRS`), each refresh mode, the 304, the crash file, 403 for a
member; status in both modes, the 304, details hidden from a guest.

**`jobs`** (`/admin/jobs`; M5; D36): the scheduler in `platform/workers` runs the mounted `JOBS` rows on the jobs pool
(§6.2): retention sweeps, the nightly backup, the weekly FTS `optimize`, the video import scan, reminders, and in `full`
the lab host's demo resets, `notes.reset` and `contacts.reset`, which put the demo rows back at 04:00 local time under
`NOTES_CAP` (500) and `CONTACTS_CAP` (2000) (RESOLUTIONS X38; §7.3). Job ids carry the feature prefix, as topics do.
"Run now" and cancel call `workers.run_now(id)` and `workers.cancel(run)`, a lookup by id like a route's; workers keeps
each run's state as data,
and `features/jobs` reads it into `jobs_runs` with leases, so a run interrupted by a restart resumes or fails on boot
(13 §3.6), and workers never calls a feature (LC §9). Progress rows upsert over `jobs.runs`, published with key = the
run id, so a new viewer's replay holds the latest row of each run (§9.2); an admin can run a job now, cancel it with an
hx-prompt reason, and download its log. M5 includes a backup and restore drill; backup policy is in §11. Perm
`Admin_Jobs`.

**`modules`** (`/admin/modules`; M4; D36): the granularity made visible. It reads `platform/obs`, `platform/env` and
the tables `platform/app` holds, and imports no feature (LC §5, §9). It lists the profile, its family members (each
one's `NAME`), the switched implementations linked and the current bot default (which bot pushes to obs; D8), the
mounted routes per host with perms and flags, bundle extensions, env (secrets masked, D10), limits, health, and
migrations applied or dormant. It never disables a compiled feature (Q28; D3's never-add list), and it has no switch of
its own: the bot default is set on bot's `/admin/bot`, which it links to (in memory, audited, reset on restart). Perm
`Admin_Modules`.

**`dbview`** (`/admin/dbview`; M5; D36): read-only SQL on a query-pool reader connection (`OPEN_READONLY`,
`stmt_readonly`, `LIMIT_ATTACHED 0`) with a 2 s `progress_handler` budget, because a long read snapshot pins the WAL
(12 §3.3). It never runs under the store lock (06 §3.1's fix), needs step-up and is audited; M5 asserts it never
takes the writer lock. Perm `Admin_Db`; it requires SQLite (D18).

### 15.5 The lab profile's pages

The `lab` profile is the starter's own page at `odin-htmx-starter.alexh95.com`, on an origin with no sessions (D25;
§7). §12 has each extension's proof; these are the pages:

| Feature | Routes | Milestone | What it shows |
|---|---|---|---|
| `landing` | `/` | M3 | the catalog explorer from `docs/catalog.json` (features, implementations, dependencies, sizes, SQLite needs); an init-command builder whose response is the `odin run tools/init -- …` line and its `--explain` output; links to every witness. The builder is cut-list item 11 |
| `status` | `/status` | M3 | the witness board (§15.4) |
| `scripting` | `/scripting/*` | M2 | the `Scripting` bundle with `.Nonce_Csp`: hx-csp nonces, `/scripting/live` (hx-live), `/scripting/streams`, `/scripting/tt` (Trusted Types, no hyperscript) |
| `compat` | `/compat/*` | M2 | the `Compat_Htmx2` and `Compat_Alpine` bundles: `/compat/htmx2` replays the skeleton's htmx-2-era views; `/compat/alpine` is inert |
| `lab` | `/lab/*` | M2 | `/lab/streams`: the raw SSE, WS and multipart contract pages (03's 29 checks), including the WS echo that the nightly Autobahn run fuzzes (§19.1.9) |
| `wiki` | `/wiki` | M8 | `source_files`: the starter's own docs, read-only |

**As built (M3): `landing`** renders the page once at boot from `docs/catalog.json`, embedded (`#load`; the
Dockerfile copies it into the build): the witnesses, a table of profiles and one of features, and the builder, a form
whose fragment `GET /landing/command` answers with the command and a plan computed from the catalog (the dependency
closure, the root, the store a feature needs, the name's shape) or the reasons the generator would refuse it. The
plan mirrors the generator's rules rather than running its `--explain`, which the page names as the authority. The
lab's index moved to `/lab`.

**Houston's lab host** (ANSWERS F2, round 3). From M4, when `cmd/full` first exists, `full` also serves the same
packages on `houston-lab.alexh95.com`: `landing` at its root, `/lab/*`, `scripting` and `compat`, with the same bundles
and nonce class as here, and beside them the skeleton's `notes`, `contacts`, `gallery`, `about` (RESOLUTIONS X36) and
`dashboard` (at `/dashboard`), their demo data capped (`NOTES_CAP` 500, `CONTACTS_CAP` 2000) and reset nightly at 04:00
local time (RESOLUTIONS X38). The host runs no identity and sets no cookie, and only the
rows its table mounts answer there (§7.3). The witness board stays in `lab`, which remains the independent witness.

## 16. The terminal console to the Raspberry Pi

The brief asks how Houston connects to the Pi Alex will set up later. The answer: an Odin agent on the Pi dials out
to Houston over WebSocket, and the VT parser runs in that agent, outside the server process (D32; Q8: agent-side VT,
confirmed by Alex on 2026-10-25). The feature is
`term` (Console, `/term`, agent at `/term/agent`; devices at `/admin/term` under `Admin_Term`; M11). It requires
SQLite (D18). The mode, line or PTY, is a per-device setting; line mode is the lean default (D8, D26).

**The devices** (RESOLUTIONS X41; §20.8). The target is Alex's own Raspberry Pi 4 (4 GB) on 64-bit Pi OS Lite, wired
to the LAN. A Pi 3B+ is the second device for multi-device tests (§16.6). A Pi Zero class board can't run the agent: it
is ARMv6 and 32-bit only, and the agent is linux_arm64.

### 16.1 Decision and order

| Step | What ships | Effort (D44) |
|---|---|---|
| T1 line mode (first) | the agent runs allow-listed commands; output streams as a POST → SSE one-shot into `<pre role="log">` | 15 h |
| T2 PTY | the agent spawns a PTY and parses VT with `features/term/vt`; the server renders grid frames to HTML over `hx-ws` | 55 h |
| T3 | watch mode, recordings written by the server, a per-device kill switch | 20 h |

**Why the parser lives in the agent.** 13 §2.1 put VT parsing either in the browser or, if server-side, "in a
subprocess if ever built". The agent is that separate process, and it already exists. A parser bug or hang kills only
the agent, which systemd restarts; it never takes Houston down through the watchdog. The server still owns what
watchers see and what is recorded, because the screen arrives as frames it validates and renders.

**Why not the alternatives:**
- **xterm.js**: 488 KB of second runtime (`lib/xterm.js` 6.0.0 is 488,663 B, 07 §0.4), and its DomRenderer needs
  `style-src 'unsafe-inline'` (11 §5.2). Not shipped; an xterm.js lab is on the never-added list unless Alex asks (Q8).
- **SSH from the server**: needs libssh2/libssh (a C dependency) or thousands of lines of SSH on `core:crypto`, plus an
  inbound port and key management on the Pi (07 §3.2b).
- **ttyd** proxied: ships xterm.js and its own page, and needs an inbound port or a tunnel (07 §3.2c).

The terminal is a deliberate stress test of latency-hostile UX (§3). If time runs short, T3 then T2 are cut-list item
5; T1 with the agent stays.

### 16.2 The agent (`cmd/term-agent`)

- **Build.** Odin, `linux_arm64` (64-bit Pi OS), built by the `term-agent` CI job on GitHub's `ubuntu-24.04-arm`
  runner, because Windows can't link Linux targets (09 §6.4; Windows emits aarch64 objects, but linking needs an
  aarch64 linker and sysroot, 07 §0.6). The arm64 build is **UNVERIFIED (CI job term-agent)** until that job runs.
- **Run.** An unprivileged systemd unit, `deploy/pi/term-agent.service`. It dials out to
  `ws://<APOLLO_LAN_IP>:8120/term/agent` (the stack Caddy with `Host: houston.alexh95.com`; LAN-direct, never through NPM)
  with a device token, and reconnects with backoff. The Pi needs no inbound port (07 §3.2a). It uses
  `platform/stream/client`, the starter's one streaming client (**NEW**, D12). The unit reads
  `/etc/houston/term-agent.env` as an `EnvironmentFile`: `TERM_AGENT_URL`, `TERM_AGENT_HOST` and `TERM_AGENT_TOKEN_FILE`
  → `/etc/houston/term-agent.token`, mode 0600 (Q30; RESOLUTIONS X15).
- **Delivery.** The `release` workflow attaches the linux_arm64 `term-agent` binary and its SHA-256 to the GitHub
  release as an asset, and Alex copies it to the Pi (Q30). The agent sends its version in `hello`, and `/admin/term`
  flags outdated agents.
- **Allow-list on both sides.** Line mode runs only allow-listed argv entries (`uptime`, `df -h`, `vcgencmd
  measure_temp`, `systemctl status <unit>`), never a shell. The server holds the list per device, and the agent
  enforces its own local list as well, so a compromised server can't widen it.
- **PTY** (T2): `posix_openpt`, `grantpt`, `unlockpt`, `ptsname`, then `fork`, `setsid`, `execve`, all in
  `core:sys/posix` (07 §0.6).
- **Parser** (`features/term/vt`): the DEC ANSI state machine, UTF-8, wide characters, the alt screen, scroll regions
  and SGR mapped to classes; 1,500–2,500 lines (07 §3.3).

Binary frames, multiplexed by session:

| Frame | Direction | Payload |
|---|---|---|
| `hello` | agent → server | device id, token, agent version (`/admin/term` flags outdated agents), os, arch |
| `open` | server → agent | session, cols, rows, and what to run |
| `input` | server → agent | session, bytes (keys already mapped to bytes by the server) |
| `resize` | server → agent | session, cols, rows |
| `grid` | agent → server | session, dirty rows as style runs, the cursor |
| `raw` | agent → server | session, the output bytes (for the recording) |
| `close` | either way | session, exit code or reason |
| `ping` | either way | none |

Field lists follow 07 §3.2 and D32. The exact encoding, and how line mode uses `open` and output frames, is set by the
agent-side grid protocol spike at the M11 start: **UNVERIFIED (M11)**.

### 16.3 Server side (`features/term/grid`)

- **Three parts**: a validated frame decoder (pure zone, fuzzed, D15), a bounded cell grid per session, and a row
  renderer. A trap in the decoder closes that stream with 1011 and leaves the server serving (D15).
- **Coalescing**: dirty rows are gathered every 16–33 ms and sent as `<hx-partial hx-target="#t<s>-r<y>"
  hx-swap="outerHTML">` frames over the browser's `hx-ws`, the page's one `hx-ws:connect` (D14). A row is a
  `<div id="t<s>-r<y>">` with one `<span class>` per style run; truecolor is `style="--fg:…"`, which
  `style-src-attr` allows (11 §5.2). Full redraws can `innerMorph` the screen (D21).
- **Render cost**: 80×24 in 53 µs (9 KB of HTML) and 200×50 in 274 µs (46 KB) (07 §3.3). D38's budget is
  ≤ 100 µs for a full 80×24 render (§18).
- **Watchers** (T3) hold `Term_Watch` and follow `term.session:<sid>` over SSE, read-only; a new watcher gets the
  current grid at once.
- **Recordings** are asciicast v2, written by the server from `raw` frames, so they live on Houston's volume, out of
  the Pi's reach (audit integrity, D32). They download with hx-download.
- **Accessibility**: the grid is not a live region, since a redraw would flood it; an opt-in polite live region gets
  line-mode text only (11 §7.4). Terminal pages carry `.Private` (`no-store`, `noindex`; 11 §5.2).

### 16.4 Input

- A labelled `<textarea>` takes the keys, for screen readers (11 §7.4). `TermKeys` (`html.behave(b, .Term_Keys)`)
  feeds them to a hidden `hx-ws:send` form. Whether `hx-ws:send` fires on a custom trigger is **UNVERIFIED (M11)**:
  a spike at the M11 start settles it, and the fallback is a 30-line app.js sender.
- `MeasureTerm` divides the container by a measured cell size and sends `resize`.
- The key-to-bytes map lives on the server (arrows → `ESC [ A`, Ctrl-C → 0x03, application cursor mode; 07 §3.3).
- Both behaviours are hyperscript-only. Under D22's progressive-enhancement rule the core flow is T1 line mode, which
  is plain forms plus SSE; PTY typing needs `TermKeys` or the fallback sender.
- Latency estimate on the LAN: typing echo 5–40 ms, dominated by the coalescing window (07 §3.3). D38's budget is
  key echo p95 ≤ 50 ms, measured on the real Pi at M11 (**UNVERIFIED (M11)**).

### 16.5 The fallback

If the agent approach fails its M11 spike, the same `vt` package runs behind `houston --worker vt`, a same-binary
subprocess on apollo. A round trip costs 22.7–28 µs on Windows and 59–71 µs on WSL2 (13 §2.2), paid once per
16–33 ms batch, not per byte. The worker takes an explicit quit frame and a kill deadline, because a parent's
`process_wait` hung once on Windows (13 §2.2).

### 16.6 Testing before the Pi exists

- **CI agent**: an amd64 agent runs in the CI container against `/bin/sh`, so the browser side is the real one
  (07 §3.7). The e2e checks: `echo hi` shows `hi`; `printf` colour codes give the expected classes; an alt-screen app
  enters and leaves; resize changes `stty size`; a watcher sees the same screen and can't type; a kill from admin
  closes both sides; recordings download.
- **Replay agent**: plays recorded vim, less and htop byte streams; golden screens (with the `tput` matrix) catch
  regressions.
- **Fuzz**: the term grid decoder and the agent's VT parser are libFuzzer targets nightly; M11 needs a 24 h VT fuzz
  with 0 crashes (D37, D44).
- **Load**: terminal grid throughput (`cat` of a large file through parse and render) is one of D37's per-feature
  load scenarios (07 §3.7).
- **Two real devices** (M11; RESOLUTIONS X41): the Pi 3B+ runs a second agent beside the Pi 4, so device rows,
  tokens, per-device limits and the per-device kill switch are exercised across two devices, not one (**NEW**).

### 16.7 Hardening and network

D35's terminal hardening is in §17.9: `Term_Write` for Admins only, with TOTP and step-up; device tokens shown once
and stored as SHA-256; the session limits; the audit list; and recordings of writable sessions, output only, kept
30 days or 1 GiB in total, whichever comes first, never raw input (Q12; RESOLUTIONS X10).

Reach: `.Lan_Only` on `/term*` (D32) and on every `/admin*` page, `/admin/term` included (D41, Q13; §17.2); NPM
answers 403 on `/term/agent`, which refuses any `Origin` and accepts only device tokens (D32, D35). D32 itself names
only `/admin/term*`; D41's wider scope holds. The terminal stays LAN-only, in-app and at NPM, after Houston goes public
(Q13). Beyond the LAN, if it is ever needed, a WireGuard overlay carries plain ws, rather than TLS (OpenSSL) in the
agent (Q9). Port 8120 on apollo looked free but is **UNVERIFIED (M3)** (08 §6.5).

**Alex's M11 steps:**
1. Bring the Pi 4 home, flash 64-bit Pi OS Lite, wire it to the home LAN (inside `LAN_CIDRS`, able to reach
   `<APOLLO_LAN_IP>:8120`) and reserve its address (RESOLUTIONS X41).
2. Register the device on `/admin/term` (`Admin_Term`, LAN only); its token is shown once.
3. Copy the linux_arm64 `term-agent` binary from the GitHub release (check it against the SHA-256 beside it) and
   `deploy/pi/term-agent.service` to the Pi; write `/etc/houston/term-agent.env` with
   `TERM_AGENT_URL=ws://<APOLLO_LAN_IP>:8120/term/agent`, `TERM_AGENT_HOST=houston.alexh95.com` and
   `TERM_AGENT_TOKEN_FILE=/etc/houston/term-agent.token`; put the token in that file with mode 0600; enable the unit
   (Q30's default; RESOLUTIONS X15).
4. Check the device's last-seen time and agent version on `/admin/term` and on `/status` (§15.4), then open `/term`.
5. For the multi-device tests (§16.6), the same steps on the Pi 3B+, with its own device row and token (its role is
   Proposed, to confirm at M11; §20.8).

## 17. Security model

Every security rule lives here; feature sections point to it (headers and CSP: §12.2; stream limits: §9; crashes: §10).
Gates (§22): `rbac.spec`, `revoke.spec` and the CSRF and CSWSH specs at M4, a focused audit of accounts, sessions, chat
and uploads before the first invite at M6, and the full-tree audit before stage 2 at M12.

### 17.1 Accounts and authentication

**Roles and permissions** (D35). `Role :: enum u8 {Guest, User, Mod, Admin}`, labelled Guest, Member, Moderator and
Admin. `Perm` is one closed enum in `platform/authz`, grouped by feature (under 64 members, one `bit_set` word), plus
`.Public` on a route for "no check" (D5). `ROLE_PERMS :: [Role]bit_set[Perm]` is the single table. There are no
per-user grants in v1, and the generator deletes the perm groups of deleted features (D26). D35 fixes the members and
tables the three grants that are judgement calls (Q31, below); the rest of this table is this plan's default
(**NEW**). `rbac.spec` freezes the whole table when it is generated at M4.

| Perms | Guest | Member | Moderator | Admin |
|---|:-:|:-:|:-:|:-:|
| `Bot_Use` (guests: mock only), `Video_Watch`, `Wiki_Read` (services check per-item visibility) | ✓ | ✓ | ✓ | ✓ |
| `Account_Self`; `Chat_Read Chat_Post Chat_Dm Chat_Create_Room Chat_Attach`; `Bot_Llama` | | ✓ | ✓ | ✓ |
| `Wiki_Edit`; `Lists_Edit`; `Polls_Create Polls_Vote`; `Calendar_Edit`; `C4_Play` | | ✓ | ✓ | ✓ |
| `Chat_Moderate`; `Video_Upload Video_Moderate`; `Guestbook_Moderate`; `Term_Watch` | | | ✓ | ✓ |
| `Term_Write` (TOTP + step-up); `Admin_Accounts Admin_Audit Admin_Ops Admin_Jobs Admin_Modules Admin_Db Admin_Term` | | | | ✓ |

**Three default grants are Q31** (D35; RESOLUTIONS X16). They are judgement calls, so Alex decides them with Q31
(§22.7); the default is the table as it stands, frozen by `rbac.spec` at M4:
- `Term_Watch` goes to Moderator and Admin, so D29's "a family member watches read-only" (§13.3) needs that person
  to be a Moderator;
- `Video_Upload` goes to Moderator and Admin, because D35's "uploaders only" is not a role (RF §8.6 had Admin only);
- `Admin_Audit` is Admin only, where PF §6.1 let moderators see their own entries.

**Passwords** (D35, S11). argon2id runs on the argon pool, never on a loop: `ACCOUNTS_ARGON_THREADS` 2 (1 when the
container has ≤ 2 CPUs, as apollo's `full` does: Q34, answered 2026-10-26), at most that many concurrent verifies and a queue of
32, then 503 "busy, retry"; the handler defers its response (F-13), and each worker keeps one buffer for argon's memory,
so the pool holds threads × 19 MiB and never allocates per login. The parameters are OWASP's (19 MiB, t = 2, p = 1):
S0.5 measured 19–32 ms per verify on the dev PC (medians, both OSes, a busy box; two at once barely slower), while the
64 MiB preset took 119–191 ms and is out; OWASP's 7 MiB, t = 5 preset is the fallback for a tight `mem_limit`. Whether
apollo verifies in ≤ 100 ms was **UNVERIFIED (M4)**: `--hash-password` prints its own derive time. *Measured
2026-11-01* from the v2.3.0 image on apollo (a throwaway password, nothing written): `derive: 33.9 ms`, a 98-byte PHC
string, so a sign-in there costs about a third of the 100 ms budget. Compares are constant-time; unknown usernames get a dummy hash; passwords are 10–256 bytes; failures
cause per-account exponential backoff, never a hard lockout (no lockout-as-DoS, 07 §5.2); the last admin can't be
demoted or disabled. Alex makes the bootstrap hash with `--hash-password` and never shares the password (M4).

**Sessions.** An opaque 32-byte token in cookie `sid`: `HttpOnly; SameSite=Lax; Path=/` with no `Domain`, so it is
host-only and never reaches `full`'s lab host (§17.2), plus `Secure` when the request arrived as https through a
trusted proxy (`COOKIE_SECURE=auto`). Only SHA-256(token) is stored. The token
rotates on login and on any privilege change; sessions expire after 14 days idle or 30 days absolute; members see a
sessions page with revoke. Browsers drop `Secure` cookies on plain http (07 §5.5), so stage 1a (LAN http) runs
`COOKIE_SECURE=0` with a warn line on every boot and a banner.

**As built (M4, slice 3):** `features/accounts/identity_accounts` over the `accounts` domain, `full`'s identity. The
token is 32 random bytes as unpadded base64url; the cookie's `Max-Age` is the absolute life. A sign-in is two hops
off the loop behind one deferred response (the verify on the argon pool, then one write that opens the session,
closes the one the request carried, sweeps the user's dead sessions and clears their failures); it counts as a
step-up. `last_seen` is written at most once a minute. The first three wrong passwords are free, then 1 s doubling to
5 min. `ACCOUNTS_SESSION_IDLE`, `ACCOUNTS_SESSION_MAX`, `ACCOUNTS_LOGIN_PER_CLIENT` and `ACCOUNTS_LOGIN_OVERALL` carry
§17.5's values as defaults (*since M5, M4-03:* `ACCOUNTS_LOGIN_PER_NET` adds a bucket per /24 or /48, the overall one
counts only password checks, and a device cookie gives a client that signed in before a backoff of its own), so the suites can lift them and test them on servers of their own. Until the shell has a
banner slot, `COOKIE_SECURE=0` is said on the sign-in form. The first admin: `ACCOUNTS_ADMIN_HASH` with
`ACCOUNTS_ADMIN_NAME` (`admin`), while no enabled admin exists.

**As built (M4, slice 5):** `platform/totp` holds RFC 6238 (HMAC-SHA1, 30 s, 6 digits, a step either side). A sign-in to
an account with TOTP answers its password with a code form carrying a pending token (the user id and five minutes,
HMAC-signed with a key made at boot), and `/login/code` takes a code or one of the ten recovery codes (40 bits each,
SHA-256 stored), spending it in the same write that opens the session (`users.totp_last_step`, `used_at`): a
replayed code is refused. `/step-up` takes the password or a code and returns a write to the page htmx says it came
from. An Admin without TOTP loads as a Member (`ACCOUNTS_ADMIN_TOTP=required`, the default). The admin-issued reset
codes come with `/admin/accounts` (slice 6).

**As built (M4, slice 6):** `/register` follows `ACCOUNTS_REGISTRATION`; an invite is `/register?code=<five groups of
four>` (100 bits, stored hashed), and one write spends it (its role, its uses), creates the member and opens their
session. A reset code is three groups (60 bits) for 24 hours, one live per member; `/reset` spends it with a new
password and ends every session. `/admin/accounts` is LAN only; each write is a `.Step_Up` row whose `HX-Prompt` reason
is required and audited, and a role change or a disable ends the member's sessions (a new sign-in picks up the role:
the rotation on a privilege change). The last enabled admin can't be demoted or disabled, in the store's own write.
`accounts_prefs` waits for its first reader (the theme, chat's transport and mutes).

**As built (M4, slice 7):** `features/accounts/identity_envadmin`: the cookie is `admin=<issued>.<expires>.<mac>`
(HMAC-SHA256, 7 days by `ACCOUNTS_ENVADMIN_LIFE`), the issue time is the viewer's `step_up_at`, and `/step-up` takes the
password and issues a fresh cookie. Sign-ins are limited as `accounts`' are and audited through `store:audit` (a
`mod=audit` line on a memory build). The nightly `envadmin` job generates `--identity envadmin --features notes` and
runs the whole e2e suite on it.

**As built (M4, slice 8):** `hub.revoke(user_id)` kicks every member topic of the user on every host with 1008. The
layout's `#live` for a member carries `data-revoke="/login"`, and core.js navigates there on `kicked` from it, so a
page's own kick (the lab's) still reconnects. UNVERIFIED (M4) answered: hx-sse keeps reconnecting after a 403, with a
backoff (5 times in 30 s), so core.js marks an element whose stream was refused with 401, 403 or 404 and cancels its
next connection (`htmx:sse:before:connection`). `identity_accounts` declares `accounts.user` (`member = true`); `full`
mounts the hub for it. A role change and a disable revoke; revoking one session doesn't (the member's topic spans
their devices), and that device's stream ends at its next request. *Since M5 (M4-09):* `authz.Viewer.session` keys
a session, `/events` records it on the stream, and `hub.revoke_session(user, session)` kicks only the streams that
session opened, which a sign-out and a member's revoke of a device call; the member's other devices stay. The hub keeps its newest
64 revokes, and `/events` kicks a stream whose viewer was revoked after its request began.

**As built (M4, slice 9):** `/admin/modules` is `features/modules`, a web package alone (LAN only). `platform/app` fills
`web.build` at `app.check` (profile, families, features, the main bundle's extensions, every route per host with its
perm and flags), and `store/sqlite`'s `migrate` appends to `store.in_force`, so the page imports no feature and no
store (`tools/check imports` refuses one). The env table shows a secret only as set or unset. The switched
implementations aren't listed (they are per request, `x-impl`; the catalog names them).

**As built (M4, slice 10, part a):** `full`'s `HOSTS` has its second row, `{"lab", "SITE_URL_LAB", false, LAB_ROUTES,
LAB_NAV}`, and `app.serve` takes `{&BRAND, &LAB_BRAND}`. The main host's tables keep the names tools/init reads
(`ROUTES`, `TOPICS`, `JOBS`, `NAV`) and the lab host's are `LAB_*`; tools/init writes and edits one-host profiles only.
Boot refuses two hosts whose origins name one host; a loopback origin counts as a placeholder (no `*.fly.dev`
redirect, and WS upgrades match by host). In the suites one server answers both: the lab host is `127.0.0.1` (its
origin `https://127.0.0.1`) and the main host `localhost`, any other name, and a spec goes to its own feature's host.

**As built (M4, slice 10, part b):** the contacts demo's cap and reset are switched on by the profile, not by the
feature: `full` calls `contacts_web.demo_init()` (`CONTACTS_CAP`, 2000; `CONTACTS_RESET_HOUR_UTC`, 2) and mounts
`contacts_web.DEMO_JOBS` (a once-a-minute check that resets once a day at that hour; tools/init reads `JOBS`, not
`DEMO_JOBS`). The hour is UTC: the distroless image has no tz database, so "04:00 local" is 2 in winter and 05:00 in
summer. `notes` isn't on the lab host yet (its card is `home`'s, Houston's), so `NOTES_CAP` waits with it.

**As built (M4, slice 10, part c):** `starter-full` sits in `deploy/compose.yaml` behind the `houston` compose profile:
`up -d --no-deps starter-full` (promote's) starts it, a plain `up` (the stack test's, or a stack before Houston's first
release) doesn't. `ACCOUNTS_ADMIN_HASH` arrives as `ACCOUNTS_ADMIN_HASH_FILE` from the compose secret `admin_hash`
(`./admin-hash` beside `compose.yaml`), since compose would read a PHC string's `$` as variables in `.env`. Its tag
is `${TAG_FULL:-unreleased}`, not `:?`, so a stack whose `.env` doesn't name it yet still promotes the rest. promote
lists it with `Sse`/`Ws` off (its streams need a member) and snapshots its database before each promote.

**As built (M4, slice 10, part d):** the `houston` palette is a scheme of the `modern` style (`theme/full`, 6 × 24),
named by `cmd/full`'s `BRAND` (`style`, `scheme`: a brand's server-rendered default; the lab host keeps the theme's).
The accounts identity sets `authz.theme_href` (`/accounts/theme`) and loads `style`/`scheme` from `accounts_prefs`
with the viewer (one indexed read per signed-in request). The layout writes `data-theme-href` for a member, so
core.js's picker posts there as well as to localStorage, and `data-kept` with the member's theme when one is kept: the
pre-paint script skips localStorage on such a page, so the server's choice wins on every device. The route accepts
only a style with one of its own schemes (`html.theme_known`), 422 otherwise.

**As built (M4, slice 11):** `full-vanilla` is the `build.sh` row `full-vanilla) … client=vanilla theme=full src=full`
(and its `build.bat` block): `BUILD_DIR` stays `build/full-vanilla`, so prepare bundles its own assets (it bundles every
row with a `src=` after the `app/cmd/*` profiles), and the binary is `app/bin/full-vanilla`. tools/check reads the
row's `src` (its checks run on it like any profile's; parity skips it, since `full`'s runs reach the same routes) and
tools/init skips it, since it composes nothing of its own. `full` needed no new behaviour or twin: its flows are
forms and htmx, and what it renders on the hyperscript client is twinned or an enhancement. CI checks it, builds it
on ubuntu and runs the chromium specs on it; `escaping.spec` adds the vanilla side of "injected `_` inert".

**As built (M4, slice 12):** `rbac.spec` and `cross-site.spec` are api-only and reach no handler. rbac probes each row
of `--routes --json` with htmx's header, so a refusal is the gate's own (401 with `HX-Redirect: /login`, or front's
403 "Not allowed."), and a write carries a Content-Length past every cap with no body: front checks the rule before
reading a byte, so an admitted write stops at 413 (with `Connection: close`, which spares a refusal odin-http's
drain of the unread body). The roles are the bootstrap admin and two members an admin's invites make; the grants
are a literal table in the spec, so changing `authz.ROLE_PERMS` fails it until the spec (and the decision) is
updated. Behind a proxy, the e2e server answers the proxied names: `E2E_PROXY` for the main host and
`E2E_PROXY_LAB` for the lab host, and direct helper calls to it name them too.

**As built (M4, slice 13):** the covering array is a seeded greedy search (`tools/init/pairwise.odin`): each round
forces the first pair still uncovered, draws 400 random selections around it, keeps those `select` accepts (closed
over dependencies and identities, never `dashboard` with `landing`) and takes the one covering the most pairs left; a
pair no draw can hold is listed as infeasible. The generator is a fixed xorshift, so seed 1's 15 rows are the same on
every machine; there are more than §19.1.12's 8 because the families exclude pairs (`chat` and `contacts` need
different stores, `scripting` and `accounts` different identities). Nightly's `selections` job adds three
`--random` selections seeded by the run number and every singleton, and runs each generated project's boot checks and
its chromium and api specs.

**TOTP and step-up** (Q11). TOTP follows RFC 6238 (vectors verified, 07 §0.6) with manual secret entry and the
`otpauth://` text, no QR encoder. It is required for Admin and `Term_Write`. **Step-up** asks for the password or a
TOTP code within the last 10 minutes on `.Step_Up` routes: `Term_Write`, role changes, invites and dbview. Recovery
without email: 10 recovery codes per account and admin-issued one-time reset codes, both stored hashed (07 §5.2).

**Registration** (Q10): `ACCOUNTS_REGISTRATION` is `invite` by default (open and closed are the other modes). Display
names pass spark's `clean_name` (06 §3.1); avatars go through uploads (§17.6); `accounts_prefs` holds theme, chat
transport and mutes.

**Identities are a family** (§2.8; LC §3): one per build, chosen by `-collection:identity=…`, which `front` calls
through `authz.Load_Viewer`; each also answers its own CLI flags (`identity.cli`) and mounts its own `ROUTES`. **The
other identities** need no SQLite (D18, D35). `envadmin` is one admin from `ACCOUNTS_ADMIN_HASH` with a signed
stateless cookie (the spark pattern, 06 §3.1); it can't revoke one session at a time, and rotating the key signs
everyone out. `nick` is a signed nickname cookie with role User; `ACCOUNTS_NICK_FROM=lan` grants it only to clients in
`LAN_CIDRS`, so a public visitor to a witness is a Guest, who under the table above has no `Chat_Read`: chat shows them
a "chat is open on the LAN" notice instead of the rooms (ANSWERS round 9). `ACCOUNTS_NICK_ADMIN_CIDRS`, empty by
default, makes nick's clients in it Admin, so a `streams` witness's `/admin/ops` opens for them; the e2e suite sets it to
loopback, and on apollo Alex may name his PC (round 9). nick is built at M2 for `streams`, ahead of the rest of
`accounts` (§22.3). `anonymous`, the default, makes everyone a Guest.

### 17.2 The enforcement point

1. **Route level, in one place.** `front`, in `platform/app`, loads the `Viewer` through the build's identity and checks
   the route row's `perm` before the body is read (D35, D5; §8.4). Guests get 401 with `HX-Redirect: /login` for htmx
   requests (a 302 otherwise); others get 403. `.Step_Up` routes send stale sessions to the step-up page. Views never
   enforce: they get the `Viewer` only to hide controls.
2. **Resource level, in services**: own message, moderator of this room, owner of the conversation, video and wiki
   visibility. Members-only media use HMAC-signed URLs that expire in 10 minutes (D33, §15).
3. **Streams.** Each topic row's `subscribe` checks the perm on subscribe, and one failure answers 403 (D13; §9.2). A
   kick or role change publishes a revoke that closes the affected streams with 1008, which htmx doesn't reconnect (§9).
   An SSE stream gets the named `kicked` event, which navigates to `/login`, and `revoke.spec` holds the server to at
   most 3 reconnects in 30 s (§19.1.3; RESOLUTIONS X19).
4. **`.Lan_Only`** routes (`/term*`, D32; `/admin*`, D41, Q13) answer 404 unless the trusted client address is in
   `LAN_CIDRS` (192.168.0.0/16). This is enforced and tested in-app; NPM Access Lists are a second layer (D35, Q13).
5. **Host tables** (`full`; §7.3, §8.4). A row answers only on the host whose table mounts it: Houston's table
   mounts no demo or lab package, and the lab host's mounts no Houston package, so each 404s on the other host.
   `.Lab_Host` rows (`/scripting/*`, `/compat/*`) may be mounted only on a host where no cookie-setting identity runs,
   and a host with no identity holds only `.Public` rows, both boot checks (§6.1 check 4; ANSWERS F2). On the lab host
   `front` runs no identity, reads no `sid` and sets no cookie. The isolation is the lab profile's own:
   Houston's `sid` is host-only, §17.3's `same_origin` guard refuses the lab host's writes to Houston (they carry
   `Sec-Fetch-Site: same-site`), and the WS `Origin` check refuses its upgrades.

**As built (M4, slice 1):** the check is `authz.refusal`, a pure proc over the viewer, the row's rule, whether the
client is on the LAN and the time; `front` maps its answer (`.Not_Found`, `.Sign_In`, `.Forbidden`, `.Step_Up`) to the
responses above, a stale session going to `/step-up?next=<path>` (a 401 with `HX-Redirect` for htmx, a 302
otherwise). The identity sets `Viewer.step_up_at`; one without passwords never does, so its `.Step_Up` rows always
step up.

`rbac.spec` is generated from `bin --routes`: every route × every role → the expected status, over 100 % of routes
at M4 (D37, D44). `bin --routes` prints each host's table, so in `full` it also runs every route × both hosts: a row
answers on the host whose table mounts it and 404 on the other, and a lab-host request carrying a valid `sid` is
answered as a Guest (ANSWERS F2; LC §11).

### 17.3 CSRF and cross-site WebSocket hijacking

CSRF is `SameSite=Lax` plus the skeleton's `same_origin` guard, unchanged
(`SK/app/src/controllers/middleware.odin:222-242`): a request with any method but GET, HEAD or OPTIONS must carry
`Sec-Fetch-Site` same-origin or none, or an `Origin` whose host equals `Host`; anything cross-site gets 403 before its
body is read, and a request with neither header isn't from a browser and passes. GETs stay side-effect free, because
hx-preload sends no `HX-Preloaded` header (04 §4.5); read receipts are POSTs for that reason (D30).

A WebSocket upgrade is a GET with no `Sec-Fetch-*` (04 §4.4), so `same_origin` passes it. Every upgrade therefore
checks `Origin == SITE_URL` itself (D12). `/term/agent` refuses any `Origin` and accepts only device tokens. SSE GETs
can leak only to same-origin `fetch` (CORS), so the cookie is enough there (03 §7). The M4 specs send a cross-site
POST and a foreign-Origin upgrade and expect 403 for both (07 §5.6).

### 17.4 Injection

Views are the only place HTML is built (D4). The escaping boundary is the skeleton's: dynamic text and attributes go
through `esc`, `href` and query values through `url_encode`, values inside JSON through `json_esc`; helpers take text,
not markup, and user text is cut by rune (`SK/CLAUDE.md` "Views").

**Hyperscript changes what the CSP means** (05 §5): an injected `_` attribute or `<script type="text/hyperscript">`
in swapped content runs, so the CSP no longer backstops an escaping mistake. Four defences (D22, RF §8.4):

| # | Defence | Why |
|---|---|---|
| 1 | `esc()` on every value | as above |
| 2 | dynamic data only in `data-*`, never inside `_` | the browser decodes `&#39;` before hyperscript parses `_`, so an escaped value broke out (05 §5) |
| 3 | the install-only gate in app.js (§12.4) | verified to block both injection forms (05 §5) |
| 4 | `hx-ignore` + `data-disable-scripting` on every UGC body element (messages, bot output, guestbook notes, terminal output); the list container carries neither, so server-rendered actions keep working | swaps into `hx-ignore` get no hyperscript init (05 §3), but hyperscript's own page scan ignores `hx-ignore`, so both are needed (11 §5.2) |

Besides the checks in §12.4, `escaping.spec` asserts that XSS payloads in every UGC field render as text (D37).
Behaviours never `put` server data (05 §5).

**Other channels.**
- Markdown (`platform/markdown`): depth cap 32 and input cap 64 KiB (spark's renderer overflowed the stack at 2,000
  nested quotes, 06 §3.2); raw HTML shown as text; links only http(s), mailto and same-site (06 §3.1); rendered at
  write time (D36); fuzzed at M8.
- The SSE encoder splits user text on CR, LF and CRLF, so no field injection (D12, 03 §10.2); multipart uses a
  random boundary, because a body line starting with the boundary would end the part (04 §4.3).
- The WS codec is strict RFC 6455 (UTF-8, control frames, version) with 64 KiB messages (D12, D13).
- `clean_name` refuses bidi overrides, zero-width and control characters (06 §3.1). UGC links carry
  `rel="noopener noreferrer nofollow ugc"` (11 §5.2).

### 17.5 Rate limits

spark's fixed-window limiter, keyed by the hashed client id (a truncated SHA-256 of a daily salt and the trusted
address, never stored raw), never the TCP peer (D35; 06 §3.1, 07 §0.1). Fixed windows allow a 2× burst at a window
boundary, and counts are per process (06 §3.1).

| Limit | Value |
|---|---|
| login | 5 per 15 min per client id, 40 per 15 min overall, per-account backoff |
| register / invite redemption | 3 per hour / 10 per hour per client id |
| chat post | 5 per 10 s per user, burst 10; WS frames 20 per second per connection (close 1008) |
| typing | 1 per 2 s |
| bot | 1 concurrent per user; members 30 per hour; guests 5 per hour per client id (mock) |
| uploads | 20 per hour per user, 2 concurrent |
| guestbook | 3 per hour per client id |
| find / palette | 10 per second per user |
| votes, RSVPs | 10 per minute per user |
| stream connects | 20 per minute per client id |
| `/csp-report` | 10 per minute per client id; each report logged at warn; only `full`, `streams` and `lab` send `report-to` (§12.2; RESOLUTIONS X11) |

429s carry `Retry-After` and route to the toast slot (`hx-status:429`).

**As built (M2):** `web.Limit{n, window}` is that limiter, one per concern, `web.limit_hit(&l, key)` keyed by a member's
id or `web.client_key` (the hashed address), and `web.respond_limited` answers the 429 with `Retry-After` in whole
seconds and a toast. Its keys are bounded: past 4,096 a limit forgets everyone, which only ever lets through a hit it
would have refused. Chat's posts and typing and `/csp-report` use it (stream connects keep `platform/stream`'s own count).

### 17.6 Uploads

Chunked (D35; the flow is in §14.2): chunks of at most 4 MiB under a per-route body cap (the default stays 64 KiB).
Images up to 10 MiB; video up to 4 GiB, for holders of `Video_Upload` only. Magic-byte sniffing, then a full decode
with `core:image` under a 40 MP pixel cap; blobs are content-addressed; responses carry `nosniff` and
`Content-Disposition: attachment` for anything that isn't an image; SVG and HTML are never served inline. At most 8
concurrent uploads × 4 MiB are in flight. NPM streams bodies through (`proxy_request_buffering off`,
`client_max_body_size 16m`, D41). M6 adds a decode-bomb fuzz.

### 17.7 Audit log

`features/audit` (D35): `audit_log` is append-only by triggers (no update; deletes only past 400 days). It records
every admin and moderator action with its `HX-Prompt` reason, the actor, the target and the hashed client id, never
message bodies or passwords. `/admin/audit` (`Admin_Audit`) has filters, keyset infinite scroll and CSV through
hx-download. Every package that audits calls `audit_store.append` through `store:audit`, the one store any domain, web
or identity package may import: the SQLite family writes the `audit_log` row, and the memory family one `mod=audit`
log line. `/admin/audit` is mounted only in SQLite profiles (D6; LC §9; §6.2).

**As built (M4, slice 4):** `append(actor, action, target, reason, meta)` queues an op nobody waits on, so an entry lands
a moment after the action answers; it is called from a loop (its write answers there), so the bootstrap admin's
creation at boot stays an obs line. The actor is `{id, name, client}` (the client is `web.client_key` as 16 hex digits).
`/admin/audit` is LAN only like every `/admin*` page; its filter is a plain GET (a filtered view is a link), the next
page comes by `intersect once` on the last row (keyset on the id), and the export carries up to 10,000 rows with any
field a spreadsheet would read as a formula quoted behind a `'`. The first entries are accounts' `sign_in`,
`sign_in_failed` (an existing account) and `revoke`.

### 17.8 Trusted proxy

`X-Real-IP`, `X-Forwarded-Proto` and `X-Request-Id` are honoured only from `TRUST_PROXY` peers (D35). `TRUST_PROXY` is
empty by default (trust no peer). On apollo, compose pins the stack network's subnet and gives `caddy` a fixed
`ipv4_address`, and every app container's `TRUST_PROXY` is that one address, as a /32: the app trusts the stack Caddy
alone (D10; RESOLUTIONS X31, X43). Not the whole subnet: the gateway that Caddy trusts (below) sits inside it, so a
process on apollo's host that connected to an app container directly would arrive from the gateway and be trusted for
`X-Real-IP`. App containers publish no ports; only Caddy publishes `:8120`. Trusting every private range was rejected:
any LAN host could then spoof `X-Real-IP` and dodge rate limits, which is spark's `client_address` bug (S6, 06 §3.1).

**The stack Caddy's trusted proxies** (D41; RESOLUTIONS X31, X39). Caddy trusts `X-Forwarded-For` only from the address
NPM connects from, `<NPM_UPSTREAM_ADDR>`. The devices session measured it on apollo: it is the gateway of the stack's
own Docker network, not NPM's container address, because Docker masquerades traffic from another bridge, or from the
host, to that gateway. So Caddy's single `trusted_proxies` entry is that gateway (X39). LAN hosts that connect straight
to :8120 keep their own address, so at stage 1a such a host is identified by its TCP peer and cannot choose its client
address. Caddy sets `header_up X-Real-IP {client_ip}`, so NPM's client IP survives the second hop (08 §6.3; the
Caddyfile is in §20.4). Untrusted requests get a generated request id (RF §8.9). `/metrics` needs an Admin session or
the bearer token in `METRICS_TOKEN_FILE`.

**The residual risk, accepted** (RESOLUTIONS X39). Trusting the gateway trusts every container on apollo that reaches
the published port, not NPM alone: any of them could claim a client address. Those containers are Alex's own services
(`<APOLLO_SERVICES>`), so the risk is accepted and written down here. The narrower alternative, joining NPM to the
stack's network and trusting it by container name, is rejected: it would change NPM's configuration, which is Alex's
service, and §20.4 never names a container.

### 17.9 Terminal hardening

From D35 and D32 (the protocol is in §16):
- `Term_Write` is Admin-only with TOTP and step-up; `Term_Watch` is read-only.
- Device tokens are 32 random bytes shown once, stored as SHA-256, revocable, with a per-device kill switch.
- The agent dials out (no inbound port on the Pi), runs unprivileged, and enforces its own allow-list; line mode runs
  only allow-listed argv entries, never a shell.
- LAN-only (`.Lan_Only`; NPM answers 403 on `/term/agent`), WireGuard beyond the LAN (Q9); a 15-minute idle timeout
  (`TERM_IDLE`), input ≤ 4 KiB/s, output ≤ 1 MiB/s, 2 sessions per device.
- Every start, stop, attach, watch, resize, kill and line-mode command is audited. Writable sessions are recorded by
  the server from `raw` frames: output only, kept 30 days or 1 GiB in total, whichever comes first, never raw input
  (Q12; RESOLUTIONS X10).

### 17.10 Blast radius on apollo

apollo also runs Alex's other self-hosted services (`<APOLLO_SERVICES>`), some holding secrets, so the stack is built
to contain a compromise (08 §3, §7; D40, D41; R10):
- distroless `base-nossl-debian13` images as `USER 10001:10001` (no shell, no ffmpeg, no Docker socket), with a
  read-only rootfs and the io_uring seccomp profile, on their own network with a pinned subnet (compose: §20.4);
- cpu and memory limits per service (D38; values in §20.4; enforcement outside Swarm **UNVERIFIED (M3)**);
- `/term*` and `/admin*` LAN-only in-app and at NPM, also after going public (Q13);
- release images assert that the `TEST_ROUTES` crash-drill routes answer 404 (D10); and the shared-host blast radius
  is one of stage 2's triggers for a move to a VPS before Houston is advertised (D41).

### 17.11 Secrets

Secrets never live in the repo. On apollo they sit in `.env` (mode 600) or in compose `secrets:` mounted under
`/run/secrets/` and read through `*_FILE` variables: `SESSION_KEY_FILE`, `METRICS_TOKEN_FILE`,
`VIDEO_SIGN_KEY_FILE`, `BOT_LLAMA_KEY_FILE` (D10, 08 §5.7). The env table marks secret rows, so `--limits`,
`--features --json` and `/admin/modules` print them masked (D10), and no log line carries one. Session tokens, device
tokens, invite, reset and recovery codes are stored only as hashes (D35, 07 §5.2). CI needs only `GITHUB_TOKEN`
(GHCR) and `FLY_API_TOKEN` (08 §5.7).

## 18. Performance budgets and the parity gate

The brief asks for a starter that can produce "something with the performance characteristics of the skeleton (or
better)". This section turns that sentence into a measured procedure with a pass rule (D38) and lists the budgets the
rest of the plan is held to. The `skeleton` profile is the witness (§7); the store work that lets it pass is in §11.

### 18.1 What "the skeleton's performance" means

S18 fixes the reference, unchanged by 6d37506 (ANSWERS F5; "HEAD" in this plan means 709bc94, §2.15): skeleton HEAD
709bc94 **and** v1.1.1, built with the same toolchain and measured on the same box in the same session, on the 20-row
suite and on the 20k-row `scale` scenario, with the noise band recorded. The starter's `skeleton` profile must match
or beat the better of the two on every scenario; D38 makes that every cell (scenario × store × leg).

| Reference | What it is | Role in the gate |
|---|---|---|
| 709bc94 (= tag v1.2.0, no code change, D1) | the build live on Fly when the research measured it (`x-version: 709bc94`, 01 header) | baseline A |
| v1.1.1 | the release before the 2026-10-08 "lists in SQL" change: lists load into Odin and sort outside the store lock | baseline B |
| the starter's `cmd/skeleton` | the skeleton's features on store v3 (D16) and the fork (D11) | candidate C |
| `SK/load-tests/RESULTS.md` | the v1.0.0 record of 2026-07-01, built with dev-2026-06 (01 §11) | not a target |
| 6d37506 (= tag v1.2.1) | the `Content-Length: -5` crash fix on `master`, on Fly from M0 (§4.2 step 1) until the M3 exit (ANSWERS F5) | never a baseline: S18 is unchanged |
| v1.2.2 on `skeleton-1.x` | the optional QPSG backport for spark (D1) | never a baseline |

**Why two baselines.** Neither build dominates. HEAD's store-backed routes are about 2.5–3× slower than v1.1.1 at 20
rows (search median about 11.9k against about 28k rps at 200 VUs and 16 loops, 01 §14.3), while its non-store routes
are as fast or faster (`/robots.txt` 67.5k against 36.0k rps at 16 VUs). The cause is verified (01 §14.4): every list
statement binds `LIMIT ?`/`OFFSET ?`, each re-bind expires the prepared statement, and SQLite re-prepares it on the
next step inside the global exclusive lock. `SQLITE_DBCONFIG_ENABLE_QPSG` (1007) stops the re-prepare (`repo_match`
22.1 → 3.8 µs; search 12.8k → 33.4k rps end to end), but QPSG alone leaves list and pages at 0.55–0.58× v1.1.1,
because their sorts still run under that lock (12 §2.1). So every cell is compared with whichever baseline is faster
there.

**Why not RESULTS.md.** It describes neither HEAD nor today's toolchain, and it was measured on another day under
another background load. On this box absolute numbers from another session are not comparable (§18.5).

### 18.2 The gate procedure

1. **Build the baselines.** `tools/baseline` builds 709bc94 and v1.1.1 with the pinned Odin, the same SQLite library
   and the skeleton's own prepare (01 §14.3 method).
2. **Run each leg.** `load-tests/run.sh --parity` runs on the Windows-native leg and on the Linux-on-WSL2 leg (Q5).
3. **Scenarios and stores.** static, seo, pages, list, search, api, detail, write and mixed at 200 VUs and 16 loops,
   plus `scale` at 20 VUs over 20k rows, each on `:memory:` and on a file DB: 10 scenarios × 2 stores × 2 legs = 40
   cells.
4. **Interleave.** Per cell, A (HEAD), B (v1.1.1) and C (the starter's `skeleton`) run back to back, n = 3 rounds, a
   fresh server per run, `LOG_LEVEL=warn` (the access log costs about 9 %, 01 §10), 3 s warmup and a 10 s window.
5. **Watch the box.** Background CPU is sampled before each block; a round is re-run when it exceeds 20 %.
6. **Record.** Results go to `perf/results/<version>-<leg>.csv` and `docs/perf/PARITY.md`, with the box, the
   toolchain and the background load.

**As built (M1):** `run.sh --parity [scenario …]` execs `load-tests/lib/parity.sh`, S0.1's loop: it builds the two
baselines into `perf/baseline/` (git-ignored) with `tools/baseline` when they are missing and `skeleton` -o:speed with
`VERSION` from `git describe`, skips ports another process listens on, and ends with `lib/parity.mjs`, which applies the
pass rule below with each cell's reference and reads the `perf` and `perf-floor` lines of `tests/parity-waivers.txt`
for the leg.

`scale` stays at 20 VUs, as the skeleton runs it (`SK/load-tests/scenarios/scale.js:17-19`): at 200 VUs HEAD and
v1.1.1 refuse 99.0–99.9 % of requests on Windows (12 §2), and S0.1 re-checks those refusals on Linux. One gate run is
40 cells × 3 builds × 3 rounds = 360 runs of about 13 s (3 s warmup + 10 s window), so about 80 minutes of
measurement; server starts, `scale`'s 20k-row seeding and retries come on top (NEW estimate).

**Pass rule, per cell:**
- the reference is max(A, B) on the store routes and HEAD (A) alone on the light routes, `static` and `seo`: v1.1.1 is
  4–8 % faster there only because it lacks 1.2.0's security middleware, which the starter keeps (S0.1; Q35, answered
  2026-10-26). The `:memory:` cells the chosen mode fails against max(A, B) are gated against HEAD with a documented
  exception each (Q6, answered 2026-10-26); a file-DB cell is never waived;
- the median of the per-round paired ratios C / reference is ≥ 0.97, or the bar of a `perf-floor` line Alex accepted
  for the cell (M1: Linux `write@mem` at 0.93 of HEAD, the writer task's hop under a closed-loop client; ANSWERS
  round 6);
- no round's ratio is below 0.85;
- C's p99 is ≤ 1.10 × the p99 of the faster baseline.

A failing cell is re-run once with n = 5 and fails only if the re-run fails too, because cells vary by up to 2× between
rounds on this box (12 §2, §10).

**Cadence.** At the M1 exit (v2.0.0 waits on it, D1) and at every milestone exit after it, M3 included, where the Fly
redeploy waits on it (RESOLUTIONS X2, X25); the slice gate's item (c) re-runs it from M4 on (D44, §22). A failing cell
blocks the milestone, and nothing is waived without Alex. The agent runs the gate on the dev PC (RF §9.2). CI never
gates on absolute RPS (08 §5.2): its `load-smoke` job runs k6 at 20 VUs on `full` and `skeleton` and flags a regression
of more than 20 % against the last green run (D40).

**Micro-guards** in `odin test`, on every push, catch regressions between gate runs:
- `repo_match`, `repo_page` and render µs per call against a committed reference (12 §2.1);
- `stmt_status(REPREPARE) == 0` after 1000 binds, so the bound-LIMIT class can't return (01 §14.4). HEAD's page SQL
  re-prepared on 100,000 of 100,000 calls (12 §2.1).

**No 1-loop leg** (D17): at one loop every variant is below v1.1.1 on list, pages and write; the numbers are in §11.3.

**Why not "median ≥ best − noise band".** PF §9.2 and CF §9.2 proposed passing a cell when the starter's median is at
least the best baseline's median less the recorded noise band. On this box that rule passes nearly anything: the
three rounds of one cell (v3 search on `:memory:`) spread from 25.3k to 52.1k rps around a 51.9k median (12 §2), a band
of about 0.52, so a candidate at half the baseline's speed would pass. Paired ratios work because A, B and C run back to
back under the same background load, so the noise they share cancels in C / max(A, B). The 0.85 floor catches one bad
round, and the retry with n = 5 absorbs the remaining swings (R13).

### 18.3 `:memory:` parity

S0.4 measured D17's candidates A, B and C on both legs (§11.3): none passes every `:memory:` cell, C passes the most
and is chosen, and its failing `:memory:` cells are gated against HEAD with documented exceptions (Q6, answered
2026-10-26). On the file DB store v3's reads pass (1.1–2.6× v1.1.1) but its write failed (0.38–0.43×), so the file DB
takes C's group commit too, which writes at 2.9–4.3×.

**The watched margin is settled** (RESOLUTIONS X17; R2a). 12 §2 read file-DB write at 0.98×; S0.4's paired rounds
read v3 at 0.38–0.43×, so, as X17 provides, the file DB gets candidate C's group commit for skeleton writes.

### 18.4 Budgets

| Area | Budget | Basis |
|---|---|---|
| `skeleton` parity | the §18.2 rule in every cell × {`:memory:`, file} × {Windows, Linux} | S18; D17 |
| Expected floor, Windows file DB | search ≥ 28.8k, list ≥ 28.0k, pages ≥ 27.8k, detail ≥ 13.6k, api ≥ 28.5k, write ≥ 10.9k, mixed ≥ 17.1k, scale@20 ≥ 150 rps | 12 §2: max(HEAD, v1.1.1) medians |
| In-app time, one client | each skeleton route ≤ its 709bc94 median + 10 % (`/data` 0.36 ms, `/` 0.18 ms, `/contacts` 0.28 ms); Houston pages p50 ≤ 0.5 ms, fragments ≤ 0.3 ms, a chat room page with 100 messages ≤ 1.5 ms | 01 (B) |
| `full` read p99 | ≤ 25 ms at 200 VUs, mixed | 12 §2 (v3 8–25 ms) |
| Platform overhead per request | guard + logfmt + metrics ≤ 1.5 µs (Linux, one thread); routing ≤ 3 µs worst case (≤ 20 routes per feature) | 13 §5.1; 09 §4.4 |
| Binary, Windows `-o:speed` | minimal ≤ 1.5 MiB (1.25 MiB at M1: the platform and the 230 KB social card); skeleton ≤ 3 MiB (2.42 + 0.22 FTS5 + fork and obs at M1, then M2's shared client code; ANSWERS round 10); full ≤ 6 MiB with embedded bundles; all in MiB, as CI reads them (ANSWERS round 7) | 01 §14.1; 12 §8 |
| Image | ≤ 25 MB compressed per profile | 08 §5.3 (spark 10.8 MB) |
| RSS | minimal and skeleton idle ≤ 6 MB + 0.4 MB per event loop, 12.4 MB at the default 16 (each loop has its log buffer, counters and io ring; skeleton measured 12.2 MB on Linux at M1; ANSWERS round 7), measured at 16 loops and gated by the dev PC's drills on both legs, as the binary budget is gated on Windows; a CI runner reports its figure and its anon/file/shmem makeup without failing (ANSWERS round 8); full idle ≤ 40 MB (about 1.15 MB per reader × 16); peak under pages@200 ≤ 80 MB; ≤ 6 KiB per open stream; 8,192 idle streams (the default `STREAMS_TOTAL`) ≤ +80 MB | 01 §14.1 (7–8 MB, 73 MB peak); 12 §8; 03 §10.4 (5.2 KiB) |
| Connections | `nofile` 65,536; `MAX_CONNS` = soft − 64; 3000 streams with `/livez` < 100 ms | 13 §3.5 |
| Fan-out, Linux, 4 loops | 1000 SSE subscribers p99 ≤ 100 ms; 3000 ≤ 200 ms; WS 1000 sockets × 20 messages delivered ≤ 2 s | 03 §10.4 (74 ms; 115–188 ms; 1.6 s) |
| Restart | boot → `/readyz` ≤ 50 ms (file DB, 20k rows) plus the bind retry; 4000 clients back ≤ 3 s; stale cursors → replay or resync 100 % | 13 §3.3-3.4 |
| Shutdown | ≤ 6 s with 500 SSE + 500 WS + a slowloris + a half-sent body + a non-closing idle peer | 13 §4.1 (13.2 s and > 30 s today) |
| Login storm | 50 logins/s under `cpus: 2.0` with one argon thread: other routes' p99 ≤ their base + 0.5 ms, the cgroup never throttled, every login answered (200/401, or 503 at once past the queue); Q34, answered 2026-10-26; the first budget, p99 within +10 %, failed in every setting (S0.5: +24 % to ×22 on a sub-millisecond p99, never by blocking a loop; +0.08–0.12 ms with one thread) | 07 §5.6; S0.5 |
| Chat | writer task ≥ 50k msgs/s batched on a file WAL; send → another member's DOM on the LAN via NPM p95 ≤ 50 ms (NEW) | 12 §3.1 |
| Bot (mock) | 1000 concurrent generations × 200 tokens at 20 Hz ≤ 1 core and ≤ +30 MB (NEW) | — |
| Video | 256 MiB Range transfer ≤ 8 MB peak private memory (Linux splice UNVERIFIED) | 07 §0.2 (5.1 MB) |
| Terminal | 80×24 full render ≤ 100 µs; LAN key echo p95 ≤ 50 ms (estimate UNVERIFIED) | 07 §3.3 (53 µs) |
| Wire | minimal 11.7 KB br JS; full about 23 KB + hyperscript 39.7 KB br; CSS ≤ 16 KB br; a Houston page ≤ 40 KB of HTML | 11 §9 |
| apollo allocations | full: `THREADS=2`, `cpus: 2.0`, `mem_limit: 512m`; witnesses (`minimal`, `streams`, `skeleton`, `lab`; X22): `THREADS=1`, `cpus: 0.5`, `mem_limit: 64m` (enforcement outside Swarm UNVERIFIED) | 08 §6.5 |

The floor row is 12 §2's file-DB medians of the faster baseline: a sanity check on a run's scale, not the pass rule,
which always compares against baselines measured in the same session. Each milestone's exit gate (§22) names the
budgets it asserts.

### 18.5 Where numbers come from

| Source | Box | Used for | Caveat |
|---|---|---|---|
| Windows leg | the dev PC: Ryzen 7 5800X 8C/16T, 64 GB, Windows 11; k6 v2.0.0 co-located on loopback (01 §14) | the parity gate, budgets, micro-guards | shared with other agents and desktop apps: background CPU 0–91 % sampled in 12, 12–59 % in 01 §14; Windows spreads k6's connections unevenly over the loops (12 §2) |
| Linux leg | the same PC, Linux on WSL2: Odin dev-2026-10 installed natively in WSL2 (Q5: yes; S0.9 retired 03 §10.3's obj + lld fallback), with k6 v2.0.0 there too | the gate's second leg; the fan-out budgets (Linux, 4 loops); S0.9's TSan build | the same CPU and the same noise |
| Two-host | k6 on the dev PC → 1 GbE → apollo (`<APOLLO_CPU>`) at stage 1a, from M3 (D41) | relative LAN realism: the deploy gap, the NPM path, the 1 h NPM soak | a functional box, not a perf box: NPM + TLS caps out near 1.9k RPS (S20; 1,888 rps against 21,987 direct for api at 50 VUs, 01 §11) |
| CI runners | GitHub standard runners | the relative `load-smoke` only | never absolute RPS (08 §5.2) |

The skeleton's own suite says the same: loopback with a co-located generator is good for relative comparison, not
headline figures (`SK/load-tests/README.md:72-77`). Fan-out and cross-loop claims come from the Linux leg only: on
Windows the 1000-subscriber SSE test ran every connection on one loop (03 §10.4), so cross-loop bugs and costs show
only on Linux (R3). On apollo, agents run LAN load tests of at most 10 minutes, with cpus capped and announced, as
Alex agreed (Q24: yes, 2026-10-25). June's direct two-host run was CPU-bound on apollo for writes and searches and
wire-bound at 1 GbE for pages and static (01 §11), so apollo numbers never feed a pass rule.

## 19. Testing and the Odin code audit

Two halves of equal weight: the suites that hold every feature to its contract (D37), then the audit Alex asked for,
"an audit of the resulting Odin code for performance and stability", run as a procedure with gates (D39). Performance
gates are in §18; the CI jobs that run all of this are in §20.

### 19.1 Testing

Every layer follows the selection: suites live per feature (`e2e/tests/<f>/`, `load-tests/scenarios/<f>/`), and each
run reads the binary's own `--features --json` (09 §4.5), so a generated project carries exactly its own tests.

#### 19.1.1 Unit

`odin test` per package, under a `Tracking_Allocator` with `ODIN_TEST_FAIL_ON_BAD_MEMORY` (0 leaks, 0 bad frees; 02
§2.3). It covers the parsers (form decode, WS frames, the SSE client, Range, multipart, the stream cursor, the term grid
frames, markdown), with new unit tests for the strict WS codec, because spark's wsserver has none to take: its RFC 6455
coverage table is the checklist (03 §5.1; RESOLUTIONS X24); a store conformance suite per feature
(`features/<f>/storetest`), which imports both of the feature's stores into one test binary, their package names being
unique (CF §4.5; LC §3, §16); feature tests under each profile that mounts the feature (`CMD=test ./build.sh <p>`); the
migration runner's 6 cases plus fixture databases written by the real 709bc94 and v1.1.1 binaries and a portal-shaped
spark database (12 §5); the hub (publish, drain, replay, resync, policies); guard classification; the limiter; TOTP
vectors; `clean_name`; and the micro-guards of §18.2.

#### 19.1.2 e2e

Playwright on the skeleton's harness (01 §9: one build, one server per worker on an OS-picked port with pinned env, a
browser-less `api` project). Specs live in `e2e/tests/<f>/`, tagged `@<f>`, and `@<f>-<impl>` when they test one
implementation. Global setup builds each profile under test through `build.sh <p>` and reads `bin --features --json`
to choose tags. **As built (M1):** a spec carries a tag for every feature it touches, its folder's first, and runs
only when the build has them all; `<impl>` is any family member's `NAME` (`@contacts-sqlite`, `@platform-full`;
`--features --json` names the store family's member too, from `app/stores/<family>/stores.odin`). The fixture skips
the rest, naming what's missing, and fails an untagged spec; `has(tag)` lets a shared spec branch on the build. Load
scenarios carry the same tags on a `// tags:` line, and `load-tests/run.sh` chooses by them.

| Profile | Engines | Scope |
|---|---|---|
| `full` | chromium, firefox, webkit | every compiled feature's specs on the host that mounts it, the lab host's demo, `lab`, `scripting` and `compat` specs among them (from M4; ANSWERS F2, round 3) |
| `skeleton` | chromium, firefox, webkit, plus the `api` project | the skeleton's 23 ported specs (D44 M1) |
| `streams` | chromium and webkit locally; all three in CI, firefox included (M6: chat's first Firefox run came by accident through `full`) | the stream substrate without SQLite |
| `minimal` | chromium | its features' specs |
| `lab` | chromium and webkit locally; all three in CI, firefox included | the lab specs, `csp-enforced.spec` and `streams-hxcsp.spec` among them (D44's M2 exit; RESOLUTIONS X18) |
| `full-vanilla` | chromium | core and twinned-behaviour specs on the main host (D22) |
| generator outputs | chromium | the selection's tags (§19.1.12) |

Firefox runs in CI only, because it can't start on this PC (11 §1): `harness-csp.spec` is the Firefox proof, and no
Firefox claim stands without a CI run (R15). The `e2e-proxy` job, from M2, reruns the hosted profiles that exist ×
chromium through the repo Caddyfile and through nginx with the config apollo's NPM version generates (§20;
RESOLUTIONS X26, X40).

**The oldest-browser device** (RESOLUTIONS X41; §20.8). An old Android phone is the oldest-browser test device. From
M6, Houston's core flows of D22 (links, forms and SSE) are walked on it with no client behaviours, and they must work
there; the result goes into the milestone's exit report (**NEW**). Whether htmx 4 runs on that browser at all is
**UNVERIFIED (M6)**. The VR headset's WebXR case is `games-frame.spec`'s (§19.1.4). The other real-device clients of
§20.8 (the tablet, the handheld gaming PC, the gaming laptop as a Windows client) are optional and block no milestone.

#### 19.1.3 Realtime specs

Real servers only: Playwright's `route.fulfill` can't stream (08 §5.1, an inference there). Two browser contexts
exchange messages; `page.on('websocket')` checks the outgoing frame shape; `context.setOffline` tests resume without
duplicates (the spec counts ids); a 1012 close reconnects and a 1008 close doesn't; `Last-Event-ID`, `after` and
`@rowid` resume, including across a server restart; a hidden tab closes its stream. Transport-parameterised specs
(`@chat-ws`, `@chat-sse`, `@chat-poll`, `@chat-multipart`) run the same chat specs once per transport against one
binary. They prove §9's resume design, which stays UNVERIFIED until these M2 specs pass.

**`revoke.spec`** (M4; RESOLUTIONS X19) covers a revoked SSE stream. The server sends the named `kicked` event, which
triggers a full navigation to `/login` and so removes `#live`. A reconnect without auth gets 403, and the spec asserts
that the server sees at most 3 reconnects in 30 s. Whether hx-sse itself stops retrying after a 403 is **UNVERIFIED
(M4)**: 03 §1 says SSE reconnects are unlimited.

#### 19.1.4 Client-stack specs (11 §7.3)

| Spec | Asserts | Engines |
|---|---|---|
| `headers.spec` | the CSP parsed into a directive map per route-flag combination, plus every other security header per class; no COEP anywhere; no HSTS over http; on a lab host, no `Set-Cookie` on any response, `X-Robots-Tag: noindex` on its pages, and the nonce class only there, never on Houston's host (ANSWERS F2) | api |
| `csp-clean.spec` | zero `securitypolicyviolation` on every sitemap page plus one interaction per feature, with trusted input; on `full`, every lab-host page too | all 3 |
| `csp-enforced.spec` | the negative canary: an `hx-on` click raises a violation under the hash CSP; an unnonced `hx-get` is stripped on `/scripting`, in `lab` and on `full`'s lab host | all 3 |
| `harness-csp.spec` | which Playwright calls bypass the CSP and which don't (11 §7.1) | all 3 |
| `bundle-race.spec` | assets delayed 400 ms, with and without hyperscript: `hx-ws:send` forms don't navigate, connects fire, `hs-include` data arrives | all 3 |
| `streams-hxcsp.spec` | `/scripting/streams` pins the upstream hx-csp gaps, so a fix shows up as a spec diff | all 3 |
| `games-frame.spec` | the games iframe gets fullscreen (and gamepad in Chromium), and is blocked without `frame-src`; a WebXR case: the frame's `allow` list carries `xr-spatial-tracking`, so a WebXR game inside it may ask for an immersive session, for the VR headset (M10; RESOLUTIONS X41; on the headset itself **UNVERIFIED (M10)**) | all 3 |
| `download.spec` | hx-download produces a download with the expected file name | all 3 |
| `a11y.spec` | `@axe-core/playwright` on every sitemap page without bypassCSP; lints: live regions in the initial markup, no click handlers on non-interactive elements | all 3 |

CI also runs hyperscript's own `--validate` over rendered pages and `._hs` files (11 §7.3; R6).

**As built (M2):** `csp-clean`, `csp-enforced`, `harness-csp` and `bundle-race` are in `e2e/tests/platform/`, each
case tagged with the features it needs, and `streams-hxcsp` in `e2e/tests/scripting/`. `csp-clean` took over
`security.spec`'s sitemap walk and checks each page before leaving it (a page's record starts over with each
document). `csp-enforced` injects its markup as an escaping mistake would put it rather than mounting a test-only
route. `bundle-race` runs the Main and Scripting layouts on `lab`'s hyperscript client; the separate-files control
stays the spike's (S0.10), and the vanilla Main layout waits for a vanilla profile that streams (`streams`, slice 11).
`streams-hxcsp` found 4.0.0 narrower than 11 §2.2: §12.2's as-built note.

#### 19.1.5 Generated specs

- `rbac.spec` is generated from `bin --routes`: every route × every role → the expected status (§17). M4's exit needs it
  over 100 % of routes × roles. In `full` it adds every route × both hosts, for the per-host tables and the session-free
  lab host (§17.2; ANSWERS F2). e2e gives `full` two origins on one server, `localhost` (`SITE_URL`) and `127.0.0.1`
  (`SITE_URL_LAB`), whose host-only cookies stay apart (**NEW**).
- `escaping.spec` asserts that every `_` on every rendered page matches `^install [A-Z]\w*$`, that every
  `data-behave` value is a vanilla name in `BEHAVIOURS` (D22), and that XSS payloads in every UGC field render as text.

#### 19.1.6 Rules for spec authors

- CSP-sensitive interactions use trusted input (`locator.click`, the keyboard), never `page.evaluate` clicks:
  `evaluate(() => el.click())` ran an `hx-on` handler that a real click can't run, a false pass (11 §7.1).
- A known-error allowlist, matched by exact text, covers htmx 4.0.0's hx-pending `htmx_error` bug and the SSE abort
  noise (04 §1; 11 key facts). An upstream fix then shows up as a diff.
- Video playback specs use `channel: 'chrome'` or AV1 WebM, because Playwright's bundled Chromium lacks H.264/AAC
  (07 §4.2).

#### 19.1.7 Load

k6 v2 per feature in `load-tests/scenarios/<f>/`; the skeleton's 10 scenarios (`scale` among them) and harness stay
(01 §10). HTTP and WS use stock k6 (`k6/websockets` verified, 08 §5.2). SSE and WS fan-out use **`tools/streamload`**,
a multi-threaded Odin generator on `platform/stream/client` (D12); publisher-stamped `data-t` gives delivery
percentiles. Not stock k6, whose `http.get` on SSE returns only when the stream ends (08 §5.2); not xk6-sse, a custom
AGPL k6 binary the repo won't distribute (10 §8.1, §11); not Node clients, which left 03's numbers client-bound
(03 §10.4). Per-feature scenarios: chat (four transports), bot (1000 mock generations and Stop storms), video Range
readers, uploads, the ptag 304 wall, a login storm, terminal grid throughput.

#### 19.1.8 Soak

Nightly, 1 h: 2000 streams, mixed load and a mid-run redeploy. It passes when RSS and FDs plateau,
`stream_queued_bytes` stays bounded, nothing exits but the deploy and reconnects take ≤ 5 s. At M3, 1 h through NPM
on apollo (1000 SSE held with no idle cuts, D44). Before M12, 8 h.

**As built (M2):** `sh tools/drills/soak.sh` (Linux; `SOAK_MINUTES`, 60) runs lab with `THREADS=4` and the per-client
stream caps lifted. The first half holds 1000 SSE + 1000 WebSocket clients in `tools/streamload restart` (5
publishes a second), with k6's lab scenario at 10 VUs throughout; at half time a SIGTERM drains the server and a new
one starts on the same port, and streamload times the 2000 coming back; the second half holds 2000 again
(`streamload hold`). Every 30 s it samples RSS and the open fds (`/proc`) and lab's `/lab/stats` (`open`, and
`queued`: bytes waiting in the streams' send queues) into `app/build/soak/samples.csv`. It passes when, in each half,
the last sample is within 10 % of the first one under full load (RSS and fds), `queued` stays under 64 MiB, the
first server exits 0 and the second lives on, and all 2000 are back within 5 s. Nightly in CI. Its first hour (WSL,
2026-10-27) found the hub's idle-ring sweep freeing a ring twice (`free(): invalid pointer` after a few minutes;
fixed, see the hub's `ring_sweep`); the hour after the fix passed: RSS 16.3 MB, +0.3 % and +1.0 % over the halves,
2023 fds throughout, no bytes queued at any sample, the first server out with 0, and 2000 of 2000 back in 1.5 s.

#### 19.1.9 Fuzz

Three tiers (02 §2.4):
1. **Raw-socket smoke, every push**: 10k malformed HTTP requests and WS frames, including `Content-Length: -5`, with
   `/livez` 200 after each. This exact harness reproduces F1 (02 §1.2, §2.4).
2. **Table-driven random-bytes unit tests** over the pure parsers.
3. **libFuzzer, nightly**, through `-build-mode:obj`, on the HTTP scanner, WS decoder, SSE client, multipart round
   trip, Range header, form decode, markdown, the stream cursor, the term grid decoder and the agent's VT parser.
   Milestone campaigns (D44): upload decode bombs at M6, wiki markdown at M8, 24 h of VT at M11, 8 h on all before M12.

Beside the three tiers, from M2, a **nightly Autobahn|Testsuite run** points its fuzzing client at the lab's WS echo
(RESOLUTIONS X24, **NEW**). It is a dev-time Docker image, exempt like Playwright and k6.

**As built (M2):** `nightly.yml`'s `autobahn` job runs `crossbario/autobahn-testsuite` (pinned by digest) with
`tests/autobahn/fuzzingclient.json` against `/lab/ws/echo` on a `-o:speed` lab: sections 1–7 and 10, leaving out 9
(performance) and 12–13 (permessage-deflate, which the server doesn't offer). A case that isn't OK, NON-STRICT or
INFORMATIONAL, or closes otherwise than OK or INFORMATIONAL, fails it. First run (WSL): 247 cases, 240 OK, 3
INFORMATIONAL (7.1.6, 7.13.x), 4 NON-STRICT (6.4.1–6.4.4: invalid UTF-8 inside a fragmented message is refused when
the message ends, not at the fragment that broke it), none failed.

#### 19.1.10 Crash drills

**As built (M1):** `node tools/drills/drills.mjs <profile> [phase …]` builds the profile twice through `build.*`, a
`-define:TEST_ROUTES=true` build (platform/app mounts `/__test/crash/<kind>` and `/__test/shutdown` from
`platform/web/drills.odin` on the main host's router only, so `--routes`, the boot checks and route coverage never
see them) and the release `-o:speed` build, and runs every phase on fresh servers: release (`/__test/*` 404), pure,
dirty, burst, hang, malformed (§19.1.9's tier 1), shutdown, restart, fdceiling (Linux, `ulimit -n 256`) and the
budgets. A kind a lower package can trap registers itself with `guard.register_drill` (store/sqlite's `sqlite`: a
nil write inside an SQL function, so `in_sqlite` is up). Windows has no SIGTERM for a child, so its shutdown drill
calls `/__test/shutdown`, which starts the same drain; `--wsl DIR` runs the servers in WSL from a Windows host.
CI's `linux-ops` runs it per profile; the nightly `asan` job runs e2e and a k6 quick run against a
`-sanitize:address` build, with `ASAN_OPTIONS=use_sigaltstack=0` because the guard installs its own alternate
signal stack.

`/__test/crash/<kind>` exists only in `TEST_ROUTES` builds; release images assert it answers 404 (D10). The drills run
on Windows and Linux (S0.6; the `linux-ops` job), with the outcomes of 13 §6.2 and D15:

| Kind | Trigger | Zone | Expected |
|---|---|---|---|
| `panic`, `bounds`, `div`, `nil`, `stack` | `panic()`; an out-of-range index; integer division by zero; a nil dereference; stack overflow by recursion | pure | 500; 20/20 bystanders alive; streams still flowing; `app_guard_recoveries_total` +1 |
| `lock`, `async`, `sqlite` | a trap while a `guarded_mutex` is held; after the callback posted an nbio op; inside a call into SQLite (`in_sqlite` > 0) | dirty | exit 70 within 6 s |
| `wsdata` | a trap inside a WS `on_data` callback | pure | that socket closes with 1011; the server stays up |
| `hang` | a loop blocked for 15 s | — | the watchdog exits 70 within 11 s and names the route and request id |

Three process drills complete the set (13 §6.2): the shutdown bound (exit ≤ 6 s with 500 SSE + 500 WS + a slowloris +
a half-sent body + a non-closing idle peer; WS got 1012), restart after `kill -9` at 0/50/100 ms (the bind retry),
and the fd ceiling (3000 streams in a container with `ulimits`, `/livez` < 100 ms). M1 runs the request-path kinds;
`wsdata` arrives with streams in M2 (D44).

**As built (M2):** a drill kind can take the request over (`guard.register_drill_handler`), which is how
`platform/stream` registers `wsdata`: a socket whose `on_data` panics. Phases added for a profile that streams (lab's
endpoints): `wsdata` (1011 to that socket; a bystander socket and the server unharmed; one pure crash line),
`streamdrain` (500 SSE on `/events` + 500 sockets on `/lab/ws/echo` + the shutdown phase's slow, half-sent and idle
peers: exit 0 in 5.7 s on Windows, every socket 1012 and every SSE stream the drain's `retry:`) and `streamfd` (Linux:
3000 SSE streams under `ulimit -n 4096`, `/livez` within 100 ms). Slice 14 added `continuation`, `streamcrash`,
`slowread`, `logstall` and `latewrite` for M1's carried findings. The servers lift the per-client stream caps, as the
suites do.

#### 19.1.11 Route-coverage parity

After the e2e run and after the k6 quick run, CI scrapes `/metrics` of each profile under test: every route id
(`"<METHOD> <pattern>"`) of every host, as `bin --routes --json` prints them per host, needs a non-zero per-route
request counter in both, or `tools/check parity` fails (CF §10; LC §11). Waivers live in `tests/parity-waivers.txt` with
a reason, reviewed in the milestone audit; slice gate (a) allows 0 unexplained ones. **As built (M1):** every server
either suite starts gets a per-run `/metrics` bearer (`METRICS_TOKEN_FILE`), and is scraped as it stops: e2e's
`stopServer` and `run.sh`'s `stop_server` keep its `app_http_requests_total` lines in
`app/build/coverage/{e2e,load}/<profile>/`. The waivers file holds both parity rules' waivers, one per line, `kind |
what | where | reason`: `perf | <scenario>@<store> | <legs> | …` gates a cell against HEAD (§18.2), `route | <route id> |
<suites> | …` excuses a suite from a route. At M1 it holds S0.4's three `perf` lines and no `route` line: both suites
reach every route of both profiles. This enforces the skeleton's
standing policy 3, every endpoint in both suites (`SK/CLAUDE.md:31-34`), which `parity.sh` only stated: a grep for path
literals (`SK/load-tests/parity.sh:6-9`) that never ran in CI and left 14 of 26 routes with no load reference at HEAD
(01 §2). Counters see even routes reached only by clicks.

#### 19.1.12 Combination coverage

| Layer | When | What |
|---|---|---|
| Named profiles | every push | the six profiles of §7 |
| Singletons | one rotating per push; all nightly | `tools/init --features <f>` (the lean hello world, D27), then its check, build and chromium e2e |
| Covering array | nightly from M4, once there are at least 10 optional features | strength 2 over feature presence, plus a second small array for the four families (store, client, theme, identity) |
| Selection fuzzing | nightly from M4 (D44) | 3 seeded random valid selections |

A strength-2 covering array of N rows covers every pair of k binary factors when C(N−1, ⌈N/2⌉) ≥ k, so 8 rows cover up
to 35 features (C(7,4) = 35). The starter has 31 feature packages, and every generated project has one root per host
(D27; RESOLUTIONS X5; §6.3), and a generated project has a single host (§7.4), so `home` is present exactly when
neither `dashboard` nor `landing` is: it is not a free factor, and the other 30 fit in 8 rows (the `dashboard` +
`landing` pair is infeasible). Rows are closed over
dependencies and cover 100 % of feasible pairs; `tools/init --pairwise --seed <n>` writes them to
`.github/matrix/pairwise.json`, which the `check` job keeps fresh. Pairs suffice because features meet only through
closed, namespaced seams guarded by boot checks and lints (D5, D6), so remaining interaction bugs are mostly between two
features (CF §11.1, NEW).

### 19.2 The Odin code audit

Alex's audit is not a one-off review. It is 02 §2's procedure plus 13 §6.2's checks, run at five cadences, with an
exit rule and a stamp per package, so the repo always knows which code is unaudited (D39).

#### 19.2.1 Cadence

| Cadence | Checks |
|---|---|
| Every push (CI) | `CMD=check ./build.sh <p>` for every profile, and `odin check app/stores/<family>/<f> -no-entry-point` for every store in both families on its own, with `-vet -strict-style -warnings-as-errors` (the skeleton's bar, clean today: 02 §2.1, 09 §3); domains, views, web packages, switched implementations and identities reach a collection, so they are checked under each selecting profile's line, never alone (LC §11); the further vet flags of 02 §2.1 (`-vet-cast -vet-semicolon -vet-tabs -disallow-do -vet-using-param`), adopted at M1 with 0 errors; `tools/check` imports (D4, with the collection rules of §5.1), profile, routes (per host), topics, contracts, exts (§6.1), locks (no `sync` lock outside the guard helpers), entry-points (every `nbio.*_poly`, `stream_begin`, thread and timer callback wrapped by `guard_call` or waived with a reason), tables (package-level `[?]T`, never slice literals inside a proc), names (table, CSS, topic, job and env prefixes), parity, pins, catalog freshness; unit tests under a `Tracking_Allocator` with `ODIN_TEST_FAIL_ON_BAD_MEMORY` (0 leaks, 0 bad frees); the fuzz smoke; the crash drills; the shutdown bound; restart; the watchdog; the observability microbench (logfmt ≤ 1 µs, metrics ≤ 100 ns) |
| Nightly | ASan over e2e and a short load (Windows and Linux); TSan (Linux) over the hub, streams, store, workers and terminal grid; the 1 h soak; the fd ceiling; libFuzzer targets; Autobahn\|Testsuite against the lab's WS echo (X24); singletons, pairwise and selection fuzzing; a generated `--identity envadmin` selection, so the identity no hosted profile selects is checked and built (LC §11; **NEW**) |
| Every milestone exit | a written audit, `docs/audit/M<n>.md`, by an agent that did not write the code: the 02 §2.8 rubric (§19.2.2), 13's pure/dirty zone rules, the fork's diff line by line, a spall trace and a Linux `perf` flame graph of the slice's hottest route, and `-vet-unused-procedures -vet-packages:…` as an aid; findings ranked by severity. **Exit needs 0 open CRITICAL or HIGH**; MEDIUM findings go to TODO with an owner milestone |
| Audit stamps | each package README records `Audited: <commit> <date> <report>`; `tools/check audit-debt` counts changed lines since each package's stamp; a release (every milestone exit) is blocked while any package has more than 300 unaudited changed lines or any open CRITICAL/HIGH (CF §9.3) |
| Before public (M12) | a full-tree audit, an 8 h libFuzzer campaign, an 8 h soak, clean sanitizers, a symbolised crash drill (`-o:speed -debug`, split debug file kept per `VERSION`) |

TSan needs Linux (Windows refuses it, 09 §3); M6 adds a focused security audit before the first invite (R18, §22).

**As built (M2), TSan:** `sh tools/drills/tsan.sh` builds with `-sanitize:thread -debug` and counts the reports in
the hub's, stream's, workers' and store/sqlite's unit tests; in lab under `tools/streamload fanout` (200 SSE + 200
WebSocket clients, 200 publishes across the loops) and its drain; and in skeleton under k6's `write` and `pages` (the
writer task, the per-loop readers, the pool) and its drain. Any report exits 1. `tools/drills/tsan.supp` holds the
one suppression, `core:nbio`'s mpsc assert (S0.9; it hides 3 reports a run of workers' tests and nothing else). The
first run reported 138. About a hundred came from connection arenas that one loop unmapped and another mapped
again (core:mem/virtual issues raw `mmap`/`munmap`, which TSan doesn't see): a TSan build now puts them on the heap
(the fork's F-22). The rest were real: `server_shutdown` woke loops that were already released, and read the threads
while `serve` freed them (F-21); and store/sqlite's group-commit test released its loop before joining the writer
that was still waking it. 0 since.

#### 19.2.2 The review rubric (02 §2.8)

1. **Allocator buckets**: request-scoped data in `context.temp_allocator`; process-lifetime data in `context.allocator`
   at boot; **connection-lifetime data in the stream's own arena** (D12). Nothing returned from the store aliases a
   statement buffer (`clone_col`).
2. **No panics on external input**: every index from external input is range-checked or validated at the boundary
   (F3, through `store.enum_from_int`); ids go through `parse_id`; no `assert` on request-derived values.
3. **Limits plus timeouts**: every new input (header, field, frame, query) has an explicit size cap and, if it reads
   over time, a timeout (F5).
4. **Lock discipline**: store access only through the feature's store family (`store:<f>`, from its own domain) under
   the documented lock; locks only through `guarded_mutex`; no new global mutable state without a lock and a TSan test.
5. **Errors as values**: logged server-side, mapped to a status, never ignored; each `x, _ :=` fallback justified.
6. **Aesthetics** (`SK/CLAUDE.md` "Code aesthetics"): one definition per concept; comments say why; the naming cases;
   `@(private="file")` only for true file-locals; HTML only through `esc`, `url_encode` and `json_esc`.
7. **Tests in lockstep**: a new endpoint brings an e2e spec and a load scenario, and a new parser a fuzz case.

#### 19.2.3 Severity

| Severity | Meaning (definitions NEW, calibrated by 02 §1.1) | Inherited example |
|---|---|---|
| CRITICAL | one unauthenticated request kills the process | F1: `Content-Length: -5` |
| HIGH | a crash path that takes down every loop, or a latent remote crash | F2: no handler recovery; F3: unchecked enum reads |
| MEDIUM | a throughput ceiling, or a missing timeout or cap | F4: the store lock; F5: no timeouts; F6: no connection cap |
| LOW | wrong framing or a latent pattern with no crash | F7: wrapping `Content-Length` parse; F8: wrapping `to_int` |

#### 19.2.4 Why `-vet-unused-procedures` is an aid, not a gate

On the skeleton it reported 13 hits, mostly false positives: `@(test)` procs and unused binding declarations such as
`bind_double` and `bind_null` (09 §3: "an audit aid, not a gate"). It also needs `-vet-packages:<names>` (02 §2.1).
So the milestone auditor runs it and sorts real dead code from noise. Of the other extra vet flags, `-vet-cast`,
`-vet-semicolon`, `-vet-tabs` and `-disallow-do` already pass with 0 errors on the prepared skeleton (09 §3);
`-vet-using-param` was not in that run. All five join the per-push gate at M1 once clean (D39). **As built (M1):** all
five pass with 0 errors on both profiles, every store alone, `tools/check`, `tools/bundle`, `tools/init` and the unit
tests, and `build.{sh,bat}`, CI's store checks and `unit-tests.sh` carry them.

#### 19.2.5 What an audit report contains

| Part of `docs/audit/M<n>.md` (layout NEW, from D39) | Content |
|---|---|
| Scope | the milestone's diff and the packages it touched, with their previous audit stamps |
| Findings | each with file:line, severity, the rubric item it breaks, and the fix commit or the owner milestone |
| Zones | the pure or dirty classification of every new entry point and module (D15) |
| Fork | the vendored fork's diff since the last audit (`app/vendor/odin-http/` against its `UPSTREAM.md` base), reviewed line by line (D11) |
| Profile | a spall trace and a Linux `perf` flame graph of the slice's hottest route (02 §2.6) |
| Aids and stamps | the triaged `-vet-unused-procedures` output; the new `Audited:` lines and the audit-debt after them |

## 20. Pipeline, hosting and deploys

CI runs on GitHub Actions on the public repo (free standard runners including `ubuntu-24.04-arm`, 20 concurrent
jobs; 08 §5.1). Its only deploy is `deploy-fly`; apollo gets tagged images from the dev PC over SSH (S21).

**Public-repo hygiene** (ANSWERS F4; the rule is in §5.3). Because the repo is public, `docs/research/`,
`docs/design/proposal-*.md`, `docs/design/OUTLINE.md` and `docs/private/` are git-ignored, and LAN addresses,
apollo's hardware and services, user names and host paths go only to `docs/private/SITE.md`, while the public docs
use placeholders. The planning docs are committed only after the scrub (§4.2 step 5).

### 20.1 CI matrix

| Job | Matrix | Content |
|---|---|---|
| pins | — | `check-pins`: Odin dev-2026-10 (84bc3fc), the vendored odin-http's base commit (fac113f, from its `UPSTREAM.md`), the htmx 4.0.0 tarball SHA-256 (04 §1.3), hyperscript's SHA, SQLite 3.53.4, the Playwright image = the lockfile, k6, the Caddy image digest |
| check | — | `tools/check` (D39: imports, profile, routes, topics, contracts, exts and the rest of §19.2.1) over every committed profile, in place of D7's `--emit --like`; `CMD=check ./build.sh <p>` for every profile; `odin check` of every store in both families on its own (a family directory is not a package, so the job loops over its subdirectories; LC §11); `docs/catalog.json` and `pairwise.json` freshness, audit-debt |
| build | {minimal, skeleton} × {ubuntu, ubuntu-arm, macos, windows}; {streams, full, lab} × {ubuntu, windows}; full-vanilla × ubuntu | every build through `build.{sh,bat} <p>` (`full-vanilla` is `full`'s files with `client=vanilla`); the static gate, `-o:speed`, `odin test` under each profile that mounts a feature, size budgets, smoke (`/healthz` body exactly `ok`; WS echo and SSE first event where present); `minimal`, `streams` and `lab` also built with prepare's SQLite step skipped and no sqlite3 library present (D18) |
| e2e | §19's matrix (D37) | `mcr.microsoft.com/playwright:v1.63.0-jammy` (the skeleton's pin); the route-coverage scrape |
| e2e-proxy | {streams, lab} × chromium from M2 (X26); full × chromium from M4 | the suite through the repo Caddyfile (the same `deploy/Caddyfile`, run in CI) and through nginx with the `proxy_host.conf` + `proxy.conf` that apollo's own NPM version generates, pinned to that version (buffering, 90 s timeouts, the Connection header, HTTP/1.0 upstream; 08 §3.1; X40) |
| proxy-config | — | from M3 (X26): `caddy validate` on `deploy/Caddyfile` and every Caddyfile snippet in the docs; `nginx -t` on the NPM Advanced snippet inside NPM's template; curl assertions for every redirect alias, bare and deep (D25); the compose publish `8120:80` and the catch-all `:80` block's 421 (X23) |
| linux-ops | full | crash drills, shutdown bound, restart, watchdog, fd ceiling (a container with `ulimits`) |
| docker | each hosted profile | compose up under `./seccomp-io-uring.json` staged next to `compose.yaml`, as `promote.ps1` stages it (X21), `--healthcheck`, **UID 10001**, read-only rootfs, SIGTERM stop ≤ 6 s, volume persistence |
| generator | each named profile + one rotating singleton | `tools/check profile` on every committed profile; `tools/init … --yes` (with `--verify`) on a clean checkout, then that output's check, build and chromium e2e for its tags (D27, D37; LC §10) |
| load-smoke | full, skeleton | k6 at 20 VUs, relative to the last green run |
| term-agent | ubuntu-24.04-arm | builds `cmd/term-agent` for linux_arm64; the e2e runs an amd64 agent in the CI container against `/bin/sh` |
| nightly | — | ASan, TSan, soak, libFuzzer, Autobahn\|Testsuite against the lab's WS echo (from M2, X24), singletons, pairwise, selection fuzzing, the generated `--identity envadmin` selection |
| release (tag `v*`) | each hosted profile | multi-arch images (amd64 on ubuntu, arm64 on ubuntu-24.04-arm, merged), GHCR `ghcr.io/alexh95/odin-htmx-starter-<profile>:vX.Y.Z` and `:sha-<7>`, provenance attestation, a GitHub Release from the CHANGELOG; from M11, the linux_arm64 `term-agent` binary and its SHA-256 attached (Q30; X15) |
| deploy-fly | skeleton | only on a tag, with `vars.FLY_DEPLOY == 'true'`; the first such tag is v2.2.0 at the M3 exit (X2) |

The jobs are D40's; what the test jobs assert is in §19, the parity gate's procedure in §18. **As built (M1):**
`pins`, `check`, `build` ({minimal, skeleton} × {ubuntu, ubuntu-arm, macOS, Windows}, `minimal` also with
`prepare`'s `NO_SQLITE=1`, the size budgets on the Windows legs), `e2e` (`E2E_PROFILE`), `coverage` (the k6 quick run
of each profile, then `tools/check parity`; route coverage has its own job because it needs both suites' counters),
`docker` and the dormant `deploy`; one composite action, `.github/actions/setup-odin`, installs the pinned Odin per
runner. `linux-ops` runs `tools/drills` per profile on `ubuntu-latest` and gates everything but the idle-memory budget,
which it reports with its makeup: a 4-vCPU runner idles about 5 MB above the dev PC's Linux, so that budget is gated
by the dev PC's drills (ANSWERS round 8). The nightly ASan workflow runs e2e and a k6 quick run against an ASan build. **The NPM the job models**
(RESOLUTIONS X40): apollo's NPM is older than the upstream v2.16.0 that D41 modelled, so `e2e-proxy` pins and models
apollo's actual version, recorded in `docs/private/SITE.md` (§2.2). Upgrading NPM is Alex's optional step and never an
agent's; if Alex upgrades it, the job's pin follows.

**As built (M2):** `check`, `build`, `e2e` (three engines), `coverage` and `linux-ops` run `lab` too; `generator`
checks `docs/catalog.json`, runs `odin test tools/init`, refuses a bad selection with nothing changed, and makes and
verifies a rotating singleton. **`e2e-proxy`** runs the lab's specs in chromium through the stack Caddy, running
`deploy/Caddyfile` as it is (its hosts in the runner's `/etc/hosts`, its upstreams the runner through `host-gateway`),
and through NPM's nginx in front of that Caddy: `tests/proxy/npm.conf` is NPM's `nginx.conf` http block and the proxy
host it renders, from the templates of the version apollo runs, with Websockets Support on and §20.4's Advanced
snippet. The pin is that rendering, not the version named: the version is one of `docs/private/SITE.md`'s values,
and the config carries what the job models (NPM's 90 s timeouts, `proxy_http_version 1.1` (2.12's, where X40 expected
1.0), `Accept-Encoding ""` upstream, `gzip on`, `$host` without the port). The suite gained a proxy mode (`E2E_PROXY`,
`E2E_UPSTREAM_PORT`): one worker, the pages through the proxy, the server on the fixed upstream port with the proxy's
origin as its own, and global-setup refuses to run unless the proxy's host resolves to the machine, since the names
are the real ones; `proxy.spec` holds that SSE and multipart arrive as written and uncompressed and a socket echoes.
NPM's nginx consumes `X-Accel-Buffering`, as nginx does every `X-Accel-*`, so the header specs accept its absence
behind NPM (which adds `X-Served-By`), and nginx listens on 80 as NPM does: its `$host` drops a port, which the
browser's `Origin` would keep. Run locally in WSL: 84 passed through each. `streams` joined the job (one proxy host
in NPM's model with both domains): behind the proxies the server sees the proxy's container, not the LAN, so the suite
lets anyone take a nickname there (`ACCOUNTS_NICK_FROM=all`), and the specs that need the LAN or an admin start servers
of their own; 79 passed through each in WSL. The nightly gained **Autobahn|Testsuite** (§19.1.9).
- **The no-SQLite build** proves D18's claim only (no SQLite library, no C compile step). The linker stays (`clang` or
  `$ODIN_CLANG_PATH` on Linux and macOS, the MSVC/SDK libraries on Windows; 09 §6.1), so "no clang" is never a gate.
- **UID 10001** is the skeleton's inherited assertion (`SK/.github/workflows/ci.yml:219`); spark's distroless default
  is 65532 (08 §1.6), so the image sets its user explicitly.
- **The same Odin tooling.** The pin is Odin dev-2026-10 (84bc3fc), the same release the skeleton's CI and
  Dockerfile pin and spark's builder builds, so there is no drift today (09 §0, §1.1). The skeleton's commands go
  through one script: every job builds, checks and tests through `build.{sh,bat} <profile>` at the repo root
  (`CMD=check|test|run`, `-vet -strict-style -warnings-as-errors` and the further vet flags on its line), because each command needs the four
  family flags and Odin has no response files (14 (1); 09 §5's flag-free build is overturned, LC §12). `prepare.*`,
  `run.*`, the Dockerfile, the e2e global setup, `load-tests/run.sh` and `tools/init --verify` call it too, and
  `ols.json` pins the editor to `full`'s families (D40; LC §3); the pin guard (now the `pins` job) and `tools/init`
  stay. A bump to dev-2026-11 goes only through a parity re-run (R3; 09 §1.2). The new dev tools are listed in §2.5;
  the audit of the resulting Odin code is §19.2.

### 20.2 Releases and images

SemVer: **v2.0.0 at the M1 exit**, then one minor release per milestone (D40; the version per milestone is in §2, the
policy and the transition in §4).

- **Naming**: one image per hosted profile, `ghcr.io/alexh95/odin-htmx-starter-<profile>:vX.Y.Z` plus `:sha-<7>`,
  never `latest` in a deploy (the tag is pinned in `.env`). Public GHCR images are free and apollo pulls them without
  credentials (08 §5.3; Q18); the Dockerfile picks Odin's amd64 or arm64 asset by `TARGETARCH` (08 §5.3) and builds
  through `./build.sh <profile> -o:speed`, as every CI job does (§20.1).
- **As built (M3):** the Dockerfile ships `/app/bin` on distroless `base-nossl-debian13`, both bases pinned by
  digest, `STOPSIGNAL SIGTERM` and `HEALTHCHECK` through `--healthcheck`, and `/app/SOURCES.md` generated from the
  base's `dpkg/status.d`. `readelf -d` lists only `libc.so.6`, `libm.so.6` and the loader with SQLite linked
  (skeleton), and the four hosted profiles' images are 6.5–7.4 MB compressed. CI's `docker` job checks all of it
  per profile. **`release.yml`** is §20.1's `release`: on a `v*` tag, the four hosted profiles (`full` joins at
  M4) built natively on amd64 and arm64 runners, pushed by digest, merged into one list tagged `vX.Y.Z` and
  `sha-<7>`, attested (`attest-build-provenance`, pushed to the registry), then a GitHub Release from the tag's
  CHANGELOG section and, with `FLY_DEPLOY`, `deploy-fly`, which moved there from `ci.yml`. Run by hand it is a
  dry run: every image builds and turns healthy, and nothing is published.
- **M1's image** builds one profile (`--build-arg PROFILE=…`, `skeleton` by default) through `build.sh` and ships it
  as `/app/server` on the skeleton's `debian:trixie-slim` base with its bash health check; the per-profile names,
  distroless and `--healthcheck` arrive with the release workflow (M3).
- **Base**: distroless `base-nossl-debian13` with `USER 10001:10001`. Linux Odin binaries need only `libc.so.6` and
  `libm.so.6` (10 §8.1), so this base drops the `cc` image's GPL-3 GCC runtime and OpenSSL; with SQLite linked it is
  UNVERIFIED until M3's `readelf`. An in-binary `--healthcheck` (06 §3.1) replaces the skeleton's bash check
  (`SK/Dockerfile:80-81`): distroless has no shell. Size ≤ 25 MB compressed (D38). **Never ffmpeg** (GPL, S21).
- **Notices**: `THIRD_PARTY_NOTICES` and the `/licenses` route carry the notices listed in §3; published images add
  a `SOURCES.md` naming the Debian source versions of the base packages, for their (L)GPL source duty (10 §8.1, §8.3).
- **The Pi agent is not an image**: the `release` workflow attaches the linux_arm64 `term-agent` binary and its SHA-256
  to the GitHub release as an asset, which Alex copies to the Pi (Q30; RESOLUTIONS X15; §16.2).

### 20.3 Staged hosting

apollo comes first, before anything goes on the public web (D41; BRIEF, S20):

| Stage | URL | Gate to enter | Gate to leave |
|---|---|---|---|
| 0 dev PC | `http://127.0.0.1:<port>` (`run.*`); optional local Caddy `tls internal` for h2 (03 §9) | — | CI green |
| 1a apollo LAN direct | `http://<host>.alexh95.com:8120` on `<APOLLO_LAN_IP>` (the stack Caddy, Host-routed), reached through split DNS (below); a request without a known host gets 421 (X23) | M3: Alex has created `<APOLLO_DATA_DIR>/odin-htmx-starter` and the split-DNS records | smoke + two-host k6 (dev PC → apollo) |
| 1b apollo LAN via NPM | `https://<host>.alexh95.com` with split DNS to `<APOLLO_LAN_IP>` and an NPM Access List "LAN only" | Alex: NPM hosts (the split-DNS records exist since 1a) | 1 h NPM soak, e2e smoke; the family beta from M6 (Q23) |
| 2 apollo public | Access Lists removed except on `/term*` and `/admin*` (also LAN-only in-app); the split-DNS records of the names that go public deleted | the M12 security gate and Alex's go | any of: uptime, the shared-host blast radius, apollo's CPU or disks under video load (the uplink is not a binding trigger, X41) |
| 3 VPS | OVH VPS-2 (€7.21, 4/8 GB) or Hetzner CX33 when orderable, with spark's compose + Caddy https flavour | Alex's decision | — |

- **apollo** is a modest home server (`<APOLLO_CPU>`, `<APOLLO_OS>`, Docker `<APOLLO_DOCKER_VERSION>`), shared with
  NPM, spark (:8111), the old skeleton (:8090, Q27) and Alex's other self-hosted services (`<APOLLO_SERVICES>`), which
  agents never touch; RAM, disk UNVERIFIED (S0.12). NPM + TLS caps it near 1.9k RPS against 22k direct (`api`, 50
  VUs; 08 §1.5): a functional stage; perf numbers are the dev PC's (§18).
- **Stage 1a is HTTP/1.1** (no TLS or h2 in odin-http): §9's page contract keeps a page within 6 connections. Caddy
  routes by Host, so stage-1a LAN testing names the host through split DNS; a request with no known host gets the
  catch-all's 421 (§20.4; RESOLUTIONS X23). Split DNS also avoids the NAT hairpin, about 2.7× slower (08 §3), and k6
  needs no `hosts` overrides on the LAN. LAN-only backends (llama.cpp on apollo's GPU, the Pi) pin features to apollo.
- **Split DNS** (Alex decided it on 2026-10-26; RESOLUTIONS X41): public records with apollo's LAN address. At M3,
  before the first LAN deploy, Alex adds seven DNS-only `A` records at the DNS provider, one per apollo name
  (`houston`, `houston-lab`, `odin-htmx-starter`, `htmx-odin-starter`, `starter-minimal`, `starter-streams`,
  `starter-skeleton`), each pointing at `<APOLLO_LAN_IP>`.
  - Each record overrides the public wildcard for its name, and every resolver gets the same answer, secure DNS
    included. Outside the LAN the names lead nowhere, which is what stages 1a and 1b mean. Alex accepted the private
    address appearing in public DNS.
  - At M12 the records of the names that go public (all but `starter-skeleton`, which stays LAN-only) are deleted, so
    the wildcard applies again. Inside the LAN those names then hairpin through the router unless a LAN DNS is added:
    a stage-2 question.
  - Rejected: the ISP router's static host table (with a test entry, added and removed with Alex's go, it served its
    own address next to the wildcard's alias, and resolvers that follow the alias reached the public address); a Pi
    as the LAN DNS, which would miss devices on secure DNS and adds a device to keep alive; hosts files, which don't
    reach the family.
- **The uplink** is `<HOME_UPLINK>`, so public video from home is plausible at family scale before apollo's CPU or
  disks bind. It is not a binding stage-2 trigger, and Q26's CDN becomes optional (RESOLUTIONS X41; §15.2).
- **What "public" means before M12.** Nothing new is public before stage 2: Houston and its lab host, the lab and
  the witnesses stay behind NPM's LAN-only Access List through stage 1b. The one public deployment is the existing Fly
  demo at `odin-htmx.alexh95.com`, which serves 6d37506 (v1.2.1) untouched from M0 (§4.2 step 1) until the M3 exit
  (D1, §4.3; ANSWERS F5).

**apollo first, Fly last** (D41; RESOLUTIONS X2, X3). The brief puts apollo's LAN before anything on the public web, and
D41 repeats it, so the Fly witness is not redeployed at the M1 exit: v2.0.0 is tagged with `FLY_DEPLOY` still off. By
the M3 exit `starter-skeleton` has passed the parity gate and the 40-item checklist on apollo's LAN (stage 1a). Order at
the M3 exit: Alex sets `FLY_DEPLOY=true` first, then the agent pushes the v2.2.0 tag, and its `deploy-fly` run deploys
`cmd/skeleton`. Alex chose this hold with Q29 on 2026-10-25, over redeploying at M1.

### 20.4 The apollo stack

`deploy/compose.yaml` runs one container per hosted profile behind one stack Caddy (D25, D41):

| Service | Serves | CPU and memory (D38) | Volume |
|---|---|---|---|
| `caddy` | port 8120, published as `8120:80` (it looked free: UNVERIFIED (M3), 08 §6.5); routes by Host; a catch-all `:80` answers 421 (X23); a fixed `ipv4_address` on the stack network, the app's one trusted proxy (X43) | — | — |
| `starter-full` | `houston.alexh95.com` and its lab host `houston-lab.alexh95.com` (`full`: one container, two origins; ANSWERS F2) | `THREADS=2`, `cpus: 2.0`, `mem_limit: 512m` | `/data`: DB, backups, media, recordings |
| `starter-minimal`, `starter-streams` | `starter-minimal.alexh95.com`, `starter-streams.alexh95.com` | witnesses: `THREADS=1`, `cpus: 0.5`, `mem_limit: 64m` | — |
| `starter-skeleton` | `starter-skeleton.alexh95.com`, LAN only, for two-host perf runs (D2) | witnesses | — |
| `starter-lab` | `odin-htmx-starter.alexh95.com` and the aliases (`lab`) | witnesses: `lab` is one (D2, D38; RESOLUTIONS X22) | — |

Every app service has: its image pinned by tag in `.env`; `user: 10001:10001`; `read_only: true` and `tmpfs: /tmp`;
`security_opt: [seccomp=./seccomp-io-uring.json]` (Docker blocks io_uring by default since 25.0, 08 §1.1), a file that
`promote.ps1` stages from `deploy/docker/` next to `compose.yaml` on apollo, as the `docker` job and M3 confirm
(RESOLUTIONS X21); `init: true`; `restart: unless-stopped` (Docker outside Swarm never restarts an unhealthy container,
§10); `stop_signal: SIGTERM`; `stop_grace_period: 10s`; `ulimits: {nofile: 65536}`; the healthcheck below; per service
`logging: {driver: local, options: {max-size: 20m, max-file: "5"}}`, as `json-file` never rotates by default (13 §5.6);
the stack network, whose subnet compose pins, with `TRUST_PROXY` set to `caddy`'s fixed `ipv4_address` as a /32, not to
the subnet; and no published port, since only `caddy` publishes one (§17.8; RESOLUTIONS X43). Limits outside Swarm:
UNVERIFIED (M3; 08 §6.5).
**As built (M3):** `deploy/compose.yaml` is this table without `starter-full`, which joins at M4 (until then the
Caddyfile's Houston hosts answer 502); the Caddy sits at `172.31.120.10`, which every app's `TRUST_PROXY` names as
a /32, with the gateway `.1` as the Caddy's trusted proxy; each service's tag is its own line in `.env`
(`deploy/.env.example`), so promote moves one at a time. `deploy/stack-test.sh` (CI's `stack` job) runs it from
local images and checks the hosts, the 421, the trusted chain, the hardening and a restart behind the Caddy.
The healthcheck is D41's in valid compose syntax (RESOLUTIONS X20):
`healthcheck: {test: ["CMD", "/app/bin", "--healthcheck"], interval: 10s, timeout: 3s, retries: 3}`.

**The stack Caddyfile** (D41, with RESOLUTIONS X23 and X31). Blocks are multi-line only: Caddy's lexer rejects tokens
after `{` on the same line and has no `;` separator. This candidate must pass the proxy-config CI job before it goes
into any doc:

```caddyfile
{
	auto_https off
	servers {
		# X39: the one trusted proxy is the gateway of the stack's own Docker network, which is
		# where NPM's traffic arrives from (<NPM_UPSTREAM_ADDR> in docs/private/SITE.md)
		trusted_proxies static <NPM_UPSTREAM_ADDR>
		trusted_proxies_strict
	}
}

(app) {
	reverse_proxy {args[0]}:8080 {
		header_up X-Real-IP {client_ip}
		lb_try_duration 10s
		health_uri /livez
		health_interval 5s
		stream_close_delay 5m
		flush_interval -1
	}
}

http://houston.alexh95.com {
	import app starter-full
}

# Houston's session-free lab host (ANSWERS F2): the same container; the app answers it from its own route table
http://houston-lab.alexh95.com {
	import app starter-full
}

http://odin-htmx-starter.alexh95.com {
	redir /full https://houston.alexh95.com/ 302
	handle /full/* {
		route {
			uri strip_prefix /full
			redir https://houston.alexh95.com{uri} 302
		}
	}
	# the same pair for /minimal → starter-minimal, /streams → starter-streams, /skeleton → odin-htmx.alexh95.com
	handle {
		import app starter-lab
	}
}

http://starter-minimal.alexh95.com {
	import app starter-minimal
}
# one block each for starter-streams and starter-skeleton

http://htmx-odin-starter.alexh95.com {
	redir https://odin-htmx-starter.alexh95.com{uri} 301
}

# X23: the catch-all for a request without a known host (a bare IP, a typo)
:80 {
	respond "Unknown host: use a host name (docs/OPS.md)" 421
}
```

- **As built (M2): `deploy/Caddyfile`** is this block whole, for the `e2e-proxy` job, which runs it as it is: one
  `(alias)` snippet writes each bare and deep redirect pair (`/full`, `/minimal`, `/streams`, `/skeleton`), and
  `trusted_proxies` names `172.31.120.1`, the gateway of `172.31.120.0/24`, the stack subnet `deploy/compose.yaml` pins
  at M3. `caddy validate` passes on the pinned 2.11.7; the redirect aliases and the catch-all are proxy-config's (M3).
- **As built (M3): proxy-config** is `deploy/proxy-config-test.sh`: it validates the Caddyfile and every
  `caddyfile` block in the committed docs (placeholders filled), runs `nginx -t` on `tests/proxy/npm.conf`, and
  asserts the Caddy's own answers with no app behind it: 8 aliases, the 301, the 421 and the publish.
- **UNVERIFIED (proxy-config CI job)**: the block is D41's with RESOLUTIONS X23, X31 and X39 applied. It needs Caddy 2.8
  or later (`trusted_proxies_strict`; `{args[0]}`, `{client_ip}` and `stream_close_delay` need 2.7), which the pinned
  2.11.7 meets (10 §8.1). The snippet shows the placeholder; the committed Caddyfile names the gateway of the subnet
  compose pins, which is the value the job validates (**NEW**).
- **Port 8120 and unknown hosts** (RESOLUTIONS X23). The `http://<host>` sites bind :80 inside the container, so compose
  publishes `8120:80`. The Caddyfile ends with the catch-all `:80` block: a request without a known host, such as a bare
  `http://<APOLLO_LAN_IP>:8120`, gets 421 and one line pointing to `docs/OPS.md`. Stage-1a LAN testing names the host
  through split DNS (§20.3; RESOLUTIONS X41), and the proxy-config job asserts both the publish and the catch-all.
- **Trusted proxies** (RESOLUTIONS X31, X39). Caddy trusts `X-Forwarded-For` only from the address NPM connects from,
  `<NPM_UPSTREAM_ADDR>`, which the devices session measured as the gateway of the stack's own Docker network: Docker
  masquerades traffic from another bridge, or from the host, to that gateway. So `trusted_proxies` = the stack
  network's gateway, one entry. A LAN host that connects straight to :8120 keeps its own address as `{client_ip}` and
  can't choose its client address. `header_up X-Real-IP {client_ip}` keeps NPM's client address across the second
  hop; the app honours it only from `TRUST_PROXY` peers, which is Caddy's fixed address alone, as a /32 (08 §1.6,
  §6.3; §17.8; RESOLUTIONS X43).
- **The residual risk** (RESOLUTIONS X39): any container on apollo that reaches the published port could claim a client
  address, since its traffic arrives from the same gateway. Those containers are Alex's own services, so the risk is
  accepted. Joining NPM to the stack's network is rejected: it would change NPM's configuration, which is Alex's
  service, and this section never names a container (§17.8).
- `lb_try_duration 10s` turns a deploy gap into latency.
- **No `encode` anywhere**: assets arrive precompressed (§12), NPM gzips HTML, streams stay raw. S0.8 found the
  encoder adds no delay that matters but costs a compressed stream 1.1–2.8 MiB of Caddy's memory; streams opt out with
  `Cache-Control: no-transform` (§8.2), so a Caddy that does compress (stage 0's `tls internal` one, stage 3's
  `Caddyfile.prod`) needs no matcher. M2's `headers.spec` asserts both stream headers and `e2e-proxy` that SSE and
  multipart come back without `Content-Encoding`. **Caddy is never reloaded on app deploys**: a reload force-closes every WebSocket (08 §3.3).

**NPM proxy hosts** (on apollo's own NPM version, which `e2e-proxy` models, §2.2, §20.1; RESOLUTIONS X40; 08 §3.2)
all forward to `http://<APOLLO_LAN_IP>:8120`, never a container name (13 §4.3):

| Proxy host | Domain names (`.alexh95.com`) | Access List |
|---|---|---|
| houston | `houston` | "LAN only" in 1b; at stage 2, LAN-only custom locations `/term` and `/admin` (per-location access lists in NPM are UNVERIFIED (M12); the in-app `.Lan_Only` covers it regardless) and a custom location `/term/agent` that answers 403 |
| houston-lab | `houston-lab` (the same `starter-full` container, through the stack Caddy; ANSWERS F2) | "LAN only" in 1b; removed at stage 2. A separate proxy host, so Houston's custom locations stay on `houston` alone |
| starter | `odin-htmx-starter`, `htmx-odin-starter`, `starter-minimal`, `starter-streams` | "LAN only" in 1b; removed at stage 2 |
| skeleton-lan | `starter-skeleton` | "LAN only" forever |

- **Details**: Websockets Support **on**; Block Common Exploits **off** (it 403s query strings holding a URL or
  `<script>` text); Cache Assets **off** (it overrides the app's cache headers) (08 §3.1). **SSL**: the `*.alexh95.com`
  certificate, Force SSL, HTTP/2 **on**; HSTS with a short max-age and no includeSubDomains from stage 2 (only at
  NPM, D20). **Access List** "LAN only": allow 192.168.0.0/16, deny all.
- **Advanced** tab (server level, inherited into `location /` because it defines none of these):

  ```nginx
  proxy_read_timeout 1h;
  proxy_send_timeout 1h;
  proxy_request_buffering off;
  client_max_body_size 16m;      # 4 MiB upload chunks plus headroom
  proxy_max_temp_file_size 0;    # never spool video to NPM's disk
  ```

- **Never `proxy_set_header` or `add_header` in Advanced**: NPM's `location /` defines both, so nginx drops them
  there (08 §3.1). The app sends `X-Accel-Buffering: no` on every stream, so `proxy_buffering` stays at its default.
  The body cap is 16m, not 08 §3.2's 2g, because uploads arrive in chunks of at most 4 MiB (D35, §17).
- **Global (Q14: yes, 2026-10-25)**: `worker_connections 4096;` in `/data/nginx/custom/events.conf` before the M3
  soak through NPM, Alex's step at M3; apollo's NPM is still at the default 512, which caps about 1,000 proxied
  streams across all of Alex's sites (08 §3.2; RESOLUTIONS X40).
- **The Pi agent** dials `ws://<APOLLO_LAN_IP>:8120/term/agent` with `Host: houston.alexh95.com` and a device token:
  LAN-direct to the stack Caddy, never through NPM, which answers 403 on that path (§16).

### 20.5 Deploys and rollback

`deploy/promote.ps1` is spark's model without `docker save` (D42; S21, 08 §5.4-5.5, 13 §4.4), run from the dev PC
over the SSH alias `<APOLLO_SSH_ALIAS>` (GitHub's runners can't reach apollo behind NAT; 08 §0, §5.4). Alex adds a
permission rule for it, as for spark's; agents run it only when Alex asks. Targets: `apollo-lan`, `apollo`, later `vps`
(08 §5.5).

1. stage the compose file, the Caddyfile, `.env` (the tag) and `seccomp-io-uring.json` next to `compose.yaml`
   (RESOLUTIONS X21);
2. `docker compose pull`;
3. take the pre-deploy snapshot (`docker exec … --backup /backups/pre-<tag>.db`, beside the nightly backups in
   `BACKUP_DIR`, keep 5; up to v2.4.0's promote it went to `/data/backups`);
4. `docker compose up -d --no-deps <service>`, one profile at a time, with no Caddy reload (`lb_try_duration` holds);
5. smoke through the LAN and NPM URLs: `/readyz`, `x-version == tag`, an SSE first event, a WS echo;
6. write `deployed.json`;
7. on failure, re-promote the previous tag automatically; restore the snapshot only after a destructive migration (D16).

**As built (M3):** steps 1–7 as written, with `-Target local` (WSL's Docker, local images) as the script's own
test: a `broken` tag (another profile's image, so `x-version` is wrong) fails its smoke and the previous tag comes
back by itself. The smoke runs `curl.exe` from the dev PC with `--connect-to` the stack's address, so it works before
the split-DNS records exist; the WebSocket check is the upgrade (101). The alias, directory and address are in the
git-ignored `deploy/promote.local.psd1`. Only `starter-full` (M4) has a database to snapshot.
Users see the gap as latency, and streams reconnect once (4,000 back within 1.5 s after a 0.2 s gap, 13 §3.4).
`promote -Status` is a read-only inventory (RAM, disk, kernel, Docker's fd default, NPM version, reachability of
`<APOLLO_LAN_IP>:8111` for the games API), recorded at M3. Backups (off-box per Q16) are in §11; secrets in §17.

### 20.6 Fly's role and the VPS fallback

For the brief's "in case fly.io isn't cutting it": Fly only ever fits the small witness; Houston goes to apollo and,
when needed, a VPS. **Fly** serves only the `skeleton` witness at `odin-htmx.alexh95.com` (app `odin-htmx-skeleton`,
fra; D41): 6d37506 (v1.2.1) from M0 until the M3 exit, then `fly.toml` builds `cmd/skeleton` (RESOLUTIONS X2;
ANSWERS F5); concurrency stays `type = "requests"`, soft 200 / hard 250 (`SK/fly.toml:45-48`; no streams); `kill_timeout` 10 s for the drain (default 5
s, 13 §4.2); the `/healthz` check; `:memory:` reseeded per deploy in D17's mode. Houston never runs on Fly: streams
count against `hard_limit`, EU egress is $0.02/GB, shared CPUs have a 6.25 % baseline (08 §2.1, §2.3, §2.5). The witness
costs $2.19/month (shared-cpu-1x 256 MB, cheapest regions; fra is higher), or $0 on a legacy allowance (08 §2.1).
**The cost check** (Q15, 2026-10-25): Alex keeps the witness and set aside the allowance question, so nobody checks
the allowance; instead, at M0, at the M3 exit (the first starter deploy), at every milestone exit after it and
whenever `fly.toml`'s machine size changes, the agent reads the witness's monthly cost (read-only, or asks Alex for
it when it has no access to Fly's billing), records it in the spike or exit report, and warns Alex at once if it is
over $10/month; the witness keeps running until Alex decides (D41).

**The VPS** (stage 3) comes when uptime, the shared-host blast radius or video load on apollo's CPU or disks demands
it; the uplink (`<HOME_UPLINK>`) is no longer a binding trigger (RESOLUTIONS X41; §20.3):

| Candidate | Size | Price (read 2026-10-25, 08 §4.1) | Caveat |
|---|---|---|---|
| OVH VPS-2 | 4 vCore / 8 GB / 75 GB, unmetered at 1 Gbps | €7.21/month excl. VAT | may assume 12 months up front (UNVERIFIED) |
| Hetzner CX33 | 4 vCPU / 8 GB, 20 TB | €8.99/month | listed "currently unavailable" |
| Netcup VPS 1000 G12.5 | 4 vCore / 8 GB / 128 GB | €14.50/month on a 12-month term | net/gross basis unclear |

All three are KVM with their own kernel, so io_uring works under the seccomp profile (08 §0, §4.1; KVM is inferred
for OVH). The VPS runs spark's `bootstrap.sh`, `compose.prod.yml` and `Caddyfile.prod` unchanged (S20, 08 §4.3);
`Caddyfile.prod`'s `encode zstd gzip` skips the starter's streams by their `no-transform` header (S0.8).
**What moves first** (NEW, from CF §11.3): the witnesses, which hold no state and need nothing on the LAN. Houston
stays on apollo while llama.cpp and the Pi live on the LAN, or moves with a WireGuard link from the VPS to the LAN
(08 §3). **Public video** may go behind a bunny.net pull zone on `/media` ($0.005–0.01/GB, 08 §4.1; Q26, now optional,
since the uplink is not a binding trigger, X41), never through Cloudflare's CDN, whose terms forbid video without paid
products (S20, 08 §4.2), and never through Fly's egress.

### 20.7 Alex's hosting steps

| When | Step | Ref |
|---|---|---|
| M0 | re-run 6d37506's failed CI run so it deploys to Fly (or ask the agent to), then set `FLY_DEPLOY` to `off`; give the apollo facts for S0.12 (Q24: yes) | §4.2 step 1, Q24 |
| M1 exit | leave `FLY_DEPLOY` off: v2.0.0 is tagged without a Fly redeploy (X2; Q29: yes) | §4, Q29 |
| M3 | create `<APOLLO_DATA_DIR>/odin-htmx-starter` with sudo; the permission rule for `deploy/promote.ps1`; at the DNS provider, before the first LAN deploy, split DNS: the seven DNS-only `A` records pointing at `<APOLLO_LAN_IP>`, one per apollo name (`houston-lab` included, ANSWERS F2; §20.3); in NPM, the four proxy hosts above and the Access List "LAN only"; `worker_connections` 4096 before the NPM soak (Q14: yes); optionally, an NPM upgrade, never an agent's step (X40); off-box backups | D41, D42, Q14, Q16, X40, X41 |
| M3 exit | set `FLY_DEPLOY=true` before the agent pushes the v2.2.0 tag, whose `deploy-fly` run redeploys Fly from `cmd/skeleton`; read the agent's Fly cost warning, if any (over $10/month, §20.6) | §4.2, Q15, Q29 |
| after M3 | retire the old skeleton container on `:8090` | Q27 |
| M6 | invite the 2–3 beta members (stage 1b, LAN only) | Q23 |
| M7 | on apollo, the llama.cpp compose project: the Vulkan image pinned to a build, the render device, an API key file, `cpus: 1.0`, a model on the spare disk; check the power supply's rating for sustained GPU load (§14.3) | X41 |
| M11 | bring the Pi 4 home, flash 64-bit Pi OS Lite, wire it and reserve its address; copy the `term-agent` release asset to it and write `/etc/houston/term-agent.env` and the token file (§16.7); the same on the Pi 3B+ for the multi-device tests (Proposed, to confirm at M11) | Q30, X41 |
| M12 | the go-public decision; delete the split-DNS records of the names that go public, so the wildcard applies again (§20.3); remove the Access Lists except `/term`, `/admin` and the `/term/agent` 403; HSTS on; SP2 live (Alex approves and promotes SP1–SP4 at M10, §21); bunny.net, now optional (Q26); read the agent's Fly cost warning, if any (§20.6) | Q13, Q15, Q26, D44, X41 |
| M14 (optional) | the devices M14 serves (camera boards, panels, the TV's Pi; §20.8) on the LAN with reserved addresses, each registered on `/admin/devices`, whose token is shown once | Q33, X42 |
| a stage-2 trigger | the VPS decision (stage 3) | D41 |
| any time | the spare OpenWrt router: nothing until M14's cameras and panels arrive (Q33: yes); then, if wanted, OpenWrt and a fenced network (§20.8) | X41, X42 |

### 20.8 Devices on the LAN

From the device discussion with Alex on 2026-10-25, with the split-DNS decision of 2026-10-26 (RESOLUTIONS X41, X42).
This section names device classes and roles only. Models, addresses, the services each device runs and the
measurements are in the git-ignored `docs/private/DEVICES.md` (apollo's in `docs/private/APOLLO.md`), and site values
use the placeholders of `docs/private/SITE.md`; `docs/design/DEVICES-SUMMARY.md` is the public-safe summary this table
follows. **Decided** means Alex said yes; **Proposed** means Alex has not objected, to confirm at the milestone;
**Open** means Alex is undecided; **No role** means none.

| Device | Role | Status | When |
|---|---|---|---|
| apollo, the home server | Houston's stack as planned (§20.4); the bot's llama.cpp server on its spare GPU, `<APOLLO_GPU>` (§14.3); video sources on its spare disk | GPU: Decided | M3; bot M7 |
| The dev PC | as in §18.5 and §20.5; its 16 GB GPU runs bigger models for occasional bot smoke tests, never as Houston's always-on backend | Decided | M0– |
| A Raspberry Pi 4 (4 GB), Alex's own | the terminal-console target (64-bit Pi OS Lite, wired; §16); a host for a USB camera | Decided | M11 |
| A Raspberry Pi 3B+ | an uptime watcher of apollo from off the box; the second terminal device for multi-device tests (§16.6); LAN DNS only as a fallback | Proposed | M3, M11 |
| A Raspberry Pi 3B | a TV dashboard (a kiosk browser on Houston's Today page), or a radio receiver (§22.3's ideas) | Proposed | after M6; M14's `wall` |
| A Raspberry Pi Zero W | none: ARMv6 and 32-bit only, so it can't run the linux_arm64 `term-agent` | No role | — |
| An ESP32 board with a 2.8" touch screen | a notification and presence panel on a device feed (M14) | Proposed (new feature) | M14 (after M12) |
| An ESP32-S3 camera board | a camera source (M14's `cams`) | Proposed (new feature) | M14 (after M12) |
| A second camera board without USB | a second camera source later (it needs a separate programmer) | Parked | — |
| Two ESP32-S3 boards with small OLEDs | status tiles on the device feed (M14), or spares | Proposed, optional | M14 (after M12) |
| A USB action camera | on the Pi 4 through ffmpeg, for cameras (M14's `cams`) or live video (§22.3's ideas) | Proposed (new feature) | M14 (after M12) |
| A 64 GB workstation laptop | not in the pipeline; optionally an agent-safe Linux sandbox, or CPU trials of larger MoE models | Open | — |
| A gaming laptop with a 6 GB GPU | a Windows test client and a second load generator; the bot's fallback only if apollo's GPU route fails | Proposed, optional | M3 |
| A large Android tablet | the touch and tablet test client; an occasional docked dashboard | Proposed | M4– |
| Two old Android phones | the oldest-browser test device (§19.1.2); IP cameras or kiosks if wanted | Proposed | M6– |
| A handheld Linux gaming PC | a test client with a gamepad, for spark games embedded in Houston (§15.3) | Proposed | M10 |
| A standalone VR headset | a test client for Houston's pages and for WebXR games inside Houston's game embed (§15.3) | Proposed | M10 |
| A spare Wi-Fi 6 router that runs OpenWrt | later, a fenced network for cameras and microcontrollers, and maybe WireGuard into the LAN (Q9) | Open | — |
| An old 802.11n router | none (a spare gigabit switch at most) | No role | — |
| Two handheld VHF/UHF radios | a receive-only radio feed (§22.3's ideas); transmitting waits for Alex's amateur licence | Open | — |

**The pipeline needs none of the optional devices.** M0–M12 run on the dev PC (builds, both gate legs, transcodes,
`promote.ps1`, k6), GitHub CI and apollo. Two-host load runs stay dev PC → apollo: apollo's CPU saturates long before
the dev PC does, so a second load generator adds nothing to a pass rule (§18.5). The other roles (the uptime watcher,
the Windows test client, the second load generator, the tablet, the handheld gaming PC) are optional, and none of them
blocks a milestone (RESOLUTIONS X41).

**Where each fact lands** (RESOLUTIONS X39–X41, X43):
- the bot's host and `BOT_LLAMA_URL`: §14.3, Alex's step at M7 (§20.7);
- the terminal device, the second device and the Pi Zero's limit: §16, §16.6, §16.7;
- split DNS: §20.3, with Alex's steps at M3 and M12 (§20.7);
- the uplink, which is not a binding stage-2 trigger, so Q26's CDN is optional: §20.3, §20.6;
- WebXR in the game embed: §15.3 and `games-frame.spec` (§19.1.4);
- the oldest-browser device: §19.1.2;
- the trusted proxy on apollo (the stack network's gateway) and its residual risk: §17.8, §20.4 (X39);
- the app's `TRUST_PROXY`, Caddy's fixed address only, as a /32: §2.12, §8.5, §17.8, §20.4 (X43);
- apollo's NPM version, which `e2e-proxy` models: §2.2, §20.1 (X40).

**The features the devices open** are M14 Devices, scheduled, optional and after M12 (a device registry and feed,
cameras, a wall and TV dashboard; Q33: yes, 2026-10-26, ANSWERS round 4), and an ideas list (live video, the radio
feed, the mesh bridge, WireGuard into the LAN); both are in §22.3 (RESOLUTIONS X42).

## 21. spark integration

How the starter and spark (`<SPARK_DIR>`, games.alexh95.com) meet, without either waiting on the other.

### 21.1 The principle

No starter milestone waits on spark (D43), with one exception: M12's gate needs SP2 live (§21.2). The iframe embed
works today with no spark change (S22, verified in 06 §2.0), so the games feature ships against today's spark; how it
embeds is in §15. Every spark change is an Ark CL through spark's own loop: the ladder, `tools/commit.ps1` (the
portal green at L2 or above), spark's CI, then an apollo promotion that Alex runs, or that an agent runs when Alex asks
(06 §2.9). The starter proposes; Alex approves.

### 21.2 The spark CLs

| # | spark change (Ark CL) | Where | When | Starter dependency |
|---|---|---|---|---|
| SP1 | `GET /api/games` (about 50 lines) + contract checks | `spark/ws/portal/src/controllers/api.odin`, `portal/src/routes.odin`, `tools/portal-test.mjs` | proposed at the M10 start | `catalog_api`; `catalog_static` until then |
| SP2 | a `frame-ancestors` allow-list on `/play/*` from `SPARK_FRAME_ANCESTORS` (Houston's LAN and public origins) | `spark/ws/infra/compose/Caddyfile:22-26`, `infra/prod/Caddyfile.prod:25-29`, `apollo.env` | M10, **before stage 2** | none (hardening: `/play/*` is frameable by anyone today, 06 §5) |
| SP3 | an embed-mode webcheck test | `spark/ws/games/hello/tests/web/` | with SP2 | none |
| SP4 | a note that healthz `players` is depended on | `spark/ws/CLAUDE.md` | with SP1 | the presence poller |
| SP5 | backports: the markdown depth cap, the `client_address` trusted-proxy fix, QPSG at open, dbview off the exclusive lock | `spark/ws/portal/src/views/markdown.odin`, `controllers/middleware.odin:403-408`, `repository/*` | after M4 | none (fixes spark's own S6 items) |
| SP6 | `UPSTREAM.md` with two pins (`Skeleton commit` kept, `Starter commit` added); `upstream.ps1` reads the repo URL from it and fails loudly (an `error` field in `last.json`); watched paths from the starter's `tools/upstream/paths.json` | `spark/ws/portal/UPSTREAM.md`, `tools/upstream.ps1`, `tools/versions.ps1` | after M1 | none |
| SP7 | a postMessage bridge in embed mode (score, share, crash; target origin from an allow-list, never `*`) | `spark/ws/shared/web/modules/core.js`, `modules/share.js`, `shared/web/defaults.json` | phase 2, after M10 | instant leaderboard refresh, richer invites |

`apollo.env` is spark's deploy target file (`spark/deploy/targets/apollo.env`, not versioned). SP2 is the only CL
on the critical path, and only for M12: it must be live before Houston goes public (§22). SP4 exists because the
poller reads `/ws/<g>/healthz`, an internal payload spark could otherwise change freely (06 §5).

### 21.3 What the starter takes back

From spark's own divergence from skeleton 709bc94 (06 §3.1), with its preconditions applied (D43):

| How | Pieces |
|---|---|
| as is | the `shared/sqlite` additions and `-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1`; Permissions-Policy (minus `interest-cohort`); the `X-Robots-Tag` prefix table; per-route body caps and quiet logging of noisy paths; `limits.odin`; `clean_name`; the catalog cache pattern; distroless + `--healthcheck`; `pagecheck.mjs` as a fast CDP smoke layer beside Playwright |
| with a fix | `markdown.odin` with the depth and input caps; the auth parts (argon2id encoding, CSRF derivation, cookie flags, `--hash-password`) generalised to server-side sessions; dbview on a pool reader connection; `client_address` behind the trusted-proxy check |
| as a pattern | the forward_auth gate (not needed in v1); `ticket.odin` for device and handoff tokens; wsserver's RFC 6455 coverage table as a checklist, its limits and the fault-injection idea, not its I/O loop (S2) |
| not taken | `shared/wt` (WebTransport, MsQuic) |

**The wsserver take-back** (D12, D43; RESOLUTIONS X24). wsserver has no unit tests (03 §5.1), so there are no test cases
to take: the starter takes its RFC 6455 coverage table as a checklist, its limits and the fault-injection idea. The
starter's strict codec gets new unit tests (§19.1.1), and a nightly Autobahn|Testsuite run, a dev-time Docker image
exempt like Playwright and k6, fuzzes the lab's WS echo (**NEW**; §19.1.9).

Two preconditions are S6 items, and each is fixed before the code touches user content:
- **The markdown depth cap.** spark's renderer recurses without a limit: 2,000 nested `>` (2 KB) or lists 2,000
  deep crash the whole process with a stack overflow on Windows' 1 MB main-thread stack (06 §3.2). The starter takes
  it only with the depth cap of 32 and the input cap of 64 KiB (D15).
- **The `client_address` check.** It trusts `X-Real-IP` from any peer
  (`spark/ws/portal/src/controllers/middleware.odin:403-408`), safe in spark only because Caddy is the only way in.
  The starter honours the header only from `TRUST_PROXY` peers, which is empty by default (D10, §17).

### 21.4 The UPSTREAM pin

spark's portal is a fork of skeleton 709bc94 and is 0 commits behind today (06 §3). Its pin
(`spark/ws/portal/UPSTREAM.md:7`, read by the regex at `spark/ws/tools/upstream.ps1:9`) stays 709bc94 and keeps
resolving after the rename, because git follows GitHub's redirect (10 §5.2, verified on a renamed repo) and the
history is continuous: `upstream.ps1:30-31` runs `git log <pin>..HEAD` against the repo URL on line 5. What goes
stale, silently: the watched paths (`upstream.ps1:12-14`) name `app/src/*`, which moves into `platform/` and
`features/`, so `touching_portal` under-reports; and `spark/ws/tools/versions.ps1:19` swallows any watcher error.
SP6 repairs both at Alex's pace, after M1, with the two-pin form and the starter's feature → paths map in
`tools/upstream/paths.json`. The rename and the tags are in §4.

### 21.5 M13: the portal on the starter (optional)

Recommended eventually, as dogfooding after M12, never as a dependency (06 §4). The portal is about
5.3k lines of Odin and uses most of what the starter generalises: a JSON API, body caps and rate limits,
single-admin auth with CSRF, the forward_auth gate, a catalog cache, markdown docs, a read-only DB viewer, SEO and a
distroless image.
- **How**: module by module inside spark's Ark workspace, the portal staying a pinned fork; 60 agent-hours,
  released as a spark CL that Alex promotes (D44).
- **Gate**: spark's unchanged black-box tests, L2 `portal-test.mjs` (about 130 HTTP contract checks), L3
  `pagecheck.mjs` pages and L4 the dev stack. The rebuild is done when they pass unchanged (06 §4).
- **Byte-compatible contracts**: the `SPARK_*` env, `/auth/gate`, the `/api/*` shapes, the `0001_init.sql` hash
  (adopted by the migration runner, §11) and the `spark_admin` cookie.
- **Builder pin**: spark builds in `spark/odin-builder:84bc3fc` (= dev-2026-10). Starter code that spark consumes must
  compile on that pin, or spark bumps its builder (06 §4). 06 §4 and §5 treat them as two pins ("toolchain drift"),
  but 09 §0 item 1 and §1.1 verified that the `dev-2026-10` tag is commit 84bc3fc2…f9, the one spark's builder builds,
  so D40 and D43 are right to equate them today. The risk 06 names is a later bump on one side only: the `pins` job
  and spark's `versions.ps1` keep checking it before M13.
- It is the last item on the cut list (§22).

### 21.6 Licensing (Q17)

spark has no LICENSE file, and its code is Alex's (06 §3.1). Moving spark modules into the zlib starter needs Alex
to grant zlib on the moved files, recorded in the starter's CHANGELOG ("imported from spark CL<n>, licensed zlib by
Alex"). **Alex granted it on 2026-10-25** (Q17: yes; ANSWERS round 1): the spark modules the starter adopts are
licensed zlib, and spark gets a LICENSE, through its own Ark loop (§21.1). The scrub still applies: before
publishing, LAN IPs, host names, apollo paths and `SPARK_*` defaults are scrubbed, and file headers mark the
provenance. The adopted candidates carry no third-party code, and spark keeps its `LICENSE-skeleton` (10 §8.4).

## 22. Milestones, effort, cut list, risks and questions for Alex

The schedule and everything Alex must decide (D44, Appendix C of DECISIONS.md).

### 22.1 How milestones work

- **Effort** is in agent-hours: one focused agent, including tests and docs. Spike code that implements fork or
  stream pieces becomes M1/M2 code and is costed once, in M0.
- **Every exit from M1 on** re-runs the skeleton parity gate (§18) and ships one release: v2.0.0 at M1, then one
  minor release per milestone (the Release column below; SemVer in §4).
- **No exit gate needs a package scoped to a later milestone** (§22.4).
- **The slice gate**: every exit from M4 on adds it to its own checks.
  - (a) route-coverage parity with 0 unexplained waivers;
  - (b) e2e green in 3 engines on `full` and on the feature's singleton generator output;
  - (c) the feature's load budgets met, and the skeleton parity gate re-run green;
  - (d) limits declared to `platform/obs` (§10.4), crash drills for new entry points, a 1 h soak with the feature's
    traffic, TSan clean where shared state was added;
  - (e) `docs/audit/M<n>.md` with 0 open CRITICAL/HIGH and audit-debt under the limit;
  - (f) CHANGELOG, the feature README (and so CATALOG.md), and the PHILOSOPHY ledger if a dependency changed.

### 22.2 M0 spikes

M0 takes 40 h. It also carries the transition (§4.2 steps 1–7: the tags, this workspace as the checkout, the vendored
fork) and the Odin dev-2026-10 install in WSL2 that Alex approved (Q5). Each spike writes `docs/spikes/S0.<n>.md` with
its criterion, result and decision; a failure changes the design before M1 starts.

| Spike | Closes | Pass criterion |
|---|---|---|
| S0.1 Baseline capture | the reference and its noise band are unsettled | HEAD and v1.1.1 built by `tools/baseline`; n = 3 interleaved rounds × every scenario × {mem, file} × {Windows, Linux}; noise band recorded; Linux `scale@200` refusals re-checked (12 §2) |
| S0.2 The fork under the skeleton's k6 | "a forked odin-http keeps the request-path throughput" (03 §10.4) | 709bc94 rebuilt on the fork with F-1 and F-5…F-12: paired ratio ≥ 0.97 against HEAD on every scenario, both legs |
| S0.3 htmx extensions in real browsers against Odin streams | hx-sse/ws/multipart never ran in a browser against Odin (digest critic) | 03's 29 contract checks as Playwright specs against a `platform/stream` prototype on the fork: Chromium and WebKit pass; Firefox in CI at M2 |
| S0.4 `:memory:` parity | D17 | candidates A, B, C on every `:memory:` cell with sort indexes, both legs; pick the first passing one, else Q6 |
| S0.5 Workers and argon2id | the login flow off the loops is unverified (07 §5.2) | fresh timings (3 presets, n = 10); pool + `next_tick` reply + generation check: a disconnect mid-hash causes no use-after-free under ASan; 50 logins/s keep `/ui/ping` p99 within +10 % |
| S0.6 The guard in the fork + watchdog | 13 verified the pieces, not the integration | the 15 crash kinds plus `sqlite` via `TEST_ROUTES` on Windows and Linux; pure → 500 + 20/20 bystanders; lock, async, sqlite → exit 70 ≤ 6 s; WAL size flat after 1000 pure traps mid-iteration (the reader-statement reset); 10k malformed requests including CL −5 → 0 deaths; the watchdog exits ≤ 11 s on a 15 s block |
| S0.7 Drain and restart | 13 §4.1's unbounded waits | exit ≤ 6 s with 500 SSE + 500 WS + a slowloris + a half body + a stuck idle peer; WS got 1012; the bind retry succeeds after `kill -9` at 0/50/100 ms |
| S0.8 Caddy and streams | whether Caddy's `encode` delays SSE events or multipart chunks (03 §8) | a native `caddy run` (dev tool, no Docker): events and parts arrive ≤ 50 ms after the write, with spark's `encode zstd gzip` and without; decide the matcher |
| S0.9 Linux leg on the dev PC | 12 and 13 measured mostly on Windows | Odin dev-2026-10 installed in WSL2 (Q5: yes), with 03 §10.3's obj + lld recipe as the fallback; a TSan build runs |
| S0.10 Bundles | S13's mechanics; the Windows brotli gap | `tools/bundle` builds the four bundles + br/gz from the `EXTS` scan; `bundle-race.spec` 9/9 per engine with assets delayed 400 ms; the minimal bundle's SHA equals the skeleton's `htmx.min.js` |
| S0.11 Tuned SQLite | S10 flags across OSes | builds on Windows and Linux (macOS in CI at M1); size delta ≤ 230 KB; the skeleton's store tests pass |
| S0.12 apollo facts | 08 §9, 13 §8 | Alex provides `uname -m`, `nproc`, `free -h`, `df -h <APOLLO_DATA_DIR>`, the kernel, the NPM version and the NPM container's `ulimit -n` (Q24: yes); the record also names the address NPM connects to the stack Caddy from, its one trusted proxy (RESOLUTIONS X31), which the devices session already measured as the stack network's gateway (X39), and apollo's NPM version, which `e2e-proxy` models (X40) |

The research critic's other critical unverified claims (00-digest) close at named gates: Firefox in CI (the ported
specs at M1, the stream extensions at M2); hx-csp inside stream fragments is settled against app-wide use (S12), with
`/scripting/streams` pinning the gaps (D21; `streams-hxcsp.spec` at M2); NPM's stream behaviour through e2e-proxy's
copy of NPM's config (M2), then apollo's real NPM in the 1 h soak (M3); large request bodies with M6's chunked uploads
of at most 4 MiB per request (D35); the Fly allowance no longer needs settling: Q15's answer replaces it with a cost
warning above $10/month (§20.6).

### 22.3 Milestones M0–M14

| M | Scope | Exit gate (all must hold) | h | Release | Alex |
|---|---|---|---:|---|---|
| **M0** Spikes | the transition (§4.2 steps 1–7: tags v1.2.0 and v1.2.1, this workspace as the checkout with `_ref/` removed and the scrubbed planning docs committed, the vendored fork); the Odin install in WSL2 (Q5); the spikes above | every spike has a decision record; the workspace is the checkout; `x-version: 6d37506` on the Fly witness and its cost recorded (§20.6) | 40 | — | the rename (Q1: yes); re-run 6d37506's failed CI so it deploys (or ask the agent to), then `FLY_DEPLOY` off (§4.2 step 1); the apollo facts (Q24: yes); Q6 if S0.4 needs it |
| **M1** Request-path substrate, `skeleton` at parity | the vendored fork productionised (F-1…F-13 in `app/vendor/odin-http/`); `platform/{sys, ext, guard, obs, app, env, web, html, authz, authz/anonymous, store, store/sqlite, store/memory, sqlite, workers, markdown, theme/full, theme/lite, client/vanilla}`; features dashboard, gallery, contacts, about, notes, home, with their stores in both families where they have them (`app/stores/{sqlite,memory}/`); `build.{sh,bat}` and `ols.json` at the root; `cmd/skeleton`, `cmd/minimal`, four hand-written files each; the migration runner adopting skeleton databases; the skeleton's 23 specs ported and tagged; route counters; `tools/{check (imports, profile, routes, contracts), baseline, bundle}`; CI pins, build, check, e2e, docker, linux-ops, nightly ASan, all through `build.*`; audit stamps begin | every profile and every store checked through `build.*` and on its own; `tools/check profile`, `routes` and `contracts` clean; the parity gate green on both legs; the 01 (A) checklist green; ported specs green in 3 engines (Firefox in CI) + the api project; request-path drills (panic, bounds, div, nil, stack, lock, async, sqlite, hang), fuzz smoke, shutdown bound with slowloris, half body and idle peers, restart, fd ceiling with keep-alive connections; skeleton ≤ 2.75 MiB, idle ≤ 6 MB + 0.4 MB per loop, boot → `/readyz` ≤ 50 ms; minimal builds with no SQLite library; route coverage with 0 unexplained waivers; `docs/audit/M1.md` 0 CRITICAL/HIGH | 70 | **v2.0.0**, tagged with `FLY_DEPLOY` still off: Fly keeps serving 6d37506 (v1.2.1; X2) | rename done; `FLY_DEPLOY` stays off (Q29: yes) |
| **M2** Stream substrate (bundles and CSP, `streams` and the lab pages, generator v1) | `platform/{stream, stream/client, hub}`; `/events` with the cursor procedure; heartbeats, pong deadline, caps, policies, close codes; the writer task; page bundles; flags → CSP; `client/hyperscript` with the gate, and `html.behave` over the `Behaviour` table (D22; moved from M1, whose one client member needed no seam); features chat (memory, the 4 transports behind `chat_web`'s switch), notify (memory), bot (memory, mock, SSE and multipart delivery, the backend switch), ops, status (basic), scripting, compat, lab; the `nick` identity (`features/accounts/identity_nick`, ahead of the rest of accounts; ANSWERS round 9); `cmd/streams`, `cmd/lab` (lab pages only); `tools/check topics` and `exts`; `tools/streamload`; `tools/init` compose mode (`--list --json`, `--explain`, `--profile`, `--features`, `--add`, `--without`, the family commands, `--verify`), with parse-planned edits of the profile files; the generator job (with `tools/check profile`) and singleton rotation; the `e2e-proxy` job with a CI Caddyfile (the same `deploy/Caddyfile`, run in CI) and NPM's generated nginx config (X26); the nightly Autobahn\|Testsuite run against the lab's WS echo (X24) | S0.3's specs and the lab specs green in 3 engines and through e2e-proxy; fan-out, restart (4000 back ≤ 3 s), replay and resync, back-pressure budgets; stream drills (`wsdata` → 1011; shutdown ≤ 6 s with 500 SSE + 500 WS; fd ceiling with 3000 streams); TSan 0 reports on hub, stream, workers and store/sqlite (S0.11), with one suppression for `core:nbio`'s mpsc assert until an Odin bump fixes it (S0.9); 1 h soak; headers, csp-clean, csp-enforced, bundle-race, streams-hxcsp green; minimal, streams and lab built with no SQLite library; generator job green; parity gate green; audit | 65 | v2.1.0 | — (Q32 answered: the bot stays in `streams`) |
| **M3** Pipeline and apollo LAN (and the landing page) | the release workflow (GHCR multi-arch); `deploy/compose.yaml` (`8120:80`, the staged seccomp profile, the valid healthcheck), `promote.ps1`; the proxy-config job for NPM's nginx, the publish and the catch-all (X23, X26); `landing` and the status witness board in `cmd/lab`; stages 1a then 1b; two-host load; 1 h NPM soak; the Fly witness redeployed from `cmd/skeleton` at the exit (X2) | minimal, streams, skeleton (LAN) and lab deployed by `promote -Target apollo-lan -Tag v2.2.x` with smoke; `starter-skeleton` green on the 40-item checklist (01 (A)) on apollo's LAN at stage 1a; a deliberately broken tag rolls back by itself; 0 5xx through Caddy during a promote under 50 VUs; 1000 SSE through NPM held 1 h with no idle cuts; `readelf` confirms the distroless base with SQLite linked; every redirect alias passes its curl test; the seccomp path, the `8120:80` publish and the 421 catch-all confirmed (X21, X23); the apollo inventory recorded; the parity gate green (X25); then `FLY_DEPLOY=true` and the v2.2.0 tag redeploy Fly, and the witness's cost is checked: over $10/month, Alex is warned (Q15) | 30 | v2.2.0; Fly redeployed from `cmd/skeleton` | create `<APOLLO_DATA_DIR>/odin-htmx-starter` (sudo); split DNS before the first LAN deploy (the seven DNS-only `A` records pointing at `<APOLLO_LAN_IP>`, X41); the four NPM hosts (`houston-lab` included) and the Access List; the promote permission rule; `worker_connections` 4096 (Q14: yes; X40); optionally, an NPM upgrade, never an agent's step (X40; the `e2e-proxy` pin then follows); `FLY_DEPLOY=true` before the v2.2.0 tag (Q29: yes) |
| **M4** Identity and the Houston shell | accounts (with envadmin; nick is M2's, ANSWERS round 9), authz enforcement (route perms, step-up, `.Lan_Only`), audit, modules; `cmd/full` with its two hosts: Houston (home and Today cards, nav from brand.odin, themes including `houston` and `accounts_prefs`) and `houston-lab.alexh95.com` with every starter demo and lab page (`landing` at its root, `notes`, the skeleton's `dashboard` at `/dashboard`, `gallery`, `contacts` and `about`, `lab`, `scripting`, `compat`), `app.Host`, per-host tables, the boot's lab rules, `SITE_URL_LAB`, `LAB_NAV`, the `NOTES_CAP` and `CONTACTS_CAP` demo caps and their nightly resets (ANSWERS F2, round 3); the hyperscript behaviours and their vanilla twins; the `full-vanilla` build (`full` with the vanilla client); pairwise and selection fuzzing start nightly | slice gate; the lab host's demo, `lab` and stream pages pass their specs there, and the demo resets run; `rbac.spec` over 100 % of routes × roles, freezing Q31's grants, and every route × both hosts in `full`; `revoke.spec` (X19); CSRF and CSWSH specs; the login-storm budget; behaviour duality (full and full-vanilla); the argon pool memory cap; injected `_` inert; `headers.spec` and `csp-clean.spec` on both of `full`'s hosts (the lab host sets no cookie), and the lab host passes `csp-enforced` and `streams-hxcsp`; Houston and its lab host deployed at stage 1b (no invites yet) | 50 | v2.3.0 | Q10, Q11, Q31; Alex runs `--hash-password` for the bootstrap admin and never shares the password |
| **M5** Operate | ops, status (full), jobs (with leases; backups as jobs), dbview | slice gate; one ops render per second whatever the number of viewers (CPU flat from 1 to 100 viewers); status parts swap independently (parallel order asserted); a backup and restore drill; dbview never takes the writer lock | 28 | v2.4.0 | — |
| **M6** Comms (and the family beta) | chat on SQLite (rooms, DMs, retention, presence, typing, receipts, moderation, attachments, FTS), notify (SQLite), uploads, the connection-mode setting | slice gate; 4 transports × resume specs (including across a restart); the retention spec (`CHAT_ROOM_CAP=5`, send 7 → 5 + the marker); the WS chat budget at 1000 sockets; the writer task ≥ 3× autocommit at 1000 msgs/s; the XSS/UGC suite; an upload decode-bomb fuzz; D22's core flows on the oldest-browser device with no client behaviours (§19.1.2; htmx 4 there UNVERIFIED (M6)); a focused security audit of accounts, sessions, chat and uploads with 0 CRITICAL/HIGH **before the first invite** | 65 | v2.5.0 | Q23: invite the 2–3 beta members |
| **M7** Ask | the bot (SQLite store, llama binding, fakellama, room mode over `bot.ask` and `chat.reply` with the hub's `deliver` rows (RESOLUTIONS X37), the default on `/admin/bot`, health badge); once Alex's llama.cpp project runs, `BOT_LLAMA_URL` = `http://<APOLLO_LAN_IP>:<LLAMA_PORT>` and the tokens/s measured with `llama-bench` (§14.3; RESOLUTIONS X41) | slice gate; room mode stores the bot's answer as a chat message, and a selection without bot drops and counts `bot.ask`; deterministic token e2e; Stop ≤ 100 ms; the queue spec with `BOT_CONCURRENCY=1`; the fakellama parser suite; the 1000-generation mock budget; `x-impl` specs | 25 | v2.6.0 | the llama.cpp compose project on apollo's GPU (the Vulkan image pinned to a build, the render device, an API key file, `cpus: 1.0`), a model on the spare disk, and a check of the power supply's rating (§14.3, §20.7; X41); optional real-model smoke |
| **M8** Plan | wiki (with the seeded docs), find (with the palette), lists (checklist and board), polls | slice gate; FTS MATCH ≤ 3 ms at 100k messages; find respects membership; a wiki markdown fuzz (depth cap) with 0 crashes; board drag and drop (trusted mouse input) and the button fallback both pass; history-cache back/forward with zero server hits on the wiki | 50 | v2.7.0 | — |
| **M9** Watch | video (both stores: memory's `catalog_file` and the SQLite library; Range, HLS + MP4, captions, chapters, resume, signed URLs, web-ready uploads, `tools/transcode`) | slice gate; the Range contract (200, 206, suffix, 416, HEAD, If-Range); playback with `channel: 'chrome'`; 256 MiB ≤ 8 MB peak on Linux; signed-URL expiry; infinite scroll | 35 | v2.8.0 | sample content on the volume (offline transcode) |
| **M10** Play and gather | games (`catalog_static`, `catalog_api` against a stub), c4, calendar, guestbook; SP1–SP4 proposed | slice gate; `games-frame.spec` in 3 engines, with its WebXR case (X41); the poller makes ≤ 3 GETs per 5 s against spark; previews proxied; c4 spectators; the ICS feed parses in the spec; the guestbook moderation-queue spec | 40 | v2.9.0 | approve and promote the spark CLs; optionally, try a WebXR game in the embed on the VR headset (§15.3, §20.8) |
| **M11** Terminal | T1 (15 h) → T2 (55 h: the agent's VT, the grid protocol, the server grid and renderer) → T3 (20 h); start-of-milestone spikes: `hx-ws:send` on a custom trigger, the agent-side grid protocol | slice gate; the agent against `/bin/sh` in CI; replay-agent golden screens (vim, less, htop, the `tput` matrix); 24 h VT fuzz with 0 crashes; 80×24 render ≤ 100 µs; LAN echo p95 ≤ 50 ms on the real Pi; a watcher can't type; kill closes both sides; every terminal action audited; recordings written by the server | 90 | v2.10.0 | set up the Pi 4 (64-bit Pi OS Lite, wired, its address reserved), copy the `term-agent` release asset and install the agent unit with its `EnvironmentFile` (Q30), issue a device token; the same on the Pi 3B+ for the multi-device tests (Proposed, to confirm at M11; X41) |
| **M12** Public | stage 2 | the full-tree audit (`docs/audit/M12.md`, 0 CRITICAL/HIGH), audit-debt 0, M3-03 closed (the stack Caddy trusts NPM by an address only NPM has, the apps on an `internal` network; deferred from M3, `docs/audit/M3.md`), the 8 h fuzz campaign, the 8 h soak, clean sanitizers; SP2 live; HSTS at NPM; `/term` and `/admin` verified LAN-only from outside; an external uptime check; bunny.net on `/media` if Alex chooses it (Q26, now optional, X41); the public names resolve through the wildcard again (X41); the parity gate green; a public smoke from outside the LAN; the Fly witness's cost checked again (Q15: warn above $10/month) | 20 | v2.11.0 (Houston public) | the go-public decision; delete the split-DNS records of the names that go public (X41); remove the Access Lists; bunny.net, optional (Q26) |
| **M13** Portal (optional) | the spark portal on the starter, inside spark's Ark loop | spark's L2/L3/L4 pass unchanged | 60 | spark CL | promotions |
| **M14** Devices (optional, after M12; Q33: yes, 2026-10-26; RESOLUTIONS X42) | a device registry and feed: `/admin/devices` generalises `/admin/term`'s device tokens, plus a plain-text `text/event-stream` (unread count, presence, next event, bot health) for screens that can't render HTML, with its ledger line, row 8 (§3.3); cameras (`cams`): Houston pulls each camera's MJPEG stream once and fans it out to members as `multipart/x-mixed-replace`, which a plain `<img>` renders with no JS, LAN-only and members-only first; a wall and TV dashboard: a kiosk view of Today, signed in by a device token (devices: §20.8) | slice gate; and M14's own gates, as written, fixed by Q33's answer (ANSWERS round 4; **NEW**): one upstream pull per camera whatever the number of viewers; `cams` LAN-only and members-only in `rbac.spec`; a device token reaches only its device's routes, and revoking it closes its feed and kiosk streams; the plain-text feed's format spec; the ledger line in PHILOSOPHY.md | ≈ 30 (estimate) | the next minor | Q33 answered (yes); the panels and cameras of §20.8 on the LAN, each registered on `/admin/devices` with its token (§20.7); the spare router's fenced network, if wanted |

**Ideas, not scheduled** (RESOLUTIONS X42; DEVICES-SUMMARY). Each is Alex's choice, and none is in a milestone:
- **Live video**: the USB camera → the Pi 4 → ffmpeg's hardware H.264 encoder → a sliding live HLS playlist under
  `/media`, a small step from M9's VOD HLS; ffmpeg on the Pi would be a new ledger line, outside every image, so the
  GPL rule holds (§3.3).
- **The radio feed**: a Pi decodes APRS packets and an agent posts them to a hub topic, the agent pattern again; after
  a licence, the licensee's own messages out under a licensee-only, audited permission (relaying other members'
  messages over the air is third-party traffic, which CEPT rules restrict).
- **The mesh bridge**: a Houston room ↔ a licence-free LoRa mesh (868 MHz), where any member may send; text only.
- **WireGuard into the LAN** for the LAN-only pages from outside (Q9), on the OpenWrt router or a container on apollo.

M3's exit gate lists "parity gate green" because D38's rule is every milestone exit from M1 on (RESOLUTIONS X25); M4 on
run it through slice gate (c).

**Total**: about **610 agent-hours** for M0–M12 (M0 40, M1 70, M2 65, M3 30; then 403 for M4–M12), plus 60 for the
optional M13 and about 30 for the optional M14 (an estimate, below). Alex set no cap on effort ("It's going to take
however long it's going to take", ANSWERS #3), so the hours are a guide to size and order, not a budget, and M0–M13's
are not re-estimated for the answers folded in. The substrate (M0–M3, 205 h) is a third of it and comes before the
first showcase feature; Houston is useful to the family from M6. Against the proposals: risk-first's 555 h covered
less scope (no lab landing, calendar, guestbook, home cards or pairwise CI). Product-first's 378 h and
composition-first's 329 h covered wider scope at rates 1.5–2× faster than risk-first's for the same work (the
engineering judge's comparison), so this plan rescales them rather than adopting them.

**M14's hours are an estimate** (**NEW**), sized after Q33 at the rates of the slices each part resembles, not
measured: the device registry and feed about 12 h, at the rate of M11's T1 (15 h), which builds the device rows and
tokens the registry generalises, plus a plain-text encoder over the hub's topics; `cams` about 12 h, at the rate of
M9's Range and stream work (M9 is 35 h for all of video): one upstream client per camera on `platform/stream/client`
and a fan-out over the multipart writer; the wall dashboard about 6 h, a kiosk layout of M4's Today behind a device
token. About 30 h in all, a guide like every figure here.

### 22.4 Dependency check

Each exit gate uses only packages built by then:
- **M0**: spikes run on prototypes, and their code is costed once and lands in M1/M2.
- **M1**: the drills are request-path only (`wsdata` waits for M2, where streams arrive); the platform packages its
  gate exercises are all in its own scope, and `minimal` proves the no-SQLite build.
- **M2**: hub, streams, `client/hyperscript` and the generator's compose mode are built here; `cmd/lab` holds only
  the lab pages, so it imports nothing later. The `e2e-proxy` job and its CI Caddyfile are M2's own scope, run over
  `streams` and `lab` (RESOLUTIONS X26).
- **M3**: deploys only profiles that exist (minimal, streams, skeleton, lab); `landing` and the witness board are
  built here; Houston is not deployed yet; the Fly redeploy uses M1's `cmd/skeleton`.
- **M4**: `cmd/full` first exists and deploys at stage 1b on M3's pipeline, with accounts, authz, audit and modules
  built in the same milestone, and every package its lab host mounts built before it: `notes`, `dashboard`,
  `gallery`, `contacts` and `about` (M1), `lab`, `scripting` and `compat` (M2), `landing` (M3); pairwise starts once at
  least 10 optional features exist (D37).
- **M5**: ops, status, jobs and dbview rely on M4's perms and step-up and M1's store and workers.
- **M6**: chat on SQLite uses M2's writer task and hub; uploads and notify (SQLite) are built here.
- **M7**: the bot's room mode needs chat (M6), which publishes `bot.ask` and mounts `chat.reply`; the hub's `deliver`
  rows arrive here; the mock and memory bot exist since M2.
- **M8**: find's FTS and membership rules search chat (M6); the lab's wiki (`source_files`) arrives here.
- **M9**: web-ready video uploads use M6's uploads; the Range sender (M2's `platform/stream`) rides F-3 (M1).
- **M10**: calendar reminders use jobs (M5) and notify (M6); "Invite crew" links to chat (M6); `catalog_api` is
  tested against a stub until SP1 lands.
- **M11**: the terminal uses `.Lan_Only`, TOTP and step-up (M4), audit (M4) and hx-ws (M2); the `term-agent` CI job
  and the start-of-milestone spikes belong to M11 itself.
- **M12**: builds no packages; it needs one spark change, SP2 live (§21).
- **M14** (optional): the device registry builds on M11's device tokens and `/admin/term`, the feed on the hub (M2),
  `cams` on M2's multipart writer and M4's perms and `.Lan_Only`, and the wall dashboard on M4's Today; nothing before
  it depends on it.
- `full`, `full-vanilla` and `lab` gain each feature in the milestone that builds it, so no profile imports a package
  that doesn't exist yet (D24).

### 22.5 Cut list and the never-cut set

Drop from the top first, ordered by product value (D44). With no effort cap (ANSWERS #3), nothing is cut for time
alone; this is the order to use if Alex asks for a cut:
1. hx-history-cache in the app (move it to a `/lab` page; coverage stays 17/17).
2. c4.
3. The guestbook.
4. In-app web-ready video uploads (keep the offline import, Range, HLS and MP4).
5. Terminal T3 (watch mode, recordings), then T2 (keep T1 line mode with the agent).
6. The calendar's ICS feed, then the calendar.
7. Chat transport D (multipart stays proven by `/status` and bot delivery B).
8. The lists board view (keep checklists).
9. Polls.
10. Bot delivery B.
11. The landing page's init-command builder (keep the catalog).
12. TOTP (then `Term_Write` step-up is by password).
13. QUERY / `hx-query`.
14. The M13 portal rebuild.

**Never cut**: the parity gate and the Fly witness; the fork's limits, timeouts and guard and the crash model; store
v3; accounts, RBAC and audit; chat with the rolling buffer and at least the ws and sse transports; the bot interface
and mock; the games embed; progressive video playback; the 17/17 extension coverage (the lab pages are cheap);
per-route e2e and load parity; the audit procedure; the generator with `minimal`. What is never added unless Alex
asks is in §3.

In-app transcoding with a host ffmpeg is not on the list: it is Q21's non-default option and is not built (§15.2;
RESOLUTIONS X27).

### 22.6 Risk register

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | The fork costs request-path throughput or stability | low / high | S0.2 before anything builds on it; hot path untouched; 03's contract tests in CI; a small vendored diff, re-applied per bump (ANSWERS F3) |
| R2 | `:memory:` parity can't be met | medium / medium | measured by S0.4: no candidate passes every cell; Q6 answered (C, the failing `:memory:` cells gated against HEAD with documented exceptions, ANSWERS round 5) |
| R2a | File-DB write parity: 0.98× clears the 0.97 bar narrowly (12 §2), a watched margin | medium / medium | settled by S0.4: v3's file-DB write measured 0.38–0.43×, so the file DB takes C's group commit too (RESOLUTIONS X17; §18.3), which writes at 2.9–4.3× |
| R3 | core:nbio is young; Windows puts every connection on one loop, so cross-loop bugs show only on Linux | medium / high | Linux legs in parity, TSan, soak and linux-ops; pin dev-2026-10; bump to dev-2026-11 only through a parity re-run (09 §1.2); avoid unbuffered multi-sender `core:sync/chan` until then; TSan flags a plain read inside an `assert` in `core:nbio`'s cross-thread queue (`mpsc.odin:36`), suppressed by name until a bump fixes it (S0.9) |
| R4 | The guard is formally UB (no returns_twice) | low / high | trivial guarded frame, volatile loads; dirty → exit 70; drills on both OSes every push |
| R5 | htmx 4.0.0 bugs (history, SSE abort noise, hx-pending error) | high / low | pin; the known-error allowlist; history-cache first on the cut list; four-dev watched; bump gated by the per-extension e2e |
| R6 | _hyperscript is pre-1.0 with a bus factor of 1, and agents write htmx-2 events | medium / medium | optional client; vanilla twins of the core behaviours; the install-only gate; `--validate` in CI; SHA pin |
| R7 | The single writer stalls (big deletes, checkpoints) | medium / medium | the writer task, chunked deletes, `journal_size_limit`, WAL and lock-wait metrics, the watchdog's 5 s lock alarm |
| R8 | Proxy idle cuts and buffering on apollo | medium / high | 20 s heartbeats, `X-Accel-Buffering`, NPM `proxy_read_timeout 1h`, the e2e-proxy job, M3's 1 h NPM soak |
| R9 | HTTP/1.1's 6-connection pool on the LAN-direct stage | high / low | the page contract (D14); stage 1b for real use |
| R10 | apollo is shared with Alex's other self-hosted services, some holding secrets | medium / high | distroless, non-root, read-only, own network, cpu and memory limits, LAN-only admin and terminal, a VPS trigger before advertising |
| R11 | Scope explosion of the showcase | high / medium | substrate first; slice gates; the cut list; every slice releasable on its own |
| R12 | Perf creep across 13 milestones | medium / high | the parity gate at every exit; micro-guards; the REPREPARE assertion |
| R13 | Box noise makes gates flaky | high / medium | paired interleaved rounds, the background-CPU rule, the one-retry rule, a Linux confirmation, two-host runs at M3 |
| R14 | The terminal is a shell on the LAN | medium / critical | T1 first; Admin + TOTP + step-up; device tokens; an unprivileged agent; LAN-only; audit; idle timeouts |
| R15 | Firefox can't be verified locally | certain / medium | CI-only Firefox; `harness-csp.spec`; no Firefox claim without a CI run |
| R16 | Granularity rot | medium / medium | every profile and singleton built in CI; every store checked on its own; boot checks; `tools/check profile`; the pairwise array |
| R17 | The VT emulator's correctness tail | high / medium | T1 ships first; golden screens; fuzz; the parser lives in the agent, the `--worker vt` fallback |
| R18 | Real family users arrive before the public security review | medium / medium | M6's focused security audit before the first invite; invite-only; LAN-only access |
| R19 | The new stream cursor design (D13) has edge cases | medium / medium | M2 resume specs across a restart; the cursor parser fuzzed; resync as the always-correct fallback |
| R20 | A host-table or identity bug puts the eval-capable lab pages on Houston's session origin, or a session on the lab host (ANSWERS F2; **NEW**) | low / high | per-host tables: a row answers only on the host whose table mounts it; no identity on the lab host; the boot's lab rules (§6.1 check 4); `tools/check routes` per host; `rbac.spec` over every route × both hosts and `headers.spec`'s no-`Set-Cookie` check, from M4 (§7.3, §17.2) |
| R21 | The collection plumbing: bare `odin build app/cmd/<p>` fails, the editor sees one member per family, fewer packages check alone, and a family member that no profile builds could rot (LC §12; **NEW**) | medium / low | `build.{sh,bat}` as the one place the flags live, called by every script, job and the Dockerfile; every profile's line checked per push; every store checked on its own in both families; the envadmin selection nightly; `ols.json` pinned to `full` (§7.2, §20.1) |

### 22.7 Questions for Alex

Each question has a recommended default, and the plan proceeds on the default unless Alex says otherwise. Grouped by
when the answer is needed. Alex answered on 2026-10-25 (`docs/design/ANSWERS.md`, rounds 1–3) and Q33 on 2026-10-26
(round 4). The Status column gives each answer with its date; "default stands (not overridden)" marks a question
raised in conversation whose default Alex left as it is, and "default (not yet raised)" one not yet put to Alex, whose
default the plan follows.

**Before M0** (the transition and the spikes):

| # | Question | Options | Recommended | Needed by | Status |
|---|---|---|---|---|---|
| Q1 | Promote the skeleton by renaming the repo in place to `odin-htmx-starter`? | rename in place (S19) / new repo with history, archive the skeleton / new repo with fresh history | **Rename in place**, after tagging v1.2.0 at 709bc94 and v1.2.1 at 6d37506, branching `skeleton-1.x`, and setting `FLY_DEPLOY` off | M0 | **Answered 2026-10-25: yes**, rename in place, working only in this workspace (ANSWERS #5); 6d37506 is tagged v1.2.1 too, and this workspace becomes the checkout at M0 (ANSWERS F5; §4.2) |
| Q2 | Host names | `odin-htmx-starter.alexh95.com` = lab + aliases, `houston.alexh95.com` = Houston, `starter-<profile>` witnesses / Houston at the starter root and the lab on `starter-lab` / the brief's `htmx-odin-starter` as canonical | **The first**, plus `htmx-odin-starter.alexh95.com` as a 301 alias | M0 | **Answered 2026-10-25: as recommended**, plus `houston-lab.alexh95.com`, `full`'s session-free lab host (ANSWERS Q2, F2; §7.3) |
| Q3 | The showcase's name | Houston / Patchbay / another | **Houston** | M0 | **Answered 2026-10-25: Houston** (ANSWERS #6) |
| Q4 | Fork odin-http: where does the fork live, and when is the seam offered upstream? | a separate repo (`alexh95/odin-http`) as a submodule, created now / vendored in-tree in this workspace / either, never upstream | **Fork now; offer upstream after M2** (round 1 named a separate repo; round 2 recommended in-tree) | S0.2 | **Answered 2026-10-25: fork it, vendored in-tree** at `app/vendor/odin-http/` with `UPSTREAM.md`, no separate repo (ANSWERS #7, F3); the upstream offer after M2 goes through a fork made then (§8.1) |
| Q5 | Install Odin dev-2026-10 in WSL2 for the Linux legs (parity, TSan)? | install in WSL2 / 03 §10.3's obj + lld recipe only / Linux legs in CI only | **Install in WSL2** (one-time dev tooling) | S0.1, S0.9 | **Answered 2026-10-25: yes** (ANSWERS Q5) |
| Q24 | apollo facts and LAN load tests | you provide `uname -m`, `nproc`, `free -h`, `df -h <APOLLO_DATA_DIR>`, the kernel, the NPM version, `ulimit -n` and the address NPM connects to the stack from at M0, and agents may run ≤ 10-minute LAN load tests (cpus capped, announced) / no load tests on apollo | **Yes to both** | S0.12 | **Answered 2026-10-25: yes to both** (ANSWERS Q24) |

**Before M1**:

| # | Question | Options | Recommended | Needed by | Status |
|---|---|---|---|---|---|
| Q6 | If S0.4 finds no `:memory:` mode passing every cell, what does the gate do? | gate the failing `:memory:` cells against HEAD 709bc94 (v1.2.0) with a documented exception / gate the file DB only and report `:memory:` / block M1 until a mode passes | **Gate the failing `:memory:` cells against HEAD**, file-DB cells never waived; asked with S0.4's numbers before M1 | M1 (only if S0.4 needs it) | **Answered 2026-10-26** (round 5): the default; S0.4's candidate C, its failing `:memory:` cells gated against HEAD with documented exceptions |
| Q34 | The login-storm budget, after S0.5 failed its +10 % (§17.1, §18.4) | restate it in absolute terms (other routes' p99 ≤ base + 0.5 ms under `cpus: 2.0`, the cgroup never throttled) and size the argon pool by CPU (1 thread with ≤ 2 CPUs, else 2) / keep +10 % and cap logins lower (fewer than 50/s) / keep +10 % and give the argon pool CPUs of its own (a container of its own) | **Restate it, and 1 thread on ≤ 2 CPUs**: hashing costs a core whatever the design, and +10 % of a sub-millisecond p99 is less than one busy neighbour core costs; the per-client login limits (§17.5) stay in front, so 50/s can only come from many clients | M4 (`accounts`; the plan follows the default meanwhile) | **Answered 2026-10-26** (round 5): the default, the absolute budget and 1 argon thread on ≤ 2 CPUs |
| Q35 | The parity gate's reference on the light routes (§18.2; S0.1) | HEAD alone on `static` and `seo`, max(HEAD, v1.1.1) on the store routes / max(HEAD, v1.1.1) everywhere / a documented exception per light cell | **HEAD alone on the light routes** | M1 exit | **Answered 2026-10-26** (round 5): "light routes (static, seo) gate against HEAD 709bc94 only, store routes against max(HEAD, v1.1.1)" |
| Q7 | _hyperscript pin | 0.9.94 (S15) / 0.9.93 until 0.9.94 has aged | **0.9.94**, SHA-pinned, bumped only through the behaviour suite | M1 (`pins`) | default (not yet raised) |
| Q15 | Keep the Fly witness at odin-htmx.alexh95.com (please check the legacy allowance)? | keep (shared-cpu-1x 256 MB, about $2–3/month) / retire with a 301 / move it to apollo | **Keep** | M1 exit | **Answered 2026-10-25: keep**, with no allowance check; Alex is warned if it costs more than $10/month, checked at M0, at the M3 exit and every exit after it, and on any machine-size change (ANSWERS Q15; §20.6) |
| Q17 | License the spark modules the starter adopts under zlib (and add a LICENSE to spark)? | yes, after scrubbing LAN and host details / no | **Yes** | M1 (first spark code, e.g. `limits.odin`) | **Answered 2026-10-25: yes**, zlib, and spark gets a LICENSE; the scrub of LAN and host details still applies (ANSWERS round 1; §21.6) |
| Q29 | When does the public Fly witness first serve the starter's `skeleton` profile? (§20.3) | hold the Fly redeploy until the M3 exit, after `starter-skeleton` has passed the parity gate and the 40-item checklist on apollo's LAN: you set `FLY_DEPLOY=true`, then the v2.2.0 tag deploys / redeploy at the M1 exit with v2.0.0 | **Hold the Fly redeploy until M3**: apollo before the web, as the brief asks | M1 exit | **Answered 2026-10-25: yes**, hold until the M3 exit; Fly serves 6d37506 (v1.2.1) until then, once §4.2 step 1 has deployed it (ANSWERS Q29, F5) |

The "Needed by" column is this plan's reading of D44's Alex column (**NEW**). Q29–Q33 come from RESOLUTIONS.md (X2,
X15, X16, X32, X42); this plan's final read against the brief first raised Q29 and Q30 (§20.3, §16.7). Q17's answer
applies from the first spark code the starter adopts: in M1 (the `shared/sqlite` additions, or `limits.odin` in
`platform/web`'s limiter), or in M4 if none lands before accounts.

**By M3** (the stream substrate, the pipeline and apollo):

| # | Question | Options | Recommended | Needed by | Status |
|---|---|---|---|---|---|
| Q32 | The bot's place in the starter (§14.3) | a catalog feature, in `streams` and Houston: no model, no llama.cpp and nothing AI ships, while the chat UI, the stream contract, the backend interface, the llama.cpp binding and the mock are what the brief calls relevant / showcase-only: drop `bot` from `streams` (one line) and mark it showcase-only in the catalog | **Keep it as a catalog feature** | M2 (`streams`) | **Answered 2026-10-25: yes**, a catalog feature, in `streams` (ANSWERS Q32) |
| Q14 | Raise NPM's global `worker_connections` to 4096 (affects all your NPM hosts)? | yes, before the M3 soak / no | **Yes** | M3 soak | **Answered 2026-10-25: yes**, before the M3 soak (ANSWERS Q14) |
| Q16 | Off-box backups | nightly pull to the dev PC now, a Hetzner Storage Box (€3.20/TB/month) once public / a Storage Box now / the dev PC only | **Dev PC now, Storage Box at stage 2** | M3 | default (not yet raised) |
| Q18 | Publish public GHCR images? | public, distroless, never ffmpeg / private images / build on the host | **Public, distroless `base-nossl-debian13`, UID 10001, never ffmpeg** | M3 | default stands (not overridden) |
| Q27 | Retire the old skeleton container on apollo `:8090` | once the starter stack runs there / keep it | **Retire it (your step)** | after M3 | default stands (not overridden) |

**Later** (in milestone order):

| # | Question | Options | Recommended | Needed by | Status |
|---|---|---|---|---|---|
| Q10 | Houston's registration mode | invite-only / open / closed | **Invite-only** | M4 | default stands (not overridden) |
| Q11 | TOTP | required for admins and terminal writers, manual secret entry / optional for everyone / none | **Required for admins and terminal writers; no QR encoder** | M4 | default stands (not overridden) |
| Q28 | Runtime disabling of compiled features from `/admin/modules` | no / yes | **No** (D3 never-add list) | M4 | default (not yet raised) |
| Q31 | The default role grants that are judgement calls (§17.1) | as tabled: `Term_Watch` to Moderator and Admin, `Video_Upload` to Moderator and Admin, `Admin_Audit` Admin only / change any of the three | **As tabled**; `rbac.spec` freezes them at M4 | M4 | default stands (not overridden) |
| Q25 | Metrics | the in-app dashboard + admin-gated `/metrics`, no Prometheus/Grafana / add Prometheus and Grafana on apollo | **In-app only for now** | M5 | default stands (not overridden) |
| Q19 | Chat retention defaults | rooms 500 / 7 d, DMs 1000 / 30 d, announcements 100 / 365 d, tombstones / one cap for all / no age cap | **Per room kind as listed**, adjustable up to 5000 / 90 d | M6 | default stands (not overridden) |
| Q23 | The family beta | at M6 on the LAN after the focused security audit, 2–3 people you pick / wait until public | **At M6** | M6 | default stands (not overridden) |
| Q20 | Bot conversation privacy | owner-only, admins see counts and timings / admin-visible / not stored | **Owner-only** | M7 | default stands (not overridden) |
| Q21 | Video pipeline | offline transcode on the dev PC + import, web-ready uploads in-app / a host ffmpeg bind-mounted for in-app transcode / a local-only transcoder image | **Offline transcode + web-ready uploads** | M9 | default stands (not overridden) |
| Q8 | Terminal approach | line mode → PTY with the VT in the Pi agent, no xterm.js / server-side VT in a `--worker` subprocess / add an xterm.js lab | **Agent-side VT, no xterm.js**; `--worker vt` as the fallback | M11 | **Answered 2026-10-25: agent-side VT** (ANSWERS #9) |
| Q9 | The Pi beyond the LAN | LAN-only now, a WireGuard overlay if ever / TLS (OpenSSL) in the agent | **LAN-only**; WireGuard if ever needed, on the spare OpenWrt router or a container on apollo (an idea, §22.3) | M11 | default (not yet raised) |
| Q12 | Terminal forensics | record output (asciicast, 30 days or 1 GiB in total, whichever comes first), never raw input / log commands only / record input too | **Output recordings, 30 days or 1 GiB, no raw input** (the size cap protects apollo's disk, X10) | M11 | default stands (not overridden) |
| Q30 | How does the Pi agent reach the Pi, and where does it read its URL and device token? (§16.2, §16.7) | the `release` workflow attaches the linux_arm64 `term-agent` binary and its SHA-256 to the GitHub release, you copy it to the Pi, and the unit reads `/etc/houston/term-agent.env` as an `EnvironmentFile` (`TERM_AGENT_URL`, `TERM_AGENT_HOST`, `TERM_AGENT_TOKEN_FILE` → `/etc/houston/term-agent.token`, mode 0600); the agent sends its version in `hello` and `/admin/term` flags outdated agents / build it on the Pi with Odin's linux_arm64 release / an agent copies it from the dev PC over SSH when Alex asks | **A release asset plus an `EnvironmentFile`** | M11 | default (not yet raised) |
| Q13 | Keep `/term` and `/admin` LAN-only after going public? | yes / no | **Yes**, in-app and with NPM Access Lists | M12 | default stands (not overridden) |
| Q26 | Public video through bunny.net | at stage 2, public videos only / keep video LAN-only / serve public video from home | **Optional: bunny.net only if public videos get real traffic**; the uplink (`<HOME_UPLINK>`) is not a binding stage-2 trigger, so the CDN is no longer needed by default (RESOLUTIONS X41; §20.3) | M12 | default (not yet raised) |
| Q33 | Which device-driven features join the plan as M14? (§20.8, §22.3) | the device registry and feed, cams and the wall dashboard / a subset of those three / none, with M14 dropped / also some of the ideas (live video, the radio feed, the mesh bridge, WireGuard) | **The device registry and feed, cams and the wall dashboard**; live video, the radio feed, the mesh bridge and WireGuard stay ideas | after M12 (M14) | **Answered 2026-10-26: yes**, M14 Devices with the default scope: the device registry and feed, cams and the wall dashboard; live video, the radio feed, the mesh bridge and WireGuard stay ideas (ANSWERS round 4; §22.3) |
| Q22 | A PWA service worker and i18n catalogs | keep out (never-add) / add the PWA late / add both | **Keep both out** | any time | default stands (not overridden) |

Round 3 (2026-10-25) answered two items that map to none of Q1–Q33: the no-DI choices of `LEAN-COMPOSITION.md` §13,
where Alex took the simpler set (per-package `ROUTES` mounted by hand-written `routes.odin`, four family collections on
`build.{sh,bat} <profile>`'s line, hand-written switches for the transports and the bot backend, the bot default on
`/admin/bot`, notify by direct import, audit through `store:audit`, room mode over static topic rows), and what "every
feature" in `full` covers (every catalog feature, with every starter demo and lab page on `houston-lab.alexh95.com`,
its demo data capped and reset nightly). See ANSWERS round 3; both are folded into §1.5, §5–§7 and §13–§15.

The device discussion (2026-10-25, split DNS on 2026-10-26; `docs/design/DEVICES-SUMMARY.md`, RESOLUTIONS X41) decided
three more items that map to none of Q1–Q33: the bot's host (apollo's spare GPU), the terminal device (a Pi 4) and split
DNS (seven DNS-only `A` records). They are folded into §1.5, §14.3, §16, §20.3 and §20.8.

Round 4 (2026-10-26) answered Q33 (the table above): M14 Devices is scheduled, optional and after M12, with the default
scope. It is folded into §1.1, §1.4, §1.5, §2.7, §2.9, §3.3 (ledger row 8), §13.2, §20.7, §20.8 and §22.3, where M14's
gates stand as written and its hours are an estimate (ANSWERS round 4; RESOLUTIONS X42).
