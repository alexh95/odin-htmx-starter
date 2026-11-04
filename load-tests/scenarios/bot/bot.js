import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js'; // the bot is the main host's
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @bot
//
// A member's questions to the mock, whole answers (run.sh sets BOT_DELAY_MS=0 and lifts
// the hourly limits): the pages, a conversation of the VU's own, an answer over each
// delivery in turn and a quick one kept by no one, then Stop on the last answer's
// generation, which has ended by then, so the route's own cost (Stop's timing is the
// e2e suite's: under 100 ms on either delivery). Every iteration is a generation or two,
// so a quick run makes thousands.
export const options = build();
options.noCookiesReset = true; // the member signed in on a VU's first iteration stays (k6 empties the jar each one)
export const handleSummary = summarize('bot');

let conv = '';
let lastGen = '0';

export default function () {
  if (__ITER === 0) {
    signIn(`load ${__VU}`);
    const c = http.post(`${BASE}/bot/c`, null, { headers: FORM, redirects: 0, tags: { name: 'POST /bot/c' } });
    check(c, { 'conversation: 303': (r) => r.status === 303 });
    conv = (c.headers['Location'] || '').split('/').pop();
  }
  const index = http.get(`${BASE}/bot`, { tags: { name: 'GET /bot' } });
  check(index, { 'bot page 200': (r) => r.status === 200 && (r.headers['X-Impl'] || '') === 'bot.backend=mock' });
  const page = http.get(`${BASE}/bot/c/${conv}`, { tags: { name: 'GET /bot/c/:id' } });
  check(page, { 'conversation 200': (r) => r.status === 200 });

  const delivery = __ITER % 2 === 0 ? 'sse' : 'multipart';
  const a = http.post(`${BASE}/bot/c/${conv}/ask`, { q: `question ${__ITER}`, delivery }, { headers: FORM, tags: { name: 'POST /bot/c/:id/ask' } });
  check(a, { 'answered, with stats': (r) => r.status === 200 && r.body.includes('bot-stats') });
  lastGen = (a.body.match(/\/bot\/gen\/(\d+)\/stop/) || [])[1] || lastGen;
  const q = http.post(`${BASE}/bot/ask`, { q: 'a quick one', delivery: 'sse' }, { headers: FORM, tags: { name: 'POST /bot/ask' } });
  check(q, { 'quick answer': (r) => r.status === 200 && r.body.includes('bot-stats') });

  const s = http.post(`${BASE}/bot/gen/${lastGen}/stop`, null, { headers: FORM, tags: { name: 'POST /bot/gen/:id/stop' } });
  check(s, { 'stop 204': (r) => r.status === 204 });
}
