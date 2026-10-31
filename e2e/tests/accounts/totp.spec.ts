import { test, expect } from '../../fixtures';
import { startServer, stopServer, type Server, mainOrigin } from '../../helpers/server';
import { ADMIN, signIn, totp } from '../../helpers/accounts';
import type { Page } from '@playwright/test';
import { mkdtempSync, readFileSync, existsSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

// Two-step sign-in (PLAN §17.1, Q11): enrolment by a code from the app, the code step after
// the password, recovery codes that each work once, step-up on `.Step_Up` rows, and an Admin
// who is one only with a second factor. Each runs on a server of its own: enrolment is state.
const T = { tag: ['@accounts-accounts'] };

async function own(env: NodeJS.ProcessEnv, run: (s: Server, base: string) => Promise<void>) {
  const s = await startServer(test.info().config, env);
  try {
    await run(s, mainOrigin(s.port));
  } finally {
    await stopServer(s);
  }
}

// Turns it on from /accounts/totp; the secret, and the recovery codes shown that once.
async function enrol(page: Page): Promise<{ secret: string; codes: string[] }> {
  await page.goto('/accounts/totp');
  const secret = (await page.locator('.totp-secret').textContent())!.trim();
  await expect(page.locator('.totp-uri')).toContainText(`otpauth://totp/`);
  await expect(page.locator('.totp-uri')).toContainText(`secret=${secret}`);
  await page.locator('#totp-code').fill(totp(secret));
  await page.getByRole('button', { name: 'Turn on' }).click();
  await expect(page.locator('.recovery-codes li')).toHaveCount(10);
  const codes = await page.locator('.recovery-codes code').allTextContents();
  return { secret, codes };
}

// The password, then the code form in its place.
async function password(page: Page) {
  await page.goto('/login');
  await page.locator('#username').fill(ADMIN.username);
  await page.locator('#password').fill(ADMIN.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.locator('#code')).toBeVisible();
}

test.describe('two-step sign-in', T, () => {
  test('turned on by a code, it asks for one after the password; a recovery code works once', async ({ browser }) => {
    await own({}, async (_, base) => {
      const one = await signIn(browser, base);
      const { secret, codes } = await enrol(one.page);
      expect(new Set(codes).size).toBe(10);
      for (const c of codes) expect(c).toMatch(/^[a-z0-9]{4}-[a-z0-9]{4}$/);
      await one.page.goto('/accounts/totp');
      await expect(one.page.locator('.totp-state')).toContainText('10 of 10 recovery codes left');
      // A second enrolment, even with a good code for its own secret, can't replace the factor in force:
      // whoever held the session could otherwise step up with theirs (M4-01).
      const other = 'JBSWY3DPEHPK3PXP';
      const replaced = await one.page.request.post('/accounts/totp', { form: { secret: other, code: totp(other) } });
      expect(replaced.status()).toBe(422);
      expect(await replaced.text()).toContain('already on');

      const two = await browser.newContext({ baseURL: base });
      const page = await two.newPage();
      await password(page);
      await page.locator('#code').fill('000000');
      await page.getByRole('button', { name: 'Continue' }).click();
      await expect(page.locator('#login-error')).toContainText('Wrong code');
      // The enrolment spent this step's code, so the app's next one (a step ahead is taken).
      await page.locator('#code').fill(totp(secret, 1));
      await page.getByRole('button', { name: 'Continue' }).click();
      await page.waitForURL((u) => u.pathname === '/');
      expect((await two.cookies()).some((c) => c.name === 'sid')).toBe(true);

      const three = await browser.newContext({ baseURL: base });
      const p3 = await three.newPage();
      await password(p3);
      await p3.locator('#code').fill(codes[0].toUpperCase()); // any case
      await p3.getByRole('button', { name: 'Continue' }).click();
      await p3.waitForURL((u) => u.pathname === '/');
      await p3.goto('/accounts/totp');
      await expect(p3.locator('.totp-state')).toContainText('9 of 10');

      const four = await browser.newContext({ baseURL: base });
      const p4 = await four.newPage();
      await password(p4);
      await p4.locator('#code').fill(codes[0]);
      await p4.getByRole('button', { name: 'Continue' }).click();
      await expect(p4.locator('#login-error')).toContainText('used already');
      await Promise.all([one.context.close(), two.close(), three.close(), four.close()]);
    });
  });

  test('a stale session steps up before new recovery codes, then is fresh', async ({ browser }) => {
    // 3 s: the steps between the step-up and Turn off must fit inside the window (a 1 s one didn't, on webkit).
    await own({ ACCOUNTS_STEP_UP_WINDOW: '3s' }, async (_, base) => {
      const { context, page } = await signIn(browser, base);
      await enrol(page);
      await page.goto('/accounts/totp');
      await page.waitForTimeout(4500); // the window counts whole seconds
      await page.getByRole('button', { name: 'New recovery codes' }).click();
      await page.waitForURL((u) => u.pathname === '/step-up');
      expect(new URL(page.url()).searchParams.get('next')).toBe('/accounts/totp'); // the page, not the POST
      await page.locator('#secret').fill('not-the-password');
      await page.getByRole('button', { name: 'Confirm' }).click();
      await expect(page.locator('#step-up-error')).toContainText("isn't your password");
      await page.locator('#secret').fill(ADMIN.password);
      await page.getByRole('button', { name: 'Confirm' }).click();
      await page.waitForURL((u) => u.pathname === '/accounts/totp');
      await page.getByRole('button', { name: 'New recovery codes' }).click();
      await expect(page.locator('.recovery-codes li')).toHaveCount(10);
      await page.goto('/accounts/totp');
      await page.getByRole('button', { name: 'Turn off' }).click(); // fresh: no step-up this time
      await expect(page.locator('.totp-secret')).toBeVisible();
      await context.close();
    });
  });

  // M4-12: with a key, secrets are sealed: a v2.3.0 database's plaintext one at boot, and a new
  // one as it is written; sealed ones and no key refuse to boot.
  test("a key seals the stored secrets, a plaintext database's at boot", async ({ browser }) => {
    test.setTimeout(90_000);
    const dir = mkdtempSync(path.join(tmpdir(), 'totp-key-'));
    const db = path.join(dir, 'h.db');
    const keyFile = path.join(dir, 'totp.key');
    writeFileSync(keyFile, 'a1'.repeat(32) + '\n');
    const stored = () => ['', '-wal'].map((x) => (existsSync(db + x) ? readFileSync(db + x).toString('latin1') : '')).join('');
    const run = async (env: NodeJS.ProcessEnv, body: (base: string) => Promise<void>) => {
      const s = await startServer(test.info().config, { DB_PATH: db, ...env });
      try { await body(mainOrigin(s.port)); } finally { await stopServer(s); }
    };
    try {
      let secret = '';
      await run({}, async (base) => { // no key: the v2.3.0 way
        const one = await signIn(browser, base);
        secret = (await enrol(one.page)).secret;
        await one.context.close();
      });
      expect(stored()).toContain(secret);
      await run({ ACCOUNTS_TOTP_KEY_FILE: keyFile }, async (base) => {
        const two = await browser.newContext({ baseURL: base });
        const page = await two.newPage();
        await password(page);
        await page.locator('#code').fill(totp(secret, 1)); // the enrolment spent this step's
        await page.getByRole('button', { name: 'Continue' }).click();
        await page.waitForURL((u) => u.pathname === '/');
        await two.close();
      });
      expect(stored()).not.toContain(secret); // sealed at that boot, and the page cache's copy is gone
      await expect(startServer(test.info().config, { DB_PATH: db })).rejects.toThrow(/sealed/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('an Admin without a second factor is a Member until it is on', async ({ browser }) => {
    await own({ ACCOUNTS_ADMIN_TOTP: 'required' }, async (_, base) => {
      const { context, page } = await signIn(browser, base);
      expect((await page.request.get('/admin/audit', { maxRedirects: 0 })).status()).toBe(403);
      await page.goto('/accounts/totp');
      await expect(page.locator('.totp-required')).toBeVisible();
      await enrol(page);
      expect((await page.request.get('/admin/audit', { maxRedirects: 0 })).status()).toBe(200);
      await context.close();
    });
  });
});
