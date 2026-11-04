import { test, expect, has } from '../../fixtures';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer, stopServer, get, post, onMain, type Server } from '../../helpers/server';
import { ADMIN } from '../../helpers/accounts';

// The backup runbook in docs/DATA.md, end to end: write a row to a file DB,
// back it up with `<bin> --backup` while the server is still running, then
// restore by starting a server on the copy. Any build on the sqlite store: a
// contact where it has contacts, a session where it has accounts (the copy still
// knows its cookie), a note where it has notes; a build with none of those (dbview
// alone) writes nothing, and its copy need only boot. API-only (no browser); starts
// its own servers.
test('a backup taken under a live server restores with the data in it', { tag: '@platform-sqlite' }, async () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'odin-backup-'));
  const live = path.join(dir, 'data.db');
  const copy = path.join(dir, 'backup.db');
  let srv: Server | undefined;
  try {
    srv = await startServer(test.info().config, { DB_PATH: live });
    const demo = has('contacts');
    const accounts = !demo && has('accounts-accounts');
    const notes = !demo && !accounts && has('notes');
    let marker = `Backup ${Date.now()}`;
    let cookie = '';
    if (accounts) {
      const made = await post(srv.port, '/login', `username=${ADMIN.username}&password=${ADMIN.password}`, onMain(srv.port));
      expect(made.status).toBe(303);
      cookie = String(made.headers['set-cookie']).split(';')[0];
      marker = `Signed in as ${ADMIN.username}`;
    } else if (demo || notes) {
      const made = demo
        ? await post(srv.port, '/contacts', `name=${encodeURIComponent(marker)}&email=backup@example.dev`)
        : await post(srv.port, '/notes', `body=${encodeURIComponent(marker)}`);
      expect(made.status).toBe(200);
    } else {
      marker = '';
    }

    // The same binary the server runs, whatever init renamed it to.
    const bin = srv.proc.spawnfile;
    const backup = (dest: string) =>
      execFileSync(bin, ['--backup', dest], { env: { ...process.env, DB_PATH: live }, stdio: 'pipe' });
    backup(copy);
    expect(existsSync(copy)).toBe(true);
    expect(() => backup(copy)).toThrow(); // never overwrites a file

    await stopServer(srv);
    srv = await startServer(test.info().config, { DB_PATH: copy });
    const page = demo ? `/api/search?q=${encodeURIComponent(marker)}` : accounts ? '/login' : '/';
    const restored = await get(srv.port, marker ? page : '/healthz', cookie ? { cookie, ...onMain(srv.port) } : {});
    expect(restored.status).toBe(200);
    expect(restored.body).toContain(marker);
  } finally {
    if (srv) await stopServer(srv);
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  }
});
