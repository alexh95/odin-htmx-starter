import { test, expect } from '../../fixtures';
import type { APIRequestContext, Page } from '@playwright/test';

// The global active-search lives in the top bar (aria-label "Search contacts")
// and swaps a results panel into #search-results. Its HTMX trigger is keyup, so
// we type with pressSequentially (fill() wouldn't emit key events).
const box = '#search-results';
const searchbox = (page: Page) => page.getByRole('searchbox', { name: 'Search contacts' });

test.describe('active search', { tag: '@contacts' }, () => {
  test('typing shows highlighted matches', async ({ page }) => {
    await page.goto('/');
    await searchbox(page).pressSequentially('grace');
    await expect(page.locator(`${box} .search-panel`)).toBeVisible();
    await expect(page.locator(`${box} mark`).first()).toBeVisible();
    await expect(page.locator(`${box} .search-list li`).first()).toContainText('Grace', {
      ignoreCase: true,
    });
  });

  test('clicking a result lands on /data with the query', async ({ page }) => {
    await page.goto('/');
    await searchbox(page).pressSequentially('grace');
    await page.locator(`${box} .search-list li a`).first().click();
    await expect(page).toHaveURL(/\/data\?q=/);
  });

  test('clearing the query collapses the dropdown', async ({ page }) => {
    const input = searchbox(page);
    await page.goto('/');
    await input.pressSequentially('grace');
    await expect(page.locator(`${box} .search-panel`)).toBeVisible();
    await input.press('ControlOrMeta+A');
    await input.press('Backspace');
    await expect(page.locator(`${box} .search-panel`)).toHaveCount(0);
  });

  test('Escape dismisses the dropdown', async ({ page }) => {
    await page.goto('/');
    await searchbox(page).pressSequentially('grace');
    await expect(page.locator(`${box} .search-panel`)).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator(`${box} .search-panel`)).toHaveCount(0);
  });

  test('outside click dismisses the dropdown', async ({ page }) => {
    await page.goto('/');
    await searchbox(page).pressSequentially('grace');
    await expect(page.locator(`${box} .search-panel`)).toBeVisible();
    // Click well inside the page body (away from the sticky header / search).
    // Matched by level so the target survives a rewording of the page copy.
    await page.getByRole('heading', { level: 1 }).click();
    await expect(page.locator(`${box} .search-panel`)).toHaveCount(0);
  });
});

// Marks are measured in the original text. Lowering can change a string's byte
// length (İ → i, ẞ → ß, an invalid byte → U+FFFD), so an offset taken from a
// lowered copy marked the wrong characters.
test.describe('search highlighting', { tag: '@contacts' }, () => {
  const results = async (request: APIRequestContext, q: string) => {
    const res = await request.get(`/search?q=${encodeURIComponent(q)}`);
    expect(res.status()).toBe(200);
    return res.text();
  };

  test('a query that shrinks when lowered marks the original span', async ({ request }) => {
    // Its own row: the seed's Turing can be the first row, which crud.spec renames and deletes on the
    // same worker's server (a flake with four workers, run 41251995318). Lower case sorts after the seed.
    const res = await request.post('/contacts', {
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      data: 'name=zz%20Turing&email=zz-turing@example.dev&role=0&status=1',
    });
    expect(res.status()).toBe(200);
    expect(await results(request, 'Turİng')).toContain('<mark>Turing</mark>');
    const dotted = await results(request, 'İ');
    expect(dotted).toContain('Tur<mark>i</mark>ng');
    expect(dotted).not.toContain('<mark>in</mark>');
  });

  test('stored text that changes length when lowered keeps its marks aligned', async ({ request }) => {
    // Lower-case names sort after the seed, so other specs' first rows stay put.
    const add = async (name: string) => {
      const res = await request.post('/contacts', {
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        data: `name=${name}&email=zz@example.dev&role=0&status=1`,
      });
      expect(res.status()).toBe(200);
    };
    await add('zz%20Stra%E1%BA%9Ee'); // ẞ is 3 bytes, its lowercase ß is 2
    await add('zz%FFhl'); // an invalid byte lowers to the 3-byte U+FFFD
    expect(await results(request, 'straße')).toContain('<mark>Straẞe</mark>');
    expect(await results(request, 'hl')).toContain('zz\uFFFD<mark>hl</mark>');
  });
});
