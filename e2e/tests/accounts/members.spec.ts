import net from 'node:net';
import { test, expect } from '../../fixtures';
import { startServer, stopServer, type Server, mainOrigin } from '../../helpers/server';
import { ADMIN, signIn, totp } from '../../helpers/accounts';
import type { Browser, Page } from '@playwright/test';

// Becoming a member and the admin's side of it (PLAN §17.1, Q10): /register in each mode, an
// invite that gives its role and its uses, /admin/accounts with a reason for every change (the
// audit log has it), the last admin, a disable, an admin's reset code, the profile's name, and
// a hostile name shown as text everywhere. Each runs on a server of its own.
const T = { tag: ['@accounts-accounts', '@audit'] };

async function own(env: NodeJS.ProcessEnv, run: (s: Server, base: string) => Promise<void>) {
  const s = await startServer(test.info().config, env);
  try {
    await run(s, mainOrigin(s.port));
  } finally {
    await stopServer(s);
  }
}

// A member's row in /admin/accounts, by the exact username in its first cell.
const row = (page: Page, username: string) =>
  page.locator('.admin-user').filter({ has: page.getByRole('cell', { name: username, exact: true }) });

// Every hx-prompt on the page is answered with `reason`.
function answering(page: Page, reason: string) {
  page.on('dialog', (d) => d.accept(reason));
}

// An admin's new invite, from /admin/accounts: the link shown once.
async function invite(page: Page, role: string, uses = 1): Promise<string> {
  await page.goto('/admin/accounts');
  await page.locator('.admin-invite select[name="role"]').selectOption(role);
  await page.locator('.admin-invite input[name="uses"]').fill(String(uses));
  await page.getByRole('button', { name: 'Make an invite' }).click();
  return (await page.locator('.invite-link').textContent())!.trim();
}

// A new member's own browser, on the link's server (a context made in a test would take the
// worker's server as its base).
async function join(browser: Browser, link: string, username: string, display = '', password = 'a-long-enough-password') {
  const context = await browser.newContext({ baseURL: new URL(link).origin });
  const page = await context.newPage();
  await page.goto(link);
  await page.locator('#username').fill(username);
  if (display) await page.locator('#display').fill(display);
  await page.locator('#password').fill(password);
  await page.locator('#again').fill(password);
  await page.getByRole('button', { name: 'Join' }).click();
  return { context, page };
}

test.describe('members', T, () => {
  test('by invite: the link registers with its role, once; without one there is no way in', async ({ browser, request }) => {
    await own({ ACCOUNTS_REGISTRATION: 'invite' }, async (_, base) => { // the suite's servers keep it open
      const plain = await request.post(`${base}/register`, { form: { username: 'nobody', password: 'a-long-enough-password', again: 'a-long-enough-password' } });
      expect(plain.status()).toBe(422);
      expect(await plain.text()).toContain('invite');

      const admin = await signIn(browser, base, '/admin/accounts');
      answering(admin.page, 'a new moderator');
      const link = await invite(admin.page, 'Moderator');
      expect(link).toMatch(/\/register\?code=[a-z0-9-]{24}$/);

      const kim = await join(browser, link, 'kim', 'Kim Lee');
      await kim.page.waitForURL((u) => u.pathname === '/');
      await kim.page.goto('/login');
      await expect(kim.page.getByRole('heading', { name: 'Signed in as Kim Lee' })).toBeVisible();

      const again = await join(browser, link, 'lee');
      await expect(again.page.locator('#register-error')).toContainText('used, or expired');

      await admin.page.goto('/admin/accounts');
      await expect(row(admin.page, 'kim')).toContainText('Moderator');
      await admin.page.goto('/admin/audit?action=accounts.');
      await expect(admin.page.locator('.audit-row', { hasText: 'accounts.invite_created' })).toContainText('a new moderator');
      await expect(admin.page.locator('.audit-row', { hasText: 'accounts.register' })).toContainText('Kim Lee');

      const spare = await invite(admin.page, 'Member');
      await admin.page.goto('/admin/accounts');
      await admin.page.locator('.admin-invite-row').getByRole('button', { name: 'Withdraw' }).click();
      await expect(admin.page.locator('.admin-invite-row')).toHaveCount(0);
      const late = await join(browser, spare, 'pat');
      await expect(late.page.locator('#register-error')).toContainText('used, or expired');
      await late.context.close();
      await Promise.all([admin.context.close(), kim.context.close(), again.context.close()]);
    });
  });

  test('open and closed registration', async ({ browser, request }) => {
    await own({ ACCOUNTS_REGISTRATION: 'open' }, async (_, base) => {
      const robin = await join(browser, `${base}/register`, 'robin');
      await robin.page.waitForURL((u) => u.pathname === '/');
      const taken = await join(browser, `${base}/register`, 'ROBIN');
      await expect(taken.page.locator('#register-error')).toContainText('taken');
      const bot = await join(browser, `${base}/register`, 'Capcom');
      await expect(bot.page.locator('#register-error')).toContainText("the bot's");
      await bot.context.close();
      const bidi = await join(browser, `${base}/register`, 'sam', 'evil‮eman');
      await expect(bidi.page.locator('#register-error')).toContainText("can't show");
      const short = await request.post(`${base}/register`, { form: { username: 'al', password: 'a-long-enough-password', again: 'a-long-enough-password' } });
      expect(await short.text()).toContain('3 to 32');
      const differ = await request.post(`${base}/register`, { form: { username: 'alex2', password: 'a-long-enough-password', again: 'another-long-password' } });
      expect(await differ.text()).toContain('differ');
      await Promise.all([robin.context.close(), taken.context.close(), bidi.context.close()]);
    });
    await own({ ACCOUNTS_REGISTRATION: 'closed' }, async (_, base) => {
      expect(await (await request.get(`${base}/register`)).text()).toContain('Registration is closed');
      expect((await request.post(`${base}/register`, { form: { username: 'robin' } })).status()).toBe(403);
    });
  });

  // M4-04, the audit's own scenario: a role change whose client leaves as soon as the request is
  // written still has its entry, written in the change's own transaction.
  test('a role change whose client leaves at once is audited all the same', async ({ browser }) => {
    await own({ ACCOUNTS_REGISTRATION: 'open' }, async (s, base) => {
      const ana = await join(browser, `${base}/register`, 'ana', 'Ana');
      await ana.page.waitForURL((u) => u.pathname === '/');
      const admin = await signIn(browser, base, '/admin/accounts');
      const action = await row(admin.page, 'ana').locator('form.admin-role').getAttribute('hx-post');
      const sid = (await admin.context.cookies()).find((c) => c.name === 'sid')!.value;
      const body = 'role=Moderator';
      await new Promise<void>((done, fail) => {
        const sock = net.connect(s.port, '127.0.0.1', () => {
          sock.write(`POST ${action} HTTP/1.1\r\nHost: ${new URL(base).host}\r\nCookie: sid=${sid}\r\nHX-Request: true\r\n` +
            `HX-Prompt: left at once\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: ${body.length}\r\n\r\n${body}`,
            () => { sock.destroy(); done(); });
        });
        sock.on('error', fail);
      });
      await expect.poll(async () => {
        await admin.page.goto('/admin/audit?action=accounts.role');
        return admin.page.locator('.audit-row', { hasText: 'left at once' }).count();
      }, { timeout: 10_000 }).toBe(1);
      await admin.page.goto('/admin/accounts');
      await expect(row(admin.page, 'ana')).toContainText('Moderator');
      await Promise.all([ana.context.close(), admin.context.close()]);
    });
  });

  test('the last admin stays; a disabled member is out; a reset code works once', async ({ browser }) => {
    await own({ ACCOUNTS_REGISTRATION: 'open' }, async (_, base) => {
      const robin = await join(browser, `${base}/register`, 'robin', 'Robin');
      await robin.page.waitForURL((u) => u.pathname === '/');
      const admin = await signIn(browser, base, '/admin/accounts');
      answering(admin.page, 'checking the rules');

      const me = row(admin.page, ADMIN.username);
      await me.locator('select[name="role"]').selectOption('Member');
      await me.getByRole('button', { name: 'Set role' }).click();
      await expect(admin.page.locator('.toast')).toContainText('last admin');

      await row(admin.page, 'robin').getByRole('button', { name: 'Disable' }).click();
      await expect(row(admin.page, 'robin')).toContainText('disabled');
      await robin.page.goto('/accounts/profile');
      await expect(robin.page).toHaveURL(/\/login$/); // signed out by the disable

      await row(admin.page, 'robin').getByRole('button', { name: 'Enable' }).click();
      await expect(row(admin.page, 'robin')).toContainText('active');
      await row(admin.page, 'robin').getByRole('button', { name: 'Reset code' }).click();
      const code = (await admin.page.locator('.reset-code').textContent())!.trim();
      expect(code).toMatch(/^[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}$/);

      // M4-05: a wrong code for a member and the right code under a name with no account answer alike.
      const tryReset = (username: string, c: string) => robin.context.request.post(`${base}/reset`,
        { form: { username, code: c, password: 'a-brand-new-password', again: 'a-brand-new-password' } });
      for (const [who, c] of [['robin', 'aaaa-bbbb-cccc'], ['nobody-here', code]]) {
        const r = await tryReset(who, c);
        expect(r.status()).toBe(422);
        expect(await r.text()).toContain('match, or was used.');
      }

      const reset = async (c: string) => {
        await robin.page.goto('/reset');
        await robin.page.locator('#username').fill('robin');
        await robin.page.locator('#code').fill(c);
        await robin.page.locator('#password').fill('a-brand-new-password');
        await robin.page.locator('#again').fill('a-brand-new-password');
        await robin.page.getByRole('button', { name: 'Set the new password' }).click();
      };
      await reset(code.toUpperCase());
      await robin.page.waitForURL((u) => u.pathname === '/login');
      await robin.page.locator('#username').fill('robin');
      await robin.page.locator('#password').fill('a-brand-new-password');
      await robin.page.getByRole('button', { name: 'Sign in' }).click();
      await robin.page.waitForURL((u) => u.pathname === '/');
      await reset(code);
      await expect(robin.page.locator('#reset-error')).toContainText('was used');
      await Promise.all([admin.context.close(), robin.context.close()]);
    });
  });

  test("an admin turns off a member's lost two-step sign-in, and the password alone signs them in", async ({ browser }) => {
    await own({ ACCOUNTS_REGISTRATION: 'open' }, async (_, base) => {
      const robin = await join(browser, `${base}/register`, 'robin', 'Robin');
      await robin.page.waitForURL((u) => u.pathname === '/');
      await robin.page.goto('/accounts/totp');
      const secret = (await robin.page.locator('.totp-secret').textContent())!.trim();
      await robin.page.locator('#totp-code').fill(totp(secret));
      await robin.page.getByRole('button', { name: 'Turn on' }).click();
      await expect(robin.page.locator('.recovery-codes li')).toHaveCount(10);
      await robin.context.close();

      const admin = await signIn(browser, base, '/admin/accounts');
      answering(admin.page, 'lost their phone and their codes');
      await expect(row(admin.page, 'robin')).toContainText('on');
      await expect(row(admin.page, ADMIN.username).getByRole('button', { name: 'Two-step off' })).toHaveCount(0);
      await row(admin.page, 'robin').getByRole('button', { name: 'Two-step off' }).click();
      await expect(row(admin.page, 'robin').getByRole('button', { name: 'Two-step off' })).toHaveCount(0);
      await expect(row(admin.page, 'robin').locator('td').nth(4)).toHaveText('off');
      // Again, or for no one, it is refused rather than audited as done.
      const id = (await row(admin.page, 'robin').getAttribute('id'))!.replace('user-', '');
      const again = await admin.page.request.post(`/admin/accounts/${id}/two-step-off`, { headers: { 'HX-Request': 'true', 'HX-Prompt': 'twice' } });
      expect(again.status()).toBe(422);
      const nobody = await admin.page.request.post('/admin/accounts/99999/two-step-off', { headers: { 'HX-Request': 'true', 'HX-Prompt': 'no one' } });
      expect(nobody.status()).toBe(404);

      const back = await browser.newContext({ baseURL: base });
      const page = await back.newPage();
      await page.goto('/login');
      await page.locator('#username').fill('robin');
      await page.locator('#password').fill('a-long-enough-password');
      await page.getByRole('button', { name: 'Sign in' }).click();
      await page.waitForURL((u) => u.pathname === '/'); // no code step
      await admin.page.goto('/admin/audit?action=accounts.totp_off');
      await expect(admin.page.locator('.audit-row')).toContainText('lost their phone');
      await Promise.all([back.close(), admin.context.close()]);
    });
  });

  test('a name is changed on the profile, and a hostile one is only ever text', async ({ browser }) => {
    await own({ ACCOUNTS_REGISTRATION: 'open' }, async (_, base) => {
      const hostile = '<img src=x onerror=alert(1)>';
      const eve = await join(browser, `${base}/register`, 'eve', hostile);
      await eve.page.waitForURL((u) => u.pathname === '/');
      let alerted = false;
      const admin = await signIn(browser, base, '/admin/accounts');
      admin.page.on('dialog', (d) => { alerted = true; d.dismiss(); });
      await expect(row(admin.page, 'eve')).toContainText(hostile);
      await admin.page.goto('/admin/audit?action=accounts.register');
      await expect(admin.page.locator('.audit-row').first()).toContainText(hostile);
      expect(alerted).toBe(false);
      expect(await admin.page.locator('img[src="x"]').count()).toBe(0);

      await eve.page.goto('/accounts/profile');
      await eve.page.locator('#display').fill('  Eve   Adams ');
      await eve.page.getByRole('button', { name: 'Save' }).click();
      await expect(eve.page.locator('#profile-msg')).toContainText('Saved');
      await eve.page.goto('/login');
      await expect(eve.page.getByRole('heading', { name: 'Signed in as Eve Adams' })).toBeVisible();
      await Promise.all([admin.context.close(), eve.context.close()]);
    });
  });

  test('a member\'s theme is kept on the server: another device renders it over its own', async ({ browser, request }) => {
    await own({}, async (_, base) => {
      const guest = await browser.newContext({ baseURL: base });
      const g = await guest.newPage();
      await g.goto('/');
      await expect(g.locator('html')).toHaveAttribute('data-scheme', 'houston'); // Houston's own default
      expect(await g.locator('html').getAttribute('data-theme-href')).toBeNull();
      await guest.close();

      const one = await signIn(browser, base);
      await expect(one.page.locator('html')).toHaveAttribute('data-theme-href', '/accounts/theme');
      await one.page.locator('.picker summary').click();
      await one.page.locator('[data-pick-style="skeuo"]').click();
      const kept = one.page.waitForResponse((r) => r.url().endsWith('/accounts/theme'));
      await one.page.locator('[data-pick-scheme="brass"]').click();
      expect((await kept).status()).toBe(204);

      // A second device whose browser kept another theme: the server's wins, before paint.
      const two = await browser.newContext({ baseURL: base });
      await two.addInitScript(() => { localStorage.setItem('style', 'terminal'); localStorage.setItem('scheme', 'green'); });
      const p = await two.newPage();
      await p.goto(`/login?next=${encodeURIComponent('/about')}`);
      await expect(p.locator('html')).toHaveAttribute('data-style', 'terminal'); // a guest: the browser's
      await p.locator('#username').fill(ADMIN.username);
      await p.locator('#password').fill(ADMIN.password);
      await p.getByRole('button', { name: 'Sign in' }).click();
      await p.waitForURL((u) => u.pathname === '/about');
      await p.reload();
      await expect(p.locator('html')).toHaveAttribute('data-kept', '');
      await expect(p.locator('html')).toHaveAttribute('data-style', 'skeuo');
      await expect(p.locator('html')).toHaveAttribute('data-scheme', 'brass');

      // Only a style with one of its own schemes is kept, and only for a member.
      expect((await p.request.post('/accounts/theme', { form: { style: 'skeuo', scheme: 'midnight' } })).status()).toBe(422);
      const guestPost = await request.post(`${base}/accounts/theme`, { form: { style: 'skeuo', scheme: 'aqua' }, maxRedirects: 0 });
      expect(guestPost.headers()['location']).toContain('/login'); // a guest is sent to sign in
      await Promise.all([one.context.close(), two.close()]);
    });
  });
});
