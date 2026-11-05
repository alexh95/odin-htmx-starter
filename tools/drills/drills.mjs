// The request-path drills and budgets (PLAN §19.1.9 tier 1, §19.1.10, §18.4), for one profile.
//
//   node tools/drills/drills.mjs <profile> [phase …] [--wsl DIR]
//
// Phases (default: all): release pure dirty burst hang logstall malformed slowread wsdata streamcrash
// shutdown streamdrain latewrite restart fdceiling streamfd opsviewers botmock backup dbview budgets.
// It builds the profile twice through build.{sh,bat}: a TEST_ROUTES build, which mounts
// /__test/crash/<kind> and /__test/shutdown (platform/web/drills.odin), and the release build at
// -o:speed, which must answer 404 there and is the one the budgets measure. Every server is fresh,
// on a port nothing else listens on.
//
// --wsl DIR runs the servers inside WSL instead, from a checkout at DIR (built there first), with
// BIND_ALL=1 so Windows' loopback reaches them: the Linux leg from a Windows host that has no node
// in WSL. Signals go through `wsl kill`; native Windows has no SIGTERM to send a child, so the
// shutdown drill uses /__test/shutdown there, which starts the same drain.
//
// Prints PASS/FAIL per check; exits 1 on any FAIL.

import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, statSync, unlinkSync, readdirSync, copyFileSync, mkdirSync, rmSync } from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const argv = process.argv.slice(2);
const wslAt = argv.indexOf('--wsl');
const WSL = wslAt >= 0 ? argv.splice(wslAt, 2)[1] : '';
const [PROFILE, ...PHASES] = argv;
if (!PROFILE) {
  console.error('usage: node tools/drills/drills.mjs <profile> [phase …] [--wsl DIR]');
  process.exit(2);
}
const WIN = process.platform === 'win32' && !WSL;
const LINUX = !WIN;
const EXE = WIN ? '.exe' : '';
const ALL = ['release', 'pure', 'dirty', 'burst', 'hang', 'logstall', 'malformed', 'slowread', 'wsdata', 'streamcrash', 'shutdown', 'streamdrain', 'latewrite', 'restart', 'fdceiling', 'streamfd', 'opsviewers', 'botmock', 'backup', 'dbview', 'budgets'];
const phases = PHASES.length ? PHASES : ALL;

// PLAN §18.4 (ANSWERS round 7): binaries in MiB, Windows -o:speed, as CI reads them; idle memory
// is 6 MB plus 0.4 MB per event loop (each has its log buffer, counters and io ring).
const MiB = 1024 * 1024;
const BUDGET = {
  size: { minimal: 1.5 * MiB, skeleton: 3 * MiB }, // ANSWERS rounds 7 and 10
  // The witnesses' 6 MB + 0.4 MB a loop; full's own 40 MB (§18.4: about 1.15 MB a SQLite reader × 16).
  idle: (loops) => (PROFILE === 'full' ? 40e6 : 6e6 + 0.4e6 * loops),
  readyMs: 50,
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const record = (name, pass, extra = '') => {
  results.push({ name, pass });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}${extra ? '  ' + extra : ''}`);
};

// ---- builds -------------------------------------------------------------------------

function build(out, ...flags) {
  let r;
  if (WSL) {
    r = spawnSync('wsl', ['--cd', WSL, '-e', 'env', `OUT=${out}`, 'sh', 'build.sh', PROFILE, ...flags], { stdio: 'inherit' });
  } else if (WIN) {
    r = spawnSync('cmd', ['/c', path.join(ROOT, 'build.bat'), PROFILE, ...flags], { cwd: ROOT, stdio: 'inherit', env: { ...process.env, OUT: out } });
  } else {
    r = spawnSync('sh', ['build.sh', PROFILE, ...flags], { cwd: ROOT, stdio: 'inherit', env: { ...process.env, OUT: out } });
  }
  if (r.status !== 0) throw new Error(`build ${out} failed`);
}

const DRILL_BIN = `app/bin/${PROFILE}-drills${EXE}`;
const RELEASE_BIN = `app/bin/${PROFILE}-release${EXE}`;

// ---- servers ------------------------------------------------------------------------

let nextPort = 9700 + (LINUX ? 100 : 0);

// netstat lists every socket (the state last); ss -ltn only listening ones.
function listening(port) {
  if (WIN) {
    const out = spawnSync('netstat', ['-an', '-p', 'tcp'], { encoding: 'utf8' }).stdout || '';
    return new RegExp(`[:.]${port}\\s.*LISTENING`).test(out);
  }
  const out = spawnSync(WSL ? 'wsl' : 'ss', WSL ? ['-e', 'ss', '-ltn'] : ['-ltn'], { encoding: 'utf8' }).stdout || '';
  return new RegExp(`[:.]${port}\\s`).test(out);
}

function freePort() {
  while (listening(nextPort)) nextPort++;
  return nextPort++;
}

// A server, fresh: its output, exit code and exit time are kept. An empty env value means unset.
function start(bin, env = {}, port = freePort(), { ulimit = 0 } = {}) {
  // full answers two hosts: its lab host (the stream drills' 127.0.0.1) is named, and any other
  // name (the malformed set's `Host: x`) is Houston's, as in the suites.
  const lab = PROFILE === 'full' ? { SITE_URL_LAB: 'https://127.0.0.1' } : {};
  const all = Object.fromEntries(Object.entries({
    PORT: String(port), THREADS: '4', LOG_LEVEL: 'info', CRASH_FILE: `app/build/last-crash-${port}.txt`, ...lab, ...env,
  }).filter(([, v]) => v !== ''));
  let child;
  if (WSL || LINUX) {
    // Single-quoted: a value is never the shell's to expand (an argon2id hash is all `$`).
    const vars = Object.entries({ ...all, ...(WSL ? { BIND_ALL: '1' } : {}) }).map(([k, v]) => `${k}='${String(v).replaceAll("'", "'\\''")}'`);
    // `echo $$` then exec: the first line is the server's own pid, for kill.
    const script = `${ulimit ? `ulimit -n ${ulimit}; ` : ''}echo pid $$; exec env ${vars.join(' ')} ${bin}`;
    child = WSL
      ? spawn('wsl', ['--cd', WSL, '-e', 'sh', '-c', script], { stdio: ['ignore', 'pipe', 'pipe'] })
      : spawn('sh', ['-c', script], { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
  } else {
    const base = { ...process.env };
    for (const k of Object.keys(env)) if (env[k] === '') delete base[k];
    child = spawn(path.join(ROOT, bin), [], { cwd: ROOT, env: { ...base, ...all }, stdio: ['ignore', 'pipe', 'pipe'] });
  }
  const s = { port, child, out: '', exited: null, exitAt: 0, pid: WIN ? child.pid : 0, startAt: performance.now() };
  const onOut = (d) => {
    s.out += d;
    if (!s.pid) { const m = /^pid (\d+)/m.exec(s.out); if (m) s.pid = Number(m[1]); }
  };
  child.stdout.on('data', onOut);
  child.stderr.on('data', onOut);
  child.on('exit', (code) => { s.exited = code; s.exitAt = performance.now(); });
  return s;
}

function signal(s, sig) {
  if (WSL) spawnSync('wsl', ['-e', 'kill', `-${sig}`, String(s.pid)]);
  else if (LINUX) process.kill(s.pid, `SIG${sig}`);
  else if (sig === 'KILL') spawnSync('taskkill', ['/F', '/PID', String(s.pid)]);
  else throw new Error(`no SIG${sig} on Windows`);
}

async function waitExit(s, ms) {
  for (let t = 0; t < ms && s.exited === null; t += 50) await sleep(50);
  return s.exited;
}

async function stop(s) {
  if (s.exited !== null) return;
  signal(s, 'KILL');
  await waitExit(s, 3000);
}

function get(port, p, { timeout = 3000, headers = {} } = {}) {
  return new Promise((res) => {
    const req = http.get({ host: '127.0.0.1', port, path: p, agent: false, timeout, headers }, (r) => {
      let body = '';
      r.setEncoding('utf8');
      r.on('data', (c) => (body += c));
      r.on('end', () => res({ status: r.statusCode, body }));
      r.on('error', () => res({ status: 0, body: '' }));
    });
    req.on('timeout', () => { req.destroy(); res({ status: -1, body: 'timeout' }); });
    req.on('error', (e) => res({ status: 0, body: String(e.code) }));
  });
}

async function ready(s, path_ = '/readyz') {
  for (let i = 0; i < 400; i++) {
    if ((await get(s.port, path_, { timeout: 500 })).status === 200) return true;
    if (s.exited !== null) break;
    await sleep(10);
  }
  console.log(s.out.slice(-2000));
  return false;
}

// The build's features: the sqlite drill exists only where the store is SQLite.
function features() {
  const r = WSL
    ? spawnSync('wsl', ['--cd', WSL, '-e', RELEASE_BIN, '--features', '--json'], { encoding: 'utf8' })
    : spawnSync(path.join(ROOT, RELEASE_BIN), ['--features', '--json'], { encoding: 'utf8' });
  return JSON.parse(r.stdout);
}

// ---- phases -------------------------------------------------------------------------

// `continuation`: in a deferred response's continuation after resume, a write's or a pool's shape (M1-04).
const PURE = ['panic', 'bounds', 'div', 'nil', 'stack', 'continuation'];

async function phaseRelease() {
  const s = start(RELEASE_BIN);
  if (!(await ready(s))) return record('release: server starts', false);
  const crash = await get(s.port, '/__test/crash/panic');
  const shut = await get(s.port, '/__test/shutdown');
  record('release: /__test/* answers 404 without TEST_ROUTES', crash.status === 404 && shut.status === 404 && s.exited === null,
    `crash=${crash.status} shutdown=${shut.status}`);
  await stop(s);
}

async function phasePure() {
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('pure: server starts', false);
  for (const kind of PURE) {
    // The crash and 20 bystanders on their own connections, at once.
    const [crash, ...by] = await Promise.all([
      get(s.port, `/__test/crash/${kind}`),
      ...Array.from({ length: 20 }, (_, i) => get(s.port, i % 2 ? '/about' : '/healthz')),
    ]);
    const ok = by.filter((r) => r.status === 200).length;
    const alive = (await get(s.port, '/livez')).status === 200;
    record(`pure ${kind}: 500, ${ok}/20 bystanders, still serving`, crash.status === 500 && ok === 20 && alive && s.exited === null,
      `crash=${crash.status}`);
  }
  const lines = s.out.split('\n').filter((l) => l.includes('ev=crash') && l.includes('route="GET /__test/crash/(%a+)"')).length;
  record('pure: one crash line per crash, naming the route', lines === PURE.length, `${lines} lines`);
  await stop(s);
}

async function phaseDirty(f) {
  const kinds = ['lock', 'async', ...(f.store === 'sqlite' ? ['sqlite'] : [])];
  for (const kind of kinds) {
    const s = start(DRILL_BIN);
    if (!(await ready(s))) { record(`dirty ${kind}: server starts`, false); continue; }
    const t0 = performance.now();
    const [crash] = await Promise.all([
      get(s.port, `/__test/crash/${kind}`, { timeout: 8000 }),
      ...Array.from({ length: 5 }, () => get(s.port, '/about', { timeout: 8000 })),
    ]);
    await waitExit(s, 8000);
    const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
    const why = /zone=dirty[^\n]*why="([^"]+)"/.exec(s.out)?.[1] ?? '';
    record(`dirty ${kind}: drains and exits 70 within 6 s`, s.exited === 70 && secs <= 6,
      `crash=${crash.status} exit=${s.exited} after ${secs.toFixed(2)} s ${why}`);
    await stop(s);
  }
  if (f.store !== 'sqlite') {
    const s = start(DRILL_BIN);
    if (await ready(s)) {
      const r = await get(s.port, '/__test/crash/sqlite');
      record(`dirty sqlite: no such drill in a ${f.store} build (404)`, r.status === 404, `status=${r.status}`);
    }
    await stop(s);
  }
}

// More than the burst limit of pure recoveries in a minute counts as dirty: each one leaks what
// its callback allocated.
async function phaseBurst() {
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('burst: server starts', false);
  let n = 0;
  for (; n < 150 && s.exited === null; n++) await get(s.port, '/__test/crash/bounds');
  await waitExit(s, 8000);
  record('burst: the recovery past the limit within a minute exits 70', s.exited === 70 && /why="too many recoveries"/.test(s.out),
    `exit=${s.exited} after ${n} crash requests`);
  await stop(s);
}

async function phaseHang() {
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('hang: server starts', false);
  const t0 = performance.now();
  get(s.port, '/__test/crash/hang?s=15', { timeout: 20000 });
  await waitExit(s, 14000);
  const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
  const named = /ev=watchdog[^\n]*id=\S+[^\n]*route="GET \/__test\/crash\/\(%a\+\)"/.test(s.out);
  // STALL (10 s) is seen by a check once a second, so 11 s at worst, and the exit after it: a second of slack
  // (eca62ba's run read 11.00 s on a loaded runner).
  record('hang: the watchdog exits 70 within 12 s and names the route and request', s.exited === 70 && secs <= 12 && named,
    `exit=${s.exited} after ${secs.toFixed(2)} s, named=${named}`);
  await stop(s);
}

// Tier 1 of the fuzz plan (PLAN §19.1.9): 10k malformed requests, raw, each on its own socket.
// F-16's payloads and the status each must get (the malformed phase checks them one by one too):
// one-byte chunks by the thousand, under both caps on a write (12k overflowed a Windows loop's stack
// before the scan trampoline, M1-17) and past what a GET's drain reads (60k: 300 KB of framing); a size line and a trailer line past 4 KiB (M1-18, M1-24); a body that
// ends inside a trailer (M1-19; the drill half-closes); a bare LF and trailing whitespace in framing
// (M1-20).
const CHUNKED = (target, body) => `${target} HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n${body}`;
const F16 = [
  // The profile's write, under its cap: minimal's and streams' notes take 4 KiB and full's sign-in
  // 2 KiB, so 500 chunks there (refused early, a bigger body's unread rest would reset the connection
  // before the 413 is read; a sign-in with no username is a 422); the depth is skeleton's, and lab's,
  // on the compat page's save (an empty name is a 422).
  PROFILE === 'minimal' || PROFILE === 'streams' || PROFILE === 'full'
    ? [CHUNKED(PROFILE === 'full' ? 'POST /login' : 'POST /notes','1\r\na\r\n'.repeat(500) + '0\r\n\r\n'), '422']
    : [CHUNKED(PROFILE === 'lab' ? 'POST /compat/htmx2/save' : 'POST /contacts', '1\r\na\r\n'.repeat(12000) + '0\r\n\r\n'), '422'],
  // Unread past the discard limit, the handler's answer stands and the connection goes (F-25).
  [CHUNKED('GET /healthz', '1\r\na\r\n'.repeat(60000) + '0\r\n\r\n'), '200'],
  [CHUNKED('POST /', '1;' + 'x'.repeat(5000) + '\r\na\r\n0\r\n\r\n'), '413'],
  [CHUNKED('POST /', '1\r\na\r\n0\r\nX-T: ' + 'y'.repeat(5000) + '\r\n\r\n'), '413'],
  // Cut off by the half-close; on Linux a half-closed client often gets no answer at all (M1-11), which
  // still isn't the success (405) of a body read as complete.
  [CHUNKED('POST /', '1\r\na\r\n0\r\nX-T: y'), WIN ? '400' : '400|none', true],
  [CHUNKED('POST /', '5\nhello\r\n0\r\n\r\n'), '400'],
  [CHUNKED('POST /', '5  \r\nhello\r\n0\r\n\r\n'), '400'],
];

const MALFORMED = [
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: -5\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 9223372036854775808\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 18446744073709551617\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: +5\r\n\r\nhello',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1_0\r\n\r\n0123456789',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 0x5\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\nhello',
  'OPTIONS * HTTP/1.1\r\nHost: x\r\nContent-Length: -5\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\nContent-Length: -5\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n-5\r\nhello\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nffffffffffffffffff\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n',
  // F-14: chunk data not followed by CRLF, a trailer field (on a write and on a GET, whose unread
  // body the response drains), and chunk sizes with a sign, a separator or past 64 bits.
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhelloXX\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\nX-Trailer: 1\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\nX-Trailer: 1\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n+5\r\nhello\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n1_0\r\n0123456789abcdef\r\n0\r\n\r\n',
  'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n8000000000000005\r\nhello\r\n0\r\n\r\n',
  ...F16.map(([payload]) => payload),
  'GET / HTTP/1.1\r\n\r\n',
  'GET / HTTP/2.0\r\nHost: x\r\n\r\n',
  'GET /' + 'a'.repeat(9000) + ' HTTP/1.1\r\nHost: x\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nX: ' + 'b'.repeat(9000) + '\r\n\r\n',
  'BREW / HTTP/1.1\r\nHost: x\r\n\r\n',
  'GET / HTTP/1.1\r\nHost: x\r\nbad header line\r\n\r\n',
  '\r\n\r\n\r\n',
  '\x00\x01\x02\xff\xfe GET / HTTP/1.1\r\n\r\n',
  'GET /static/../../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n',
  'GET /about?%zz=%ff%00 HTTP/1.1\r\nHost: x\r\n\r\n',
  'POST /about HTTP/1.1\r\nHost: x\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 9\r\n\r\n%%%&&==%%',
  'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhel', // half a body, then gone
];

// The first 12 bytes of the answer ("HTTP/1.1 400"). `halfClose` ends the write side after the
// payload, as a client that sends one request does; without it the socket closes once the status line is in.
function raw(port, payload, halfClose = true) {
  return new Promise((res) => {
    const sock = net.connect(port, '127.0.0.1');
    let got = '';
    sock.setTimeout(2000, () => sock.destroy());
    sock.on('connect', () => { sock.write(Buffer.from(payload, 'latin1')); if (halfClose) sock.end(); });
    sock.on('data', (d) => { got += d; if (!halfClose && got.length >= 12) sock.destroy(); });
    sock.on('close', () => res(got.slice(0, 12)));
    sock.on('error', () => res('ERR'));
  });
}

async function phaseMalformed() {
  // An accounts build's sign-in limits would answer full's write with 429 long before the F-16 checks.
  const s = start(RELEASE_BIN, PROFILE === 'full' ? { ACCOUNTS_LOGIN_PER_CLIENT: '100000000', ACCOUNTS_LOGIN_PER_NET: '100000000', ACCOUNTS_LOGIN_OVERALL: '100000000' } : {});
  if (!(await ready(s))) return record('malformed: server starts', false);
  const N = 10000, PAR = 50, codes = {};
  for (let i = 0; i < N && s.exited === null; i += PAR) {
    const batch = await Promise.all(Array.from({ length: PAR }, (_, j) => raw(s.port, MALFORMED[(i + j) % MALFORMED.length])));
    for (const b of batch) { const k = b.slice(9, 12) || 'none'; codes[k] = (codes[k] || 0) + 1; }
  }
  const alive = (await get(s.port, '/livez')).status === 200 && s.exited === null;
  record(`malformed: ${N} requests, /livez 200 after, 0 deaths`, alive, JSON.stringify(codes));
  const got = [];
  // Each with the socket left open until its status line arrives (but the cut-off one): a half-close
  // races the answer on Linux (M1-11).
  for (const [payload, want, half] of F16) got.push([(await raw(s.port, payload, !!half)).slice(9, 12) || 'none', want]);
  const ok = ([g, w]) => w.split('|').includes(g);
  record('malformed: each chunked-framing payload gets its status (F-16)', got.every(ok),
    got.map((x) => (ok(x) ? x[0] : `${x[0]}≠${x[1]}`)).join(' '));
  await stop(s);
}

// The shutdown bound (PLAN §8.7): a slowloris, a half-sent body, an idle peer that never answers
// the FIN and 50 idle keep-alive connections are open; a signal must still end it in 6 s, exit 0.
async function phaseShutdown() {
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('shutdown: server starts', false);
  const socks = [];
  const open = (fn) => { const c = net.connect(s.port, '127.0.0.1', () => fn(c)); c.on('error', () => {}); socks.push(c); return c; };
  const slow = open((c) => c.write('GET /healthz HTTP/1.1\r\nHost: x\r\n'));
  const slowTimer = setInterval(() => slow.write(`X-Slow-${Date.now()}: 1\r\n`), 1000);
  open((c) => c.write('POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\n\r\n' + 'x'.repeat(500)));
  const idle = open((c) => c.write('GET /healthz HTTP/1.1\r\nHost: x\r\n\r\n'));
  idle.on('data', () => idle.pause());
  for (let i = 0; i < 50; i++) open((c) => c.write('GET /livez HTTP/1.1\r\nHost: x\r\n\r\n'));
  await sleep(1000);
  const t0 = performance.now();
  if (WIN) get(s.port, '/__test/shutdown');
  else signal(s, 'TERM');
  await waitExit(s, 9000);
  const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
  clearInterval(slowTimer);
  for (const c of socks) c.destroy();
  record('shutdown: a signal with slow, half-sent and idle peers open exits 0 within 6 s', s.exited === 0 && secs <= 6,
    `exit=${s.exited} after ${secs.toFixed(2)} s${WIN ? ' (/__test/shutdown)' : ' (SIGTERM)'}`);
  await stop(s);
}

// M1-05: a write still on the writer when the loops leave. Its reply must not be posted into a loop
// that released its event loop (a SIGSEGV on Linux, a spin for good on Windows), and the store's
// close must not outlast the shutdown. The write holds the writer 2 s; the drain deadline is 1 s.
async function phaseLateWrite(f) {
  if (f.store !== 'sqlite') return console.log(`skip  latewrite: a ${f.store} build has no writer task`);
  const s = start(DRILL_BIN, { DRAIN_DEADLINE_MS: '1000' });
  if (!(await ready(s))) return record('latewrite: server starts', false);
  const w = await get(s.port, '/__test/crash/latewrite');
  const t0 = performance.now();
  if (WIN) get(s.port, '/__test/shutdown');
  else signal(s, 'TERM');
  await waitExit(s, 9000);
  const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
  record('latewrite: a write that outlasts the loops lets the process exit 0 within 3 s', w.status === 200 && s.exited === 0 && secs <= 3,
    `write=${w.status} exit=${s.exited} after ${secs.toFixed(2)} s`);
  await stop(s);

  // And a close that outlasts the shutdown's own bound: DRAIN_DEADLINE_MS + 1.5 s, then exit 70.
  const t = start(DRILL_BIN, { DRAIN_DEADLINE_MS: '200' });
  if (!(await ready(t))) return record('latewrite: server starts', false);
  await get(t.port, '/__test/crash/latewrite');
  const t1 = performance.now();
  if (WIN) get(t.port, '/__test/shutdown');
  else signal(t, 'TERM');
  await waitExit(t, 9000);
  const secs2 = t.exited === null ? Infinity : (t.exitAt - t1) / 1000;
  const said = /why="the shutdown didn't finish"/.test(t.out);
  record('latewrite: a close past DRAIN_DEADLINE_MS + 1.5 s exits 70, saying why', t.exited === 70 && secs2 <= 2.5 && said,
    `exit=${t.exited} after ${secs2.toFixed(2)} s, said=${said}`);
  await stop(t);
}

// kill -9, then the next server on the same port after 0, 50 and 100 ms: F-12's bind retry.
async function phaseRestart() {
  for (const delay of [0, 50, 100]) {
    const port = freePort();
    const a = start(RELEASE_BIN, {}, port);
    if (!(await ready(a))) { record(`restart +${delay} ms: first server starts`, false); continue; }
    await get(port, '/about');
    signal(a, 'KILL');
    await waitExit(a, 3000);
    await sleep(delay);
    const b = start(RELEASE_BIN, {}, port);
    const ok = await ready(b);
    record(`restart: kill -9, then a new server on the port after ${delay} ms`, ok, ok ? '' : b.out.slice(-300));
    await stop(b);
  }
}

// Past the open-file limit, keep-alive connections get the cap's 503, not a stalled accept: a
// fresh request still has an answer within 100 ms, and /livez is 200 once they go (Linux only:
// the limit is a ulimit).
async function phaseFdCeiling() {
  if (WIN) return record('fdceiling: Linux only (a ulimit)', true, 'skipped on Windows');
  const s = start(RELEASE_BIN, {}, freePort(), { ulimit: 256 });
  if (!(await ready(s))) return record('fdceiling: server starts under ulimit -n 256', false);
  const socks = [];
  const statuses = {};
  await Promise.all(Array.from({ length: 400 }, () => new Promise((res) => {
    const c = net.connect(s.port, '127.0.0.1', () => c.write('GET /livez HTTP/1.1\r\nHost: x\r\n\r\n'));
    let got = '';
    c.on('data', (d) => { got += d; const k = got.slice(9, 12); if (k) { statuses[k] = (statuses[k] || 0) + 1; res(); } });
    c.on('error', () => { statuses.err = (statuses.err || 0) + 1; res(); });
    c.on('close', () => res());
    socks.push(c);
  })));
  const t0 = performance.now();
  const r = await get(s.port, '/livez', { timeout: 1000 });
  const ms = performance.now() - t0;
  for (const c of socks) c.destroy();
  await sleep(500);
  const after = (await get(s.port, '/livez')).status;
  record('fdceiling: 400 keep-alive connections under ulimit -n 256: an answer within 100 ms, 200 after',
    r.status > 0 && ms < 100 && after === 200 && s.exited === null,
    `while full: ${r.status} in ${ms.toFixed(1)} ms; per connection ${JSON.stringify(statuses)}; after: ${after}`);
  await stop(s);
}

function rss(s) {
  if (WIN) {
    const r = spawnSync('powershell', ['-NoProfile', '-Command', `(Get-Process -Id ${s.pid}).WorkingSet64`], { encoding: 'utf8' });
    return Number(r.stdout.trim());
  }
  const r = WSL
    ? spawnSync('wsl', ['-e', 'cat', `/proc/${s.pid}/status`], { encoding: 'utf8' })
    : { stdout: readFileSync(`/proc/${s.pid}/status`, 'utf8') };
  return Number(/VmRSS:\s+(\d+) kB/.exec(r.stdout)?.[1] ?? 0) * 1024;
}

// RssAnon, RssFile and RssShmem in MB, and the transparent-hugepage mode.
function rssDetail(s) {
  const read = (f) => (WSL ? spawnSync('wsl', ['-e', 'cat', f], { encoding: 'utf8' }).stdout : readFileSync(f, 'utf8')) || '';
  const st = read(`/proc/${s.pid}/status`);
  const mb = (k) => (Number(new RegExp(`${k}:\\s+(\\d+) kB`).exec(st)?.[1] ?? 0) / 1000).toFixed(2);
  const thp = /\[(\w+)\]/.exec(read('/sys/kernel/mm/transparent_hugepage/enabled'))?.[1] ?? '?';
  return ` (anon ${mb('RssAnon')}, file ${mb('RssFile')}, shmem ${mb('RssShmem')}; THP ${thp})`;
}

async function phaseBudgets() {
  // Boot → /readyz, from the spawn, with the default loop count: the median of 5. Through WSL
  // the spawn costs wsl.exe's own start (about 0.7 s), so there the server's boot_ms counts.
  const times = [];
  for (let i = 0; i < 5; i++) {
    const s = start(RELEASE_BIN, { THREADS: '', LOG_LEVEL: 'info' });
    let ms = Infinity;
    for (let t = 0; t < 2000; t++) {
      if ((await get(s.port, '/readyz', { timeout: 200 })).status === 200) { ms = performance.now() - s.startAt; break; }
      if (s.exited !== null) break;
      await sleep(2);
    }
    if (WSL) ms = Number(/boot_ms=(\d+)/.exec(s.out)?.[1] ?? Infinity);
    times.push(ms);
    await stop(s);
  }
  times.sort((a, b) => a - b);
  const boot = times[2];
  record(`budgets: boot → /readyz ≤ ${BUDGET.readyMs} ms (median of 5, ${WSL ? "the server's boot_ms" : 'from the spawn'})`,
    boot <= BUDGET.readyMs, `${times.map((t) => t.toFixed(0)).join(' ')} ms`);

  // Idle memory at the loop count the budget states (16, the dev PC's default), whatever this
  // machine's core count, after a page, an asset and 3 s. On Linux the line also says what the
  // RSS is made of and the kernel's transparent-hugepage mode: a CI runner held 5 MB more than
  // the dev PC's Linux at 4 loops (M1's first runs), and the breakdown says where.
  const LOOPS = 16;
  const s = start(RELEASE_BIN, { THREADS: String(LOOPS), LOG_LEVEL: 'warn' });
  if (await ready(s)) {
    for (const p of ['/', '/about', '/static/app.css']) await get(s.port, p);
    await sleep(3000);
    const bytes = rss(s);
    const cap = BUDGET.idle(LOOPS);
    const name = `budgets: idle ${WIN ? 'working set' : 'RSS'} ≤ ${(cap / 1e6).toFixed(1)} MB (${PROFILE === 'full' ? "full's" : `6 + 0.4 × ${LOOPS} loops`})`;
    const got = `${(bytes / 1e6).toFixed(2)} MB${WIN ? '' : rssDetail(s)}`;
    // The budget is the dev PC's, as the size budget is Windows' (ANSWERS round 8): a CI runner
    // reports its figure and what it is made of, and doesn't fail on it.
    if (process.env.GITHUB_ACTIONS) console.log(`info  ${name}: ${got} (a CI runner reports it)`);
    else record(name, bytes > 0 && bytes <= cap, got);
  }
  await stop(s);

  // Size: the budget is Windows -o:speed's; elsewhere it's reported only.
  const bin = WSL ? null : path.join(ROOT, RELEASE_BIN);
  const size = bin && existsSync(bin) ? statSync(bin).size : 0;
  const cap = BUDGET.size[PROFILE];
  if (WIN && cap) record(`budgets: binary ≤ ${cap / MiB} MiB (Windows -o:speed)`, size <= cap, `${size} B`);
  else if (size) console.log(`info  budgets: binary ${size} B (the size budget is Windows')`);
}

// M1-02: a client that stops reading can't hold its connection, and a copy of its response,
// forever. It pipelines 100 requests for og.png (23 MB of answers), far past what the socket
// buffers take, and reads nothing; the send that stalls is cut at SEND_TIMEOUT_MS (plus the 1 s
// sweep), so when it reads again, the answers end before the hundredth.
async function phaseSlowRead() {
  const TIMEOUT = 1500;
  const s = start(DRILL_BIN, { SEND_TIMEOUT_MS: String(TIMEOUT) });
  if (!(await ready(s))) return record('slowread: server starts', false);
  const sock = net.connect(s.port, '127.0.0.1');
  sock.on('error', () => {});
  await new Promise((r) => sock.once('connect', r));
  sock.pause();
  sock.write('GET /static/og.png HTTP/1.1\r\nHost: x\r\n\r\n'.repeat(100));
  await sleep(TIMEOUT + 2500);
  let answers = 0;
  let tail = '';
  const closed = await new Promise((resolve) => {
    sock.on('data', (d) => {
      const text = tail + d.toString('latin1');
      answers += (text.match(/HTTP\/1\.1 200 /g) || []).length;
      tail = text.slice(-16);
    });
    sock.on('close', () => resolve(true));
    sock.resume();
    setTimeout(() => resolve(false), 8000);
  });
  sock.destroy();
  const alive = (await get(s.port, '/livez')).status === 200;
  const logged = /send waited past send_timeout/.test(s.out);
  record(`slowread: a client that stops reading is cut at the send timeout; serving goes on`,
    closed && answers < 100 && logged && alive && s.exited === null, `${answers}/100 answers, closed=${closed}, logged=${logged}`);
  await stop(s);
}

// M1-03: stderr is a pipe whose reader stopped. The loops block flushing their logs, /livez stops,
// and the watchdog's exit must not block behind the same lock: exit 70, with the crash file.
async function phaseLogStall() {
  // Under --wsl the server's output reaches node through wsl.exe, which buffers it: nothing stalls.
  if (WSL) return console.log('skip  logstall: under --wsl the output passes through wsl.exe, which buffers it');
  const s = start(DRILL_BIN, { LOG_LEVEL: 'info' });
  const crashFile = path.join(ROOT, `app/build/last-crash-${s.port}.txt`);
  try { unlinkSync(crashFile); } catch {} // an earlier run's, on the same port
  if (!(await ready(s))) return record('logstall: server starts', false);
  s.child.stdout.pause();
  s.child.stderr.pause();
  // Fill the pipe: the access log writes a line a request, until requests stop being answered.
  let stalledAt = 0;
  for (let i = 0; i < 200 && s.exited === null && !stalledAt; i++) {
    const rs = await Promise.all(Array.from({ length: 50 }, () => get(s.port, '/healthz', { timeout: 2000 })));
    if (rs.some((r) => r.status !== 200)) stalledAt = performance.now();
  }
  await waitExit(s, 20000);
  s.child.stdout.resume();
  s.child.stderr.resume();
  const secs = s.exited === null || !stalledAt ? Infinity : (s.exitAt - stalledAt) / 1000;
  let file = '';
  try { file = readFileSync(crashFile, 'utf8'); } catch {}
  record('logstall: a stalled log pipe ends in the watchdog\'s exit 70, with its crash file',
    s.exited === 70 && secs <= 15 && file.includes('loop stalled'), `exit=${s.exited} ${secs.toFixed(1)} s after the stall, file=${JSON.stringify(file.trim().slice(0, 60))}`);
  await stop(s);
}

// ---- streams (a profile that streams: lab's endpoints) --------------------------------------

// Admission caps a person never meets and this one client would: hundreds of streams a second.
const STREAMS_ENV = { STREAMS_PER_CLIENT: '100000', STREAM_CONNECTS: '100000', STREAMS_PER_USER: '100000', LAB_PUBLISH_PER_MINUTE: '100000000' };

// An SSE client on a raw socket (spike S0.7's): whether the drain's retry: event came.
function sseClient(port, path) {
  return new Promise((res) => {
    const c = { retry: false, opened: false, sock: null };
    const sock = net.connect(port, '127.0.0.1', () => sock.write(`GET ${path} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nAccept: text/event-stream\r\n\r\n`));
    c.sock = sock;
    let buf = '';
    sock.on('data', (d) => {
      buf += d;
      if (!c.opened && buf.includes(': open')) { c.opened = true; res(c); }
      if (/retry: \d+\nevent: restart\ndata: restarting/.test(buf)) c.retry = true;
    });
    sock.on('close', () => { if (!c.opened) res(c); });
    sock.on('error', () => {});
    setTimeout(() => res(c), 5000);
  });
}

// A WebSocket client on a raw socket: the server's close code; send() writes one masked text frame.
function wsClient(port, path) {
  return new Promise((res) => {
    const c = { code: 0, opened: false, sock: null, send: (text) => {
      const p = Buffer.from(text), mask = Buffer.from([1, 2, 3, 4]);
      const masked = Buffer.from(p.map((b, i) => b ^ mask[i % 4]));
      let head = Buffer.from([0x81, 0x80 | p.length]);
      if (p.length > 125) { // the 16-bit length (a frame here stays under WS_MAX_MESSAGE)
        head = Buffer.from([0x81, 0x80 | 126, 0, 0]);
        head.writeUInt16BE(p.length, 2);
      }
      c.sock.write(Buffer.concat([head, mask, masked]));
    } };
    const key = Buffer.from(Array.from({ length: 16 }, () => Math.floor(Math.random() * 256))).toString('base64');
    const sock = net.connect(port, '127.0.0.1', () => sock.write(
      `GET ${path} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`));
    c.sock = sock;
    let buf = Buffer.alloc(0), upgraded = false;
    sock.on('data', (d) => {
      buf = Buffer.concat([buf, d]);
      if (!upgraded) {
        const i = buf.indexOf('\r\n\r\n');
        if (i < 0) return;
        upgraded = buf.subarray(0, 12).toString() === 'HTTP/1.1 101';
        buf = buf.subarray(i + 4);
        c.opened = upgraded;
        res(c);
      }
      // Server frames are unmasked: a close frame (opcode 8) carries its code.
      while (buf.length >= 2) {
        const op = buf[0] & 0x0f, len = buf[1] & 0x7f;
        if (len > 125 || buf.length < 2 + len) break;
        if (op === 8 && len >= 2) c.code = buf.readUInt16BE(2);
        buf = buf.subarray(2 + len);
      }
    });
    sock.on('close', () => { if (!c.opened) res(c); });
    sock.on('error', () => {});
    setTimeout(() => res(c), 5000);
  });
}

// D15's `wsdata`: a trap inside a socket's on_data is pure. That socket closes 1011 (hx-ws reconnects on
// it); the server and every other socket stay up.
async function phaseWsData(f) {
  if (!f.features.includes('lab')) return console.log('skip  wsdata: no streams in this profile');
  const s = start(DRILL_BIN, STREAMS_ENV);
  if (!(await ready(s))) return record('wsdata: server starts', false);
  const by = await wsClient(s.port, '/lab/ws/echo');
  const c = await wsClient(s.port, '/__test/crash/wsdata');
  c.send('crash');
  for (let i = 0; i < 40 && !c.code; i++) await sleep(50);
  by.send('still here');
  await sleep(200);
  const alive = (await get(s.port, '/livez')).status === 200 && s.exited === null;
  const line = /ev=crash[^\n]*zone=pure[^\n]*msg="drill: a crash in a socket's on_data"/.test(s.out);
  record('wsdata: a crash in a socket\'s on_data closes it 1011; the server and the other socket stay up',
    c.opened && c.code === 1011 && by.code === 0 && alive && line, `code=${c.code} bystander=${by.code} alive=${alive} line=${line}`);
  by.sock.destroy();

  // M2-01: JSON nested past what core:encoding/json's recursion survives (a loop's stack is 1 MiB on Windows),
  // to the public room. Refused by stream.ws_field at WS_JSON_DEPTH: before, each frame was a stack overflow, and more than
  // GUARD_BURST of them a minute exited the process. M2-22: the same brackets behind a JSON5 comment holding a
  // `"`, which hid them from the scan, and a frame of 20,000 comments, which JSON5's tokenizer recursed through.
  // M2-30: behind a raw line feed in a key, which ends the strict tokenizer's string. 15 frames: one overflowed,
  // and the room caps 20 a second.
  const room = await wsClient(s.port, '/lab/ws/chat?room=deep');
  const deep = ['{"message":"x","headers":' + '['.repeat(60000), '{"message":"x","headers":/*"*/' + '['.repeat(60000),
    '{"message":"x"' + '//\n'.repeat(20000) + '}', '{"a\n:' + '['.repeat(60000)];
  for (let i = 0; i < 15; i++) room.send(deep[i % 4]);
  await sleep(500);
  const up = (await get(s.port, '/livez')).status === 200 && s.exited === null;
  const overflow = /kind=stack_overflow/.test(s.out);
  record('wsdata: 15 frames of JSON nested 60,000 deep (plain, behind a comment or a raw line feed) or of 20,000 comments are refused unparsed; the socket stays open, the server up',
    room.opened && room.code === 0 && up && !overflow, `code=${room.code} alive=${up} overflow=${overflow}`);
  room.sock.destroy();
  await stop(s);
}

// The shutdown bound with streams open (PLAN §8.7, §22.3's M2 gate): 500 SSE and 500 WebSocket clients, a
// slowloris, a half-sent body and an idle peer that never answers the FIN. Exit 0 within 6 s; every socket
// got 1012 and every SSE stream its retry: event, so the reconnects spread out.
async function phaseStreamDrain(f) {
  if (!f.features.includes('lab')) return console.log('skip  streamdrain: no streams in this profile');
  const s = start(DRILL_BIN, STREAMS_ENV);
  if (!(await ready(s))) return record('streamdrain: server starts', false);
  const sses = [], wss = [];
  for (let i = 0; i < 500; i += 50) {
    sses.push(...await Promise.all(Array.from({ length: 50 }, (_, j) => sseClient(s.port, `/events?t=lab.feed:drain-${i + j}`))));
    wss.push(...await Promise.all(Array.from({ length: 50 }, () => wsClient(s.port, '/lab/ws/echo'))));
  }
  const socks = [];
  const open = (fn) => { const c = net.connect(s.port, '127.0.0.1', () => fn(c)); c.on('error', () => {}); socks.push(c); return c; };
  const slow = open((c) => c.write('GET /healthz HTTP/1.1\r\nHost: x\r\n'));
  const slowTimer = setInterval(() => slow.write(`X-Slow-${Date.now()}: 1\r\n`), 1000);
  open((c) => c.write('POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\n\r\n' + 'x'.repeat(500)));
  const idle = open((c) => c.write('GET /healthz HTTP/1.1\r\nHost: x\r\n\r\n'));
  idle.on('data', () => idle.pause());
  await sleep(1000);
  const t0 = performance.now();
  if (WIN) get(s.port, '/__test/shutdown');
  else signal(s, 'TERM');
  await waitExit(s, 9000);
  const secs = s.exited === null ? Infinity : (s.exitAt - t0) / 1000;
  clearInterval(slowTimer);
  await sleep(200);
  const opened = sses.filter((c) => c.opened).length + wss.filter((c) => c.opened).length;
  const retry = sses.filter((c) => c.retry).length;
  const restart = wss.filter((c) => c.code === 1012).length;
  for (const c of [...sses, ...wss]) c.sock.destroy();
  for (const c of socks) c.destroy();
  record('streamdrain: 500 SSE + 500 WS + slow, half-sent and idle peers: exit 0 within 6 s; 1012 and retry: for each',
    opened === 1000 && s.exited === 0 && secs <= 6 && retry === 500 && restart === 500,
    `opened ${opened}/1000, exit=${s.exited} after ${secs.toFixed(2)} s, WS 1012 ${restart}/500, SSE retry: ${retry}/500`);
  await stop(s);
}

// The fd ceiling with streams (§22.3's M2 gate): 3000 SSE streams on a server under ulimit -n 4096 (a
// container's ulimits); /livez still answers within 100 ms. Linux only, as fdceiling is. The clients are
// tools/streamload's, on the server's own side: under --wsl, WSL's localhost relay gave out near 2000
// connections from Windows, which says nothing about the server.
// A path in the repo (app/bin/streamload) from its root; a bare name (curl) from PATH.
function onServerSide(cmd, args) {
  return WSL ? spawn('wsl', ['--cd', WSL, '-e', cmd, ...args], { stdio: ['ignore', 'pipe', 'pipe'] })
    : spawn(cmd.includes('/') ? path.join(ROOT, cmd) : cmd, args, { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
}

// The server's CPU time so far, in ms, read from outside: Windows' TotalProcessorTime, Linux's
// utime + stime (clock ticks of 10 ms).
function cpuMs(s) {
  if (WIN && !WSL) {
    const r = spawnSync('powershell', ['-NoProfile', '-Command', `(Get-Process -Id ${s.pid}).TotalProcessorTime.TotalMilliseconds`], { encoding: 'utf8' });
    return Number(r.stdout.trim());
  }
  const st = WSL ? spawnSync('wsl', ['-e', 'cat', `/proc/${s.pid}/stat`], { encoding: 'utf8' }).stdout : readFileSync(`/proc/${s.pid}/stat`, 'utf8');
  const f = st.slice(st.lastIndexOf(')') + 2).split(' ');
  return (Number(f[11]) + Number(f[12])) * 10;
}

// One ops render a second whatever the number of viewers (PLAN §15.4, M5): 1, 10 and 100 SSE
// viewers of the panel's topic, each held 10 s; the server's CPU a second at each count, and every
// viewer's refreshes. A nick build's loopback admin, so no password is involved.
async function phaseOpsViewers(f) {
  if (!f.features.includes('ops') || f.identity !== 'nick') return console.log('skip  opsviewers: no ops on the nick identity here');
  const s = start(RELEASE_BIN, {
    ...STREAMS_ENV, LOG_LEVEL: 'warn', LAN_CIDRS: '0.0.0.0/0', ACCOUNTS_NICK_FROM: 'all',
    ACCOUNTS_NICK_ADMIN_CIDRS: '0.0.0.0/0', ACCOUNTS_NICK_KEY: 'drill-only-nickname-signing-key-0123456789',
  });
  if (!(await ready(s))) return record('opsviewers: server starts', false);
  const cookie = await new Promise((res) => {
    const req = http.request({ host: '127.0.0.1', port: s.port, path: '/login', method: 'POST', agent: false,
      headers: { 'content-type': 'application/x-www-form-urlencoded' } }, (r) => {
      r.resume();
      res((r.headers['set-cookie'] ?? []).map((c) => c.split(';')[0]).join('; '));
    });
    req.on('error', () => res(''));
    req.end('nick=drill&next=%2F');
  });
  const watch = (n) => Array.from({ length: n }, () => {
    const v = { events: 0, req: null };
    v.req = http.get({ host: '127.0.0.1', port: s.port, path: '/events?t=ops.panel', agent: false, headers: { cookie } }, (r) => {
      r.setEncoding('utf8');
      r.on('data', (c) => { v.events += (c.match(/^id: /gm) || []).length; });
      r.on('error', () => {});
    });
    v.req.on('error', () => {});
    return v;
  });
  const rows = [];
  for (const n of [1, 10, 100]) {
    const vs = watch(n);
    await sleep(3000);
    const c0 = cpuMs(s); const e0 = vs.map((v) => v.events);
    await sleep(10000);
    const perS = (cpuMs(s) - c0) / 10;
    const least = Math.min(...vs.map((v, i) => v.events - e0[i]));
    rows.push({ n, perS, least });
    for (const v of vs) v.req.destroy();
    await sleep(1000);
  }
  const [one, , hundred] = rows;
  // Flat: 99 more viewers cost at most 3 % of a core (each gets the same bytes; nothing renders twice).
  record('opsviewers: 100 viewers of the ops panel cost about what 1 does, and every one refreshes each second',
    !!cookie && hundred.perS - one.perS <= 30 && rows.every((r) => r.least >= 8),
    rows.map((r) => `${r.n}: ${r.perS.toFixed(1)} ms CPU/s, the slowest viewer ${r.least} refreshes in 10 s`).join('; '));
  await stop(s);
}

// PLAN §18.4: 1000 concurrent mock generations, 20 tokens a second each, ≤ 1 core and ≤ +30 MB. Each
// answer is a guest's, on a stream of its own, and a new one starts as one ends, so there are 1000
// at once for the whole window. A mock answer is shorter than the budget's 200 tokens; its cost is
// per token, so the rate is what matters. The client's CPU isn't the server's: `cpuMs` reads the server.
async function phaseBotMock(f) {
  if (!f.features.includes('bot') || f.identity !== 'nick') return console.log('skip  botmock: no bot on the nick identity');
  const s = start(RELEASE_BIN, { ...STREAMS_ENV, LOG_LEVEL: 'warn', BOT_GUEST_PER_HOUR: '100000000', BOT_DELAY_MS: '50' });
  if (!(await ready(s))) return record('botmock: server starts', false);
  await sleep(500);
  const base = rss(s);
  let going = true, answers = 0, tokens = 0, failed = 0, live = 0, least = Infinity;
  const ask = () => {
    if (!going) return;
    live += 1;
    const req = http.request({ host: '127.0.0.1', port: s.port, path: '/bot/ask', method: 'POST', agent: false,
      headers: { 'content-type': 'application/x-www-form-urlencoded' } }, (r) => {
      if (r.statusCode !== 200) failed += 1;
      r.setEncoding('utf8');
      r.on('data', (c) => { tokens += (c.match(/hx-swap="beforeend"/g) || []).length; });
      r.on('end', () => { live -= 1; answers += 1; ask(); });
      r.on('error', () => { live -= 1; });
    });
    req.on('error', () => { live -= 1; if (going) failed += 1; });
    req.end('q=hello&delivery=sse');
  };
  for (let i = 0; i < 1000; i += 1) {
    ask();
    if (i % 100 === 99) await sleep(50);
  }
  await sleep(4000);
  const c0 = cpuMs(s), t0 = tokens, a0 = answers;
  for (let i = 0; i < 10; i += 1) {
    await sleep(1000);
    least = Math.min(least, live);
  }
  const perS = (cpuMs(s) - c0) / 10;
  const grew = rss(s) - base;
  going = false;
  record('botmock: 1000 concurrent mock generations cost at most a core and 30 MB',
    perS <= 1000 && grew <= 30e6 && least >= 990 && failed === 0,
    `${perS.toFixed(0)} ms CPU/s, +${(grew / 1e6).toFixed(1)} MB, at least ${least} at once, ${((tokens - t0) / 10).toFixed(0)} frames/s, ${((answers - a0) / 10).toFixed(0)} answers/s, ${failed} failed`);
  await stop(s);
}

// Files beside the server: under the checkout, in WSL's when the servers run there.
function onDisk(cmd, ...args) {
  return WSL ? spawnSync('wsl', ['--cd', WSL, '-e', cmd, ...args], { encoding: 'utf8' }).stdout ?? ''
    : spawnSync(cmd, args, { cwd: ROOT, encoding: 'utf8', shell: WIN }).stdout ?? '';
}
const listDir = (rel) => (WSL ? onDisk('ls', '-1', rel) : (existsSync(path.join(ROOT, rel)) ? readdirSync(path.join(ROOT, rel)).join('\n') : '')).split('\n').filter(Boolean);
const copyIn = (from, to) => (WSL ? onDisk('cp', from, to) : copyFileSync(path.join(ROOT, from), path.join(ROOT, to)));
const makeDir = (rel) => (WSL ? onDisk('mkdir', '-p', rel) : mkdirSync(path.join(ROOT, rel), { recursive: true }));
const removeDir = (rel) => (WSL ? onDisk('rm', '-rf', rel) : rmSync(path.join(ROOT, rel), { recursive: true, force: true }));

// One request with a method, a Host, headers and a form body.
function send(port, method, p, { host = '', headers = {}, form = null } = {}) {
  return new Promise((res) => {
    const body = form ? new URLSearchParams(form).toString() : '';
    const h = { ...headers, ...(host ? { host: `${host}:${port}` } : {}), ...(form ? { 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(body) } : {}) };
    const req = http.request({ host: '127.0.0.1', port, path: p, method, agent: false, headers: h, timeout: 5000 }, (r) => {
      let b = '';
      r.setEncoding('utf8');
      r.on('data', (c) => (b += c));
      r.on('end', () => res({ status: r.statusCode, headers: r.headers, body: b }));
    });
    req.on('timeout', () => { req.destroy(); res({ status: -1, headers: {}, body: '' }); });
    req.on('error', () => res({ status: 0, headers: {}, body: '' }));
    req.end(body);
  });
}

// e2e's test admin (e2e/helpers/accounts.ts): its hash, made with --hash-password.
const DRILL_ADMIN = { username: 'admin', password: 'e2e-and-load-only-password', hash: '$argon2id$v=19$m=19456,t=2,p=1$usNdKTDf754mp5KZr0QZOg$UmN+6Cr4ai7YMbp4f0SsrCtA/kmVO/w4cSHz7Fs8F8I' };

// M5's backup and restore drill (PLAN §11.8, §22.3): a contact before the backup and one after;
// the backup by the store.backup job, asked for on /admin/jobs as an admin would; a new server
// on the backup's copy has the first and not the second.
async function phaseBackup(f) {
  if (f.store !== 'sqlite' || !f.features.includes('jobs') || f.identity !== 'accounts') return console.log('skip  backup: no jobs on SQLite with accounts here');
  const dir = `app/build/backup-drill-${nextPort}`;
  removeDir(dir);
  makeDir(dir);
  const env = {
    DB_PATH: `${dir}/data.db`, LOG_LEVEL: 'warn', LAN_CIDRS: '0.0.0.0/0',
    ACCOUNTS_ADMIN_HASH: DRILL_ADMIN.hash, ACCOUNTS_ADMIN_TOTP: 'optional',
  };
  const s = start(RELEASE_BIN, env);
  if (!(await ready(s))) {
    await stop(s);
    return record('backup: server starts on a file', false, s.out.trim().split('\n').slice(-3).join(' | '));
  }
  const add = (port, name) => send(port, 'POST', '/contacts', { form: { name, email: `${name.replace(/\W/g, '').toLowerCase()}@example.com`, role: 'Member' } });
  const before = await add(s.port, 'Before Backup');
  const login = await send(s.port, 'POST', '/login', { host: 'localhost', form: { username: DRILL_ADMIN.username, password: DRILL_ADMIN.password } });
  const cookie = (login.headers['set-cookie'] ?? []).map((c) => c.split(';')[0]).join('; ');
  const asked = await send(s.port, 'POST', '/admin/jobs/run', { host: 'localhost', headers: { cookie, 'hx-request': 'true', 'hx-prompt': 'the drill' }, form: { job: 'store.backup' } });
  let copies = [];
  for (let i = 0; i < 100 && copies.length === 0; i++) {
    await sleep(100);
    copies = listDir(`${dir}/backups`).filter((n) => /^manual-\d{8}-\d{6}\.db$/.test(n)); // by hand: manual-
  }
  await sleep(300); // the copy is checked after it is written
  const after = await add(s.port, 'After Backup');
  await stop(s);
  if (copies.length === 0) {
    removeDir(dir);
    return record('backup: the job writes a backup', false, `contact ${before.status}, sign-in ${login.status}, run ${asked.status}`);
  }
  copyIn(`${dir}/backups/${copies[0]}`, `${dir}/restored.db`);
  const r = start(RELEASE_BIN, { ...env, DB_PATH: `${dir}/restored.db` });
  const up = await ready(r);
  const found = up ? await send(r.port, 'GET', '/api/search?q=Backup') : { status: 0, body: '[]' };
  let names = [];
  try { names = JSON.parse(found.body).map((c) => c.name); } catch { /* not JSON: the record says */ }
  record('backup: the job\'s backup restores into a server with what came before it and nothing after',
    before.status === 200 && asked.status === 200 && after.status === 200 && up && names.includes('Before Backup') && !names.includes('After Backup'),
    `writes ${before.status}/${after.status}, run ${asked.status}, ${copies[0]}; restored: ${JSON.stringify(names)}`);
  await stop(r);
  removeDir(dir);
}

// dbview never takes the writer's lock (PLAN §22.3, M5): a query that runs to its 2 s budget on
// the query pool, and beside it a write every 20 ms; the writes' slowest stays near what it was
// with no query at all.
async function phaseDbview(f) {
  if (f.store !== 'sqlite' || !f.features.includes('dbview')) return console.log('skip  dbview: no dbview here');
  const dir = `app/build/dbview-drill-${nextPort}`;
  removeDir(dir);
  makeDir(dir);
  const s = start(RELEASE_BIN, {
    DB_PATH: `${dir}/data.db`, LOG_LEVEL: 'warn', LAN_CIDRS: '0.0.0.0/0', CONTACTS_CAP: '0',
    ACCOUNTS_ADMIN_HASH: DRILL_ADMIN.hash, ACCOUNTS_ADMIN_TOTP: 'optional',
  });
  if (!(await ready(s))) {
    await stop(s);
    return record('dbview: server starts on a file', false, s.out.trim().split('\n').slice(-3).join(' | '));
  }
  const login = await send(s.port, 'POST', '/login', { host: 'localhost', form: { username: DRILL_ADMIN.username, password: DRILL_ADMIN.password } });
  const cookie = (login.headers['set-cookie'] ?? []).map((c) => c.split(';')[0]).join('; ');
  let n = 0;
  const writes = async (ms) => {
    const took = [];
    const until = performance.now() + ms;
    while (performance.now() < until) {
      const t0 = performance.now();
      const r = await send(s.port, 'POST', '/contacts', { form: { name: `Drill ${n}`, email: `drill${n++}@example.com`, role: 'Member' } });
      if (r.status === 200) took.push(performance.now() - t0);
      await sleep(20);
    }
    return took.sort((a, b) => a - b);
  };
  const alone = await writes(1500);
  const query = send(s.port, 'POST', '/admin/dbview', { host: 'localhost', headers: { cookie, 'hx-request': 'true' },
    form: { sql: 'WITH RECURSIVE r(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM r) SELECT count(*) FROM r' } });
  const beside = await writes(1800);
  const q = await query;
  const max = (a) => (a.length ? a[a.length - 1] : Infinity);
  // The writer's lock would hold a write for the query's whole 2 s: the bar sits far below that and
  // above a busy runner's hiccup (one write at 63 ms with the query burning a core, run 41251995318).
  const ok = alone.length > 20 && beside.length > 20 && /stopped past the 2 s budget/.test(q.body) && max(beside) <= Math.max(250, 3 * max(alone));
  record('dbview: a query running to its 2 s budget leaves the writes\' latency alone (never the writer\'s lock)', ok,
    `alone: ${alone.length} writes, slowest ${max(alone).toFixed(1)} ms; beside the query: ${beside.length}, slowest ${max(beside).toFixed(1)} ms; query ${q.status} ${/stopped past/.test(q.body) ? 'stopped at its budget' : JSON.stringify(q.body.slice(0, 80))}`);
  await stop(s);
  removeDir(dir);
}

async function phaseStreamFd(f) {
  if (WIN) return record('streamfd: Linux only (a ulimit)', true, 'skipped on Windows');
  if (!f.features.includes('lab')) return console.log('skip  streamfd: no streams in this profile');
  const s = start(RELEASE_BIN, { ...STREAMS_ENV, LOG_LEVEL: 'warn' }, freePort(), { ulimit: 4096 });
  if (!(await ready(s))) return record('streamfd: server starts under ulimit -n 4096', false);
  const sl = onServerSide('app/bin/streamload', ['hold', '--base', `http://127.0.0.1:${s.port}`, '--sse', '3000', '--ws', '0', '--for', '10']);
  let out = '';
  sl.stdout.on('data', (d) => (out += d));
  for (let i = 0; i < 300 && !/connected \d+ of 3000/.test(out); i++) await sleep(100);
  const opened = Number(/connected (\d+) of 3000/.exec(out)?.[1] ?? 0);
  // /livez from the server's side too, timed by curl.
  const probe = await new Promise((res) => {
    const c = onServerSide('curl', ['-s', '-o', '/dev/null', '-w', '%{http_code} %{time_total}', `http://127.0.0.1:${s.port}/livez`]);
    let o = '';
    c.stdout.on('data', (d) => (o += d));
    c.on('exit', () => res(o.trim().split(' ')));
  });
  const status = Number(probe[0] || 0), ms = Number(probe[1] || 9) * 1000;
  await new Promise((r) => sl.on('exit', r));
  await sleep(500);
  const after = (await get(s.port, '/livez')).status;
  record('streamfd: 3000 SSE streams under ulimit -n 4096: /livez within 100 ms, 200 after',
    opened === 3000 && status === 200 && ms < 100 && after === 200 && s.exited === null,
    `opened ${opened}/3000; /livez ${status} in ${ms.toFixed(1)} ms; after: ${after}`);
  await stop(s);
}

// M1-26: a stream that ends hands its connection back, and the next request runs inside the
// stream's own callback. One that crashes there is answered 500 and its connection closed, like
// any other, and serving goes on. A profile with a chunked stream to end only (lab's tick).
async function phaseStreamCrash(f) {
  if (!f.features.includes('lab')) return console.log('skip  streamcrash: no lab feature, no stream to end');
  const s = start(DRILL_BIN);
  if (!(await ready(s))) return record('streamcrash: server starts', false);
  const got = await new Promise((resolve) => {
    const sock = net.connect(s.port, '127.0.0.1');
    let buf = '';
    let sent = false;
    // The lab host by name (full serves two; a one-host profile answers any name).
    sock.on('connect', () => sock.write('GET /lab/sse/tick?n=1&ms=0 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n'));
    sock.on('data', (d) => {
      buf += d.toString('latin1');
      if (!sent && buf.endsWith('\r\n0\r\n\r\n')) {
        sent = true;
        buf = '';
        sock.write('GET /__test/crash/panic HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n'); // at once, on the same socket
      }
    });
    sock.on('close', () => resolve({ buf, closed: true }));
    sock.on('error', () => {});
    setTimeout(() => { sock.destroy(); resolve({ buf, closed: false }); }, 5000);
  });
  const alive = (await get(s.port, '/livez')).status === 200;
  record('streamcrash: a request after a stream that crashes gets 500 and a closed connection; serving goes on',
    got.buf.startsWith('HTTP/1.1 500') && got.closed && alive && s.exited === null,
    `got ${JSON.stringify(got.buf.slice(0, 12))} closed=${got.closed}`);
  await stop(s);
}

// ---- run ----------------------------------------------------------------------------

build(DRILL_BIN, '-define:TEST_ROUTES=true');
build(RELEASE_BIN, '-o:speed');
const f = features();
// streamfd's clients (Linux, a profile that streams).
if (!WIN && f.features.includes('lab') && phases.includes('streamfd')) {
  const args = ['build', 'tools/streamload', '-o:speed', '-out:app/bin/streamload'];
  const r = WSL ? spawnSync('wsl', ['--cd', WSL, '-e', 'odin', ...args], { stdio: 'inherit' })
    : spawnSync('odin', args, { cwd: ROOT, stdio: 'inherit' });
  if (r.status !== 0) throw new Error('build tools/streamload failed');
}
console.log(`${PROFILE} on ${WSL ? 'Linux (WSL)' : process.platform}: store ${f.store}; phases: ${phases.join(' ')}`);
const PH = {
  release: phaseRelease, pure: phasePure, dirty: () => phaseDirty(f), burst: phaseBurst, hang: phaseHang, logstall: phaseLogStall,
  malformed: phaseMalformed, slowread: phaseSlowRead, wsdata: () => phaseWsData(f), streamcrash: () => phaseStreamCrash(f), shutdown: phaseShutdown, streamdrain: () => phaseStreamDrain(f), latewrite: () => phaseLateWrite(f), restart: phaseRestart, fdceiling: phaseFdCeiling, streamfd: () => phaseStreamFd(f), opsviewers: () => phaseOpsViewers(f), botmock: () => phaseBotMock(f), backup: () => phaseBackup(f), dbview: () => phaseDbview(f), budgets: phaseBudgets,
};
for (const p of phases) {
  if (!PH[p]) { console.error(`unknown phase ${p}`); process.exit(2); }
  await PH[p]();
}
const failed = results.filter((r) => !r.pass);
console.log(`\n${PROFILE} (${WSL ? 'linux' : process.platform}): ${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
