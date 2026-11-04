package jobs_views

// ---- jobs' views: the jobs, their runs, a run's row ------------------------------------------
//
// The runs table's rows have stable ids, `run-<boot>-<id>`, so a live update upserts its row
// (`jobs.runs`, newest first by when it was queued): a viewer who arrives mid-run gets the latest
// row of each run, never two.

import "core:fmt"
import "core:strings"
import "core:time"

import "../../../platform/html"
import jobs ".."
import m "../models"

w :: html.w
esc :: html.esc

page :: proc(b: ^strings.Builder, list: []jobs.Job_Row, runs: []m.Run_Row) {
	w(b, `<section class="block"><table class="table jobs-table"><thead><tr><th>Job</th><th>Every</th><th>Runs</th><th>Last took</th><th></th></tr></thead><tbody>`)
	for j in list {
		w(b, `<tr class="job"><td><code>`)
		esc(b, j.id)
		fmt.sbprintf(b, `</code></td><td>%s</td><td>%d`, every(j.every), j.state.runs)
		if j.state.crashes > 0 { fmt.sbprintf(b, `, %d crashed`, j.state.crashes) }
		w(b, `</td><td>`)
		if j.state.runs > 0 { fmt.sbprintf(b, `%d ms`, j.state.last_ms) } else { w(b, `—`) }
		// The job's id rides in the form; a reason comes from the prompt (HX-Prompt), audited.
		w(b, `</td><td><form hx-post="/admin/jobs/run" hx-prompt="Why run it now?" hx-swap="none"><input type="hidden" name="job" value="`)
		esc(b, j.id)
		w(b, `"><button class="btn btn-outline" type="submit">Run now</button></form></td></tr>`)
	}
	w(b, `</tbody></table></section>`)
	w(b, `<section class="block"><h2>Runs</h2><table class="table jobs-runs"><thead><tr><th>Job</th><th>State</th><th>Queued (UTC)</th><th>Took</th><th>Progress</th><th></th></tr></thead><tbody id="jobs-runs">`)
	for r in runs { row(b, r) }
	w(b, `</tbody></table><p class="muted">A run is kept for 30 days. Jobs due every minute or more often show only the runs asked for by hand.</p></section>`)
}

// One run's row; `data-at` orders the table, newest first.
row :: proc(b: ^strings.Builder, r: m.Run_Row) {
	fmt.sbprintf(b, `<tr id="run-%d-%d" class="run run-`, r.boot, r.id)
	esc(b, r.state)
	fmt.sbprintf(b, `" data-at="%d"><td><code>`, r.queued_at)
	esc(b, r.job)
	w(b, `</code>`)
	if r.by_hand { w(b, ` <span class="badge">by hand</span>`) }
	w(b, `</td><td class="run-state">`)
	esc(b, r.state)
	if r.note != "" {
		w(b, `<br><small class="muted">`)
		esc(b, r.note)
		w(b, `</small>`)
	}
	fmt.sbprintf(b, `</td><td>%s</td><td>`, stamp(r.queued_at))
	switch {
	case r.started_at != 0 && r.ended_at != 0: fmt.sbprintf(b, `%d ms`, r.ended_at - r.started_at)
	case r.started_at != 0:                    w(b, `running`)
	case:                                      w(b, `—`)
	}
	w(b, `</td><td class="run-progress">`)
	if r.total > 0 {
		fmt.sbprintf(b, `<progress max="%d" value="%d"></progress> %d of %d`, r.total, r.done, r.done, r.total)
	} else {
		w(b, `—`)
	}
	w(b, `</td><td class="run-actions">`)
	if (r.state == "queued" || r.state == "running") && r.boot == jobs.boot() {
		fmt.sbprintf(b, `<form hx-post="/admin/jobs/cancel" hx-prompt="Why stop it?" hx-swap="none"><input type="hidden" name="run" value="%d-%d"><button class="btn btn-outline" type="submit">Cancel</button></form>`, r.boot, r.id)
	}
	fmt.sbprintf(b, `<a href="/admin/jobs/runs/%d/%d/log" download>Log</a></td></tr>`, r.boot, r.id)
}

// A run's row as a live update: upserted into the table by its id, ordered by `data-at`.
update :: proc(b: ^strings.Builder, r: m.Run_Row) {
	w(b, `<hx-partial hx-target="#jobs-runs" hx-swap="upsert key:data-at sort:desc">`)
	row(b, r)
	w(b, `</hx-partial>`)
}

// The log as a download: what the run wrote, and how it ended.
log_text :: proc(r: m.Run_Row) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s, run %d-%d: %s\nqueued %s UTC", r.job, r.boot, r.id, r.state, stamp(r.queued_at))
	if r.started_at != 0 { fmt.sbprintf(&b, ", started %s", stamp(r.started_at)) }
	if r.ended_at != 0 { fmt.sbprintf(&b, ", ended %s", stamp(r.ended_at)) }
	if r.note != "" { fmt.sbprintf(&b, "\n%s", r.note) }
	strings.write_string(&b, "\n\n")
	strings.write_string(&b, r.log)
	return strings.to_string(b)
}

@(private)
every :: proc(d: time.Duration) -> string {
	switch {
	case d >= time.Hour && d % time.Hour == 0:     return fmt.tprintf("%d h", i64(d / time.Hour))
	case d >= time.Minute && d % time.Minute == 0: return fmt.tprintf("%d min", i64(d / time.Minute))
	}
	return fmt.tprintf("%d s", i64(d / time.Second))
}

@(private)
stamp :: proc(ms: i64) -> string {
	if ms == 0 { return "—" }
	t := time.unix(ms / 1000, 0)
	y, mo, d := time.date(t)
	h, mi, s := time.clock(t)
	return fmt.tprintf("%04d-%02d-%02d %02d:%02d:%02d", y, int(mo), d, h, mi, s)
}

// A failed run, for an admin's Inbox.
failed_line :: proc(r: m.Run_Row) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `The job <b>`)
	html.esc(&b, r.job)
	html.w(&b, `</b> failed.`)
	return strings.to_string(b)
}
