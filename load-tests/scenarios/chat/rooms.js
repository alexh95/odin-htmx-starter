import http from 'k6/http';
import { check, sleep } from 'k6';
import { MAIN as BASE } from '../../lib/config.js'; // chat is the main host's
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @chat
//
// Rooms beyond public (PLAN §14.1): each VU is a private room's owner and a guest, the guest in a
// cookie jar of its own. Each iteration the owner hands out an invite link, the guest opens the
// link's page, joins by it and leaves, the owner revokes the link, and the owner opens their DM
// with the peer setup() signed in (found again, never made twice). Each is a row read or a write
// (write_now): an invite, a membership, a revoke, a DM lookup. Both sign in until they are in: an
// accounts build's registration answers 503 while the argon pool's queue is full, as it is when
// every VU registers at once on a small box, and k6 gives the measured window new VUs.
export const options = build();
options.noCookiesReset = true; // the members signed in on a VU's first iteration stay
export const handleSummary = summarize('rooms');

const ok = (...codes) => http.expectedStatuses(...codes);
const guest = new http.CookieJar(); // this VU's guest
let ready = false; // the owner in, their room made, the guest in

// A member for every VU's DM: their id from a room page's data-me, and known to chat from it.
export function setup() {
  signIn('rooms peer');
  const page = http.get(`${BASE}/chat/r/lobby?transport=poll`, { tags: { name: 'GET /chat/r/:slug' } });
  return { peer: (page.body.match(/data-me="(\d+)"/) || [])[1] };
}

// Signs `name` in until the answer isn't the argon pool's 503 (expected here, so not a failure);
// true once in.
const RETRY = http.expectedStatuses({ min: 200, max: 399 }, 422, 503);
function enter(name, params = {}) {
  for (let i = 0; i < 100; i++) {
    const r = signIn(name, { ...params, responseCallback: RETRY });
    if (r.status !== 503) return r.status < 400;
    sleep(0.1);
  }
  return false;
}

export default function (data) {
  const slug = `rooms-${__VU}`;
  if (!ready) {
    // Made, or there already (422): either is a member's answer.
    const made = enter(`rooms ${__VU}`) && http.post(`${BASE}/chat/rooms`, { name: `rooms ${__VU}`, kind: 'private' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /chat/rooms' }, responseCallback: ok(204, 422) });
    ready = !!made && (made.status === 204 || made.status === 422) && enter(`rooms ${__VU} guest`, { jar: guest });
    if (!ready) return;
  }
  const as = { headers: FORM, jar: guest };
  const invite = http.post(`${BASE}/chat/r/${slug}/invite`, null, { headers: FORM, tags: { name: 'POST /chat/r/:slug/invite' } });
  check(invite, { 'invite link': (r) => r.status === 200 && r.body.includes('/chat/join/') });
  const href = (invite.body.match(/href="(\/chat\/join\/(\d+)\.[^"]+)"/) || []);
  if (href[1]) {
    const page = http.get(`${BASE}${href[1]}`, { jar: guest, tags: { name: 'GET /chat/join/:token' } });
    check(page, { 'join page 200': (r) => r.status === 200 && r.body.includes('chat-join') });
    const join = http.post(`${BASE}${href[1]}`, null, { ...as, redirects: 0, tags: { name: 'POST /chat/join/:token' }, responseCallback: ok(303) });
    check(join, { 'joined 303': (r) => r.status === 303 && r.headers['Location'] === `/chat/r/${slug}` });
    const out = http.post(`${BASE}/chat/r/${slug}/leave`, null, { ...as, tags: { name: 'POST /chat/r/:slug/leave' } });
    check(out, { 'left 204': (r) => r.status === 204 && r.headers['Hx-Redirect'] === '/chat' });
    const revoke = http.post(`${BASE}/chat/r/${slug}/invites/${href[2]}/revoke`, null, { headers: FORM, tags: { name: 'POST /chat/r/:slug/invites/:id/revoke' } });
    check(revoke, { 'revoked': (r) => r.status === 200 && !r.body.includes(`id="inv-${href[2]}"`) });
  }
  if (data.peer) {
    const dm = http.post(`${BASE}/chat/dm/${data.peer}`, null, { headers: FORM, tags: { name: 'POST /chat/dm/:id' } });
    check(dm, { 'DM 204': (r) => r.status === 204 && /^\/chat\/r\/dm-[0-9a-f]{16}$/.test(r.headers['Hx-Redirect'] || '') });
  }
}
