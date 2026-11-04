# Design decisions: odin-htmx-starter and Houston

Synthesis of the design round, 2026-10-25; the lean composition, X36–X43, the device inventory and ANSWERS round 4
(Q33) folded in 2026-10-26 (§0). This file is the consolidated design and the source of truth for `docs/PLAN.md`;
`docs/design/OUTLINE.md` cuts PLAN.md into sections and names which decisions each section carries.

Inputs: `docs/BRIEF.md`, the skeleton's `PHILOSOPHY.md` (tag v1.2.0), `docs/design/SETTLED.md` (S1–S22),
`docs/research/00-digest.md` and notes 01–14, the three proposals (`proposal-risk-first.md`,
`proposal-product-first.md`, `proposal-composition-first.md`), the three judges' verdicts, and
`docs/design/LEAN-COMPOSITION.md` (the no-DI mechanism, as revised to ANSWERS round 3).

Citation style: research "03 §7", and note 14 by its numbered experiments, "14 (1)"; settled "S8"; skeleton
`SK/<path>:<line>` (= the skeleton at 709bc94, tag v1.2.0, D1);
proposals "RF §4.5" (risk-first), "PF §6.2" (product-first), "CF §4.6" (composition-first); the lean composition "LC §6"
(`LEAN-COMPOSITION.md`, whose §16 records its prototype runs); Alex's answers "ANSWERS #5" (round 1), "ANSWERS F2"
(round 2's follow-ups, always with the prefix, so they never read as 02's audit findings "02 F5"), "ANSWERS round 3" and
"ANSWERS round 4" from `docs/design/ANSWERS.md`. **NEW** = proposed here or in a proposal and not verified by any note;
**UNVERIFIED** = needs the named spike or CI job before it can be relied on. Each decision ends with **Alex confirms**:
"no" means it follows from the brief, SETTLED and research and the plan proceeds on it; "yes (Qn)" points to the
question in Appendix C. Since Alex's answers (§0), each question named there also says where it stands: "answered" with
the answer and the date, "default stands (not overridden)" (raised with Alex, who overrode nothing), or "default (not
yet raised)".

---

## 0. Basis

**Resolutions folded in, 2026-10-25.** The lead architect's `docs/design/RESOLUTIONS.md` (X1–X35) decided the open
items that the PLAN.md writing round left. They are folded into the decisions below and cited "X12". Four became
questions for Alex (Q29–Q32, Appendix C), and Q12's default changed (X10). Renamed throughout: `NICK_FROM` →
`ACCOUNTS_NICK_FROM` (X7), `user_prefs` → `accounts_prefs` (X9), and every room URL is keyed by slug (X12).

**X36–X43 and the device inventory folded in, 2026-10-26.** RESOLUTIONS X36–X43 and `docs/design/DEVICES-SUMMARY.md`
(cited "DEVICES-SUMMARY") land in D3, D6, D10, D25, D31, D32, D33, D34, D35, D36, D37, D40, D41 and D44 and in
§0.2's S20 row, and add Q33 (Appendix C). X43 makes the app's `TRUST_PROXY` Caddy's fixed address alone (D10, D35,
D41).

**ANSWERS round 4 folded in, 2026-10-26.** Alex answered Q33: yes, M14 Devices with the default scope. It lands in D3
(the ledger's row 8), D29 and D36 (the `devices`, `cams` and `wall` features, marked M14), D41, D44 (M14 scheduled,
its gates and its estimate) and Appendix C.

**Alex's answers folded in, 2026-10-25 and 2026-10-26.** `docs/design/ANSWERS.md` records what Alex answered in
four rounds, rounds 1–3 on 2026-10-25 and round 4 on 2026-10-26; it is folded into the decisions below. In short:
- **Repo** (Q1, Q29, ANSWERS #5, F5; D1): rename in place. This workspace becomes the renamed repo's checkout at M0,
  `_ref/` goes, and the planning docs are committed after the scrub. The skeleton's crash fix 6d37506, already on
  `master`, becomes v1.2.1; v1.2.0 is still to be tagged at 709bc94, and the S18 baseline stays 709bc94 + v1.1.1. Fly
  serves 6d37506 from M0 until the M3 exit; its deploy has not run yet (D1 step 1).
- **Names and hosts** (Q2, Q3, ANSWERS #4, F2, round 3; D2, D24, D25, D29): Houston; the hosts as recommended,
  plus `houston-lab.alexh95.com`. `full` implements every catalog feature itself, with no dependency on another
  profile's container (one container, two origins). Houston proper stays on `houston.alexh95.com`; every starter
  demo and lab page goes on the session-free `houston-lab.alexh95.com`: the skeleton's notes, contacts, gallery and
  dashboard, the lab's stream contract pages, scripting and compat (the four lab-only extensions), and `landing` at
  that host's root. Each host has its own root, and the demo data there is capped and reset nightly. `lab` stays an
  independent witness.
- **The fork** (Q4, ANSWERS #7, F3; D11): vendored in-tree at `app/vendor/odin-http/` with `UPSTREAM.md`; no separate
  GitHub repo.
- **Public-repo hygiene** (ANSWERS F4; D40, D45): `docs/research/`, the proposals, `OUTLINE.md` and `docs/private/`
  are git-ignored, and site details stay out of committed docs.
- **Kept as recommended**: the agent-side VT (Q8; D32), zlib for the adopted spark modules (Q17; D43), both client
  implementations (ANSWERS #2; D22), no cap on effort (ANSWERS #3; D44), and yes to Q5, Q14, Q15 (warn Alex above
  $10/month), Q24 and Q32.
- **Devices** (Q33, ANSWERS round 4, 2026-10-26; D3, D29, D36, D44): M14 Devices is scheduled, optional and after
  M12, with the default scope: the device registry and feed, cams and the wall dashboard. Live video, the radio feed,
  the mesh bridge and WireGuard stay ideas.
- **Lean composition** (ANSWERS #1, F1, round 3; D4–D10, D19, D26, D27, D45): layers call each other directly, with
  no dependency injection. Alex took the main session's simpler set (ANSWERS round 3), which LC folds into one
  mechanism (LC §1):
  - **four family collections on the build line**, `store` (`app/stores/{sqlite,memory}/<f>/`), `identity`, `client`
    and `theme`, spelled only in `build.{sh,bat} <profile>` at the repo root; imports land on the real code, with no
    alias packages (D8);
  - **hand-written `switch`es** with a direct call per case for the axes chosen per request: one in `chat_web` over
    all four transports, which every chat profile ships, and one in `bot_web` over the backends, whose default is set
    on `/admin/bot` (D8, D31);
  - **hand-written profile files**: `main.odin` (the boot sequence as plain calls) and `routes.odin` (one mount line
    per package's `ROUTES`, per host), as in the skeleton; the generator writes and edits them, and CI checks that
    they are consistent (D7, D26);
  - **cross-feature calls**: notify by direct import (a hard dependency of every producer), the audit log through
    `store:audit`, and the bot's room mode over static `TOPICS` rows (D6).

  This replaces D5–D8's `Feature` struct and `register()` calls, the proc-field vtables handed in from `cmd`,
  `platform/ports`, `app.Capability`, `Module_Ops`, the `STORE` switch, D7's `--emit --like` byte check and X33's
  vtable `exts` path (§0.3). What those decisions said and still holds is kept below: D9's prefix rule, D5's boot
  checks (now per host), X29's per-package `EXTS`, X30's L4 `platform/app`, and the switching rule of D8.

Appendix C's Status column records where every question stands; the round-3 answers and the device decisions map to
no question number and are recorded under its table.

### 0.1 The base proposal

The three lenses are weighted equally.

| Lens | risk-first | product-first | composition-first | Lens winner |
|---|---:|---:|---:|---|
| Philosophy and legibility | 76 | 60 | 65 | risk-first |
| Engineering risk, performance, effort | 86 | 59 | 65 | risk-first |
| Brief coverage and product value | 80 | 86 | 83 | product-first |
| **Sum** | **242** | **205** | **213** | **risk-first** |

**Base: risk-first** (substrate first, measurable gates, honest effort, the F-1..F-12 fork checklist, the parity
procedure, the M0 spikes). Grafted in:

- **From product-first**: Houston as the household's home channel and its tenets; the page-level realtime contract
  with a render-time cursor; the closed `Behaviour` enum with hyperscript and vanilla twins behind one `html.behave`
  seam; route rows that carry their perm and flags; a home card per feature; chat retention per room kind, an
  in-memory ring with a global byte budget and the "connection mode" framing of the four transports; the bot's
  front-end stream contract; proxied game previews; the household features (lists with a board view, polls, calendar,
  visitor log); a LAN family beta once Comms exists; server-side theme preferences; the lab profile on its own origin.
- **From composition-first**: the domain / views / web / impl package split; the closed `Ext` enum from which the
  bundle and the htmx-config allowlist are derived; the generator's `--explain`, `--verify` and lean defaults;
  route-coverage parity from per-route request counters; audit stamps with an audit-debt gate; the pairwise covering
  array over feature presence; namespacing lints; no foreign keys across features; eval-capable pages kept off any
  origin that holds sessions; the landing page (catalog explorer and init-command builder); the VT parser kept out of
  the server process; CI proving the generator reproduces each hosted profile (now a consistency check of the
  hand-written profile files, `tools/check profile`, D7).

Every item in the judges' `must_fix_in_synthesis` lists is resolved; Appendix B maps each one to its decision.
Appendix A lists every factual error the judges found, re-checked against the research, and what this design does
instead.

### 0.2 SETTLED items refined or overturned

| Item | Change | Evidence |
|---|---|---|
| **S9** (wording overturned) | "profiles without SQLite need no C toolchain" becomes "need no SQLite library and no C compile step". The platform linker is still required: `clang` (or `$ODIN_CLANG_PATH`) is the link driver on Linux and macOS, and Windows still needs the MSVC/SDK libraries. "Optional through a Store vtable" becomes "optional through `store:<f>`, the build's store family" (D8, D18; ANSWERS #1) | 09 §6.1 (`src/linker.cpp:613-616`; 09 line 335); 14 (1); LC §16 (`$L2 a`: the memory build's linker line holds no C library) |
| **S18** (refined) | "12 shows store v3 does" holds for the file DB only. On `:memory:` no measured mode passes every cell, so spike S0.4 and question Q6 decide before M1 (D17) | 12 §2, 16T mem table |
| **S3** (refined) | Stream event ids are `<epoch>-<seq>`; persisted topics additionally resume by SQLite rowid through a keyset replay before falling back to `resync` (D13) | 13 §3.6, §7 item 8 |
| **S5** (refined) | The guard wraps every nbio completion callback the fork owns, not only callbacks into user code; a trap inside SQLite is dirty; a pure recovery resets the loop's reader statements (D15) | 13 §1.3, §2.1; 12 §10 |
| **S12** (refined) | `/scripting/*` and `/compat/*` exist only on origins with no sessions: the `lab` profile's, and `full`'s second host `houston-lab.alexh95.com`, which carries every starter demo and lab page (D20, D25; ANSWERS F2, round 3) | CF §4.8 reason 3 (cookie `Path` does not isolate same-origin pages) |
| **S15** (refined) | Behaviours are a closed enum emitted only by `html.behave`, with a vanilla twin where one exists (D22) | 05 §9; PF §5.5 |
| **S17** (overturned in part, and refined) | "Explicit `register()` calls; proc-field vtables for alternative implementations; runtime env selection only among the implementations the profile imports" becomes "hand-written `main.odin` and `routes.odin` per profile; the store, identity, client and theme families as collections on `build.{sh,bat} <profile>`'s line; hand-written switches for the transports and the bot backend" (D7, D8; ANSWERS #1, round 3). One package per feature, one entry package per profile whose imports are the selection, and the composing generator stand. Per-request implementation switching is allowed only on transport axes and the bot backend, and every response names the implementation (D8) | ANSWERS #1; 14 (1), (2); LC §3, §4, §6; philosophy judge must-fix 16 |
| **S20** (refined) | "Video goes to bunny.net when public" becomes "a bunny.net pull zone is optional for public video (Q26)": the home uplink is not a binding stage-2 trigger (D33, D41) | DEVICES-SUMMARY (`<HOME_UPLINK>`); X41 |

Everything else in SETTLED stands as written, and the design round's open items (what a profile is at hosting time,
the showcase, the terminal approach, chat transports, milestones, the profile catalog) are decided below. One research
finding is overturned too: 09 §5's flag-free `odin build cmd/<p>`, since every build now names the four families
(D7, LC §12 item 1).

### 0.3 The lean composition: what went, and the names it adds

What ANSWERS #1 and round 3 deleted, and what replaces it (LC §14):

| Deleted | Replaced by |
|---|---|
| the `Feature` struct and each feature's `register()` (D5, D7) | per-package `ROUTES`, `TOPICS`, `JOBS` and `EXTS`, mounted per host by the profile's `routes.odin`; explicit `init`, `start` and `drain` calls in `main.odin` |
| the proc-field vtables `Store`, `Transport`, `Bot_Backend`, `authz.Identity` and their constructors (D8) | the four families on the build line; hand-written switches in `chat_web` and `bot_web`; store contracts as typed constants (D8) |
| `platform/ports` (D6) | notify by direct import; audit through `store:audit`; room mode over the `bot.ask` and `chat.reply` rows |
| `Feature.nav`, `home_card`, `search`, `ops`, `env`, `jobs`, `migrations`, `topics`; `app.Search_Hit` | `NAV` and `LAB_NAV` in `brand.odin`; `HOME_CARDS` and `FIND_SOURCES` in `main`; obs pushes; `platform/env` reads in each `init`; `JOBS`; one `migrate` call per store in `main`; `TOPICS`; `store.Search_Hit` |
| `Module_Ops`, its `zone` included (D15) | health, metrics and limits pushed to `platform/obs`; `start` and `drain` called by `main`; guard's counters decide pure or dirty |
| `Feature.requires` and `app.Capability` | a build that reaches a missing family member fails to compile; the generator refuses first, with advice |
| `Feature.extensions` and X33's vtable `exts` union | `BUNDLE_EXTS` in `main` against the bundle header; `tools/bundle` over the compiler's package list (D19) |
| per-feature store choice and `STORE` at boot (D8, D10) | one store family per build |
| X29's lean transport sets | every chat profile ships the four transports |
| D7's `--emit --like` byte check | `tools/check profile` |
| the `.Lab_Host` host filter in `front` | per-host tables; `.Lab_Host` stays as a mount rule (D25) |
| the bot default on `/admin/modules` (D8, D31) | bot's own `/admin/bot` |

**New names** (PLAN §2 defines them, and PLAN §7.4 the generator's commands): `app/stores/{sqlite,memory}/<f>/` with
packages `<f>_store_sqlite` and `<f>_store_memory`; `features/<f>/models/` (`f_models`); the collections `store:`,
`identity:`, `client:`, `theme:`; `build.{sh,bat} <profile>` and `ols.json` at the repo root; `app/cmd/<p>/`'s four
files `brand.odin`, `main.odin`, `routes.odin`, `routes_test.odin`; `app.Host` and `HOSTS`; `MAIN_ROUTES` and
`LAB_ROUTES`, `MAIN_TOPICS` and `LAB_TOPICS` (`full`), or `ROUTES` and `TOPICS` (one host); `JOBS`; `HOME_CARDS`,
`FIND_SOURCES`, `BUNDLE_EXTS`; `web.ROUTES` and `web.PUBLIC_ROUTES`; `LAB_NAV`; `platform/env`;
`platform/authz/anonymous` (`authz_anonymous`); the topic families `bot.ask` and `chat.reply`; the job ids `notes.reset`
and `contacts.reset`; `NOTES_CAP` and `CONTACTS_CAP` (X38); `tools/check profile`, `topics` and `contracts`; the
generator's `--add`.

---

## A. Repo, names and philosophy

### D1. Repo: promote the skeleton by renaming it in place

**Decision.** Rename `alexh95/odin-htmx-skeleton` to `alexh95/odin-htmx-starter` (Q1: yes, 2026-10-25). History
continues and versioning continues at v2.0.0. All starter work happens in this workspace, which becomes the renamed
repo's checkout at M0 (ANSWERS #5, F5). The skeleton's default branch is `master`, and its tip is **6d37506**, the fix
for the `Content-Length: -5` crash (02 F1, §1.2), pushed on 2026-10-25: `front` now answers any `Content-Length` that
is not plain digits within `int` with 400 and closes the connection, and `auto_expect_continue` is off. `FLY_DEPLOY`
was still on, but that push's CI run failed (the chromium e2e job timed out in its toolchain step) and so skipped
the deploy job: on 2026-10-25 the Fly witness still answered `x-version: 709bc94`. The transition runs in this order
(who does it in brackets):

1. **[Alex, or the agent when Alex asks]** Re-run 6d37506's failed CI run, so that its deploy job puts v1.2.1 on Fly,
   and confirm `x-version: 6d37506` on odin-htmx.alexh95.com (UNVERIFIED (M0)). **[Alex]** Then set the repo variable
   `FLY_DEPLOY` to `off`. The deploy job runs only on a default-branch push with `vars.FLY_DEPLOY == 'true'`
   (`SK/.github/workflows/ci.yml:420`); CI triggers only on pushes and PRs to master/main (`ci.yml:5-9`), so tags and
   other branches never deploy, but starter commits on master would.
2. **[agent]** Tag **v1.2.0 at 709bc94 with no code change**, tag **v1.2.1 at 6d37506** (the crash fix, already on
   `master`), and branch **`skeleton-1.x`** at 6d37506. v1.2.0 is exactly the build S18 measures; the parity baseline
   stays 709bc94 plus v1.1.1 (ANSWERS F5). v1.2.1 is the skeleton's last release and the build Fly serves from step 1
   until the M3 exit (steps 8 and 9).
3. **[agent, optional, for spark]** The QPSG fix (`sqlite3_db_config(db, 1007, 1)` after open, 01 §14.4) lands on
   `skeleton-1.x` as v1.2.2. It never changes the baseline.
4. **[Alex]** Rename the repo in GitHub settings. Never create a repo named `odin-htmx-skeleton` afterwards: that
   kills the redirects (10 §2.1).
5. **[agent]** Make this workspace the renamed repo's checkout (ANSWERS F5): bring in the repo's history and working
   tree with `master` at 6d37506; remove `_ref/` (`SK/` citations then resolve against tag v1.2.0); fold the
   workspace's own README, an index of the planning docs, into `docs/` so the repo keeps its README; add D45's
   `.gitignore` rules (ANSWERS F4); and commit the planning docs once D45's scrub has run. The separate local clone of
   the skeleton, used for steps 2 and 3, is deleted once the workspace is the checkout. There is no fork repo to
   create (step 7).
6. **[agent]** First code commit: the `tools/init` identity literals change in lockstep, read from one
   `tools/init/UPSTREAM` file (`SK/tools/init/main.odin:48-53,197,208-246,288-309`, `SK/app/src/views/brand.odin:28`;
   10 §5.3); `THIRD_PARTY_NOTICES` carries the Shopify MIT notice that `hx-multipart.min.js` drops (10 §8.3).
7. **[agent]** Vendor laytan/odin-http fac113f into `app/vendor/odin-http/` with an `UPSTREAM.md`, replacing the
   skeleton's `app/odin-http` submodule; F-1..F-13 land on top, S0.2's changes first (D11; Q4; ANSWERS F3).
8. **[agent]** At the M1 exit (the `skeleton` profile passes the parity gate), the agent tags **v2.0.0** with
   `FLY_DEPLOY` still off. The Fly witness is not redeployed: odin-htmx.alexh95.com keeps serving 6d37506 (v1.2.1)
   untouched until the M3 exit (X2; Q29: yes, 2026-10-25).
9. **[Alex, then agent]** At the M3 exit: by then `starter-skeleton` has passed the parity gate and the 40-item
   checklist (01 (A)) on apollo's LAN (stage 1a). `deploy/fly/fly.toml` builds `cmd/skeleton`. Alex sets
   `FLY_DEPLOY=true` first, then the agent pushes the **v2.2.0** tag, and its `deploy-fly` run deploys `cmd/skeleton`;
   the agent then records the witness's cost (D41, Q15). This honours the brief's "apollo before the web" (X2, X3;
   Q29).

spark's `UPSTREAM.md` pin stays at 709bc94 and keeps resolving through the redirect (10 §5.2, verified on a renamed
repo). Its watched paths go stale when `app/src/*` moves into `platform/` and `features/`; spark repoints at Alex's
pace through Ark CL SP6 (D43).

**Rationale.** 10 §2.1 (web, git, API, tarball and badge redirects verified on a renamed repo); 10 §0 (0 forks, 1
outside star, 26 views in 14 days); 10 §5.2 (spark's `upstream.ps1` needs continuous history, and `versions.ps1:19`
swallows the error a fresh-history repo would cause).

**Rejected.** A new repo with carried history and the skeleton archived (issues, releases, settings and secrets move
by hand, 10 §2.2). A fresh-history repo (breaks spark's pin silently, 10 §5.2). Keeping the skeleton live and frozen
(freezes the bound-LIMIT regression in public, 10 §2.3). Landing the QPSG fix before tagging v1.2.0 (PF §2 step 1,
CF §2.1 step 2): it changes the frozen reference, and in PF's order the live demo is still armed to redeploy.

**Alex confirms:** answered 2026-10-25: Q1 yes (rename in place, ANSWERS #5), Q29 yes; this workspace becomes the
checkout (ANSWERS F5). Steps 1 and 4, and the `FLY_DEPLOY` switch in step 9, are Alex's (step 1's re-run may be
the agent's when Alex asks).

### D2. Names and hosts

**Decision.** Repo and starter: `odin-htmx-starter`. Showcase product: **Houston** (profile `full`). Every host is one
label under `alexh95.com`, covered by the `*.alexh95.com` wildcard certificate (two-level names are not, 09 §5):

| Host | Serves | Where |
|---|---|---|
| `houston.alexh95.com` | profile `full` (Houston) | apollo |
| `houston-lab.alexh95.com` | `full`'s second, session-free origin: every starter demo and lab page: `landing` at its root, notes, the skeleton's contacts, gallery, about and dashboard (at `/dashboard`), the lab's `/lab/streams`, and `/scripting/*` and `/compat/*`, the four lab-only extensions' pages (D25; ANSWERS F2, round 3). It never sets or reads a session | apollo, the same `starter-full` container |
| `odin-htmx-starter.alexh95.com` | profile `lab` (a witness, X22): the starter's landing page, witness board, `/scripting/*`, `/compat/*`, `/lab/*`; plus the redirect aliases `/full`, `/minimal`, `/skeleton`, `/streams` (D25) | apollo |
| `starter-minimal.alexh95.com`, `starter-streams.alexh95.com` | witnesses | apollo |
| `starter-skeleton.alexh95.com` | the skeleton witness for two-host LAN perf runs; LAN-only forever | apollo |
| `odin-htmx.alexh95.com` | profile `skeleton`, the standing parity witness (Fly app name stays `odin-htmx-skeleton`: apps can't be renamed, 10 §0); it serves 6d37506 (v1.2.1, the `Content-Length` crash fix) from M0 (D1 step 1; 709bc94 until then) until the M3 exit (D1, X2; Q29) | Fly fra, Cloudflare-proxied |
| `htmx-odin-starter.alexh95.com` | 301 to `odin-htmx-starter.alexh95.com` (the brief's spelling) | apollo stack Caddy |

A **witness** is a hosted profile that proves a claim: `skeleton` (parity), `minimal` (the smallest build), `streams`
(the stream substrate without SQLite) and `lab` (the lab-only extensions, on an origin with no sessions, independent
of `full`'s own copy on `houston-lab`). Every witness gets the witness resource class of D38's budget table (X22).

**Rationale.** 08 §0 (any `*.alexh95.com` name needs only an NPM proxy host); 10 §4.4; origin isolation (D25).

**Rejected.** Houston at the starter root with the labs inside it (RF §4.5): eval-capable pages would share Houston's
origin and sessions. The name Patchbay (CF §1). Two-level names such as `minimal.odin-htmx-starter.alexh95.com`.

**Alex confirms:** answered 2026-10-25: Q2, as recommended plus `houston-lab.alexh95.com` (ANSWERS F2), which
carries every starter demo and lab page (ANSWERS round 3); Q3, Houston (ANSWERS #6).

### D3. Philosophy, tenets and the ledger

**Decision.** `PHILOSOPHY.md` keeps its thesis and its line; the line now reads: the shipped app depends on htmx (plus
the extensions a profile loads, from the same tarball under the same 0BSD licence), odin-http (our fork), optionally
SQLite, and optionally _hyperscript. An optional client runtime is still a dependency, and is counted as one (X1). The
"90% honestly" ledger counts everything that bends the philosophy, on purpose (8 rows: X1's seven, and row 8 with M14,
X42 and Q33):

1. **app.js**: small, vanilla, only what the server can't do.
2. **SQLite**: optional per profile; statically linked when present.
3. **_hyperscript 0.9.94**: optional per profile; core only; 39.7 KB br; pre-1.0 with a bus factor of about 1 (05 §0).
4. **The odin-http fork**: we now maintain a small diff, vendored in-tree at `app/vendor/odin-http/` and offered
   upstream (D11).
5. **ffmpeg as an offline tool** on the dev PC: never in a shipped binary or a published image (GPL, S21).
6. **`tools/bundle`**: a prepare-time Odin tool. It concatenates pinned, SHA-verified files in a fixed order and
   precompresses them with the `brotli` and `gzip` CLIs, because core Odin has no compressor (09 §0.8). It has no
   module graph, no transpile step and no npm, and costs nothing at runtime: it is a bundler only in the sense of
   concatenation. It is counted because the skeleton's prepare ran once, while this one reruns whenever CSS, `_hs` or
   extension files change (D19).
7. **`platform/guard`**: non-local control flow (setjmp/longjmp, formally UB, R4), confined to one package and the
   fork's callback entry points. It exists because Odin has no recover, so a single trap would otherwise kill every
   stream on every loop (13 §0). Pure-or-exit keeps it from hiding bugs: every trap is logged, and a dirty one exits
   with code 70 (D15).
8. **The device feed's plain-text stream** (M14, optional): a plain-text `text/event-stream` (unread count, presence,
   next event, bot health) for screens that can't render HTML; a non-HTML representation, still rendered by the
   server. It enters PHILOSOPHY.md in the change that lands the feed, and M14's exit gate checks it (X42; Q33: yes,
   2026-10-26; D44).

**What is *not* a runtime dependency** (X1):
- Each profile still runs bare (`./bin/<profile>`) with no proxy. The compose + stack-Caddy setup on apollo (D41) is
  hosting topology for running five profiles on one box, not something a profile needs.
- hx-pending's optimistic copies and hx-history-cache's sessionStorage snapshots are transient caches of
  server-rendered HTML. The server stays the source of truth.

**Never added unless Alex asks** (each enters the ledger in the same change if adopted): an xterm.js lab, a live-Alpine
page, hyperscript's `socket`/`eventsource`/`worker`/`component`, litestream, a PWA service worker, i18n catalogs, SSO
with spark, runtime disabling of compiled features.

**Houston's tenets** (PF §1.2, made generic):
1. Every feature answers a real household need, and every htmx extension and behaviour earns its place through one of
   those needs. An extension with no honest product use lives on a lab page, never on Houston's own origin; `full`
   serves those pages on its session-free second host, `houston-lab.alexh95.com` (D21, D25).
2. Reading works without JavaScript on public pages, login, the wiki, video and games: boosted links are real links
   and forms really post. JavaScript makes it live; it does not make it work (the progressive-enhancement rule, D22).
3. One binary, one SQLite file and one media volume per deployment.
4. Branding is configuration (`cmd/full/brand.odin`); packages and route prefixes stay generic (D9).

**Rationale.** PHILOSOPHY ("Naming the 10% is the point"); 05 §9; 10 §7.2, §8.

**Rejected.** PF §1.1's countable-dependencies claim that omitted the service worker and xterm.js it added; CF §1's
two-line growth that omitted ffmpeg.

**Alex confirms:** yes. PHILOSOPHY edits are on purpose; Q22 covers PWA and i18n (default stands (not
overridden)); row 8 follows Q33 (answered 2026-10-26: yes).

---

## B. Architecture and composition

### D4. Layering: platform layers and the feature package shape

**Decision.** The skeleton's strict layering (`SK/CLAUDE.md` "Architecture — strict layering") extends to two axes,
platform and features, and every rule below is a CI gate (`tools/check imports`), not a review convention.

Layers call each other directly, with qualified names, as the skeleton's `controllers → services → repository` do
(ANSWERS #1): no implementation is handed in from `cmd` as a value (D8). Each feature `f` is a set of packages, and
its stores live in their family's directory (LC §5):

| Package (Odin name) | Directory | Holds | May import | Never imports |
|---|---|---|---|---|
| models `f_models` | `app/features/f/models/` | types, enum label tables, the store contract's proc types | core, platform L1–L2 | anything of `f` |
| store `f_store_<family>` | `app/stores/<family>/f/` (`app/stores/sqlite/chat/` is `chat_store_sqlite`) | one store and its `contract.odin`; `migrations/` in the SQLite family | `f_models`, `platform/store*`, `platform/sqlite` and `platform/workers` (SQLite family) | `f`, `f_views`, `f_web`, other stores, any collection |
| domain `f` | `app/features/f/` | services (validation, rules, ownership checks) returning plain values and errors, never HTTP | `f_models`, `store:f` (its own store, through the family), `store:audit`, other features' **domain** packages it depends on, platform L1–L2 | odin-http, `platform/web`, `platform/html`, `platform/hub`, another feature's store |
| views `f_views` | `app/features/f/views/` | HTML builders over `^strings.Builder` | `f_models`, `f`, `platform/html` | stores, `f_web`, odin-http |
| switched impl `f_<axis>_<impl>` | `app/features/chat/transport_ws/`, `bot/backend_llama/`, `games/catalog_api/` … | one transport, backend or catalog, chosen by `f_web`'s switch (D8): its `NAME`, `EXTS` and handlers | `f`, `f_models`, `f_views`, platform L1–L3 | `f_web`, other impls |
| web `f_web` | `app/features/f/web/` | handlers; the package's `ROUTES` (its impls' rows too), `TOPICS`, `JOBS` and `EXTS`; `init`, `start`, `drain`; `home_card`; the axis switch; hub publishes | `f`, `f_models`, `f_views`, its own impls, `notify_web` (D6), `store:audit`, platform L1–L3 | any other web package, `platform/app`, odin-http (X30) |
| identity `accounts_identity_<x>`, `authz_anonymous` | `app/features/accounts/identity_*/`, `app/platform/authz/anonymous/` | `NAME`, `SETS_COOKIE`, `load_viewer`, `cli`, its `ROUTES` (`/login`, `/logout` …) | `accounts_models`, `store:audit`, platform L1–L3 (`anonymous`, in L2: L1–L2); `identity_accounts` also `accounts` and `accounts_views` | `accounts_web`, other identities, `platform/app`, any store but audit; `nick` and `envadmin` never reach SQLite (D18) |
| entry | `app/cmd/<profile>/` | the four hand-written profile files (D7) | everything | — |

`f_models` exists because the domain imports its store: a store that imported the domain would be an import cycle
(14 (1)), so the shared types and the contract types sit below both, as the skeleton's `models` does.

The rules that are not table rows:
- **Only the domain imports its store**, as "controllers never import repository" in the skeleton. The two other
  importers allowed are any domain, web or identity package for `store:audit` (D6) and a SQLite profile's `main` for
  `MIGRATIONS` (D16).
- **A web package reaches another feature four ways only**: a domain import for a hard dependency, `notify_web` (the
  one web-to-web edge), a hub topic named by string, and a plain link (D6).
- **Preferences travel on the `Viewer`** that the identity loads (theme, chat transport, mutes from `accounts_prefs`,
  X9), so chat, notify and `platform/html` read them without importing accounts (NEW).

Platform layers: **L1 bindings and leaf tables** `platform/sys` (with the thread-local counters the guard classifies
by, since `platform/sqlite` raises `in_sqlite`), `platform/sqlite` (core only), `platform/ext` (the
closed `Ext` enum and its tables, no imports, re-exported as `web.Ext`; X33), `platform/escape` (`w esc url_encode
json_esc`, one definition below `platform/markdown`, which renders at write time in L2; `platform/html` re-exports
it; M1); **L2 core** `platform/store` (with
`Search_Hit`, which domains return), `store/sqlite`, `store/memory`, `env` (the typed env table, D10), `authz`,
`authz/anonymous`, `obs`, `guard`, `workers`, `markdown`; **L3 I/O** `platform/web`, `stream`, `stream/client`, `hub`,
`html`, `client/hyperscript`, `client/vanilla`, `theme/full`, `theme/lite`; **L4** `platform/app` (`front`, boot, the
drain deadlines, the platform's CLI flags, and the per-host tables it holds after `app.serve`). `platform/app` stays at
the top of the platform (X30): it imports `identity:.` and L1–L3, and only `cmd/*` imports it; features never do,
which is why the env table moved to `platform/env`. `front` moved there from `platform/web` because the identity
packages import `platform/web` for their routes and cookies, so `platform/web` can't import `identity:` without a
cycle (NEW: not prototyped). Below L4, platform imports a feature only through a family: `platform/app` imports
`identity:`, whose members include feature packages, and `platform/html` imports `client:` and `theme:`, platform
packages that never import `platform/html`. Only `platform/web` imports odin-http. It re-exports `web.Request ::
http.Request` and `web.Response :: http.Response`, so no feature package ever imports odin-http. `platform/obs` (L2)
supplies the counters and health state, and `platform/web` serves `/metrics`, `/livez`, `/readyz` and `/healthz` from
it. `tools/check imports` enforces all of this, the collection rules included (D39; X30).

The request path stays the skeleton's: route → `f_web` handler → `f` service → `store:<f>` (the build's store family)
→ `f_views` render → respond (PHILOSOPHY "Legibility"). From the profile's `routes.odin` a reader follows a request to
its SQL with go-to-definition alone, with no hop added and nothing looked up at run time once the router has matched
the row (LC §2). Publishing to the hub happens in `web` after the service returns, so services stay pure and views
stay the only place HTML is built.

Files by convention: `features/f/static/` (`f.css`, `f._hs`; not a package);
`app/stores/sqlite/f/migrations/NNNN_name.sql`; `features/f/storetest/` (the conformance suite, D37);
`features/f/README.md` with fixed headings (What, Routes, Env, Data, Implementations, Limits, Tests, Audited), from
which `docs/CATALOG.md` is generated.

**Rationale.** CF §3.1: with one package per feature the skeleton's layer rules become per-file conventions, because
all files of a package see each other (09 §4.4). The skeleton's direction rule was review-only (01 §1). ANSWERS #1
(direct calls, no DI); 14 (1) (the import cycle; unique package names); LC §2, §5.

**Rejected.** RF §3.1's feature web packages holding views ("views never see HTTP" becomes a convention). PF §3.1's
domain-plus-views package ("services never render" becomes review-only). Stores inside the feature directory that
import the domain (an import cycle, 14 (1)). Implementation values handed to `f_web` from `cmd` (ANSWERS #1).

**Alex confirms:** answered 2026-10-25: separate packages per layer, calling each other directly, with no dependency
injection (ANSWERS #1).

### D5. The feature contract

**Decision.** There is no `Feature` struct and no `register()` (ANSWERS #1). A feature's web package keeps its rows
in package-level tables next to its handlers (slice literals inside a proc point into its stack frame, 09 §4.4), and
the profile's `routes.odin` mounts them, one line per package and host (D7; LC §6, §8):

- **`ROUTES`**, `[?]web.Route`: its own rows and its switched impls' rows (the chat transports' `/ws`, `/since`,
  `/parts`). A root row (`GET /`) is never in a package's table: the profile writes it (D9);
- **`TOPICS`**, `[?]hub.Topic` (D13), and **`JOBS`**, `[?]workers.Job`: job ids carry the feature prefix, as topics
  do (D36);
- **`EXTS`** on one line (D19), and the procs `main` calls or lists: `init` (reads its env rows from `platform/env`,
  declares its limits to obs, starts nothing), `start` and `drain`, and, where the feature has them, `home_card` and
  its domain's `search`, which `main` lists in `HOME_CARDS` and `FIND_SOURCES` (D6).

The feature's name, its directory under `features/`, stays its namespace: log `mod=`, metric prefix `app_chat_`, env
prefix `CHAT_`, e2e tag `@chat`, table prefix `chat_`, topic and job prefix `chat.`.

```odin
Route :: struct {
	method:   http.Method,
	pattern:  string,                     // Lua pattern inside the feature's prefix; route id = "<METHOD> <pattern>"
	handler:  proc(req: ^web.Request, res: ^web.Response),   // odin-http's types, re-exported (X30)
	perm:     authz.Perm,                 // .Public = no check
	flags:    bit_set[web.Route_Flag],    // .Step_Up .Lan_Only .Private .Fragment .Stream .Frame_Games .Media .Nonce_Csp
	                                      // .Lab_Host (a mount rule, D25)
	body_cap: int,                        // 0 = MAX_BODY, 64 KiB (SK/app/src/controllers/middleware.odin:36)
}

// app.Host: one origin a profile serves, in the profile's HOSTS (LC §6)
Host :: struct {
	name:     string,                     // "main", "lab": the log and metrics label
	site_env: string,                     // "SITE_URL", "SITE_URL_LAB": the env var that names its origin
	identity: bool,                       // front runs the identity: family here; false = every viewer is the Guest
	routes:   [][]web.Route,              // the mounted tables, plus the profile's own rows
	topics:   [][]hub.Topic,
	nav:      []html.Nav_Item,
}

// hub.Topic row:   {"chat.room", .Queue, 256, true, subscribe_room, nil}   family, policy, ring, persisted, subscribe, deliver
// workers.Job row: {"notify.prune", .Daily, prune}                         id, schedule, run
```

LC §16's prototype host held its routes only; the topics and nav per host are NEW.

**Boot checks**, in `app.check`, per host, and in CI through `app/cmd/<p>/routes_test.odin` (each fatal with a
message; LC §11):
1. a duplicate route id on one host, or a row with no handler;
2. a row whose prefix or flags need a perm (`/admin/*`, `.Step_Up`, `.Lan_Only`) but that declares `.Public` (X4);
3. not exactly one root row (`GET /`) on a host (D9);
4. a `.Lab_Host` row on a host where a cookie-setting identity runs; a row with any perm but `.Public` on a host with
   no identity; a second host whose env var is unset or names `SITE_URL`'s host (D25). `identity.SETS_COOKIE` is a
   constant, but the env is read at boot, so this check stays at boot;
5. a router key fed by two mounted tables on one host (NEW);
6. `main`'s `BUNDLE_EXTS` differs from the embedded bundle's `/* exts: … */` header ("run prepare"; D19);
7. a nav href with no GET route on its host;
8. a topic family mounted twice on a host, or a persisted topic with no `subscribe`; a job id mounted twice.

LC §16 (`$L2 b`) prototyped 1–4: a deliberately broken profile trips 1, 3 and 4 (8 problems at boot, 7 under
`odin test`), and `odin test` passes for `skeleton` and `full`. The same `Perm` member listed twice in `ROLE_PERMS`
for one role is a compile-time impossibility (a `bit_set`), so it is not a boot check (X4). An unknown env var inside
a mounted prefix is a warning, given after the `init` calls have recorded their rows.

**Static checks**, in `tools/check` over `core:odin/parser`, for what the binary can't see (it can't tell which
feature owns a profile row's handler, or which table a row came from; 14 (3)): prefix ownership per host (D9), no
root row inside a package's `ROUTES`, and mount completeness (`tools/check profile`: every imported feature package
mounted, no orphan `ROUTES`; D39). `requires` goes: a build that reaches a missing family member fails to compile, and
the generator refuses first (D18, D26).

**Derived, never declared twice**: `robots.txt` Disallow from `.Fragment` routes (the literal prefix up to the first
pattern character), per host; the sitemap from `NAV`, per host (as today, `SK/CLAUDE.md` "Crawlers"); `rbac.spec`
from `bin --routes` (every route × role × host, D37); route coverage from route ids; the CSP and cache class from the
flags; the htmx-config allowlist from the bundle's extensions; dependencies from import lines; the README env tables
from `bin --limits --json`, the rows each `init` recorded.

**Rationale.** RF §3.9 (boot checks turn granularity mistakes into loud failures, the skeleton's "drift fails loudly",
`SK/tools/init/plan.odin:228-239`); PF §8.3 (one definition per route); CF §4.1 (namespacing by feature name);
ANSWERS #1 and round 3 (per-package tables, mounted by hand-written profile files); 14 (3); LC §6, §11.

**Rejected.** RF §3.9's parallel `perms`, `classes` and `body_caps` tables keyed by route or prefix. CF §4.1's
manifest with string perms and open registries. `@(init)` self-registration (09 §4.3: contextless, static storage
only). The `Feature` struct with `register()` calls (a registration framework, ANSWERS #1). One flat route literal
per profile, exactly the skeleton's shape: every row would be repeated in every profile that mounts it. Root rows
inside a package's `ROUTES`: a package couldn't then sit at `/` in one profile and `/dashboard` in another (LC §13).

**Alex confirms:** answered 2026-10-25: a `ROUTES` table per package, mounted one line per package by the profile's
hand-written `routes.odin` (ANSWERS round 3); the checks run per host because `full` has two (ANSWERS F2).

### D6. Cross-feature seams

**Decision.** Features meet only through these, each justified in CLAUDE.md, and every one is a direct call or a
dispatch-table row (ANSWERS #1, round 3; LC §9):

- **Notify by direct import.** A producer's web package imports `notify_web` and calls `notify_web.send(user, kind, ref,
  html)`, which stores the item through notify's domain and publishes the bell on `notify.user:<uid>`. Every producer
  does this (chat, lists, calendar, polls, guestbook, bot, jobs): round 3 named chat, and the other producers follow the
  same rule, so notify is a hard dependency of each, and the generator closes a selection over it (D26). It is the one
  web-to-web import, and `tools/check imports` allows no other. `kind` is a namespaced string (`"chat.mention"`), so
  notify never names a producer's kinds; mutes per kind keep the same strings.
- **Audit is a store.** A package that audits imports `audit_store "store:audit"` and calls
  `audit_store.append(actor, action, target, reason, meta)`. The SQLite family writes an `audit_log` row; the memory
  family writes one `mod=audit` log line (LC §16, `$L2 a`). It is the one store any domain, web or identity package
  may import, because an append-only log has no rules for a domain to add. The `audit` feature's page,
  `/admin/audit`, reads through audit's domain and is mounted only in SQLite profiles.
- **Topic rows for the bot's room mode.** `chat_web` publishes a message that mentions the bot on `bot.ask:<room>`,
  by name. `bot_web.TOPICS` holds the static row `{"bot.ask", .Queue, 64, false, nil, room_ask}`, whose `deliver` proc
  the hub runs once per publish (D13). `room_ask` starts the backend and streams upserts of `#m-<id>` to
  `chat.room:<room>`; the finished answer goes back on `chat.reply:<room>`, chat's own static row, which stores it as
  a message from the bot and publishes the persisted bubble. Neither feature imports the other. Without bot, nothing
  mounts `bot.ask`, so the publish reaches no row and is dropped and counted; `tools/check topics` requires every
  family a package publishes to by name to be declared by some package, so a typo fails CI (NEW: the `deliver` field
  and the check are not prototyped). ANSWERS round 3 says "a hub topic with a static `TOPICS` row"; storing the answer
  without bot importing chat takes one row each way, so room mode uses **two static rows**: `bot.ask`, consumed by
  bot, and `chat.reply`, consumed by chat. Each feature works alone (X37).
- **Tables in the profile, read by one consumer each**: `NAV` and `LAB_NAV` (`brand.odin`; the layout), `HOME_CARDS`
  (`main`; home's Today page, in the table's order) and `FIND_SOURCES` (`main`; find, each row a domain's `search`
  filling `store.Search_Hit` rows), the mounted `TOPICS` (the hub) and `JOBS` (`platform/workers`). `home_web` and
  `find_web` import no other feature.
- **Obs pushes for health and limits**: each feature pushes its health, metrics and limits to `platform/obs` as data;
  `status`, `modules` and `/readyz` read obs, `platform/env` and the tables `platform/app` holds, and import no
  feature. The bot pushes its live default backend there, and `modules` links to `/admin/bot` (D31).
- **Domain imports for hard dependencies** (dashboard → contacts; video → uploads). The import lines are the
  dependency graph (09 §4.6).
- **Hub topics named by string** for genuine broadcasts (D13).
- **Plain links for UI composition**: "Invite crew" on a game page links to `/chat/r/<slug>?draft=<text>`; no code
  coupling.

There are no open plugin registries (no `Admin_Panel`, `Probe`, `Notifier` list or `On_User_Deleted` hook, CF §4.3),
and no subscription made at run time. There are **no foreign keys across features**: a feature stores user ids as
plain integers plus an `author_name` snapshot taken at write time (names change rarely and rolling retention ages old
snapshots out), and deleting an account is a soft disable that keeps the row, so nothing cascades across features.

**Rationale.** RF §3.1 (optional features compose without a dependency graph between them); CF §4.2 (any combination
migrates); the philosophy judge (composition machinery lighter than the features); ANSWERS #1 and round 3; 14 (5);
LC §9.

**Rejected.** CF §4.3's eleven registries; PF §3.1's catch-all `app.Hooks`; RF §7.1's foreign keys into `users` from
other features (cascades break optional accounts). `platform/ports`, a struct of three proc fields installed at
registration (dependency injection, ANSWERS #1). Null-object seam packages chosen by the build (LC §13): no seam is
left to fill. A run-time `hub.subscribe` in `main` for room mode (14 (5) (b): the observer pattern; a static row is a
dispatch table). Bot importing chat's domain for room mode: any bot selection would pull chat in.

**Alex confirms:** answered 2026-10-25: notify by direct import, audit through `store:audit`, room mode over a
static topic row (ANSWERS #1, round 3). X37 settles that row as two, `bot.ask` and `chat.reply`, which is what round 3
needs in practice.

### D7. The composition root

**Decision.** Each profile is four hand-written files in `app/cmd/<profile>/`, as `SK/app/src/main.odin` and
`SK/app/src/routes.odin` are (ANSWERS round 3; LC §6). Their import lines are the feature selection:
- **`routes.odin`**: the host tables. One mount line per package (`chat_web.ROUTES[:]`), the platform's
  `web.ROUTES` (the main host's probes, `/metrics`, the sitemap) and `web.PUBLIC_ROUTES` (every host's static assets,
  `/events`, `robots.txt`, `favicon.ico`, `/licenses`, `/csp-report`), and the profile's own rows: the root, and any
  page placed outside its package's table (`/dashboard` on houston-lab, D25). Then `TOPICS` and `JOBS` mounted the
  same way, and `HOSTS`, one `app.Host` per origin (D5). Tables are package-level; boot keys every row by prefix
  (D9), so order matters only inside a prefix, and `bin --routes` prints each host's flat table. Each mount is an
  `app.Mount{feature, rows}` (M1), so the build can say which features it mounts (`bin --features`).
- **`main.odin`**: the boot sequence as plain calls. `app.boot(<profile>)`; `identity.cli()`; each feature's `init`
  in dependency order (notify before its producers); `home_web.init(HOME_CARDS[:])` and
  `find_web.init(FIND_SOURCES[:])`; `app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS)` (D5's boot checks; `--features`,
  `--routes` and `--limits` answer here); in a SQLite profile `store_sqlite.open()` and one
  `store_sqlite.migrate("<f>", <f>_store.MIGRATIONS[:])` per store in dependency order (D16); `app.serve(HOSTS[:],
  JOBS[:], &BRAND)`; the `start` calls; `app.wait()`; the `drain` calls in the order written; `app.shutdown()`; in a
  SQLite profile `store_sqlite.close()`; `app.exit()` (PLAN
  §8.6, §8.7). The platform keeps the deadlines; `main` shows who drains what. It also holds `HOME_CARDS`,
  `FIND_SOURCES` and `BUNDLE_EXTS` (D6, D19).
- **`brand.odin`**: `BRAND`, `NAV` per host (`LAB_NAV` in `full`), nav labels and order, the default scheme and copy.
  Boot checks that every nav href is a GET route on its host.
- **`routes_test.odin`**: runs the boot checks under `CMD=test ./build.sh <p>`.

**The build line** is spelled in one place, `build.{sh,bat} <profile>` at the repo root, with every path relative to
it: one `case` row per profile naming its four families (D8), then `odin ${CMD:-build} app/cmd/<p>
-collection:store=app/stores/<family> -collection:identity=app/<identity dir> -collection:client=… -collection:theme=…
-vet -strict-style -warnings-as-errors "$@"` (and, from M1, the further vet flags of §19.2.4). `run.*`, `prepare.*`, CI, the Dockerfile, the e2e global setup,
`load-tests/run.sh`, `tools/watch` and `tools/init --verify` all call it. A bare `odin build app/cmd/<p>` fails with
"Unknown library collection: 'store'" (and the same for the other three; LC §16), and Odin has no response files
("Invalid flag: @mem.rsp", 14 (1)), so the script is the only home the flags can have. `ols.json` at the repo root
pins the four collections to `full`'s members, so the editor follows every call into one family (OLS's
`collections` are top-level; not yet tried in an editor). **`full-vanilla` has no directory of its own**: it is
`app/cmd/full` built with `client=vanilla` (D24), so the two can't drift apart.

**The generator writes and edits these files** (D26): it writes all four, `build.*` and `ols.json` for a new
project, and edits them in place when a feature is added or removed. CI's generator job runs `tools/check profile` on
every committed profile (D39) instead of an emitted-file byte comparison: every imported feature package mounted (its
`ROUTES` on some host, its `TOPICS` and `JOBS` mounted, its `init` called), no orphan `ROUTES`, and a `migrate` line
for every store with `MIGRATIONS` that a SQLite build reaches (LC §16 prototyped the mount check; the orphan and
`migrate` parts are NEW). A hand edit that keeps the profile consistent passes; one that leaves a package unmounted
fails.

**Rationale.** S17 (as refined, §0.2); ANSWERS #1 and round 3; `SK/app/src/{main,routes}.odin`; 14 (1), (3); LC §3,
§6, §12 (the four flags cost nothing measurable: 138 ms to check `streams` or `full`, 277 and 281 ms to build). 09 §5's
flag-free build is overturned (§0.2).

**Rejected.** CF §4.6's `profiles.odin` table with emitter-generated `cmd/*` (a second definition of each profile and
another build step); `#config`/`when` feature flags (09 §4.3, 14 (4): false branches are never type-checked and fight
`-vet`, and a value typo silently takes the `else` branch); one binary with route-prefixed profiles (D25). The
previous form of this decision, `register()` calls with implementation values and one options literal per feature,
checked by `tools/init --emit --like` (ANSWERS #1). A `sel:` collection per profile with generated alias packages
(a hop per aliased call, 14–30 generated files per profile, and aliases can't name a package variable, 14 (1c)); a
`SELECTION` mini-language with generated `main.odin` and `routes.odin` (a second syntax, and a generator that is
load-bearing for every profile); a collection per axis per feature (a flag per axis on every command, with no family
rule to keep them consistent) (LC §13).

**Alex confirms:** answered 2026-10-25: the hand-written profile files and the four families on one build line
(ANSWERS #1, round 3).

### D8. Implementation axes and when each is chosen

**Decision.** Which implementation runs is never a value passed around at run time (ANSWERS #1). It is one of three
things (LC §1):
- **a family collection on the build line**, when the choice keeps a C library off the linker or swaps a whole
  platform layer: the store, the identity, the client and the theme;
- **a hand-written `switch` over an enum, with a direct call in each case**, when it varies per request: the chat
  transport and the bot backend;
- **an env value read at boot, then the same kind of switch**, when both members are pure Odin and one serves the
  whole process: the games catalog.

A proc value is stored in only two kinds of place: **dispatch tables** (route, topic and job rows, `HOME_CARDS` and
`FIND_SOURCES`; D5, D6) and **continuations** that name the caller's own next step (nbio completions, the writer
task's commit, timers, jobs, the bot's token sink). Both say *when* code runs, never *which* implementation runs.

**The four families** (the flags live only in `build.{sh,bat}`, D7):

| Family | Flag | Members | Imported by | Contract |
|---|---|---|---|---|
| store | `-collection:store=app/stores/<sqlite\|memory>` | one directory per family, one package per feature: `app/stores/sqlite/chat/` is `chat_store_sqlite` | the feature's domain, as `store:<f>`; `store:audit` from any domain, web or identity package (D6); a SQLite profile's `main`, for `MIGRATIONS` | proc types in `features/<f>/models`, one typed constant per proc in each store's `contract.odin` |
| identity | `-collection:identity=<dir>` | `features/accounts/identity_{accounts,envadmin,nick}/`, `platform/authz/anonymous/` | `platform/app` (`front`) as `identity:.`; the profile's `routes.odin` for `identity.ROUTES`; `main` for `identity.cli` | `authz.Load_Viewer` |
| client | `-collection:client=<dir>` | `platform/client/{hyperscript,vanilla}/` | `platform/html` (`behave`, D22) | none: CI builds both members (`full` and `full-vanilla`) at every call site |
| theme | `-collection:theme=<dir>` | `platform/theme/{full,lite}/` | `platform/html` (D23) | none: the hosted profiles build both members |

- **Contracts are typed constants**, `_ : m.Store_Insert : insert`: pure type checking with no code. A drifted store
  fails in its own package, built or not: "Cannot assign 'insert' of type 'proc(^Message, u64) -> Error' to
  'Store_Insert'" (LC §16). `#assert(type_of(insert) == T)` can't do this job: it is false even for an exact match
  (14 (1), 14 critic).
- **Package names are unique** per program (14 (1)), so `features/<f>/storetest` imports both stores into one test
  binary (D37).
- **A feature with no member in a family has no directory there**, so a build that reaches it fails to compile:
  "Path does not exist: store:contacts" (LC §16). That is D18's refusal, made by the compiler; the generator refuses
  first, with advice (D26). SQLite only: accounts (so `identity_accounts`), contacts and term.
- **One store family per build.** Every feature in a profile uses the same family, so the per-feature store choice
  and `STORE` at boot go (D10); every hosted profile was all-SQLite or all-memory already (D24).

**Every axis:**

| Axis | Members | Chosen | How |
|---|---|---|---|
| Store (notes, chat, notify, polls, lists, calendar, guestbook, jobs, bot conversations, uploads' session rows: lost on restart in the memory family, so resumable uploads need SQLite, X13) | `app/stores/{sqlite,memory}/<f>/` | build | the store family |
| Identity | `accounts` (SQLite), `envadmin` (one env-provisioned admin, signed cookie), `nick` (signed nickname cookie, role User), `anonymous` (the default) | build | the identity family |
| Client behaviours | `client/hyperscript`, `client/vanilla` | build, one per profile | the client family |
| Theme | `theme/full` (6 styles × 24 schemes), `theme/lite` (one style, two schemes) | build | the theme family |
| Search, wiki source, video catalog | FTS5 or a `contains_ci` scan; `source_files` (memory: the read-only embedded docs) or editable pages (SQLite); `catalog_file` (memory: the manifest scan) or SQLite metadata | build | they follow the store family; the old member names survive as each store's `IMPL` constant |
| Games catalog | `features/games/catalog_{static,api}` | per process: `api` when `GAMES_API_URL` is set, `static` otherwise (`GAMES_CATALOG` still overrides the static JSON) | `games_web` reads it at `init`, then a `switch`; both pure Odin and both linked |
| Terminal mode | line, PTY | per device row | a column of the row, switched in `term_web` |
| **Chat transport** | `features/chat/transport_{ws,sse,poll,multipart}` | **per request**: the user's preference (Houston: `accounts_prefs`, X9; elsewhere a cookie), `?transport=` in tests, default `CHAT_TRANSPORT` | one hand-written `switch` in `chat_web`, which imports all four; every chat profile links and ships all four |
| **Bot delivery** | POST → SSE, POST → multipart, room (over `bot.ask` and `chat.reply`, D6) | **per request** (a form choice): the same backend stream rendered for another transport | a local `switch` in `bot_web` |
| **Ops refresh** | SSE push, ptag poll, multipart slow panels | **per request** (`?mode=`) | a local `switch` in `ops_web` |
| **Bot backend** | `features/bot/backend_{mock,llama}` | **per request** among the healthy ones: guests always get mock; members choose when both are healthy; the default is `BOT_BACKEND`, which an admin can change at run time on `/admin/bot` (in memory only, audited, reset on restart) | one `switch` in `bot_web` (`health`, `start`, `cancel`); both linked, since llama's client is `platform/stream/client`, pure Odin |

The chat switch, beside the routes in `chat_web` (LC §4):

```odin
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

**The switching rule** is unchanged: per-request switching exists only on transport axes (how the same content
travels) and on the bot backend, the axes that are the showcase's point. Every response from a feature with a
runtime-switched axis carries a header such as `x-impl: chat.transport=sse` (or `bot.backend=mock`) and its
access-log line carries `impl=`, so what served a request is always visible.

**The switch's cost** (14 (2): 200M calls at `-o:speed`, in ns per call): a direct call 1.09–1.11; enum + switch
1.53–1.56 with the same transport every call and 6.31–6.62 with a random mix of four; the proc-field table it
replaces 1.33–1.38 and 5.20–5.39. So the switch costs 0.2–1.2 ns more than a table, against 0.5–15 µs for a store
call or a socket write, and the IR holds four direct calls and no indirect one.

**Rationale.** S17 (as refined, §0.2); PF §4.3; philosophy judge must-fix 16; ANSWERS #1 and round 3; 14 (1), (2);
LC §3, §4.

**Rejected.** CF §4.5's per-request cookie switching on every runtime axis and Patch-panel switches persisted in
`app_settings`. RF §4.2's `CLIENT_BEHAVIORS` boot switch that embeds both client runtimes in `full`. Proc-field
vtables handed in from `cmd` (dependency injection, ANSWERS #1). Generated per-profile dispatchers over each
profile's own transport set (`sel:chat_transports`): they kept X29's lean chat bundles at the cost of a generated
package per runtime axis, and a hand-written switch over all four is simpler (ANSWERS round 3). A build-time choice
for the games catalog and the bot backend: both members are pure Odin, so there is nothing to keep off the linker.
`STORE=sqlite|memory` at boot: no build links both families (LC §13).

**Alex confirms:** answered 2026-10-25: the four families, the chat and bot switches, every chat profile shipping all
four transports, and the bot default on `/admin/bot` (ANSWERS #1, round 3).

### D9. Router and route prefixes

**Decision.** Dispatch by prefix first (S7): **one prefix map per host**, built at boot from that host's mounted
tables (D5, D25), from the first one or two path segments to the owning feature's rows, longest key first
(`/ui/ping` → dashboard, `/ui` → gallery; `/admin/<f>` and `/api/<f>` are two-segment keys). `front` picks the host
by `Host` and routes only within its map (D25). odin-http's anchored Lua patterns run only inside the feature: at most
about 20 routes × 140 ns ≈ 2.8 µs worst case, against 22.4 µs for a flat 150-route table (09 §4.4). Static assets
match before anything else. The 405-with-`Allow` and site-404 fallback keep the skeleton's behaviour (01 §2).

**Prefix rule.** A feature owns `/<name>`, `/admin/<name>` and `/api/<name>`, on whichever host mounts it: the rule is
per feature, so it reads the same on every host (`/chat` is chat's wherever it is mounted), and one package may be
mounted on both hosts (the platform's public rows are). On one host a router key belongs to one feature. Exceptions
are listed, with the reason, in the feature's README:
- **one root per host**: each host's table has exactly one `GET /` row, written in the profile's `routes.odin`, never
  in a package's `ROUTES` (D5). The root is `home` in `minimal`, `streams` and on `full`'s main host; the dashboard's
  page in `skeleton`; `landing` in `lab` and on `full`'s lab host. So one package's page can sit at `/` in one profile
  and elsewhere in another: the skeleton's dashboard is the root in `skeleton` and `/dashboard` on houston-lab, inside
  dashboard's own `/dashboard` prefix (LC §16). This replaces "`home`, `dashboard` and `landing` are mutually
  exclusive": `full` has `home` on one host and `landing` on the other, and the generator refuses two roots on one
  host (X5, X28; D26);
- `accounts` owns `/login /logout /register /invite /account` (conventional URLs), mounted from the identity's
  `ROUTES`;
- `video` owns `/media` (content-addressed files);
- the skeleton features keep the skeleton's exact URLs (the dashboard's page at `/` as `skeleton`'s root row, and
  `/ui/ping`; contacts `/data /contacts /search /api/search`; gallery `/components /forms /ui /validate`; about
  `/about`; `SK/app/src/routes.odin`) because parity needs them byte-identical (X5);
- the platform owns `/events /static /healthz /livez /readyz /metrics /robots.txt /sitemap.xml /favicon.ico
  /BingSiteAuth.xml /<indexnow-key>.txt /licenses /csp-report`: `web.ROUTES` on a site's main host, and
  `web.PUBLIC_ROUTES` (`/static`, `/events`, `/robots.txt`, `/favicon.ico`, `/licenses`, `/csp-report`) on every
  host (D7).

**Ownership is checked statically, per host**: `tools/check routes` keys rows as boot does and takes each row's owner
from its package's import path, or, for a profile row, from its handler's (LC §16: `prefix "/chat" claimed by
dashboard … and chat`). Boot refuses a router key fed by two mounted tables on one host (D5, NEW), but can't tell
which feature a profile row's handler belongs to, so a build that skipped CI could boot with a row outside its
feature's prefixes (14 (3); LC §12 item 9).

Global search is the **`find`** feature at `/find`, because the skeleton's `/search` is the contacts active-search
fragment (`SK/app/src/routes.odin:42`) that the k6 search scenario hits. Product names (Comms, Capcom, Logbook …) are
nav labels from `brand.odin`, never prefixes.

**Rejected.** PF §4.2's branded prefixes (`/capcom`, `/log`, `/control/console`); a global search at `/search` that
collides with contacts (PF §4.2, CF §4.4). One map for all of a profile's hosts with a `.Lab_Host` filter in `front`:
per-host tables say which rows answer where (D25; LC §13).

**Alex confirms:** no.

### D10. Configuration

**Decision.** One typed env table in `platform/env` (L2), so features read their own rows without importing
`platform/app` (D4). Each row is `{name, type, default, secret, doc}`; types are int, bool, duration (`7d`), size
(`16MiB`), CIDR list, enum, path and secret. `app.boot` parses the platform's rows; each feature's `init` reads and
records its own rows, and starts nothing (D7). After the `init` calls, `app.check` answers `--features`, `--routes`
and `--limits` (printed with secrets masked) and warns on an unknown variable inside a mounted prefix (D5). The rows
are listed on `/admin/modules`, and the README env tables are generated from `bin --limits --json`. `*_FILE` variants
read compose secrets (08 §5.7).

**CLI flags** are answered by the package that owns them, called from `main` (LC §5): `platform/app` answers only
the platform's own, `--features --routes --limits --healthcheck --worker`; `--backup` and `--adopt-profile` are
answered by `store_sqlite.open`; `--hash-password` by `identity.cli` in the identities that check an argon2id hash
(`accounts`, `envadmin`; `nick`'s and `anonymous`'s `cli` answer nothing). So a profile without SQLite or a hashing
identity links neither for a flag.

- **Platform** (no prefix; the skeleton's names keep their meaning, `SK/CLAUDE.md` env table): `PORT BIND_ALL DB_PATH
  SEED SITE_URL THREADS LOG_LEVEL`, plus `MEMMODE` (single|ephemeral), `MAX_CONNS` (fd soft limit − 64),
  `HEADER_TIMEOUT_MS` 10000, `IDLE_TIMEOUT_MS` 75000, `BODY_TIMEOUT_MS` 30000, `DRAIN_DEADLINE_MS` 5000,
  `TRUST_PROXY` (**empty = trust no peer**), `LAN_CIDRS` 192.168.0.0/16, `METRICS_TOKEN_FILE`, `STREAM_HEARTBEAT_S`
  20, `STREAM_MAX_QUEUED` 256KiB, `STREAMS_PER_USER` 8, `STREAMS_PER_CLIENT` 16, `STREAMS_TOTAL` 8192, `HUB_RING` 256,
  `SESSION_KEY_FILE`, `COOKIE_SECURE` auto, `SITE_URL_LAB` (unset = no lab host: the origin of `HOSTS`' second host,
  D25's session-free origin, whose host, without the port, `front` matches against `Host`; like `SITE_URL` it
  defaults from brand.odin, and only `cmd/full/brand.odin` names one, `https://houston-lab.alexh95.com`; NEW).
  `STORE` (sqlite|memory) is deleted: no build links both store families (D8).
- **Features** (prefix = feature name): `CHAT_ROOM_CAP` 500, `CHAT_ROOM_MAX_AGE` 7d, `CHAT_DM_CAP` 1000,
  `CHAT_DM_MAX_AGE` 30d, `CHAT_ANNOUNCE_CAP` 100, `CHAT_ANNOUNCE_MAX_AGE` 365d, `CHAT_RING_BYTES` 16MiB,
  `CHAT_TRANSPORT`; `BOT_BACKEND` mock, `BOT_LLAMA_URL` (required for llama, never assumed: 07 §2.2; on apollo
  `http://<APOLLO_LAN_IP>:<LLAMA_PORT>`, D31), `BOT_LLAMA_KEY_FILE`, `BOT_SEED`, `BOT_DELAY_MS`, `BOT_CONCURRENCY`;
  `ACCOUNTS_REGISTRATION` invite, `ACCOUNTS_ADMIN_HASH`, `ACCOUNTS_ARGON_THREADS` 2, `ACCOUNTS_NICK_FROM` lan (X7),
  `ACCOUNTS_NICK_ADMIN_CIDRS` none (ANSWERS round 9);
  `GAMES_URL`, `GAMES_API_URL`, `GAMES_CATALOG`; `VIDEO_DIR` /data/media, `VIDEO_SIGN_KEY_FILE`, `VIDEO_CDN_URL`;
  `TERM_IDLE` 15m; `STATUS_PROBES`; `GUESTBOOK_OPEN` 1; `NOTES_CAP` 500 and `CONTACTS_CAP` 2000 (the row caps on
  houston-lab's demo data, D25, X38; they apply only where `full` mounts notes and contacts on its lab host, and the
  `skeleton` profile stays uncapped). `GAMES_API_URL` also chooses the games catalog: `api` when set, `static`
  otherwise (D8, D34), so the catalog needs no env var of its own.
- **Build-time `-define`** only for `VERSION`, `TEST_ROUTES` (crash-drill routes; release images assert they answer
  404) and `PROFILE` (spall) (S17).

Compose pins the stack network's subnet and gives `caddy` a fixed `ipv4_address`, and every app container's
`TRUST_PROXY` is that one address, as a /32, so the app trusts the stack Caddy alone (X31, X43). Not the subnet: the
gateway that Caddy trusts (D41, X39) sits inside it, so a process on apollo's host that connected to an app container
directly would arrive from the gateway and be trusted for `X-Real-IP`. App containers publish no ports, and only Caddy
publishes `:8120`. Nothing trusts every private range by default.

The Pi agent (`cmd/term-agent`, not a profile) reads its own three variables from an `EnvironmentFile`:
`TERM_AGENT_URL`, `TERM_AGENT_HOST` and `TERM_AGENT_TOKEN_FILE` (D32, X15).

**Rejected.** CF §3.7's `TRUST_PROXY` default of all RFC 1918 ranges: any LAN host could then spoof `X-Real-IP` and
dodge rate limits, which is the spark `client_address` bug S6 lists (06 §3.1). RF §3.8's `LAN_ONLY_PREFIXES` env (a
second definition): LAN-only is the route flag `.Lan_Only`. The env table in `platform/app` (features would then
import L4). `STORE` at boot (LC §13).

**Alex confirms:** no.

---

## C. Server substrate

### D11. The odin-http fork

**Decision.** The fork is **vendored in-tree at `app/vendor/odin-http/`** (ANSWERS #7, F3), replacing the skeleton's
`app/odin-http` submodule of laytan/odin-http: laytan's fac113f plus F-1..F-13, with
`app/vendor/odin-http/UPSTREAM.md` naming the base commit and listing each F-change and the files it touches. There is
no separate GitHub repo. It is a small, generic diff, offered upstream to laytan after M2 (Q4) through a GitHub fork
made at that time. Protocol code stays in the starter (S1). The checklist (RF §3.3, from 03 §11 and 13 §1.4):

| # | Change | Why | Evidence |
|---|---|---|---|
| F-1 | `Streaming` state, `Connection.stream`, `stream.odin` (`stream_begin/write/end/queued/loop`, `on_data`, `on_close`, `on_shutdown`) | SSE, WS and multipart on the HTTP port (S2) | 03 §10.1 (29/29 contract tests on Linux) |
| F-2 | HTTP/1.0 fallback: a close-delimited body instead of chunked | nginx without "Websockets Support" talks 1.0 upstream | 03 §10.5 |
| F-3 | `stream_sendfile(s, fd, off, len)` on `nbio.sendfile` | video Range without buffering the file | 07 §0.2 (256 MiB at 5.1 MB peak) |
| F-4 | `Server_Opts.on_thread_init` / `on_thread_shutdown` | hub inbox registration, heartbeat and watchdog timers, timer cancellation at drain | 03 §11 item 2; 13 §4.2 step 6 |
| F-5 | `Server_Opts.invoke`: every nbio completion callback the fork owns (accept, scanner recv, body read, dispatch, send completion, stream ops, sendfile) runs through this wrapper, where `guard_call` sits | F1-class crashes inside odin-http escape an app-level guard | 13 §1.3 (F1 row) |
| F-6 | `_body_length` rejects `Content-Length` < 0, overflow and non-digits with 400 | F1: one unauthenticated packet aborts the process. The skeleton's v1.2.1 (6d37506) works around it in `front`, but `OPTIONS *` is still answered by odin-http itself, so the fix belongs at the source | 02 §1.2 (`SK/app/odin-http/body.odin:119-148`); 6d37506's TODO.md |
| F-7 | Timeouts: header read 10 s, idle keep-alive 75 s, body read 30 s, as per-op nbio timeouts on the scanner's recv | slowloris; shutdown hangs | 02 F5; `scanner.odin:204` |
| F-8 | `max_connections` (fd soft limit − 64) answering 503; accept errors logged and re-posted instead of `panicf` | at the fd limit the server stops accepting after 1,012 streams and `/healthz` hangs; non-EMFILE accept errors panic | 13 §3.5; 03 §2.8 (`server.odin:418-428`) |
| F-9 | Shutdown deadlines: Active ≤ `DRAIN_DEADLINE`, idle peers and peers still sending their headers get `shutdown(SEND)` then a recv cancel within 500 ms, streams get 2 s grace; past the deadline, closing connections no longer hold the loop (S0.7: 5.6 s with 500 SSE + 500 WS + a slowloris + a half body + an idle peer) | the three unbounded waits | 13 §4.1-4.2; S0.7 |
| F-10 | SIGTERM handled as well as SIGINT; a second signal exits immediately | PID-1 SIGTERM under compose | 13 §4.2 step 1 |
| F-11 | Per-thread Date header buffer | the Date race (2 malformed headers in about 800k) | S6; 01 §16 |
| F-12 | `listen` returns an error naming io_uring and seccomp; bind retry for 3 s | `Address_In_Use` after `kill -9` | 13 §3.3 |
| F-13 | Deferred responses: `response_defer` hands a handler a `Response_Ref` (loop, socket, a per-thread request generation) and `response_resume` returns the Response on that loop, or nil once the connection is gone or has moved on; while deferred, a poll on the socket closes the connection when the peer leaves and calls the application's `on_gone`; a thread's shutdown waits, to `DRAIN_DEADLINE_MS`, for the replies it owes | a pool's reply (argon2id, the query pool, llama, jobs) must not touch a connection that is gone | S0.5 (ASan: 5,042 clients left mid-verify, 0 reports; a raw-pointer control, 3/3 heap-use-after-free) |
| F-14 | The chunked body decoder refuses bad input instead of asserting: chunk data not followed by CRLF is a 400, trailer fields are discarded (at most 32 lines), and a chunk size is 1–15 plain hex digits. Found by the M1 audit (M1-01, CRITICAL): one client could stop the process with about 101 such requests a minute | — | M1 audit |
| F-15 | Throughput on the response path, from a profile behind M1's parity gate: header values written whole instead of rune by rune (12 % of a write's CPU), lookups with an already-lower-case key skip `sanitize_key`'s copy, and F-13's watch is optional (`response_defer(…, watch)`), off for store writes (7 %) | — | M1 parity gate |
| F-16 | The M1 re-read's fixes: a scan asked for inside a scan callback is queued and run by the outermost call, not nested one frame per buffered token (M1-17, CRITICAL once confirmed: 12,000 one-byte chunks overflowed a loop's stack); chunk framing counted against the body cap, 4 KiB CRLF-only chunk lines, trailer scan errors as errors (M1-18..M1-21); client-caused parse and send failures at info (M1-22) | — | M1 audit |

The request hot path keeps its shape (03 §10.4: the prototype added an enum value, a field and a shutdown case).
Spike S0.2 proves k6 parity on the fork before anything builds on it. Each upstream bump re-vendors the new base,
reapplies the F-changes that `UPSTREAM.md` lists, and re-runs the 03 contract suite.

**Rejected.** The no-fork takeover seam (07 §0.2 verified it only for client disconnects; shutdown waits forever on
Active connections and `connection_close` is private, 03 §2.6). A separate realtime port (S2). A guard only at the
places odin-http calls user code (PF §3.3 item 7, CF §3.3 item 10): it misses odin-http's own parser callbacks. A
separate `alexh95/odin-http` repo mounted as a submodule (Q4's first default): Alex chose to keep the fork in this
workspace, in-tree (ANSWERS F3).

**Alex confirms:** answered 2026-10-25: Q4, fork it, vendored in-tree with no separate repo (ANSWERS #7, F3); the
upstream offer after M2 goes through a fork made then.

### D12. Streams, allocators and the stream client

**Decision.** `platform/stream` holds the protocol code (S1):
- an SSE encoder that splits user text on CR, LF and CRLF, so no field injection (03 §10.2);
- the WS handshake with its own `Origin == SITE_URL` check (GET upgrades pass `same_origin` and carry no Sec-Fetch-*,
  04 §4.4) and a strict RFC 6455 codec (RSV, UTF-8, control frames, version) with new unit tests of its own. From
  spark's `wsserver` it takes the RFC 6455 coverage table as a checklist, the limits and the fault-injection idea;
  wsserver has no unit tests (03 §5.1, X24). A nightly Autobahn|Testsuite run fuzzes it through the lab's WS echo
  (D37, NEW);
- a multipart/mixed writer with CRLF framing (LF-only fails, 04 §4.3);
- a Range sender (200, 206, suffix, 416, HEAD, If-Range, ETag) over F-3.

Every stream response sends `X-Accel-Buffering: no` and `Cache-Control: no-cache, no-transform` (08 §3.2; S0.8: no proxy
compresses a stream), and writes its first
bytes with the headers (an SSE comment line, a multipart CRLF preamble), because WebKit resolves a streamed fetch only
at its first body bytes (S0.3). The WS handshake lets a request without `Origin` through: it isn't a browser's, so it
can't be cross-site hijacking (S0.3). **As built (M2):** while the host's origin is still the brand's placeholder (a
dev run with no `SITE_URL`), an `Origin` naming the request's own `Host` passes too, so a local run's pages can open
their sockets; a deployment names its origin and gets the strict comparison.

`platform/stream/client` is one non-blocking chunked/SSE/WS client on `core:net` (NEW). It serves `bot/backend_llama`,
`cmd/term-agent` and `tools/streamload`: one definition of the streaming client.

**Allocators: three buckets**, written into CLAUDE.md's "Allocator model" and the review rubric (02 §2.8 item 1):
1. request-scoped data in `context.temp_allocator` (as today);
2. process-lifetime data in `context.allocator` at boot (as today);
3. connection-lifetime data on the heap, in the stream's `Conn` and its buffers, freed one tick after `on_close`
   (03 §7). Handlers copy what they need before returning; after the handler the request arena is per-callback
   scratch; every timer, cross-thread and worker callback ends with `free_all(context.temp_allocator)` (03 §2.8).
   **As built (M2):** not a `virtual.Arena` per stream, as first planned: an arena commits a 4 KiB page, and F-1's
   `Stream` already holds a 4 KiB receive buffer, so the pair would pass §18.4's 6 KiB per open stream.

**Rejected.** spark's `wsserver` I/O loop (it polls every socket every tick, 03 §5.1); keeping stream state in the
request arena (02 §2.7).

**Alex confirms:** no.

### D13. The hub

**Decision** (S3, 03 §7, 13 §3.6):

- **Topics** are named `<feature>.<family>:<key>` (`chat.room:12`, `notify.user:42`, `games.players`). Each family is
  declared once, as a row of its web package's `TOPICS` table, `hub.Topic{family, policy = .Queue | .Latest | .Sample,
  ring = 256, persisted, perm, allow, replay, deliver}`, and the profile mounts the tables per host (D5, D7). A
  subscription runs the row as a GET runs a route's handler: the perm, then `allow` for the key, then, for a persisted
  topic, the keyset replay by rowid. **As built (M2):** D13's single `subscribe` is split into those three, and `main`
  mounts the tables with `hub.mount("<host>", ..TOPICS[:])` beside a `hub.ROUTES` line (`/events`) in the host's
  routes, rather than through `app.Host`, so `platform/app` never calls the hub and a profile that doesn't stream
  links none of it. Each ring also holds at most `HUB_RING_BYTES` (1 MiB), and a topic with no publish for 10 minutes
  lets its ring go (a cursor from before then is resynced). `deliver` is a server-side row the hub runs once per
  publish; room mode is its only use (`bot.ask` and `chat.reply`, D6; NEW: not prototyped). Two more fields came with
  M2's features: `member` (a family keyed by the viewer's id, `notify.user`: the layout's `#live` carries it on every
  page of theirs, and `/events` refuses it to anyone else) and `watch`, which `/events` calls when a page's stream
  subscribes to one of the row's keys and again when that stream ends, on its own loop: how chat knows who is in a
  room (D14's presence). **Topics are per host**:
  `/events` on a host subscribes only to the families mounted there, so a houston-lab page can't subscribe to Houston's
  topics even as a Guest (NEW). A publish to a family no table mounts reaches no row and is dropped and counted.
  `.Latest` topics (presence, counters, poll bars, progress) keep the newest message per publish key and never grow past
  the ring. The default key is the topic key; a publisher may pass a key, which is the element id the message targets.
  `jobs.runs` publishes with key = the run id, so its replay holds the latest row of each run, capped at the ring size
  (X8). `.Sample` drops intermediate updates while a send is in flight (telemetry).
- **Publish** from any thread: `hub.publish(topic, html, rowid = 0, key = "")`. The message is refcounted, encoded
  once per transport per loop and appended to each loop's inbox, with at most **one** `next_tick_poly` per loop per
  burst (07 §0.2 livelocked the 128-slot cross-thread queue). The hub mutex is a guard-tracked lock, so a trap under it
  is dirty and exits 70 (13 §1.3: otherwise SSE delivery silently stops while `/healthz` stays 200). Subscribing
  copies the ring refs out under the mutex and writes the replay after releasing it (03 §10.5).
- **Persisted topics publish after the writer task commits** (12 §9), carrying the SQLite rowid; memory topics
  publish immediately. Ids are never pre-allocated or seeded from `max(id)`.
- **Ids and resume.** Every SSE event's `id:` is the hub sequence `<epoch>-<seq>` (process-wide, monotonic; the epoch
  is the boot time in milliseconds, so a restart within a second still changes it, S0.3).
  Persisted payloads carry their rowid in the DOM (`id="m-<rowid>"`, zero-padded `data-seq`). The page renders its
  stream URL as `/events?t=chat.room:12@88200,notify.user:42@5512,chat.presence:12&after=<epoch>-<seq>`, where
  `@rowid` is the newest rowid the page rendered for that persisted topic and `after` is the hub sequence at render
  time (PF §6.2). On connect, after every topic's perm check in its `subscribe` passes (one failure answers 403):
  1. a `Last-Event-ID` from this epoch still inside the rings → replay from the rings;
  2. otherwise an `after` from this epoch inside the rings → replay from the rings (this closes the gap between
     render and connect on every boosted navigation that re-creates `#live`);
  3. otherwise (a foreign epoch after a restart, or a gap older than a ring) → for each `topic@rowid`, a keyset
     replay from the owning feature's store (`id > ? ORDER BY id LIMIT 200`); more than 200 missing, or any memory
     topic → `event: resync` for that topic, which the page answers by refetching its fragment
     (`hx-trigger="resync from:body"`).

  Duplicates from an overlap are harmless because every live element has a stable id and is swapped by upsert or by
  id. (NEW design; UNVERIFIED until the M2 resume specs, including one across a server restart.)
- **Per-room transports**: WS sends a snapshot of the last 50 on (re)connect and upsert dedups; multipart resumes by
  `HX-Last-Part-ID` (rowid or hub sequence); polling uses the ptag as the cursor (last rowid). *As built (M3, M2-31 and
  M2-35):* a WS page sends the room's version it has seen as its first frame and gets what changed since, or the last
  50 replacing its log when the room let some of that go; SSE's resync asks `/since?ver=` the same way.
- **Authors**: the hub skips nobody. The author's POST or WS reply and the hub's copy carry the same id and dedupe by
  upsert, so the author's other tabs and devices get the message too.
- **Limits**: 256 KiB queued per stream, then the consumer is closed as `Too_Slow` (SSE ends; WS closes with 1013
  when the next frame would pass the cap, then gets 2 s to read before the fork cuts it, F-1's `stream_end` deadline,
  S0.3; both resume); 64 MiB queued in total, after which new streams get 503; `STREAMS_PER_USER` 8, `STREAMS_PER_CLIENT`
  16, `STREAMS_TOTAL` 8192 (≤ `MAX_CONNS`); 64 KiB per message; 20 stream connects per minute per client id.
- **Heartbeat**: one timer per loop, every 20 s (`: hb` for SSE, a ping for WS). WS pong deadline 45 s, then the
  socket closes. 20 s is under NPM's 90 s, Fly's 60 s and Cloudflare's 125 s idle cuts (S20, 08 §0).
- **Close codes** (hx-ws reconnects only on 1001, 1005, 1006, 1011, 1012, 1013 and 1014: 03 §7, 13 key facts): 1008
  for policy and revoked auth and 1009 for oversize (the client stops); 1011 after a pure-zone crash in that stream;
  1012 on drain and restart; 1013 for a slow consumer.
- **Authorisation**: each topic row's `subscribe` checks the perm; a kick or role change publishes a revoke that closes
  the affected streams with 1008 (07 §1.5). On the page's SSE stream the server sends the named `kicked` event, which
  triggers a full navigation to `/login` and so removes `#live`; a reconnect without auth gets 403. `revoke.spec` (M4)
  asserts this, and that the server sees at most 3 reconnects in 30 s. Whether hx-sse itself stops retrying after a 403
  is UNVERIFIED (M4) (X19).

**Rationale.** S3; 03 §7, §10.5; 13 §3.6, §7 item 8; 12 §9; LC §6, §9 (the `TOPICS` rows).

**Rejected.** One global id for all topics (CF §3.4: every restart forces durable chat to resync). Ids allocated
before persistence and seeded from `max(id)` (CF §6.3: a crash reuses ids and cursors silently skip messages).
Skipping the author's connections (PF §6.4.1: the author's other tabs miss the message). Posting per message per
connection across threads (07 livelock).

**Alex confirms:** no.

### D14. The page-level realtime contract

**Decision** (PF §6.2, 03 §9):
- At most **one SSE stream per page**, at layout level (`<div id="live" hx-sse:connect="/events?…">`), carrying the
  member's own topic, presence and the page's topics. Unnamed events carry OOB or `<hx-partial>` HTML (badges, toasts,
  upserts). Named events only trigger a refetch or a navigation (`resync` refetches a fragment; `kicked` navigates to
  `/login`, D13, X19); content never rides `event: message` (04 §4.2).
- At most **one `hx-ws:connect` per page**, inside the swapped region (a chat room in WS mode, the terminal, a c4
  game), so switching rooms opens a fresh socket.
- A boosted navigation re-creates `#live`; the render-time cursor closes the gap (D13); presence is debounced 10 s so
  it doesn't flap. Presence follows `pauseOnBackground` (04 §4.2): online while a stream is open, away if it closed
  less than 5 minutes ago, offline otherwise.
- Live logs are `<div role="log">` of `<article>` elements, never `<ul>`/`<li>` or table targets, because hx-pending
  wraps its clones in `<div class="hx-pending" style="all: initial">` (04 §5.5). Live regions exist in the initial
  markup (11 §7.4).

This keeps a page within the browser's 6 connections per origin on the HTTP/1.1 LAN-direct stage (03 §9; 08 §3.2).

**Rejected.** Per-component streams (they need h2 everywhere). CF §6.3's `<li>` messages under hx-pending.

**Alex confirms:** no.

### D15. The crash model

**Decision** (S5, 13 §1.4, §6.3):
1. **Guard every entry point**: every completion callback the fork owns (F-5), hub drain, app timers, worker tasks
   (argon, query, llama, jobs) and the writer task. Linux binds glibc `_setjmp` (3 ns, against 298–518 ns for
   `setjmp`) with `sigaction` and a lazily set per-thread `sigaltstack`; Windows uses a vectored exception handler and
   `_resetstkoflw` (13 §1.4-1.5). The guarded frame stays trivial, with volatile loads after the jump: Odin does not
   mark `setjmp` returns_twice, so the guard is formally UB (13 key facts).
2. **Thread-local counters**, kept by helpers: `locks_held` (`guarded_mutex`, the only `sync` locks allowed: `tools/check
   locks`), `async_posted` (ops posted by this callback), and `in_sqlite` (incremented around every call into SQLite by
   `platform/sqlite`).
3. **On a trap**: dirty if `locks_held`, `async_posted` or `in_sqlite` is above zero (a trap inside SQLite's C code is
   never pure, 13 §1.4 table and §2.1). Dirty → answer 500 if possible, log, drain, **exit 70**. Pure → answer 500 (or
   close that stream with 1011), log `ev=crash zone=pure`, count `app_guard_recoveries_total`, keep serving. Every
   statement on that loop's reader connection must then be reset (walk `sqlite3_next_stmt`, `sqlite3_reset` each),
   because `longjmp` skipped the deferred resets (13 §1.3) and an unreset reader statement pins the WAL without bound
   (12 §10). The reset is **pulled, not installed**: `platform/guard` counts recoveries per thread, and
   `platform/store/sqlite` compares that count before each use of the loop's reader, and on a 1 s timer that the
   reader's first use arms on its loop, and resets every statement when it has moved. Without the timer, a loop that
   crashed and then got no more reads kept its snapshot for good (S0.6: +165 MB of WAL in 5 s of writes; flat with
   it). `guard` never calls into SQLite, so a memory profile still links no SQLite (D18; LC §5). More than
   100 pure recoveries in 60 s counts as dirty, because each recovery leaks its `context.allocator` allocations
   (13 §1.3) (NEW).
4. **Watchdog thread**: a loop whose `tick_age` exceeds 10 s, or the store write lock held for more than 5 s → log
   `lvl=fatal`, flush logs, write `/data/last-crash.txt` (shown on `/admin/ops` after the restart), exit 70.
5. **Supervision**: compose `restart: unless-stopped` and `init: true` (Docker outside Swarm never restarts an
   unhealthy container, 13 §3.1); `setrlimit` NOFILE soft = hard at boot and compose `ulimits: nofile: 65536`
   (13 §3.5); bind retry for 3 s (F-12).
6. **Remotely triggerable crashes are fixed regardless**: F1 (F-6), enum columns read through `store.enum_from_int`
   (02 F3), the markdown depth cap of 32 and input cap of 64 KiB (06 §3.2), the accept panic (F-8), the strict WS
   codec. The guard is defence in depth.
7. **No zone declarations**: rule 3's counters decide pure or dirty, so `Module_Ops.zone` is dropped with
   `Module_Ops` (§0.3). In practice the markdown, form, frame and multipart parsers, the terminal's grid-frame decoder
   and the cursor parser are pure; SQLite is dirty (`in_sqlite`).
8. **Always log what died**: the trap handler writes one line (signal or code, thread, route, request id) and a
   `core:debug/trace` capture for assert and panic (13 §1.4 item 5). Release builds keep a split debug file per
   `VERSION` (13 §6.2).

**Rejected.** A middleware-only recover (Odin has none: `Assertion_Failure_Proc` is noreturn and bounds checks trap
without a context; digest critic). Unlocking and continuing after a dirty trap (13 §1.3). One guard around
`nbio.tick` (13 §1.3: may leave completions unconsumed).

**Alex confirms:** no.

---

## D. Data

### D16. The store

**Decision** (S8, 12 §9):
- **`platform/store/sqlite` (store v3)**: one writer connection under a guarded mutex with `BEGIN IMMEDIATE`; one
  read-only connection per nbio loop, opened lazily through `@(thread_local)`; `SQLITE_DBCONFIG_ENABLE_QPSG` (1007)
  on every connection before any prepare; WAL, `synchronous=NORMAL`, `journal_size_limit=64 MiB`, `busy_timeout`
  5000.
- **The writer task**: a dedicated thread with a bounded queue that commits whatever is queued as soon as it is free,
  up to 100 items per transaction (chat messages, receipts, notifications, audit rows, and the skeleton's request
  writes, S0.4's candidate C), so writes that arrive during a commit form the next batch; then it runs each write's
  continuation on its originating loop, with one `next_tick` per loop per batch (12 §3.1: 56–59k msgs/s batched 10 per
  transaction against 18–19k autocommit). It has no timer: a fixed 10 ms tick, the first design, would add up to 10 ms
  to every request write against a p99 bar near 16 ms (S0.4).
  The continuation is the caller's own next step (`Store_Insert` carries it; the memory family calls it at once): on
  the web side it publishes the persisted topic and responds, so `store/sqlite` never imports `hub` (LC §8).
- **A 2-thread query pool** for anything that scans, ranks, exports, backs up or can hit a budget (bm25, dbview,
  `VACUUM INTO`, retention chunks). Results return through `nbio.next_tick_poly(l = loop)` and
  `http.response_resume`, whose generation check is F-13's (S0.5); a full queue answers 503 (12 §4: two inline 2 s queries cut fast-path RPS from 51.4k to 28.4k;
  pooled, it stayed at 51–52k).
- **Chunked deletes** of 1,000 rows per transaction on the writer task (a 100k-row delete held the writer for 330 ms,
  12 §3.2); **sort indexes per list sort key** (a page goes from 10.7 µs to about 3 µs, 12 §2.1); **keyset paging**
  for history and infinite scroll.
- **Build flags**: `-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_THREADSAFE=2 -DSQLITE_DEFAULT_MEMSTATUS=0
  -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_FTS5` (12 §8; FTS5 adds 220,160 B;
  MEMSTATUS=0 is 4.1× on sorts across 16 connections). The ops dashboard shows `sqlite3_db_status`, because
  MEMSTATUS=0 disables `sqlite3_memory_used` (12 §10): `store/sqlite` pushes those numbers, the writer queue and the
  pool depth to `platform/obs` on its own timer, and `ops` reads obs, so `streams` keeps ops without SQLite (LC §5).
- **`MEMMODE`, one vocabulary everywhere**: `single` (one in-RAM connection, reads under the writer lock: the
  skeleton's model) or `ephemeral` (a WAL temp file swept at boot: the production code path). The default is
  `ephemeral`; the `skeleton` profile's mode comes from D17. Shared cache and memdb are rejected (12 §1: `SQLITE_LOCKED`
  errors and starving readers).
- **`platform/store/memory`**: rings and maps behind guarded locks, ids `<epoch>-<seq>`; the UI says "ephemeral mode".
- **Migrations** (the 12 §5 runner, 6/6 tests): `schema_migrations(feature, seq, name, sha256, applied_at)`,
  `schema_meta(app, profile, adopted_from)`, `PRAGMA application_id = 0x4F485354`; one package-level `MIGRATIONS` per
  SQLite store (`app/stores/sqlite/<f>/migrations/`), applied by one `store_sqlite.migrate("<f>",
  <f>_store.MIGRATIONS[:])` line per store in a SQLite profile's `main`, in dependency order (the runner never holds a
  literal that points into `main`'s frame, 09 §4.4, and a `migrate` line left in a memory profile doesn't compile, since
  memory stores declare no `MIGRATIONS`; LC §6); dormant features' rows left alone; skeleton (709bc94, v1.1.1) and spark
  portal databases adopted as legacy features with `schema_version` frozen; foreign or edited migrations refused;
  another profile's database refused unless the binary runs once with `--adopt-profile`. Migrations are forward-only and
  **additive** (binary N−1 runs on schema N, so a rollback needs no restore, 08 §5.5); a destructive change takes two
  releases.
- **Tables** are prefixed with the feature name (`chat_messages`, `accounts_prefs`; `uploads` owns its session rows in
  `uploads_blobs` and `uploads_parts`, X9, X13), except the legacy skeleton tables (`contacts`, `events`, `notes`) and
  accounts' `users` and `sessions`. No cross-feature foreign keys (D6).
- **FTS5** with `unicode61 remove_diacritics 2`, external content and triggers, highlighted with FTS5's own
  `highlight()`/`snippet()` (12 §7: MATCH 12 µs–2.8 ms at 100k messages against 46–272 ms for a `contains_ci` scan;
  the index adds 5.7 MB). bm25 ranking runs on the pool; `optimize` runs weekly through the writer task;
  `contains_ci` stays for small tables and memory impls; one result list never mixes the two engines (their folding
  differs, 12 §10).
- **Backups**: `--backup` (answered by `store_sqlite.open`, D10; `VACUUM INTO`, live-safe, refuses to overwrite;
  `SK/app/src/repository/db.odin:269-295`) nightly from the pool (keep 7) and before every deploy (keep 5); off-box
  copies per Q16; a restore drill per release; litestream deferred (08 §9: checkpoint coordination unverified).

**Rejected.** A single connection plus QPSG as the production store (12 §2: list and pages at 0.55–0.58× v1.1.1).
Several writer connections (12 §3.4: 1.23M BUSY errors in 4 s). The trigram tokenizer (index 6× larger).

**Alex confirms:** no.

### D17. `:memory:` parity for the `skeleton` profile

**Decision.** S18's both-stores requirement stands, but no measured mode passes every `:memory:` cell (12 §2, 16
loops, 200 VUs, against v1.1.1):

| Cell | v1.1.1 | HEAD | single + QPSG | ratio | v3 ephemeral | ratio |
|---|---:|---:|---:|---:|---:|---:|
| list | 39,301 | 10,225 | 21,502 | 0.55 | 37,648 | 0.96 |
| pages | 36,267 | 13,506 | 20,862 | 0.58 | 32,990 | 0.91 |
| write | 38,908 | 36,172 | 35,753 | 0.92 | 12,756 | 0.33 |
| mixed | 28,782 | 13,883 | 22,025 | 0.77 | 37,150 | 1.29 |

So spike **S0.4** decides before M1, measuring every cell with the sort indexes installed (they add write cost).
Candidates:
- **A**: `single` + QPSG + sort indexes + a dashboard aggregate cached for 1 s (12 §2.1, §9); the cache makes the
  dashboard lag a write by up to 1 s (S0.4).
- **B**: `ephemeral` + sort indexes + the temp file on tmpfs (`/dev/shm`) on Linux, unsynced; on Windows B is v3 with
  the sort indexes, since research 12's ephemeral file already ran unsynced and WAL's `NORMAL` never syncs a commit
  (S0.4).
- **C**: B + group commit of concurrent skeleton writes through the writer task (D16), each write handler answering
  through F-13's deferred response after its batch commits (S0.4).

The first candidate that passes every `:memory:` cell under D38's rule on both legs becomes the `skeleton` profile's
default. If none does, Q6 applies. The `write@mem` target is v1.1.1's 38,908 rps, not HEAD's 36,172. The file-DB
read cells already pass with v3 (1.2–2.7× v1.1.1). File-DB write at 0.98× (a ratio of medians, 12 §2) is a watched
margin, not an open question: S0.1's and S0.4's paired rounds settle it, and if that cell fails, the file DB also gets
candidate C (group commit through the writer task) for skeleton writes (X17; R2a). No 1-loop leg is added: at one
loop every variant is below v1.1.1 on list, pages and write (12 §2 1T tables, for example file-DB write 6,683 for v3
against 7,501 for v1.1.1).

**Rejected.** Declaring `MEMMODE=single` parity-passing (PF §3.6). RF §3.8's "should hold writes at HEAD's 36k" (wrong
target). Gating on the file DB only without Alex.

**Measured and answered (S0.4; ANSWERS round 5, 2026-10-26).** No candidate passes every `:memory:` cell on both
legs. C (B + group commit) passes the most and is chosen: the `skeleton` profile's `:memory:` mode is C. On Linux,
where the noise band is about 2 %, C passes search, api, detail, mixed and scale@20 and misses pages, list and write by
4–9 % against v1.1.1, which sorts its 20 rows in Odin straight from RAM; v3 alone writes at 0.06–0.09× on `:memory:`,
B at 0.18–0.28× (tmpfs on Linux didn't save it), and A at 0.58–0.64×. Per Q6's answer those `:memory:` cells are gated against HEAD (709bc94) with a
documented exception each. The file DB takes C too (X17): v3's file-DB write measured 0.38–0.43× v1.1.1, so R2a's
fallback applies, and C writes at 2.9–4.3× on a file DB. No file-DB cell is waived.

**Alex confirms:** yes (Q6 answered 2026-10-26: the default, candidate C; ANSWERS round 5).

### D18. Optional SQLite and the no-SQLite-build claim

**Decision.** SQLite stays optional per profile (S9). A profile built with `-collection:store=app/stores/memory`,
whose `main` doesn't import `platform/store/sqlite`, and with the `envadmin`, `nick` or `anonymous` identity never
references the foreign library, which then never reaches the linker (09 §4.1: an imported but uncalled package costs
about 512 B, an unused `#load` 0 B; LC §16: `streams`' linker line ends at `"kernel32.lib"`, and the stand-in
library's marker is in `full`'s executable and not in `streams'`). The provable claim is:
**such a profile builds from a checkout where prepare's SQLite step never ran and no sqlite3 library exists.** It still
needs the platform linker: `clang` (or `$ODIN_CLANG_PATH`) as the link driver on Linux and macOS (09 §6.1,
`linker.cpp:613-616`) and the MSVC/SDK libraries on Windows. CI proves the claim by building `minimal`, `streams` and
`lab` with prepare's C step skipped and the SQLite build output deleted.

Features whose value is persistence have **no member in the memory family**, so a memory build that reaches one does
not compile: "Path does not exist: store:accounts" and "store:contacts" (LC §16). That refusal is the compiler's, and
the generator makes it first, with advice (D26). They are accounts (and so the `accounts` identity), contacts (and so
dashboard and gallery, which import it; gallery's form posts create contacts) and term. dbview reads through
`platform/store/sqlite`'s pool, so it is mounted only in SQLite profiles, as is the `audit` feature's `/admin/audit`
page, which reads the log back; audit's memory member only writes log lines (D6). Wiki, find and video follow the
family instead of leaving: in memory the wiki is the read-only embedded docs, find scans with `contains_ci` and video
reads the manifest (D8). `uploads` itself does not require SQLite: its session rows live in `app/stores/sqlite/uploads/`
or in `app/stores/memory/uploads/`, where they are lost on restart, so resumable uploads need SQLite (X13).

**Rejected.** "Builds on a runner with no clang" (RF §11.1, PF §11.1, CF §11.1): it cannot pass on Linux or macOS.
A boot-time `requires` check over the imported implementations (the old D5): the compiler refuses earlier.

**Alex confirms:** no.

---

## E. Client stack

### D19. Client bundles

**Decision** (S13, 11 §8):
- **One definition.** Each web package, and any switched implementation that needs an extension, declares
  `EXTS :: bit_set[web.Ext]{.Sse, .Ws, …}` on one line (a lint-enforced form) (X29). `chat_transport_ws` declares
  `.Ws`, `chat_transport_sse` `.Sse`, `chat_transport_multipart` `.Multipart` and `chat_transport_poll` `.Ptag`.
  Since `chat_web` imports all four for its switch (D8), its `EXTS` is their union plus what the feature needs
  regardless of transport, `.Pending .Upsert .Prompt .Targets .Download` (the last for D21's transcripts, X34):
  `EXTS :: chat_transport_ws.EXTS + chat_transport_sse.EXTS + chat_transport_poll.EXTS +
  chat_transport_multipart.EXTS + bit_set[web.Ext]{.Pending, .Upsert, .Prompt, .Targets, .Download}`, still one
  line in the file. So every chat profile ships ws, sse, hx-multipart and ptag, and X29's lean transport sets go (LC
  §12 item 5). `bot_web` adds `.Browser_Indicator`. `main`'s **`BUNDLE_EXTS`** constant is the union of the `EXTS`
  of the packages the profile mounts (`chat_web.EXTS + notify_web.EXTS + …`); `tools/check exts` requires it to name
  every mounted package that declares one. `web.Ext` (declared in the L1 leaf package `platform/ext` and re-exported
  by `platform/web`; X33) is a closed enum with one table of registration names and one of file names
  (04 §2.2): `.Sse` sse, `.Ws` ws, `.Multipart` hx-multipart, `.Live` hx-live, `.Pending` hx-pending,
  `.Browser_Indicator` browser-indicator, `.Prompt` hx-prompt, `.Preload` preload, `.Ptag` ptag, `.History_Cache`
  history-cache, `.Head` hx-head, `.Upsert` upsert, `.Targets` hx-targets, `.Download` download, `.Compat_Htmx2`
  compat, `.Compat_Alpine` alpine-compat, `.Csp` hx-csp. A misspelt extension is a compile error.
- **`tools/bundle <profile>`** (run by prepare) takes the package list from the compiler, `./build.sh <p>
  -export-dependencies:json`, which resolves the four collections and lists exactly the selected family members
  (LC §16: `streams` lists `stores/memory/*`, `client/vanilla`, `identity_nick` and `theme/lite` and no SQLite
  package), and unions the `EXTS` of those packages, web and implementation alike (X29). It concatenates
  `htmx.min.js` → (`hx-csp`, in the scripting page bundle only) → the extensions in a fixed order, writes a header
  `/* exts: … */` (none for an empty union, so `minimal`'s bundle is `htmx.min.js` exactly), and precompresses with
  `brotli -q 11` and `gzip -9 -n`, required on Linux and found on the `PATH` or in Git for Windows on Windows, so the
  files are byte-identical on both OSes (S0.10; a Windows build without them ships what it has). The app `#load`s each
  bundle under `when #exists(...)`, since the package list comes only from a build; a build before prepare compiles
  and boot check 6 refuses it (S0.10). CSS (`platform/static/base.css`, the build's theme member, each mounted feature's
  `static/<f>.css`) and behaviours (each mounted feature's `static/<f>._hs`) are concatenated the same way: **assets
  ride with the package that owns them.** The binary `#load`s identity, `.br` and `.gz`, fingerprints by crc32 at
  boot, and serves br > gzip > identity with `Vary: Accept-Encoding` and immutable caching. The boot check compares
  the header with `main`'s `BUNDLE_EXTS` (D5 check 6); it stays fatal (X29). X33's runtime union over vtable `exts`
  fields is deleted with the vtables (§0.3).
- **Page bundles**: a closed `web.Bundle` enum `{Main, Scripting, Compat_Htmx2, Compat_Alpine}`. `Main` is the union;
  the other three have fixed extension sets in one table and are built only for a profile that imports the
  `scripting` or `compat` feature (`lab`, and `full` for its `houston-lab` origin, D25), whose web packages declare
  `BUNDLES :: bit_set[web.Bundle]{…}` on one line; `web.Bundle` and its table live in `platform/ext` (S0.10). The four lab-only extensions
  ride only in those three, never in `Main` (D21). The layout takes the bundle as a parameter, and links across
  bundles are full navigations (`hx-boost="false"`; a body swap keeps the old document's CSP and scripts, 11 §6.4,
  05 §9).
- **Hyperscript** (in `client/hyperscript` profiles) ships as a separate fingerprinted deferred file after the bundle,
  using upstream's shipped `.br` (11 §8.1: both layouts are race-free).
- **The htmx-config meta** is generated at boot from the same union as strict JSON (S14), written with `w()`, never
  `fmt` (`SK/CLAUDE.md` "Views"), and names `hs-include` whenever the hyperscript client is present.
- `minimal` and `skeleton` ship `htmx.min.js` byte-identical to the skeleton's, under the same crc32 name (11 §8.1).

Sizes (S0.10, raw / br): htmx alone 36,716 / 11,736 B; `full`'s Main 79,790 / 23,022 B; `streams`' Main 71,358 /
20,852 B; Scripting 85,173 / 25,063 B; the compat bundles 38,466 / 12,180 B and 38,487 / 12,249 B; hyperscript 175,365
/ 39,706 B (11 §9). `bundle-race.spec` passed 9/9 per engine with assets held 400 ms (S0.10).

**Rejected.** Hand-written `cmd/<p>/bundle.txt` (RF §5.1) and `bundles/manifest/*.txt` (PF §3.9): second
definitions. CF §5.1's `tools/catalog` → `catalog.json` → `tools/bundle` pipeline (a deeper build). Boot-time
concatenation without precompression (core has no gzip writer and vendor:zlib links only with `-linker:msvc`,
09 §0.8). Separate deferred extension files (the defer race, 04 §2.3, 11 key facts).

**Alex confirms:** no.

### D20. CSP modes and headers

**Decision** (S12, 11 §5):
- **Base policy**: the skeleton's hash CSP verbatim (`SK/app/src/controllers/middleware.odin:182-205`) plus
  `Permissions-Policy: camera=(), microphone=(), geolocation=()` (never fullscreen, autoplay or gamepad entries, which
  silently break the games iframe, 11 §3), COOP `same-origin`, CORP `same-origin` (`cross-origin` on og.png and
  favicons). Never COEP. HSTS only at NPM. `minimal` keeps exactly the skeleton's header set (11 §5.2).
  `connect-src` stays `'self'`, which covers same-origin ws and wss (Firefox since 2018, Chrome 71, Safari 16; 11
  key facts; Firefox proven in CI).
- **Route flags add to the base**, as boot-constant strings looked up in O(1) (11 §6.1):
  - `.Private`: `Cache-Control: no-store`, `X-Robots-Tag: noindex, nofollow`, `hx-history="false"` on `<body>`;
  - `.Frame_Games`: `frame-src <GAMES_URL>`;
  - `.Media`: CORP same-origin, immutable caching, `Accept-Ranges`;
  - `.Nonce_Csp` (`/scripting/*` only: in `lab`, and in `full` on `houston-lab`): `script-src 'nonce-<16 B>'
    'sha256-<prepaint>'` per response (about 182 ns, 11 key facts), `no-store`, `hx-nonce` stamped by a marker
    substitution in the response writer; `/scripting/tt` adds Trusted Types and loads no hyperscript (TT breaks
    hyperscript's `put`, 11 §2.3);
  - `.Lab_Host` (every `scripting` and `compat` route, D25): a mount rule, checked at boot, not a header flag: the
    row may be mounted only on a host where no cookie-setting identity runs, so no `Set-Cookie`. Every response on
    `full`'s lab host (`SITE_URL_LAB`) sends `X-Robots-Tag: noindex`, since the `lab` profile's origin holds the
    indexed copy (NEW).
- **CSP reports** (X11): `full`, `streams` and `lab` send `Reporting-Endpoints: csp="/csp-report"` and add `report-to
  csp` to their CSP. `minimal` and `skeleton` never do: their CSP stays the skeleton's verbatim, and `minimal` keeps
  the skeleton's exact header set. `/csp-report` logs at warn and is rate-limited (D35).
- UGC bodies carry `hx-ignore` and `data-disable-scripting`.

**Rejected.** App-wide hx-csp (11 §2: it strips hx-* from stream fragments and fails open for verb-less connect
elements). `unsafe-eval`. Separate CSP modes per profile (one base plus flags is enough).

**As built (M2):** Trusted Types is its own route flag, `.Trusted_Types`, valid only beside `.Nonce_Csp`; the nonce is
base64url, so `/scripting/streams` can send it in a connect URL. On 4.0.0 the fail-open is narrower than 11 §2 found:
an unnonced connect that arrives in an htmx swap is stripped, one handed to `htmx.process` inside a subtree that other
code wrote still connects (`streams-hxcsp.spec` pins both; PLAN §12.2's note). The rejection stands.

**Alex confirms:** no.

### D21. All 17 htmx extensions

**Decision.** Thirteen extensions have real uses in Houston; the other four (the lab-only extensions) have no honest
product use and are proven on lab pages with a written reason. Those pages run only on origins that hold no sessions:
the `lab` profile's, and `full`'s second host `houston-lab.alexh95.com`, so Houston covers all 17 itself (D25;
ANSWERS F2). Each is declared in the `EXTS` of the package that uses it, web or implementation (D19, X29). Every
extension has an e2e assertion on its behaviour (no API lists registered extensions, 11 §8.2), and `bundle-race.spec`
delays assets 400 ms with and without hyperscript (11 §7.3).

| Extension | Real use in Houston | Lab-page proof and reason (the lab-only four; in `lab`, and in `full` on `houston-lab`) |
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
| hx-live | — | `/scripting/live`: the password-rules widget built three ways (app.js, hyperscript, hx-live). It needs eval: EvalError under the hash CSP (04 §5.4) |
| hx-csp | — | `/scripting/*` with per-response nonces; `/scripting/streams` pins the upstream gaps so a fix shows up as a spec diff. App-wide it fails (11 §2) |
| htmx-2-compat | — | `/compat/htmx2` replays the skeleton's htmx-2-era views (commit 78a31ca, 07 key facts): a 422 is not swapped and `htmx:afterSwap` fires. It breaks the 422 pattern and turns on implicit inheritance (04 §5.15) |
| hx-alpine-compat | — | `/compat/alpine`: inert registration, no errors, no Alpine vendored. It needs Alpine, a client framework (PHILOSOPHY "The line we hold") |

htmx 4 core features showcased (RF §5.4, PF §5.4): morph swaps (`innerMorph` on ops tables and the terminal screen,
`outerMorph` for the bot's final message), `<hx-partial>`, `hx-status:422/429/5xx`, `swapEmpty`, the `delete` swap,
view transitions on boosted links only (`SK/CLAUDE.md` "View Transitions"), `hx-config timeout:0` on the upload
finish request only (`POST /uploads/<id>/finish`, which can run long while the server hashes and moves the file; the
chunks go through app.js's fetch shim, so no htmx timeout applies to them; UNVERIFIED (M6), X14), HCON in
`hx-vals` (the meta stays JSON, S14), `hx-sync` (`this:replace` on search; the default is `queue first`, 04 §9),
`hx-disable`, `hx-indicator`, `hx-ignore` on UGC, `intersect once` and `every 2s` triggers, the `HX-Trigger`,
`HX-Location`, `HX-Retarget`/`HX-Reswap` and `HX-Push-Url` response headers, explicit `:inherited`. QUERY /
`hx-query` only if the fork's method table accepts it (cut list).

**Alex confirms:** no. Alex agreed (ANSWERS #8, 2026-10-25), and ANSWERS F2 brings the four's pages into `full` too,
on `houston-lab` (D25). Alpine stays inert unless Alex asks (D3).

### D22. Hyperscript and the two client implementations

**Decision** (S15):
- _hyperscript 0.9.94, core only (Q7), served by the binary. Behaviours live in each feature's `static/<f>._hs` and
  in the platform's core set; markup only ever says `_="install Name"`, emitted only by `html.behave(b, .Name)`.
- One closed table in `platform/html`: `Behaviour :: enum {…}` and `BEHAVIOURS :: [Behaviour]struct{hs, vanilla:
  string}`. Under `client/hyperscript`, `behave` writes `_="install Composer"`; under `client/vanilla` it writes
  `data-behave="composer"`, routed by one delegated listener in app.js on `htmx:after:process`. An empty vanilla
  entry means "no twin". The two implementations are the `client:` family (D8): `platform/html` imports `client:.`,
  and `behave` calls the build's member directly. They have no contract constant, so CI builds both members at every
  call site, through `full` and `full-vanilla`.
- A `hyperscript:before:init` gate in app.js refuses everything but `install Name(...)` (05 §5: verified to block both
  injection forms). Dynamic data travels only in `data-*` through `esc()`, never spliced into `_` (escaping doesn't
  protect a value inside `_`, 05 §5). `socket`, `eventsource`, `worker`, `component`, `js` and `hdb` are banned. Large
  lists use one delegated container behaviour, never a behaviour per row (05 §6: about 0.1 ms per inline element).
- **Twinned** (both implementations, specced both ways): `Tabs`, `Toast`, `ResetOnSuccess`, `Dismiss`, `SearchBox`,
  `RangeFill`, `Composer`, `AutoScroll`. **Hyperscript only**, progressive enhancement: `RelTime`, `CopyText`,
  `ShowPassword`, `Draggable`, `DropZone`, `Palette`, `TermKeys`, `MeasureTerm`, `Resume`, `Scrubber`, `OtpInput`,
  `Expire`.
- **Progressive-enhancement rule** (RF §5.5): every feature's core flow works with zero behaviours (forms + htmx).
  Core specs run on `full` (hyperscript) and on the CI-only `full-vanilla` profile, which is `app/cmd/full` built
  with `client=vanilla` (D24).
- app.js keeps in every profile: the hashed theme pre-paint and persistence, count-up, the gate (hyperscript
  profiles), the roughly 40-line chunked-upload shim (fetch reports no upload progress, 07 §4.3), and later the games
  postMessage listener.
- `escaping.spec` asserts that every `_` on every rendered page matches `^install [A-Z]\w*$` and every `data-behave`
  value is a vanilla name in `BEHAVIOURS`.

**As built (M1):** `html.behave` and the `Behaviour` table arrive in M2 with `client/hyperscript`, the family's second
member. M1 has one member, vanilla, and the skeleton answers byte for byte as 1.2.x did, so its own `data-*` markup and
app.js's delegated listeners stay as they are until then.

**As built (M2):** both members and the table are in (PLAN §12.4's as-built note), and the skeleton's markup now goes
through `html.behave` too, so its pages carry `data-behave="…"` where 1.2.x had `data-reset-on-success` and app.js
matched roles and classes: one dispatcher by name is what lets a page built for either client carry the same view code,
and the skeleton is the vanilla member's witness. The pages grow by a few attributes; their routes, statuses and
behaviour are unchanged, and the skeleton's specs pass on both members. The code both members keep (the theme picker,
count-up, the overlay's Escape) is `client/core.js`, which tools/bundle puts first in each profile's `app.js`. `lab`
is the first profile on hyperscript; `full` and `full-vanilla` take over the both-members check when `full` exists.
The table gained `Password_Rules` (scripting's, hyperscript-only). A feature's `static/*.js` is appended to `app.js`
for code that is no behaviour and runs under either client (PLAN §12.4's note); a behaviour still goes through
`html.behave`.

**Rejected.** String behaviour names (RF §3.9, CF §4.1). RF §4.2's boot switch embedding both runtimes. A vanilla twin
of every behaviour (PF's `houston-vanilla`): twin cost without user value.

**Alex confirms:** yes (Q7, the pin: default (not yet raised)). Both client implementations stay, as Alex chose on
2026-10-25 ("let's dupe it for now", ANSWERS #2).

### D23. Themes

**Decision.** The skeleton's token system is unchanged (`data-style` × `data-scheme`, the hashed pre-paint;
`SK/CLAUDE.md` "CSS conventions"). `theme/full` is 6 styles × 24 schemes (skeleton, full, lab, full-vanilla).
`theme/lite` is the `modern` style with `midnight` and `daylight` (minimal, streams); it keeps the same pre-paint
script, so minimal's CSP string stays identical. The two are the `theme:` family (D8), which `platform/html` imports
as `theme:.`; the hosted profiles build both. Houston adds one palette block (`houston`) as its server-rendered
default and stores each member's choice in the accounts feature's `accounts_prefs` (X9), so the server renders the
right attributes on every device; localStorage still covers guests (PF §5.6). Feature CSS is namespaced `.<f>-*`
(lint).

**Alex confirms:** no.

---

## F. Granularity

### D24. The profile catalog

**Decision.**

| Profile | Features (beyond platform) | Store family | Identity / client / theme (families) | Transports | Bundle (derived, D19) | CSP | Purpose | Host |
|---|---|---|---|---|---|---|---|---|
| `minimal` | home, notes, about | memory | anonymous / vanilla / lite | none | `htmx.min.js` byte-identical | the skeleton's header set exactly | the smallest hello world; no SQLite library; ≤ 1.5 MiB | `starter-minimal` |
| `skeleton` | dashboard (its page is the root row), gallery, contacts, about | SQLite (v3); `:memory:` per D17 | anonymous / vanilla (the skeleton's app.js behaviours) / full | none | `htmx.min.js` byte-identical | base | the S18 witness and the skeleton's 40-item checklist (01 (A)) | `odin-htmx.alexh95.com` (Fly); `starter-skeleton` (LAN only) |
| `streams` | home, notes, chat (4 transports), notify, bot (mock), ops, status, about | memory | nick (posting only from `LAN_CIDRS` by default) / vanilla / lite | SSE, WS, multipart, poll | Main: htmx + sse, ws, hx-multipart, upsert, hx-pending, ptag, hx-targets, download, hx-prompt, browser-indicator (X29) | base | the stream substrate without SQLite, so stream regressions are attributable | `starter-streams` |
| `full` (Houston) | every catalog feature (ANSWERS round 3), on two hosts (D25): Houston's features on the main host (D29); on `houston-lab`, `landing` at its root and every starter demo and lab page: notes, contacts, gallery, about, dashboard (at `/dashboard`), lab (`/lab/streams`), scripting, compat | SQLite (one file; houston-lab's demo tables in it, capped and reset nightly) | accounts / hyperscript / full (no identity on `houston-lab`) | all, plus Range and the agent WS | Main (13 extensions) + hyperscript; Scripting + Compat_Htmx2 + Compat_Alpine on `houston-lab` only | base + flags; nonce on `/scripting/*` (`houston-lab`) | the showcase. It implements every feature itself, with no dependency on another profile's container, the four lab-only extensions' pages included (ANSWERS F2, round 3) | `houston.alexh95.com`; `houston-lab.alexh95.com` (the same container, session-free) |
| `lab` | landing, status (witness board), wiki (the memory family's read-only docs: the starter's own; from M8), scripting, compat, lab, about | memory | anonymous / hyperscript / full | SSE, WS, multipart (contract pages) | Main + Scripting + Compat_Htmx2 + Compat_Alpine | base; nonce on `/scripting/*` | the starter's own page, the witness board and the four lab-only extensions, on an origin with no sessions; a witness (D2, X22), independent of `full` | `odin-htmx-starter.alexh95.com` |
| `full-vanilla` (CI only) | `app/cmd/full` built with `client=vanilla`, with no directory of its own (D7): everything `full` has, on both hosts. Its lab host's `/scripting/live` builds one widget in hyperscript, which is inert under the vanilla client; `lab` and `full` cover it (NEW) | SQLite | accounts / vanilla / full | all | as `full`'s, without hyperscript | as `full`'s | the second client implementation: the core and twinned-behaviour specs on the main host (D22) | CI |

Each `build.{sh,bat}` row names a profile's four families, as the two middle columns do (D7). **Each host has exactly
one root row** at `/` (D9, X5): `home` in `minimal`, `streams` and on `full`'s main host; the dashboard's page in
`skeleton`; `landing` in `lab` and on `full`'s lab host. The bundle column is derived from the mounted packages' `EXTS`
(D19, X29), never declared; every chat profile ships the four transports' extensions. `cmd/term-agent` (linux_arm64, the
Raspberry Pi agent) is not a profile. CI also builds generated selections (D26) as throwaway profiles. `full` and `lab`
(and so `full-vanilla`) grow milestone by milestone: each slice adds its feature's lines to the profile files of the
profiles that mount it (`routes.odin`, `main.odin`, `brand.odin`) when the slice lands (D44), so no profile ever imports
a package that doesn't exist yet. `full` gains houston-lab's pages at M4, when `cmd/full` first exists: notes,
dashboard, gallery, contacts and about (built at M1), lab, scripting and compat (built at M2) and landing (built at M3).

**Rejected.** PF §4.4's eight profiles (hello and minimal duplicate each other; `houston-vanilla` as a hosted twin).
CF §4.7's ten (landing, scripting and compat as separate binaries; `full-mem`, `notes-sql`). A directory of its own
for `full-vanilla`: the two copies could drift apart (LC §3). Leaving the starter demos out of `full`, which ANSWERS
F2 and round 3 ask it to integrate.

**Alex confirms:** no. The hosting names (Q2) and `bot` in `streams` (Q32, D31) were answered on 2026-10-25: as
recommended plus `houston-lab.alexh95.com`, and yes; `full` integrating every feature is ANSWERS #4 and F2, and round 3
settles that "every feature" means every catalog feature, the starter demos on houston-lab included.

### D25. What a profile is at hosting time

**Decision.** A profile is one binary and one container, served at the root of its own one-label subdomain. No binary
serves another profile's routes, and there is **no `BASE_PATH`**. `full` is the one profile with a second origin, for
its starter demos and lab pages (below).

The brief's URL shape is kept with redirects on `odin-htmx-starter.alexh95.com` that **strip the prefix**:
`/full` → `https://houston.alexh95.com/…`, `/minimal` → `starter-minimal`, `/streams` → `starter-streams`,
`/skeleton` → `https://odin-htmx.alexh95.com/…` (the public skeleton witness). `/minimal/notes?x=1` must land on
`https://starter-minimal.alexh95.com/notes?x=1` and bare `/minimal` on `https://starter-minimal.alexh95.com/`; the
proxy-config CI job asserts both forms for every alias (D40). PF §11.4's `redir /minimal* …{uri}` kept the prefix
(`{uri}` is the full request URI) and would 404.

Eval-capable `/scripting/*` and htmx-semantics-changing `/compat/*` run only on an origin that holds no sessions:
cookie `Path` does not isolate same-origin pages, so a script on `/scripting/` could fetch an admin page with the
session cookie attached (CF §4.8 reason 3). They are route classes with their own page bundles and CSP flag (S12),
served on two such origins:
- **the `lab` profile's** (`odin-htmx-starter.alexh95.com`): its identity is `anonymous`, so the whole origin is
  session-free;
- **`full`'s second host, `houston-lab.alexh95.com`** (ANSWERS F2, round 3). Alex asked that `full` implement every
  feature itself, with no dependency on another profile's container, the four lab-only extensions included, and to
  push back where there were important reasons not to. The one such reason, those pages beside Houston's sessions, is
  met by a second origin rather than by leaving them out: one binary, one container (`starter-full`), two origins.
  Round 3 settled what "every feature" covers: **every catalog feature**. Houston proper stays on
  `houston.alexh95.com`, and every starter demo and lab page goes on houston-lab.

`full`'s two hosts (LC §7):

| Host | Origin env | Identity | Root | Mounts |
|---|---|---|---|---|
| `houston.alexh95.com` (`main`) | `SITE_URL` | `accounts`: sessions, cookies | `home` at `/` (Today) | Houston's features (D29), `web.ROUTES` and `web.PUBLIC_ROUTES` |
| `houston-lab.alexh95.com` (`lab`) | `SITE_URL_LAB`, which `cmd/full/brand.odin` names (D10) | none: every viewer is the Guest, and nothing sets a cookie | `landing` at `/` (the catalog explorer) | `web.PUBLIC_ROUTES` and every starter demo and lab page: `notes`; the skeleton's `contacts` (its contacts/events console), `gallery`, `about` and `dashboard` (its page at `/dashboard`, its `/ui/ping` row); `lab` (the stream contract pages, `/lab/streams`); `scripting`; `compat` |

Round 3 names no page for one catalog feature, `about`, the skeleton's `/about`; it goes on houston-lab with the
skeleton's other demo pages (LC §7; X36). Houston proper has no "about the stack" page; its footer links to
houston-lab.

**How the hosts work** (LC §7, §16 `$L2 b`):
- **A row answers on the host whose table mounts it.** `front` (in `platform/app`, D4) picks the host by `Host` (the
  origin's host without the port, matched against `SITE_URL_LAB` as before) and routes only within that host's
  prefix map (D9). A request whose `Host` matches no origin goes to the main host, where the canonical-host 301 still
  applies. So `/dashboard` answers on houston-lab and 404s on Houston, `/chat` the reverse, `/scripting/live` only on
  houston-lab and `/healthz` only on Houston; `/term*` and `/admin*` 404 on houston-lab because no table there mounts
  them. Per-host tables replace the old `.Lab_Host` host filter in `front`.
- **Topics are per host too**: `/events` on houston-lab subscribes only to the families in `LAB_TOPICS` (the lab's
  stream demos), so a page there can't subscribe to Houston's topics even as a Guest (D13, NEW).
- **No identity runs on houston-lab** (its `identity` field is false): every request there is a guest, so each of its
  rows must declare `.Public`, and nothing on it sets a cookie (D20). Houston's `sid` is host-only (no `Domain`
  attribute, D35), so browsers never send it there, and the skeleton's `same_origin` guard refuses a write whose
  `Sec-Fetch-Site` is `same-site`, so a page on houston-lab cannot post to Houston
  (`SK/app/src/controllers/middleware.odin:222-242`).
- **`.Lab_Host` keeps its name and becomes a mount rule**: `scripting` and `compat` flag every row `.Lab_Host`, and
  such a row may be mounted only on a host where no cookie-setting identity runs: houston-lab, or `lab`'s one origin
  (identity `anonymous`), never Houston's. The pages keep their page bundles (Scripting, Compat_Htmx2, Compat_Alpine)
  and `.Nonce_Csp` on `/scripting/*` (D19, D20). A WS upgrade on houston-lab checks `Origin` against `SITE_URL_LAB`
  instead of `SITE_URL`.
- **The boot checks** (D5 check 4), per host: a `.Lab_Host` row on a host with a cookie-setting identity; a row with
  any perm but `.Public` on a host with no identity; a second host whose env var is unset or names `SITE_URL`'s host.
- **One root per host** (D9): `home` on Houston, `landing` on houston-lab, each written in `full`'s `routes.odin`.
  The dashboard's page is mounted there at `/dashboard`, inside dashboard's own prefix.
- **The demo data** lives in Houston's SQLite file, in the demo features' own tables (contacts keeps the skeleton's
  table names, D16). Each is capped, by `NOTES_CAP` 500 and `CONTACTS_CAP` 2000 (D10, X38), and reset nightly at 04:00
  local time by the job rows `notes.reset` and `contacts.reset`, which `full`'s `routes.odin` writes as it writes the
  root: whether a feature's data is a capped demo is a fact about the profile, not the package. A feature's `reset`
  drops its rows and reseeds them as `SEED=1` does. The `skeleton` profile stays uncapped, so parity and the 20k-row
  scale scenario are untouched (X38).
- **The pages there** use the bare lab layout (no bell, no account menu) and their own nav, `LAB_NAV`, send
  `X-Robots-Tag: noindex` (the `lab` profile's origin holds the indexed copy), and link to Houston by absolute URL,
  so every crossing is a full navigation. Houston links to them from its footer (D29).
- **Two hosts share one process and one SQLite file.** A crash in a demo page is a crash of Houston's process, which
  the crash model contains as it contains any other (D15). This is F2's one-binary, two-origins choice, unchanged.

`lab` stays an independent witness: it serves its own copy of those pages from its own binary and container, and
neither profile depends on the other's container (ANSWERS F2).

| | One binary, route-prefixed profiles | **Container per profile, one-label subdomains (chosen)** | Container per profile behind paths |
|---|---|---|---|
| Representative footprint and perf | no: `/minimal` isn't a minimal binary (08 §6.1) | yes: the parity witness is the real `skeleton` binary | yes |
| App change | none | none | `BASE_PATH` through every href, hx-* URL, src, connect URL, cookie `Path` and the sitemap (08 §6.2) |
| Root-only files (robots.txt, BingSiteAuth.xml, the IndexNow key) | one set for all | one set per profile | can't live under a mount |
| Isolation | shared cookies, storage, the 6-connection pool | host-only cookies, separate storage | shared origin |
| Cross-profile links | boosted navigation breaks across bundles and CSP (05 §9, 11 §6.4) | always full navigations | hand-marked `hx-boost="false"` |
| Restart and rollback blast radius | all profiles at once | per profile | per profile |
| Cost on apollo | one process | about 6–9 MiB idle each (08 §6.5) | same |

**Rejected.** One binary mounting `/minimal` and `/full` (not representative). Path mounts with `BASE_PATH`, an
`html.url` helper and a URL-literal lint (CF §4.8): one cross-cutting rule with a long regression tail, flagged in
08 §6.2 and 09 §5. Labs inside Houston (RF §4.5), that is, on Houston's own origin beside its sessions. Houston
linking to the `lab` profile's pages instead of serving them (ANSWERS F2's other option): `full` would then depend on
another profile's container. Reading F2's "every feature" as the four lab-only extensions' pages only (this
decision's first reading, which round 3 replaced). The `.Lab_Host` gate as a flag filter in `front` over one route
table: per-host tables say which rows answer where, and the flag stays only as a mount rule (LC §13).

**Alex confirms:** answered 2026-10-25: Q2, as recommended plus `houston-lab.alexh95.com`; `full` implements every
feature itself (ANSWERS #4, F2), and every catalog feature, with the starter demos and lab pages on houston-lab
(ANSWERS round 3).

### D26. The generator

**Decision.** `tools/init` keeps the skeleton's plan-then-commit engine: every edit is planned in memory, every literal
edit must match, any miss aborts with nothing written, then `[y/N]` (`SK/tools/init/plan.odin:52-268`). It changes
from overlay to compose (09 §4.6).

- **Commands**: `--list [--json]` (features, family members, switched implementations, dependencies, sizes, SQLite
  needs; the JSON is committed as `docs/catalog.json`, `#load`ed by the landing feature, and checked fresh in CI);
  `--explain <features>` (closure and plan, writes nothing); `--profile <p>`; `--features a,b`; `--add <f>` and
  `--without x,y` (edit the profile in place); the family commands `--store sqlite|memory`, `--identity
  accounts|envadmin|nick|anonymous`, `--client`, `--theme` (they edit the profile's row in `build.*` and
  `ols.json`); `--dry-run`; `--verify` (on by default: apply the plan to a scratch copy, build through `build.*`, run
  `tools/check profile`, and compare `bin --features --json`, the profile, the family members' `NAME`s and the route
  ids per host, with the plan before touching the tree); `--pairwise --seed <n>` (D37). `--minimal` stays as an alias
  of `--profile minimal`. The skeleton's naming flags (`--wordmark --suffix --repo --site`) stay unchanged; they write
  `cmd/app/brand.odin` (X6). **The per-axis `--impl` commands and `--rich` go**: every transport and both bot
  backends are always linked, the games catalog follows `GAMES_API_URL`, and the wiki and video follow the store
  family (D8), so no axis is left to pick per feature. **`--emit --like` goes** with D7's byte check.
- **Lean defaults**: the memory family (so the wiki is the read-only docs, video the manifest scan and search a
  `contains_ci` scan), the `nick` identity unless a feature needs accounts (or `anonymous` when the selection has
  `scripting` or `compat`, whose pages need a session-free origin, D25; NEW), the vanilla client, the lite theme,
  and `home` as the root. With `GAMES_API_URL` unset the games catalog is static. So `init myapp --features chat`
  writes chat's hello world (D27).
- **Refusals with advice**: "contacts has no memory store; use --store sqlite" (D18). It also refuses two roots on
  one host (D9, X5).
- **What it writes** (LC §10):

  | File | When | What |
  |---|---|---|
  | `app/cmd/app/{main,routes,routes_test,brand}.odin` | a new project | D7's four files for the selection: imports, `init` calls in dependency order, `start` and `drain` calls, `store_sqlite.open` and one `migrate` per SQLite-backed store (SQLite family only), the host tables with the root row, `TOPICS`, `JOBS`, `HOME_CARDS`, `FIND_SOURCES`, `BUNDLE_EXTS`, `HOSTS`, the nav |
  | `build.{sh,bat}` | a new project | one profile, `app`, with the selection's four families |
  | `ols.json` | a new project | the four collections pinned to the project's families |
  | `UPSTREAM.md`, `.github/workflows/ci.yml`, `CHANGELOG.md`, `TODO.md` | a new project | as before: `UPSTREAM.md` holds the upstream URL, version, commit, exact command line, selection, and the vendored odin-http's base and F-changes from `app/vendor/odin-http/UPSTREAM.md` (10 §6); the CI matrix is trimmed to `app`; a fresh CHANGELOG and TODO |
  | the four profile files, `build.*`, `ols.json` | `--add <f>`, `--without <f>`, the family commands | edits in place |

  It deletes the unselected `features/*`, their `app/stores/*/<f>/`, `e2e/tests/<f>` and `load-tests/scenarios/<f>`,
  and every `cmd/*` but `cmd/app` (`--without` deletes the same for one feature); removes the `Perm` and `Behaviour`
  groups of deleted features (D35, D22; literal edits, abort on miss); and renames identity tokens from
  `tools/init/UPSTREAM`. It keeps the skeleton's closing checklist ("Done. Next:", `SK/tools/init/main.odin:86`
  onward) and leftover report.
- **Edits are planned against the parsed file.** `core:odin/parser` finds each table literal and the call block, and
  each edit is a literal insertion or deletion of one line: an import, a mount line per host table, a `TOPICS` or
  `JOBS` line, an `init`, `start` or `drain` call, a `migrate` line, a home-card or find-source row. If a file doesn't
  have the shape the plan expects, the engine aborts with nothing written (`SK/tools/init/plan.odin:228-239`) and
  says which file to fix by hand (NEW: not prototyped).
- **In CI** the generator job runs `tools/check profile` on every committed profile, and keeps its singleton and
  pairwise runs (D27, D37).

A sample `--explain` output (CF §4.9 shape): features, family members, bundle extensions, route counts per host,
removed and written paths, and the `--verify` result.

**As built (M2).** Where the lines come from was left open; the answer is **the committed profiles** (NEW). A
feature's lines (its mounts, `TOPICS` and `JOBS` lines, nav entries, the copy its `init` takes, and `main`'s
statements that name it, with their phase) are taken as a committed profile that mounts it writes them, its donor;
the platform's lines are written for the families; `BUNDLE_EXTS`, `PAGE_BUNDLES` and `HOME_CARDS` come from the
declarations. Nothing is declared for the generator's sake: no manifest per feature, no profile-line constants in the
packages. The profiles are hand-written and held to `tools/check profile`, and check refuses a `ROUTES` no profile
mounts, so every feature has a donor; `odin test tools/init` composes each committed profile again from its own
selection and holds it to its lines, so a profile edited into a shape the generator can't take fails there. Two
brand fields are a feature's: `search` (the donor's, when its href is the feature's page) and `overlays` (when the
feature's source targets `#overlay` or `#toasts`). Rejected for v1: a `PROFILE_LINES` table in each web package (a
second copy of what the profiles already say, which the profiles would drift from) and a template per feature in
`tools/init` (the same, further away). The `--without x,y` list takes one feature a run; `--pairwise` waits for D37's
combination matrices.

**Rationale.** 01 §8; 09 §4.6; CF §4.9; RF §4.4; ANSWERS round 3 (the generator writes the hand-written profile
files for new projects and edits them on add or remove); LC §10.

**Rejected.** More whole-file overlays (01 risks: the overlay already duplicates the layout shell). CF's `profiles.odin`
table. A generator that emits each profile's `main.odin` and `routes.odin` from a `SELECTION` line, checked by an
`--emit --like` byte comparison (load-bearing for every profile, and a second syntax; LC §13).

**Alex confirms:** answered 2026-10-25 for the profile files: the generator writes them for new projects and edits
them when a feature is added or removed, and CI checks their consistency (ANSWERS round 3); otherwise no.

### D27. Hello world for any selection

**Decision.** A hello world is the leanest families (D26's lean defaults) plus a root; there are **no hello
packages**, and each feature runs on its env defaults. Every feature with a page exports a `home_card`, and `main`'s
`HOME_CARDS` lists the selection's cards in order (D6). Every generated project has one root per host: `home` unless
the selection includes `dashboard` or `landing` (D9, X5, X28). Where `home` is the root, a selection boots to a page
with one working card per selected feature (PF §4.1). The skeleton's dashboard stays byte-identical, so it shows no
home cards; the cards appear only where `home` is the root. A feature whose leanest selection grows beyond about 400
lines gets a leaner real implementation (as chat has its memory store), never a demo-only copy. CI builds every
named profile per push, one rotating singleton `--features <f>` per push and every singleton nightly (D37).

**Chat's hello world**: `init myapp --features chat` writes chat, notify (its hard dependency, D6) and home, and boots
to Today with chat's card over all four transports, on the memory store and the nick identity (LC §10). It is larger
than the old poll-only one: the bell comes with it, and ws, sse, hx-multipart and ptag ride in its bundle and binary
(LC §12 items 5 and 7; the size growth is not measured yet).

**Rejected.** PF §4.1's hello variant per feature as separate code with mandatory `@<f>:hello` specs (§3.9, §10.7):
a second implementation of every feature. A poll-only chat hello world through generated per-profile dispatchers
(D8's rejection).

**Alex confirms:** no.

---

## G. The showcase: Houston

### D28. Houston: identity

**Decision.** **Houston, the crew's home channel**: the household app on apollo where Alex's friends and family
talk, ask the bot, watch home videos, play spark's games and plan things, and where Alex runs the server from one
admin area (PF §1.2). It is the `full` profile, branded in `cmd/full/brand.odin`, under D3's tenets. Scale target:
5–50 accounts, a handful of concurrent viewers, bursts during gatherings. UI labels are plain words; Apollo vocabulary
appears only in product names (Comms, Capcom, Watch, Arcade, Logbook, Checklists, Go/No-go, Calendar, Visitor log,
Control).

**Rejected.** RF §1's "mission control" feature inventory with the skeleton demo in its nav; CF §1's Patchbay home-lab
hub.

**Alex confirms:** answered 2026-10-25: Q3, Houston ("I like it", ANSWERS #6).

### D29. Houston: information architecture and feature list

**Decision.**

| Nav label (brand.odin) | Feature package | Prefixes | What it is for | Store family and switched impls in `full` | Milestone |
|---|---|---|---|---|---|
| Today | `home` | `/` | one page of cards from every feature | — | M4 |
| Comms | `chat` | `/chat` | rooms, DMs, presence, typing, receipts, moderation | SQLite; transports ws, sse, poll, multipart (one switch, D8) | M6 |
| Inbox (bell) | `notify` | `/notify` | mentions, DMs, assignments, reminders, results | SQLite | M6 |
| Capcom | `bot` | `/bot` | the AI bot: mock now, llama.cpp on the LAN later | backends mock and llama (one switch, D8); SQLite | M7 |
| Watch | `video` | `/video`, `/media` | library, player, captions, resume | SQLite (the metadata) | M9 |
| Arcade | `games`, `c4` | `/games`, `/c4` | spark's games embedded with live player counts and leaderboards; connect-four | `catalog_static`, then `catalog_api` once `GAMES_API_URL` is set (D34) | M10 |
| Logbook | `wiki` | `/wiki` | house manual, recipes, trip notes, the starter's docs | SQLite (docs seeded read-only) | M8 |
| Checklists | `lists` | `/lists` | shared live lists with a board view | SQLite | M8 |
| Go/No-go | `polls` | `/polls` | quick polls with live results | SQLite | M8 |
| Calendar | `calendar` | `/calendar` | gatherings, RSVP, ICS feed | SQLite | M10 |
| Visitor log | `guestbook` | `/guestbook` | public notes, moderated | SQLite | M10 |
| Search (Ctrl-K) | `find` | `/find` | global search and the command palette | FTS5 per source, over `main`'s `FIND_SOURCES` (D6) | M8 |
| Status | `status` | `/status` | public health of the parts | — | M5 |
| Me | `accounts` | `/account`, `/login`, `/logout`, `/register`, `/invite` | profile, sessions, TOTP, preferences | the `accounts` identity | M4 |
| Control | `accounts`, `audit`, `ops`, `jobs`, `modules`, `bot`, `dbview`, `term` | `/admin/accounts`, `/admin/audit`, `/admin/ops`, `/admin/jobs`, `/admin/modules`, `/admin/bot`, `/admin/dbview`, `/admin/term` | Alex's area (`/admin/bot` holds the bot's default backend, D31) | — | M4–M11 |
| Console | `term` | `/term` (agent at `/term/agent`) | the Raspberry Pi console, LAN-only | line and PTY modes | M11 |
| (shared) | `uploads` | `/uploads` | chunked uploads for chat images, avatars and video | SQLite (X13) | M6 |
| Control | `devices` | `/admin/devices`, `/devices` (the feed) | the device registry, generalising `/admin/term`'s device tokens to every device, and a plain-text `text/event-stream` (unread count, presence, next event, bot health) for screens that can't render HTML (D3's row 8) | SQLite | M14 (optional) |
| Cams | `cams` | `/cams` | each camera's MJPEG stream, pulled once and fanned out to members as `multipart/x-mixed-replace`, which a plain `<img>` renders with no JS; LAN-only and members-only first | — | M14 (optional) |
| (no nav: a device's own URL) | `wall` | `/wall` | the wall and TV dashboard: a kiosk view of Today, signed in by a device token | — | M14 (optional) |
| Lab (a footer link to `houston-lab.alexh95.com`) | `landing` (its root), `notes`, `dashboard` (at `/dashboard`), `gallery`, `contacts`, `about`, `lab`, `scripting`, `compat` | their own prefixes (D9), on `houston-lab.alexh95.com` only | every starter demo and lab page, session-free: the catalog explorer, the skeleton's demos with their data capped and reset nightly, the stream contract pages and the four lab-only extensions' pages (D21, D25; ANSWERS F2, round 3) | SQLite for the demos | M4 (built at M1–M3) |

Houston proper stays on `houston.alexh95.com`; the last row is `full`'s second host, whose pages are not Houston's
product and carry no session (D25; ANSWERS round 3). The three M14 rows join `full` when M14 lands, after M12 (Q33:
yes, 2026-10-26; X42; D44); the nav label Cams and the package name `wall` are NEW.

**Layout**: topbar (wordmark · nav · `/find` active search · the notifications bell with an hx-targets badge · theme
picker · account menu), `<main>`, `#overlay`, `#toasts` (`hx-preserve`, `aria-live`), `#live` (the page stream).
Guests see the Today landing, Arcade, public Watch, public Logbook, the Visitor log, Status and Sign in. Every list
item has a stable id (`m-<id>`, `item-<id>`, `job-<id>`) and is swapped by upsert; toasts are OOB carriers into
`#toasts`; overlays use `<dialog>`.

**Journeys** (PF §6.3, with generic routes): a guest lands on Today, plays brick in the Arcade (facade → iframe on
desktop, link-out on a phone), tries the bot in mock mode, signs the Visitor log, follows an invite link to `/register`.
A member works through Today, Comms (an @mention lights the bell everywhere), a Go/No-go, a packing checklist with
assignments, an RSVP with the ICS feed on a phone, resuming a video, the bot with Stop, "Invite crew" from a game, and
Ctrl-K search. A moderator approves visitor notes, deletes a message to a tombstone with a reason, mutes a user and
locks a room. Alex (admin) bootstraps with `ACCOUNTS_ADMIN_HASH` and TOTP, issues invites, manages accounts, watches
`/admin/ops`, runs and cancels jobs, reads `/admin/modules`, switches the bot default on `/admin/bot`, registers the Pi
and opens a console after step-up while a family member watches read-only.

**Alex confirms:** no; the M14 rows follow Q33 (answered 2026-10-26: yes).

### D30. Instant messaging (`chat`)

**Decision.**
- **Model** (07 §1): rooms (public, private, announcements), DMs, membership, presence, typing (at most one event per
  2 s, expiring after 5 s, memory only, a `.Latest` topic), read receipts (`intersect once` → `POST
  /chat/r/<slug>/read?upto=`, never a GET: preloads can't be told apart, 04 §9), mentions → `notify_web.send` (a direct
  import, D6), edits within 10 minutes, delete own, moderation (delete → tombstone, mute, kick, lock, slow mode), image
  attachments through `uploads`, `@bot` published on `bot.ask:<room>` (D6), 2,000-rune bodies cut by rune.
- **Rolling buffer and truncation**, whichever cap hits first, pinned messages exempt (at most 20 per room): rooms
  500 messages / 7 days, DMs 1000 / 30 days, announcements 100 / 365 days; room owners and admins may set up to
  5000 / 90 days (Q19). With SQLite: chunked deletes on the writer task every 50 inserts per room, plus a 60 s age
  sweep job; FTS triggers are budgeted at 6.4 ms per 1000 rows (12 §9). An in-memory ring in both modes keeps the
  last 100 messages per room for first paint and replay, under a global `CHAT_RING_BYTES` of 16 MiB that evicts the
  oldest rooms' tails; in memory mode the ring is the history. When "load older" passes the oldest kept message, the
  log shows "Older messages were removed (this room keeps the last 500 messages or 7 days)". Moderation deletes are
  tombstones; the audit log keeps who and why, never the body (07 §1.2).
- **Ids and markup**: rowids with SQLite, `<epoch>-<seq>` in memory; `<article id="m-<id>" data-seq="<12-digit
  zero-padded id>" data-author="<uid>">` inside `<div role="log">` (D14). Every room route is keyed by slug,
  `/chat/r/<slug>/...`, `read` included; DMs get an opaque generated slug (X12).
- **Four transports, all full implementations**, linked into every chat profile and chosen per request by one switch
  in `chat_web` (D8), offered to users as a "Connection: Auto / WebSocket / Streaming
  / Polling / Multipart" setting, a compatibility mode for networks whose proxies kill WebSockets:

| | Client | Server | Resume |
|---|---|---|---|
| A WS (default) | `hx-ws:connect="/chat/r/<slug>/ws"` on the room pane; `<form hx-ws:send>` composer | JSON in (the 04 §4.4 frame shape); escaped `<hx-partial hx-swap="upsert sort">` out | snapshot of the last 50 on (re)connect; upsert dedups (as built in M3: the page's version as the first frame, what changed since it) |
| B SSE + POST | the room topic on `#live`; `hx-post` composer with `hx-pending` | POST → writer task → commit → the bubble in the response and on the hub | `Last-Event-ID`, `after`, then `@rowid` keyset replay (D13) |
| C poll + ptag | `hx-get="/chat/r/<slug>/since" hx-trigger="every 2s" hx-ptag` | 304 when nothing is new | the ptag (last rowid) |
| D multipart | `hx-multipart:connect="/chat/r/<slug>/parts"` | one part per event with `HX-Target`, `HX-Swap`, `HX-Part-ID` | `HX-Last-Part-ID` |

  "Auto" is WS, falling back to SSE after two failed connects (the `htmx:ws:error` event detail is UNVERIFIED: spike
  at M6).
- **Fan-out**: each message is rendered once. Per-viewer differences come from CSS (`<body data-me>` against
  `data-author`) and from an on-demand message menu (`GET /chat/m/<id>/menu`, rendered with the viewer's perms).
  Unread counts for other rooms go to `notify.user:<id>` as hx-targets updates of `.unread-<room>`.
- **Limits**: 5 messages per 10 s per user, burst 10; WS frames 20 per second per connection (close 1008); 64 KiB WS
  messages; 2 concurrent uploads per user; slow mode per room.

**As built (M2)**, public rooms on the memory store with all four transports (PLAN §14.1's as-built note has the
rest). Three changes from the above. CSS can't compare two attributes, so "mine" is marked on the client: the log
carries `data-me`, and `AutoScroll` adds `.mine` where a child's `data-author` matches (the reader's own "is typing"
too, which CSS then hides). Unread counts go out of band on the class selector (`innerHTML:.unread-<slug>`), which
core htmx swaps into every match, so no hx-targets. And no `data-seq`: hx-upsert compares with `localeCompare(…,
{numeric: true})`, so the `id`s sort as numbers; memory ids are one number, the boot time in ms × 10⁶ plus the
sequence, so a page from before a restart never sees a new message take an old one's id.

**Rejected.** CF §6.3's ids allocated before persistence and its `<li>` markup; PF §6.4.1's hub skipping the author's
connections.

**Alex confirms:** yes (Q19, retention defaults: default stands (not overridden)).

### D31. The AI chatbot (`bot`)

**Decision.** Only the front-end and back-end interfaces and the bindings matter now; the mock answers.

```odin
Bot_Turn    :: struct { role: Bot_Role, text: string }
Bot_Request :: struct { conv_id, user_id: i64, system: string, history: []Bot_Turn, max_tokens: int, temperature: f32, stop: []string }
Bot_Event   :: union { Bot_Token, Bot_Done, Bot_Error, Bot_Queued }   // tokens coalesced to at most 20 Hz
Bot_Done    :: struct { stop: Bot_Stop, tokens, ms_first_token, ms_total: int }   // llama's timings shape
Bot_Health  :: struct { state: enum u8 { Ready, Loading, Sleeping, Offline, Mock }, slots_total, slots_busy, queued: int, model: string }
Bot_Sink    :: struct { user: rawptr, loop: ^nbio.Event_Loop, gen: u64, on_event: proc(user: rawptr, gen: u64, ev: Bot_Event) }

// bot_web: both backends are linked, and one switch per operation calls the chosen one directly (D8)
Backend :: enum u8 {Mock, Llama}

start :: proc(b: Backend, req: Bot_Request, sink: Bot_Sink) -> Bot_Gen_Id {   // events arrive on sink.loop via next_tick
	switch b {
	case .Mock:  return bot_backend_mock.start(req, sink)
	case .Llama: return bot_backend_llama.start(req, sink)
	}
	return {}
}
// health(b) -> Bot_Health and cancel(b, id) (idempotent) are the same shape; the sink stays a continuation.
// TODO(Alex, M7): llama.cpp on apollo's GPU (below). Set BOT_BACKEND=llama and BOT_LLAMA_URL=http://<APOLLO_LAN_IP>:<LLAMA_PORT>;
// the binding never assumes a port (07 §2.2).
```

- **`backend_mock`** (default): a timer chain on the stream's loop emits canned "under construction" / "TODO" lines
  word by word with 30–120 ms jitter; `BOT_SEED` makes it deterministic and `BOT_DELAY_MS=0` fast; its `Bot_Done`
  stats have llama's shape.
- **`backend_llama`** (binding in place, model later): `POST {BOT_LLAMA_URL}/v1/chat/completions` with `stream:true`
  through `platform/stream/client` on the llama worker pool, sized from `/props total_slots`; it parses chunked SSE
  `data:` lines, `choices[0].delta.content` and `[DONE]`; health from `/health` (503 = loading) and `/props
  is_sleeping`; deadlines connect 2 s, first token 30 s, idle 15 s; `cancel` closes the upstream socket, which is what
  stops llama.cpp's generation (07 §2.2); plain http on the LAN, no OpenSSL. `tools/fakellama` (Odin, on the
  starter's own SSE encoder) tests the parser with chunk boundaries inside `data:` lines, `[DONE]`, an OAI error and a
  503 "Loading model".
- **The bot host** (X41; DEVICES-SUMMARY): apollo's spare GPU (`<APOLLO_GPU>`) runs llama.cpp's official Vulkan
  server image, in a compose project that Alex owns and agents never restart, apart from the starter's stack. It
  publishes `<LLAMA_PORT>` on the LAN with an API key, which `BOT_LLAMA_KEY_FILE` carries, so `BOT_LLAMA_URL` =
  `http://<APOLLO_LAN_IP>:<LLAMA_PORT>`. It fits a current 4–8B instruct model at Q4 with about 8k of context; tokens/s
  are measured with `llama-bench` at M7 (est. 40–60, UNVERIFIED (M7)). It costs the box about one CPU thread (`cpus:
  1.0`), and the GPU's power only while a reply is being written. Setting it up is Alex's M7 step (D44). The dev PC's
  bigger GPU is for occasional smoke tests only, never Houston's always-on backend. A gaming laptop with a 6 GB GPU
  is the fallback only if apollo's GPU route fails (PLAN §20.8).
- **Choosing the backend** (D8): per request among the healthy ones, with guests always on mock; the default is
  `BOT_BACKEND`, which an admin changes at run time on bot's own `/admin/bot` (in memory only, audited, reset on
  restart), a page bot owns by D9's prefix rule. `modules` shows the value, which bot pushes to `platform/obs`, and
  links to the page, so `modules` never imports bot (D6). Every bot response carries `x-impl: bot.backend=<name>`.
- **Front-end contract** (PF §6.4.2): `<form hx-post="/bot/c/<id>/ask" hx-target="#c-log" hx-swap="beforeend"
  hx-disable="find button[type=submit]">` with `hx-pending` echoing the question and the browser indicator on. The
  response is `text/event-stream`: (1) the assistant shell `<article id="m-<mid>">` with a Stop button (`hx-post
  /bot/gen/<gid>/stop`); (2) unnamed events of escaped token text as `<hx-partial hx-target="#mb-<mid>"
  hx-swap="beforeend">`, with `event: hx:release` after the first token; (3) a final `<hx-partial
  hx-target="#m-<mid>" hx-swap="outerMorph">` carrying the depth-capped markdown render and the stats; (4) end. A
  queued generation shows "Queued (#2)"; the health badge rides `bot.health`. Delivery B sends the same four as
  multipart parts plus `#conv-title` and `#usage` parts. Room mode (D6): `@bot` in a chat room → chat publishes on
  `bot.ask:<room>` → bot's static row starts the backend and streams upserts of `#m-<id>` to `chat.room:<room>`, so
  every member sees it → the finished answer goes on `chat.reply:<room>`, whose row in chat stores it as a message
  from the bot. Neither feature imports the other.
- **Policy**: conversations are stored for their owner only, admins see counts and timings (Q20); guests get mock
  only, 5 per hour per client id; members 1 concurrent generation and 30 per hour; no tools or function calling.
- **Place in the starter** (X32): the brief's "not part of the starter" is read as: no model, no llama.cpp and
  nothing AI ships. The `bot` package (the chat UI, the stream contract, the backend switch, the llama.cpp
  binding, the mock) is exactly what the brief calls relevant, so it stays a catalog feature and is in `streams`
  (D24). Alex confirmed this reading on 2026-10-25 (Q32: yes).

**Alex confirms:** yes (Q20: default stands (not overridden)); Q32 answered 2026-10-25: yes, a catalog feature, in
`streams`; the backend switch, its default on `/admin/bot` and room mode over a topic row answered the same day
(ANSWERS round 3). The bot host on apollo's GPU is Alex's decision of 2026-10-25 (DEVICES-SUMMARY, X41), and its
compose project is Alex's M7 step. An optional real-model smoke against the dev PC's `llama-server` happens only when
Alex starts it.

### D32. The terminal console to the Raspberry Pi

**Decision.** Built in this order, with the VT parser **outside the server process**:

1. **T1 line mode** (ships first). `cmd/term-agent` (Odin, linux_arm64, built on GitHub's `ubuntu-24.04-arm` runner
   because Windows can't link Linux targets, 09 §6.4) runs on the Pi as an unprivileged systemd unit
   (`deploy/pi/term-agent.service`) and dials out to `ws://<APOLLO_LAN_IP>:8120/term/agent` (the stack Caddy, `Host:
   houston.alexh95.com`; LAN-direct, never through NPM) with a device token; it needs no inbound port on the Pi
   (07 §3.2a). It runs only allow-listed argv entries (`uptime`, `df -h`, `vcgencmd measure_temp`, `systemctl status
   <unit>`), never a shell, and enforces its own local allow-list as well. Output streams to the browser as a POST →
   SSE one-shot into `<pre role="log">`. **Delivery** (Q30, X15): the `release` workflow attaches the linux_arm64
   `term-agent` binary and its SHA-256 as a GitHub release asset, and Alex copies it to the Pi. The systemd unit
   reads `/etc/houston/term-agent.env` as an `EnvironmentFile`: `TERM_AGENT_URL`, `TERM_AGENT_HOST`, and
   `TERM_AGENT_TOKEN_FILE` → `/etc/houston/term-agent.token`, mode 0600. The agent sends its version in `hello`, and
   `/admin/term` flags outdated agents.
2. **T2 PTY with the VT emulator in the agent**. The agent spawns a PTY (`posix_openpt/grantpt/unlockpt/ptsname`,
   `fork/setsid/execve`, 07 §0.6) and parses VT with `features/term/vt` (the DEC ANSI state machine, UTF-8, wide
   characters, alt screen, scroll regions, SGR to classes; 1,500–2,500 lines, 07 §3.3). It sends binary frames
   `hello`, `open`, `input`, `resize`, `grid` (dirty rows as style runs, plus the cursor), `raw` (output bytes, for
   the recording), `close` and `ping`. The server keeps a bounded cell grid per session in `features/term/grid` (a
   validated frame decoder, the model and the row renderer), coalesces dirty rows every 16–33 ms into `<hx-partial
   hx-target="#t<s>-r<y>" hx-swap="outerHTML">` frames over the browser's `hx-ws` (07 §3.3: 80×24 in 53 µs, 200×50
   in 274 µs), and gives a watcher the current grid at once. Input comes from a labelled `<textarea>` with `TermKeys`
   feeding a hidden `hx-ws:send` form (firing on a custom trigger is UNVERIFIED: spike at the M11 start, fallback a
   30-line app.js sender); `MeasureTerm` sends resizes.
3. **T3** watch mode (`Term_Watch`, read-only, over the session's SSE topic `term.session:<id>`), asciicast v2
   recordings **written by the server** from `raw` frames (audit integrity; downloadable with hx-download; kept 30
   days or 1 GiB in total, whichever comes first, X10), and a per-device kill switch.

**Why.** 13 §2.1 places a server-side VT emulator outside the server process ("in a subprocess if ever built"). A
parser bug or hang in the agent kills only the agent, which systemd restarts; it never takes Houston down through the
watchdog. The server still owns what watchers see and what is recorded. xterm.js is not shipped: 488 KB of second
runtime, and its DomRenderer needs `style-src 'unsafe-inline'` (11 §5.2). **Fallback** if the agent approach fails its
M11 spike: the same `vt` package behind `houston --worker vt`, a same-binary subprocess on apollo (13 §2.2: 22.7–28 µs
per call on Windows, 59–71 µs on WSL2, paid once per 16–33 ms batch).

**The devices** (X41; DEVICES-SUMMARY): the target is Alex's **Raspberry Pi 4**, on 64-bit Pi OS Lite and wired. A Pi
3B+ is the second device for multi-device tests (two agents, two device tokens). Pi Zero class boards can't run the
agent: they are ARMv6 and 32-bit, and `term-agent` is linux_arm64 only.

Before the Pi exists, CI runs the agent in the Linux container against `/bin/sh`, plus a replay agent that plays
recorded vim, less and htop byte streams (07 §3.7). The terminal is LAN-only (`.Lan_Only` on `/term*` and
`/admin/term*`; NPM denies `/term/agent`); beyond the LAN, a WireGuard overlay with plain ws inside (Q9). Hardening is
in D35.

**Rejected.** An in-process server-side VT emulator (RF §6.5, silently against 13 §2.1). An xterm.js lab (Q8). SSH from
the server (a C dependency, 07 §3.2b). ttyd.

**Alex confirms:** answered 2026-10-25: Q8, agent-side VT ("That's sensible", ANSWERS #9). Q12: default stands (not
overridden); Q9, Q30: default (not yet raised). The M11 hardware steps are Alex's.

### D33. Video (`video`)

**Decision.**
- **Library** `/video`: a grid with infinite scroll (`intersect once`), `hx-preload` on mouseover, history-cache.
  **Player** `/video/<id>`: `<video controls preload="metadata" poster>` with an HLS `<source>` first and MP4 second,
  so browsers pick with no hls.js (07 §4.2: Chrome 156 plays native HLS, MP4 and AV1 WebM from the Odin Range
  server); WebVTT captions, server-rendered chapters, resume (the `Resume` behaviour posts every 10 s; the page renders
  `data-resume`), up next.
- **Media route** `/media/v/<sha256>/<file>` with the strict pattern `[0-9a-f]{64}/[a-z0-9_.-]+`: single Range, 200,
  206, suffix, 416, HEAD, If-Range and ETag over `stream_sendfile` with a manual content-length
  (`_response_write_heading(res, -1)`, 07 §0.2), cached `immutable`, CORP same-origin. Members-only videos use
  HMAC-signed URLs `?exp=&sig=` (10 minutes).
- **Content pipeline**: offline encoding on the dev PC (`tools/transcode` runs 07 §4.3's verified ffmpeg recipes:
  H.264 faststart MP4, HLS VOD, AV1/Opus, poster, VTT sprites) into `VIDEO_DIR/v/<sha>/` with a `meta.json`; the app
  scans and imports it. Uploaders may upload web-ready MP4 or WebM through `uploads`, with no transcode. ffmpeg never
  goes into an image (S21). In-app transcoding with a host ffmpeg is Q21's non-default option and is not built (X27).
- **The catalog follows the store family** (D8): the memory member is `catalog_file` (the manifest scan, no SQLite),
  the SQLite member holds the video metadata (library, visibility, watch progress); each store's `IMPL` constant
  keeps the name. Upload sessions belong to `uploads` and its own stores, not to video (X13).
- **Public stage**: optionally, a bunny.net pull zone in front of `/media` for public videos only (Q26). The home
  uplink is not a binding stage-2 trigger, so public video from home is plausible at family scale and the CDN is
  optional (D41, X41). Never Cloudflare's CDN, whose terms forbid video (S20).

**Alex confirms:** yes (Q21: default stands (not overridden); Q26: default (not yet raised)).

### D34. Games (`games`, `c4`)

**Decision.**
- Per S22: `/games` renders the catalog server-side from `games.Catalog`. Both members are pure Odin and both are
  linked; `games_web` reads `GAMES_API_URL` at `init` and switches (D8): `catalog_api` when it is set, `catalog_static`
  otherwise (a repo JSON of brick, gridlock and backpulse, overridable with `GAMES_CATALOG`). So `full` runs
  `catalog_static` until spark's `GET /api/games` lands (SP1) and `GAMES_API_URL` is set. `/games/<g>` is a
  click-to-play facade; its button `hx-get`s the player fragment, an `<iframe src="{GAMES_URL}/play/<g>/?embed=1"
  allow="xr-spatial-tracking; fullscreen; autoplay; gamepad; screen-wake-lock; clipboard-write" loading="lazy">`. On
  `(pointer: coarse)` CSS shows a "Play full screen" link-out instead (06 §2.2).
- **WebXR in the embed** (X41; DEVICES-SUMMARY): `xr-spatial-tracking` in the `allow` list lets the VR headset play
  spark's WebXR games inside Houston's frame, and `games-frame.spec` gains a WebXR spec (M10). Like fullscreen,
  autoplay and gamepad, it gets no entry in D20's `Permissions-Policy`, where a restrictive one would block it for the
  frame (NEW).
- **Previews are proxied same-origin** (`/games/p/<g>.<crc>.png`, fetched at refresh, 200 KB cap), so `img-src` stays
  `'self'` and visitors' IPs never reach the games host (PF §6.4.5).
- A poller on one loop reads `/ws/<g>/healthz` `players` every 5 s and `/api/scores/<g>` every 30 s and publishes the
  diffs to `games.players` (`.Latest`) and `games.board:<g>` (upsert of the top 10, `key:data-score sort:desc`).
- **"Invite crew"** is a link to `/chat/r/<slug>?draft=<game link>` (D6).
- On LAN http, `GAMES_URL` matches the starter's scheme: an https Houston needs `https://games.alexh95.com`, or the
  frame is mixed content (06 §2.9).
- **`c4`**: connect-four as game content that is hypermedia: server-authoritative state over WS, cells upserted,
  spectators over SSE (`c4.game:<id>`), a depth-limited minimax opponent running in the pure zone. On the cut list.

**Rejected.** A reverse proxy under the starter's domain and SSO (S22). PF §4.3's sitemap/`build.json` scrape source
(it couples to undocumented spark files, and SP1 is about 50 lines).

**Alex confirms:** no; Alex approves and promotes the spark CLs (D43).

### D35. Accounts, roles and permissions

**Decision.**
- **Roles** `Role :: enum u8 {Guest, User, Mod, Admin}`; labels Guest, Member, Moderator, Admin.
- **One closed `Perm` enum** in `platform/authz`, grouped by feature with section dividers, and one table
  `ROLE_PERMS :: [Role]bit_set[Perm]` (07 §5.2; `SK/CLAUDE.md` "One definition per concept"). Members: `Account_Self`;
  `Chat_Read Chat_Post Chat_Dm Chat_Create_Room Chat_Attach Chat_Moderate`; `Bot_Use Bot_Llama`; `Video_Watch
  Video_Upload Video_Moderate`; `Wiki_Read Wiki_Edit`; `Lists_Edit`; `Polls_Create Polls_Vote`; `Calendar_Edit`;
  `Guestbook_Moderate`; `C4_Play`; `Term_Watch Term_Write`; `Admin_Accounts Admin_Audit Admin_Ops Admin_Jobs
  Admin_Modules Admin_Db Admin_Term` (under 64, one bit_set word). The generator deletes the groups of deleted
  features (D26). No per-user grants in v1.
- **Default grants that are judgement calls** (Q31, X16), as tabled; `rbac.spec` freezes them at M4:

| Perm | Granted to |
|---|---|
| `Term_Watch` | Moderator and Admin |
| `Video_Upload` | Moderator and Admin |
| `Admin_Audit` | Admin only |

- **Enforcement**: `front` (in `platform/app`, D4) loads the `Viewer` through the `identity:` family, the build's one
  identity (`identity.load_viewer`, checked against the contract `authz.Load_Viewer`), on every host whose `identity`
  field is true, then checks the route row's `perm` before the body is read: guests get 401 with `HX-Redirect: /login`
  for htmx (a 302 otherwise), others 403; `.Step_Up` routes send stale sessions to the step-up page. Resource checks
  (own message, moderator of this room) live in services; each topic row's `subscribe` checks its perm; views receive
  the `Viewer` only to hide controls. `.Lan_Only` routes answer 404 unless the trusted client address is in `LAN_CIDRS`,
  enforced and tested in-app; NPM Access Lists are a second layer. **No identity runs on a host whose `identity` field
  is false** (`full`'s lab host, `SITE_URL_LAB`): every viewer there is the Guest, every row there is `.Public`, and
  `.Lab_Host` rows are mounted only on such a host or on an origin whose identity sets no cookie (D25). `rbac.spec` is
  generated from `bin --routes` (every route × every role × every host → the expected status, D37).
- **The `accounts` identity**: registration by `ACCOUNTS_REGISTRATION` (`invite` by default, Q10), login, logout, a
  sessions page with revoke, password change, admin-issued one-time reset codes (no email), 10 recovery codes, TOTP
  (RFC 6238, vectors verified in 07 §0.6) with manual secret entry and the `otpauth://` text (no QR encoder), required
  for Admin and `Term_Write` (Q11); a profile (display name through spark's `clean_name`, avatar through uploads);
  `accounts_prefs` (theme, chat transport, mutes; X9).
- **Passwords**: argon2id on the argon pool (`ACCOUNTS_ARGON_THREADS` 2, or 1 when the container has ≤ 2 CPUs as
  apollo's `full` does, Q34, answered 2026-10-26; at most that many concurrent verifies, a queue of 32, 503 "busy, retry" beyond;
  the handler defers its response, F-13; one reused buffer per worker), with OWASP's parameters (19 MiB, t = 2, p = 1):
  S0.5 measured 19–32 ms per verify on the dev PC, the 64 MiB preset 119–191 ms (out), and apollo's figure is
  UNVERIFIED (M4), printed by `--hash-password`; constant-time compares,
  a dummy hash for unknown usernames, 10–256 bytes, per-account exponential backoff (never a hard lockout), last-admin
  protection.
- **Sessions**: an opaque 32-byte token in cookie `sid` (`HttpOnly; SameSite=Lax; Path=/`, host-only with no `Domain`
  attribute, so it never reaches `houston-lab`, D25; `Secure` when the request arrived as https through a trusted
  proxy, `COOKIE_SECURE=auto`), SHA-256 stored, rotated on login and privilege change, idle 14 days, absolute 30
  days. Stage 1a (LAN http) runs `COOKIE_SECURE=0`, with a warn line on every boot
  and a banner. **Step-up**: password or TOTP within 10 minutes for `Term_Write`, role changes, invites and dbview.
- **CSRF**: `SameSite=Lax` plus the skeleton's `same_origin` guard, unchanged
  (`SK/app/src/controllers/middleware.odin:222-242`). Every WS upgrade checks `Origin == SITE_URL` (D12);
  `/term/agent` refuses any `Origin` and accepts only device tokens.
- **Other identities**: `envadmin` (a single admin from `ACCOUNTS_ADMIN_HASH` with a signed stateless cookie, the
  spark pattern, 06 §3.1), `nick` (a signed nickname cookie with role User; `ACCOUNTS_NICK_FROM=lan` grants it only to
  clients in `LAN_CIDRS`, so a public visitor to a witness is a Guest, with no `Chat_Read` under the table above, and
  chat shows them a "chat is open on the LAN" notice; `ACCOUNTS_NICK_ADMIN_CIDRS`, empty by default, makes its clients
  there Admin, which opens `/admin/ops` in `streams`; built at M2 for `streams`, ahead of the rest of accounts; X7,
  ANSWERS round 9), `anonymous` (its own package,
  `platform/authz/anonymous`, so the identity collection always names one package). Each identity exports `NAME`,
  `SETS_COOKIE`, `load_viewer`, `cli` (`--hash-password` in `accounts` and `envadmin`, D10) and its `ROUTES`; the
  member is picked by the profile's `build.*` row (D8). The `Viewer` it loads carries the member's preferences
  (theme, chat transport, mutes from `accounts_prefs`), so other features read them without importing accounts (D4).
- **Rate limits** (spark's fixed-window limiter, keyed by the hashed client id from the trusted address, never the TCP
  peer; 06 §3.1, 07 §0.1):

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
| `/csp-report` | 10 per minute per client id |

  429s carry `Retry-After` and route to the toast slot (`hx-status:429`).
- **Audit** (`features/audit`): `audit_log` is append-only by triggers (no update; deletes only past 400 days); it
  records every admin and moderator action with the `HX-Prompt` reason, the actor, the target and the hashed client
  id, never message bodies or passwords; `/admin/audit` has filters, keyset infinite scroll and CSV through
  hx-download. Every audited action goes through `store:audit` (D6): the SQLite family writes the `audit_log` row,
  and the memory family, in profiles without SQLite, writes one `mod=audit` log line; the page is mounted only in
  SQLite profiles.
- **Uploads** (`features/uploads`): chunked (create → `PUT /uploads/<id>?off=` with chunks of at most 4 MiB under a
  per-route body cap → finish with sniff, the header and sha256), images up to 10 MiB, video up to 4 GiB (uploaders only),
  magic-byte sniffing, a header read and a 40 MP pixel cap with no decode on the server (M6: PLAN §17.6 says why, and what a
  feature needing pixels must do), content-addressed blobs, `nosniff`,
  `Content-Disposition: attachment` for anything that isn't an image, never SVG or HTML inline, at most 8 concurrent
  uploads × 4 MiB in flight. The chunks go through the app.js shim (fetch), so no htmx timeout applies to them;
  `hx-config` `timeout:0` sits only on the finish request (`POST /uploads/<id>/finish`), which can run long while the
  server hashes and moves the file (UNVERIFIED (M6), X14). `uploads` owns its session rows (`uploads_blobs`,
  `uploads_parts`) through its SQLite store, `app/stores/sqlite/uploads/`, or in memory through
  `app/stores/memory/uploads/`, where they are lost on restart (D18, X13).
- **Terminal hardening**: `Term_Write` is Admin-only with TOTP and step-up; `Term_Watch` is read-only; device tokens
  are 32 random bytes shown once, stored as SHA-256, revocable, with a per-device kill switch; the agent runs
  unprivileged with its own allow-list; LAN-only; 15-minute idle timeout; input ≤ 4 KiB/s, output ≤ 1 MiB/s, 2
  sessions per device; every start, stop, attach, watch, resize, kill and line-mode command is audited; writable
  sessions are recorded (output only, 30 days or 1 GiB in total, whichever comes first, never raw input; the size cap
  protects apollo's disk, NEW; Q12, X10).
- **Trusted proxy**: `X-Real-IP`, `X-Forwarded-Proto` and `X-Request-Id` are honoured only from `TRUST_PROXY` peers
  (fixes spark's `client_address`, S6); the stack Caddy sets `header_up X-Real-IP {client_ip}` and trusts
  `X-Forwarded-For` only from the address NPM connects from, so NPM's client IP survives the second hop (08 §6.3).
  The devices session measured that address as the gateway of the stack's own Docker network, Caddy's one
  `trusted_proxies` entry, with its residual risk accepted (D41, X39). A LAN host that connects straight to :8120
  keeps its own address, so it is identified by its TCP peer and cannot choose its client address. The app's
  `TRUST_PROXY` is Caddy's fixed `ipv4_address` alone, as a /32, not the stack network's subnet, which also holds the
  gateway Caddy trusts (D10, D41, X31, X43). `/metrics` needs an Admin session or the bearer token in
  `METRICS_TOKEN_FILE`.

**Rejected.** CF §6.8's perms registered as strings with `ROLE_BITS` built at boot. RF §3.9's perms in a parallel
table. Per-user grants (PF §6.4.6) in v1.

**Alex confirms:** yes (Q10, Q11, Q12, Q13, Q31: default stands (not overridden)); the identity as a build family
answered 2026-10-25 (ANSWERS round 3).

### D36. The other features

**Decision.** Short contracts; each feature's README carries the full spec under the fixed headings (D4).

| Feature | Contract |
|---|---|
| `home` | Today page: the cards in `main`'s `HOME_CARDS`, in that table's order, which no longer has to follow `NAV` (D6); each card is a fragment refreshed over `#live` |
| `notify` | `notify.user:<id>` upserts `#notify-list` and updates `.notify-count` everywhere through hx-targets; producers import `notify_web` and call `notify_web.send`, so notify is a hard dependency of each (D6): mentions, DMs, list assignments, calendar reminders, poll results, a bot reply finished after you navigated away, moderation, the guestbook queue for mods, job failures for admins; 200 per user and read ones after 30 days; per-room and per-kind mute |
| `ops` `/admin/ops` | a 1 Hz publisher renders the metrics registry (13 §5.2) once into OOB fragments and server-side SVG sparklines on `ops.panel`, so N viewers cost one render; `innerMorph` tables; `?mode=poll` (ptag 304s) and multipart slow panels (D8) |
| `status` `/status` | one multipart/parallel response; each part is a mounted feature's health, which its package pushes to `platform/obs` (D6), or a `STATUS_PROBES` external (llama `/health`, the Pi agent's last seen, games healthz, disk free, backup age, the witnesses), 2 s timeout each, swapped as it answers; details behind `Admin_Ops`; a ptag polling variant every 30 s; in the lab it is the witness board |
| `jobs` `/admin/jobs` | the scheduler in `platform/workers` runs the mounted `JOBS` rows on the jobs pool (retention sweeps, nightly backup, weekly FTS optimize, video import scan, reminders, houston-lab's demo resets at 04:00, X38); "run now" and cancel call `workers.run_now(id)` and `workers.cancel(run)`, a lookup by id like a route's, and workers keeps each run's state as data, so it never calls a feature (D6); `features/jobs` adds `jobs_runs` with leases (resume or fail on boot, 13 §3.6), SSE progress rows by upsert, run now, cancel with hx-prompt, log download |
| `modules` `/admin/modules` | the granularity made visible, from obs, `platform/env` and the tables `platform/app` holds: the profile, its family members, the mounted routes per host with perms and flags, topics and jobs, bundle extensions, env, limits, health, migrations applied or dormant, and the live bot default, which bot pushes to obs, with a link to `/admin/bot` (D31). It imports no feature, and never disables a compiled feature (Q28) |
| `wiki` `/wiki` | the source follows the store family (D8). SQLite: pages, revisions with a line diff computed on the pool, a rev-mismatch 409 that shows the diff, server-rendered preview (`keyup changed delay:500ms`), FTS, hx-head per page, history-cache, `.md` export, visibility public or members; memory (`source_files`): read-only embedded docs (the lab); Houston seeds the starter's docs as read-only Manual pages; markdown is rendered at write time by `platform/markdown` (depth cap 32, input cap 64 KiB) |
| `find` `/find` | the page and the Ctrl-K palette over the sources in `main`'s `FIND_SOURCES`, each a domain's `search` filling `store.Search_Hit` rows (D6), filtered by the viewer (chat: rooms the viewer belongs to; DMs only their own); FTS5 in the SQLite family, `contains_ci` in the memory family; `hx-sync="this:replace"`; bm25 on the pool |
| `lists` `/lists` | lists of items (text ≤ 200 runes, done, assignee → notify, integer positions with gaps of 1024 renumbered by the server); a checklist view with hx-pending add; a board view (columns; `Draggable`/`DropZone` → `POST /lists/<id>/items/<iid>/move`; move buttons are the no-JS path); live through `lists.list:<id>` upserts keyed `data-pos`; templates (groceries, packing) |
| `polls` `/polls` | a question with options or the Go/No-go preset; single or multi; anonymous flag; closes at; vote with hx-pending; CSS bars `style="--p:NN%"` (allowed by `style-src-attr`); a `.Latest` topic `polls.poll:<id>`; closing notifies the voters |
| `calendar` `/calendar` | a server-rendered month grid, event pages, a create wizard (each step a URL through `HX-Push-Url`, 422 per step), RSVP yes/maybe/no updating `.rsvp-<id>` through hx-targets, reminders (jobs → notify, 24 h and 1 h before), a per-event `.ics` download, a per-user secret feed `/calendar/feed.ics?t=<token>` |
| `guestbook` `/guestbook` | a public form (name ≤ 40 runes through `clean_name`, message ≤ 500 runes), a honeypot and a signed render timestamp (reject submits under 3 s), 3 per hour per client id, `GUESTBOOK_OPEN` switch; notes enter the moderation queue (`guestbook.queue`) and appear only once approved (a reject needs an hx-prompt reason); pending notes expire after 14 days |
| `dbview` `/admin/dbview` | read-only SQL on a pool reader connection (`OPEN_READONLY`, `stmt_readonly`, `LIMIT_ATTACHED 0`, a 2 s `progress_handler` budget), never under the store lock (06 §3.1's fix), step-up, audited |
| `landing` (the root in `lab` and on `full`'s lab host) | the catalog explorer from `docs/catalog.json` (features, implementations, dependencies, sizes, SQLite needs); an init-command builder (a form whose response is the `odin run tools/init -- …` line and its `--explain` output); links to every witness |
| `scripting`, `compat`, `lab` (in `lab`, and in `full` on `houston-lab`) | D21's lab pages, every `scripting` and `compat` route `.Lab_Host` (D25); `/lab/streams` holds the raw SSE, WS and multipart contract pages (03's 29 checks) |
| `notes` | the skeleton's `--minimal` Notes (422 validation, `afterbegin` insert), in either store family; on houston-lab capped at 500 rows by `NOTES_CAP` and reset at 04:00 local time each night by `notes.reset` (D25, X38); uncapped everywhere else |
| skeleton features | `dashboard`, `gallery`, `contacts`, `about`, split 1:1 from `SK/app/src` (01 §2's routes); contacts' migrations 0001–0003 keep their hashes and gain `0004_sort_indexes`. On houston-lab the dashboard's page sits at `/dashboard`, `about` sits beside them (X36), and contacts is capped at 2000 rows by `CONTACTS_CAP` and reset at 04:00 local time each night by `contacts.reset` (D25, X38). The `skeleton` profile mounts them uncapped, so parity and the 20k-row scale scenario are untouched |
| `devices` `/admin/devices` (M14, optional) | the device registry: one row and one token per device, generalising `/admin/term`'s device tokens (D32, D35); LAN-only like every `/admin*` page (D41); a device token reaches only its device's routes, and revoking it closes its feed and kiosk streams; the plain-text `text/event-stream` (unread count, presence, next event, bot health) for screens that can't render HTML, D3's row 8, with a format spec of its own (X42) |
| `cams` `/cams` (M14, optional) | Houston pulls each camera's MJPEG stream once (`platform/stream/client`, D12) and fans it out to members as `multipart/x-mixed-replace`, which a plain `<img>` renders with no JS: one upstream pull per camera whatever the number of viewers; LAN-only and members-only first (X42) |
| `wall` `/wall` (M14, optional) | the wall and TV dashboard: a kiosk view of Today (the cards in `main`'s `HOME_CARDS`), signed in by a device token (X42; the name is NEW) |

**Alex confirms:** no (Q28 on runtime disabling: default (not yet raised)); the M14 rows follow Q33 (answered
2026-10-26: yes).

---

## H. Quality

### D37. Testing

**Decision.**
- **Unit**: `odin test` per package. It covers the parsers (form decode, WS frames, the SSE client, Range, multipart,
  the stream cursor, the term grid frames, markdown); a store conformance suite per feature (`features/<f>/storetest`,
  which imports both families' stores directly into one test binary, since their package names are unique; CF §4.5; LC
  §16: 2 tests pass); each feature's own tests under every profile that mounts it, through `CMD=test ./build.sh <p>`,
  since a domain reaches a collection and can't build alone (D39); each profile's `routes_test.odin` (D5's boot checks);
  the migration runner's 6 cases plus real fixture databases (12 §5); the hub (publish, drain, replay, resync,
  policies); guard classification; the limiter; TOTP vectors; `clean_name`; and the micro-guards (D38).
- **e2e** (Playwright, the skeleton's harness, 01 §9): specs in `e2e/tests/<f>/`, tagged `@<f>` and, for
  implementation-specific ones, `@<f>-<impl>`. Global setup builds each profile under test through `build.{sh,bat} <p>`
  (D7) and reads `bin --features --json` to choose tags; each worker gets its own server on an OS-picked port.
  **Matrix**: `full` × {chromium, firefox, webkit}; `skeleton` × 3 engines; `minimal` and `streams` × chromium (plus
  webkit for streams); `lab` × 3 engines (chromium and webkit locally, all three in CI, Firefox included; this matches
  D44's M2 exit, X18); `full-vanilla` × chromium (core and twinned-behaviour specs); generator outputs × chromium.
  Firefox runs in CI only (it can't start on this PC, 11 §1); `harness-csp.spec` is the Firefox proof.
- **Realtime specs**: real servers only; two browser contexts; `page.on('websocket')` frame shape; `context.setOffline`
  resume without duplicates (count ids); a 1012 close reconnects, a 1008 close doesn't; `Last-Event-ID`, `after` and
  `@rowid` resume, including across a server restart; a hidden tab closes the stream; transport-parameterised specs
  (`@chat-ws` …); `revoke.spec` (M4): the named `kicked` event navigates to `/login`, a reconnect without auth gets
  403, and the server sees at most 3 reconnects in 30 s (D13, X19).
- **Client-stack specs** (11 §7.3): `headers.spec` (parsed directive maps per flag combination, on both of `full`'s
  hosts: no `Set-Cookie` and `X-Robots-Tag: noindex` on the lab host, the nonce CSP on `/scripting/*` there and never on
  Houston's host), `csp-clean.spec` (zero violations on every sitemap page plus one interaction per feature, and on
  `full` every `houston-lab` page), `csp-enforced.spec` (negative canary; in `lab` and on `full`'s lab host),
  `harness-csp.spec`, `bundle-race.spec` (assets delayed 400 ms, with and without hyperscript), `streams-hxcsp.spec`,
  `games-frame.spec` (from M10 with a WebXR spec: the embed's `allow` list carries `xr-spatial-tracking`, D34, X41),
  `download.spec`, `a11y.spec` (`@axe-core/playwright` without bypassCSP, plus lints: live regions in the initial
  markup, no click handlers on non-interactive elements).
- **Test devices** (X41; DEVICES-SUMMARY), by hand beside the CI matrix: an **old Android phone is the oldest-browser
  device**. D22's core flows (links, forms, SSE) must work there without the client behaviours; whether htmx 4 runs on
  that browser is UNVERIFIED (M6). The VR headset is the test client for WebXR games inside the embed (M10). The other
  test clients (the tablet, the Windows laptop, the handheld gaming PC) are optional and gate nothing.
- **Generated specs**: `rbac.spec` from `bin --routes --json`, every route × every role × each of the profile's hosts.
  In `full` that adds the per-host tables (D25): a row answers only on the host whose table mounts it, so each of
  houston-lab's rows 404s on Houston's host and each of Houston's 404s on houston-lab, and every houston-lab row answers
  a request carrying a valid `sid` exactly as it answers a guest and sets no cookie. e2e gives `full` two origins on one
  server, `localhost` (`SITE_URL`) and `127.0.0.1` (`SITE_URL_LAB`), whose host-only cookies stay apart (NEW).
  `escaping.spec` (D22's checks, and XSS payloads in every UGC field render as text).
- **Rules**: CSP-sensitive interactions use trusted input only (`locator.click`, keyboard), never `page.evaluate` clicks
  (11 §7.1); a known-error allowlist by exact text covers htmx 4.0.0's hx-pending `htmx_error` bug and the SSE abort
  noise (11 key facts, 04 §1), so an upstream fix shows up as a diff; video playback specs use `channel: 'chrome'` or
  AV1 WebM (07 §4.7).
- **Load**: k6 v2 per feature in `load-tests/scenarios/<f>/` (the skeleton's 10 scenarios and `scale` stay); HTTP and
  WS with stock k6 (`k6/websockets` verified, 08 §5.2); SSE and WS fan-out with **`tools/streamload`**, a
  multi-threaded Odin generator on `platform/stream/client` with publisher-stamped `data-t` delivery percentiles (the
  Node clients behind 03's numbers were client-bound, 03 §10.4; it avoids distributing an AGPL custom k6, 10 §11).
  Per-feature scenarios: chat (four transports), bot (1000 mock generations and Stop storms), video Range readers,
  uploads, the ptag 304 wall, a login storm, terminal grid throughput.
- **Soak**: nightly 1 h (2000 streams + mixed load + a mid-run redeploy; RSS and FDs plateau, `stream_queued_bytes`
  bounded, no exits but the deploy, reconnects ≤ 5 s); 1 h through NPM at M3; 8 h before M12.
- **Fuzz** (02 §2.4): the raw-socket smoke per push (10k malformed HTTP requests and WS frames including
  `Content-Length: -5`, `/livez` 200 after each); table-driven random-bytes unit tests; libFuzzer nightly through
  `-build-mode:obj` on the HTTP scanner, WS decoder, SSE client, multipart round trip, Range header, form decode,
  markdown, the stream cursor, the term grid decoder and the agent's VT parser; an 8 h campaign before M12. From M2, a
  nightly Autobahn|Testsuite fuzzing client runs against the lab's WS echo; its image is dev-time Docker, exempt like
  Playwright and k6 (D12, X24, NEW).
- **Crash drills**: `TEST_ROUTES` builds only (release images assert 404):
  `/__test/crash/{panic,bounds,div,nil,stack,lock,async,sqlite,wsdata,hang}`. Pure kinds → 500, 20/20 bystanders
  alive, streams still flowing, the recovery counter up by one; `lock`, `async` and `sqlite` → exit 70 within 6 s;
  `wsdata` → 1011 with the server alive; `hang` → the watchdog exits within 11 s and names the route and request id.
  Plus the shutdown bound, restart after `kill -9` at 0/50/100 ms, and the fd ceiling (13 §6.2).
- **Route-coverage parity**: after the e2e run and after the k6 quick run, CI scrapes `/metrics`; every route id must
  have a non-zero per-route request counter in both (CF §10). `tools/check parity` fails otherwise; waivers live in
  `tests/parity-waivers.txt` with a reason and are reviewed in the milestone audit. This enforces the skeleton's
  "every endpoint in both suites" rule (`SK/CLAUDE.md` standing policy 3), which `parity.sh` stated but never
  enforced (14 of 26 routes had no load scenario, 01 §2). **M1:** each server either suite starts is scraped as it
  stops, through a per-run bearer, into `app/build/coverage/{e2e,load}/<profile>/`; new e2e checks and the load
  scenarios `ops`, `ping`, `gallery`, `home` and `about` bring every route of both profiles into both suites with no
  route waiver. The waivers file holds both parity rules' waivers (`perf | <cell> | <legs> | <reason>`, `route |
  <route id> | <suites> | <reason>`; PLAN §19.1.11).
- **Tags, as built (M1)**: a spec or scenario carries a tag for every feature it touches, its folder's first, and
  runs only when the build has them all; `@<f>-<member>` names a family member by its `NAME` (the store family's from
  `app/stores/<family>/stores.odin`). An untagged spec fails rather than run on builds it wasn't written for.
- **Combination coverage**: every named profile per push; one rotating singleton per push; every singleton nightly;
  from M4 (once there are at least 10 optional features) a strength-2 covering array over feature presence nightly:
  N rows cover every pair of k binary factors when C(N−1, ⌈N/2⌉) ≥ k, so 8 rows cover up to 35 features (C(7,4) =
  35); a second small array assigns the four build families (store, identity, client, theme); rows are closed over
  dependencies and must cover 100% of feasible pairs; plus 3 seeded random valid selections nightly. The array comes
  from `tools/init --pairwise --seed <n>`, is committed as `.github/matrix/pairwise.json` and is checked fresh.

**Alex confirms:** no.

### D38. Performance budgets and the parity gate

**M1:** the gate's procedure is `load-tests/run.sh --parity` (`lib/parity.sh`, spike S0.1's loop, and
`lib/parity.mjs`, the pass rule with each cell's reference and the waivers file's `perf` and `perf-floor` lines); the baselines build
into the git-ignored `perf/baseline/`.

**Decision.**

**The parity gate (S18), as a procedure.** `tools/baseline` builds 709bc94 and v1.1.1 with the pinned Odin, the same
SQLite library and the skeleton's own prepare (01 §14.3 method). The baseline is unchanged by the crash fix: **HEAD**
here, in D17, in S0.1–S0.4 and in Q6 means 709bc94 (tag v1.2.0), the build 12 measured, never `master`'s later tip
6d37506 (v1.2.1; ANSWERS F5). `load-tests/run.sh --parity` runs, per leg (Windows
native; Linux on WSL2, Q5):
- scenarios static, seo, pages, list, search, api, detail, write and mixed at 200 VUs and 16 loops, plus scale at 20
  VUs over 20k rows, each on `:memory:` and on a file DB;
- interleaved rounds A (HEAD), B (v1.1.1), C (the starter's `skeleton`), n = 3, a fresh server per run,
  `LOG_LEVEL=warn`, 3 s warmup and a 10 s window;
- background CPU sampled before each block; a round re-run when it exceeds 20 %.

**Pass, per cell**: the median of the per-round ratios C / max(A, B) is ≥ 0.97, no round is below 0.85, and p99 is ≤
1.10 × the p99 of the faster baseline. On the light routes, `static` and `seo`, the reference is HEAD alone: v1.1.1 is
4–8 % faster there only because it lacks 1.2.0's security middleware, which the starter keeps (S0.1; Q35, answered
2026-10-26). The `:memory:` cells that the chosen `:memory:` mode fails against max(A, B) are gated against HEAD with a
documented exception each (Q6, answered 2026-10-26); a file-DB cell is never waived. A cell Alex accepts below 0.97 at
its measured level carries a `perf-floor` line with its bar and reason, and only the median rule moves (M1: Linux
`write@mem` at 0.93 of HEAD, the writer task's hop; ANSWERS round 6). A failing cell is re-run once with n = 5 and fails only if the re-run fails
too, because cells vary by up to 2× between rounds on this box (12 §10). **When**: at the M1 exit and at every
milestone exit after it, M3 included (X25); results go to `perf/results/<version>-<leg>.csv` and
`docs/perf/PARITY.md` with the box, toolchain and background load; nothing is waived without Alex. CI runs only a
relative load smoke against the last green run (flagging regressions over 20 %), never absolute RPS (08 §5.2).
**Micro-guards** in `odin test` between gate runs: `repo_match`, `repo_page` and render µs per call against a
committed reference (12 §2.1), and a `stmt_status(REPREPARE) == 0` assertion after 1000 binds, so the bound-LIMIT
class can't return (01 §14.4). No 1-loop leg (D17).

**Budgets.**

| Area | Budget | Basis |
|---|---|---|
| `skeleton` parity | the rule above in every cell × {`:memory:`, file} × {Windows, Linux} | S18; D17 |
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
| Login storm | 50 logins/s under `cpus: 2.0` with one argon thread: other routes' p99 ≤ their base + 0.5 ms, the cgroup never throttled, every login answered (Q34, answered 2026-10-26; the first budget, +10 %, failed in S0.5) | 07 §5.6; S0.5 |
| Chat | writer task, on a real post (FTS, the version bump, a trim at the cap) on a file WAL: ≥ 10k msgs/s at a retention cap, ≥ 3× autocommit, 1000 msgs/s offered at p95 ≤ 50 ms; send → another member's DOM on the LAN via NPM p95 ≤ 50 ms (NEW) | 12 §3.1; restated at M6 from "≥ 50k msgs/s batched", a bare insert's number (`docs/perf/CHAT-BUDGETS.md`) |
| Bot (mock) | 1000 concurrent generations × 200 tokens at 20 Hz ≤ 1 core and ≤ +30 MB (NEW) | — |
| Video | 256 MiB Range transfer ≤ 8 MB peak private memory (Linux splice UNVERIFIED) | 07 §0.2 (5.1 MB) |
| Terminal | 80×24 full render ≤ 100 µs; LAN key echo p95 ≤ 50 ms (estimate UNVERIFIED) | 07 §3.3 (53 µs) |
| Wire | minimal 11.7 KB br JS; full about 23 KB + hyperscript 39.7 KB br; CSS ≤ 16 KB br; a Houston page ≤ 40 KB of HTML | 11 §9 |
| apollo allocations | full: `THREADS=2`, `cpus: 2.0`, `mem_limit: 512m`; the witness resource class (`minimal`, `streams`, `skeleton`, and `lab` too, X22): `THREADS=1`, `cpus: 0.5`, `mem_limit: 64m` (enforcement outside Swarm UNVERIFIED) | 08 §6.5 |

**Rejected.** PF §9.2's and CF §9.2's "median ≥ best − noise band" rules (vacuous on cells whose rounds spread
25–52k, 12 §2); PF's gate cadence (M2 and releases only); CF's 1-loop leg.

**Alex confirms:** answered 2026-10-25: Q5 yes, Odin dev-2026-10 in WSL2 for the Linux leg. Q6: default (not yet
raised), and only through D17.

### D39. The Odin code audit

**Decision.** Alex's "audit of the resulting Odin code" is a procedure with gates (02 §2, 13 §6.2):

| Cadence | Checks |
|---|---|
| Every push (CI) | `CMD=check ./build.sh <p>` for every profile, since each call site is checked only against its build's family members, and `odin check app/stores/<family>/<f> -no-entry-point` for every store in both families, which import no collection and so check alone, so a store no profile builds can't rot (a family directory is not itself a package, so CI loops over its subdirectories; LC §11, §16), all with `-vet -strict-style -warnings-as-errors` (the skeleton's bar, clean today: 02 §2.1, 09 §3). Domains, views, web packages, switched implementations and identities reach a collection and don't check alone ("Unknown library collection: 'store'"; 14 critic): they are checked under each selecting profile's line, and `identity_envadmin`, which no hosted profile selects, under a generated `--identity envadmin` selection in the nightly matrix (NEW); the further vet flags of 02 §2.1 (`-vet-cast -vet-semicolon -vet-tabs -disallow-do -vet-using-param`), adopted at M1 with 0 errors; `tools/check` imports (D4), locks (no `sync` lock outside the guard helpers), entry-points (every `nbio.*_poly`, `stream_begin`, thread and timer callback wrapped by `guard_call` or waived with a reason), tables (package-level `[?]T`, never slice literals in a proc), names (table, CSS, topic, job and env prefixes), parity, pins, catalog freshness, and the lean-composition checks: `profile` (every imported feature package mounted, no orphan `ROUTES`, a `migrate` line for every SQLite store a build reaches; it replaces D7's `--emit --like` byte check), per-host `routes` (prefix ownership, one root, no root row in a package's `ROUTES`; D9), `topics` (each family and job id prefixed by its declaring feature and declared once; every family a package publishes to by name declared by some package; D6), `contracts` (every proc type in a `models` contract has a typed-constant line in that feature's store in each family that has one; every identity checks `authz.Load_Viewer`), the collection rules in `imports` (`store:<f>` only from `f`'s domain, `store:audit` from any domain, web or identity package, either from a SQLite profile's `main`; `identity:` from `platform/app` and `cmd`; `client:` and `theme:` from `platform/html`; no web-to-web import but `notify_web`; D4) and `exts` (D19); unit tests under a `Tracking_Allocator` with `ODIN_TEST_FAIL_ON_BAD_MEMORY` (0 leaks, 0 bad frees); the fuzz smoke; the crash drills; the shutdown bound; restart; the watchdog; the observability microbench (logfmt ≤ 1 µs, metrics ≤ 100 ns) |
| M1 as built | `tools/check` `imports`, `profile`, `routes`, `contracts` and `parity` (PLAN §6.1), each tripped by `tools/check/testdata/bad`; prefix exceptions are a `## Prefixes` table in the feature's README; `platform/app` may import `store:.` for the family's `NAME`. The rest of the static list (locks, entry-points, tables, names, topics, exts, pins, catalog, audit-debt) lands with the milestone that needs it |
| Nightly | ASan over e2e and a short load (Windows and Linux); TSan (Linux) over the hub, streams, store, workers and terminal grid; the 1 h soak; the fd ceiling; libFuzzer targets; singletons, pairwise and selection fuzzing |
| Every milestone exit | a written audit, `docs/audit/M<n>.md`, by an agent that did not write the code: the 02 §2.8 rubric (allocator buckets including connection-owned state, no panics on external input, limits plus timeouts, lock discipline, errors as values, aesthetics, tests in lockstep), 13's pure/dirty zone rules, the fork's diff line by line, a spall trace and a Linux `perf` flame graph of the slice's hottest route, and `-vet-unused-procedures -vet-packages:…` as an aid; findings ranked by severity. **Exit needs 0 open CRITICAL or HIGH**; MEDIUM findings go to TODO with an owner milestone |
| Audit stamps | each package README records `Audited: <commit> <date> <report>`; `tools/check audit-debt` counts changed lines since each package's stamp; a release (every milestone exit) is blocked while any package has more than 300 unaudited changed lines or any open CRITICAL/HIGH (CF §9.3) |
| Before public (M12) | a full-tree audit, an 8 h libFuzzer campaign, an 8 h soak, clean sanitizers, a symbolised crash drill (`-o:speed -debug`, split debug file kept per `VERSION`) |

**Rejected.** `-vet-unused-procedures` as a per-push gate (RF §9.3, PF §9.3): 09 §3 measured 13 hits, mostly false
positives (`@(test)` procs, unused binding declarations), "an audit aid, not a gate"; the flag also needs
`-vet-packages` (02 §2.1).

**Alex confirms:** no.

---

## I. Delivery

### D40. Pipeline and releases

**Decision.** GitHub Actions on the public repo (free standard runners including `ubuntu-24.04-arm`, 20 concurrent
jobs; 08 §5.1):

| Job | Matrix | Content |
|---|---|---|
| pins | — | `check-pins`: Odin dev-2026-10 (84bc3fc), the vendored fork's base (laytan fac113f, named in `app/vendor/odin-http/UPSTREAM.md` with its F-changes, D11), the htmx 4.0.0 tarball SHA-256 (04 §1.3), hyperscript's SHA, SQLite 3.53.4, the Playwright image = lockfile, k6, the Caddy image digest |
| check | — | `tools/check` (D39), its `profile` check on every committed profile included; `CMD=check ./build.sh <p>` for every profile; `odin check` of every store package in both families on its own; `docs/catalog.json` and `pairwise.json` freshness, audit-debt |
| build | {minimal, skeleton} × {ubuntu, ubuntu-arm, macos, windows}; {streams, full, lab} × {ubuntu, windows}; full-vanilla (`./build.sh full-vanilla`: `cmd/full` with the vanilla client) × ubuntu | through `build.{sh,bat} <p>`; the static gate, `-o:speed`, `odin test`, size budgets, smoke (`/healthz` body exactly `ok`; WS echo and SSE first event where present); `minimal`, `streams` and `lab` also built with prepare's SQLite step skipped and no sqlite3 library present (D18) |
| e2e | D37's matrix | `mcr.microsoft.com/playwright:v1.63.0-jammy` (the skeleton's pin); the route-coverage scrape |
| e2e-proxy | `streams` and `lab` × chromium from M2; `full` × chromium from M4 | from M2, whose exit needs it (X26): the suite through `deploy/Caddyfile` run in CI (the same file apollo runs) and through nginx with the generated `proxy_host.conf` + `proxy.conf` of apollo's actual NPM version, pinned (X40; the plan first modelled v2.16.0) (buffering, 90 s timeouts, the Connection header, HTTP/1.0 upstream; 08 §3.1) |
| proxy-config | — | from M3 (X26): `caddy validate` on `deploy/Caddyfile` and every Caddyfile snippet in the docs; `nginx -t` on the NPM Advanced snippet inside NPM's template; curl assertions for every redirect alias, bare and deep (D25); asserts compose's `8120:80` publish and the Caddyfile's 421 catch-all (X23) |
| linux-ops | full | crash drills, shutdown bound, restart, watchdog, fd ceiling (a container with `ulimits`) |
| docker | each hosted profile | compose up under `./seccomp-io-uring.json`, staged next to `compose.yaml` as `promote.ps1` does on apollo (X21), `--healthcheck`, **UID 10001** (the inherited assertion, `SK/.github/workflows/ci.yml:219`), read-only rootfs, SIGTERM stop ≤ 6 s, volume persistence |
| generator | each named profile + one rotating singleton | `tools/init … --yes` (with `--verify`) on a clean checkout, then that output's `tools/check profile`, check and build through its own `build.*`, and chromium e2e for its tags |
| load-smoke | full, skeleton | k6 at 20 VUs, relative to the last green run |
| term-agent | ubuntu-24.04-arm | builds `cmd/term-agent` for linux_arm64; the e2e runs an amd64 agent in the CI container against `/bin/sh` |
| nightly | — | ASan, TSan, soak, libFuzzer, Autobahn\|Testsuite against the lab's WS echo (from M2, X24), singletons, pairwise, selection fuzzing |
| release (tag `v*`) | each hosted profile | multi-arch images (amd64 on ubuntu, arm64 on ubuntu-24.04-arm, merged), GHCR `ghcr.io/alexh95/odin-htmx-starter-<profile>:vX.Y.Z` and `:sha-<7>`, provenance attestation, a GitHub Release from the CHANGELOG; from M11, the linux_arm64 `term-agent` binary and its SHA-256 as release assets (D32, X15) |
| deploy-fly | skeleton | only on a tag, with `vars.FLY_DEPLOY == 'true'`; its first run is the v2.2.0 tag at the M3 exit (D1, X2) |

**Every job builds through `build.{sh,bat} <profile>`** at the repo root (D7), the one place the four family flags
live; so do the Dockerfile, the e2e global setup and `load-tests/run.sh`. `ols.json` at the repo root is pinned to
`full`'s families, so editors resolve the collections the way `full` builds them.

**Versioning**: SemVer. v1.2.0 is the frozen skeleton (709bc94, the parity baseline) and v1.2.1 its last release
(6d37506, the `Content-Length` crash fix, which Fly serves until the M3 exit); an optional QPSG backport would be
v1.2.2 on `skeleton-1.x` (D1). **v2.0.0 at the M1 exit**, tagged with `FLY_DEPLOY` still off; Fly is redeployed only
by v2.2.0 at the M3 exit (D1, X2, Q29). Each later milestone is one minor release (M2 = v2.1.0 … M12 = v2.11.0); M13
is a spark CL, and the optional M14 takes the next minor after M12's (D44, X42); a major only for a breaking change.
Conventional Commits and the CHANGELOG policy carry over (`SK/CLAUDE.md`).

**Public-repo hygiene** (ANSWERS F4): the repo is public, so D45's rule applies to every commit: the research notes,
the proposals, `OUTLINE.md` and `docs/private/` are git-ignored, and committed docs name no LAN address, apollo
hardware or service list, user name or host path.

**Images**: distroless `base-nossl-debian13` with `USER 10001:10001` (Linux binaries need only libc and libm,
10 §8.1; whether that holds with SQLite linked is checked with `readelf` at M3, UNVERIFIED); an in-binary
`--healthcheck` instead of bash (06 §3.1); never ffmpeg (S21); `THIRD_PARTY_NOTICES`, a `/licenses` route and a
`SOURCES.md` (10 §8.3).

**Rejected.** CF §11.3's `user: 65532` (it fails the inherited docker check, unmentioned). The "no clang" build gate
(D18).

**Alex confirms:** yes (Q18, public GHCR images: default stands (not overridden); Q30, the agent as a release asset:
default (not yet raised)); Q29 answered 2026-10-25: yes, Fly is redeployed only at the M3 exit.

### D41. Hosting stages and proxy configuration

**Decision.** apollo comes first, before anything goes public (S20):

| Stage | URL | Gate to enter | Gate to leave |
|---|---|---|---|
| 0 dev PC | `http://127.0.0.1:<port>` (`run.*`); optional local Caddy `tls internal` for h2 (03 §9) | — | CI green |
| 1a apollo LAN direct | `http://<host>.alexh95.com:8120` on `<APOLLO_LAN_IP>` (the stack Caddy, Host-routed), reached through split DNS (below, X41); a request without a known host gets 421 (X23) | M3: Alex has created `<APOLLO_DATA_DIR>/odin-htmx-starter` and the split-DNS records | smoke + two-host k6 (dev PC → apollo) |
| 1b apollo LAN via NPM | `https://<host>.alexh95.com` with split DNS to `<APOLLO_LAN_IP>` and an NPM Access List "LAN only" | Alex: NPM hosts (the split-DNS records exist since 1a) | 1 h NPM soak, e2e smoke; the family beta from M6 (Q23) |
| 2 apollo public | Access Lists removed except on `/term*` and `/admin*` (also LAN-only in-app); the split-DNS records of the names that go public deleted | the M12 security gate and Alex's go | any of: uptime, the shared-host blast radius, apollo's CPU or disks under video load; the uplink is not a binding trigger (below, X41) |
| 3 VPS | OVH VPS-2 (€7.21, 4/8 GB) or Hetzner CX33 when orderable, with spark's compose + Caddy https flavour | Alex's decision | — |

**The stack** (`deploy/compose.yaml`): services `caddy` (published as `8120:80`, X23; 8120 looked free, UNVERIFIED,
08 §6.5; a fixed `ipv4_address` on the stack network, X43), `starter-full`, `starter-lab`, `starter-minimal`,
`starter-streams`, `starter-skeleton`. Every app service has: the image pinned by tag in `.env`; `user: 10001:10001`;
`read_only: true` and `tmpfs: /tmp`; `security_opt: [seccomp=./seccomp-io-uring.json]` (`promote.ps1` stages
`deploy/docker/seccomp-io-uring.json` next to `compose.yaml` on apollo; the `docker` job and M3 confirm the path, X21);
`init: true`; `restart: unless-stopped`; `stop_signal: SIGTERM`; `stop_grace_period: 10s`; `ulimits: {nofile: 65536}`;
`logging: {driver: local, options: {max-size: 20m, max-file: 5}}` (13 §5.6); D38's cpu and memory limits; `healthcheck:
{test: ["CMD", "/app/bin", "--healthcheck"], interval: 10s, timeout: 3s, retries: 3}` (valid compose, X20); the stack
network, whose subnet compose pins, with `TRUST_PROXY` set to `caddy`'s fixed `ipv4_address` as a /32, not to the subnet
(X43); no published port, since only `caddy` publishes one; for `starter-full`, a volume at `/data` (DB, backups, media,
recordings). Its second, session-free origin needs no compose entry: `SITE_URL_LAB` defaults to
`https://houston-lab.alexh95.com` in `cmd/full/brand.odin` (D10, D25).

**The stack Caddyfile** (multi-line blocks only; Caddy's lexer rejects tokens after `{` on the same line and has no
`;` separator). The candidate below must pass the proxy-config CI job before it goes into any doc:

```caddyfile
{
	auto_https off
	servers {
		# X39: the gateway of the stack's own Docker network, which NPM's connections arrive from (measured);
		# it also trusts any other container on apollo that reaches the published port (the residual risk, below)
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

# D25: full's second, session-free origin, the same container
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

**The trusted proxy** (X39). The devices session measured `<NPM_UPSTREAM_ADDR>`, the address NPM connects to the stack
Caddy from, as the gateway of the stack's own Docker network, not NPM's container address: Docker masquerades traffic
from another bridge, or from the host, to that gateway, while LAN clients that connect straight to `:8120` keep their
own address. So Caddy's one `trusted_proxies` entry is that gateway. The **residual risk** is written down and accepted:
any container on apollo that reaches the published port could claim a client address, and those containers are Alex's
own services. The app's `TRUST_PROXY` is Caddy's fixed address alone, as a /32, not the subnet: the gateway sits inside
the subnet, so with the whole subnet trusted, a process on apollo's host that connected to an app container directly
would arrive from the gateway and be trusted for `X-Real-IP` (D35, X31, X43). The last block answers 421 with one line
that points to `docs/OPS.md`; stage-1a LAN testing therefore uses a host name through split DNS (X23, X41).

No `encode` anywhere: assets arrive precompressed, NPM gzips HTML, and streams stay raw. S0.8: the encoder adds no
delay worth counting, but a compressed stream holds 1.1–2.8 MiB of Caddy's memory, so streams opt out with
`Cache-Control: no-transform`, which Caddy's `encode` honours: a compressing Caddy needs no matcher. Caddy is never reloaded on app deploys, because a reload force-closes WebSockets
(08 key facts).

**apollo's NPM is older than the v2.16.0 the plan modelled** (X40; the exact version is in `docs/private/SITE.md`).
The `e2e-proxy` job pins and models apollo's actual version (D40). Upgrading NPM is Alex's optional step and never an
agent's.

**NPM proxy hosts** (08 §3.2), four, all forwarding to `http://<APOLLO_LAN_IP>:8120`:
- **houston** (`houston.alexh95.com`), **houston-lab** (`houston-lab.alexh95.com`: the stack Caddy routes it to the
  same `starter-full` container, ANSWERS F2), **starter** (`odin-htmx-starter`, `htmx-odin-starter`,
  `starter-minimal`, `starter-streams`), **skeleton-lan** (`starter-skeleton`, LAN Access List forever).
- Details: Websockets Support **on**, Block Common Exploits **off**, Cache Assets **off**. SSL: the `*.alexh95.com`
  certificate, Force SSL, HTTP/2 **on**; HSTS with a short max-age and no includeSubDomains from stage 2.
- Access List "LAN only" (192.168.0.0/16) during 1b; at stage 2, houston keeps LAN-only custom locations for `/term`
  and `/admin` (per-location access lists in NPM are UNVERIFIED; the in-app `.Lan_Only` covers it regardless) and a
  custom location `/term/agent` that answers 403. houston-lab needs no custom locations: `/term*` and `/admin*`
  404 there (D25).
- Advanced tab (server level, inherited into `location /` because it defines none of these):

  ```nginx
  proxy_read_timeout 1h;
  proxy_send_timeout 1h;
  proxy_request_buffering off;
  client_max_body_size 16m;      # 4 MiB upload chunks plus headroom
  proxy_max_temp_file_size 0;    # never spool video to NPM's disk
  ```

  Never `proxy_set_header` or `add_header` there: NPM's `location /` defines both, so they would be dropped (08 §3.1).
  The app sends `X-Accel-Buffering: no` on every stream, so `proxy_buffering` stays at its default.
- Global (Q14: yes, 2026-10-25; Alex's step at M3, X40): `/data/nginx/custom/events.conf` with
  `worker_connections 4096;` before the M3 soak, the first soak through NPM (apollo's NPM still runs the default 512,
  which caps about 1,000 proxied streams across all of Alex's sites).

**Split DNS** (Alex, decided 2026-10-26; X41, DEVICES-SUMMARY): seven DNS-only `A` records, one per apollo name in D2,
pointing at `<APOLLO_LAN_IP>`, which Alex adds at M3 before the first LAN deploy. Each overrides the public wildcard
for its name, and every resolver gets the same answer, secure DNS included; outside the LAN the names lead nowhere,
which is what stages 1a and 1b mean. Alex accepted the private address appearing in public DNS. At M12 the records of
the names that go public (all but `starter-skeleton`, which stays LAN-only) are deleted, so the wildcard applies again
(inside the LAN those names then hairpin through the router unless a LAN DNS is added: a stage-2 question). k6 no
longer needs `hosts` overrides on the LAN.

**The uplink** (`<HOME_UPLINK>`, X41) is not a binding stage-2 trigger: public video from home is plausible at family
scale before apollo's CPU or disks bind, so Q26's CDN becomes optional.

**Home devices** (X41; DEVICES-SUMMARY, PLAN §20.8). The pipeline needs none of the optional devices: M0–M12 run on
the dev PC, GitHub CI and apollo, and two-host load runs stay dev PC → apollo. The roles that land in the plan: the bot
host on apollo's spare GPU (D31), the Pi 4 terminal target with a Pi 3B+ as the second device (D32), the VR headset for
WebXR in the game embed (D34), and an old Android phone as the oldest-browser device (D37). The other roles (an uptime
watcher of apollo from off the box, a Windows test client, a second load generator, the tablet, the handheld gaming
PC) are optional, and none of them blocks a milestone. The device-driven features are M14's, scheduled, optional and
after M12 (Q33: yes, 2026-10-26; D44).

**Fly's role**: only the `skeleton` witness at `odin-htmx.alexh95.com`. From M0 (D1 step 1) it serves 6d37506
(v1.2.1) untouched until the M3 exit, when v2.2.0's `deploy-fly` run first deploys the starter (D1, X2; Q29: yes,
2026-10-25). From then on `fly.toml` builds `cmd/skeleton`, the concurrency stays `type = "requests"`, soft 200 / hard 250 (no streams in this
profile, `SK/fly.toml:45-48`), `kill_timeout` 10 s for the drain, the `/healthz` check, `:memory:` reseeded per deploy
in D17's mode. Houston never runs on Fly (streams, video egress at $0.02/GB, the 6.25 % CPU baseline; 08 §2.5).

**Fly's cost** (Q15, answered 2026-10-25: keep the witness, with no allowance check): at M0, at the M3 exit (the
first starter deploy), at every milestone exit after it, and whenever `fly.toml`'s machine size changes, the agent
reads the witness's monthly cost (read-only, or asks Alex for it when it has no access to Fly's billing) and records
it in the spike or exit report. Above $10/month, it warns Alex at once; the witness keeps running until Alex decides.

**VPS fallback**: move when a stage-2 trigger fires. LAN-only backends (llama.cpp, the Pi) then need a WireGuard link
from the VPS to the LAN, or those features stay on apollo (08 §3). Public video may go through bunny.net (Q26, now
optional, X41), never Cloudflare's CDN (S20).

**Rejected.** The proposals' Caddyfiles with tokens after `{` (RF §11.2, PF §11.4) or `;` separators (CF §11.3); NPM
pointed at container names (a stale IP for up to 10 s after a recreate, 13 §4.3). Joining NPM to the stack's network,
so that Caddy could trust NPM's container alone (X39): it would change NPM's configuration, which is Alex's service,
and PLAN §20.4 never names containers. For split DNS (DEVICES-SUMMARY): the ISP router's static host table, which
served its own address next to the wildcard's alias, so resolvers that follow the alias reached the public address; a
Pi as the LAN DNS, which misses devices on secure DNS and adds a device to keep alive; hosts files, which don't reach
the family.

**Alex confirms:** answered 2026-10-25: Q14 yes; Q15 keep the witness, and warn Alex above $10/month; Q29 yes. Split
DNS decided 2026-10-26, with the private address in public DNS accepted (X41). Stages 1b and 2, the DNS records at M3
and M12, and any NPM upgrade (X40) are Alex's steps.

### D42. Deploys, backups and rollback

**Decision.** `deploy/promote.ps1` follows spark's model without `docker save` (S21, 08 §5.4-5.5, 13 §4.4). It runs
from the dev PC over the SSH alias `<APOLLO_SSH_ALIAS>`; Alex adds a permission rule for it as for spark's, and agents
run it only when Alex asks. Per run:
1. stage the compose file, the Caddyfile, `.env` (the tag) and `deploy/docker/seccomp-io-uring.json`, next to
   `compose.yaml`, which references it as `./seccomp-io-uring.json` (D41, X21);
2. `docker compose pull`;
3. take the pre-deploy snapshot (`docker exec … --backup /data/backups/pre-<tag>.db`, keep 5; after v2.4.0's promote
   `/backups/pre-<tag>.db`, beside the nightly backups in `BACKUP_DIR`, which M4-12 moved off the database's volume);
4. `docker compose up -d --no-deps <service>`, one profile at a time; Caddy is not reloaded, and `lb_try_duration`
   turns the deploy gap into latency rather than 502s;
5. smoke through the LAN and NPM URLs: `/readyz`, `x-version == tag`, an SSE first event, a WS echo;
6. write `deployed.json`;
7. on failure, re-promote the previous tag automatically, restoring the snapshot only if a destructive migration ran
   (migrations are additive, D16).

`promote -Status` is a read-only inventory (RAM, disk, kernel, Docker's fd default, NPM version, reachability of
`<APOLLO_LAN_IP>:8111` for the games API), recorded at M3. Backups follow D16; off-box copies per Q16.

**LAN load tests** (Q24: yes, 2026-10-25): agents may run load tests against apollo over the LAN of 10 minutes or
less, announced to Alex first and with the services' D38 cpu caps in place; the apollo facts of S0.12 are collected
at M0.

**Alex confirms:** yes (the permission rule; Q16: default (not yet raised)); Q24 answered 2026-10-25: yes to both.

### D43. spark integration

**Decision.** No starter milestone waits on spark: the iframe works with no spark change (S22, verified in 06 §2.0),
and every spark change is an Ark CL through spark's ladder, CI and an apollo promotion that Alex runs, or that an agent
runs when Alex asks (06 §2.9).

| # | spark change (Ark CL) | Where | When | Starter dependency |
|---|---|---|---|---|
| SP1 | `GET /api/games` (about 50 lines) + contract checks | `ws/portal/src/controllers/api.odin`, `routes.odin`, `tools/portal-test.mjs` | proposed at the M10 start | `catalog_api`; `catalog_static` until then |
| SP2 | a `frame-ancestors` allow-list on `/play/*` from `SPARK_FRAME_ANCESTORS` (Houston's LAN and public origins) | `ws/infra/compose/Caddyfile:22-26`, `infra/prod/Caddyfile.prod:25-29`, `apollo.env` | M10, **before stage 2** | none (hardening: `/play/*` is frameable by anyone today, 06 §5) |
| SP3 | an embed-mode webcheck test | `games/hello/tests/web/` | with SP2 | none |
| SP4 | a note that healthz `players` is depended on | `ws/CLAUDE.md` | with SP1 | the presence poller |
| SP5 | backports: the markdown depth cap, the `client_address` trusted-proxy fix, QPSG at open, dbview off the exclusive lock | `portal/src/views/markdown.odin`, `controllers/middleware.odin:403-408`, `repository/*` | after M4 | none (fixes spark's own S6 items) |
| SP6 | `UPSTREAM.md` with two pins (`Skeleton commit` kept, `Starter commit` added); `upstream.ps1` reads the repo URL from it and fails loudly (an `error` field in `last.json`); watched paths from the starter's `tools/upstream/paths.json` | `portal/UPSTREAM.md`, `tools/upstream.ps1`, `tools/versions.ps1` | after M1 | none |
| SP7 | a postMessage bridge in embed mode (score, share, crash; target origin from an allow-list, never `*`) | `shared/web/modules/core.js`, `share.js`, `defaults.json` | phase 2, after M10 | instant leaderboard refresh, richer invites |

**What the starter takes back from spark** (06 §3.1, with its preconditions applied):

| How | Pieces |
|---|---|
| as is | the `shared/sqlite` additions and `-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1`; Permissions-Policy (minus `interest-cohort`); the `X-Robots-Tag` prefix table; per-route body caps and quiet logging of noisy paths; `limits.odin`; `clean_name`; the catalog cache pattern; distroless + `--healthcheck`; `pagecheck.mjs` as a fast CDP smoke layer beside Playwright |
| with a fix | `markdown.odin` with the depth and input caps; the auth parts (argon2id encoding, CSRF derivation, cookie flags, `--hash-password`) generalised to server-side sessions; dbview on a pool reader connection; `client_address` behind the trusted-proxy check |
| as a pattern | the forward_auth gate (not needed in v1); `ticket.odin` for device and handoff tokens; wsserver's RFC 6455 coverage table as a checklist, its limits and the fault-injection idea, not its I/O loop (S2). wsserver has no unit tests (03 §5.1), so the starter's strict codec gets new ones, plus a nightly Autobahn\|Testsuite run against the lab's WS echo (D12, X24, NEW) |
| not taken | `shared/wt` (WebTransport, MsQuic) |

**Licence** (Q17: yes, 2026-10-25): the spark modules the starter adopts are licensed zlib, and spark gets a LICENSE
file (an Ark CL, like every spark change). Their LAN and host details are still scrubbed before they enter the public
repo (D45).

**Later (M13, optional)**: the portal rebuilt on the starter, module by module inside spark's Ark workspace, gated by
spark's unchanged L2/L3/L4 tests, keeping the `SPARK_*` env, `/auth/gate`, the `/api/*` shapes, the `0001_init.sql`
hash (adopted by the migration runner) and the `spark_admin` cookie (06 §4). spark's builder pin (84bc3fc =
dev-2026-10) must compile the starter code it consumes.

**Alex confirms:** yes (every CL's approval and promotion); Q17 answered 2026-10-25: yes, zlib ("you can [license] it to
zlib", ANSWERS round 1).

### D44. Milestones, effort, cut list and risks

**Decision.** Effort is in agent-hours (one focused agent, including tests and docs). Spike code that implements fork
or stream pieces becomes M1/M2 code and is costed once, in M0. No exit gate needs a package scoped to a later
milestone: M1's crash drills are request-path only (streams arrive in M2), Houston's `cmd/full` first exists at M4, and
`full` and `lab` (and so `full-vanilla`) gain each feature's lines in the milestone that builds it (the lab's wiki at
M8; houston-lab's demos at M4, D24).

**The slice gate** (every exit from M4 on adds it to its own checks):
- (a) route-coverage parity with 0 unexplained waivers;
- (b) e2e green in 3 engines on `full` and on the feature's singleton generator output;
- (c) the feature's load budgets met, and the skeleton parity gate re-run green;
- (d) the feature's limits declared to `platform/obs` by its `init`, crash drills for new entry points, a 1 h soak with
  the feature's traffic, TSan clean where shared state was added;
- (e) `docs/audit/M<n>.md` with 0 open CRITICAL/HIGH and audit-debt under the limit;
- (f) CHANGELOG, the feature README (and so CATALOG.md), and the PHILOSOPHY ledger if a dependency changed.

**M0 spikes** (40 h). Each writes `docs/spikes/S0.<n>.md` with its criterion, result and decision; a failure changes the
design before M1.

| Spike | Closes | Pass criterion |
|---|---|---|
| S0.1 Baseline capture | the reference and its noise band are unsettled | HEAD and v1.1.1 built by `tools/baseline`; n = 3 interleaved rounds × every scenario × {mem, file} × {Windows, Linux}; noise band recorded; Linux `scale@200` refusals re-checked (12 §2) |
| S0.2 The fork under the skeleton's k6 | "a forked odin-http keeps the request-path throughput" (03 §10.4) | 709bc94 rebuilt on the fork with F-1 and F-5…F-12: paired ratio ≥ 0.97 against HEAD on every scenario, both legs |
| S0.3 htmx extensions in real browsers against Odin streams | hx-sse/ws/multipart never ran in a browser against Odin (digest critic) | 03's 29 contract checks as Playwright specs against a `platform/stream` prototype on the fork: Chromium and WebKit pass; Firefox in CI at M2 |
| S0.4 `:memory:` parity | D17 | candidates A, B, C on every `:memory:` cell with sort indexes, both legs; pick the first passing one, else Q6 |
| S0.5 Workers and argon2id | the login flow off the loops is unverified (07 §5.2) | fresh timings (3 presets, n = 10); pool + `next_tick` reply + generation check: a disconnect mid-hash causes no use-after-free under ASan; 50 logins/s keep `/ui/ping` p99 within +10 % |
| S0.6 The guard in the fork + watchdog | 13 verified the pieces, not the integration | the 15 crash kinds plus `sqlite` via TEST_ROUTES on Windows and Linux; pure → 500 + 20/20 bystanders; lock, async, sqlite → exit 70 ≤ 6 s; WAL size flat after 1000 pure traps mid-iteration (the reader-statement reset); 10k malformed requests including CL −5 → 0 deaths; the watchdog exits ≤ 11 s on a 15 s block |
| S0.7 Drain and restart | 13 §4.1's unbounded waits | exit ≤ 6 s with 500 SSE + 500 WS + a slowloris + a half body + a stuck idle peer; WS got 1012; the bind retry succeeds after `kill -9` at 0/50/100 ms |
| S0.8 Caddy and streams | whether Caddy's `encode` delays SSE events or multipart chunks (03 §8) | a native `caddy run` (dev tool, no Docker): events and parts arrive ≤ 50 ms after the write, with spark's `encode zstd gzip` and without; decide the matcher |
| S0.9 Linux leg on the dev PC | 12 and 13 measured mostly on Windows | Odin dev-2026-10 installed in WSL2 (Q5: yes, 2026-10-25), with 03 §10.3's obj + lld recipe only as the fallback; a TSan build runs |
| S0.10 Bundles | S13's mechanics; the Windows brotli gap | `tools/bundle` builds the four bundles + br/gz from the `EXTS` scan; `bundle-race.spec` 9/9 per engine with assets delayed 400 ms; the minimal bundle's SHA equals the skeleton's `htmx.min.js` |
| S0.11 Tuned SQLite | S10 flags across OSes | builds on Windows and Linux (macOS in CI at M1); size delta ≤ 230 KB; the skeleton's store tests pass |
| S0.12 apollo facts | 08 §9, 13 §8 | Alex provides `uname -m`, `nproc`, `free -h`, `df -h <APOLLO_DATA_DIR>`, the kernel, the NPM version and the NPM container's `ulimit -n` (Q24: yes, 2026-10-25); the address NPM connects to the stack Caddy from is recorded for Caddy's `trusted_proxies` (D41, X31). The devices session already measured that address as the stack network's gateway (X39) and apollo's NPM version (X40), both in `SITE.md` |

**Milestones.**

| M | Scope | Exit gate (all must hold) | h | Release | Alex |
|---|---|---|---:|---|---|
| **M0** | the spikes above (S0.2's fork vendored in-tree at `app/vendor/odin-http/`, D11); D1's transition: the v1.2.0 and v1.2.1 tags and `skeleton-1.x`, this workspace as the renamed repo's checkout with `_ref/` removed, the scrubbed planning docs committed (D45) | every spike has a decision record; the workspace is the checkout; Fly confirmed serving 6d37506 and its cost recorded (D41) | 40 | — | re-run 6d37506's failed CI so it deploys (or ask the agent to), then `FLY_DEPLOY` off (D1 step 1); the rename (Q1: yes); the apollo facts (Q24: yes); Q6 if S0.4 needs it |
| **M1** Request-path substrate, `skeleton` at parity | the fork productionised in `app/vendor/odin-http/` (F-1…F-13, D11); `platform/{sys, ext, guard, obs, env, app, web, html, authz, authz/anonymous, store, store/sqlite, store/memory, sqlite, workers, markdown, theme/full, theme/lite, client/vanilla}`; features dashboard, gallery, contacts, about, notes, home, with their `models` packages, contacts' SQLite store and notes' stores in both families under `app/stores/{sqlite,memory}/` (D4); `cmd/skeleton`, `cmd/minimal`, each as D7's four hand-written files; `build.{sh,bat}` and `ols.json` at the repo root (D7); the migration runner adopting skeleton databases; the skeleton's 23 specs ported and tagged; route counters; `tools/{check, baseline, bundle}`, with `tools/check` `profile`, per-host `routes`, `contracts` and the collection rules in `imports` (D39), and `tools/bundle` over the compiler's package list (D19); CI pins, build, check (every store package checked alone in both families), e2e, docker, linux-ops, nightly ASan, every job through `build.*`; audit stamps begin | the parity gate green on both legs; the 01 (A) checklist green; ported specs green in 3 engines (Firefox in CI) + the api project; request-path drills (panic, bounds, div, nil, stack, lock, async, sqlite, hang), fuzz smoke, shutdown bound with slowloris, half body and idle peers, restart, fd ceiling with keep-alive connections; skeleton ≤ 2.75 MiB, idle ≤ 6 MB + 0.4 MB per loop, boot → `/readyz` ≤ 50 ms; minimal builds with no SQLite library; route coverage with 0 unexplained waivers; `docs/audit/M1.md` 0 CRITICAL/HIGH | 70 | **v2.0.0**, tagged with `FLY_DEPLOY` still off; Fly keeps serving 6d37506 (v1.2.1; X2) | rename done; `FLY_DEPLOY` stays off (Q29: yes) |
| **M2** Stream substrate, bundles and CSP, `streams` and the lab pages, generator v1 | `platform/{stream, stream/client, hub}`; `/events` with the cursor procedure; heartbeats, pong deadline, caps, policies, close codes; the writer task; page bundles; flags → CSP; `client/hyperscript` with the gate; features chat (memory, 4 transports behind one switch), notify (memory), bot (memory, mock, SSE and multipart delivery), ops, status (basic), scripting, compat, lab; the `nick` identity, ahead of the rest of accounts (ANSWERS round 9); `cmd/streams`, `cmd/lab` (lab pages only); `tools/streamload`; `tools/init` compose mode (`--list --json`, `--explain`, `--profile`, `--features`, `--add`, `--without`, the family commands, `--verify` through `build.*` and `tools/check profile`; D26), writing and editing D7's four profile files with parser-planned edits; `tools/check topics`; the generator job and singleton rotation; `deploy/Caddyfile` and the `e2e-proxy` job that runs it in CI (X26); the nightly Autobahn\|Testsuite run against the lab's WS echo (X24) | S0.3's specs and the lab specs green in 3 engines and through e2e-proxy; fan-out, restart (4000 back ≤ 3 s), replay and resync, back-pressure budgets; stream drills (`wsdata` → 1011; shutdown ≤ 6 s with 500 SSE + 500 WS; fd ceiling with 3000 streams); TSan 0 reports on hub, stream, workers and store/sqlite (S0.11), with one suppression for `core:nbio`'s mpsc assert until an Odin bump fixes it (S0.9); 1 h soak; headers, csp-clean, csp-enforced, bundle-race, streams-hxcsp green; minimal, streams and lab built with no SQLite library; generator job green; parity gate green; audit | 65 | v2.1.0 | — (Q32 answered: `bot` is in `streams`) |
| **M3** Pipeline, apollo LAN, the landing page | the release workflow (GHCR multi-arch); `deploy/compose.yaml`, the Caddyfile's apollo deploy, `promote.ps1` (staging `seccomp-io-uring.json` next to `compose.yaml`, X21); the proxy-config job for NPM's nginx (X26); `landing` and the status witness board in `cmd/lab`; stages 1a then 1b; two-host load; 1 h NPM soak | minimal, streams, skeleton (LAN) and lab deployed by `promote -Target apollo-lan -Tag v2.2.x` with smoke; a deliberately broken tag rolls back by itself; 0 5xx through Caddy during a promote under 50 VUs; 1000 SSE through NPM held 1 h with no idle cuts; `readelf` confirms the distroless base with SQLite linked; every redirect alias passes its curl test; the seccomp path, the `8120:80` publish and the 421 catch-all confirmed (X21, X23); the apollo inventory recorded; parity gate green (X25), with `starter-skeleton` passing it and the 01 (A) 40-item checklist on apollo's LAN (stage 1a) before Fly is redeployed (X2); the Fly cost recorded after that deploy (Alex warned above $10/month, D41) | 30 | v2.2.0; its `deploy-fly` run redeploys Fly from `cmd/skeleton` (X2) | create `<APOLLO_DATA_DIR>/odin-htmx-starter` (sudo); split DNS: the seven DNS-only `A` records pointing at `<APOLLO_LAN_IP>`, before the first LAN deploy (D41, X41); the four NPM proxy hosts (houston-lab included, D41) and the Access List; the promote permission rule; NPM's `worker_connections` 4096 before the soak (Q14: yes; X40); optionally, upgrade NPM (X40; the `e2e-proxy` pin then follows); set `FLY_DEPLOY=true` before the v2.2.0 tag (Q29: yes) |
| **M4** Identity and the Houston shell | accounts (with envadmin; nick is M2's, ANSWERS round 9), authz enforcement (route perms, step-up, `.Lan_Only`), audit, modules; `cmd/full` (home and Today cards, nav from brand.odin, themes including `houston` and `accounts_prefs`; houston-lab through `SITE_URL_LAB` and its own host table, D25: `landing` at its root, notes, dashboard at `/dashboard`, gallery, contacts and about, the notes and contacts demo data capped and reset nightly, lab, scripting and compat), the hyperscript behaviours and their vanilla twins, `full-vanilla` (`./build.sh full-vanilla`); pairwise and selection fuzzing start nightly | slice gate; `rbac.spec` over 100 % of routes × roles × hosts, freezing the default grants (Q31) and the per-host tables (every houston-lab row 404s on Houston's host and the reverse); houston-lab's nightly demo resets run; `headers.spec` and `csp-clean.spec` on both of `full`'s hosts, `csp-enforced` and `streams-hxcsp` on `houston-lab` (D37); CSRF and CSWSH specs; `revoke.spec` (X19); the login-storm budget; behaviour duality (full and full-vanilla); the argon pool memory cap; injected `_` inert; Houston and `houston-lab` deployed at stage 1b (no invites yet) | 50 | v2.3.0 | Q10, Q11, Q31 (defaults stand); Alex runs `--hash-password` for the bootstrap admin and never shares the password |
| **M5** Operate | ops, status (full), jobs (with leases; backups as jobs), dbview | slice gate; one ops render per second whatever the number of viewers (CPU flat from 1 to 100 viewers); status parts swap independently (parallel order asserted); a backup and restore drill; dbview never takes the writer lock | 28 | v2.4.0 | — |
| **M6** Comms and the family beta | chat on SQLite (rooms, DMs, retention, presence, typing, receipts, moderation, attachments, FTS), notify (SQLite), uploads, the connection-mode setting | slice gate; 4 transports × resume specs (including across a restart); the retention spec (`CHAT_ROOM_CAP=5`, send 7 → 5 + the marker); the WS chat budget at 1000 sockets; the writer task ≥ 3× autocommit at 1000 msgs/s; the XSS/UGC suite; an upload decode-bomb fuzz; D22's core flows on the oldest-browser device with no client behaviours (D37; htmx 4 there UNVERIFIED (M6)); a focused security audit of accounts, sessions, chat and uploads with 0 CRITICAL/HIGH **before the first invite** | 65 | v2.5.0 | Q23: invite the 2–3 beta members |
| **M7** Ask | the bot (SQLite store, llama binding, fakellama, room mode over `bot.ask` and `chat.reply` (X37), the default on `/admin/bot`, health badge); once Alex's llama.cpp project runs, `BOT_LLAMA_URL` = `http://<APOLLO_LAN_IP>:<LLAMA_PORT>` and the tokens/s measured with `llama-bench` (D31, X41) | slice gate; room mode stores the bot's answer as a chat message, and a selection without bot drops and counts `bot.ask` (X37); deterministic token e2e; Stop ≤ 100 ms; the queue spec with `BOT_CONCURRENCY=1`; the fakellama parser suite; the 1000-generation mock budget; `x-impl` specs | 25 | v2.6.0 | the llama.cpp compose project on apollo (Vulkan image pinned to a build, the render device of `<APOLLO_GPU>`, an API key file, `cpus: 1.0`), a model on the spare disk, and a check of the power supply's rating for sustained GPU load (D31, X41); optional real-model smoke |
| **M8** Plan | wiki (with the seeded docs), find (with the palette), lists (checklist and board), polls | slice gate; FTS MATCH ≤ 3 ms at 100k messages; find respects membership; a wiki markdown fuzz (depth cap) with 0 crashes; board drag and drop (trusted mouse input) and the button fallback both pass; history-cache back/forward with zero server hits on the wiki | 50 | v2.7.0 | — |
| **M9** Watch | video (its store in both families: `catalog_file`, the manifest scan, and the SQLite metadata; Range, HLS + MP4, captions, chapters, resume, signed URLs, web-ready uploads, `tools/transcode`) | slice gate; the Range contract (200, 206, suffix, 416, HEAD, If-Range); playback with `channel: 'chrome'`; 256 MiB ≤ 8 MB peak on Linux; signed-URL expiry; infinite scroll | 35 | v2.8.0 | sample content on the volume (offline transcode) |
| **M10** Play and gather | games (`catalog_static`, `catalog_api` against a stub), c4, calendar, guestbook; SP1–SP4 proposed | slice gate; `games-frame.spec` in 3 engines, with its WebXR spec (`xr-spatial-tracking` in the embed's `allow` list, D34, X41); the poller makes ≤ 3 GETs per 5 s against spark; previews proxied; c4 spectators; the ICS feed parses in the spec; the guestbook moderation-queue spec | 40 | v2.9.0 | approve and promote the spark CLs; optionally, try a WebXR game in the embed on the VR headset (D37) |
| **M11** Terminal | T1 (15 h) → T2 (55 h: the agent's VT, the grid protocol, the server grid and renderer) → T3 (20 h); start-of-milestone spikes: `hx-ws:send` on a custom trigger, the agent-side grid protocol | slice gate; the agent against `/bin/sh` in CI; replay-agent golden screens (vim, less, htop, the `tput` matrix); 24 h VT fuzz with 0 crashes; 80×24 render ≤ 100 µs; LAN echo p95 ≤ 50 ms on the real Pi; a watcher can't type; kill closes both sides; every terminal action audited; recordings written by the server | 90 | v2.10.0 | bring the Pi 4 home, flash 64-bit Pi OS Lite, wire it and reserve its address (D32, X41); copy the release's `term-agent` binary over, install the unit and `/etc/houston/term-agent.env`, issue a device token (Q30); the same on the Pi 3B+, the second device for the multi-device tests (Proposed, to confirm at M11; X41) |
| **M12** Public | stage 2 | the full-tree audit (`docs/audit/M12.md`, 0 CRITICAL/HIGH), audit-debt 0, the 8 h fuzz campaign, the 8 h soak, clean sanitizers; SP2 live; HSTS at NPM; `/term` and `/admin` verified LAN-only from outside; an external uptime check; bunny.net on `/media` if public video takes it (Q26, optional: X41); the public names resolve through the wildcard again; the parity gate green; a public smoke from outside the LAN; the Fly cost recorded (D41) | 20 | v2.11.0 (Houston public) | the go-public decision; remove the Access Lists; delete the DNS records of the names that go public, so the wildcard applies again (D41, X41); bunny.net, only if wanted (Q26) |
| **M13** Portal (optional) | the spark portal on the starter, inside spark's Ark loop | spark's L2/L3/L4 pass unchanged | 60 | spark CL | promotions |
| **M14** Devices (optional, after M12; Q33: yes, 2026-10-26; X42) | **the device registry and feed**: `/admin/devices` generalises `/admin/term`'s device tokens to every device, plus a plain-text `text/event-stream` (unread count, presence, next event, bot health) for screens that can't render HTML, which takes D3's ledger row 8: a non-HTML representation, still rendered by the server; **cameras** (`cams`): Houston pulls each camera's MJPEG stream once and fans it out to members as `multipart/x-mixed-replace`, which a plain `<img>` renders with no JS, LAN-only and members-only first; **the wall and TV dashboard**: a kiosk view of Today, signed in by a device token | slice gate; and M14's own gates, as written, fixed by Q33's answer (ANSWERS round 4; NEW): one upstream pull per camera whatever the number of viewers; `cams` LAN-only and members-only in `rbac.spec`; a device token reaches only its device's routes, and revoking it closes its feed and kiosk streams; the plain-text feed's format spec; the ledger line in PHILOSOPHY.md | ≈ 30 (estimate) | the next minor | Q33 answered (yes); the devices themselves (camera boards, panels, the TV's Pi), their addresses and their tokens; the spare router's fenced network, if wanted |

**Total**: about **610 agent-hours** for M0–M12 (M0 40, M1 70, M2 65, M3 30; then 403 for M4–M12), plus 60 for the
optional M13 and about 30 for the optional M14 (an estimate, below; X42, Q33). The substrate (M0–M3, 205 h) is a third
of it and comes before the first showcase feature; Houston is useful to the family from M6. Against the proposals:
risk-first's 555 h covered less scope (no lab landing, calendar, guestbook, home cards or pairwise CI); product-first's
378 h and composition-first's 329 h for wider scope run 1.5–2× faster than risk-first's rates for the same work (the
engineering judge's comparison), so this plan rescales them.
Alex set no cap on effort ("It's going to take however long it's going to take", ANSWERS #3, 2026-10-25): the hours
are a guide for ordering and sizing, not a budget, and the cut list below is for a slice that stalls, not for staying
under a total. The lean composition (ANSWERS #1, round 3) leaves the hours as they are: there is no profile emitter
and no alias layer, but the generator learns parser-planned edits and `tools/check` gains `profile`, per-host `routes`
and `contracts` (LC §12 item 11; an estimate, NEW).

**M14's hours are an estimate** (NEW), sized after Q33 at the rates of the slices each part resembles, not measured:
the device registry and feed about 12 h, at the rate of M11's T1 (15 h), which builds the device rows and tokens the
registry generalises, plus a plain-text encoder over the hub's topics; `cams` about 12 h, at the rate of M9's Range and
stream work (M9 is 35 h for all of video): one upstream client per camera on `platform/stream/client` and a fan-out
over the multipart writer (D12); the wall dashboard about 6 h, a kiosk layout of M4's Today behind a device token.
About 30 h in all, a guide like every figure here.

**Ideas, not scheduled** (X42; DEVICES-SUMMARY): live video (the USB camera on the Pi → ffmpeg's hardware H.264
encoder → a sliding live HLS playlist under `/media`; ffmpeg on the Pi would be a new ledger line, outside every image);
the radio feed (a Pi decodes APRS packets and an agent posts them to a hub topic; transmitting waits for Alex's amateur
licence); the mesh bridge (a Houston room ↔ a licence-free LoRa mesh, text only); WireGuard into the LAN for the
LAN-only pages from outside (Q9). None is in a milestone, and each is Alex's choice.

**Cut list** (drop from the top first, ordered by product value):
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
per-route e2e and load parity; the audit procedure; the generator with `minimal`.

**Risk register.**

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | The fork costs request-path throughput or stability | low / high | S0.2 before anything builds on it; hot path untouched; 03's contract tests in CI; a small vendored diff, reapplied per bump (D11) |
| R2 | `:memory:` parity can't be met | medium / medium | measured by S0.4: no candidate passes every cell; Q6 answered (C, the failing `:memory:` cells gated against HEAD with documented exceptions, ANSWERS round 5) |
| R2a | (sub-item of R2) file-DB write sits at 0.98× (a ratio of medians, 12 §2), a narrow margin over 0.97 on a noisy box | medium / medium | settled by S0.4: v3's file-DB write measured 0.38–0.43×, so the file DB takes C's group commit too (X17), which writes at 2.9–4.3× |
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
| R16 | Granularity rot | medium / medium | every profile and singleton built in CI; every store package checked alone in both families; boot checks; `tools/check profile`; the pairwise array |
| R17 | The VT emulator's correctness tail | high / medium | T1 ships first; golden screens; fuzz; the parser lives in the agent, the `--worker vt` fallback |
| R18 | Real family users arrive before the public security review | medium / medium | M6's focused security audit before the first invite; invite-only; LAN-only access |
| R19 | The new stream cursor design (D13) has edge cases | medium / medium | M2 resume specs across a restart; the cursor parser fuzzed; resync as the always-correct fallback |
| R20 | A host-table or identity bug puts the eval-capable lab pages on Houston's session origin, or a session on `houston-lab` (ANSWERS F2; NEW) | low / high | per-host tables: a row answers only on the host whose table mounts it; no identity on the lab host; D5's per-host boot checks (`.Lab_Host` only on a host with no cookie-setting identity, every lab-host row `.Public`) and `tools/check routes` per host; `rbac.spec` over every route × both hosts and `headers.spec`'s no-`Set-Cookie` check, from M4 (D25, D37) |
| R21 | Collection plumbing: a build that skips `build.*` fails or picks the wrong family, the editor follows calls into one family only, and the generator's edits meet a profile file reshaped by hand (LC §12 items 1, 2, 8; NEW) | medium / low | `build.{sh,bat}` is the only place the flags live, and every script, CI job, the Dockerfile and the generator call it; a bare build fails loudly ("Unknown library collection"); `ols.json` pinned to `full`'s families; every store package checked alone; `tools/check profile` on every committed profile; the generator aborts with nothing written and names the file |

**Alex confirms:** no for the plan's shape (no effort cap, ANSWERS #3); the Alex column lists each step that needs
Alex. M14 is yes (Q33: answered 2026-10-26: yes, with the default scope; ANSWERS round 4).

### D45. House style and documentation

**Decision.** The starter's `CLAUDE.md` keeps the skeleton's contract (standing policy, Conventional Commits, code
aesthetics, views and HTML rules, htmx gotchas, validation, CSS and JS conventions) and is updated on purpose:
- **Architecture**: the platform layers and the feature package shape of D4 (models, stores by family, domain, views,
  web, switched impls, identities), with the `tools/check imports` table and its collection rules, and the reading
  test of D4 (LC §2): from `routes.odin` to the SQL by go-to-definition alone.
- **Allocator model**: the three buckets of D12.
- **Crash model**: entry points go through `guard_call`; locks only through `guarded_mutex`; SQLite calls only through
  `platform/sqlite` (it keeps `in_sqlite`); what pure and dirty mean (D15).
- **Recipes**: new feature (models, domain, views, web with its `ROUTES`, `TOPICS`, `JOBS`, `EXTS` and `init`, its
  stores, static, README, then its lines in each profile that mounts it: a mount line per host table, the `init`,
  `start` and `drain` calls, a `migrate` line, a home card; e2e and load scenarios), new store (a package per family
  under `app/stores/<family>/<f>/` with its `contract.odin`, and the feature's `storetest`), new route (a row in the
  package's `ROUTES`, or, for a root, the profile's own row in `routes.odin`; e2e and load in the same change), new
  switched implementation (a package, a case in the web package's switch, its `EXTS` in the web package's union),
  new migration (per store, additive), new topic (a `TOPICS` row: family, policy, ring, persisted, `subscribe`,
  `deliver`), new job (a `JOBS` row, id prefixed by the feature), new behaviour (enum row, `_hs`, vanilla twin or
  empty), new perm (enum group, `ROLE_PERMS`), new env var (a row its `init` reads from `platform/env`, prefix).
- **Gotchas**: build only through `build.{sh,bat} <p>`, because a bare `odin build` lacks the four family flags; store
  contracts are typed constants (`_ : m.Store_Insert : insert`), never `#assert(type_of(…) == T)`, which is false even
  for an exact match (14 (1)); store package names are unique (`<f>_store_<family>`); root rows live only in
  `routes.odin`; feature tables are package-level `[?]T` (09 §4.4); `EXTS` stays on one line; never keep stream state in
  the temp arena; the `fmt` brace rule for JSON and HCON; live logs are `<div role="log">` of `<article>`; `x-impl` on
  runtime-switched axes; boosted links never cross a bundle; hyperscript data only in `data-*`.
- **Families and switches** (it replaces the old "Ports" section): the four families of D8 and why each axis is a
  family, a switch or an env value; the cross-feature edges of D6 (notify by direct import, `store:audit`, the room
  mode rows), each with its reason.

Every feature's `README.md` follows D4's fixed headings and carries its audit stamp; `docs/CATALOG.md` is generated
from them. PHILOSOPHY.md's ledger changes per D3. Docs the skeleton let drift (STRIP.md, the e2e and load PLAN files,
the docker-host backup advice; 01 risks) are rewritten or removed, not copied.

**Public-repo hygiene** (ANSWERS F4, 2026-10-25). The repo is public, so committed docs name no LAN address, no
apollo hardware or list of the services it runs, no user name and no host path. Those live in `docs/private/SITE.md`,
and the public docs use placeholders in their place. `.gitignore` lists `docs/research/`, `docs/design/proposal-*.md`,
`docs/design/OUTLINE.md` and `docs/private/`, so the research notes, the three proposals and the outline stay local;
citations to them keep their form. A scrub pass applies the rule to the planning docs before their first commit
(D1 step 5), and every later doc change follows it (D40); `docs/design/LEAN-COMPOSITION.md` gets the same scrub
before its first commit.

**Alex confirms:** no (the hygiene rule is Alex's, ANSWERS F4).

---

## Appendix A. Errata: errors found in the proposals, re-checked

| Proposal | Claim | Re-check | This design |
|---|---|---|---|
| all three | the minimal profile builds "on a runner with no clang" / "no C toolchain" | 09 line 335: "Unix link = clang (or `$ODIN_CLANG_PATH`, `linker.cpp:613-616`)"; Windows links against MSVC/SDK libs | D18: no SQLite library and no C compile step; the linker stays |
| RF §9.3, PF §9.3 | `-vet-unused-procedures` gates every push | 09 §3 table: "13 hits, mostly false positives … An audit aid, not a gate"; 02 §2.1: needs `-vet-packages` | D39: milestone-audit aid only |
| RF §3.8 | single + QPSG "should hold writes at HEAD's 36k" | the target is max(HEAD, v1.1.1) = 38,908; qpsg measured 35,753 (0.92×); 12 §2 16T mem | D17 |
| RF §6.5 | VT parser in-process in the pure zone, no mention of 13 | 13 §2.1: "a server-side VT emulator goes in a subprocess if ever built" | D32: the VT parser runs in the agent; `--worker vt` fallback |
| RF §3.9/§5.1 | dependencies "never declared twice" | `Feature.extensions` and `cmd/<p>/bundle.txt` declare the extension set twice | D19: one `EXTS` constant |
| RF §4.2/§5.5 | a vanilla twin inside the same binary | markup only ever emitted `_="install X"`; no seam for vanilla | D22: `html.behave` writes either form |
| RF §11.2, PF §11.4 | Caddyfile with tokens after `{` on the same line | Caddy's lexer rejects this (to be confirmed by `caddy validate`, D40) | D41: multi-line blocks, CI-validated |
| RF §2 step 4 | `brand.odin:28` (the engineering judge said line 27) | re-checked: `BRAND_REPO` is on `SK/app/src/views/brand.odin:28`; the judge's nit was wrong | D1 cites :28 |
| PF §11.4 | `redir /minimal* https://starter-minimal…{uri}` | `{uri}` is the full request URI, so the prefix survives and the target 404s | D25, D41: strip the prefix; curl assertions |
| PF §3.6 | `MEMMODE=single` is the parity mode | 12 §2: list 0.55×, pages 0.58×, write 0.92× v1.1.1 on `:memory:`; no sort indexes mentioned | D17 |
| PF §3.7 vs §3.6 | `MEMMODE` default `multi` vs modes ephemeral/single | inconsistent names | D16: `single \| ephemeral` everywhere |
| PF §13 M1 | M1's exit needs 03's 29 contract tests and a wsdata drill | the WS codec, SSE encoder and hub are scoped to M3 | D44: M1 drills are request-path only; streams in M2 |
| PF §9.2 | pass if median ≥ best − noise band | with 25.3–52.1k spreads (12 §2) this passes nearly anything | D38: paired ratios with a floor |
| PF §9.2 + §11.2 | parity at M2 and minor releases; v2.0.0 only at M12 | no parity run between M2 and M12 | D38: every milestone exit |
| PF §4.2 | contacts and search both claim `/search` | `SK/app/src/routes.odin:42`: `/search` is the contacts fragment | D9: `find` at `/find` |
| PF §6.4.1 | the hub skips all of the author's connections | the author's other tabs and devices miss the message | D13: skip nobody; upsert dedups |
| PF §1.1, §5.5 | dependencies stay countable | omits the service worker (§6.4.19) and xterm.js (lab) it adds | D3: never-add list |
| PF §1.2 vs §4.2 | packages stay generic | `/capcom`, `/log`, `/control/console` are branded prefixes | D9 |
| PF §15 | references to "Q15.x" | §15 is numbered 1–17; the file ends with stray `</content></invoke>` | not carried |
| CF §6.3 | chat messages as `<li>` with hx-pending | 04 §5.5: hx-pending wraps clones in `<div class="hx-pending" style="all: initial">` | D14, D30: `<article>` in `<div role="log">` |
| CF §11.3 | `;` separators inside Caddyfile blocks | not Caddyfile syntax | D41 |
| CF §6.3 | a lost ≤ 10 ms batch is "the same window as synchronous=NORMAL" | NORMAL loses commits only on power loss or an OS crash (12 §0), not on a process crash; seeding from `max(id)` then reuses ids | D13, D16: publish after commit, rowids |
| CF §3.4 | one global `<epoch>-<seq>` id for every topic | 13 §7 item 8 recommends rowids in SQLite mode | D13 |
| CF §9.2 | a 1-loop parity leg | every variant is below v1.1.1 at 1T on list, pages and write (12 §2 1T tables) | D17: no 1T leg |
| CF §9.1 | platform overhead ≤ 1.5 µs including routing, while routing alone is ≤ 2 µs | internally inconsistent | D38: overhead ≤ 1.5 µs excluding routing; routing ≤ 3 µs |
| CF §11.3 | compose `user: 65532` | the inherited docker job asserts UID 10001 (`SK/.github/workflows/ci.yml:219`) | D40, D41: UID 10001 |
| CF §3.7 | `TRUST_PROXY` defaults to every RFC 1918 range | any LAN host could spoof `X-Real-IP` (06 §3.1) | D10: empty by default |
| CF §3.2 | `controllers.odin:503-590` | the file has 587 lines (re-checked with `wc -l`) | not carried |
| CF §4.9 | `tools/init/main.odin:122-177` is the "Next" checklist | "Done. Next:" is at line 86; 122-177 is the leftover report | D26 cites :86 |

## Appendix B. Judges' must-fix items → decisions

| Judge | Must-fix item | Decision |
|---|---|---|
| Philosophy | one composition-root mechanism; no profiles.odin | D7 (now four hand-written profile files and one build line, ANSWERS #1) |
| Philosophy | one definition for htmx extensions; no bundle.txt or manifests | D19 |
| Philosophy | behaviours as a closed enum with twins via `html.behave` | D22 |
| Philosophy | closed `Perm` enum + `ROLE_PERMS`; perm and flags on the route row | D5, D35 |
| Philosophy | no BASE_PATH; fix the `{uri}` alias; drop `html.url` | D25, D41 |
| Philosophy | hello = leanest implementations + options literal | D27 (now the leanest families plus a root) |
| Philosophy | generic route prefixes; branding in labels | D9, D28 |
| Philosophy | a small closed ports struct; no open registries; no runtime disabling | D6, D36 (ANSWERS #1 removed the ports struct too: direct imports, a store and topic rows) |
| Philosophy | the domain / views / web / impl shape and the CLAUDE.md rewrite | D4, D45 |
| Philosophy | `/scripting` and `/compat` on their own origin | D24, D25 |
| Philosophy | complete ledger; xterm.js and i18n out by default | D3 |
| Philosophy | VT out of the server process, or an evidence-backed overturn | D32 |
| Philosophy | route-coverage parity from runtime counters | D37 |
| Philosophy | chat markup `<div role=log>` of `<article>` | D14, D30 |
| Philosophy | one typed env table; `TRUST_PROXY` empty by default | D10 |
| Philosophy | per-request switching only on the showcase axes, always announced | D8 |
| Engineering | `:memory:` parity measured with indexes; Q6 before M1; no 1T leg | D17 |
| Engineering | paired-ratio statistics; the gate at every milestone exit | D38 |
| Engineering | guard × reader statements; a trap in SQLite is dirty | D15 |
| Engineering | guard wraps every completion callback the fork owns | D11, D15 |
| Engineering | reword the no-clang gate | D18, D40 |
| Engineering | drop `-vet-unused-procedures` from per push | D39 |
| Engineering | rowids for persisted topics; publish after commit; no pre-allocated ids | D13, D16 |
| Engineering | copy refs out of the hub mutex; the hub lock is guard-tracked | D13 |
| Engineering | eval-enabled pages on a separate origin | D25 |
| Engineering | VT placement picked explicitly | D32 |
| Engineering | one-label subdomains; no BASE_PATH (root SEO files) | D25 |
| Engineering | effort based on ~555 h; spike code costed once | D44 |
| Engineering | no exit gate needs a later package | D44 (M1/M2 drills) |
| Engineering | validate every Caddyfile and nginx snippet in CI | D40, D41 |
| Engineering | WS pong deadline and per-stream caps in the hub spec | D13 |
| Product | reword the S9 gate | D18 |
| Product | eval pages on an origin with no sessions | D25 |
| Product | `/minimal` and `/full` resolve; one public name for the showcase | D2, D25 |
| Product | resolve the `/search` collision with `/find` | D9 |
| Product | `FLY_DEPLOY` paused first; v1.2.0 = 709bc94 unchanged | D1 |
| Product | durable topics resume by rowid with a keyset replay | D13 |
| Product | the hub must not skip all of the author's connections | D13 |
| Product | hello variants: lean implementations + home cards | D27 |
| Product | VT placement; recordings written by the server | D32 |
| Product | re-estimate effort; cut list by product value; the never-cut set | D44 |
| Product | one `MEMMODE` vocabulary | D16 |
| Product | product-first's M1 sequencing | D44 |
| Product | keep UID 10001 | D40, D41 |
| Product | anonymous posting off by default on a public witness | D24, D35 (`ACCOUNTS_NICK_FROM=lan`); D36 (guestbook moderated) |
| Product | stray markup at the end of product-first | Appendix A (not carried) |

## Appendix C. Questions for Alex

Each has a recommended default; the plan proceeds on the default unless Alex says otherwise. Alex answered twelve of
them on 2026-10-25 (`docs/design/ANSWERS.md`, rounds 1 and 2) and a thirteenth, Q33, on 2026-10-26 (round 4), and
overrode no other default; round 3 and the device discussion answered no numbered question (both below the table). The
Status column records each one: **answered**, with the answer and the date; "default stands (not overridden)" for a
question raised with Alex and not overridden; "default (not yet raised)" for one not yet put to Alex.

| # | Question | Options | Recommended | Status |
|---|---|---|---|---|
| Q1 | Promote the skeleton by renaming the repo in place to `odin-htmx-starter`? | rename in place (S19) / new repo with history, archive the skeleton / new repo with fresh history | **Rename in place**, after tagging v1.2.0 at 709bc94 and v1.2.1 at 6d37506, branching `skeleton-1.x`, and setting `FLY_DEPLOY` off | **Answered 2026-10-25: yes.** All starter work happens in this workspace, which becomes the renamed repo's checkout at M0 (ANSWERS #5, F5; D1) |
| Q2 | Host names | `odin-htmx-starter.alexh95.com` = lab + aliases, `houston.alexh95.com` = Houston, `starter-<profile>` witnesses / Houston at the starter root and the lab on `starter-lab` / the brief's `htmx-odin-starter` as canonical | **The first**, plus `htmx-odin-starter.alexh95.com` as a 301 alias | **Answered 2026-10-25: as recommended**, plus `houston-lab.alexh95.com`, `full`'s session-free second origin (ANSWERS F2; D2, D25) |
| Q3 | The showcase's name | Houston / Patchbay / another | **Houston** | **Answered 2026-10-25: Houston** (ANSWERS #6; D28) |
| Q4 | Fork odin-http: where does the fork live, and when is the seam offered upstream? | a separate repo (`alexh95/odin-http`) as a submodule, created now / vendored in-tree in this workspace / either, never upstream | **Fork now; offer upstream after M2** (round 1 named a separate repo; round 2 recommended in-tree) | **Answered 2026-10-25: fork it, vendored in-tree** at `app/vendor/odin-http/` with `UPSTREAM.md` (laytan fac113f plus F-1..F-13), no separate GitHub repo; the upstream offer after M2 goes through a fork made then (ANSWERS #7, F3; D11) |
| Q5 | Install Odin dev-2026-10 in WSL2 for the Linux legs (parity, TSan)? | install in WSL2 / 03 §10.3's obj + lld recipe only / Linux legs in CI only | **Install in WSL2** (one-time dev tooling) | **Answered 2026-10-25: yes** (S0.9, D38) |
| Q6 | If S0.4 finds no `:memory:` mode passing every cell, what does the gate do? | gate the failing `:memory:` cells against HEAD 709bc94 (v1.2.0, the parity baseline) with a documented exception / gate the file DB only and report `:memory:` / block M1 until a mode passes | **Gate the failing `:memory:` cells against HEAD**, file-DB cells never waived; asked with S0.4's numbers before M1 | **Answered 2026-10-26: the default**: candidate C, and the `:memory:` cells it fails gated against HEAD 709bc94 with a documented exception each; file-DB cells never waived (ANSWERS round 5; S0.4) |
| Q34 | The login-storm budget after S0.5 (D35, D38) | restate it in absolute terms (p99 ≤ base + 0.5 ms under `cpus: 2.0`, the cgroup never throttled) and size the argon pool by CPU (1 thread with ≤ 2 CPUs) / keep +10 % and cap logins lower / keep +10 % and give argon CPUs of its own | **Restate it, and 1 thread on ≤ 2 CPUs** (S0.5: a hash costs a core; +10 % of a sub-millisecond p99 is under one busy neighbour core) | **Answered 2026-10-26: the default**: the absolute budget, and 1 argon thread on ≤ 2 CPUs (ANSWERS round 5; S0.5) |
| Q35 | The parity gate's reference on the light routes (D38; S0.1) | HEAD alone on `static` and `seo`, max(HEAD, v1.1.1) on the store routes / max(HEAD, v1.1.1) everywhere (the starter must out-run v1.1.1, which lacks 1.2.0's security middleware) / a documented exception per light cell | **HEAD alone on the light routes** | **Answered 2026-10-26**: "light routes (static, seo) gate against HEAD 709bc94 only, store routes against max(HEAD, v1.1.1)" (ANSWERS round 5) |
| Q7 | _hyperscript pin | 0.9.94 (S15) / 0.9.93 until 0.9.94 has aged | **0.9.94**, SHA-pinned, bumped only through the behaviour suite | default (not yet raised) |
| Q8 | Terminal approach | line mode → PTY with the VT in the Pi agent, no xterm.js / server-side VT in a `--worker` subprocess / add an xterm.js lab | **Agent-side VT, no xterm.js**; `--worker vt` as the fallback | **Answered 2026-10-25: agent-side VT** (ANSWERS #9; D32) |
| Q9 | The Pi beyond the LAN | LAN-only now, a WireGuard overlay if ever / TLS (OpenSSL) in the agent | **LAN-only**; WireGuard if ever needed, on the spare OpenWrt router or a container on apollo (an idea, D44) | default (not yet raised) |
| Q10 | Houston's registration mode | invite-only / open / closed | **Invite-only** | default stands (not overridden) |
| Q11 | TOTP | required for admins and terminal writers, manual secret entry / optional for everyone / none | **Required for admins and terminal writers; no QR encoder** | default stands (not overridden) |
| Q12 | Terminal forensics | record output (asciicast, 30 days or 1 GiB in total, whichever comes first), never raw input / log commands only / record input too | **Output recordings, 30 days or 1 GiB in total (whichever comes first; the size cap protects apollo's disk, NEW, X10), no raw input** | default stands (not overridden) |
| Q13 | Keep `/term` and `/admin` LAN-only after going public? | yes / no | **Yes**, in-app and with NPM Access Lists | default stands (not overridden) |
| Q14 | Raise NPM's global `worker_connections` to 4096 (affects all your NPM hosts)? | yes, before the M3 soak / no | **Yes** | **Answered 2026-10-25: yes**, before the M3 soak (D41) |
| Q15 | Keep the Fly witness at odin-htmx.alexh95.com (please check the legacy allowance)? | keep (shared-cpu-1x 256 MB, about $2–3/month) / retire with a 301 / move it to apollo | **Keep** | **Answered 2026-10-25: keep**, with no allowance check; warn Alex if it costs more than $10/month (D41) |
| Q16 | Off-box backups | nightly pull to the dev PC now, a Hetzner Storage Box (€3.20/TB/month) once public / a Storage Box now / the dev PC only | **Dev PC now, Storage Box at stage 2** | default (not yet raised) |
| Q17 | License the spark modules the starter adopts under zlib (and add a LICENSE to spark)? | yes, after scrubbing LAN and host details / no | **Yes** | **Answered 2026-10-25: yes**, zlib, and spark gets a LICENSE; the LAN and host details are still scrubbed (ANSWERS round 1; D43) |
| Q18 | Publish public GHCR images? | public, distroless, never ffmpeg / private images / build on the host | **Public, distroless `base-nossl-debian13`, UID 10001, never ffmpeg** | default stands (not overridden) |
| Q19 | Chat retention defaults | rooms 500 / 7 d, DMs 1000 / 30 d, announcements 100 / 365 d, tombstones / one cap for all / no age cap | **Per room kind as listed**, adjustable up to 5000 / 90 d | default stands (not overridden) |
| Q20 | Bot conversation privacy | owner-only, admins see counts and timings / admin-visible / not stored | **Owner-only** | default stands (not overridden) |
| Q21 | Video pipeline | offline transcode on the dev PC + import, web-ready uploads in-app / a host ffmpeg bind-mounted for in-app transcode / a local-only transcoder image | **Offline transcode + web-ready uploads** | default stands (not overridden) |
| Q22 | A PWA service worker and i18n catalogs | keep out (never-add) / add the PWA late / add both | **Keep both out** | default stands (not overridden) |
| Q23 | The family beta | at M6 on the LAN after the focused security audit, 2–3 people you pick / wait until public | **At M6** | default stands (not overridden) |
| Q24 | apollo facts and LAN load tests | you provide `uname -m`, `nproc`, `free -h`, `df -h <APOLLO_DATA_DIR>`, the kernel, the NPM version, `ulimit -n` and the address NPM connects to the stack Caddy from (X31) at M0, and agents may run ≤ 10-minute LAN load tests (cpus capped, announced) / no load tests on apollo | **Yes to both** | **Answered 2026-10-25: yes to both** (S0.12, D42) |
| Q25 | Metrics | the in-app dashboard + admin-gated `/metrics`, no Prometheus/Grafana / add Prometheus and Grafana on apollo | **In-app only for now** | default stands (not overridden) |
| Q26 | Public video through bunny.net | at stage 2, public videos only / keep video LAN-only / serve public video from home | **Optional: bunny.net only if public videos get real traffic**; the home uplink (`<HOME_UPLINK>`) is not a binding stage-2 trigger, so the CDN is no longer needed by default (X41; D41) | default (not yet raised) |
| Q27 | Retire the old skeleton container on apollo `:8090` | once the starter stack runs there / keep it | **Retire it (your step)** | default stands (not overridden) |
| Q28 | Runtime disabling of compiled features from `/admin/modules` | no / yes | **No** (D3 never-add list) | default (not yet raised) |
| Q29 | When is the Fly witness (odin-htmx.alexh95.com) redeployed from the starter's `skeleton` profile? (D1, X2) | hold the redeploy until the M3 exit: Fly keeps serving the skeleton's build untouched (6d37506, v1.2.1, once D1 step 1 has deployed it) while `starter-skeleton` passes the parity gate and the 40-item checklist on apollo's LAN; then Alex sets `FLY_DEPLOY=true` and the v2.2.0 tag deploys / redeploy at the M1 exit with v2.0.0 | **Hold until the M3 exit** ("apollo before the web") | **Answered 2026-10-25: yes**; Fly keeps 6d37506 (v1.2.1) until the M3 exit (D1) |
| Q30 | How does the Pi agent reach the Pi, and where does it read its URL and device token? (D32, X15) | the `release` workflow attaches the linux_arm64 `term-agent` binary and its SHA-256 as a release asset, Alex copies it over, and the unit reads `/etc/houston/term-agent.env` (`TERM_AGENT_URL`, `TERM_AGENT_HOST`, `TERM_AGENT_TOKEN_FILE` → `/etc/houston/term-agent.token`, mode 0600) as an `EnvironmentFile` / build it on the Pi with Odin's linux_arm64 release / an agent copies it from the dev PC over SSH when Alex asks | **A release asset plus an `EnvironmentFile`**; the agent reports its version in `hello` and `/admin/term` flags outdated agents | default (not yet raised) |
| Q31 | The default role grants that are judgement calls (D35, X16) | as tabled: `Term_Watch` to Moderator and Admin, `Video_Upload` to Moderator and Admin, `Admin_Audit` to Admin only / another split | **As tabled**; `rbac.spec` freezes them at M4 | default stands (not overridden) |
| Q32 | The bot: a catalog feature, or Houston only? (D31, X32) | a catalog feature, in `streams` (the package ships with no model, no llama.cpp and nothing AI) / Houston only: drop `bot` from `streams` and mark it showcase-only in the catalog (a one-line change) | **A catalog feature** | **Answered 2026-10-25: yes**, a catalog feature, in `streams` (D31) |
| Q33 | The device-driven features: an optional milestone? (D44, X42) | an optional **M14 Devices** after M12, like M13: the device registry and feed (`/admin/devices`, generalising `/admin/term`'s device tokens, plus a plain-text `text/event-stream` for screens that can't render HTML), cameras (`cams`: each camera's MJPEG pulled once and fanned out to members as `multipart/x-mixed-replace`, LAN-only and members-only first) and the wall and TV dashboard (a kiosk view of Today, signed in by a device token), while live video, the radio feed, the mesh bridge and WireGuard stay in the ideas list / only some of the three / none: keep all of them in the ideas list and drop M14 / M14 plus some of those ideas | **M14 as stated**: optional, after M12, the three features above, the rest left as ideas | **Answered 2026-10-26: yes**, M14 Devices with the default scope: the device registry and feed, cams and the wall dashboard; live video, the radio feed, the mesh bridge and WireGuard stay ideas (ANSWERS round 4; D44) |

**Answered 2026-10-25 outside the numbered questions** (ANSWERS round 3; none maps to Q1–Q33): the lean-composition
choices, the main session's simpler set (per-package `ROUTES` mounted by a hand-written `routes.odin`; the four
family collections `store`, `identity`, `client` and `theme`, spelled only in `build.{sh,bat} <profile>`; one switch
in `chat_web` over all four transports and one for the bot backend; hand-written `main.odin` and `routes.odin` that
the generator writes and edits and CI checks; the bot default on `/admin/bot`; notify by direct import, audit through
`store:audit`, room mode over a static topic row, which X37 makes one row each way: D4–D8, D26, D31), and the
full-coverage reading: `full` carries every catalog feature, with Houston proper on `houston.alexh95.com` and every
starter demo and lab page on the session-free `houston-lab.alexh95.com`, each host with its own root and the demo data
capped and reset nightly (D2, D24, D25, D29).

**Decided in the device discussion** (2026-10-25, split DNS on 2026-10-26; DEVICES-SUMMARY, X41; none maps to
Q1–Q33): the bot's host, llama.cpp's Vulkan image on apollo's spare GPU (D31); the terminal device, a Pi 4 on 64-bit
Pi OS Lite, wired (D32); and split DNS, seven DNS-only `A` records pointing at `<APOLLO_LAN_IP>` (D41).
