package ops_views

// ---- ops: the views (PLAN §15.4) -------------------------------------------------------------
//
// The panel is a few cards, each with its numbers and a sparkline of the minute, drawn on the
// server as SVG. The same cards serve the page and every refresh: a refresh carries them out of
// band (`hx-swap-oob="innerMorph"`), so a card is morphed in place, not replaced.

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import ops ".."

w :: html.w
esc :: html.esc

Mode :: enum u8 {
	Sse,
	Poll,
	Multipart,
}

MODES := [Mode]struct {
	name, label: string,
} {
	.Sse       = {"sse", "Streaming"},
	.Poll      = {"poll", "Polling"},
	.Multipart = {"multipart", "Multipart"},
}

page :: proc(samples: []ops.Sample, modules: []ops.Module, limits: []ops.Limit, crash: string, mode: Mode, wiring: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Operate", "Ops", "What the process is doing, every second.")
	fmt.sbprintf(&b, `<section class="block ops"%s><p class="muted ops-via">Refreshed every second by %s. `, wiring, MODES[mode].label)
	for row, k in MODES {
		if k == mode { continue }
		fmt.sbprintf(&b, `<a href="/admin/ops?mode=%s">%s</a> `, row.name, row.label)
	}
	w(&b, `</p>`)
	if crash != "" {
		w(&b, `<article class="card ops-crash"><h2>The last run ended in a crash</h2><pre>`)
		esc(&b, crash)
		w(&b, `</pre></article>`)
	}
	cards(&b, samples, modules, false)
	w(&b, `<details class="ops-limits"><summary>Limits</summary><table><thead><tr><th>Module</th><th>Limit</th><th>Value</th></tr></thead><tbody>`)
	for l in limits {
		w(&b, `<tr><td>`)
		esc(&b, l.module)
		w(&b, `</td><td>`)
		esc(&b, l.name)
		fmt.sbprintf(&b, `</td><td>%d`, l.value)
		if l.unit != "" {
			w(&b, ` `)
			esc(&b, l.unit)
		}
		w(&b, `</td></tr>`)
	}
	w(&b, `</tbody></table></details></section>`)
	return strings.to_string(b)
}

// The cards, in place (`oob` false: the page) or out of band (a refresh).
cards :: proc(b: ^strings.Builder, samples: []ops.Sample, modules: []ops.Module, oob: bool) {
	now: ops.Sample
	if len(samples) > 0 { now = samples[len(samples) - 1] }
	series :: proc(samples: []ops.Sample, pick: proc(s: ops.Sample) -> f64) -> []f64 {
		out := make([]f64, len(samples), context.temp_allocator)
		for s, i in samples { out[i] = pick(s) }
		return out
	}
	if !oob { w(b, `<div class="ops-grid">`) }

	open(b, "ops-http", "Requests", oob)
	fmt.sbprintf(b, `<p class="ops-big">%d<small> a second</small></p>`, now.per_s)
	sparkline(b, series(samples, proc(s: ops.Sample) -> f64 { return f64(s.per_s) }))
	fmt.sbprintf(b, `<p class="muted">%d since boot</p></article>`, now.requests)

	open(b, "ops-streams", "Streams", oob)
	fmt.sbprintf(b, `<p class="ops-big">%d<small> open</small></p>`, now.streams)
	sparkline(b, series(samples, proc(s: ops.Sample) -> f64 { return f64(s.streams) }))
	fmt.sbprintf(b, `<p class="muted">%s queued</p></article>`, bytes(now.queued))

	open(b, "ops-hub", "Hub", oob)
	fmt.sbprintf(b, `<p class="ops-big">%d<small> a second</small></p>`, now.published_per_s)
	sparkline(b, series(samples, proc(s: ops.Sample) -> f64 { return f64(s.published_per_s) }))
	fmt.sbprintf(b, `<p class="muted">%d published, %d dropped, %d resyncs</p></article>`, now.published, now.dropped, now.resyncs)

	open(b, "ops-process", "Process", oob)
	if now.rss > 0 {
		fmt.sbprintf(b, `<p class="ops-big">%s<small> resident</small></p>`, bytes(now.rss))
	} else {
		w(b, `<p class="ops-big">—<small> resident</small></p>`)
	}
	sparkline(b, series(samples, proc(s: ops.Sample) -> f64 { return f64(s.rss) }))
	fmt.sbprintf(b, `<p class="muted">%d loops, the slowest ticked %d ms ago</p></article>`, now.loops, now.oldest_tick_ms)

	if now.has_store {
		open(b, "ops-store", "Store", oob)
		fmt.sbprintf(b, `<p class="ops-big">%s<small> page cache</small></p>`, bytes(int(now.store.cache)))
		sparkline(b, series(samples, proc(s: ops.Sample) -> f64 { return f64(s.store.cache) }))
		fmt.sbprintf(b, `<p class="muted">%s schema, %s statements</p>`, bytes(int(now.store.schema)), bytes(int(now.store.stmt)))
		fmt.sbprintf(b, `<p class="muted%s" id="ops-drops">%d audit entries dropped</p></article>`, " ops-warn" if now.drops > 0 else "", now.drops)
	}

	open(b, "ops-modules", "Modules", oob)
	w(b, `<table class="ops-table"><tbody>`)
	for m in modules {
		fmt.sbprintf(b, `<tr class="ops-%s"><td>`, m.state)
		esc(b, m.name)
		fmt.sbprintf(b, `</td><td>%s</td><td class="muted">`, m.state)
		esc(b, m.message)
		w(b, `</td></tr>`)
	}
	if len(modules) == 0 { w(b, `<tr><td class="muted">None report yet.</td></tr>`) }
	w(b, `</tbody></table></article>`)

	if !oob { w(b, `</div>`) }
}

@(private)
open :: proc(b: ^strings.Builder, id, title: string, oob: bool) {
	fmt.sbprintf(b, `<article id="%s" class="card ops-card"%s><h2>%s</h2>`, id, ` hx-swap-oob="innerMorph"` if oob else "", title)
}

// A minute as a line: the values scaled to the box, the newest at the right.
sparkline :: proc(b: ^strings.Builder, values: []f64) {
	W :: 120
	H :: 28
	w(b, `<svg class="spark" viewBox="0 0 120 28" preserveAspectRatio="none" aria-hidden="true">`)
	if len(values) > 1 {
		lo, hi := values[0], values[0]
		for v in values {
			lo = min(lo, v)
			hi = max(hi, v)
		}
		span := hi - lo if hi > lo else 1
		w(b, `<polyline points="`)
		for v, i in values {
			x := f64(W) * f64(i) / f64(len(values) - 1)
			y := f64(H - 2) - (v - lo) / span * f64(H - 4)
			fmt.sbprintf(b, "%.1f,%.1f ", x, y)
		}
		w(b, `"/>`)
	}
	w(b, `</svg>`)
}

@(private)
bytes :: proc(n: int) -> string {
	switch {
	case n >= 1 << 20: return fmt.tprintf("%.1f MiB", f64(n) / f64(1 << 20))
	case n >= 1 << 10: return fmt.tprintf("%.1f KiB", f64(n) / f64(1 << 10))
	}
	return fmt.tprintf("%d B", n)
}
