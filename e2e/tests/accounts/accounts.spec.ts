import { test, expect } from '../../fixtures';
import { request as pwRequest } from '@playwright/test';
import { startServer, stopServer, type Server, mainOrigin } from '../../helpers/server';
import { ADMIN, signIn } from '../../helpers/accounts';

// The accounts identity (PLAN §17.1, §17.5): a username and a password at /login, a
// server-side session in the host-only `sid` cookie, the member's sessions with revoke,
// per-account backoff, the sign-in limits and the two lifetimes.
const T = { tag: ['@accounts-accounts'] };

// A server of the spec's own, for what would disturb the worker's (its limits, its clock).
async function own(env: NodeJS.ProcessEnv, run: (s: Server, base: string) => Promise<void>) {
  const s = await startServer(test.info().config, env);
  try {
    await run(s, mainOrigin(s.port));
  } finally {
    await stopServer(s);
  }
}

const form = (password = ADMIN.password) => ({ form: { username: ADMIN.username, password }, maxRedirects: 0 });

test.describe('accounts', T, () => {
  test('a member signs in and lands where they were going', async ({ browser, baseURL }) => {
    const { context, page } = await signIn(browser, baseURL!, '/accounts/sessions');
    await expect(page.getByRole('heading', { name: 'Your sessions' })).toBeVisible();
    await expect(page.locator('.session')).toHaveCount(1);
    await expect(page.locator('.session')).toContainText('this device');
    await page.goto('/login');
    await expect(page.getByRole('heading', { name: 'Signed in as admin' })).toBeVisible();
    await context.close();
  });

  test('the cookie is host-only, HttpOnly and Lax, and Secure only over https', async ({ request }) => {
    // Two cookies, one a line: the session's, and the device's (M4-03), which carries the same attributes.
    const lines = (await request.post('/login', form())).headers()['set-cookie'].split('\n');
    expect(lines.find((l) => l.startsWith('sid='))).toMatch(/^sid=[A-Za-z0-9_-]{43}; Path=\/; Max-Age=2592000; HttpOnly; SameSite=Lax$/);
    expect(lines.find((l) => l.startsWith('dev='))).toMatch(/^dev=\d+\.[0-9a-f]{16}\.[A-Za-z0-9_-]{22}; Max-Age=15552000; Path=\/; SameSite=Lax; HttpOnly$/);
    // Secure, it is __Host-sid, which a sibling host can't plant; a plain sid is then no one's (M4-08).
    await own({ COOKIE_SECURE: '1' }, async (_, base) => {
      const r = await request.post(`${base}/login`, form());
      const both = r.headers()['set-cookie'].split('\n');
      const secure = both.find((l) => l.startsWith('__Host-sid='))!;
      expect(secure).toMatch(/^__Host-sid=[A-Za-z0-9_-]{43}; Path=\/; .*; Secure$/);
      expect(both.find((l) => l.startsWith('__Host-dev='))).toMatch(/; Path=\/; .*Secure/);
      const token = secure.split(';')[0].split('=')[1];
      const as = async (cookie: string) => {
        const ctx = await pwRequest.newContext();
        try {
          return (await ctx.get(`${base}/accounts/sessions`, { headers: { cookie }, maxRedirects: 0 })).status();
        } finally {
          await ctx.dispose();
        }
      };
      expect(await as(`__Host-sid=${token}`)).toBe(200);
      expect(await as(`sid=${token}`)).toBe(302);
    });
  });

  test('a wrong password stays as typed, with the reason', async ({ page }) => {
    await page.goto('/login');
    await page.locator('#username').fill(ADMIN.username);
    await page.locator('#password').fill('not-the-password');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.locator('#login-error')).toContainText('Wrong username or password');
    await expect(page.locator('#username')).toHaveValue(ADMIN.username);
    await expect(page).toHaveURL(/\/login$/);
  });

  test('a guest is sent to sign in, and an htmx request is told to go there', async ({ request }) => {
    const page = await request.get('/accounts/sessions', { maxRedirects: 0 });
    expect(page.status()).toBe(302);
    expect(page.headers()['location']).toBe('/login');
    const hx = await request.post('/accounts/sessions/revoke', { headers: { 'HX-Request': 'true' }, form: { session: 'x' } });
    expect(hx.status()).toBe(401);
    expect(hx.headers()['hx-redirect']).toBe('/login');
  });

  test('revoking another session signs that device out; signing out ends this one', async ({ browser, baseURL }) => {
    const one = await signIn(browser, baseURL!, '/accounts/sessions');
    const two = await signIn(browser, baseURL!, '/accounts/sessions');
    await one.page.reload();
    // At least these two; behind a proxy the one server holds other specs' sessions of this admin too,
    // so every other one is revoked until this device's is the last.
    const others = one.page.locator('.session', { hasNotText: 'this device' });
    expect(await others.count()).toBeGreaterThanOrEqual(1);
    while ((await others.count()) > 0) {
      const n = await others.count();
      await others.first().getByRole('button', { name: 'Revoke' }).click();
      await expect(others).toHaveCount(n - 1);
    }
    await expect(one.page.locator('.session')).toHaveCount(1);

    await two.page.goto('/accounts/sessions');
    await expect(two.page).toHaveURL(/\/login$/);
    expect((await two.context.cookies()).filter((c) => c.name === 'sid')).toEqual([]); // the dead cookie is cleared

    await one.page.goto('/login');
    await one.page.getByRole('button', { name: 'Sign out' }).click();
    await one.page.waitForURL((u) => u.pathname === '/');
    expect((await one.context.cookies()).filter((c) => c.name === 'sid')).toEqual([]);
    await one.page.goto('/accounts/sessions');
    await expect(one.page).toHaveURL(/\/login$/);
    await one.context.close();
    await two.context.close();
  });

  test('a sign-in rotates the session the request carried', async ({ browser, baseURL }) => {
    const { context, page } = await signIn(browser, baseURL!);
    const [before] = (await context.cookies()).filter((c) => c.name === 'sid');
    const again = await context.request.post('/login', form());
    expect(again.status()).toBe(303);
    const [after] = (await context.cookies()).filter((c) => c.name === 'sid');
    expect(after.value).not.toBe(before.value);
    await page.goto('/accounts/sessions');
    await expect(page.locator('.session')).toHaveCount(1); // the old one closed, not left beside it
    await context.close();
  });

  test('wrong passwords back the account off, never lock it', async ({ request }) => {
    await own({}, async (_, base) => {
      for (let i = 0; i < 3; i++) expect((await request.post(`${base}/login`, form('wrong-wrong-wrong'))).status()).toBe(422);
      const shut = await request.post(`${base}/login`, form()); // even the right one waits
      expect(shut.status()).toBe(429);
      expect(Number(shut.headers()['retry-after'])).toBeGreaterThanOrEqual(1);
      await expect.poll(async () => (await request.post(`${base}/login`, form())).status(), { timeout: 5000 }).toBe(303);
    });
  });

  // M4-05: the fourth try's 429 says nothing about whether the name exists.
  test('a name with no account backs off the same way', async ({ request }) => {
    await own({}, async (_, base) => {
      const ghost = (password: string) => ({ form: { username: 'Nobody-Here', password }, maxRedirects: 0 });
      for (let i = 0; i < 3; i++) expect((await request.post(`${base}/login`, ghost('wrong-wrong-wrong'))).status()).toBe(422);
      const shut = await request.post(`${base}/login`, ghost('wrong-wrong-wrong'));
      expect(shut.status()).toBe(429);
      expect(await shut.text()).toContain('Too many wrong passwords');
      // Names compare without case, here as for accounts; a real account is untouched.
      expect((await request.post(`${base}/login`, { form: { username: 'nobody-here', password: 'x' }, maxRedirects: 0 })).status()).toBe(429);
      expect((await request.post(`${base}/login`, form())).status()).toBe(303);
    });
  });

  // M5-17: tries at once count as tries one after another, for an account and a name with no account alike.
  test('wrong passwords at once back off a name as they would one by one', async ({ request }) => {
    await own({}, async (_, base) => {
      for (const username of [ADMIN.username, 'nobody-here']) {
        const post = (password: string) => request.post(`${base}/login`, { form: { username, password }, maxRedirects: 0 });
        const four = await Promise.all([0, 1, 2, 3].map(() => post('wrong-wrong-wrong')));
        expect(four.every((r) => [422, 429].includes(r.status()))).toBe(true);
        expect((await post('wrong-wrong-wrong')).status(), username).toBe(429);
      }
    });
  });

  // M4-03 (b): a stranger holding an account's door shut doesn't shut it on a device that signed in before.
  test("a device that signed in before gets through a backoff a stranger holds", async ({ browser, playwright }) => {
    await own({}, async (_, base) => {
      const mine = await browser.newContext({ baseURL: base });
      expect((await mine.request.post('/login', form())).status()).toBe(303);
      expect((await mine.cookies()).some((c) => c.name === 'dev')).toBe(true);
      expect((await mine.request.post('/logout', { maxRedirects: 0 })).status()).toBe(303);
      const stranger = await playwright.request.newContext({ baseURL: base });
      for (let i = 0; i < 3; i++) expect((await stranger.post('/login', form('wrong-wrong-wrong'))).status()).toBe(422);
      expect((await stranger.post('/login', form())).status()).toBe(429);
      // A device cookie names one account: under another id it is no one's, and meets the account's door.
      const real = (await mine.cookies()).find((c) => c.name === 'dev')!;
      await mine.addCookies([{ ...real, value: real.value.replace(/^\d+/, '999') }]);
      expect((await mine.request.post('/login', form())).status()).toBe(429);
      await mine.addCookies([real]);
      expect((await mine.request.post('/login', form())).status()).toBe(303);
      await Promise.all([mine.close(), stranger.dispose()]);
    });
  });

  // M4-03 (a): one network's tries can't spend everyone's, and refusals before the argon pool spend nothing.
  test('sign-ins are limited per network, and the ceiling counts only password checks', async ({ request }) => {
    await own({ ACCOUNTS_LOGIN_PER_NET: '2' }, async (_, base) => {
      expect((await request.post(`${base}/login`, form())).status()).toBe(303);
      expect((await request.post(`${base}/login`, form())).status()).toBe(303);
      const third = await request.post(`${base}/login`, form());
      expect(third.status()).toBe(429);
      expect(await third.text()).toContain('from your network');
    });
    await own({ ACCOUNTS_LOGIN_OVERALL: '1' }, async (_, base) => {
      for (let i = 0; i < 3; i++) expect((await request.post(`${base}/login`, form(''))).status()).toBe(422); // no password: no check
      expect((await request.post(`${base}/login`, form())).status()).toBe(303);
      const next = await request.post(`${base}/login`, form());
      expect(next.status()).toBe(429);
      expect(await next.text()).toContain('right now');
    });
  });

  test('sign-ins from one client are limited', async ({ request }) => {
    await own({ ACCOUNTS_LOGIN_PER_CLIENT: '2' }, async (_, base) => {
      expect((await request.post(`${base}/login`, form())).status()).toBe(303);
      expect((await request.post(`${base}/login`, form('wrong-wrong-wrong'))).status()).toBe(422);
      const third = await request.post(`${base}/login`, form());
      expect(third.status()).toBe(429);
      expect(await third.text()).toContain('Too many sign-ins');
    });
  });

  test('a session ends when idle, and at its absolute end', async ({ playwright }) => {
    for (const env of [{ ACCOUNTS_SESSION_IDLE: '1s' }, { ACCOUNTS_SESSION_MAX: '1s' }] as NodeJS.ProcessEnv[]) {
      await own(env, async (_, base) => {
        const api = await playwright.request.newContext({ baseURL: base });
        expect((await api.post('/login', form())).status()).toBe(303);
        expect((await api.get('/accounts/sessions', { maxRedirects: 0 })).status()).toBe(200);
        await new Promise((r) => setTimeout(r, 1300));
        const late = await api.get('/accounts/sessions', { maxRedirects: 0 });
        expect(late.status()).toBe(302);
        // An idle session's cookie is still sent, and cleared; an expired one's Max-Age already dropped it.
        if (env.ACCOUNTS_SESSION_IDLE) expect(late.headers()['set-cookie']).toMatch(/^sid=; .*Max-Age=0/);
        await api.dispose();
      });
    }
  });
});
