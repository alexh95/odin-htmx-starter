package main

// ---- locks: only the guard's (PLAN §19.2.1, D15) -----------------------------------------
//
// A lock a handler can trap under is a guard.Mutex: the guard counts it, so the trap is dirty
// and the server drains, instead of recovering with the lock still held and hanging the next
// request on it. So nothing names core:sync's locks (its mutexes, benaphores, condition
// variables, a Once, which holds a mutex across its callback, and a futex, and their procs) but
// the platform packages below, each for its reason; the exemption is the whole package, so a
// new lock there is read in review, not here. A semaphore or an atomic is no lock and passes.

import "core:odin/ast"
import "core:strings"

RAW_LOCK_OWNERS := [?]struct {
	path, reason: string,
} {
	{"platform/guard", "it is the guard: Mutex wraps a sync.Mutex, and the recovery burst's lock is taken while a crash is classified"},
	{"platform/obs", "below the guard, which logs through it: each lock covers a copy into a fixed table, and the log must write while a crash is handled"},
	{"platform/hub", "an inbox's lock covers an append or a swap, taken by publishers on any thread inside the hub's guard.Mutex, and by its loop's drain"},
	{"platform/workers", "a pool's threads sleep on its condition variable, which a guard.Mutex can't take (the watchdog would read the sleep as a held lock)"},
	{"platform/store/sqlite", "the writer's queue sleeps on a condition variable as a pool does; the reader list is touched at a reader's first use and at close"},
}

check_locks :: proc(t: ^Tree) {
	outer: for q in t.pkgs {
		for o in RAW_LOCK_OWNERS { if q.path == o.path { continue outer } }
		walk_lock_pkg = q
		for _, f in q.ast.files {
			walk_sync_alias = ""
			for imp in f.imports {
				if strings.trim(imp.relpath.text, "\"`") == "core:sync" { walk_sync_alias = imp.name.text if imp.name.text != "" else "sync" }
			}
			if walk_sync_alias == "" { continue }
			for d in f.decls {
				ast.inspect(d, proc(n: ^ast.Node) -> bool {
					if n == nil { return true }
					s, ok := n.derived.(^ast.Selector_Expr)
					if !ok || ident(s.expr) != walk_sync_alias || !is_raw_lock(s.field.name) { return true }
					problem("locks", "%s: %s takes core:sync's %s; lock through guard.Mutex (or platform/store/memory's Lock)", where_(s.pos), walk_lock_pkg.path, s.field.name)
					return true
				})
			}
		}
	}
}

// ast.inspect's callback takes no data, so the walk's state is the file's.
@(private = "file") walk_lock_pkg: ^Pkg
@(private = "file") walk_sync_alias: string

@(private = "file")
is_raw_lock :: proc(name: string) -> bool {
	lower := strings.to_lower(name, context.temp_allocator)
	if strings.contains(lower, "mutex") || strings.contains(lower, "benaphore") || strings.has_suffix(lower, "cond") ||
	   strings.contains(lower, "futex") || lower == "once" || strings.has_prefix(lower, "once_") { return true }
	switch name {
	case "lock", "unlock", "try_lock", "shared_lock", "shared_unlock", "try_shared_lock", "guard", "shared_guard", "cond_wait", "cond_wait_with_timeout", "cond_signal", "cond_broadcast":
		return true
	}
	return false
}
