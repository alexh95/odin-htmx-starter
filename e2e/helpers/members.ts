import crypto from 'node:crypto';
import type { Browser, BrowserContext, Page } from '@playwright/test';

// Members of a nick build (PLAN §17.1): each in a browser context of its own, so
// their cookies stay apart, with a nickname picked at /login. The suite's browser
// is loopback, which the test server counts as the LAN (helpers/server.ts).

export type Member = { name: string; context: BrowserContext; page: Page; errors: string[] };

export const uid = (p: string) => `${p}${crypto.randomBytes(3).toString('hex')}`;

export async function member(browser: Browser, baseURL: string, name = uid('m')): Promise<Member> {
  const context = await browser.newContext({ baseURL });
  const page = await context.newPage();
  // An uncaught error or a CSP refusal on any page of theirs fails the spec that reads `errors`.
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => {
    if (m.type() === 'error' && /Content Security Policy|Refused to/.test(m.text())) errors.push(m.text());
  });
  await page.goto('/login');
  await page.locator('#nick').fill(name);
  await page.getByRole('button', { name: 'Use this nickname' }).click();
  await page.waitForURL((u) => u.pathname !== '/login');
  return { name, context, page, errors };
}

export async function leave(...members: Member[]) {
  for (const m of members) await m.context.close();
}
