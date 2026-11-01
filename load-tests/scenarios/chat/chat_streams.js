import http from 'k6/http';
import { check } from 'k6';
import { setTimeout } from 'k6/timers';
import { WebSocket } from 'k6/websockets';
import { BASE, P95, P99 } from '../../lib/config.js';
import { cookieHeader, signIn } from '../../lib/nick.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @chat @accounts-nick
//
// A room's live transports, per iteration: the socket (the page's version first, as its
// page sends it, 0 so it gets the snapshot; then one message sent and back through the
// hub, or the slow-down toast past the post rate), a poll
// and its 304 for a version it already has, and two streams held a moment and cut
// by the client: multipart's (its snapshot part) and the page's #live on the room's
// topics, whose open and close are presence's join and leave. Stock k6 can't read a
// stream that never ends, so the held ones are left out of the gates (fan-out is
// tools/streamload's, PLAN §19.1.7).
export const options = build({ 'ws_sessions{phase:load}': ['count>0'] });
options.noCookiesReset = true; // the nickname picked on a VU's first iteration stays (k6 empties the jar each one)
delete options.thresholds['http_req_failed{phase:load}'];
delete options.thresholds['http_req_duration{phase:load}'];
options.thresholds['http_req_failed{phase:load,held:no}'] = ['rate<0.01'];
options.thresholds['http_req_duration{phase:load,held:no}'] = [`p(95)<${P95}`, `p(99)<${P99}`];
options.scenarios.warmup.gracefulStop = '6s'; // let a cut-off iteration's awaits finish (see lab/streams.js)
export const handleSummary = summarize('chat_streams');

const WS = BASE.replace(/^http/, 'ws');

function socket() {
  return new Promise((resolve) => {
    const ws = new WebSocket(`${WS}/chat/r/lobby/ws`, null, { headers: { Cookie: cookieHeader() }, tags: { name: 'GET /chat/r/:slug/ws' } });
    let frames = 0;
    ws.onopen = () => {
      ws.send(JSON.stringify({ ver: '0' }));
      ws.send(JSON.stringify({ body: `ws ${__VU}-${__ITER}` }));
    };
    // The snapshot (once the lobby has messages), then ours or the toast: two is enough.
    ws.onmessage = () => { if (++frames >= 2) ws.close(); };
    ws.onclose = () => resolve(frames);
    ws.onerror = () => resolve(frames);
    setTimeout(() => ws.close(), 2000);
  });
}

export default async function () {
  if (__ITER === 0) signIn(`load ${__VU}`);
  const frames = await socket();
  check(frames, { 'socket: something back': (n) => n >= 1 });

  const first = http.get(`${BASE}/chat/r/lobby/since`, { tags: { name: 'GET /chat/r/:slug/since', held: 'no' } });
  check(first, { 'poll 200 and a tag': (r) => r.status === 200 && r.headers['Hx-Ptag'] !== undefined });
  const tag = first.headers['Hx-Ptag'] || '0';
  const next = http.get(`${BASE}/chat/r/lobby/since`, { headers: { 'HX-PTag': tag }, tags: { name: 'GET /chat/r/:slug/since', held: 'no' }, responseCallback: http.expectedStatuses(200, 304) });
  check(next, { 'poll again: 304, or what changed': (r) => r.status === 304 || r.status === 200 });

  const held = { timeout: '300ms', tags: { held: 'yes' } };
  const parts = http.asyncRequest('GET', `${BASE}/chat/r/lobby/parts`, null, { ...held, tags: { name: 'GET /chat/r/:slug/parts', held: 'yes' } });
  const live = http.asyncRequest('GET', `${BASE}/events?t=chat.presence:1,chat.typing:1,chat.room:1`, null, { ...held, tags: { name: 'GET /events', held: 'yes' } });
  await Promise.all([parts, live]);
}
