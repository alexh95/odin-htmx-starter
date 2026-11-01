import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js'; // chat is the main host's
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @chat
//
// Rooms beyond public (PLAN §14.1): each VU owns a private room, made on its first iteration,
// and each iteration hands out an invite link, opens the link's page, leaves the room, joins it
// again by the link (the owner too needs it once out) and revokes the link, then opens its DM
// with the peer setup() signed in (found again, never made twice). Each is a row read or a
// write (write_now): an invite, a membership, a revoke, a DM lookup. A VU joins by its last link first:
// the warmup stops without grace, and k6 hands its VUs on to the measured window, so a VU cut
// off between leaving and joining again was out of its own room for good.
export const options = build();
options.noCookiesReset = true; // the member signed in on a VU's first iteration stays
export const handleSummary = summarize('rooms');

const ok = (...codes) => http.expectedStatuses(...codes);
let href; // this VU's last invite link

// A member for every VU's DM: their id from a room page's data-me, and known to chat from it.
export function setup() {
  signIn('rooms peer');
  const page = http.get(`${BASE}/chat/r/lobby?transport=poll`, { tags: { name: 'GET /chat/r/:slug' } });
  return { peer: (page.body.match(/data-me="(\d+)"/) || [])[1] };
}

export default function (data) {
  const slug = `rooms-${__VU}`;
  if (__ITER === 0) {
    signIn(`rooms ${__VU}`);
    http.post(`${BASE}/chat/rooms`, { name: `rooms ${__VU}`, kind: 'private' }, { headers: FORM, tags: { name: 'POST /chat/rooms' }, responseCallback: ok(204, 422) });
  }
  if (href) http.post(`${BASE}${href}`, null, { headers: FORM, redirects: 0, tags: { name: 'POST /chat/join/:token' }, responseCallback: ok(303) });
  const invite = http.post(`${BASE}/chat/r/${slug}/invite`, null, { headers: FORM, tags: { name: 'POST /chat/r/:slug/invite' } });
  check(invite, { 'invite link': (r) => r.status === 200 && r.body.includes('/chat/join/') });
  href = (invite.body.match(/href="(\/chat\/join\/[^"]+)"/) || [])[1] || href;
  if (href) {
    const page = http.get(`${BASE}${href}`, { tags: { name: 'GET /chat/join/:token' } });
    check(page, { 'join page 200': (r) => r.status === 200 && r.body.includes('chat-join') });
    const out = http.post(`${BASE}/chat/r/${slug}/leave`, null, { headers: FORM, tags: { name: 'POST /chat/r/:slug/leave' } });
    check(out, { 'left 204': (r) => r.status === 204 && r.headers['Hx-Redirect'] === '/chat' });
    const back = http.post(`${BASE}${href}`, null, { headers: FORM, redirects: 0, tags: { name: 'POST /chat/join/:token' }, responseCallback: ok(303) });
    check(back, { 'joined 303': (r) => r.status === 303 && r.headers['Location'] === `/chat/r/${slug}` });
    const id = (href.match(/\/chat\/join\/(\d+)\./) || [])[1];
    const revoke = http.post(`${BASE}/chat/r/${slug}/invites/${id}/revoke`, null, { headers: FORM, tags: { name: 'POST /chat/r/:slug/invites/:id/revoke' } });
    check(revoke, { 'revoked': (r) => r.status === 200 && !r.body.includes(`id="inv-${id}"`) });
    href = undefined; // revoked: the next iteration makes its own
  }
  if (data.peer) {
    const dm = http.post(`${BASE}/chat/dm/${data.peer}`, null, { headers: FORM, tags: { name: 'POST /chat/dm/:id' } });
    check(dm, { 'DM 204': (r) => r.status === 204 && /^\/chat\/r\/dm-[0-9a-f]{16}$/.test(r.headers['Hx-Redirect'] || '') });
  }
}
