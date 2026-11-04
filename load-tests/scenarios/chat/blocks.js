import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js'; // chat is the main host's
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @chat
//
// Blocking: each VU, a member with a DM to the peer setup() signed in, blocks them from the DM,
// reads the list, finds a DM refused, and unblocks. Row writes through write_now, and the reads a
// DM's page makes for it.
export const options = build();
options.noCookiesReset = true;
export const handleSummary = summarize('blocks');

let slug = '';

export function setup() {
  signIn('blocks peer');
  const page = http.get(`${BASE}/chat/r/lobby?transport=poll`, { tags: { name: 'GET /chat/r/:slug' } });
  return { peer: (page.body.match(/data-me="(\d+)"/) || [])[1] };
}

export default function (data) {
  if (!slug) {
    if (signIn(`blocks ${__VU}`).status >= 400) return;
    const dm = http.post(`${BASE}/chat/dm/${data.peer}`, null, { headers: FORM, tags: { name: 'POST /chat/dm/:id' }, responseCallback: http.expectedStatuses(204, 403) });
    if (dm.status === 403) http.post(`${BASE}/chat/unblock/${data.peer}`, null, { headers: FORM, tags: { name: 'POST /chat/unblock/:id' } });
    slug = (dm.headers['Hx-Redirect'] || '').split('/').pop();
    if (!slug) return;
  }
  const block = http.post(`${BASE}/chat/r/${slug}/block`, null, { headers: FORM, tags: { name: 'POST /chat/r/:slug/block' } });
  check(block, { 'blocked 204': (r) => r.status === 204 });
  const list = http.get(`${BASE}/chat/blocks`, { tags: { name: 'GET /chat/blocks' } });
  check(list, { 'listed': (r) => r.status === 200 && r.body.includes('Unblock') });
  const refused = http.post(`${BASE}/chat/dm/${data.peer}`, null, { headers: FORM, tags: { name: 'POST /chat/dm/:id' }, responseCallback: http.expectedStatuses(403) });
  check(refused, { 'refused 403': (r) => r.status === 403 });
  const open = http.post(`${BASE}/chat/unblock/${data.peer}`, null, { headers: FORM, tags: { name: 'POST /chat/unblock/:id' } });
  check(open, { 'unblocked 204': (r) => r.status === 204 });
}
