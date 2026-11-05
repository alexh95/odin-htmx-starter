import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js'; // the wiki is the main host's
import { options as build, summarize } from '../../lib/options.js';

// tags: @wiki
//
// The wiki's read side: a page is rendered when written, so a view is the store's read and the layout. The
// export is here as well as in edit.js because the profiles with no accounts reach it only here.
export const options = build();
export const handleSummary = summarize('wiki');

export default function () {
  const index = http.get(`${BASE}/wiki`, { tags: { name: 'GET /wiki' } });
  check(index, { 'index 200': (r) => r.status === 200 && r.body.includes('wiki-pages') });
  const page = http.get(`${BASE}/wiki/philosophy`, { tags: { name: 'GET /wiki/(page)' } });
  check(page, { 'page 200': (r) => r.status === 200 && r.body.includes('wiki-body') });
  const source = http.get(`${BASE}/wiki/philosophy.md`, { tags: { name: 'GET /wiki/(page).md' } });
  check(source, { 'source 200': (r) => r.status === 200 && r.headers['Content-Type'].startsWith('text/markdown') });
}
