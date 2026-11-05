import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { leave, member, uid } from '../../helpers/members';

// The history cache is opt-in (PLAN §12): the layout marks every page's <main> `hx-history="false"` and
// only a public wiki page leaves it off, so a page can't be snapshotted into sessionStorage by being
// forgotten. A boost replaces the body's children, so the mark has to live inside them.
const T = { tag: ['@wiki', '@wiki-sqlite', '@accounts-accounts'] };

const snapshots = (page: Page) => page.evaluate(() => Object.keys(sessionStorage).filter((k) => k.startsWith('htmx-history-') && k !== 'htmx-history-index'));
const held = (page: Page) => page.evaluate(() => Object.keys(sessionStorage).filter((k) => k.startsWith('htmx-history-')).map((k) => sessionStorage.getItem(k)).join('\n'));

function fetches(page: Page, path: RegExp): string[] {
  const seen: string[] = [];
  page.on('request', (r) => { if (path.test(new URL(r.url()).pathname)) seen.push(r.url()); });
  return seen;
}

test.describe('the history cache', { tag: '@wiki' }, () => {
  test("a guest's back and forward over the wiki hit no server", async ({ page }) => {
    await page.goto('/wiki');
    const heading = await page.locator('main h1').first().textContent();
    await page.locator('.wiki-pages a[href="/wiki/philosophy"]').click();
    await page.waitForURL('**/wiki/philosophy');
    await expect(page.locator('.wiki-body')).toBeVisible();
    const hits = fetches(page, /^\/wiki/);
    await page.goBack();
    await expect(page.locator('.wiki-pages')).toBeVisible();
    await expect(page.locator('main h1').first()).toHaveText(heading!);
    await page.goForward();
    await expect(page.locator('.wiki-body')).toBeVisible();
    await page.goBack();
    await expect(page.locator('.wiki-pages')).toBeVisible();
    expect(hits).toEqual([]);
  });

  test("a boost carries the page's own head", async ({ page }) => {
    await page.goto('/wiki');
    await page.locator('.wiki-pages a[href="/wiki/philosophy"]').click();
    await page.waitForURL('**/wiki/philosophy');
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', /\/wiki\/philosophy$/);
    await expect(page).toHaveTitle(/Philosophy|philosophy/i);
  });
});

test.describe('nothing private is kept', T, () => {
  test('a boost into a private page and away leaves no snapshot', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/about');
    await ann.page.locator('.nav-link[href="/chat"]').click();
    await ann.page.waitForURL('**/chat');
    await ann.page.locator('.nav-link[href="/about"]').click();
    await ann.page.waitForURL('**/about');
    await ann.page.locator('.nav-link[href="/notify"]').click();
    await ann.page.waitForURL('**/notify');
    await expect(ann.page.locator('main')).toHaveAttribute('hx-history', 'false');
    expect(await snapshots(ann.page)).toEqual([]);
    await leave(ann);
  });

  test('a hard load of a private page leaves the next public page free to be kept', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    await ann.page.locator('.nav-link[href="/wiki"]').click();
    await ann.page.waitForURL('**/wiki');
    await ann.page.locator('.wiki-pages a[href="/wiki/philosophy"]').click();
    await ann.page.waitForURL('**/wiki/philosophy');
    await expect(ann.page.locator('.wiki-body')).toBeVisible();
    await ann.page.locator('.nav-link[href="/chat"]').click();
    await ann.page.waitForURL('**/chat');
    const hits = fetches(ann.page, /^\/wiki/);
    await ann.page.goBack();
    await expect(ann.page.locator('.wiki-body')).toBeVisible();
    expect(hits).toEqual([]);
    await leave(ann);
  });

  test("a members' page, and a member's index with its title, leave nothing", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const title = uid('Secret ');
    await ann.page.goto('/wiki/new');
    await ann.page.locator('#wiki-title').fill(title);
    await ann.page.locator('#wiki-md').fill('a secret');
    await ann.page.getByRole('button', { name: 'Save' }).click();
    await ann.page.waitForURL((u) => u.pathname.startsWith('/wiki/secret'));
    await ann.page.goto('/wiki');
    await ann.page.locator('.wiki-pages a', { hasText: title }).click();
    await ann.page.waitForURL((u) => u.pathname.startsWith('/wiki/secret'));
    await expect(ann.page.locator('main')).toHaveAttribute('hx-history', 'false');
    await ann.page.locator('.nav-link[href="/about"]').click();
    await ann.page.waitForURL('**/about');
    expect(await held(ann.page)).not.toContain(title);
    await leave(ann);
  });

  test('signing out clears the snapshots', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/wiki/philosophy');
    await ann.page.locator('.nav-link[href="/about"]').click();
    await ann.page.waitForURL('**/about');
    expect((await snapshots(ann.page)).length).toBeGreaterThan(0);
    await ann.page.goto('/login');
    await ann.page.evaluate(() => { (window as any).__stayed = 1; });
    await ann.page.getByRole('button', { name: 'Sign out' }).click();
    await ann.page.waitForURL((u) => !u.pathname.startsWith('/account'));
    await expect.poll(() => snapshots(ann.page)).toEqual([]);
    await leave(ann);
  });
});
