import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js';
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @polls @accounts-accounts
//
// A member on a poll of their own: reads it and its bars, changes a named vote, and casts a final one on an
// anonymous poll. Votes are limited to 10 a minute per member and asking to 10, so a 429 here is the limit working,
// and a 409 is the vote that was already final.
export const options = build();
options.noCookiesReset = true; // the member's session stays
export const handleSummary = summarize('polls');

const OK = { responseCallback: http.expectedStatuses(200, 303, 409, 429) };
let poll = '';

function ask(question, extra) {
  return http.post(`${BASE}/polls`, { question, kind: 'go', closes: '1h', ...extra }, { headers: FORM, redirects: 0, tags: { name: 'POST /polls' }, ...OK });
}

export default function () {
  if (__ITER === 0) {
    signIn(`polls ${__VU}`);
    const made = ask(`load ${__VU}`, {});
    check(made, { made: (r) => r.status === 303 });
    poll = made.headers.Location || '';
  }
  const all = http.get(`${BASE}/polls`, { tags: { name: 'GET /polls' } });
  check(all, { index: (r) => r.status === 200 });
  const page = http.get(`${BASE}${poll}`, { tags: { name: 'GET /polls/(id)' } });
  check(page, { page: (r) => r.status === 200 && r.body.includes('poll-bars') });
  http.get(`${BASE}${poll}/results`, { tags: { name: 'GET /polls/(id)/results' } });
  const option = (page.body.match(/data-option="(\d+)"/) || [])[1];
  if (option) http.post(`${BASE}${poll}/vote`, { option }, { headers: FORM, redirects: 0, tags: { name: 'POST /polls/(id)/vote' }, ...OK });
  if (__ITER % 50 === 49) {
    http.post(`${BASE}${poll}/close`, {}, { headers: FORM, redirects: 0, tags: { name: 'POST /polls/(id)/close' }, ...OK });
    const made = ask(`load ${__VU} again`, {});
    if (made.status === 303) poll = made.headers.Location;
  }
}
