import { test, expect } from '../../fixtures';
import type { Browser, Page } from '@playwright/test';
import { leave, member, uid } from '../../helpers/members';

// Writing the wiki (PLAN §6), on SQLite with an identity: who reads what, a save over a newer revision,
// what the Manual refuses, and that a page's text stays text.
const T = { tag: ['@wiki', '@wiki-sqlite', '@accounts-accounts'] };

async function write(page: Page, title: string, md: string, visibility: 'members' | 'public' = 'members'): Promise<string> {
  await page.goto('/wiki/new');
  await page.locator('#wiki-title').fill(title);
  await page.locator('#wiki-visibility').selectOption(visibility);
  await page.locator('#wiki-md').fill(md);
  await page.getByRole('button', { name: 'Save' }).click();
  await page.waitForURL((u) => /^\/wiki\/[a-z0-9-]+$/.test(u.pathname) && u.pathname !== '/wiki/new');
  return new URL(page.url()).pathname;
}

async function guest(browser: Browser, baseURL: string) {
  const context = await browser.newContext({ baseURL });
  return { context, page: await context.newPage() };
}

test.describe('writing the wiki', T, () => {
  test("a members' page is theirs: a guest gets the 404 a missing page gets", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const href = await write(ann.page, uid('Secret '), 'only for **members**');
    await expect(ann.page.locator('.wiki-body strong')).toHaveText('members');
    const seen = await ann.page.request.get(href);
    expect(seen.headers()['cache-control']).toBe('no-store');
    expect(seen.headers()['x-robots-tag']).toContain('noindex');

    const g = await guest(browser, baseURL!);
    expect((await g.page.goto(href))?.status()).toBe(404);
    expect((await g.page.request.get(`${href}.md`)).status()).toBe(404);
    await g.page.goto('/wiki');
    await expect(g.page.locator(`.wiki-pages a[href="${href}"]`)).toHaveCount(0);
    await g.context.close();
    await leave(ann);
  });

  test('a public page is read by anyone, and downloads as what was written', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const href = await write(ann.page, uid('Open '), '# Heading\n\nfor *all*', 'public');
    const g = await guest(browser, baseURL!);
    const res = await g.page.goto(href);
    expect(res?.status()).toBe(200);
    expect(res?.headers()['cache-control'] ?? '').not.toContain('no-store');
    await expect(g.page.locator('.wiki-body em')).toHaveText('all');
    await expect(g.page.getByRole('link', { name: 'Edit' })).toHaveCount(0);
    const md = await g.page.request.get(`${href}.md`);
    expect(md.headers()['content-disposition']).toContain('.md');
    expect(await md.text()).toBe('# Heading\n\nfor *all*');
    await g.context.close();
    await leave(ann);
  });

  test('the preview renders as it is typed', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/wiki/new');
    await ann.page.locator('#wiki-md').pressSequentially('some **bold**');
    await expect(ann.page.locator('#wiki-preview strong')).toHaveText('bold');
    await leave(ann);
  });

  test('saving over a newer revision answers with the diff, and a second save is deliberate', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const href = await write(ann.page, uid('Shared '), 'one\ntwo\nthree');
    await ann.page.goto(`${href}/edit`);
    await bob.page.goto(`${href}/edit`);
    await bob.page.locator('#wiki-md').fill('one\nbob\nthree');
    await bob.page.getByRole('button', { name: 'Save' }).click();
    await bob.page.waitForURL(`**${href}`);

    await ann.page.locator('#wiki-md').fill('one\nann\nthree');
    await ann.page.getByRole('button', { name: 'Save' }).click();
    await expect(ann.page.locator('#wiki-conflict')).toContainText(bob.name);
    await expect(ann.page.locator('#wiki-conflict del')).toContainText('bob');
    await expect(ann.page.locator('#wiki-conflict ins')).toContainText('ann');
    await expect(ann.page.locator('#wiki-md')).toHaveValue('one\nann\nthree');
    expect(ann.page.url()).toContain('/edit');
    await ann.page.getByRole('button', { name: 'Save' }).click();
    await ann.page.waitForURL(`**${href}`);
    await expect(ann.page.locator('.wiki-body')).toContainText('ann');

    await ann.page.goto(`${href}/history`);
    await ann.page.getByRole('link', { name: 'Revision 2' }).click();
    await expect(ann.page.locator('.wiki-diff del')).toContainText('bob');
    await leave(ann, bob);
  });

  test("the Manual can't be edited", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/wiki/philosophy');
    await expect(ann.page.getByRole('link', { name: 'Edit' })).toHaveCount(0);
    expect((await ann.page.request.get('/wiki/philosophy/edit')).status()).toBe(404);
    const res = await ann.page.request.post('/wiki/philosophy', { form: { title: 'Mine now', md: 'gone', rev: '1' } });
    expect(res.status()).toBe(409);
    await ann.page.goto('/wiki/philosophy');
    await expect(ann.page.locator('.wiki-body')).not.toContainText('gone');
    await leave(ann);
  });

  test('a title is refused with a reason, what was typed staying', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/wiki/new');
    await ann.page.locator('#wiki-title').fill('New');
    await ann.page.locator('#wiki-md').fill('kept');
    await ann.page.getByRole('button', { name: 'Save' }).click();
    await expect(ann.page.locator('#wiki-error')).toContainText('taken');
    await expect(ann.page.locator('#wiki-md')).toHaveValue('kept');
    await leave(ann);
  });

  test('new pages are limited per member, and an edit is not', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const href = await write(ann.page, uid('First '), 'one');
    const post = (title: string) => ann.page.request.post('/wiki', { form: { title, md: 'x', visibility: 'members' }, maxRedirects: 0 });
    for (let i = 0; i < 19; i++) expect((await post(uid('Page '))).status()).toBeLessThan(400);
    expect((await post(uid('Page '))).status()).toBe(429);
    await ann.page.goto(`${href}/edit`);
    await ann.page.locator('#wiki-md').fill('two');
    await ann.page.getByRole('button', { name: 'Save' }).click();
    await expect(ann.page.locator('.wiki-body')).toContainText('two');
    await leave(ann);
  });

  test('a guest can write nothing', async ({ browser, baseURL }) => {
    const g = await guest(browser, baseURL!);
    const res = await g.page.request.post('/wiki', { form: { title: 'x', md: 'y' }, maxRedirects: 0 });
    expect([401, 302, 303]).toContain(res.status());
    await g.context.close();
  });

  test("a page's text and its title stay text", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const errors: string[] = [];
    ann.page.on('dialog', (d) => { errors.push(d.message()); void d.dismiss(); });
    const title = `${uid('T ')} <img src=x data-xss onerror=window.__xss=1>`;
    const href = await write(ann.page, title, '<img src=x data-xss onerror=window.__xss=1>\n\n[x](javascript:window.__xss=1)\n\n<script>window.__xss=1</script>', 'public');
    await expect(ann.page.locator('main h1').first()).toContainText('<img');
    await expect(ann.page.locator('[data-xss]')).toHaveCount(0);
    await expect(ann.page.locator('.wiki-body a[href^="javascript"]')).toHaveCount(0);
    await ann.page.goto('/wiki');
    await expect(ann.page.locator('[data-xss]')).toHaveCount(0);
    await ann.page.goto(`${href}/edit`);
    await ann.page.locator('#wiki-md').press('End');
    await ann.page.locator('#wiki-md').pressSequentially(' ');
    await expect(ann.page.locator('#wiki-preview .wiki-body')).toBeVisible();
    await expect(ann.page.locator('[data-xss]')).toHaveCount(0);
    expect(await ann.page.evaluate(() => (window as any).__xss)).toBeUndefined();
    expect(errors).toEqual([]);
    await leave(ann);
  });
});
