import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { leave, member, uid } from '../../helpers/members';

// The Ctrl-K palette (PLAN §6, D22): hyperscript's alone; the vanilla client has the nav's plain link.
// Hyperscript installs behaviours after the load: a key pressed before it is the browser's.
async function open(page: Page) {
  await expect(page.locator('#palette')).toHaveAttribute('data-hyperscript-powered', 'true');
  await page.keyboard.press('Control+k');
  await expect(page.locator('#palette-q')).toBeFocused();
}

test.describe('the palette', { tag: ['@find', '@find-hyperscript', '@wiki'] }, () => {
  test('opens on Ctrl-K, searches, goes by keyboard, and gives focus back', async ({ page }) => {
    await page.goto('/about');
    await page.locator('.nav-link[href="/about"]').focus();
    await page.keyboard.press('Control+k');
    await expect(page.locator('#palette')).toBeVisible();
    await expect(page.locator('#palette-q')).toBeFocused();
    await page.keyboard.type('philosophy');
    await expect(page.locator('#palette-results a[href="/wiki/philosophy"]')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('#palette')).toBeHidden();
    await expect(page.locator('.nav-link[href="/about"]')).toBeFocused();
    await expect(page.locator('#palette-results')).toBeEmpty();
    await expect(page.locator('#palette-q')).toHaveValue('');

    await open(page);
    await page.keyboard.type('philosophy');
    await expect(page.locator('#palette-results a[href="/wiki/philosophy"]')).toBeVisible();
    await page.locator('#palette-results a[href="/wiki/philosophy"]').focus();
    await page.keyboard.press('Enter');
    await page.waitForURL('**/wiki/philosophy');
  });

  test('goes to a page the viewer can open, by its name', async ({ page }) => {
    await page.goto('/about');
    await open(page);
    await page.keyboard.type('stat');
    await expect(page.locator('#palette-results a[href="/status"]')).toBeVisible();
  });

  test('a click on the backdrop closes it', async ({ page }) => {
    await page.goto('/about');
    await open(page);
    await page.mouse.click(4, 4);
    await expect(page.locator('#palette')).toBeHidden();
  });

  test('survives a boost, and with no script it is a form', async ({ page }) => {
    await page.goto('/about');
    await page.locator('.nav-link[href="/status"]').click();
    await page.waitForURL('**/status');
    await expect(page.locator('.nav-link[aria-current="page"]')).toHaveAttribute('href', '/status'); // the URL leads the swap
    await open(page);
    await expect(page.locator('#palette form')).toHaveAttribute('action', '/find');
  });
});

test.describe('the palette and the history cache', { tag: ['@find', '@find-hyperscript', '@wiki'] }, () => {
  test("what a guest found leaves with the page, and Back brings the page back shut", async ({ page }) => {
    await page.goto('/wiki/philosophy');
    await open(page);

    await page.keyboard.type('brief');
    await expect(page.locator('#palette-results a[href="/wiki/brief"]')).toBeVisible();
    await page.locator('#palette-results a[href="/wiki/brief"]').click();
    await page.waitForURL('**/wiki/brief');
    const kept = await page.evaluate(() => JSON.stringify(sessionStorage));
    expect(kept).toContain('wiki-body');
    expect(kept).not.toContain('find-group');
    expect(kept).not.toContain('find-snippet');

    await page.goBack();
    await expect(page.locator('.wiki-body')).toBeVisible();
    await expect(page.locator('#palette')).toBeHidden();
    await expect(page.locator('#palette-results')).toBeEmpty();
    await page.keyboard.press('Control+k');
    await expect(page.locator('#palette')).toBeVisible();
  });
});

test.describe('the palette, for a member', { tag: ['@find', '@find-hyperscript', '@chat', '@wiki-sqlite', '@accounts-accounts'] }, () => {
  test('nothing it found is kept: a member has no snapshots', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const word = uid('quokka');
    await ann.page.goto('/chat');
    await ann.page.locator('#room-name').fill(uid('room '));
    await ann.page.locator('#room-kind').selectOption('private');
    await ann.page.getByRole('button', { name: 'Create' }).click();
    await ann.page.waitForURL(/\/chat\/r\//);
    await ann.page.locator('.chat-composer textarea').fill(`secret ${word}`);
    await ann.page.locator('.chat-composer textarea').press('Enter');
    await expect(ann.page.locator('.chat-msg .chat-body', { hasText: word }).first()).toBeVisible();

    await ann.page.goto('/wiki/philosophy');
    await open(ann.page);
    await ann.page.keyboard.type(word);
    await expect(ann.page.locator('#palette-results')).toContainText(word);
    await ann.page.evaluate(() => (document.querySelector('.nav-link[href="/about"]') as HTMLElement).click());
    await ann.page.waitForURL('**/about');
    expect(await ann.page.evaluate(() => JSON.stringify(sessionStorage))).not.toContain(word);
    await leave(ann);
  });
});

test.describe('find with no behaviours', { tag: ['@find', '@find-vanilla'] }, () => {
  test('Ctrl-K does nothing, and the nav goes to a plain form', async ({ page }) => {
    await page.goto('/about');
    await page.keyboard.press('Control+k');
    await expect(page.locator('#palette')).toBeHidden();
    await page.locator('.nav-link[href="/find"]').click();
    await page.waitForURL('**/find');
    await expect(page.locator('form.find-form')).toHaveAttribute('action', '/find');
  });
});
