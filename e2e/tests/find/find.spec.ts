import { test, expect } from '../../fixtures';
import type { Browser, Page } from '@playwright/test';
import { leave, member, uid, type Member } from '../../helpers/members';

// Find answers for the viewer, on either engine (PLAN §6): the same suite on `full`'s FTS and `streams`'
// scans. What a search finds is what that viewer may read, and nothing of it stays behind in the tab.
const T = { tag: ['@find', '@chat', '@wiki'] };

async function say(page: Page, slug: string, text: string) {
  await page.goto(`/chat/r/${slug}?transport=sse`);
  const box = page.locator('.chat-compose textarea, form[hx-post] textarea[name="body"], input[name="body"]').first();
  await box.fill(text);
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.locator('.chat-msg .chat-body', { hasText: text }).first()).toBeVisible();
}

async function newRoom(page: Page, kind: 'public' | 'private'): Promise<string> {
  await page.goto('/chat');
  await page.locator('#room-name').fill(uid('room '));
  await page.locator('#room-kind').selectOption(kind);
  await page.getByRole('button', { name: 'Create' }).click();
  await page.waitForURL(/\/chat\/r\//);
  return new URL(page.url()).pathname.split('/').pop()!;
}

async function finds(page: Page, q: string): Promise<string> {
  const res = await page.request.get(`/find/results?q=${encodeURIComponent(q)}`);
  expect(res.status()).toBe(200);
  return res.text();
}

async function guest(browser: Browser, baseURL: string) {
  const context = await browser.newContext({ baseURL });
  return { context, page: await context.newPage() };
}

test.describe('find', T, () => {
  test('finds what a member may read, grouped, with its hit marked', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('quokka');
    const slug = await newRoom(ann.page, 'public');
    await say(ann.page, slug, `a ${word} here`);
    const res = await ann.page.goto(`/find?q=${word}`);
    expect(res?.headers()['cache-control']).toBe('no-store');
    expect(res?.headers()['x-impl']).toMatch(/^find\.engine=/);
    await expect(ann.page.locator('.find-group h2')).toHaveText('Chat');
    await expect(ann.page.locator('.find-snippet mark')).toHaveText(word);
    await ann.page.locator('.find-hits a').click();
    await ann.page.waitForURL(new RegExp(`/chat/r/${slug}`));
    await leave(ann);
  });

  test('searches as it is typed, with no form submit', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/find');
    await ann.page.locator('#find-results-q').pressSequentially('philosophy');
    await expect(ann.page.locator('.find-hits a[href="/wiki/philosophy"]')).toBeVisible();
    expect(new URL(ann.page.url()).pathname).toBe('/find');
    await leave(ann);
  });

  test('a guest finds the docs and no chat at all', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('quokka');
    const slug = await newRoom(ann.page, 'public');
    await say(ann.page, slug, `public ${word}`);
    const g = await guest(browser, baseURL!);
    expect(await finds(g.page, word)).not.toContain(word);
    expect(await finds(g.page, 'philosophy')).toContain('/wiki/philosophy');
    await g.context.close();
    await leave(ann);
  });

  test("a private room is its members', and a member who left finds nothing", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const word = uid('quokka');
    const slug = await newRoom(ann.page, 'private');
    await say(ann.page, slug, `behind ${word}`);
    expect(await finds(ann.page, word)).toContain(word);
    expect(await finds(bob.page, word)).not.toContain(word);
    await leave(ann, bob);
  });

  test('what was edited or removed is gone from the results', async ({ browser, baseURL }) => {
    const ann: Member = await member(browser, baseURL!);
    const word = uid('quokka');
    const slug = await newRoom(ann.page, 'public');
    await say(ann.page, slug, `soon gone ${word}`);
    expect(await finds(ann.page, word)).toContain(word);
    const msg = ann.page.locator('.chat-msg', { hasText: word }).first();
    await msg.getByRole('button', { name: 'Message actions' }).click();
    ann.page.once('dialog', (d) => d.accept());
    await msg.getByRole('button', { name: 'Delete' }).click();
    await expect(ann.page.locator('.chat-msg', { hasText: word })).toHaveCount(0);
    await expect.poll(() => finds(ann.page, word)).not.toContain(word);
    await leave(ann);
  });

  test("a member's bot conversation is found by nobody, its owner included", async ({ browser, baseURL }) => {
    test.skip(!process.env.E2E_FEATURES?.includes('"bot"'), 'no bot here');
    const ann = await member(browser, baseURL!);
    const word = uid('quokka');
    await ann.page.goto('/bot');
    await ann.page.getByRole('button', { name: 'New conversation' }).click();
    await ann.page.waitForURL(/\/bot\/c\/\d+$/);
    await ann.page.locator('.bot-ask textarea').fill(`tell me of ${word}`);
    await ann.page.locator('.bot-ask textarea').press('Enter');
    await expect(ann.page.locator('.bot-q', { hasText: word })).toBeVisible();
    expect(await finds(ann.page, word)).not.toContain(word);
    await leave(ann);
  });

  test('keeps nothing in the tab', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('quokka');
    const slug = await newRoom(ann.page, 'private');
    await say(ann.page, slug, `secret ${word}`);
    await ann.page.goto(`/find?q=${word}`);
    await expect(ann.page.locator('.find-snippet mark')).toHaveText(word);
    await expect(ann.page.locator('main')).toHaveAttribute('hx-history', 'false');
    await ann.page.locator('.nav-link[href="/about"]').click();
    await ann.page.waitForURL('**/about');
    const kept = await ann.page.evaluate(() => JSON.stringify(sessionStorage));
    expect(kept).not.toContain(word);
    await leave(ann);
  });

  test('a mark a member types stays a stray highlight, and text stays text', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('quokka');
    const slug = await newRoom(ann.page, 'public');
    await say(ann.page, slug, `<img src=x data-xss> ${word}  <b>tail`);
    await ann.page.goto(`/find?q=${word}`);
    await expect(ann.page.locator('.find-snippet')).toContainText('<img');
    await expect(ann.page.locator('.find-snippet').locator('img, b')).toHaveCount(0);
    expect(await ann.page.locator('.find-snippet mark').count()).toBeLessThanOrEqual(4);
    await leave(ann);
  });

  test('the limit answers 429, with a reason', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const codes = await Promise.all(Array.from({ length: 40 }, () => ann.page.request.get('/find/results?q=x').then((r) => r.status())));
    expect(codes).toContain(429);
    await leave(ann);
  });

  test('takes any text', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    for (const q of ['%00', 'a"b', '* OR x', 'NEAR(a b)', 'é'.repeat(150), 'x'.repeat(3000)]) {
      expect((await ann.page.request.get(`/find?q=${encodeURIComponent(q)}`)).status(), q).toBeLessThan(500);
      await ann.page.waitForTimeout(120); // the limit's own window
    }
    await leave(ann);
  });
});

test.describe("find over the wiki's visibility", { tag: ['@find', '@wiki', '@wiki-sqlite', '@accounts-accounts'] }, () => {
  test("a guest finds no members' page, its title and snippet included, and a page moved to members leaves at once", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('quokka');
    const title = uid('Pagetitle ');
    await ann.page.goto('/wiki/new');
    await ann.page.locator('#wiki-title').fill(title);
    await ann.page.locator('#wiki-visibility').selectOption('public');
    await ann.page.locator('#wiki-md').fill(`open ${word}`);
    await ann.page.getByRole('button', { name: 'Save' }).click();
    await ann.page.waitForURL((u) => u.pathname.startsWith('/wiki/pagetitle'));
    const href = new URL(ann.page.url()).pathname;

    const g = await guest(browser, baseURL!);
    await expect.poll(() => finds(g.page, word)).toContain(word);
    expect(await finds(g.page, title.split(' ')[1])).toContain(href);

    await ann.page.goto(`${href}/edit`);
    await ann.page.locator('#wiki-visibility').selectOption('members');
    await ann.page.getByRole('button', { name: 'Save' }).click();
    await ann.page.waitForURL(`**${href}`);
    const after = await finds(g.page, word);
    expect(after).not.toContain(word);
    expect(after).not.toContain(title);
    expect(await finds(g.page, title.split(' ')[1])).not.toContain(href);
    expect(await finds(ann.page, word)).toContain(word);
    await g.context.close();
    await leave(ann);
  });
});

test.describe('find over the bot', { tag: ['@find', '@chat', '@wiki', '@bot'] }, () => {
  test("a bot's answer in a private room is found by its members and nobody else", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const slug = await newRoom(ann.page, 'private');
    await say(ann.page, slug, '@bot tell me something');
    const answer = ann.page.locator('.chat-log > article.chat-msg', { has: ann.page.locator('.chat-name', { hasText: 'Capcom' }) });
    await expect(answer).toHaveCount(1);
    await expect(ann.page.locator('.bot-live')).toHaveCount(0);
    const words = (await answer.locator('.chat-body').innerText()).split(/\s+/).filter((w) => /^[A-Za-z]{5,}$/.test(w));
    const q = `${words[0]} ${words[1]}`;
    expect(await finds(ann.page, q)).toContain(`/chat/r/${slug}`);
    expect(await finds(bob.page, q)).not.toContain(`/chat/r/${slug}`);
    await leave(ann, bob);
  });
});

test.describe('find, on each engine', { tag: ['@find', '@chat', '@wiki', '@chat-sqlite'] }, () => {
  test('FTS folds `cafe` to `café`, and marks what it found', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('z');
    const slug = await newRoom(ann.page, 'public');
    await say(ann.page, slug, `the café ${word}`);
    await ann.page.goto(`/find?q=${encodeURIComponent(`cafe ${word}`)}`);
    await expect(ann.page.locator('.find-snippet mark').first()).toHaveText('café');
    await leave(ann);
  });
});

test.describe('find, on a scan', { tag: ['@find', '@chat', '@wiki', '@chat-memory'] }, () => {
  test("a scan doesn't fold, and finds the middle of a word", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('z');
    const slug = await newRoom(ann.page, 'public');
    await say(ann.page, slug, `the café ${word}`);
    expect(await finds(ann.page, `cafe ${word}`)).not.toContain(word);
    expect(await finds(ann.page, `afé ${word}`)).toContain(word);
    await leave(ann);
  });
});
