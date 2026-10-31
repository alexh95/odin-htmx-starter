import { test, expect } from '../../fixtures';
import http from 'node:http';
import type net from 'node:net';
import { startServer, stopServer, mainOrigin } from '../../helpers/server';

// /status (PLAN §15.4): a card per probe, filled by one multipart/parallel response or, with
// ?mode=poll, every 30 s (304 while no state changed). What a probe says beyond its state is
// for admins (ops's panel.spec servers have one); a guest sees states only.
const T = { tag: '@status' };

test.describe('status', T, () => {
  for (const mode of ['parallel', 'poll'] as const) {
    test(`the board fills ${mode === 'poll' ? 'by a poll' : 'from one multipart/parallel response'}`, async ({ page }) => {
      const errors: string[] = [];
      page.on('pageerror', (e) => errors.push(e.message));
      const res = await page.goto(mode === 'poll' ? '/status?mode=poll' : '/status');
      expect(res!.headers()['x-impl']).toBe(`status.mode=${mode}`);
      for (const probe of ['loops', 'process']) {
        await expect(page.locator(`#st-${probe} .status-state`)).toHaveText('ok');
      }
      await expect(page.locator('.status-checking')).toHaveCount(0);
      await expect(page.locator('#st-process')).not.toContainText('version'); // details are an admin's
      expect(errors).toEqual([]);
    });
  }

  test('the parts are multipart/parallel, and a poll with the board\'s tag is a 304', async ({ request }) => {
    const parts = await request.get('/status/parts');
    expect(parts.headers()['content-type']).toMatch(/^multipart\/parallel; boundary=/);
    expect(await parts.text()).toContain('HX-Target: #st-loops');
    const board = await request.get('/status/board');
    const tag = board.headers()['hx-ptag'];
    expect(tag).toMatch(/^\d+$/);
    const again = await request.get('/status/board', { headers: { 'HX-PTag': tag } });
    expect(again.status()).toBe(304);
  });

  // M5's parallel order: each external's part swaps in as its probe answers, so a fast witness
  // is up on the board while a slow one is still being checked. Both answers are let go stale
  // (FRESH, 5 s) before the page loads, so the page waits on a fresh probe of each.
  test('parts arrive in the order their probes answer', async ({ browser }) => {
    const fake = (delay: number) => new Promise<http.Server>((res) => {
      const srv = http.createServer((_, r) => setTimeout(() => r.writeHead(200, { 'x-version': `fake-${delay}` }).end('ok'), delay));
      srv.listen(0, '127.0.0.1', () => res(srv));
    });
    const fast = await fake(0);
    const slow = await fake(1500);
    const port = (srv: http.Server) => (srv.address() as net.AddressInfo).port;
    const s = await startServer(test.info().config, { STATUS_PROBES: `fast=127.0.0.1:${port(fast)},slow=127.0.0.1:${port(slow)}` });
    const context = await browser.newContext({ baseURL: mainOrigin(s.port) });
    const page = await context.newPage();
    try {
      await page.waitForTimeout(7500); // the slow answer comes 1.5 s after boot: stale 5 s after that
      await page.goto('/status');
      await expect(page.locator('#st-fast .status-state')).toHaveText('ok');
      await expect(page.locator('#st-slow .status-state')).toHaveText('checking…');
      await expect(page.locator('#st-slow .status-state')).toHaveText('ok', { timeout: 3000 });
      await expect(page.locator('#st-slow')).toContainText('version fake-1500');
    } finally {
      await context.close();
      await stopServer(s);
      fast.close();
      slow.close();
    }
  });

  // The witness board (M3): STATUS_PROBES' externals, each its own card, whose state and the
  // version it answers are anyone's to see. One witness runs; the other's port is closed.
  test('external probes: a live witness is ok with its version, a gone one down', async ({ browser }) => {
    const live = await startServer(test.info().config);
    const s = await startServer(test.info().config, { STATUS_PROBES: `alive=127.0.0.1:${live.port},gone=127.0.0.1:9` });
    const context = await browser.newContext({ baseURL: mainOrigin(s.port) });
    const page = await context.newPage();
    try {
      // Both answer within a round (a refused connect takes about 2 s on Windows).
      await expect.poll(async () => {
        await page.goto('/status');
        // The cards render "checking…" and /status/parts fills them in after load: read them once it has.
        await expect(page.locator('#st-process .status-state')).toHaveText('ok');
        return [await page.locator('#st-alive .status-state').innerText(), await page.locator('#st-gone .status-state').innerText()];
      }, { timeout: 15000 }).toEqual(['ok', 'down']);
      await expect(page.locator('#st-alive')).toContainText(/version \S+, \d+ ms/);
      // Windows retries a refused SYN for about 2 s, past the probe's 2 s connect: there it reads as no connection.
      await expect(page.locator('#st-gone')).toContainText(process.platform === 'win32' ? /refused|no connection in \d+ ms/ : /refused/);
    } finally {
      await context.close();
      await stopServer(s);
      await stopServer(live);
    }
  });
});
