import { test, expect } from '../../fixtures';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer, stopServer, mainOrigin } from '../../helpers/server';
import { signIn } from '../../helpers/accounts';
import type { Page } from '@playwright/test';

// /admin/jobs (PLAN §15.4, M5): every mounted job, Run now with a reason (audited), the run's row
// upserted live as it goes, its log as a download, and the runs kept past a restart. Perms over
// every role and host are rbac.spec's; a cancelled run is held by the backup drill's job (slice 6)
// and workers' own unit test.
const T = { tag: ['@jobs', '@accounts-accounts'] };

// Every hx-prompt on the page is answered with `reason`.
function answering(page: Page, reason: string) {
  page.on('dialog', (d) => d.accept(reason));
}

const job = (page: Page, id: string) => page.locator('tr.job').filter({ has: page.locator('code', { hasText: new RegExp(`^${id.replace('.', '\.')}$`) }) });

test.describe('jobs', T, () => {
  // A backup dir under a file can't be made, whatever the OS: the run fails, and the admin hears.
  test("a failed run lands in the admins' Inbox", { tag: '@notify' }, async ({ browser }) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'odin-jobs-'));
    const file = path.join(dir, 'a-file');
    fs.writeFileSync(file, '');
    const s = await startServer(test.info().config, { DB_PATH: path.join(dir, 'data.db'), BACKUP_DIR: path.join(file, 'backups') });
    try {
      const admin = await signIn(browser, mainOrigin(s.port), '/admin/jobs');
      answering(admin.page, 'a backup that cannot work');
      await job(admin.page, 'store.backup').getByRole('button', { name: 'Run now' }).click();
      await expect(admin.page.locator('#jobs-runs tr.run').filter({ hasText: 'store.backup' }).first().locator('.run-state')).toHaveText('failed', { timeout: 10_000 });
      await expect.poll(async () => (await admin.page.request.get('/notify/list')).text()).toContain('store.backup');
      await admin.page.goto('/notify');
      const item = admin.page.locator('#notify-list article.notify-item').first();
      await expect(item).toContainText('The job store.backup failed.');
      await expect(item.locator('a')).toHaveAttribute('href', '/admin/jobs');
      await admin.context.close();
    } finally {
      await stopServer(s);
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('an admin runs a job by hand: its row arrives live, its log downloads, the reason is audited', async ({ browser, baseURL }) => {
    const admin = await signIn(browser, baseURL!, '/admin/jobs');
    try {
      answering(admin.page, 'checking the panel by hand');
      await expect(job(admin.page, 'ops.sample')).toBeVisible();
      await expect(job(admin.page, 'jobs.sync')).toContainText('1 s');
      const before = await admin.page.locator('#jobs-runs tr.run').count();
      await job(admin.page, 'ops.sample').getByRole('button', { name: 'Run now' }).click();
      await expect(admin.page.locator('.toast')).toContainText('Queued');
      const row = admin.page.locator('#jobs-runs tr.run').first();
      await expect(admin.page.locator('#jobs-runs tr.run')).toHaveCount(before + 1, { timeout: 5000 });
      await expect(row).toContainText('ops.sample');
      await expect(row).toContainText('by hand');
      await expect(row.locator('.run-state')).toHaveText('done', { timeout: 5000 });

      const [download] = await Promise.all([admin.page.waitForEvent('download'), row.getByRole('link', { name: 'Log' }).click()]);
      const text = fs.readFileSync((await download.path())!, 'utf8');
      expect(text).toMatch(/^ops\.sample, run \d+-\d+: done\nqueued /);

      await admin.page.goto('/admin/audit?action=jobs.');
      await expect(admin.page.locator('.audit-row').first()).toContainText('jobs.run_now');
      await expect(admin.page.locator('.audit-row').first()).toContainText('checking the panel by hand');
    } finally {
      await admin.context.close();
    }
  });

  test('a run needs a reason and a job that exists; an ended run can\'t be stopped', async ({ browser, baseURL }) => {
    const admin = await signIn(browser, baseURL!, '/admin/jobs');
    try {
      const h = { 'HX-Request': 'true' };
      expect((await admin.page.request.post('/admin/jobs/run', { form: { job: 'ops.sample' }, headers: h })).status()).toBe(422);
      expect((await admin.page.request.post('/admin/jobs/run', { form: { job: 'no.such' }, headers: { ...h, 'HX-Prompt': 'x' } })).status()).toBe(422);
      expect((await admin.page.request.post('/admin/jobs/cancel', { form: { run: 'nope' }, headers: { ...h, 'HX-Prompt': 'x' } })).status()).toBe(404);
      expect((await admin.page.request.post('/admin/jobs/cancel', { form: { run: '1-999999' }, headers: { ...h, 'HX-Prompt': 'x' } })).status()).toBe(409);
      expect((await admin.page.request.get('/admin/jobs/runs/1/999999/log')).status()).toBe(404);
    } finally {
      await admin.context.close();
    }
  });

  test('the runs outlive the process', { tag: '@status' }, async ({ browser }) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'jobs-'));
    const env = { DB_PATH: path.join(dir, 'data.db') };
    let s = await startServer(test.info().config, env);
    try {
      const admin = await signIn(browser, mainOrigin(s.port), '/admin/jobs');
      answering(admin.page, 'before a restart');
      await job(admin.page, 'ops.sample').getByRole('button', { name: 'Run now' }).click();
      await expect(admin.page.locator('#jobs-runs tr.run .run-state').first()).toHaveText('done', { timeout: 5000 });
      // The nightly backup, by hand: its progress in three steps, and its age on /status.
      await job(admin.page, 'store.backup').getByRole('button', { name: 'Run now' }).click();
      const backup = admin.page.locator('#jobs-runs tr.run').filter({ hasText: 'store.backup' }).first();
      await expect(backup.locator('.run-state')).toHaveText('done', { timeout: 10_000 });
      await expect(backup.locator('.run-progress')).toContainText('3 of 3');
      // A run by hand is said beside the nightly, never counted: with no nightly yet, still degraded.
      await admin.page.goto('/status');
      await expect(admin.page.locator('#st-backups .status-state')).toHaveText('degraded');
      await expect(admin.page.locator('#st-backups')).toContainText(/no nightly yet; by hand or before a deploy, \d+ s ago/);
      await admin.page.waitForTimeout(1500); // the sync's next second has the ended rows in the file
      await admin.context.close();
      await stopServer(s);
      s = await startServer(test.info().config, env);
      const again = await signIn(browser, mainOrigin(s.port), '/admin/jobs');
      const kept = again.page.locator('#jobs-runs tr.run');
      await expect(kept.filter({ hasText: 'ops.sample' }).locator('.run-state')).toHaveText('done');
      await expect(kept.filter({ hasText: 'store.backup' }).locator('.run-progress')).toContainText('3 of 3');
      await expect(kept.getByRole('button', { name: 'Cancel' })).toHaveCount(0);
      await again.context.close();
    } finally {
      await stopServer(s);
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
