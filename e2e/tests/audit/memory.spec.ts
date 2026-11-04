import { test, expect } from '../../fixtures';
import { startServer, stopServer } from '../../helpers/server';
import { member } from '../../helpers/members';

// The audit log on a memory build (streams, for chat's moderation): its store keeps no rows, each
// entry is a log line (PLAN §11.4), so the page, its next page and the export answer, empty. A
// server of its own, whose loopback nicknames are admins.
test("a memory build's audit log answers, with no rows to list", { tag: ['@audit', '@audit-memory', '@accounts-nick'] }, async ({ browser }) => {
  const s = await startServer(test.info().config, { ACCOUNTS_NICK_ADMIN_CIDRS: '127.0.0.1/32' });
  try {
    const admin = await member(browser, `http://127.0.0.1:${s.port}`);
    await admin.page.goto('/admin/audit');
    await expect(admin.page.locator('main')).toContainText('This build keeps no audit table');
    expect((await admin.page.request.get('/admin/audit/rows?before=0')).status()).toBe(200);
    const csv = await admin.page.request.get('/admin/audit/export');
    expect(csv.status()).toBe(200);
    expect(csv.headers()['content-disposition']).toMatch(/^attachment/);
    await admin.context.close();
  } finally {
    await stopServer(s);
  }
});
