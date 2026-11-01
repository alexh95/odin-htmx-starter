package status

import "core:testing"

@(test)
the_tag_follows_the_states_alone :: proc(t: ^testing.T) {
	a := []Probe{{"hub", "ok", "", false}, {"process", "ok", "up 3 s", false}}
	b := []Probe{{"hub", "ok", "", false}, {"process", "ok", "up 4 s", false}}
	c := []Probe{{"hub", "down", "", false}, {"process", "ok", "up 4 s", false}}
	testing.expect_value(t, tag(a), tag(b)) // the uptime moved: nothing to send
	testing.expect(t, tag(b) != tag(c))
}

@(test)
probes_parse_names_and_hosts_and_skip_the_rest :: proc(t: ^testing.T) {
	ps := parse_probes("minimal=starter-minimal:8080, streams = starter-streams:8080,Bad=x:1,nohost=,noport=host,<b>=h:1")
	defer {
		for p in ps { delete(p.name); delete(p.host) }
		delete(ps)
	}
	testing.expect_value(t, len(ps), 2)
	testing.expect_value(t, ps[0].name, "minimal")
	testing.expect_value(t, ps[1].host, "starter-streams:8080")
	testing.expect_value(t, ps[1].state, "checking")
}

// Only the nightly's age is health: a run by hand or a pre-deploy snapshot newer than a stale
// nightly still leaves the store degraded, and is said beside it.
@(test)
backups_judge_by_the_nightly_alone :: proc(t: ^testing.T) {
	H :: i64(3600 * 1000)
	now := i64(1_800_000_000_000)
	fresh := backups_probe(now - 2 * H, 0, now)
	testing.expect_value(t, fresh.state, "ok")
	testing.expect_value(t, fresh.message, "the newest nightly is 2 h 0 min old")
	stale := backups_probe(now - 30 * H, now - 60_000, now)
	testing.expect_value(t, stale.state, "degraded")
	testing.expect_value(t, stale.message, "the newest nightly is 1 d 6 h old; by hand or before a deploy, 1 min ago")
	none := backups_probe(0, now - 5_000, now)
	testing.expect_value(t, none.state, "degraded")
	testing.expect_value(t, none.message, "no nightly yet; by hand or before a deploy, 5 s ago")
	testing.expect_value(t, backups_probe(0, 0, now).message, "no nightly yet")
}
