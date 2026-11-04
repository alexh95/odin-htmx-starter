import { spawn, type ChildProcess } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import path from 'node:path';
import type { FullConfig } from '@playwright/test';
import { appDirFrom, BIN, coverageDir } from '../global-setup';
import { ADMIN_HASH } from './accounts';

// Starts and talks to the server under test. fixtures.ts gives each worker one;
// specs that need their own (a file DB, a store they may wreck) start one here.
// The binary is built once in global-setup.ts.

// `output` is everything the server has printed so far, start-up banner included
// (a listener attached after startServer returns would miss that). `coverage` is
// where stopServer leaves its per-route counters.
export type Server = { port: number; proc: ChildProcess; output: () => string; coverage: string };
export type Resp = { status: number; body: string; headers: http.IncomingHttpHeaders };

// A port nothing listens on, picked by the OS. A fixed base can't promise that:
// two runs at once collide, and on Windows a second server binds a taken port
// without an error while the first keeps answering, so a stale build gets tested.
function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.on('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const { port } = probe.address() as net.AddressInfo;
      probe.close(() => resolve(port));
    });
  });
}

// Whether nothing listens on `port` on any interface: a fixed port (the proxy runs' upstream) taken by
// another server would answer the health check in the suite's place.
export function portFree(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const probe = net.createServer();
    probe.once('error', () => resolve(false));
    probe.listen(port, '0.0.0.0', () => probe.close(() => resolve(true)));
  });
}

// The env is pinned, not inherited: the server prefers PORT over argv, and an
// exported DB_PATH would aim the suite's deletes at a real database. An empty
// BIND_ALL/SITE_URL reads as unset, so the server stays on loopback with its
// built-in canonical origin. /metrics takes this run's bearer, so stopServer can
// read the counters. One client (this machine) opens far more streams than a
// person would, so the per-client stream caps are lifted (§9.4); the totals stand.
// The suite's browser is loopback, which nick counts as the LAN, so a nickname makes
// it a member; its key is fixed, so a nickname outlives a restart. The bot's mock is seeded
// (the same question, the same answer) and quick. An accounts build boots its first admin
// from the suite's test hash (helpers/accounts.ts holds the password) and lifts the sign-in
// limits, which the suite's many sign-ins from one client would hit, and lets that admin be one
// without TOTP; a spec that tests them starts its own server.
// `env` overrides (a spec's own DB_PATH); `port` reuses one (a restart).
// A build with a lab host (full, PLAN §7.3) answers two hosts on one port, told apart by name: the
// lab host is 127.0.0.1, where nearly every catalog feature lives and the raw helpers below
// already go, and the main host is any other name, `localhost`. A one-host build answers both.
const HOSTS: Record<string, string[]> = JSON.parse(process.env.E2E_FEATURES || '{}').hosts || {};
export const TWO_HOSTS = 'lab' in HOSTS;
// Behind a proxy (CI's e2e-proxy) the worker's server, on E2E_UPSTREAM_PORT, answers the proxied
// names (E2E_PROXY, and E2E_PROXY_LAB for a two-host build's lab host), so a direct request to it
// names them too; a spec's own server keeps the names above.
const PROXY = process.env.E2E_PROXY || '';
const PROXY_LAB = process.env.E2E_PROXY_LAB || '';
export const UPSTREAM = Number(process.env.E2E_UPSTREAM_PORT || 8080);
const proxied = (port: number) => PROXY !== '' && port === UPSTREAM;
export const mainHost = (port: number) =>
  proxied(port) ? new URL(PROXY).host : `${TWO_HOSTS ? 'localhost' : '127.0.0.1'}:${port}`;
const labHost = (port: number) => (proxied(port) && PROXY_LAB ? new URL(PROXY_LAB).host : '');
// The Host a direct request names to reach the lab host (or a one-host build's only one).
export const directHost = (port: number) => labHost(port) || `127.0.0.1:${port}`;
export const mainOrigin = (port: number) => `http://${mainHost(port)}`;

// Which host serves `feature`: the main one when only the main host mounts it.
export function hostOf(feature: string): 'main' | 'lab' {
  return TWO_HOSTS && (HOSTS.main || []).includes(feature) && !(HOSTS.lab || []).includes(feature) ? 'main' : 'lab';
}

export async function startServer(config: FullConfig, env: NodeJS.ProcessEnv = {}, port?: number): Promise<Server> {
  const appDir = appDirFrom(config);
  const coverage = coverageDir(appDir);
  port ??= await freePort();
  const proc = spawn(path.join(appDir, BIN), [], {
    cwd: appDir,
    env: {
      ...process.env, PORT: String(port), DB_PATH: ':memory:', BIND_ALL: '', SITE_URL: '',
      STREAM_CONNECTS: '1000000', STREAMS_PER_CLIENT: '4096', LAB_PUBLISH_PER_MINUTE: '100000000',
      LAN_CIDRS: '127.0.0.0/8', ACCOUNTS_NICK_KEY: 'e2e-only-nickname-signing-key-0123456789',
      BOT_SEED: '7', BOT_DELAY_MS: '25',
      ACCOUNTS_ADMIN_HASH: ADMIN_HASH, ACCOUNTS_LOGIN_PER_CLIENT: '1000000', ACCOUNTS_LOGIN_PER_NET: '1000000', ACCOUNTS_LOGIN_OVERALL: '1000000',
      ACCOUNTS_STEP_UP_PER_MEMBER: '1000000',
      ACCOUNTS_ADMIN_TOTP: 'optional', ACCOUNTS_REGISTRATION: 'open', ACCOUNTS_REGISTER_PER_HOUR: '1000000', ACCOUNTS_CODES_PER_HOUR: '1000000',
      UPLOADS_DIR: path.join(coverage, `uploads-${port}`), UPLOADS_PER_HOUR: '1000000',
      CONTACTS_CAP: '0', // full's demo cap: contacts/demo.spec sets its own
      // https and no port, like a real origin (hosts match by name): the SEO specs check its shape.
      ...(TWO_HOSTS ? { SITE_URL_LAB: proxied(port) && PROXY_LAB ? new URL(PROXY_LAB).origin : 'https://127.0.0.1' } : {}),
      METRICS_TOKEN_FILE: path.join(coverage, '.token'), ...env,
    },
  });
  // Kept so a failed start shows the server's own error (an io_uring/seccomp
  // abort, a DB it can't open) instead of a bare health timeout.
  let log = '';
  proc.stdout?.on('data', (d) => (log += d));
  proc.stderr?.on('data', (d) => (log += d));

  const deadline = Date.now() + 20_000;
  while (proc.exitCode === null && proc.signalCode === null && Date.now() < deadline) {
    try {
      if ((await get(port, '/healthz')).status === 200) return { port: port!, proc, output: () => log, coverage };
    } catch { /* not listening yet */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  const why = proc.exitCode !== null || proc.signalCode !== null
    ? `exited early (code=${proc.exitCode}, signal=${proc.signalCode})`
    : 'did not become healthy in 20 s';
  proc.kill();
  throw new Error(`server on :${port} ${why}\n--- server output ---\n${log || '(none)'}`);
}

// Stops a server, first keeping what each of its routes was asked
// (`app_http_requests_total`) in its own file under `coverage`. A server that
// can't answer (gone, or started with another METRICS_TOKEN_FILE) leaves none.
export async function stopServer({ port, proc, coverage }: Server): Promise<void> {
  if (proc.exitCode !== null || proc.signalCode !== null) return;
  try {
    const token = readFileSync(path.join(coverage, '.token'), 'utf8');
    const res = await request({ port, path: '/metrics', method: 'GET', headers: { authorization: `Bearer ${token}` } });
    const counts = res.body.split('\n').filter((l) => l.startsWith('app_http_requests_total{'));
    if (res.status === 200) writeFileSync(path.join(coverage, `${port}-${proc.pid}.prom`), counts.join('\n') + '\n');
  } catch { /* no counters from this one */ }
  return new Promise((resolve) => {
    if (proc.exitCode !== null || proc.signalCode !== null) return resolve();
    const giveUp = setTimeout(resolve, 3000); // so cleanup never hangs
    proc.once('exit', () => {
      clearTimeout(giveUp);
      resolve();
    });
    proc.kill();
  });
}

function request(opts: http.RequestOptions, body?: string): Promise<Resp> {
  return new Promise((resolve, reject) => {
    const lab = labHost(Number(opts.port));
    const headers = { ...(lab ? { host: lab } : {}), ...(opts.headers as http.OutgoingHttpHeaders) };
    const req = http.request({ host: '127.0.0.1', ...opts, headers }, (res) => {
      let b = '';
      res.on('data', (d) => (b += d));
      res.on('end', () => resolve({ status: res.statusCode ?? 0, body: b, headers: res.headers }));
    });
    req.on('error', reject);
    req.setTimeout(3000, () => req.destroy(new Error('request timeout')));
    req.end(body);
  });
}

// Writes `bytes` as they are, for a request node:http won't send (a malformed
// header), and resolves with the reply's status, or 0 if the connection ended
// without one. Only the status line is waited for: a keep-alive reply leaves the
// socket open.
export function raw(port: number, bytes: string): Promise<number> {
  return new Promise((resolve) => {
    const sock = net.connect(port, '127.0.0.1', () => sock.write(bytes));
    let got = '';
    const done = () => {
      sock.destroy();
      resolve(Number(/^HTTP\/1\.1 (\d{3}) /.exec(got)?.[1] ?? 0));
    };
    sock.setTimeout(3000, done);
    sock.on('data', (d) => {
      got += d;
      if (got.includes('\r\n')) done();
    });
    sock.on('error', done); // a reset is "no reply" too
    sock.on('close', done);
  });
}

export const get = (port: number, p: string, headers: http.OutgoingHttpHeaders = {}) => request({ port, path: p, method: 'GET', headers });
// The main host, where a two-host build's sessions are (helpers default to the lab host's 127.0.0.1).
export const onMain = (port: number): http.OutgoingHttpHeaders => ({ host: mainHost(port) });
export const del = (port: number, p: string) => request({ port, path: p, method: 'DELETE' });
export const post = (port: number, p: string, form: string, headers: http.OutgoingHttpHeaders = {}) =>
  request(
    {
      port, path: p, method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(form), ...headers },
    },
    form,
  );
