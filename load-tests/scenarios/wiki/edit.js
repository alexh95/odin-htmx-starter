import http from 'k6/http';
import { check } from 'k6';
import { MAIN as BASE } from '../../lib/config.js';
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @wiki-sqlite @accounts-accounts
//
// Writing the wiki: each VU has a page of its own and saves over it, which renders on the query pool
// and takes the writer's lock, then reads its history, a revision's diff, the preview and the export. The
// save limit is 30 a minute per member, so a 429 here is the limit working.
export const options = build();
options.noCookiesReset = true; // the member's session stays
export const handleSummary = summarize('wiki-edit');

const TEXT = 'one line\n\n'.repeat(40);
const LIMITED = { responseCallback: http.expectedStatuses(200, 303, 409, 429) };

let rev = 0;
let slug = '';

export default function () {
  if (__ITER === 0) {
    signIn(`wiki ${__VU}`);
    slug = `load-page-${__VU}-${Date.now()}`;
    const made = http.post(`${BASE}/wiki`, { title: slug, md: TEXT, visibility: 'members' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /wiki' }, ...LIMITED });
    check(made, { 'made': (r) => r.status === 303 || r.status === 429 });
    rev = 1;
  }
  const f = http.post(`${BASE}/wiki/preview`, { md: TEXT }, { headers: FORM, tags: { name: 'POST /wiki/preview' }, ...LIMITED });
  check(f, { 'preview': (r) => r.status === 200 || r.status === 429 });
  const saved = http.post(`${BASE}/wiki/${slug}`, { title: slug, md: `${TEXT}${__ITER}\n`, visibility: 'members', rev: `${rev}` },
    { headers: FORM, redirects: 0, tags: { name: 'POST /wiki/(page)' }, ...LIMITED });
  if (saved.status === 303) rev += 1;
  check(saved, { 'saved': (r) => r.status === 303 || r.status === 429 });
  const history = http.get(`${BASE}/wiki/${slug}/history`, { tags: { name: 'GET /wiki/(page)/history' } });
  check(history, { 'history': (r) => r.status === 200 });
  if (rev > 1) {
    const one = http.get(`${BASE}/wiki/${slug}/history/${rev - 1}`, { tags: { name: 'GET /wiki/(page)/history/(rev)' } });
    check(one, { 'a diff': (r) => r.status === 200 });
  }
  check(http.get(`${BASE}/wiki/${slug}/edit`, { tags: { name: 'GET /wiki/(page)/edit' } }), { 'editor': (r) => r.status === 200 });
  check(http.get(`${BASE}/wiki/new`, { tags: { name: 'GET /wiki/new' } }), { 'new': (r) => r.status === 200 });
  check(http.get(`${BASE}/wiki/${slug}.md`, { tags: { name: 'GET /wiki/(page).md' } }), { 'export': (r) => r.status === 200 });
}
