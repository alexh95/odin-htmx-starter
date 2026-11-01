import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { FORM, signIn } from '../../lib/nick.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @notify @accounts-nick
//
// A member's Inbox: the page, the log a resync refetches, and marking it all read.
// (Notifications arrive from producers, chat's mentions: chat.js and the e2e specs.)
export const options = build();
options.noCookiesReset = true; // the nickname picked on a VU's first iteration stays (k6 empties the jar each one)
export const handleSummary = summarize('notify');

export default function () {
  if (__ITER === 0) signIn(`load ${__VU}`);
  const page = http.get(`${BASE}/notify`, { tags: { name: 'GET /notify' } });
  check(page, { 'inbox 200': (r) => r.status === 200 && r.body.includes('notify-list') });
  const list = http.get(`${BASE}/notify/list`, { tags: { name: 'GET /notify/list' } });
  check(list, { 'list 200': (r) => r.status === 200 });
  const read = http.post(`${BASE}/notify/read`, null, { headers: FORM, tags: { name: 'POST /notify/read' } });
  check(read, { 'read: counts to 0': (r) => r.status === 200 && r.body.includes('notify-count') });
}
