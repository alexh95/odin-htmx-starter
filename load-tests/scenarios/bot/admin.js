import http from 'k6/http';
import { check } from 'k6';
import { MAIN } from '../../lib/config.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @bot @accounts-accounts
//
// Houston's admin on /admin/bot (M7): the test admin, signed in once per VU, reads the page, whose
// counts are a table scan of the bot's own rows, and sets the default to the one it already is,
// which is the route's cost with no audit row. fakellama isn't here, so the default stays the mock.
export const options = build();
options.noCookiesReset = true; // the admin's session stays
export const handleSummary = summarize('bot-admin');

const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

export default function () {
  if (__ITER === 0) {
    const r = http.post(`${MAIN}/login`, { username: 'admin', password: 'e2e-and-load-only-password' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /login' }, responseCallback: http.expectedStatuses(303, 503) });
    check(r, { 'admin signed in': (x) => x.status === 303 });
  }
  const page = http.get(`${MAIN}/admin/bot`, { tags: { name: 'GET /admin/bot' } });
  check(page, { 'admin page 200': (r) => r.status === 200 && r.body.includes('id="bot-admin"') });
  const set = http.post(`${MAIN}/admin/bot/default`, { backend: 'mock' }, { headers: FORM, tags: { name: 'POST /admin/bot/default' } });
  check(set, { 'default set': (r) => r.status === 200 && r.body.includes('id="bot-default"') });
}
