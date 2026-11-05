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

  test("a guest's public page survives a private one between", async ({ page }) => {
    await page.goto('/find');
    await page.locator('.nav-link[href="/wiki"]').click();
    await page.waitForURL('**/wiki');
    await page.locator('.wiki-pages a[href="/wiki/philosophy"]').click();
    await page.waitForURL('**/wiki/philosophy');
    await expect(page.locator('.wiki-body')).toBeVisible();
    await page.locator('.nav-link[href="/find"]').click();
    await page.waitForURL('**/find');
    await expect(page.locator('main')).toHaveAttribute('hx-history', 'false');
    const hits = fetches(page, /^\/wiki/);
    await page.goBack();
    await expect(page.locator('.wiki-body')).toBeVisible();
    expect(hits).toEqual([]);
  });

  test("a member's pages are never kept, a public one included", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/wiki/philosophy');
    await expect(ann.page.locator('main')).toHaveAttribute('hx-history', 'false');
    await ann.page.locator('.nav-link[href="/about"]').click();
    await ann.page.waitForURL('**/about');
    expect(await snapshots(ann.page)).toEqual([]);
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

  test("a member's index, which holds members' titles, isn't stored", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const res = await ann.page.request.get('/wiki');
    expect(res.headers()['cache-control']).toContain('no-store');
    await leave(ann);
  });

  test("what a guest kept goes when they sign in and out in that tab", async ({ browser, baseURL }) => {
    const context = await browser.newContext({ baseURL });
    const page = await context.newPage();
    await page.goto('/wiki/philosophy');
    await page.locator('.nav-link[href="/about"]').click();
    await page.waitForURL('**/about');
    expect((await snapshots(page)).length).toBeGreaterThan(0);
    await page.goto('/register');
    await page.locator('#username').fill(uid('m'));
    await page.locator('#password').fill('a-long-enough-password');
    await page.locator('#again').fill('a-long-enough-password');
    await page.getByRole('button', { name: 'Join' }).click();
    await page.waitForURL((u) => u.pathname !== '/register');
    await page.goto('/login');
    await page.getByRole('button', { name: 'Sign out' }).click();
    // The sign-out's navigation can pull the page out from under a read: that read just goes again.
    await expect.poll(() => snapshots(page).catch(() => ['navigating'])).toEqual([]);
    await context.close();
  });
});
