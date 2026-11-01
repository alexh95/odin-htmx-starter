import crypto from 'node:crypto';
import type { Browser, BrowserContext, Page } from '@playwright/test';

// Members (PLAN §17.1): each in a browser context of its own, so their cookies stay apart. On a
// nick build, a nickname picked at /login; on an accounts build (full, M6), an account registered
// at /register, which the suite's servers keep open (helpers/server.ts). The suite's browser is
// loopback, which the test server counts as the LAN.

export type Member = { name: string; context: BrowserContext; page: Page; errors: string[] };

export const uid = (p: string) => `${p}${crypto.randomBytes(3).toString('hex')}`;

const IDENTITY: string = JSON.parse(process.env.E2E_FEATURES || '{}').identity ?? '';

export async function member(browser: Browser, baseURL: string, name = uid('m')): Promise<Member> {
  const context = await browser.newContext({ baseURL });
  const page = await context.newPage();
  // An uncaught error or a CSP refusal on any page of theirs fails the spec that reads `errors`. But
  // not one: _hyperscript's bootstrap fetches its `text/hyperscript` scripts with no catch, and
  // Firefox rejects a fetch that a navigation cuts (AbortError, or a NetworkError) where Chromium
  // stays silent. A spec navigates the moment `load` fires, so on the hyperscript client (full) that
  // fetch was cut every few pages; it is never the page's fault (an answer, even a 404, resolves it).
  const errors: string[] = [];
  page.on('pageerror', (e) => {
    const cut = /^(AbortError|TypeError)$/.test(e.name) && /aborted|NetworkError/.test(e.message);
    if (cut && /\/static\/_hyperscript\.[0-9a-f]+\.min\.js/.test(e.stack || '')) return;
    // With where it was thrown: WebKit's "…due to access control checks" for a cut /events has
    // come without a source to go by.
    const at = String(e.stack || '').split(String.fromCharCode(10)).slice(0, 4).join(' / ');
    errors.push(at ? `${e.message} @ ${at}` : e.message);
  });
  page.on('console', (m) => {
    if (m.type() === 'error' && /Content Security Policy|Refused to/.test(m.text())) errors.push(m.text());
  });
  if (IDENTITY === 'accounts') {
    await page.goto('/register');
    await page.locator('#username').fill(name);
    await page.locator('#password').fill('a-long-enough-password');
    await page.locator('#again').fill('a-long-enough-password');
    await page.getByRole('button', { name: 'Join' }).click();
    await page.waitForURL((u) => u.pathname !== '/register');
  } else {
    await page.goto('/login');
    await page.locator('#nick').fill(name);
    await page.getByRole('button', { name: 'Use this nickname' }).click();
    await page.waitForURL((u) => u.pathname !== '/login');
  }
  return { name, context, page, errors };
}

export async function leave(...members: Member[]) {
  for (const m of members) await m.context.close();
}
