import { test, expect } from '../../fixtures';
import { signIn } from '../../helpers/accounts';

// /admin/ops in Houston (PLAN §15.4, M5): the same panel as streams', behind the accounts identity's
// Admin_Ops, with the SQLite store's own numbers (sqlite3_db_status, pushed through obs) as a card.
// The perms over every role and host are rbac.spec's; panel.spec covers the nick identity's admin.
const T = { tag: ['@ops', '@accounts-accounts'] };

const since = async (page: import('@playwright/test').Page) =>
  Number((await page.locator('#ops-http .muted').innerText()).match(/(\d+) since boot/)![1]);

test.describe('ops in Houston', T, () => {
  for (const mode of ['sse', 'poll', 'multipart'] as const) {
    test(`an admin's panel refreshes every second by ${mode}, the store's card among them`, async ({ browser, baseURL }) => {
      const admin = await signIn(browser, baseURL!, '/admin/ops');
      try {
        await admin.page.goto(`/admin/ops?mode=${mode}`);
        await expect(admin.page.locator('#ops-store')).toContainText('page cache');
        await expect(admin.page.locator('#ops-store')).toContainText('statements');
        await expect(admin.page.locator('#ops-drops')).toHaveText('0 audit entries dropped'); // M4-04
        const first = await since(admin.page);
        await expect.poll(async () => {
          await admin.page.request.get('/livez');
          return since(admin.page);
        }, { timeout: 10_000 }).toBeGreaterThan(first);
      } finally {
        await admin.context.close();
      }
    });
  }

  test('a guest is sent to sign in', async ({ page }) => {
    await page.goto('/admin/ops');
    await expect(page).toHaveURL(/\/login/);
    await expect(page.locator('#username')).toBeVisible();
  });
});
