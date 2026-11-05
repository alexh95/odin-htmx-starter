import type { FullConfig } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { lookup } from 'node:dns/promises';
import { existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';

// Resolve app/ relative to this config's location (not cwd or rootDir, which is
// the testDir). configFile is the absolute path to playwright.config.ts.
export function appDirFrom(config: FullConfig): string {
  const e2eDir = config.configFile ? path.dirname(config.configFile) : process.cwd();
  return path.resolve(e2eDir, '..', 'app');
}

// The profile under test (build.{sh,bat} <profile>): skeleton by default, the
// starter's witness of the skeleton; E2E_PROFILE=minimal runs the minimal one.
export const PROFILE = process.env.E2E_PROFILE || 'skeleton';

// The binary global-setup builds and helpers/server.ts starts, relative to app/.
export const BIN = process.platform === 'win32' ? `bin\\${PROFILE}.exe` : `bin/${PROFILE}`;

// Where each server's per-route request counters land when it stops
// (helpers/server.ts), for `tools/check parity` (PLAN §19.1.11): every route the
// profile mounts needs a non-zero count from e2e and from the load suite.
export function coverageDir(appDir: string): string {
  return path.join(appDir, 'build', 'coverage', 'e2e', PROFILE);
}

// Whether prepare's outputs are in place and match its current pins: each htmx
// and _hyperscript file by its SHA-256 in vendor/<package>/PINS, the SQLite
// source by the stamp prepare writes beside it (against prepare.sh's pin;
// prepare.bat pins the same), a library built after that source, and the
// profile's bundled assets.
function prepared(appDir: string): boolean {
  const at = (p: string) => path.join(appDir, p);
  const pins = readFileSync(at('prepare.sh'), 'utf8');
  const pin = (name: string) => pins.match(new RegExp(`^\\s*${name}=(\\w+)`, 'm'))?.[1];
  const lib = at(process.platform === 'win32' ? 'vendor/sqlite/sqlite3.lib' : 'vendor/sqlite/sqlite3.a');
  const sha = (p: string) => createHash('sha256').update(readFileSync(at(p))).digest('hex');
  try {
    const pinned = (pkg: string) => readFileSync(at(`vendor/${pkg}/PINS`), 'utf8').split('\n')
      .map((line) => line.trim().split(/\s+/))
      .filter(([file]) => file && !file.startsWith('#'))
      .every(([file, digest]) => sha(`vendor/${pkg}/${file}`) === digest);
    const htmx = pinned('htmx') && pinned('hyperscript');
    const stamp = readFileSync(at('vendor/sqlite/.stamp'), 'utf8').trim();
    return htmx && stamp === pin('SQLITE_SHA256')
      && statSync(lib).mtimeMs >= statSync(at('vendor/sqlite/sqlite3.c')).mtimeMs
      && existsSync(at(`build/${PROFILE}/main.js`));
  } catch {
    return false; // something is missing
  }
}

// Build the binary once, before any worker starts. Each worker then spawns its
// own copy on its own port (see fixtures.ts), so the in-memory stores are
// isolated and the suite can run fully in parallel.
export default async function globalSetup(config: FullConfig) {
  const appDir = appDirFrom(config);

  // E2E_PROXY names the deployed hosts (the stack Caddyfile's), so the suite would send its writes
  // to the real site unless this machine resolves the host to itself (CI's /etc/hosts lines).
  for (const name of ['E2E_PROXY', 'E2E_PROXY_LAB']) {
    if (!process.env[name]) continue;
    const host = new URL(process.env[name]!).hostname;
    const { address } = await lookup(host);
    if (address !== '127.0.0.1' && address !== '::1') {
      throw new Error(`[global-setup] ${name}'s host ${host} resolves to ${address}, not this machine: add "127.0.0.1 ${host}" to the hosts file`);
    }
  }

  mkdirSync(path.join(appDir, 'bin'), { recursive: true });
  // prepare runs only when there's work for it: prepare.bat refuses to start
  // without cl.exe on PATH even when nothing needs compiling, and CI restores
  // these outputs from a cache. When it does run, its failure stops the suite.
  if (!prepared(appDir)) {
    try {
      if (process.platform === 'win32') execFileSync('cmd', ['/c', path.join(appDir, 'prepare.bat')], { cwd: appDir, stdio: 'inherit' });
      else execFileSync('sh', [path.join(appDir, 'prepare.sh')], { cwd: appDir, stdio: 'inherit' });
    } catch {
      throw new Error('[global-setup] prepare failed: see its output above. On Windows it needs cl.exe, so run it from an x64 Native Tools prompt.');
    }
  }

  // Through build.{sh,bat} at the repo root, the one place a profile's flags live.
  // E2E_BUILD_FLAGS adds odin flags: the nightly's `-sanitize:address -debug`.
  const repo = path.resolve(appDir, '..');
  const flags = (process.env.E2E_BUILD_FLAGS || '').split(/\s+/).filter(Boolean);
  if (process.platform === 'win32') execFileSync('cmd', ['/c', path.join(repo, 'build.bat'), PROFILE, ...flags], { cwd: repo, stdio: 'inherit' });
  else execFileSync('sh', [path.join(repo, 'build.sh'), PROFILE, ...flags], { cwd: repo, stdio: 'inherit' });

  // This run's counters only, and this run's bearer for /metrics.
  const coverage = coverageDir(appDir);
  rmSync(coverage, { recursive: true, force: true });
  mkdirSync(coverage, { recursive: true });
  writeFileSync(path.join(coverage, '.token'), randomBytes(16).toString('hex'));

  // What the build mounts, in its own words: fixtures.ts runs a spec only when
  // the profile has every feature its tags name. Workers inherit the variable.
  process.env.E2E_FEATURES = execFileSync(path.join(appDir, BIN), ['--features', '--json'], { cwd: appDir, encoding: 'utf8' });
  if (JSON.parse(process.env.E2E_FEATURES).features.includes('bot')) {
    execFileSync('odin', ['build', 'tools/fakellama', `-out:${path.join('app', 'bin', process.platform === 'win32' ? 'fakellama.exe' : 'fakellama')}`], { cwd: repo, stdio: 'inherit' });
  }
}
