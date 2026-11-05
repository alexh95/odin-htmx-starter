import { test, expect } from '../../fixtures';

// The wiki's read side, on whichever store the build has. On memory that's `source_files`: the
// starter's docs, read-only, with their links turned into pages.
test.describe('wiki', { tag: '@wiki' }, () => {
  test('the index names the store and lists the Manual', async ({ page }) => {
    const res = await page.goto('/wiki');
    expect(res?.status()).toBe(200);
    expect(res?.headers()['x-impl']).toMatch(/^wiki\.store=/);
    await expect(page.locator('.wiki-pages a[href="/wiki/philosophy"]')).toBeVisible();
    await expect(page.locator('.nav-link[aria-current="page"]')).toHaveAttribute('href', '/wiki');
  });

  test('a page is rendered, inert, and its links stay on the site or go to the repo', async ({ page }) => {
    await page.goto('/wiki/guide');
    const body = page.locator('.wiki-body');
    await expect(body).toHaveAttribute('hx-ignore', '');
    await expect(body).toHaveAttribute('data-disable-scripting', '');
    await expect(page.locator('main h1').first()).toBeVisible();
    await expect(body.locator('a[href^="/wiki/"]').first()).toBeVisible();
    const hrefs = await body.locator('a').evaluateAll((all) => all.map((a) => a.getAttribute('href')!));
    for (const h of hrefs) expect(h).toMatch(/^(#|\/|https?:|mailto:)/);
  });

  test('every internal link in the Manual lands', async ({ page }) => {
    await page.goto('/wiki');
    const slugs = await page.locator('.wiki-pages a').evaluateAll((all) => all.map((a) => a.getAttribute('href')!));
    expect(slugs.length).toBeGreaterThanOrEqual(11);
    const seen = new Set<string>();
    for (const s of slugs) {
      await page.goto(s);
      const links = await page.locator('.wiki-body a[href^="/wiki/"]').evaluateAll((all) => all.map((a) => a.getAttribute('href')!));
      for (const l of links) seen.add(l.split('#')[0]);
    }
    for (const l of seen) expect((await page.request.get(l)).status(), l).toBe(200);
  });

  test('an unknown page is the site\'s 404', async ({ page }) => {
    expect((await page.goto('/wiki/no-such-page'))?.status()).toBe(404);
  });
});
