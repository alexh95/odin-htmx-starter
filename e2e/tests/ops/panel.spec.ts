import { test, expect } from '../../fixtures';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer, stopServer, type Server } from '../../helpers/server';
import { leave, member } from '../../helpers/members';

// /admin/ops (PLAN §15.4; named panel.spec: an ops.spec runs browser-less, see the config): the 1 Hz panel, rendered once and refreshed by each mode, for
// admins on the LAN. Admin is ACCOUNTS_NICK_ADMIN_CIDRS (ANSWERS round 9): these specs start
// a server of their own that gives it to loopback, so the worker's members stay members.
const T = { tag: ['@ops', '@accounts-nick'] };

async function adminServer(env: NodeJS.ProcessEnv = {}): Promise<Server> {
  return startServer(test.info().config, { ACCOUNTS_NICK_ADMIN_CIDRS: '127.0.0.1/32', ...env });
}

const since = async (page: import('@playwright/test').Page) =>
  Number((await page.locator('#ops-http .muted').innerText()).match(/(\d+) since boot/)![1]);

test.describe('ops', T, () => {
  for (const mode of ['sse', 'poll', 'multipart'] as const) {
    test(`the panel refreshes every second by ${mode}`, async ({ browser }) => {
      const s = await adminServer();
      const admin = await member(browser, `http://127.0.0.1:${s.port}`);
      try {
        const res = await admin.page.goto(`/admin/ops?mode=${mode}`);
        expect(res!.headers()['x-impl']).toBe(`ops.mode=${mode}`);
        const first = await since(admin.page);
        // Every request counts, so the number moves once a refresh lands. A request of our own each poll: the
        // sse mode makes none, and its first push can carry the page's own requests before `first` is read.
        await expect.poll(async () => {
          await admin.page.request.get('/livez');
          return since(admin.page);
        }, { timeout: 10_000 }).toBeGreaterThan(first);
        await expect(admin.page.locator('#ops-modules')).toContainText('hub');
        await expect(admin.page.locator('#ops-drops')).toHaveCount(0); // no store that counts drops in a memory build (M4-04)
        await expect(admin.page.locator('#ops-http svg.spark polyline')).toHaveCount(1);
        expect(admin.errors).toEqual([]);
      } finally {
        await leave(admin);
        await stopServer(s);
      }
    });
  }

  test('a poll for the render it has is a 304', async ({ browser }) => {
    const s = await adminServer();
    const admin = await member(browser, `http://127.0.0.1:${s.port}`);
    try {
      await expect.poll(async () => (await admin.context.request.get('/admin/ops/panel')).headers()['hx-ptag'] ?? '', { timeout: 5000 }).not.toBe('0');
      const r = await admin.context.request.get('/admin/ops/panel');
      const tag = r.headers()['hx-ptag'];
      const again = await admin.context.request.get('/admin/ops/panel', { headers: { 'HX-PTag': tag } });
      // A new sample may land between the two: then it is the new render, with its own tag.
      expect([304, 200]).toContain(again.status());
      if (again.status() === 200) expect(again.headers()['hx-ptag']).not.toBe(tag);
    } finally {
      await leave(admin);
      await stopServer(s);
    }
  });

  test('the crash the last run left is on the page', async ({ browser }) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ops-'));
    const file = path.join(dir, 'last-crash.txt');
    fs.writeFileSync(file, 'exit 70: lock held (route "GET /x", request a-1)\n');
    const s = await adminServer({ CRASH_FILE: file });
    const admin = await member(browser, `http://127.0.0.1:${s.port}`);
    try {
      await admin.page.goto('/admin/ops');
      await expect(admin.page.locator('.ops-crash')).toContainText('lock held (route "GET /x"');
    } finally {
      await leave(admin);
      await stopServer(s);
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  // M2-18: an admin by ACCOUNTS_NICK_ADMIN_CIDRS outside LAN_CIDRS gets neither the page nor its
  // topic, which once streamed the panel to anyone the page refused.
  test('an admin off the LAN gets neither the page nor the panel\'s stream', async ({ browser }) => {
    const s = await adminServer({ LAN_CIDRS: '10.0.0.0/8', ACCOUNTS_NICK_FROM: 'all' });
    const admin = await member(browser, `http://127.0.0.1:${s.port}`);
    try {
      expect((await admin.page.goto('/admin/ops'))!.status()).toBe(404);
      expect((await admin.context.request.get('/events?t=ops.panel')).status()).toBe(403);
    } finally {
      await leave(admin);
      await stopServer(s);
    }
  });

  // A server of its own too: behind a proxy the worker's sees the proxy, not the LAN, and .Lan_Only
  // answers 404 to everyone off the LAN before any perm is checked.
  test('a member gets 403, a guest the nickname page', async ({ browser }) => {
    const s = await startServer(test.info().config);
    const base = `http://127.0.0.1:${s.port}`;
    const ann = await member(browser, base);
    const context = await browser.newContext({ baseURL: base });
    try {
      const res = await ann.page.goto('/admin/ops');
      expect(res!.status()).toBe(403);
      const page = await context.newPage();
      await page.goto('/admin/ops');
      await expect(page).toHaveURL(/\/login/);
    } finally {
      await leave(ann);
      await context.close();
      await stopServer(s);
    }
  });
});
