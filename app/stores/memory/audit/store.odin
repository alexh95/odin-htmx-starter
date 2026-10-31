package audit_store_memory

// ---- audit in memory: one log line per entry ----------------------------------------------
//
// A memory build keeps no audit table (PLAN §11.4): each entry is one `mod=audit` logfmt line,
// so it lands wherever the process's log goes, and the log lists nothing.

import "../../../platform/obs"
import m "../../../features/audit/models"

IMPL :: "memory"

append :: proc(actor: m.Actor, action: string, target: m.Target, reason, meta: string) -> bool {
	if l, ok := obs.begin(.Info, "audit", action); ok {
		obs.num(&l, "actor_id", actor.id)
		obs.str(&l, "actor", actor.name)
		obs.str(&l, "target", target.kind)
		obs.num(&l, "target_id", target.id)
		if reason != "" { obs.str(&l, "reason", reason) }
		if meta != "" { obs.str(&l, "meta", meta) }
		obs.str(&l, "client", actor.client)
		obs.end(&l)
	}
	return true
}

// The memory family keeps no rows, so a change's entry is its log line, at once.
append_in :: proc(actor_id: i64, actor_name, client, action, target_kind: string, target_id: i64, reason, meta: string) -> m.Error {
	append({actor_id, actor_name, client}, action, {target_kind, target_id}, reason, meta)
	return .None
}

// The log line is written at once, so nothing is ever refused.
dropped :: proc() -> u64 { return 0 }

list :: proc(f: m.Filter, into: ^[dynamic]m.Entry) -> m.Error {
	return .None
}
