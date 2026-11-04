import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js'; // chat and the Inbox are the main host's
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @notify
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
  for (const on of ['1', '0']) {
    const mute = http.post(`${BASE}/notify/mute`, { key: 'chat.mention', on }, { headers: FORM, tags: { name: 'POST /notify/mute' } });
    check(mute, { 'mute 204': (r) => r.status === 204 });
  }
}
