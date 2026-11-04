import http from 'k6/http';
import { check, sleep } from 'k6';
import encoding from 'k6/encoding';
import { MAIN as BASE } from '../../lib/config.js'; // uploads are the main host's
import { FORM, signIn } from '../../lib/member.js';
import { options as build, summarize } from '../../lib/options.js';

// tags: @uploads @chat
//
// An image's whole way (PLAN §14.2): each VU, a member of its own, opens an upload, sends it in two
// chunks, asks how far it got, finishes it, and reads the blob, then posts it to the lobby. The
// same tiny PNG each time, so the blob is there already after the first: what's measured is the
// path, the row writes, the pools and a decode, not the disk. A pool's refusal is a 503, tried again
// as the shim does: an upload left open would count against its member for an hour.
export const options = build();
options.noCookiesReset = true;
export const handleSummary = summarize('uploads');

const PNG = encoding.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC');
const CUT = 30;
const BUSY = http.expectedStatuses(200, 201, 503);
const BIN = { 'Content-Type': 'application/octet-stream' };
const name = (n) => ({ tags: { name: n }, responseCallback: BUSY });
let signed = false;

function retried(send) {
  for (let i = 0; i < 200; i++) {
    const r = send();
    if (r.status !== 503) return r;
    sleep(0.01);
  }
  return send();
}

export default function () {
  if (!signed) signed = signIn(`uploads ${__VU}`).status < 400;
  if (!signed) return;
  const made = http.post(`${BASE}/uploads?size=${PNG.byteLength}`, null, { headers: FORM, tags: { name: 'POST /uploads' } });
  if (!check(made, { 'made 201': (r) => r.status === 201 })) return;
  const id = made.json('id');
  const one = retried(() => http.put(`${BASE}/uploads/${id}?off=0`, PNG.slice(0, CUT), { headers: BIN, ...name('PUT /uploads/:id') }));
  const at = http.get(`${BASE}/uploads/${id}`, { tags: { name: 'GET /uploads/:id' } });
  check(at, { 'got to the cut': (r) => one.status === 200 && r.status === 200 && r.json('received') === CUT });
  const two = retried(() => http.put(`${BASE}/uploads/${id}?off=${CUT}`, PNG.slice(CUT), { headers: BIN, ...name('PUT /uploads/:id') }));
  const done = retried(() => http.post(`${BASE}/uploads/${id}/finish`, null, { headers: FORM, ...name('POST /uploads/:id/finish') }));
  if (!check(done, { 'finished': (r) => two.status === 200 && r.status === 200 })) return;
  const sha = done.json('sha256');
  const blob = retried(() => http.get(`${BASE}/uploads/blob/${sha}`, { responseType: 'none', ...name('GET /uploads/blob/:sha') }));
  check(blob, { 'blob 200': (r) => r.status === 200 });
  http.post(`${BASE}/chat/r/lobby`, { attachment: sha }, { headers: FORM, tags: { name: 'POST /chat/r/:slug' }, responseCallback: http.expectedStatuses(200, 429) });
}
