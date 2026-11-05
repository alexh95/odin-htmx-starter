import { test, expect } from '../../fixtures';
import type { Browser, Page } from '@playwright/test';
import { leave, member, uid, type Member } from '../../helpers/members';

// Checklists (PLAN §6): shared by every member, live, one fact for done, and a board of the same items whose
// moves work with a mouse and with buttons alike.
const T = { tag: ['@lists', '@accounts-accounts', '@notify'] };

async function newList(page: Page, template = 'plain'): Promise<string> {
  await page.goto('/lists');
  await page.locator('#list-title').fill(uid('List '));
  await page.locator('#list-template').selectOption(template);
  await page.getByRole('button', { name: 'Create' }).click();
  await page.waitForURL(/\/lists\/\d+$/);
  return new URL(page.url()).pathname;
}

async function addItem(page: Page, text: string) {
  await page.locator('#list-item').fill(text);
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await expect(page.locator('.list-item', { hasText: text })).toBeVisible();
}

const item = (m: Member | { page: Page }, text: string) => m.page.locator('.list-item', { hasText: text });
const column = (page: Page, name: string) => page.locator('.list-column', { has: page.locator('h2', { hasText: name }) });

async function guest(browser: Browser, baseURL: string) {
  const context = await browser.newContext({ baseURL });
  return { context, page: await context.newPage() };
}

test.describe('checklists', T, () => {
  test('an item reaches another member live, and a reload keeps it', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const href = await newList(ann.page);
    await bob.page.goto(href);
    await expect(bob.page.locator('.list-column').first()).toBeVisible();
    await addItem(ann.page, 'bread');
    await expect(item(bob, 'bread')).toBeVisible();
    await ann.page.reload();
    await expect(item(ann, 'bread')).toBeVisible();
    await leave(ann, bob);
  });

  test('done is being in the closing column, both ways', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const href = await newList(ann.page);
    await addItem(ann.page, 'tent');
    await bob.page.goto(href);
    await item(ann, 'tent').getByRole('button', { name: 'Done' }).click();
    await expect(column(ann.page, 'Done').locator('.list-item', { hasText: 'tent' })).toBeVisible();
    await expect(column(bob.page, 'Done').locator('.list-item', { hasText: 'tent' })).toBeVisible();
    await expect(column(bob.page, 'To do').locator('.list-item')).toHaveCount(0);
    await item(ann, 'tent').getByRole('button', { name: 'Reopen' }).click();
    await expect(column(ann.page, 'To do').locator('.list-item', { hasText: 'tent' })).toBeVisible();
    await leave(ann, bob);
  });

  test('a template brings its columns and items', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await newList(ann.page, 'groceries');
    await expect(ann.page.locator('.list-column h2')).toHaveText(['To buy', 'Bought']);
    await expect(item(ann, 'Milk')).toBeVisible();
    await leave(ann);
  });

  test('order moves by button, and an item goes away', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await newList(ann.page);
    await addItem(ann.page, 'first');
    await addItem(ann.page, 'second');
    await item(ann, 'second').getByRole('button', { name: 'Up' }).click();
    await expect(ann.page.locator('.list-text')).toHaveText(['second', 'first']);
    await item(ann, 'second').getByRole('button', { name: 'Right' }).click();
    await expect(column(ann.page, 'Doing').locator('.list-item', { hasText: 'second' })).toBeVisible();
    await item(ann, 'first').getByRole('button', { name: 'Delete' }).click();
    await expect(item(ann, 'first')).toHaveCount(0);
    await leave(ann);
  });

  test("whoever is given an item hears of it", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const href = await newList(ann.page);
    await addItem(ann.page, 'firewood');
    await bob.page.goto(href);
    await addItem(bob.page, 'matches');
    await ann.page.reload();
    await item(ann, 'firewood').locator('select[name="who"]').selectOption({ label: bob.name });
    await expect(item(ann, 'firewood').locator('.tag')).toHaveText(bob.name);
    await bob.page.goto('/notify');
    await expect(bob.page.locator('main')).toContainText('firewood');
    await leave(ann, bob);
  });

  test('find reaches an item, and a removed one leaves; a guest finds none', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('quokka');
    await newList(ann.page);
    await addItem(ann.page, word);
    await expect.poll(async () => (await ann.page.request.get(`/find/results?q=${word}`)).text()).toContain('#li-');
    const g = await guest(browser, baseURL!);
    expect(await (await g.page.request.get(`/find/results?q=${word}`)).text()).not.toContain(word);
    await g.context.close();
    await item(ann, word).getByRole('button', { name: 'Delete' }).click();
    await expect(item(ann, word)).toHaveCount(0);
    await expect.poll(async () => (await ann.page.request.get(`/find/results?q=${word}`)).text()).not.toContain('#li-');
    await leave(ann);
  });

  test('a guest has none of it', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const href = await newList(ann.page);
    const g = await guest(browser, baseURL!);
    const page = await g.page.request.get(href, { maxRedirects: 0 });
    expect([302, 303, 401]).toContain(page.status());
    expect((await g.page.request.post(`${href}/items`, { form: { text: 'x' }, maxRedirects: 0 })).status()).not.toBe(200);
    const events = await g.page.request.get(`/events?t=lists.list:${href.split('/').pop()}`, { maxRedirects: 0 });
    expect(events.status()).toBeGreaterThanOrEqual(300);
    await g.context.close();
    await leave(ann);
  });

  test('text stays text, and a blank or long item is refused', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const href = await newList(ann.page);
    await addItem(ann.page, '<img src=x data-xss onerror=window.__xss=1>');
    await expect(ann.page.locator('[data-xss]')).toHaveCount(0);
    await ann.page.reload();
    await expect(ann.page.locator('[data-xss]')).toHaveCount(0);
    expect((await ann.page.request.post(`${href}/items`, { form: { text: '   ' } })).status()).toBe(422);
    expect((await ann.page.request.post(`${href}/items`, { form: { text: 'x'.repeat(201) } })).status()).toBe(422);
    await ann.page.goto('/lists');
    expect(await ann.page.evaluate(() => (window as any).__xss)).toBeUndefined();
    await leave(ann);
  });
});

test.describe('the board', { tag: ['@lists', '@lists-hyperscript', '@accounts-accounts', '@notify'] }, () => {
  test('a mouse drags a card between columns, and another member sees it', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const href = await newList(ann.page);
    await addItem(ann.page, 'one');
    await addItem(ann.page, 'two');
    await bob.page.goto(`${href}?view=board`);
    await ann.page.goto(`${href}?view=board`);
    await expect(ann.page.locator('.list-column').first()).toHaveAttribute('data-hyperscript-powered', 'true');

    const card = await item(ann, 'two').boundingBox();
    const into = await column(ann.page, 'Doing').boundingBox();
    await ann.page.mouse.move(card!.x + 12, card!.y + 12);
    await ann.page.mouse.down();
    await ann.page.mouse.move(card!.x + 40, card!.y + 20, { steps: 4 });
    await ann.page.mouse.move(into!.x + into!.width / 2, into!.y + into!.height / 2, { steps: 8 });
    await ann.page.mouse.up();
    await expect(column(ann.page, 'Doing').locator('.list-item', { hasText: 'two' })).toBeVisible();
    await expect(column(bob.page, 'Doing').locator('.list-item', { hasText: 'two' })).toBeVisible();
    await ann.page.reload();
    await expect(column(ann.page, 'Doing').locator('.list-item', { hasText: 'two' })).toBeVisible();
    await leave(ann, bob);
  });

  test('a card dropped on another lands above it', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const href = await newList(ann.page);
    await addItem(ann.page, 'one');
    await addItem(ann.page, 'two');
    await addItem(ann.page, 'three');
    await ann.page.goto(`${href}?view=board`);
    await expect(ann.page.locator('.list-column').first()).toHaveAttribute('data-hyperscript-powered', 'true');
    const from = await item(ann, 'three').boundingBox();
    const to = await item(ann, 'one').boundingBox();
    await ann.page.mouse.move(from!.x + 12, from!.y + 12);
    await ann.page.mouse.down();
    await ann.page.mouse.move(from!.x + 30, from!.y + 2, { steps: 4 });
    await ann.page.mouse.move(to!.x + 12, to!.y + 6, { steps: 8 });
    await ann.page.mouse.up();
    await expect(column(ann.page, 'To do').locator('.list-text')).toHaveText(['three', 'one', 'two']);
    await leave(ann);
  });
});

test.describe('the board, with no behaviours', { tag: ['@lists', '@lists-vanilla', '@accounts-accounts', '@notify'] }, () => {
  test('the buttons do what dragging does', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const href = await newList(ann.page);
    await addItem(ann.page, 'one');
    await ann.page.goto(`${href}?view=board`);
    await item(ann, 'one').getByRole('button', { name: 'Right' }).click();
    await expect(column(ann.page, 'Doing').locator('.list-item', { hasText: 'one' })).toBeVisible();
    await leave(ann);
  });
});
