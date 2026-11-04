import http from 'k6/http';
import { check, sleep } from 'k6';
import { MAIN as BASE } from '../../lib/config.js'; // chat is the main host's
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @chat
//
// Moderation (PLAN §14.1): each VU is a moderator with a public room of its own, and a guest in a
// cookie jar of its own. Each iteration the guest posts and reports the moderator's message; the
// moderator removes the guest's, mutes and kicks the guest and lifts both, locks and unlocks the
// room, sets slow mode off, opens the reports page and closes one report each way. Each act is a
// write with its audit entry (write_now; a removal through the writer). The moderator: on a nick
// build any loopback nickname (run.sh's ACCOUNTS_NICK_ADMIN_CIDRS), on an accounts build the
// suites' test admin. The guest's mute and kick are lifted first each iteration: the warmup stops
// without grace, and a guest left kicked was out of the room for the rest of the run.
export const options = build();
options.noCookiesReset = true;
export const handleSummary = summarize('moderation');

const ACCOUNTS = __ENV.IDENTITY === 'accounts';
const ok = (...codes) => http.expectedStatuses(...codes);
const RETRY = http.expectedStatuses({ min: 200, max: 399 }, 422, 503);
const WHY = { ...FORM, 'HX-Prompt': 'k6' };
const guest = new http.CookieJar();
let ready = false;
let who; // the guest's id, from a room page's data-me

// Signs in until the answer isn't the argon pool's 503 (expected here); true once in.
function enter(fn) {
  for (let i = 0; i < 100; i++) {
    const r = fn();
    if (r.status !== 503) return r.status < 400;
    sleep(0.1);
  }
  return false;
}

const admin = () => http.post(`${BASE}/login`, { username: 'admin', password: 'e2e-and-load-only-password', next: '/' },
  { headers: FORM, redirects: 0, tags: { name: 'POST /login' }, responseCallback: RETRY });

export default function () {
  const slug = `mod-${__VU}`;
  if (!ready) {
    const made = enter(ACCOUNTS ? admin : () => signIn(`mod ${__VU}`, { responseCallback: RETRY })) &&
      http.post(`${BASE}/chat/rooms`, { name: `mod ${__VU}` }, { headers: FORM, redirects: 0, tags: { name: 'POST /chat/rooms' }, responseCallback: ok(204, 422) });
    ready = !!made && (made.status === 204 || made.status === 422) && enter(() => signIn(`mod ${__VU} guest`, { jar: guest, responseCallback: RETRY }));
    if (!ready) return;
  }
  const as = { headers: FORM, jar: guest };
  const ban = (kind, minutes) => http.post(`${BASE}/chat/r/${slug}/${kind}/${who}`, { minutes }, { headers: WHY, tags: { name: `POST /chat/r/:slug/${kind}/:id` } });
  if (who) {
    ban('kick', '0');
    ban('mute', '0');
  } else {
    const page = http.get(`${BASE}/chat/r/${slug}?transport=poll`, { jar: guest, tags: { name: 'GET /chat/r/:slug' } });
    who = (page.body.match(/data-me="(\d+)"/) || [])[1];
  }

  // The moderator's message, which the guest reports; the guest's, which the moderator removes.
  const mine = http.post(`${BASE}/chat/r/${slug}`, { body: `mod ${__ITER}` }, { headers: FORM, tags: { name: 'POST /chat/r/:slug' }, responseCallback: ok(200, 429) });
  const theirs = http.post(`${BASE}/chat/r/${slug}`, { body: `guest ${__ITER}` }, { ...as, tags: { name: 'POST /chat/r/:slug' }, responseCallback: ok(200, 429) });
  const id = (r) => (r.status === 200 ? (r.body.match(/id="m-(\d+)"/) || [])[1] : undefined);
  const reported = id(mine);
  if (reported) {
    // Retention may have let it go already (the room keeps 500): a 404.
    const rep = http.post(`${BASE}/chat/m/${reported}/report`, null, { headers: WHY, jar: guest, tags: { name: 'POST /chat/m/:id/report' }, responseCallback: ok(200, 404) });
    check(rep, { 'reported': (r) => r.status === 404 || (r.status === 200 && r.body.includes('Reported')) });
  }
  const removed = id(theirs);
  if (removed) {
    const rm = http.post(`${BASE}/chat/m/${removed}/remove`, null, { headers: WHY, tags: { name: 'POST /chat/m/:id/remove' } });
    check(rm, { 'removed': (r) => r.status === 200 && r.body.includes('Message deleted.') });
  }
  if (who) {
    for (const kind of ['mute', 'kick']) {
      for (const minutes of ['60', '0']) {
        check(ban(kind, minutes), { [`${kind} ${minutes}`]: (r) => r.status === 200 });
      }
    }
  }
  for (const locked of ['1', '0']) {
    const l = http.post(`${BASE}/chat/r/${slug}/lock`, { locked }, { headers: WHY, tags: { name: 'POST /chat/r/:slug/lock' } });
    check(l, { 'lock 204': (r) => r.status === 204 && r.headers['Hx-Refresh'] === 'true' });
  }
  const slow = http.post(`${BASE}/chat/r/${slug}/slow`, { seconds: '0' }, { headers: WHY, tags: { name: 'POST /chat/r/:slug/slow' } });
  check(slow, { 'slow 204': (r) => r.status === 204 });

  // The reports page, and its oldest two closed: one removed, one dismissed.
  const list = http.get(`${BASE}/chat/reports`, { tags: { name: 'GET /chat/reports' } });
  check(list, { 'reports 200': (r) => r.status === 200 && r.body.includes('chat-report-list') });
  const open = [...list.body.matchAll(/id="report-(\d+)"/g)].map((m) => m[1]);
  ['remove', 'dismiss'].forEach((act, i) => {
    if (!open[i]) return;
    // Another VU may close it first: then it is no longer open, a 404.
    const r = http.post(`${BASE}/chat/reports/${open[i]}/${act}`, null, { headers: WHY, tags: { name: `POST /chat/reports/:id/${act}` }, responseCallback: ok(204, 404) });
    check(r, { [`report ${act}`]: (x) => x.status === 204 || x.status === 404 });
  });
}
