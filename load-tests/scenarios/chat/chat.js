import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../../lib/config.js';
import { FORM, signIn } from '../../lib/nick.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @chat @accounts-nick
//
// A member's requests in a room, the transport rotating per iteration: the rooms,
// the room page, the Connection setting, a post (5 in 10 s per member, so most
// iterations get the 429 and its toast, which is measured too), and with a post that
// went in, its menu, its edit form, the edit, the delete and the read receipt; then
// a CSP report, and typing (at most one in 2 s goes out, the rest are dropped). Each VU
// makes a room of its own once, while there is room for one (a memory build keeps 100).
export const options = build();
options.noCookiesReset = true; // the nickname picked on a VU's first iteration stays (k6 empties the jar each one)
export const handleSummary = summarize('chat');

const TRANSPORTS = ['ws', 'sse', 'poll', 'multipart'];
// What a browser posts when the room's policy refuses something (streams sends
// Reporting-Endpoints, as lab does: lab.js posts lab's).
const REPORT = JSON.stringify([{ type: 'csp-violation', url: `${BASE}/chat/r/lobby`, body: { blockedURL: 'inline', effectiveDirective: 'script-src-elem' } }]);
const ok = (...codes) => http.expectedStatuses(...codes);

export default function () {
  if (__ITER === 0) {
    signIn(`load ${__VU}`);
    http.post(`${BASE}/chat/rooms`, { name: `load ${__VU}` }, { headers: FORM, tags: { name: 'POST /chat/rooms' }, responseCallback: ok(204, 422) });
  }
  const t = TRANSPORTS[__ITER % TRANSPORTS.length];
  const rooms = http.get(`${BASE}/chat`, { tags: { name: 'GET /chat' } });
  check(rooms, { 'rooms 200': (r) => r.status === 200 && r.body.includes('chat-rooms') });
  const page = http.get(`${BASE}/chat/r/lobby?transport=${t}`, { tags: { name: 'GET /chat/r/:slug' } });
  check(page, { 'room 200': (r) => r.status === 200 && (r.headers['X-Impl'] || '').includes(`chat.transport=${t}`) });
  const set = http.post(`${BASE}/chat/transport`, { transport: t }, { headers: FORM, redirects: 0, tags: { name: 'POST /chat/transport' }, responseCallback: ok(303) });
  check(set, { 'setting 303': (r) => r.status === 303 });

  const post = http.post(`${BASE}/chat/r/lobby`, { body: `load ${__VU}-${__ITER}` }, { headers: FORM, tags: { name: 'POST /chat/r/:slug' }, responseCallback: ok(200, 429) });
  check(post, { 'post 200, or 429 past the rate': (r) => r.status === 200 ? r.body.includes('hx-partial') : (r.status === 429 && r.headers['Retry-After'] !== undefined) });
  const id = post.status === 200 ? (post.body.match(/id="m-(\d+)"/) || [])[1] : undefined;
  if (id) {
    const menu = http.get(`${BASE}/chat/m/${id}/menu`, { tags: { name: 'GET /chat/m/:id/menu' } });
    check(menu, { 'menu: Edit': (r) => r.status === 200 && r.body.includes('Edit') });
    const form = http.get(`${BASE}/chat/m/${id}/edit`, { tags: { name: 'GET /chat/m/:id/edit' } });
    check(form, { 'edit form 200': (r) => r.status === 200 && r.body.includes('chat-edit') });
    const edit = http.post(`${BASE}/chat/m/${id}/edit`, { body: `edited ${__ITER}` }, { headers: FORM, tags: { name: 'POST /chat/m/:id/edit' } });
    check(edit, { 'edited': (r) => r.status === 200 && r.body.includes('(edited)') });
    const del = http.post(`${BASE}/chat/m/${id}/delete`, null, { headers: FORM, tags: { name: 'POST /chat/m/:id/delete' } });
    check(del, { 'deleted': (r) => r.status === 200 && r.body.includes('Message deleted.') });
    const read = http.post(`${BASE}/chat/r/lobby/read?upto=${id}`, null, { headers: FORM, tags: { name: 'POST /chat/r/:slug/read' } });
    check(read, { 'read 204': (r) => r.status === 204 });
  }
  const report = http.post(`${BASE}/csp-report`, REPORT, { headers: { 'Content-Type': 'application/reports+json' }, tags: { name: 'POST /csp-report' } });
  check(report, { 'report 204': (r) => r.status === 204 });
  const typing = http.post(`${BASE}/chat/r/lobby/typing`, { body: 'x' }, { headers: FORM, tags: { name: 'POST /chat/r/:slug/typing' } });
  check(typing, { 'typing 204': (r) => r.status === 204 });
}
