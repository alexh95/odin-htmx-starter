import http from 'k6/http';
import { check } from 'k6';
import { MAIN } from '../../lib/config.js';
import { signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @audit @audit-memory
//
// The audit log's reads on a memory build (streams, for chat's moderation): its store keeps no
// rows (each entry is a log line, PLAN §11.4), so the page, the next page and the export answer
// empty. A loopback nickname is an admin there (run.sh's ACCOUNTS_NICK_ADMIN_CIDRS).
export const options = build({ 'checks{phase:load}': ['rate>0.99'] });
options.noCookiesReset = true;
export const handleSummary = summarize('audit_memory');

export default function () {
  if (__ITER === 0) signIn(`audit ${__VU}`);
  const page = http.get(`${MAIN}/admin/audit`, { tags: { name: 'GET /admin/audit' } });
  check(page, { 'audit page 200, no table': (r) => r.status === 200 && r.body.includes('keeps no audit table') });
  const rows = http.get(`${MAIN}/admin/audit/rows?before=0`, { tags: { name: 'GET /admin/audit/rows' } });
  check(rows, { 'rows 200': (r) => r.status === 200 });
  const csv = http.get(`${MAIN}/admin/audit/export`, { tags: { name: 'GET /admin/audit/export' } });
  check(csv, { 'csv 200, an attachment': (r) => r.status === 200 && (r.headers['Content-Disposition'] || '').startsWith('attachment') });
}
