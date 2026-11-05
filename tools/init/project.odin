package main

// ---- a new project: the selection's profile in place of the template's ---------------------
//
// What init writes besides the four profile files (PLAN §7.4): build.{sh,bat} with one profile,
// `app`, on the selection's families; ols.json pinned to them; the scripts that default to a
// profile pointed at `app`; CI trimmed to `app`; UPSTREAM.md saying where the project came
// from; a fresh CHANGELOG and TODO. It deletes every other app/cmd/*, and each feature not
// selected with its stores, its e2e specs and its load scenarios. Every edit is a literal one
// that must match, as the rename's are: a template that changed under init stops it.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// The Dockerfile's copy of the catalog, which only `landing` reads.
DOCKER_CATALOG :: "# The lab's landing page embeds the generator's catalog.\nCOPY docs/catalog.json /src/docs/catalog.json\n"
DOCKER_MANUAL :: "# The wiki embeds these (features/wiki/wiki.odin).\nCOPY README.md PHILOSOPHY.md CLAUDE.md /src/\nCOPY docs/README.md docs/BRIEF.md docs/USE_CASES.md docs/DATA.md /src/docs/\nCOPY docs/perf/PARITY.md /src/docs/perf/\nCOPY e2e/README.md /src/e2e/\nCOPY load-tests/README.md /src/load-tests/\n"
IGNORE_MANUAL :: "!README.md\n!PHILOSOPHY.md\n!CLAUDE.md\n!docs/README.md\n!docs/BRIEF.md\n!docs/USE_CASES.md\n!docs/DATA.md\n!docs/perf/PARITY.md\n!e2e/README.md\n!load-tests/README.md\n"

new_project :: proc(s: Selection, opt: Options) -> Profile_Text {
	text := compose(s)
	dir := join("app/cmd", s.name)
	put(join(dir, "main.odin"), text.main)
	put(join(dir, "routes.odin"), text.routes)
	put(join(dir, "brand.odin"), text.brand)
	put(join(dir, "routes_test.odin"), text.routes_test)

	names := make([dynamic]string)
	for p in catalog.profiles {
		append(&names, p.name)
		remove_tree(join("app/cmd", p.name))
	}
	for f in catalog.features {
		if slice.contains(s.features, f.name) { continue }
		remove_tree(join("app/features", f.name))
		for fam in f.stores { remove_tree(fmt.aprintf("app/stores/%s/%s", fam, f.name)) }
		remove_tree_if_present(join("e2e/tests", f.name))
		remove_tree_if_present(join("load-tests/scenarios", f.name))
	}

	build_lines(s, names[:])
	set_ols(s)
	default_profile(s)
	trim_ci(s, names[:])
	// The TSan gate, the soak and the Autobahn run build the template's lab and skeleton, which a
	// project doesn't keep; the selections are generated from the template's catalog (the job
	// that needs `selections` goes first).
	for job in ([]string{"tsan", "soak", "autobahn", "selection", "selections"}) { drop_job(".github/workflows/nightly.yml", job) }
	for f in ([]string{
		"tools/drills/tsan.sh", "tools/drills/tsan.supp", "tools/drills/soak.sh", "tests/autobahn/fuzzingclient.json",
		".github/matrix/pairwise.json",
	}) { remove(f) }
	// The template's own: its catalog and the generator job that keeps it, and its hosting on apollo
	// (the stack Caddyfile, compose file and promote script, and the jobs that test them).
	for job in ([]string{"generator", "e2e-proxy", "stack", "proxy-config"}) { drop_job(".github/workflows/ci.yml", job) }
	for f in ([]string{
		"deploy/Caddyfile", "tests/proxy/npm.conf", "deploy/compose.yaml", "deploy/.env.example",
		"deploy/promote.ps1", "deploy/stack-test.sh", "deploy/proxy-config-test.sh",
	}) { remove(f) }
	// `landing` embeds the catalog (#load), so a project that keeps it keeps the file, frozen at the
	// template's; one without it drops the file and the Dockerfile's copy of it.
	if !slice.contains(s.features, "landing") {
		remove("docs/catalog.json")
		edit("Dockerfile", {
			{DOCKER_CATALOG, ""},
			{"tools/bundle and\n# docs/catalog.json are what the build needs.", "and tools/bundle are what the build needs."},
		})
		edit(".dockerignore", {
			{"THIRD_PARTY_NOTICES, docs/catalog.json (the lab's landing page embeds it) and the wiki's Manual: everything", "THIRD_PARTY_NOTICES and the wiki's Manual: everything"},
			{"!docs/catalog.json\n", ""},
		})
	}
	// Only the wiki reads these in the image.
	if !slice.contains(s.features, "wiki") {
		edit("Dockerfile", {{DOCKER_MANUAL, ""}})
		edit(".dockerignore", {{IGNORE_MANUAL, ""}})
	}
	put("UPSTREAM.md", upstream_md(s, opt))
	put("CHANGELOG.md", fmt.aprintf(
		"# Changelog\n\nThis project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and\n[Semantic Versioning](https://semver.org/).\n\n## [Unreleased]\n\n### Added\n- **The project**, from %s (UPSTREAM.md): %s, on store=%s identity=%s client=%s theme=%s.\n",
		template_version(), strings.join(s.features, ", "), s.members[.Store], s.members[.Identity], s.members[.Client], s.members[.Theme]))
	put("TODO.md", "# TODO\n\n- [ ] Write the site's own `home_title`, wordmark and copy (app/cmd/app/brand.odin).\n- [ ] Re-render `og.png` from tools/og/og.html; redraw favicon.svg and favicon.ico.\n- [ ] Point SITE_URL at the real domain; verify the site for Bing and IndexNow if wanted.\n")
	return text
}

// build.sh's and build.bat's table: one row, `app`, on the selection's families.
@(private = "file")
build_lines :: proc(s: Selection, profiles: []string) {
	id := member_dir(.Identity, s.members[.Identity])
	data, err := os.read_entire_file("build.sh", context.allocator)
	if err != nil {
		problem("build.sh: not found")
		return
	}
	repls := make([dynamic]Repl)
	row := fmt.aprintf("  %s) store=%s id=%s client=%s theme=%s ;;", s.name, s.members[.Store], id, s.members[.Client], s.members[.Theme])
	// Every row goes, a build of another profile's files (full-vanilla's `src=full`) with it; the
	// usage lines name them all.
	rows := make([dynamic]string)
	first := true
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		l := strings.trim_space(line)
		paren := strings.index_byte(l, ')')
		if paren <= 0 || !strings.contains(l, "store=") { continue }
		append(&rows, l[:paren])
		_, _, src := strings.partition(l, " src=")
		if src != "" { src = strings.fields(src)[0] }
		if !slice.contains(profiles, l[:paren]) && !slice.contains(profiles, src) { continue }
		append(&repls, Repl{strings.concatenate({line, "\n"}), strings.concatenate({row, "\n"}) if first else ""})
		first = false
	}
	append(&repls, Repl{fmt.aprintf("<%s>", strings.join(rows[:], "|")), fmt.aprintf("<%s>", s.name)})
	append(&repls, Repl{fmt.aprintf("(%s)", strings.join(rows[:], ", ")), fmt.aprintf("(%s)", s.name)})
	edit("build.sh", repls[:])

	// build.bat: the if/else-if chain from the first profile's test to `) else (`.
	bat, berr := os.read_entire_file("build.bat", context.allocator)
	if berr != nil {
		problem("build.bat: not found")
		return
	}
	b := string(bat)
	start := strings.index(b, fmt.aprintf("if \"%%P%%\"==\"%s\" (", profiles[0]))
	end := strings.index(b, ") else (")
	if start < 0 || end < start {
		problem("build.bat: no `if \"%%P%%\"==\"%s\" (` … `) else (` chain to replace", profiles[0])
		return
	}
	chain := fmt.aprintf("if \"%%P%%\"==\"%s\" (\r\n  set \"STORE=%s\" & set \"ID=%s\" & set \"CLIENT=%s\" & set \"THEME=%s\"\r\n",
		s.name, s.members[.Store], id, s.members[.Client], s.members[.Theme])
	if !strings.contains(b, "\r\n") { chain, _ = strings.replace_all(chain, "\r\n", "\n") }
	edit("build.bat", {
		{b[start:end], chain},
		{fmt.aprintf("^<%s^>", strings.join(rows[:], "^|")), fmt.aprintf("^<%s^>", s.name)},
		{fmt.aprintf("^(%s^)", strings.join(rows[:], ", ")), fmt.aprintf("^(%s^)", s.name)},
	})
}

member_dir :: proc(fam: Family, name: string) -> string {
	m, _ := member(fam, name)
	return m.dir
}

// ols.json's four collections, at the selection's members.
@(private = "file")
set_ols :: proc(s: Selection) {
	data, err := os.read_entire_file("ols.json", context.allocator)
	if err != nil {
		problem("ols.json: not found")
		return
	}
	repls := make([dynamic]Repl)
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		for fam in Family {
			key := fmt.aprintf("\"name\": \"%s\"", FAMILY_FLAGS[fam])
			if !strings.contains(line, key) { continue }
			at := strings.index(line, "\"path\": \"")
			if at < 0 { continue }
			rest := line[at + len("\"path\": \""):]
			close := strings.index_byte(rest, '"')
			if close < 0 { continue }
			want := fmt.aprintf("app/%s", member_dir(fam, s.members[fam]))
			if rest[:close] != want { append(&repls, Repl{line, strings.concatenate({line[:at + len("\"path\": \"")], want, rest[close:]})}) }
		}
	}
	if len(repls) > 0 { edit("ols.json", repls[:]) }
}

// The scripts that build or serve a profile when none is named: `app` now.
@(private = "file")
default_profile :: proc(s: Selection) {
	edit("app/run.sh", {{`PROFILE="${PROFILE:-skeleton}"`, fmt.aprintf(`PROFILE="${{PROFILE:-%s}}"`, s.name)}})
	edit("app/run.bat", {{`set "PROFILE=skeleton"`, fmt.aprintf(`set "PROFILE=%s"`, s.name)}})
	edit("load-tests/run.sh", {{`PROFILE="${PROFILE:-skeleton}"`, fmt.aprintf(`PROFILE="${{PROFILE:-%s}}"`, s.name)}})
	edit("Dockerfile", {{"ARG PROFILE=skeleton", fmt.aprintf("ARG PROFILE=%s", s.name)}, {"(PROFILE, skeleton by", fmt.aprintf("(PROFILE, %s by", s.name)}})
	edit("e2e/global-setup.ts", {{"process.env.E2E_PROFILE || 'skeleton'", fmt.aprintf("process.env.E2E_PROFILE || '%s'", s.name)}})
	edit("e2e/playwright.config.ts", {
		{"process.env.E2E_PROFILE || 'skeleton'", fmt.aprintf("process.env.E2E_PROFILE || '%s'", s.name)},
		{"['skeleton', 'lab', 'full'].includes(PROFILE)", fmt.aprintf("['%s'].includes(PROFILE)", s.name)},
	})
	edit("app/prepare.sh", {{"./build.sh skeleton", fmt.aprintf("./build.sh %s", s.name)}})
	edit("app/prepare.bat", {{"build.bat skeleton", fmt.aprintf("build.bat %s", s.name)}})
}

// CI for one profile: the per-profile loops and matrices name `app`, and its include rows are
// the template's for the profile whose write route the selection keeps.
@(private = "file")
trim_ci :: proc(s: Selection, profiles: []string) {
	path :: ".github/workflows/ci.yml"
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		problem("%s: not found", path)
		return
	}
	text := string(data)
	lines := strings.split_lines(text)
	listed := strings.join(profiles, ", ")
	spaced := strings.join(profiles, " ")
	repls := make([dynamic]Repl)
	append(&repls, Repl{fmt.aprintf("profile: [%s]", listed), fmt.aprintf("profile: [%s]", s.name)})
	append(&repls, Repl{fmt.aprintf("for p in %s;", spaced), fmt.aprintf("for p in %s;", s.name)})

	// The include rows: single-line `- { profile: x, … }` and the `- profile: x` blocks.
	write := ""
	build_rows := make([dynamic]string)
	e2e_rows := make([dynamic]string)
	for i := 0; i < len(lines); i += 1 {
		l := lines[i]
		t := strings.trim_space(l)
		name := ""
		switch {
		case strings.has_prefix(t, "- { profile: "):
			name = strings.trim_space(strings.split(t[len("- { profile: "):], ",")[0])
		case strings.has_prefix(t, "- profile: "):
			name = strings.trim_space(t[len("- profile: "):])
		}
		if !slice.contains(profiles, name) { continue }
		block := l
		indent := len(l) - len(strings.trim_left_space(l))
		for i + 1 < len(lines) && len(lines[i + 1]) - len(strings.trim_left_space(lines[i + 1])) > indent && !strings.has_prefix(strings.trim_space(lines[i + 1]), "-") {
			i += 1
			block = strings.concatenate({block, "\n", lines[i]})
		}
		if w := field_of(block, "write: "); w != "" && write == "" && write_kept(s, w) { write = w }
		if strings.contains(block, "browser:") {
			append(&e2e_rows, block)
		} else {
			append(&build_rows, block)
		}
	}
	// Each group's rows go; one row for app takes the first's place.
	indent_of :: proc(l: string) -> string { return l[:len(l) - len(strings.trim_left_space(l))] }
	if len(build_rows) > 0 {
		pad := indent_of(build_rows[0])
		row := fmt.aprintf("%s- { profile: %s, write: %s }", pad, s.name, write) if write != "" else fmt.aprintf("%s- { profile: %s, write: '' }", pad, s.name)
		if s.members[.Store] == "memory" {
			row = strings.concatenate({row, "\n", fmt.aprintf("%s- { profile: %s, os: ubuntu-latest, sqlite: none, write: %s }", pad, s.name, write if write != "" else "''"),
				"\n", fmt.aprintf("%s- { profile: %s, os: windows-latest, sqlite: none, write: %s }", pad, s.name, write if write != "" else "''")})
		}
		for r, i in build_rows { append(&repls, Repl{strings.concatenate({r, "\n"}), strings.concatenate({row, "\n"}) if i == 0 else ""}) }
	}
	if len(e2e_rows) > 0 {
		pad := indent_of(e2e_rows[0])
		row := fmt.aprintf("%s- {{ profile: %s, browser: chromium, also: --project=api }}\n%s- {{ profile: %s, browser: firefox }}\n%s- {{ profile: %s, browser: webkit }}", pad, s.name, pad, s.name, pad, s.name)
		for r, i in e2e_rows { append(&repls, Repl{strings.concatenate({r, "\n"}), strings.concatenate({row, "\n"}) if i == 0 else ""}) }
	}

	// The coverage job's k6 runs: one, for app.
	runs := make([dynamic]string)
	for l in lines {
		if strings.contains(l, "load-tests/run.sh --quick --strict") && !strings.contains(l, "BUILD_FLAGS") { append(&runs, l) }
	}
	for r, i in runs {
		pad := r[:len(r) - len(strings.trim_left_space(r))]
		append(&repls, Repl{strings.concatenate({r, "\n"}), fmt.aprintf("%sPROFILE=%s sh load-tests/run.sh --quick --strict\n", pad, s.name) if i == 0 else ""})
	}
	if s.members[.Store] == "sqlite" {
		append(&repls, Repl{`[ "${{ matrix.profile }}" = skeleton ]`, fmt.aprintf(`[ "${{{{ matrix.profile }}}}" = %s ]`, s.name)})
		append(&repls, Repl{`if: matrix.profile == 'skeleton'`, fmt.aprintf(`if: matrix.profile == '%s'`, s.name)})
	}
	if !slice.contains(s.features, "about") {
		for l in lines {
			if strings.contains(l, `curl -fsS "http://127.0.0.1:8099/about"`) { append(&repls, Repl{strings.concatenate({l, "\n"}), ""}) }
		}
	}
	edit(path, repls[:])

	// The release publishes the project's one image.
	edit(".github/workflows/release.yml", {
		{fmt.aprintf("profile: [%s]", listed), fmt.aprintf("profile: [%s]", s.name)},
		{fmt.aprintf("for p in %s;", spaced), fmt.aprintf("for p in %s;", s.name)},
	})
}

// `write: /notes body=CI+smoke  # …` → "/notes body=CI+smoke".
@(private = "file")
field_of :: proc(block, key: string) -> string {
	at := strings.index(block, key)
	if at < 0 { return "" }
	rest := block[at + len(key):]
	if nl := strings.index_byte(rest, '\n'); nl >= 0 { rest = rest[:nl] }
	if hash := strings.index(rest, "  #"); hash >= 0 { rest = rest[:hash] }
	return strings.trim_space(strings.trim_suffix(strings.trim_space(rest), "}"))
}

// Whether a smoke write's POST lands on a selected feature's row.
@(private = "file")
write_kept :: proc(s: Selection, write: string) -> bool {
	path := strings.split(write, " ")[0]
	owner := route_owner(path, "Post")
	return owner != "" && slice.contains(s.features, owner)
}

// The project's provenance (10 §6): the template, its version, the command, the selection, and
// the vendored odin-http's base and changes.
@(private = "file")
upstream_md :: proc(s: Selection, opt: Options) -> string {
	b := strings.builder_make()
	fmt.sbprintf(&b, "# Upstream\n\nThis project was made with `tools/init` from **%s**, %s.\n\n", upstream_repo(), template_version())
	fmt.sbprintf(&b, "    odin run tools/init -- %s\n\n", strings.join(os.args[1:], " "))
	fmt.sbprintf(&b, "| | |\n|---|---|\n| features | %s |\n| root | %s |\n", strings.join(s.features, ", "), s.root)
	fmt.sbprintf(&b, "| families | store=%s, identity=%s, client=%s, theme=%s |\n", s.members[.Store], s.members[.Identity], s.members[.Client], s.members[.Theme])
	if fork, err := os.read_entire_file("app/vendor/odin-http/UPSTREAM.md", context.allocator); err == nil {
		base := ""
		changes := make([dynamic]string)
		t := string(fork)
		for line in strings.split_lines_iterator(&t) {
			if base == "" && strings.contains(line, "commit") && strings.contains(line, "laytan") { base = strings.trim_space(line) }
			if strings.has_prefix(line, "| F-") { append(&changes, strings.split(line, " |")[0][2:]) }
		}
		fmt.sbprintf(&b, "| odin-http | the vendored fork, %d changes (%s…%s); app/vendor/odin-http/UPSTREAM.md names its base and each |\n",
			len(changes), changes[0] if len(changes) > 0 else "", changes[len(changes) - 1] if len(changes) > 0 else "")
	}
	strings.write_string(&b, "\nUpdating from the template is a merge by hand: its CHANGELOG says what changed.\n")
	return strings.to_string(b)
}

// "v2.0.0 (75c6e3a)", from git; "an unknown version" without it.
template_version :: proc() -> string {
	tag := git("describe", "--tags", "--abbrev=0")
	commit := git("rev-parse", "--short", "HEAD")
	if tag == "" && commit == "" { return "an unknown version" }
	return fmt.aprintf("%s (%s)", tag if tag != "" else "untagged", commit)
}

git :: proc(args: ..string) -> string {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, "git")
	append(&cmd, ..args)
	state, stdout, _, err := os.process_exec({command = cmd[:]}, context.allocator)
	if err != nil || state.exit_code != 0 { return "" }
	return strings.trim_space(string(stdout))
}

// ---- the in-place commands (edit.odin has them) ------------------------------------------

print_changes :: proc() {
	for c in changes {
		switch {
		case c.removed && c.dir: fmt.printfln("  remove   %s/", c.path)
		case c.removed:          fmt.printfln("  remove   %s", c.path)
		case c.wrote:            fmt.printfln("  write    %s", c.path)
		case c.edits > 0:        fmt.printfln("  edit     %s (%d)", c.path, c.edits)
		}
	}
}
