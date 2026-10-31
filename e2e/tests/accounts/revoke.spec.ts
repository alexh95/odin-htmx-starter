import { test, expect } from '../../fixtures';
import { startServer, stopServer, type Server, mainOrigin } from '../../helpers/server';
import { signIn } from '../../helpers/accounts';
import type { Browser, Page } from '@playwright/test';

// Revocation on streams (PLAN §17.2.3, X19): a role change or a disable ends the member's open
// streams. Their #live gets `kicked` and the page goes to sign in again; and even a page that
// ignored it (its #live stripped of data-revoke) settles: hx-sse meets 403 as a guest and
// gives up, at most 3 reconnects in 30 s.
const T = { tag: ['@accounts-accounts'] };

async function own(env: NodeJS.ProcessEnv, run: (s: Server, base: string) => Promise<void>) {
  const s = await startServer(test.info().config, env);
  try {
    await run(s, mainOrigin(s.port));
  } finally {
    await stopServer(s);
  }
}

// A registered member on a page with its #live connected; `events` counts their /events requests.
async function member(browser: Browser, base: string, name: string) {
  const context = await browser.newContext({ baseURL: base });
  const page = await context.newPage();
  const events: number[] = [];
  page.on('request', (r) => { if (new URL(r.url()).pathname === '/events') events.push(Date.now()); });
  await page.goto('/register');
  await page.locator('#username').fill(name);
  await page.locator('#password').fill('a-long-enough-password');
  await page.locator('#again').fill('a-long-enough-password');
  await page.getByRole('button', { name: 'Join' }).click();
  await page.waitForURL((u) => u.pathname === '/');
  await page.goto('/accounts/profile');
  await expect(page.locator('#live[data-revoke="/login"]')).toHaveCount(1);
  await expect.poll(() => events.length).toBeGreaterThan(0);
  return { context, page, events };
}

async function act(admin: Page, username: string, button: string) {
  await admin.goto('/admin/accounts');
  const row = admin.locator('.admin-user').filter({ has: admin.getByRole('cell', { name: username, exact: true }) });
  if (button === 'Set role') await row.locator('select[name="role"]').selectOption('Moderator');
  await row.getByRole('button', { name: button }).click();
}

test.describe('revoke', T, () => {
  test('a role change sends the member page to sign in again', async ({ browser }) => {
    await own({ ACCOUNTS_REGISTRATION: 'open' }, async (_, base) => {
      const kim = await member(browser, base, 'kim');
      const admin = await signIn(browser, base, '/admin/accounts');
      admin.page.on('dialog', (d) => d.accept('promoted'));
      const at = Date.now();
      await act(admin.page, 'kim', 'Set role');
      await kim.page.waitForURL((u) => u.pathname === '/login', { timeout: 10_000 });
      await kim.page.waitForTimeout(3000);
      expect(kim.events.filter((t) => t > at).length).toBeLessThanOrEqual(3);
      await Promise.all([kim.context.close(), admin.context.close()]);
    });
  });

  // M4-09: a member's revoke of one device ends that device's streams, and only its.
  test("revoking a device sends its page to sign in again; this device's page stays", async ({ browser }) => {
    await own({ ACCOUNTS_REGISTRATION: 'open' }, async (_, base) => {
      const here = await member(browser, base, 'ada');
      const there = await browser.newContext({ baseURL: base });
      const away = await there.newPage();
      let opened = 0;
      away.on('request', (r) => { if (new URL(r.url()).pathname === '/events') opened += 1; });
      await away.goto('/login');
      await away.locator('#username').fill('ada');
      await away.locator('#password').fill('a-long-enough-password');
      await away.getByRole('button', { name: 'Sign in' }).click();
      await away.waitForURL((u) => u.pathname === '/');
      await away.goto('/accounts/profile');
      await expect(away.locator('#live[data-revoke="/login"]')).toHaveCount(1);
      await expect.poll(() => opened).toBeGreaterThan(0);

      const watcher = await here.context.newPage(); // this device's own open page, on its own stream
      await watcher.goto('/accounts/profile');
      await expect(watcher.locator('#live[data-revoke="/login"]')).toHaveCount(1);

      await here.page.goto('/accounts/sessions');
      await here.page.locator('.session', { hasNotText: 'this device' }).getByRole('button', { name: 'Revoke' }).click();
      await expect(here.page.locator('.session')).toHaveCount(1);
      await away.waitForURL((u) => u.pathname === '/login', { timeout: 10_000 });
      await watcher.waitForTimeout(2000);
      expect(new URL(watcher.url()).pathname).toBe('/accounts/profile');
      await Promise.all([here.context.close(), there.close()]);
    });
  });

  test('a page that ignores the kick settles: 403 as a guest, at most 3 reconnects in 30 s', async ({ browser }) => {
    test.setTimeout(60_000);
    await own({ ACCOUNTS_REGISTRATION: 'open' }, async (_, base) => {
      const lee = await member(browser, base, 'lee');
      await lee.page.evaluate(() => document.getElementById('live')!.removeAttribute('data-revoke'));
      const admin = await signIn(browser, base, '/admin/accounts');
      admin.page.on('dialog', (d) => d.accept('away for a while'));
      const at = Date.now();
      await act(admin.page, 'lee', 'Disable');
      await lee.page.waitForTimeout(30_000);
      expect(new URL(lee.page.url()).pathname).toBe('/accounts/profile'); // nothing navigated it
      expect(lee.events.filter((t) => t > at).length).toBeLessThanOrEqual(3);
      await Promise.all([lee.context.close(), admin.context.close()]);
    });
  });
});
