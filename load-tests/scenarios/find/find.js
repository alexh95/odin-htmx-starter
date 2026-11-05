import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js'; // find is the main host's
import { options as build, summarize } from '../../lib/options.js';

// tags: @find
//
// A guest's search, off the loop: a word the docs have, as a page and as the box's fragment. The limit is
// 10 a second per client, and k6's VUs are one client, so a 429 here is the limit working.
export const options = build();
export const handleSummary = summarize('find');

const LIMITED = { responseCallback: http.expectedStatuses(200, 429) };

export default function () {
  const page = http.get(`${BASE}/find?q=philosophy`, { tags: { name: 'GET /find' }, ...LIMITED });
  check(page, { 'page': (r) => r.status === 429 || r.body.includes('find-results') });
  const part = http.get(`${BASE}/find/results?q=philosophy`, { tags: { name: 'GET /find/results' }, ...LIMITED });
  check(part, { 'results': (r) => r.status === 200 || r.status === 429 });
}
