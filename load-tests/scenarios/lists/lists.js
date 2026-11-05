import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js';
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @lists @accounts-accounts
//
// A member on a list of their own: reads it, adds, ticks, moves and gives an item to themselves, deletes it.
// A change runs on the query pool; the limit is 60 a minute per member, so a 429 here is the limit working.
export const options = build();
options.noCookiesReset = true; // the member's session stays
export const handleSummary = summarize('lists');

const OK = { responseCallback: http.expectedStatuses(200, 303, 429) };
let list = '';
let col = '';

export default function () {
  if (__ITER === 0) {
    signIn(`lists ${__VU}`);
    const made = http.post(`${BASE}/lists`, { title: `load ${__VU}`, template: 'plain' }, { headers: FORM, redirects: 0, tags: { name: 'POST /lists' }, ...OK });
    check(made, { made: (r) => r.status === 303 });
    list = made.headers.Location || '';
  }
  const all = http.get(`${BASE}/lists`, { tags: { name: 'GET /lists' } });
  check(all, { index: (r) => r.status === 200 });
  const page = http.get(`${BASE}${list}`, { tags: { name: 'GET /lists/(id)' } });
  check(page, { page: (r) => r.status === 200 && r.body.includes('list-columns') });
  col = (page.body.match(/data-col="(\d+)"/) || [])[1] || col;
  const ids = page.body.match(/data-item="(\d+)"/);
  http.post(`${BASE}${list}/items`, { text: `item ${__ITER}` }, { headers: FORM, redirects: 0, tags: { name: 'POST /lists/(id)/items' }, ...OK });
  http.get(`${BASE}${list}/columns/${col}`, { tags: { name: 'GET /lists/(id)/columns/(col)' } });
  if (ids) {
    const item = ids[1];
    http.post(`${BASE}${list}/move`, { item, col, after: '0' }, { headers: FORM, redirects: 0, tags: { name: 'POST /lists/(id)/move' }, ...OK });
    http.post(`${BASE}${list}/items/${item}/toggle`, {}, { headers: FORM, redirects: 0, tags: { name: 'POST /lists/(id)/items/(item)/toggle' }, ...OK });
    http.post(`${BASE}${list}/items/${item}/assign`, { who: '0' }, { headers: FORM, redirects: 0, tags: { name: 'POST /lists/(id)/items/(item)/assign' }, ...OK });
    http.post(`${BASE}${list}/items/${item}/delete`, {}, { headers: FORM, redirects: 0, tags: { name: 'POST /lists/(id)/items/(item)/delete' }, ...OK });
  }
}
